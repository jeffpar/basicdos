;
; BASIC-DOS Utility Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	devapi.inc
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<sfb_from_sfh,sfb_write>,near
	EXTERNS	<itoa,sprintf,write_string>,near

	EXTERNS	<sfh_debug,key_boot>,byte
	EXTERNS	<scb_active>,word

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strlen (AL = 00h or 24h)
;
; Return the length of the REG_DS:REG_SI string in AX, using terminator AL.
;
; Modifies:
;	AX
;
DEFPROC	utl_strlen,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	call	strlen
	mov	[bp].REG_AX,ax		; update REG_AX
	ret
	DEFLBL	strlen,near		; for internal calls (no REG_FRAME)
	push	cx
	push	di
	push	es
	push	ds
	pop	es
	mov	di,si
	mov	cx,di
	not	cx			; CX = largest possible count
	repne	scasb
	je	sl8
	sub	ax,ax			; operation failed
	stc				; return carry set and zero length
	jmp	short sl9
sl8:	sub	di,si
	lea	ax,[di-1]		; don't count the terminator character
sl9:	pop	es
	pop	di
	pop	cx
	ret
ENDPROC	utl_strlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strstr (AL = 01h)
;
; Find string (CS:SI) in string (ES:DI)
;
; Inputs:
;	REG_CS:REG_SI = source string
;	REG_ES:REG_DI = target string
;
; Outputs:
;	On match, carry clear, and REG_DI is updated with position of match
;	Otherwise, carry set (no registers modified)
;
; Modifies:
;	AX, BX, CX, DS, ES
;
DEFPROC	utl_strstr,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ds,[bp].REG_ES
	ASSUME	DS:NOTHING
	xchg	si,di
	mov	al,0
	call	strlen
	xchg	dx,ax			; DX = length of target string
	xchg	si,di
	mov	es,[bp].REG_ES
	ASSUME	ES:NOTHING
	mov	ds,[bp].REG_CS
	mov	al,0
	call	strlen
	xchg	bx,ax			; BX = length of source string

	lodsb				; AX = first char of source
	test	al,al
	stc
	jz	ss9

	mov	cx,dx
