;
; BASIC-DOS Utility Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc
	include	parser.inc

DOS	segment word public 'CODE'

	EXTNEAR	<sfb_from_sfh,sfb_write>
	EXTNEAR	<atoi,atoi_len,atoi_base,atof64>
	EXTNEAR	<itoa,sprintf,write_string>

	EXTBYTE	<sfh_debug,key_boot>
	EXTWORD	<scb_active>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strlen (AH = 00h or 24h)
;
; Return the length of the REG_DS:REG_SI string in AX, using terminator AH.
;
; Modifies:
;	AX
;
DEFPROC	utl_strlen,DOS
	sti
	mov	al,ah			; AL = terminator
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
; utl_strstr (AH = 01h)
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
; utl_strupr (AH = 03h)
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
; utl_printf (AH = 04h)
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
ENDPROC	utl_printf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_dprintf (AH = 05h)
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
ENDPROC	utl_dprintf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_sprintf (AH = 06h)
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
; utl_itoa (AH = 07h)
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
; utl_atoi16 (AH = 08h)
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
	sti
	jmp	atoi
ENDPROC utl_atoi16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atoi32 (AH = 09h)
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
	sti
	mov	di,-2			; no validation, 32-bit result
	jmp	atoi_len
ENDPROC utl_atoi32

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atoi32d (AH = 0Ah)
;
; Convert decimal string at DS:SI to number in DX:AX.
;
; This is equivalent to calling utl_atoi32 with BL = 10 and CX = -1, with
; the advantage that the caller's BX and CX registers are ignored (ie, they
; can be used for other purposes).
;
DEFPROC	utl_atoi32d,DOS
	sti
	mov	bl,10			; always base 10
	mov	cx,-1			; no specific length
	mov	di,-2			; no validation
	jmp	atoi_base		; atoi returns a 32-bit value
ENDPROC utl_atoi32d

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atof64 (AH = 0Ch)
;
; Inputs:
;	REG_DS:REG_SI -> string
;
; Outputs:
;	REG_ES:REG_DI -> result (in FAC)
;
; Modifies:
;
DEFPROC	utl_atof64,DOS
	sti
	jmp	atof64
ENDPROC utl_atof64

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_i32f64 (AH = 0Dh)
;
; Inputs:
;	REG_DX:REG_SI = 32-bit value
;
; Outputs:
;	REG_ES:REG_DI -> result (in FAC)
;
; Modifies:
;
DEFPROC	utl_i32f64,DOS
	ret
ENDPROC utl_i32f64

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_opf64 (AH = 0Eh)
;
; Inputs:
;	REG_AL = operation (see OPF64_*)
;
; Outputs:
;
; Modifies:
;
DEFPROC	utl_opf64,DOS
	ret
ENDPROC utl_opf64

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_tokify (AH = 11h or 12h)
;
; DOS_UTL_TOKEN1 (11h) performs generic parsing, which means that only
; tokens separated by whitespace (or SWITCHAR) will be returned, and they
; will all be identified "generically" as CLS_STR.
;
; DOS_UTL_TOKEN2 (12h) performs BASIC parsing, which returns all tokens,
; even whitespace sequences (CLS_WHITE).
;
; Inputs:
;	AH = 11h (TOKTYPE_GENERIC) or 12h (TOKTYPE_BASIC)
;	REG_CL = length of string
;	REG_DS:REG_SI -> string to "tokify"
;	REG_ES:REG_DI -> TOKBUF (to be filled with token info)
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
	mov	al,ah
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
	cbw				; AH = initial classification (0)
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

	cmp	al,CLS_FLOAT OR CLS_SYM	; if an incomplete float is detected
	jne	tf6b			; convert it to CLS_FLOAT
	mov	al,CLS_FLOAT

tf6b:	IFDEF	DEBUG
	cmp	byte ptr [bp].TMP_AL,-1
	jne	tf6c
	push	ax
	mov	ah,0
	DPRINTF	't',<"token: '%.*ls' (%#04x)\r\n">,cx,dx,ds,ax
	pop	ax
