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

	EXTERNS	<write_tty>,near

	DEFLBL	UTILTBL,word
	dw	util_strlen,util_atoi,util_itoa,util_printf	; 00h-03h
	dw	util_strlen,util_none,util_none,util_none	; 04h-07h
	dw	util_strlen,util_none,util_none,util_none	; 08h-0Bh
	dw	util_strlen,util_none,util_none,util_none	; 0Ch-0Fh
	dw	util_strlen,util_none,util_none,util_none	; 10h-13h
	dw	util_strlen,util_none,util_none,util_none	; 14h-17h
	dw	util_strlen,util_none,util_none,util_none	; 18h-1Bh
	dw	util_strlen,util_none,util_none,util_none	; 1Ch-1Fh
	dw	util_strlen,util_none,util_none,util_none	; 20h-23h
	dw	util_strlen					; 24h
	DEFABS	UTILTBL_SIZE,<($ - UTILTBL) SHR 1>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_func (AH = 18h)
;
; Inputs:
;	AL = utility function (eg, UTIL_ATOI)
;
; Outputs:
;	Varies
;
DEFPROC	util_func,DOS
	cmp	al,UTILTBL_SIZE
	cmc
	jb	dc9
	cbw
	mov	bx,ax
	add	bx,ax
	call	UTILTBL[bx]
	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
dc9:	ret
ENDPROC	util_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_strlen (AL = 00h or 24h)
;
; Returns the length of the REG_DS:SI string in AX, using the terminator in AL.
;
; Modifies:
;	AX, CX, DI
;
DEFPROC	util_strlen,DOS
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	DEFLBL	strlen,near		; for internal calls (no REG_FRAME)
	push	es
	push	ds
	pop	es
	mov	di,si
	mov	cx,di
	not	cx			; CX = largest possible count
	repne	scasb
	je	usl9
	stc				; error if we didn't end on a match
usl9:	sub	di,si
	lea	ax,[di-1]		; don't count the terminator character
	pop	es
	ret
ENDPROC	util_strlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_atoi (AL = 01h)
;
; Convert string at DS:SI to decimal, then validate using values at ES:DI.
;
; For no validation, set DI to zero; otherwise, ES:DI must point to a pair
; of (min,max) 16-bit values; and like SI, DI will be advanced, making it easy
; to parse a series of values, each with their own (min,max) values.
;
; Returns:
;	AX = value, DS:SI -> next character (after non-decimal digit)
;	Carry will be set on a validation error, but AX will ALWAYS be valid
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	util_atoi,DOS
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	sub	ax,ax
	cwd
	mov	cx,10
ud1:	mov	dl,[si]
	cmp	dl,'0'
	jb	ud5
	sub	dl,'0'
	cmp	dl,cl
	jae	ud6
	inc	si
	push	dx
	mul	cx
	pop	dx
	add	ax,dx
	jmp	ud1
ud5:	test	dl,dl
	jz	ud6
	inc	si
ud6:	test	di,di			; validation data provided?
	jz	ud9			; no
	cmp	ax,es:[di]		; too small?
	jae	ud7			; no
	mov	ax,es:[di]
	jmp	short ud8
ud7:	cmp	es:[di+2],ax		; too large?
	jae	ud8			; no
	mov	ax,es:[di+2]
ud8:	lea	di,[di+4]		; advance DI in case there are more
	mov	[bp].REG_DI,di		; but do so without disturbing CARRY
ud9:	mov	[bp].REG_SI,si		; update caller's SI, too
	ret
ENDPROC util_atoi

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_itoa (AL = 02h)
;
; Convert the value DX:SI to a string representation at ES:DI, using base BL,
; flags BH, and length CX.
;
; Returns:
;	ES:DI filled in
;	AL = # of digits
;
; Modifies:
;	AX, CX, DX, ES
;

;
; Assorted "print flags"
;
PF_HASH	equ	01h			; prefix requested (eg, 0x for hex)
PF_ZERO	equ	02h			; zero padding requested
PF_LONG	equ	04h			; long value (32 bits); default is 16
PF_SIGN	equ	08h			; signed value