ss1:	repne	scasb			; scan all remaining target chars
	stc
	jne	ss9
	clc				; clear the carry in case CX is zero
	push	cx			; (in that case, cmpsb won't clear it)
	mov	cx,bx
	dec	cx
	push	si
	push	di
	rep	cmpsb			; compare all remaining source chars
	pop	di
	pop	si
	pop	cx
	je	ss8			; match (and carry clear)
	mov	dx,cx
	jmp	ss1

ss8:	dec	di
	mov	[bp].REG_DI,di

ss9:	ret
ENDPROC	utl_strstr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strupr (AL = 03h)
;
; Make the string at REG_DS:SI with length CX upper-case; use length 0
; if null-terminated.
;
; Outputs:
;	None
;
; Modifies:
;	AX (but not REG_AX)
;
DEFPROC	utl_strupr,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	DEFLBL	strupr,near		; for internal calls (no REG_FRAME)
	push	si
su1:	mov	al,[si]
	test	al,al
	jz	su9
	cmp	al,'a'
	jb	su2
	cmp	al,'z'
	ja	su2
	sub	al,20h
	mov	[si],al
su2:	inc	si
	loop	su1
su9:	pop	si
	ret
ENDPROC	utl_strupr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_printf (AL = 04h)
;
; A CDECL-style calling convention is assumed, where all parameters EXCEPT
; for the format string are pushed from right to left, so that the first
; (left-most) parameter is the last one pushed.  The format string is stored
; in the CODE segment following the INT 21h, which we automatically skip, and
; the next instruction should be an "ADD SP,N*2", assuming N word parameters.
;
; Use the PRINTF macro to simplify calls to this function.
;
; Inputs:
;	format string follows the INT 21h
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	REG_AX = # of characters printed
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; See sprintf.asm for more information on the format string.
;
DEFPROC	utl_printf,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
	mov	bl,0
	DEFLBL	hprintf,near		; BL = SFH (or 0 for STDOUT)
	sti
	push	ss
	pop	es
	mov	cx,BUFLEN		; CX = length
	sub	sp,cx
	mov	di,sp			; ES:DI -> buffer on stack
	push	bx
	mov	bx,[bp].REG_IP
	mov	ds,[bp].REG_CS		; DS:BX -> format string
	call	sprintf
	mov	[bp].REG_AX,ax		; update REG_AX with count in AX
	add	[bp].REG_IP,bx		; update REG_IP with length in BX
	pop	bx
	mov	si,sp
	push	ss
	pop	ds			; DS:SI -> buffer on stack
	xchg	cx,ax			; CX = # of characters
	test	bl,bl			; SFH?
	jz	pf7			; no
	jl	pf8			; DEBUG output not enabled
	call	sfb_from_sfh		; BX -> SFB
	jc	pf7
	mov	al,IO_COOKED
	call	sfb_write
	jmp	short pf8
pf7:	call	write_string		; write string to STDOUT
pf8:	add	sp,BUFLEN		; carry should always be clear now
	ret
ENDPROC	utl_printf endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_dprintf (AL = 05h)
;
; This is used by DEBUG code (specifically, the DPRINTF macro) to print
; to a "debug" device defined by a DEBUG= line in CONFIG.SYS.  However, this
; code is always left in place, in case we end up with a mix of DEBUG and
; FINAL binaries.  Without this function, those calls would crash, due to
; how the format strings are stored after the INT 21h.
;
; Use the DPRINTF macro to simplify calls to this function.
;
; Inputs:
;	option code (following INT 21h)
;	format string (following the option code)
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	REG_AX = # of characters printed
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; See sprintf.asm for more information on the format string.
;
DEFPROC	utl_dprintf,DOS
	IFDEF	DEBUG
	lds	si,dword ptr [bp].REG_IP
	ASSUME	DS:NOTHING
	lodsb				; AL = option code
	mov	[bp].REG_IP,si
	sub	al,[key_boot].LOB	; does option code match boot key?
	jz	dp1			; yes
	cmp	al,20h			; maybe boot key is upper case letter?
	jne	dp8			; no
dp1:	push	ax
	mov	bl,[sfh_debug]
	call	hprintf
	pop	ax
	mov	[bp].REG_AL,al		; update caller's AL to trip DBGBRK
	ret
	ENDIF	; DEBUG

dp8:	mov	al,0			; AL = null terminator
	mov	[bp].REG_AL,al		; update caller's AL to skip DBGBRK
	call	strlen			; get length of string at CS:IP
	inc	ax			; count null terminator
	add	[bp].REG_IP,ax		; update REG_IP with length in AX
	ret
ENDPROC	utl_dprintf endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_sprintf (AL = 06h)
;
; A CDECL-style calling convention is assumed, where all parameters EXCEPT
; for the format string are pushed from right to left, so that the first
; (left-most) parameter is the last one pushed.  The next instruction should
; be an "ADD SP,N*2", assuming N word parameters.
;
; Inputs:
;	DS:BX -> format string
;	ES:DI -> output buffer
;	CX = length of buffer
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	REG_AX = # of characters generated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; See sprintf.asm for more information on the format string.
;
DEFPROC	utl_sprintf,DOS
	sti
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	mov	bx,[bp].REG_BX		; DS:BX -> format string
	call	sprintf
	mov	[bp].REG_AX,ax		; update REG_AX with count in AX
	add	[bp].REG_IP,bx		; update REG_IP with length in BX
	ret
ENDPROC	utl_sprintf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_itoa (AL = 07h)
;
; Convert the value DX:SI to a string representation at ES:DI, using base BL,
; flags BH (see itoa for PF definitions), minimum length CX (0 for no minimum).
;
; Returns:
;	ES:DI filled in
;	AL = # of digits
;
; Modifies:
;	AX, CX, DX, ES
;
DEFPROC	utl_itoa,DOS
	sti
	xchg	ax,si			; DX:AX is now the value
	mov	es,[bp].REG_ES		; ES:DI -> buffer
	ASSUME	ES:NOTHING
	call	itoa
	mov	[bp].REG_AX,ax		; update REG_AX
	ret
ENDPROC	utl_itoa

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atoi16 (AL = 08h)
;
; Convert string at DS:SI to number in AX using base BL, using validation
; values at ES:DI.  It will also advance SI past the first non-digit character
; to facilitate parsing of a series of delimited, validated numbers.
;
; For validation, ES:DI must point to a triplet of (def,min,max) 16-bit values
; and like SI, DI will be advanced, making it easy to parse a series of values,
; each with their own set of (def,min,max) values.
;
; For no validation (and to leave SI pointing to the first non-digit), set
; DI to -1.
;
; Returns:
;	AX = value, DS:SI -> next character (ie, AFTER first non-digit)
;	Carry set on a validation error (AX will be set to the default value)
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	utl_atoi16,DOS
	mov	cx,-1			; no specific length
	DEFLBL	utl_atoi,near
	mov	bl,[bp].REG_BL		; BL = base (eg, 10)
	DEFLBL	utl_atoi_base,near
	sti
	mov	bh,0
	mov	[bp].TMP_BX,bx		; TMP_BX equals 16-bit base
	mov	[bp].TMP_AL,bh		; TMP_AL is sign (0 for +, -1 for -)
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY

	mov	ah,-1			; cleared when digit found
	sub	bx,bx			; DX:BX = value
	sub	dx,dx			; (will be returned in DX:AX)

ai0:	jcxz	ai6
	lodsb				; skip any leading whitespace
	dec	cx
	cmp	al,CHR_SPACE
	je	ai0
	cmp	al,CHR_TAB
	je	ai0

	cmp	al,'-'			; minus sign?
	jne	ai1			; no
	cmp	byte ptr [bp].TMP_AL,0	; already negated?
	jl	ai6			; yes, not good
	dec	byte ptr [bp].TMP_AL	; make a note to negate later
	jmp	short ai4

ai1:	cmp	al,'a'			; remap lower-case
	jb	ai2			; to upper-case
	sub	al,20h
ai2:	cmp	al,'A'			; remap hex digits
	jb	ai3			; to characters above '9'
	cmp	al,'F'
	ja	ai6			; never a valid digit
	sub	al,'A'-'0'-10
ai3:	cmp	al,'0'			; convert ASCII digit to value
	jb	ai6
	sub	al,'0'
	cmp	al,[bp].TMP_BL		; outside the requested base?
	jae	ai6			; yes
	cbw				; clear AH (digit found)
;
; Multiply DX:BX by the base in TMP_BX before adding the digit value in AX.
;
	push	ax
	xchg	ax,bx
	mov	[bp].TMP_DX,dx
	mul	word ptr [bp].TMP_BX	; DX:AX = orig BX * BASE
	xchg	bx,ax			; DX:BX
	xchg	[bp].TMP_DX,dx
	xchg	ax,dx
	mul	word ptr [bp].TMP_BX	; DX:AX = orig DX * BASE
	add	ax,[bp].TMP_DX
	adc	dx,0			; DX:AX:BX = new result
	xchg	dx,ax			; AX:DX:BX = new result
	test	ax,ax
	jz	ai3a
	int	04h			; signal overflow
ai3a:	pop	ax			; DX:BX = DX:BX * TMP_BX

	add	bx,ax			; add the digit value in AX now
	adc	dx,0
	jno	ai4
;
; This COULD be an overflow situation UNLESS DX:BX is now 80000000h AND
; the result is going to be negated.  Unfortunately, any negation may happen
; later, so it's insufficient to test the sign in TMP_AL; we'll just have to
; allow it.
;
	test	bx,bx
	jz	ai4
	int	04h			; signal overflow

ai4:	jcxz	ai6
	lodsb				; fetch the next character
	dec	cx
	jmp	ai1			; and continue the evaluation

ai6:	cmp	byte ptr [bp].TMP_AL,0
	jge	ai6a
	neg	dx
	neg	bx
	sbb	dx,0
	into				; signal overflow if set

ai6a:	cmp	di,-1			; validation data provided?
	jg	ai6c			; yes
	je	ai6b			; -1 for 16-bit result only
	mov	[bp].REG_DX,dx		; -2 for 32-bit result (update REG_DX)
ai6b:	dec	si			; rewind SI to first non-digit
	add	ah,1			; (carry clear if one or more digits)
	jmp	short ai9

ai6c:	test	ah,ah			; any digits?
	jz	ai6d			; yes
	mov	bx,es:[di]		; no, get the default value
	stc
	jmp	short ai8
ai6d:	cmp	bx,es:[di+2]		; too small?
	jae	ai7			; no
	mov	bx,es:[di+2]		; yes (carry set)
	jmp	short ai8
ai7:	cmp	es:[di+4],bx		; too large?
	jae	ai8			; no
	mov	bx,es:[di+4]		; yes (carry set)
ai8:	lea	di,[di+6]		; advance DI in case there are more
	mov	[bp].REG_DI,di		; update REG_DI

ai9:	mov	[bp].REG_AX,bx		; update REG_AX
	mov	[bp].REG_SI,si		; update caller's SI, too
	ret
ENDPROC utl_atoi16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atoi32 (AL = 09h)
;
; Convert string at DS:SI (with length CX) to number in DX:AX using base BL.
;
; Note these differences from utl_atoi16:
;
;	1) Validation data is not supported (DI is preset to -2)
;	2) CX should contain the exact length (use -1 if unknown)
;	2) SI will point to the first unprocessed character, not PAST it
;
; Returns:
;	Carry clear if one or more digits, set otherwise
;	DX:AX = value, DS:SI -> first unprocessed character
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	utl_atoi32,DOS
	mov	di,-2			; no validation, 32-bit result
	jmp	utl_atoi
