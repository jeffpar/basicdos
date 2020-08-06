;
; BASIC-DOS Utility Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<get_sfh_sfb,sfb_write>,near
	EXTERNS	<chk_devname,dev_request,write_string>,near
	EXTERNS	<scb_load,scb_start,scb_stop,scb_unload>,near
	EXTERNS	<scb_yield,scb_delock,scb_wait,scb_endwait>,near
	EXTERNS	<mem_query>,near
	EXTERNS	<psp_term_exitcode>,near
	EXTERNS	<itoa,sprintf>,near

	EXTERNS	<scb_locked,sfh_debug>,byte
	EXTERNS	<scb_active>,word
	EXTERNS	<scb_table,clk_ptr>,dword

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strlen (AX = 1800h or 1824h)
;
; Returns the length of the REG_DS:SI string in AX, using the terminator in AL.
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
; utl_strstr (AX = 1801h)
;
; Find string (DS:SI) in string (ES:DI)
;
; Inputs:
;	REG_DS:REG_SI = source string
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
	mov	ds,[bp].REG_DS
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
; utl_strupr (AX = 1803h)
;
; Makes the string at REG_DS:SI with length CX upper-case; use length 0
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
; utl_printf (AX = 1804h)
;
; A semi-CDECL-style calling convention is assumed, where all parameters
; EXCEPT for the format string are pushed from right to left, so that the
; first (left-most) parameter is the last one pushed.  The format string
; is stored in the CODE segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; See utl_sprintf for more details.
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
DEFPROC	utl_printf,DOS
	mov	bl,0
	DEFLBL	hprintf,near		; BL = SFH (or 0 for STDOUT)
	sti
	push	ss
	pop	es
	ASSUME	ES:NOTHING
	mov	cx,BUFLEN		; CX = length
	sub	sp,cx
	mov	di,sp			; ES:DI -> buffer on stack
	push	bx
	mov	bx,[bp].REG_IP
	mov	ds,[bp].REG_CS		; DS:BX -> format string
	ASSUME	DS:NOTHING
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
	call	get_sfh_sfb		; BX -> SFB
	jc	pf7
	mov	al,IO_COOKED
	call	sfb_write
	jmp	short pf8
pf7:	call	write_string		; write string to STDOUT
pf8:	add	sp,BUFLEN
	ret
ENDPROC	utl_printf endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_dprintf (AX = 1805h)
;
; This is used by DEBUG code (in particular, the DPRINTF macro) to print
; to a "debug" device defined by a DEBUG= line in CONFIG.SYS.  However, this
; code is always left in place, in case we end up with a mix of DEBUG and
; NODEBUG binaries.  Without this function, those calls would crash, due to
; how the format strings are stored after the INT 21h.
;
; Except for the output device, this function is identical to utl_printf.
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
DEFPROC	utl_dprintf,DOS
	mov	bl,[sfh_debug]
	jmp	hprintf
ENDPROC	utl_dprintf endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_sprintf (AX = 1806h)
;
; A semi-CDECL-style calling convention is assumed, where all parameters
; EXCEPT for the format string are pushed from right to left, so that the
; first (left-most) parameter is the last one pushed.  The format string
; is stored in the CODE segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; When printing 32-bit values, list the low word first, then the high word,
; so that the high word is pushed first.
;
; Inputs:
;	DS:BX -> format string
;	ES:DI -> output buffer
;	CX = length of buffer
;	format string follows the INT 21h
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	REG_AX = # of characters generated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; See sprintf.asm for a list of supported format specifiers.
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
; utl_atoi16 (AX = 1807h)
;
; Convert string at DS:SI to number in AX using base BL, using validation
; values at ES:DI.
;
; ES:DI must point to a triplet of (def,min,max) 16-bit values; and like SI,
; DI will be advanced, making it easy to parse a series of values, each with
; their own set of (def,min,max) values.
;
; Returns:
;	AX = value, DS:SI -> next character (after any non-digit)
;	Carry will be set on a validation error, but AX will ALWAYS be valid
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	utl_atoi16,DOS
	sti
	mov	bl,[bp].REG_BL		; BL = base (eg, 10)
	mov	bh,0
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY

	mov	ah,-1			; cleared when digit found
	sub	cx,cx			; CX:DX = value
	sub	dx,dx			; (will be returned in DX:AX)
	push	bp
	sub	bp,bp			; BP will be negative if # is negative