tf6c:	ENDIF	; DEBUG
;
; Update the TOKLET in the TOK_DATA at ES:DI, token index BX.
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
	mov	ah,CLS_VAR		; no, force a transition
	ret
tc3b:	mov	ah,CLS_SYM
	ret
tc3c:	cmp	ch,CLS_VAR		; did we force a transition?
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
	jmp	short tc7a		; change previous class and exit
tc4b:	cmp	ah,CLS_FLOAT OR CLS_SYM
	jne	tc6a
	mov	ah,CLS_FLOAT
	jmp	short tc7a		; change previous class and exit
;
; Check for letters next.
;
tc5:	cmp	al,'a'
	jb	tc5a			; may be a letter, but not lowercase
	cmp	al,'z'
	ja	tc7			; not a letter
	sub	al,'a'-'A'
tc5a:	cmp	al,'A'
	jb	tc7			; not a letter
	cmp	al,'Z'
	ja	tc7			; not a letter
;
; If we're on the heels of a decimal number (either integer or float),
; then an 'E' is allowed to indicate an exponent (which makes it definitively
; float).  'D' is also allowed to indicate the exponent of a double-precision
; value, but it makes no difference to us, since ALL our floats are doubles.
;
	cmp	al,'D'			; the letter 'D'?
	je	tc5b			; yes
	cmp	al,'E'			; the letter 'E'?
	jne	tc5c			; no
tc5b:	test	ah,CLS_DEC		; preceded by some decimal value?
	jz	tc5c			; no
	mov	ah,CLS_FLOAT OR CLS_SYM	; definitively float now
	jmp	short tc7a		; change previous class and exit
;
; If we're on the heels of an ampersand, check for letters that determine
; the base of the number ('H' for hex, 'O' for octal).
;
tc5c:	cmp	ah,CLS_OCT OR CLS_HEX	; did we see an ampersand previously?
	jne	tc6			; no
	cmp	al,'H'
	jne	tc5d
	and	ah,CLS_HEX
	jmp	short tc7a		; change previous class and exit

tc5d:	cmp	al,'O'
	jne	tc6
	and	ah,CLS_OCT
	jmp	short tc7a		; change previous class and exit
;
; Letters can start or continue CLS_VAR, or continue CLS_HEX if <= 'F';
; however, as with octal numbers, we'll worry about the validity of a hex
; number later, during evaluation.
;
tc6:	test	ah,CLS_HEX OR CLS_VAR
	jnz	tc6a
	mov	ah,CLS_VAR		; must be a variable
tc6a:	ret
;
; Periods can be a decimal point, so it can start or continue CLS_DEC,
; or continue CLS_VAR.
;
tc7:	cmp	al,'.'
	jne	tc7c
	test	ah,CLS_VAR
	jnz	tc7b
	mov	ah,CLS_FLOAT		; update current class
tc7a:	mov	ch,ah			; change previous class, too
tc7b:	ret
;
; Similarly, '+' and '-' can be embedded in the exponent of a float, but ONLY
; if they immediately follow an exponent symbol ('E' or 'D').
;
tc7c:	cmp	al,'+'
	je	tc7d
	cmp	al,'-'
	jne	tc8
tc7d:	cmp	ah,CLS_FLOAT OR CLS_SYM
	jne	tc8
	mov	ah,CLS_FLOAT
	jmp	tc7a
;
; Ampersands are leading characters for hex and octal values.
;
tc8:	cmp	al,'&'			; leading char for hex or octal?
	jne	tc9			; no
	mov	ah,CLS_OCT OR CLS_HEX
	ret
;
; Everything else is just a symbol at this point.
;
tc9:	mov	ah,CLS_SYM
	ret
ENDPROC	tok_classify

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_tokid (AH = 13h)
;
; The main advantage of this function is that, by requiring the TOKTBL
; to be sorted, it can use a binary search to find the token faster.  For
; small token tables, that's probably insignificant, but for larger tables
; (eg, BASIC keywords), the difference will presumably add up.
;
; Inputs:
;	REG_CX = token length
;	REG_DS:REG_SI -> token
;	REG_CS:REG_DX -> TOKTBL followed by sorted array of TOKDEFs
;
; Outputs:
;	If carry clear, REG_AX = ID (TOKDEF_ID), REG_SI = offset of TOKDEF
;	If carry set, token not found, REG_AX = 0
;
; Modifies:
;	AX, BX, CX, DX, DI, DS, ES
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
	je	td9			; yes, no match
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