ENDPROC utl_atoi32

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atoi32d (AL = 0Ah)
;
; Convert decimal string at DS:SI to number in DX:AX.
;
; This is equivalent to calling utl_atoi32 with BL = 10 and CX = -1, with
; the advantage that the caller's BX and CX registers are ignored (ie, they
; can be used for other purposes).
;
DEFPROC	utl_atoi32d,DOS
	mov	bl,10			; always base 10
	mov	cx,-1			; no specific length
	mov	di,-2			; no validation
	jmp	utl_atoi_base		; utl_atoi returns a 32-bit value
ENDPROC utl_atoi32d

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; div_32_16
;
; Divide DX:AX by CX, returning quotient in DX:AX and remainder in BX.
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	div_32_16
	mov	bx,ax			; save low dividend in BX
	mov	ax,dx			; divide high dividend
	sub	dx,dx			; DX:AX = new dividend
	div	cx			; AX = high quotient
	xchg	ax,bx			; move to BX, restore low dividend
	div	cx			; AX = low quotient
	xchg	dx,bx			; DX:AX = new quotient, BX = remainder
	ret
ENDPROC	div_32_16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mul_32_16
;
; Multiply DX:AX by CX, returning result in DX:AX.
;
; Modifies:
;	AX, DX
;
DEFPROC	mul_32_16
	push	bx
	mov	bx,dx
	mul	cx			; DX:AX = orig AX * CX
	push	ax			;
	xchg	ax,bx			; AX = orig DX
	mov	bx,dx			; BX:[SP] = orig AX * CX
	mul	cx			; DX:AX = orig DX * CX
	add	ax,bx
	adc	dx,0
	xchg	dx,ax
	pop	ax			; DX:AX = new result
	pop	bx
	ret