ai0:	lodsb				; skip any leading whitespace
	cmp	al,CHR_SPACE
	je	ai0
	cmp	al,CHR_TAB
	je	ai0

	cmp	al,'-'			; minus sign?
	jne	ai1			; no
	test	bp,bp			; already negated?
	jl	ai6			; yes, not good
	dec	bp			; make a note to negate later
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
	jb	ai5
	sub	al,'0'
	cmp	al,bl			; outside the requested base?
	jae	ai6			; yes
	cbw				; clear AH (digit found)
;
; Multiply CX:DX by the base in BX before adding the digit value in AX.
;
	push	ax
	push	di
	mov	ax,dx
	mul	bx
	xchg	ax,cx
	mov	di,dx
	mul	bx
	add	ax,di
	adc	dx,0			; DX:AX:CX contains the result
	xchg	ax,cx			; DX:CX:AX now
	xchg	ax,dx			; AX:CX:DX now
	pop	di
	pop	ax			; CX:DX = CX:DX * BX

	add	dx,ax			; add the digit value in AX now
	adc	cx,0
ai4:	lodsb				; fetch the next character
	jmp	ai1			; and continue the evaluation

ai5:	test	al,al			; normally we skip the first non-digit
	jnz	ai6			; but if it's a null
	dec	si			; rewind

ai6:	test	bp,bp
	jge	ai6a
	neg	cx
	neg	dx
	sbb	cx,0
ai6a:	pop	bp

	cmp	di,-1			; validation data provided?
	jne	ai6b			; yes
	add	ah,1			; (carry clear if one or more digits)
	jmp	short ai9
ai6b:	test	ah,ah			; any digits?
	jz	ai6c			; yes
	mov	dx,es:[di]		; no, get the default value
	stc
	jmp	short ai8
ai6c:	cmp	dx,es:[di+2]		; too small?
	jae	ai7			; no
	mov	dx,es:[di+2]		; yes (carry set)
	jmp	short ai8
ai7:	cmp	es:[di+4],dx		; too large?
	jae	ai8			; no
	mov	dx,es:[di+4]		; yes (carry set)
ai8:	lea	di,[di+6]		; advance DI in case there are more
	mov	[bp].REG_DI,di		; update REG_DI
	jmp	short ai9a

ai9:	mov	[bp].REG_DX,cx		; update REG_DX if no validation data
ai9a:	mov	[bp].REG_AX,dx		; update REG_AX
	mov	[bp].REG_SI,si		; update caller's SI, too
	ret
ENDPROC utl_atoi16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atoi32 (AX = 1808h)
;
; Convert string at DS:SI to number in DX:AX using base BL.
;
; Returns:
;	Carry clear if one or more digits, set otherwise
;	DX:AX = value, DS:SI -> next character (after any non-digit)
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	utl_atoi32,DOS
	mov	di,-1			; setting no validation allows
	jmp	utl_atoi16		; atoi16 to return a 32-bit value
ENDPROC utl_atoi32

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_itoa (AX = 1809h)
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
; utl_tokify (AX = 180Bh or 180Ch)
;
; DOS_UTL_TOKIFY1 (180Bh) performs GENERIC parsing, which means that only
; tokens separated by whitespace will be returned (and they will all be
; identified "generically" as CLS_STR).
;
; DOS_UTL_TOKIFY2 (180Ch) performs BASIC parsing, which returns all tokens,
; even whitespace sequences (CLS_WHITE).
;
; Inputs:
;	REG_AL = 0Bh (TOKTYPE_GENERIC) or 0Ch (TOKTYPE_BASIC)
;	REG_DS:REG_SI -> BUF_INPUT
;	REG_ES:REG_DI -> BUF_TOKEN
;
; Outputs:
;	AX = # tokens; token buffer updated
;
; Modifies:
;	AX
;
DEFPROC	utl_tokify,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ds,[bp].REG_DS		; DS:SI -> BUF_INPUT
	mov	es,[bp].REG_ES		; ES:DI -> BUF_TOKEN
	ASSUME	DS:NOTHING, ES:NOTHING

	sub	bx,bx			; BX = token index
	add	si,offset INP_BUF	; SI -> 1st character
	mov	ah,0			; AH = initial classification
	test	al,TOKTYPE_GENERIC
	mov	al,-1
	jz	tf0			; for generic parsing
	mov	al,NOT CLS_WHITE	; we're not interested in whitespace