td9:	jnc	td9a
	mov	ax,0
	jmp	short td9b

td9a:	mov	[bp].REG_SI,dx
td9b:	mov	[bp].REG_AX,ax

	ret
ENDPROC	utl_tokid

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_parsesw (AH = 14h)
;
; Switch tokens start with the system's SWITCHAR and may contain 1 or more
; alphanumeric characters, each of which is converted to a bit in either
; PSP_DIGITS or PSP_LETTERS.
;
; Actually, alphanumeric is not entirely true anymore: in PSP_DIGITS, we now
; capture anything from '0' to '?'.
;
; Inputs:
;	REG_DL = 1st token to parse
;	REG_DH = # non-switch tokens to ignore (0 to ignore none)
;	REG_ES:REG_DI -> TOKBUF (filled with token info)
;
; Outputs:
;	PSP_DIGITS, PSP_LETTERS updated
;	REG_DL set to first non-switch token
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS
;
DEFPROC	utl_parsesw,DOS
	sti
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	mov	ch,[bx].SCB_SWITCHAR	; CH = SWITCHAR
	mov	es,[bx].SCB_PSP
	ASSUME	ES:NOTHING
	sub	ax,ax
	push	di
	mov	di,PSP_DIGITS
	stosw				; zero PSP_DIGITS
	stosw				; zero PSP_LETTERS.LOW
	stosw				; zero PSP_LETTERS.HIW
	xchg	bx,ax			; BX = 0
	mov	dx,[bp].REG_DX		; DL = token index
	mov	bl,dl			; BX = token index
	mov	ds,[bp].REG_ES
	pop	di			; DS:DI -> TOKBUF
	ASSUME	DS:NOTHING
pw1:	cmp	bl,[di].TOK_CNT
	jae	pw9
	push	bx
	add	bx,bx
	add	bx,bx			; BX = BX * 4 (size TOKLET)
	ASSERT	<size TOKLET>,EQ,4
	mov	si,[di].TOK_DATA[bx].TOKLET_OFF
	pop	bx
	lodsb
	push	di
	cmp	al,ch			; starts with SWITCHAR?
	jne	pw7			; no
pw2:	lodsb				; consume option chars
	cmp	al,'a'			; until we reach non-alphanumeric char
	jb	pw3
	sub	al,20h
pw3:	sub	al,'0'
	jb	pw8			; not alphanumeric
	cmp	al,16
	jae	pw5
	mov	di,PSP_DIGITS
pw4:	mov	cl,al
	mov	ax,1
	shl	ax,cl
	or	es:[di],ax		; set bit in word at ES:DI
	jmp	pw2			; go back for more option chars
pw5:	sub	al,'A'-'0'
	jb	pw8			; not alphanumeric
	cmp	al,16			; in the range of the first 16?
	jae	pw6			; no
	mov	di,PSP_LETTERS
	jmp	pw4
pw6:	sub	al,16
	cmp	al,10			; in the range of the next 10?
	jae	pw8			; no
	mov	di,PSP_LETTERS+2
	jmp	pw4
pw7:	test	dl,dl			; already find a non-switch token?
	js	pw8			; yes
	mov	dl,bl			; no, so remember this one
	or	dl,80h			; mark it
pw8:	pop	di
	dec	dh			; have we reached the limit?
	jz	pw9			; yes
	inc	bx			; advance token index
	jmp	pw1			; keep looping
pw9:	test	dl,dl			; already find a non-switch token?
	js	pw10			; yes
	mov	dl,bl			; no, so remember this one
pw10:	and	dl,7Fh			; unmark it (and clear carry)
	mov	[bp].REG_DL,dl		; return first non-switch token
	ret
ENDPROC	utl_parsesw

DOS	ends

	end