ENDPROC	mul_32_16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_tokify (AL = 0Bh or 0Ch)
;
; DOS_UTL_TOKIFY1 (0Bh) performs GENERIC parsing, which means that only
; tokens separated by whitespace (or SWITCHAR) will be returned, and they
; will all be identified "generically" as CLS_STR.
;
; DOS_UTL_TOKIFY2 (0Ch) performs BASIC parsing, which returns all tokens,
; even whitespace sequences (CLS_WHITE).
;
; Inputs:
;	AL = 0Bh (TOKTYPE_GENERIC) or 0Ch (TOKTYPE_BASIC)
;	REG_CL = length of string
;	REG_DS:REG_SI -> string to "tokify"
;	REG_ES:REG_DI -> TOKBUF (filled in with token info)
;
; Outputs:
;	Carry clear if tokens found; AX = # tokens, TOKBUF updated
;	Carry set if no tokens found
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, TMP_AX, TMP_CX
;
DEFPROC	utl_tokify,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	bx,[scb_active]
	mov	bl,[bx].SCB_SWITCHAR
	mov	[bp].TMP_BL,bl		; TMP_BL = SWITCHAR
	mov	[bp].TMP_BH,al		; TMP_BH = TOKTYPE
	mov	ds,[bp].REG_DS		; DS:SI -> string
	ASSUME	DS:NOTHING
	mov	es,[bp].REG_ES		; ES:DI -> TOKBUF
	ASSUME	ES:NOTHING
	mov	ch,0
	mov	[bp].TMP_CX,cx		; TMP_CX = length

	sub	bx,bx			; BX = token index
	mov	ah,0			; AH = initial classification
	test	al,TOKTYPE_GENERIC
	mov	al,-1
	jz	tf0			; for generic parsing
	mov	al,NOT CLS_WHITE	; we're not interested in whitespace