tf0:	mov	[bp].TMP_AL,al
	jmp	short tf8		; dive in
;
; Starting a new token.
;
tf1:	lea	dx,[si-1]		; DX = start of token
tf2:	lodsb
	mov	ch,ah
	call	tok_classify		; AH = next classification
	mov	al,ch			; AL = previous classification
	test	ah,ah			; all done?
	jz	tf6			; yes
	test	ch,ch			; still priming the pump?
	jz	tf1			; yes
	cmp	ah,CLS_SYM		; symbol found? (only happens w/BASIC)
	je	tf6a			; yes
	cmp	ah,ch			; any change to classification?
	je	tf2			; no

tf6:	test	al,[bp].TMP_AL		; any previous classification?
	jz	tf7			; no

tf6a:	lea	cx,[si-1]		; SI = end of token
	sub	cx,dx			; CX = length of token

	IFDEF DEBUG
	cmp	byte ptr [bp].TMP_AL,-1
	jne	tf6b
	push	ax
	mov	ah,0
	DPRINTF	<"token: '%.*ls' (%#04x)",13,10>,cx,dx,ds,ax
	pop	ax
tf6b:
	ENDIF
;
; Update the TOKLET in the TOK_BUF at ES:DI, token index BX
;
	push	bx
	add	bx,bx
	add	bx,bx			; BX = BX * 4 (size TOKLET)
	mov	es:[di+bx].TOK_BUF.TOKLET_CLS,al
	mov	es:[di+bx].TOK_BUF.TOKLET_LEN,cl
	mov	es:[di+bx].TOK_BUF.TOKLET_OFF,dx
	pop	bx
	inc	bx			; and increment token index

tf7:	test	ah,ah			; all done?
	jz	tf9			; yes

tf8:	cmp	bl,es:[di].TOK_MAX	; room for more tokens?
	jb	tf1			; yes

tf9:	mov	es:[di].TOK_CNT,bl	; update # tokens
	mov	[bp].REG_AX,bx		; return # tokens in AX, too
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
	cmp	al,CHR_RETURN
	jne	tc1
	sub	ah,ah
	ret
;
; Check for quotations first.
;
tc1:	cmp	al,CHR_DQUOTE		; double quotes?
	jne	tc1b			; no
	and	ah,CLS_DQUOTE		; yes
	xor	ah,CLS_DQUOTE		; are we inside double quotes?
	jnz	tc1a			; no
	mov	ah,CLS_STR		; convert classification to CLS_STR
	mov	ch,ah			; and set previous class to match
tc1a:	ret
tc1b:	test	ah,CLS_DQUOTE		; are we inside double quotes?
	jz	tc2			; no
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
; For generic parsing, everything is whitespace or a string.
;
tc3:	test	byte ptr [bp].REG_AL,TOKTYPE_GENERIC
	jz	tc4
	mov	ah,CLS_STR		; call it a string
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
; Technically, they can only continue CLS_OCT if < '8', but we worry about that
; later, during evaluation.
;
	test	ah,CLS_OCT OR CLS_HEX OR CLS_DEC OR CLS_VAR
	jnz	tc4a
	mov	ah,CLS_DEC		; must be decimal