DEFPROC	util_itoa,DOS
	xchg	ax,si			; DX:AX is the value
	mov	es,[bp].REG_ES		; ES:DI -> buffer
	ASSUME	ES:NOTHING
;
; itoa internal calls use DX:AX
;
	DEFLBL	itoa,near		; for internal calls (no REG_FRAME)
	push	bp
	push	si
	push	di
	push	bx			; save flags and base
	push	cx			; save requested length

	sub	si,si
	test	bh,PF_SIGN		; treat value as signed?
	jz	ia0			; no
	test	dx,dx			; negative value?
	jns	ia0			; no
	neg	dx			; yes, negate DX:AX
	neg	ax
	sbb	dx,0
	inc	si			; SI = 1 if we must add a sign

ia0:	mov	bh,0
	mov	bp,sp
ia1:	mov	cx,ax			; save low dividend in CX
	mov	ax,dx			; divide high dividend
	sub	dx,dx			; DX:AX is new dividend
	div	bx			; AX is high quotient (DX remainder)
	xchg	ax,cx			; move to CX, restore low dividend
	div	bx			; AX is low quotient (remainder is 0-N)
	push	dx			; save remainder
	mov	dx,cx			; new quotient in DX:AX
	or	cx,ax			; is new quotient zero?
	jnz	ia1			; no, use as next dividend

ia2:	mov	cx,[bp]			; recover requested length
	mov	bx,[bp+2]		; recover flags
	sub	bp,sp
	shr	bp,1			; BP = # of digits
	sub	cx,bp			; is space left over?
	jle	ia6			; no
	sub	cx,si			; subtract room for sign, if any
	jle	ia6			; again, jump if no space left over
;
; Padding is required, but unfortunately, spaces must appear BEFORE any sign
; and zeros must appear AFTER any sign.
;
	mov	al,' '
	test	bl,PF_ZERO		; pad with zeros?
	jz	ia3			; no
	mov	al,'0'			; yes

ia3:	test	si,si
	jz	ia5			; no sign
	cmp	al,' '			; space padding (before sign?)
	jne	ia4			; no

	rep	stosb			; we require spaces followed by sign
	mov	al,'-'
	stosb
	jmp	short ia7

ia4:	mov	al,'-'			; we require a sign followed by zeros
	stosb
	mov	al,'0'

ia5:	sub	si,si
	rep	stosb			; no sign, we just need to pad

ia6:	test	si,si
	jz	ia7
	mov	al,'-'
	stosb

ia7:	pop	ax			; pop a digit
	add	al,'0'			; convert digit to ASCII
	cmp	al,'9'			; alpha hex digit instead?
	jbe	ia8			; no
	add	al,'A'-'0'-10		; yes, adjust it to 'A' to 'F'
ia8:	stosb				; store the digit
	dec	bp
	jnz	ia7

	add	sp,4			; discard requested length and flags
	pop	ax
	pop	si
	pop	bp
	sub	di,ax			; current - original address
	xchg	ax,di			; DI restored, AX is the digit count
	ret
ENDPROC util_itoa

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_printf (AL = 03h)
;
; A semi-CDECL-style calling convention is assumed, where all parameters
; EXCEPT for the format string are pushed from right to left, so that the
; first (left-most) parameter is the last one pushed.  The format string
; is stored in the CODE segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; The code also relies on BPOFF, which must be set to the EXACT number of
; additional bytes pushed onto the stack since REG_FRAME was created.
; Obviously that could be calculated at run-time, but it's preferable to know
; the value at assembly-time so that we can use constant displacements and
; simplify register usage.
;
; A BPOFF value of 4 indicates there were two near-call dispatches (one in
; dos_func and the other in util_func) and no other pushes between the creation
; of REG_FRAME and arriving here.
;
; Inputs:
;	format string follows the INT 21h
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	# of characters printed
;
; Modifies:
;	AX, BX, CX, SI, DI, DS, ES
;
BUFLEN	equ	80			; arbitrary buffer limit
BPOFF	equ	6			; # of bytes pushed since REG_FRAME