tf0:	mov	[bp].TMP_AL,al
	jmp	tf8			; dive in
;
; Starting a new token.
;
tf1:	lea	dx,[si-1]		; DX = start of token
tf2:	lodsb
	mov	ch,ah
	dec	word ptr [bp].TMP_CX
	jge	tf3
	sub	ah,ah			; AH = 0 means we're done
	jmp	short tf6
tf3:	call	tok_classify		; AH = next classification
	test	ch,ch			; still priming the pump?
	jz	tf1			; yes
	cmp	ah,CLS_SYM		; symbol found?
	jne	tf5			; no
;
; Let's merge CLS_SYM with CLS_VAR to make life simpler downstream.
;
	cmp	ch,CLS_VAR
	jne	tf6
	cmp	al,'%'
	jne	tf3b
	mov	ah,CLS_VAR_LONG
	jmp	short tf3e
tf3b:	cmp	al,'$'
	jne	tf3c
	mov	ah,CLS_VAR_STR
	jmp	short tf3e
tf3c:	cmp	al,'!'
	jne	tf3d
	mov	ah,CLS_VAR_SINGLE
	jmp	short tf3e
tf3d:	cmp	al,'#'
	jne	tf6a
	mov	ah,CLS_VAR_DOUBLE
tf3e:	mov	ch,ah			; change previous classification, too

tf5:	cmp	ah,ch			; any change to classification?
	je	tf2			; no

tf6:	test	ch,[bp].TMP_AL		; any previous classification?
	jz	tf7			; no

tf6a:	mov	al,ch			; AL = previous classification
	lea	cx,[si-1]		; SI = end of token
	sub	cx,dx			; CX = length of token

	IFDEF	MAXDEBUG
	cmp	byte ptr [bp].TMP_AL,-1
	jne	tf6b
	push	ax
	mov	ah,0
	DPRINTF	't',<"token: '%.*ls' (%#04x)\r\n">,cx,dx,ds,ax
	pop	ax
tf6b:
	ENDIF	; MAXDEBUG
;
; Update the TOKLET in the TOK_DATA at ES:DI, token index BX
;
	push	bx
	add	bx,bx
	add	bx,bx			; BX = BX * 4 (size TOKLET)
	mov	es:[di+bx].TOK_DATA.TOKLET_CLS,al
	mov	es:[di+bx].TOK_DATA.TOKLET_LEN,cl
	mov	es:[di+bx].TOK_DATA.TOKLET_OFF,dx
	pop	bx
	inc	bx			; and increment token index

tf7:	test	ah,ah			; all done?
	jz	tf9			; yes

tf8:	cmp	bl,es:[di].TOK_MAX	; room for more tokens?
	jae	tf9			; no
	jmp	tf1			; yes

tf9:	mov	es:[di].TOK_CNT,bl	; update # tokens
	mov	[bp].REG_AX,bx		; return # tokens in AX, too
	cmp	bx,1			; set carry if no tokens
	ret