tc4a:	cmp	ah,CLS_OCT OR CLS_HEX
	jne	tc4b
	and	ah,CLS_OCT
	mov	ch,ah			; set previous class as well
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
cl5b:	mov	ch,ah			; set previous class as well
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
; utl_tokid (AX = 180Dh)
;
; Inputs:
;	REG_CX = token length
;	REG_DS:REG_SI -> token
;	REG_ES:REG_DI -> TOKDEFs
; Outputs:
;	If carry clear, AX = token ID (TOKDEF_ID), DX = token data (TOKDEF_DATA)
;	If carry set, token not found
;
; Modifies:
;	AX
;
DEFPROC	utl_tokid,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ds,[bp].REG_DS		; DS:SI -> token (length CX)
	mov	es,[bp].REG_ES		; ES:DI -> TOKDEFs
	ASSUME	DS:NOTHING, ES:NOTHING

	push	bp
	sub	bp,bp			; BP = top index
	mov	dx,es:[di]		; DX = number of tokens in TOKDEFs
	add	di,2

td0:	mov	ax,-1
	cmp	bp,dx
	stc
	je	td9
	mov	bx,dx
	add	bx,bp
	shr	bx,1			; BX = midpoint index

	push	bx
	IF	SIZE TOKDEF EQ 6
	mov	ax,bx
	add	bx,bx
	add	bx,ax
	add	bx,bx
	ELSE
	ASSERT	B,<cmp bl,256>
	mov	al,size TOKDEF
	mul	bl
	mov	bx,ax
	ENDIF
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
	pop	bx			; BX = index of token we just tested
	mov	cl,ah			; restore CL from AH
	jnc	td4
	mov	dx,bx			; new bottom is middle
	jmp	td0
td4:	inc	bx
	mov	bp,bx			; new top is middle + 1
	jmp	td0

td8:	sub	ax,ax			; zero AX (and carry, too)
	mov	al,es:[di+bx].TOKDEF_ID	; AX = token ID
	mov	dx,es:[di+bx].TOKDEF_DATA; DX = user-defined token data
	pop	bx			; toss BX from stack

td9:	pop	bp
	jc	td9a
	mov	[bp].REG_DX,dx
	mov	[bp].REG_AX,ax
td9a:	ret
ENDPROC	utl_tokid

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_getdev (AX = 1810h)
;
; Returns DDH in ES:DI for device name at DS:DX.
;
; Inputs:
;	DS:DX -> device name
;
; Outputs:
;	ES:DI -> DDH if success; carry set if not found
;
; Modifies:
;	AX, CX, DI, ES (ie, whatever chk_devname modifies)
;
DEFPROC	utl_getdev,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY
	mov	si,dx
	call	chk_devname		; DS:SI -> device name
	jc	gd9
	mov	[bp].REG_DI,di
	mov	[bp].REG_ES,es
gd9:	ret
ENDPROC	utl_getdev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_ioctl (AX = 1811h)
;
; Inputs:
;	REG_BX = IOCTL command (BH = DDC_IOCTLIN, BL = IOCTL command)
;	REG_ES:REG_DI -> DDH
;	Other registers will vary
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	utl_ioctl,DOS
	sti
	mov	ax,[bp].REG_BX		; AX = command codes from BH,BL
	mov	es,[bp].REG_ES		; ES:DI -> DDH
	call	dev_request		; call the driver
	ret
ENDPROC	utl_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_load (AX = 1812h)
;
; Inputs:
;	REG_CL = SCB #
;	REG_DS:REG_DX = name of program (or command-line)
;
; Outputs:
;	Carry clear if successful
;	Carry set if error, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, DI, DS, ES
;
DEFPROC	utl_load,DOS
	sti
	mov	es,[bp].REG_DS
	and	[bp].REG_FL,NOT FL_CARRY
	ASSUME	DS:NOTHING		; CL = SCB #
	jmp	scb_load		; ES:DX -> name of program
ENDPROC	utl_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_start (AX = 1813h)
;
; "Start" the specified session (actual starting will handled by scb_switch)
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful, BX -> SCB
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_start,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
 	jmp	scb_start
ENDPROC	utl_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_stop (AX = 1814h)
;
; "Stop" the specified session
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_stop,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_stop
ENDPROC	utl_stop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_unload (AX = 1815h)
;
; Unload the current program from the specified session
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_unload,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_unload
ENDPROC	utl_unload

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_yield (AX = 1816h)
;
; Asynchronous interface to decide which SCB should run next.
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	utl_yield,DOS
	sti
	mov	ax,[scb_active]
	jmp	scb_yield
