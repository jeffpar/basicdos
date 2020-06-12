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
; Convert the value CX:DX to a string representation at ES:DI, with base BX.
;
; Returns:
;	ES:DI filled in
;	AL = # of digits
;
; Modifies:
;	AX, CX, DX, ES
;
DEFPROC	util_itoa,DOS
	mov	es,[bp].REG_ES
	ASSUME	ES:NOTHING
	DEFLBL	itoa,near		; for internal calls (no REG_FRAME)
	push	di			; DI saved
	push	bx
	xchg	dx,cx			; DX:CX instead of CX:DX
	mov	ax,cx			; DX:AX = 32-bit value
ia1:	mov	cx,ax			; save low dividend in CX
	mov	ax,dx			; divide the high dividend
	sub	dx,dx			; DX:AX is the new divided
	div	bx			; AX is high quotient (remainder in DX)
	xchg	ax,cx			; move to CX, restore low dividend
	div	bx			; AX is low quotient (remainder is 0-9)
	push	dx			; save remainder
	mov	dx,cx			; new quotient in DX:AX
	or	cx,ax			; is new quotient zero?
	jnz	ia1			; no, use as next dividend
ia2:	pop	ax			; pop a digit
	cmp	ax,bx			; end of digits?
	jae	ia4			; yes
	add	al,'0'			; convert digit to ASCII
	cmp	al,'9'			; alpha hex digit instead?
	jbe	ia3			; no
	add	al,'A'-'0'-10		; yes, adjust it to 'A' to 'F'
ia3:	stosb				; store the digit
	jmp	ia2
ia4:	pop	ax
	sub	di,ax			; DI = current - original address
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
BPOFF	equ	4			; # of bytes pushed since REG_FRAME

;
; Assorted "print flags"
;
PF_HASH	equ	01h
PF_ZERO	equ	02h
PF_LONG	equ	04h

DEFPROC	util_printf,DOS
	push	ss
	pop	es
	ASSUME	ES:NOTHING
	sub	bp,BPOFF		; align BP and SP
	ASSERTZ	<cmp bp,sp>		; assert that BPOFF is correct
	sub	sp,BUFLEN		; SP -> BUF
	mov	di,-BUFLEN		; [BP+DI] -> BUF
	mov	si,BPOFF+size REG_FRAME	; [BP+SI] -> 1st parameter, if any
	mov	bx,[BP+BPOFF].REG_IP
	mov	ds,[BP+BPOFF].REG_CS	; DS:BX -> format string
	ASSUME	DS:NOTHING

	push	bx
pf1:	mov	al,[bx]			; AL = next format character
	inc	bx
	test	al,al
	jz	pf8			; end of format string
	cmp	al,'%'			; format specifier?
	je	pf2			; yes
pf1a:	test	di,di			; buffer full?
	jz	pf1			; yes, but keep consuming format chars
	mov	[bp+di],al		; buffer the character
	inc	di
	jmp	pf1

pf2:	sub	cx,cx			; CX = assorted PF bits, if any
	mov	dx,bx			; DX = where this specifier started
pf2a:	mov	al,[bx]
	inc	bx
	cmp	al,'l'
	jne	pf2b
	or	cl,PF_LONG
	jmp	pf2a
pf2b:	cmp	al,'0'
	jne	pf2c
	or	al,PF_ZERO
	jmp	pf2a
pf2c:	cmp	al,'#'
	jne	pf2d
	or	al,PF_HASH
	jmp	pf2a
pf2d:	cmp	al,'d'
	je	pfd
pf2x:	mov	bx,dx			; error, didn't end with known letter
	mov	al,'%'			; restore '%'
	jmp	pf1a
;
; Process '%d' specification
;
pfd:	mov	dx,[bp+si]		; grab a stack parameter
	add	si,2
	test	cl,PF_LONG
	jnz	pfd2
	sub	cx,cx			; CX:DX = 16-bit value
	cmp	di,-6			; room?
	jge	pf2x			; no
pfd1:	push	bx
	mov	bx,10
	push	di
	lea	di,[bp+di]		; ES:DI -> room for number
	call	itoa
	pop	di
	add	di,ax
	pop	bx
	jmp	pf1
pfd2:	mov	cx,[bp+si]		; grab another stack parameter
	add	si,2			; CX:DX = 32-bit value
	cmp	di,-12			; room?
	jge	pf2x			; no
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
	add	sp,BUFLEN
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