ENDPROC	utl_tokify

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tok_classify
;
; Inputs:
;	AL = character
;	AH = classification of previous character(s)
;
; Outputs:
;	AH = new classification, 0 if none (end of input)
;
; Modifies:
;	AX
;
DEFPROC	tok_classify
;
; Check for quotations first.
;
tc1:	cmp	al,CHR_DQUOTE		; double quotes?
	jne	tc1b			; no
	cmp	ah,CLS_DQUOTE		; already inside double quotes?
	mov	ah,CLS_DQUOTE
	jne	tc1a			; no (but we are now)
	mov	ah,CLS_STR		; convert classification to CLS_STR
	mov	ch,ah			; and change previous class to match
tc1a:	ret

tc1b:	cmp	ah,CLS_DQUOTE		; are we inside double quotes?
	jne	tc2			; no
	ret				; yes, so leave classification alone
;
; Take care of whitespace next.
;
tc2:	cmp	al,CHR_SPACE
	je	tc2a
	cmp	al,CHR_TAB
	jne	tc3
tc2a:	mov	ah,CLS_WHITE
	ret
;
; For generic parsing, everything is either whitespace or a string.
;
tc3:	test	byte ptr [bp].TMP_BH,TOKTYPE_GENERIC
	jz	tc4
	cmp	al,'|'			; pipe char?
	je	tc3b			; yes
	cmp	al,'<'			; input redirection char?
	je	tc3b			; yes
	cmp	al,'>'			; output redirection char?
	je	tc3b			; yes
	cmp	al,[bp].TMP_BL		; SWITCHAR?
	jne	tc3c			; no
	cmp	ah,CLS_WHITE		; any intervening whitespace?
	je	tc3c			; yes
tc3b:	mov	ah,CLS_SYM		; no, force a transition
	ret
tc3c:	cmp	ch,CLS_SYM		; did we force a transition?
	jne	tc3d			; no
	mov	ch,CLS_STR		; yes, revert to string
tc3d:	mov	ah,CLS_STR		; and call anything else a string
	ret
;
; Check for digits next.
;
tc4:	cmp	al,'0'
	jb	tc5
	cmp	al,'9'
	ja	tc5
;
; Digits can start CLS_DEC, or continue CLS_OCT, CLS_HEX, CLS_DEC, or CLS_VAR.
; Technically, they can only continue CLS_OCT if < '8', but we'll worry about
; that later, during evaluation.
;
	test	ah,CLS_OCT OR CLS_HEX OR CLS_DEC OR CLS_VAR
	jnz	tc4a
	mov	ah,CLS_DEC		; must be decimal
tc4a:	cmp	ah,CLS_OCT OR CLS_HEX
	jne	tc4b
	and	ah,CLS_OCT
	mov	ch,ah			; change previous class as well
tc4b:	ret				; to avoid unnecesary token transition
;
; Check for letters next.
;
tc5:	cmp	al,'a'
	jb	cl5a			; may be a letter, but not lowercase
	cmp	al,'z'
	ja	cl6			; not a letter
	sub	al,'a'-'A'
cl5a:	cmp	al,'A'
	jb	cl6			; not a letter
	cmp	al,'Z'
	ja	cl6			; not a letter
;
; If we're on the heels of an ampersand, check for letters that determine
; the base of the number ('H' for hex, 'O' for octal).
;
	cmp	ah,CLS_OCT OR CLS_HEX	; did we see an ampersand previously?
	jne	cl5d			; no
	cmp	al,'H'
	jne	cl5c
	and	ah,CLS_HEX
cl5b:	mov	ch,ah			; change previous class as well
	ret				; to avoid unnecesary token transition
cl5c:	cmp	al,'O'
	jne	cl5d
	and	ah,CLS_OCT
	jmp	short cl5b
;
; Letters can start or continue CLS_VAR, or continue CLS_HEX if < 'G'; however,
; as with octal numbers, we'll worry about the validity of a hex number later,
; during evaluation.
;
cl5d:	test	ah,CLS_HEX OR CLS_VAR
	jnz	cl5e
	mov	ah,CLS_VAR		; must be a variable