ENDPROC	utl_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_sleep (AX = 1817h)
;
; Converts DX from milliseconds (1000/second) to ticks (18.2/sec) and
; issues an IOCTL to the CLOCK$ driver to wait the corresponding # of ticks.
;
; 1 tick is equivalent to approximately 55ms, so that's the granularity of
; sleep requests.
;
; Inputs:
;	REG_CX:REG_DX = # of milliseconds to sleep
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	utl_sleep,DOS
	sti
	add	dx,27			; add 1/2 tick (as # ms) for rounding
	adc	cx,0
	mov	bx,55			; BX = divisor
	xchg	ax,cx			; AX = high dividend
	mov	cx,dx			; CX = low dividend
	sub	dx,dx
	div	bx			; AX = high quotient
	xchg	ax,cx			; AX = low dividend, CX = high quotient
	div	bx			; AX = low quotient
	xchg	dx,ax			; CX:DX = # ticks
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_WAIT
	les	di,clk_ptr
	call	dev_request		; call the driver
	ret
ENDPROC	utl_sleep

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_wait (AX = 1818h)
;
; Synchronous interface to mark current SCB as waiting for the specified ID.
;
; Inputs:
;	REG_DX:REG_DI == wait ID
;
; Outputs:
;	None
;
DEFPROC	utl_wait,DOS
	jmp	scb_wait
ENDPROC	utl_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_endwait (AX = 1819h)
;
; Asynchronous interface to examine all SCBs for the specified ID and clear it.
;
; Inputs:
;	REG_DX:REG_DI == wait ID
;
; Outputs:
;	Carry clear if found, set if not
;
DEFPROC	utl_endwait,DOS
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_endwait
ENDPROC	utl_endwait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_hotkey (AX = 181Ah)
;
; Inputs:
;	REG_CX = CONSOLE context
;	REG_DL = char code, REG_DH = scan code
;
; Outputs:
;	Carry clear if successful, set if unprocessed
;
; Modifies:
;	AX
;
DEFPROC	utl_hotkey,DOS
	sti
	xchg	ax,dx			; AL = char code, AH = scan code
	and	[bp].REG_FL,NOT FL_CARRY
;
; Find the SCB with the matching context; that's the one with focus.
;
	mov	bx,[scb_table].OFF
hk1:	cmp	[bx].SCB_CONTEXT,cx
	je	hk2
	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	hk1
	stc
	jmp	short hk9

hk2:	cmp	al,CHR_CTRLC
	jne	hk3
	or	[bx].SCB_CTRLC_ACT,1

hk3:	cmp	al,CHR_CTRLP
	clc
	jne	hk9
	xor	[bx].SCB_CTRLP_ACT,1

hk9:	ret
ENDPROC	utl_hotkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_lock (AX = 181Bh)
;
; Asynchronous interface to lock the current SCB
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	utl_lock,DOS
	LOCK_SCB
	ret
ENDPROC	utl_lock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_unlock (AX = 181Ch)
;
; Asynchronous interface to unlock the current SCB
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	utl_unlock,DOS
	UNLOCK_SCB
	ret
ENDPROC	utl_unlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_qrymem (AX = 181Dh)
;
; Query info about memory blocks
;
; Inputs:
;	REG_CX = memory block # (0-based)
;	REG_DL = memory block type (0 for any, 1 for free, 2 for used)
;
; Outputs:
;	On success, carry clear:
;		REG_ES:0 -> MCB
;		REG_AX = owner ID (eg, PSP)
;		REG_DX = size (in paragraphs)
;		REG_DS:REG_BX -> owner name, if any
;	On failure, carry set (ie, no more blocks of the requested type)
;
; Modifies:
;	AX, BX, CX, DS, ES
;
DEFPROC	utl_qrymem,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	mem_query
ENDPROC	utl_qrymem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_abort (AX = 181Fh)
;
; Inputs:
;	REG_DL = exit code
;	REG_DH = exit type
;
; Outputs:
;	None
;
DEFPROC	utl_abort,DOS
	xchg	ax,dx			; AL = exit code, AH = exit type
	jmp	psp_term_exitcode
ENDPROC	utl_abort

DOS	ends

	end