DEFPROC	util_printf,DOS
	push	ss
	pop	es
	ASSUME	ES:NOTHING
	push	ax			; scratch space
	sub	bp,BPOFF		; align BP and SP
	ASSERTZ	<cmp bp,sp>		; assert that BPOFF is correct
	sub	sp,BUFLEN		; SP -> BUF
	mov	di,-BUFLEN		; BP+DI -> BUF
	mov	si,BPOFF+size REG_FRAME	; BP+SI -> 1st parameter, if any
	mov	bx,[BP+BPOFF].REG_IP
	mov	ds,[BP+BPOFF].REG_CS	; DS:BX -> format string
	ASSUME	DS:NOTHING

	push	bx
pf1:	mov	al,[bx]			; AL = next format character
	inc	bx
	test	al,al
	jz	pf1b			; end of format string
	cmp	al,'%'			; format specifier?
	je	pf2			; yes
pf1a:	test	di,di			; buffer full?
	jz	pf1			; yes, but keep consuming format chars
	mov	[bp+di],al		; buffer the character
	inc	di
	jmp	pf1
pf1b:	jmp	pf8

pf2:	mov	cx,10			; CH = print flags, CL = base
	mov	dx,bx			; DX = where this specifier started
	mov	word ptr [bp],0		; use scratch for specifier length
pf2a:	mov	al,[bx]
	inc	bx
	cmp	al,'#'
	jne	pf2b
	or	ch,PF_HASH
	jmp	pf2a
pf2b:	cmp	al,'0'
	jne	pf2c
	cmp	word ptr [bp],0
	jne	pf2g
	or	ch,PF_ZERO
	jmp	pf2a
pf2c:	cmp	al,'l'
	jne	pf2d
	or	ch,PF_LONG
	jmp	pf2a
pf2d:	cmp	al,'d'
	jne	pf2e
	or	ch,PF_SIGN
	jmp	short pfd
pf2e:	cmp	al,'u'
	je	pfd
	cmp	al,'x'
	jne	pf2f
	mov	cl,16			; use base 16 instead
	jmp	short pfd
pf2f:	cmp	al,'0'			; possible length?
	jb	pf2z			; no
	cmp	al,'9'
	ja	pf2z			; no
pf2g:	sub	al,'0'
	push	dx
	xchg	dx,ax
	mov	al,[bp]
	mov	ah,10
	mul	ah
	add	al,dl
	mov	[bp],al
	pop	dx
	jmp	pf2a
pf2z:	mov	bx,dx			; error, didn't end with known letter
	mov	al,'%'			; restore '%'
	jmp	pf1a
;
; Process %d, %u, and %x specifications
;
pfd:	mov	ax,[bp]			; if the length - DI is > 0
	add	ax,di			; then we don't have enough space
	jg	pf2z

	mov	ax,[bp+si]		; grab a stack parameter
	add	si,2
	test	ch,PF_LONG
	jnz	pfd2
	cmp	di,-6			; room?
	jge	pf2z			; no
	sub	dx,dx			; DX:AX = 16-bit value
	test	ch,PF_SIGN		; signed value?
	jz	pfd1			; no
	cwd				; yes, sign-extend AX to DX
pfd1:	push	bx
	mov	bx,cx			; set flags (BH) and base (BL)
	push	di
	mov	cx,[bp]			; CX = length (0 if unspecified)
	lea	di,[bp+di]		; ES:DI -> room for number
	call	itoa
	pop	di
	add	di,ax			; adjust DI by number of digits
	pop	bx
	jmp	pf1

pfd2:	mov	dx,[bp+si]		; grab another stack parameter
	add	si,2			; DX:AX = 32-bit value
	cmp	di,-12			; room?
	jge	pf2z			; no
	jmp	pfd1

pf8:	pop	ax			; AX = original format string address
	sub	bx,ax			; BX = length of string (incl. null)
	add	[bp+BPOFF].REG_IP,bx	; skip over the format string at CS:IP
	mov	si,sp
	push	ss
	pop	ds			; DS:SI -> BUF
	lea	cx,[di+BUFLEN]		; CX = # of characters
	push	cx
	call	write_tty
	pop	ax			; AX = # of characters
	add	sp,BUFLEN+2
	add	bp,BPOFF
	ret
ENDPROC	util_printf endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_none
;
; Modifies:
;	None
;
DEFPROC	util_none
	ret
ENDPROC	util_none

DOS	ends

	end