cl5e:	ret
;
; Periods can be a decimal point, so it can start or continue CLS_DEC,
; or continue CLS_VAR.
;
cl6:	cmp	al,'.'
	jne	cl7
	test	ah,CLS_VAR
	jnz	cl6a
	mov	ah,CLS_DEC
cl6a:	ret
;
; Ampersands are leading characters for hex and octal values.
;
cl7:	cmp	al,'&'			; leading char for hex or octal?
	jne	cl8			; no
	mov	ah,CLS_OCT OR CLS_HEX
	ret
;
; Everything else is just a symbol at this point.
;
cl8:	mov	ah,CLS_SYM
	ret
ENDPROC	tok_classify

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_tokid (AL = 0Dh)
;
; The main advantage of this function is that, by requiring the TOKTBL
; to be sorted, it can use a binary search to find the token faster.  For
; small token tables, that's probably insigificant, but for larger tables
; (eg, BASIC keywords), the difference will presumably add up.
;
; Inputs:
;	REG_CX = token length
;	REG_DS:REG_SI -> token
;	REG_CS:REG_DX -> TOKTBL followed by sorted array of TOKDEFs
;
; Outputs:
;	If carry clear, REG_AX = ID (TOKDEF_ID), REG_SI = offset of TOKDEF
;	If carry set, token not found
;
; Modifies:
;	AX
;
DEFPROC	utl_tokid,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ds,[bp].REG_DS		; DS:SI -> token (length CX)
	mov	di,dx
	mov	es,[bp].REG_CS		; ES:DI -> TOKTBL (from CS:DX)
	ASSUME	DS:NOTHING, ES:NOTHING

	mov	byte ptr [bp].TMP_BL,0	; TMP_BL = top index
	mov	dx,es:[di]		; DL = # TOKDEFs
					; DH = size of TOKDEF
	add	di,2			; ES:DI -> 1st TOKDEF

td0:	mov	ax,-1
	cmp	[bp].TMP_BL,dl		; top index = bottom index?
	stc
	je	td10			; yes, no match
	mov	bl,dl
	mov	bh,0
	add	bl,[bp].TMP_BL
	shr	bx,1			; BL = index of midpoint

	push	bx
	mov	al,dh			; AL = size TOKDEF
	mul	bl			; BL = index of TOKDEF
	xchg	bx,ax			; BX = offset of TOKDEF
	mov	ch,es:[di+bx].TOKDEF_LEN; CH = length of current token
	mov	ah,cl			; CL is saved in AH
	push	si
	push	di
	mov	di,es:[di+bx].TOKDEF_OFF; ES:DI -> current token
td1:	lodsb
	cmp	al,'a'
	jb	td2
	cmp	al,'z'
	ja	td2
	sub	al,20h
td2:	scasb				; compare input to current
	jne	td3
	sub	cx,0101h
	jz	td3			; match!
	test	cl,cl
	stc
	jz	td3			; if CL exhausted, input < current
	test	ch,ch
	jz	td3			; if CH exhausted, input > current
	jmp	td1

td3:	pop	di
	pop	si
	jcxz	td8
;
; If carry is set, set the bottom range to BX, otherwise set the top range
;
	pop	bx			; BL = index of token we just tested
	mov	cl,ah			; restore CL from AH
	jnc	td4
	mov	dl,bl			; new bottom is middle
	jmp	td0
td4:	inc	bx
	mov	[bp].TMP_BL,bl		; new top is middle + 1
	jmp	td0

td8:	sub	ax,ax			; zero AX (and carry, too)
	mov	al,es:[di+bx].TOKDEF_ID	; AX = token ID
	lea	dx,[di+bx]		; DX -> TOKDEF
	pop	bx			; toss BX from stack

td9:	jc	td10
	mov	[bp].REG_SI,dx
	mov	[bp].REG_AX,ax
td10:	ret
ENDPROC	utl_tokid

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_restart (AL = 0Eh)
;
; TODO: Ensure any disk modifications (once we support disk modifications)
; have been written.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	utl_restart,DOS
	cli
	db	OP_JMPF
	dw	00000h,0FFFFh
ENDPROC	utl_restart

DOS	ends

	end
