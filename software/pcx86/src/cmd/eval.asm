;
; BASIC-DOS Evaluation Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalAddLong
;
; Inputs:
;	2 32-bit values on stack (popped)
;
; Outputs:
;	1 32-bit sum on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalAddLong,FAR
	ARGVAR	addA,dword
	ARGVAR	addB,dword
	ENTER
	mov	ax,[addB].OFF
	add	[addA].OFF,ax
	mov	ax,[addB].SEG
	adc	[addA].SEG,ax
	LEAVE
	ret	4
ENDPROC	evalAddLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalSubLong
;
; Inputs:
;	2 32-bit values on stack (popped)
;
; Outputs:
;	1 32-bit difference on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	evalSubLong,FAR
	ARGVAR	subA,dword
	ARGVAR	subB,dword
	ENTER
	mov	ax,[subB].OFF
	sub	[subA].OFF,ax
	mov	ax,[subB].SEG
	sbb	[subA].SEG,ax
	LEAVE
	ret	4
ENDPROC	evalSubLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalMulLong
;
; Inputs:
;	2 32-bit values on stack (popped)
;
; Outputs:
;	1 32-bit product on stack (pushed)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	evalMulLong,FAR
	ARGVAR	mulA,dword
	ARGVAR	mulB,dword
	ENTER

	mov	ax,[mulB].OFF
	mul	[mulA].SEG
	xchg	cx,ax			; CX = mulB.OFF * mulA.SEG

	mov	ax,[mulA].OFF
	mul	[mulB].SEG
	add	cx,ax			; CX = sum of cross product

	mov	ax,[mulA].OFF
	mul	[mulB].OFF		; DX:AX = mulB.OFF * mulA.OFF
	add	dx,cx			; add cross product to upper word

	mov	[mulA].OFF,ax
	mov	[mulA].SEG,dx
	LEAVE
	ret	4
ENDPROC	evalMulLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalDivLong
;
; Inputs:
;	2 32-bit values on stack (popped)
;
; Outputs:
;	1 32-bit quotient on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
; Adapted from sample code in "The Art of Assembly Language" by Randall Hyde
; and Stack Overflow (https://stackoverflow.com/questions/55429707/).
;
DEFPROC	evalDivLong,FAR
	mov	al,0			; AL = 0 for quotient, 1 for remainder
	DEFLBL	evalDivModLong,near
	ARGVAR	divA,dword
	ARGVAR	divB,dword
	LOCVAR	bitCount,byte
	LOCVAR	resultType,byte
	LOCVAR	signDivisor,byte
	LOCVAR	signDividend,byte

	ENTER
	mov	[bitCount],32
	mov	[resultType],al
	mov	bx,[divA].OFF
	mov	ax,[divA].SEG		; AX:BX = dividend
	mov	[signDividend],ah

	cwd				; DX = 0 or -1
	xor	bx,dx
	xor	ax,dx			; flip all the bits in AX:BX (or not)
	sub	bx,dx
	sbb	ax,dx			; AX:BX = abs(dividend)

	xchg	si,ax			; SI:BX = abs(dividend), for now

	mov	cx,[divB].OFF
	mov	ax,[divB].SEG		; AX:CX = divisor
	mov	[signDivisor],ah

	cwd				; DX = 0 or -1
	xor	cx,dx
	xor	ax,dx			; flip all the bits in AX:CX (or not)
	sub	cx,dx
	sbb	ax,dx			; AX:CX = abs(divisor)

	xchg	cx,ax			; CX:AX = abs(divisor)
	xchg	bx,ax			; CX:BX = abs(divisor)
	mov	dx,si			; DX:AX = abs(dividend)

	sub	si,si
	sub	di,di			; SI:DI = remainder (initially zero)
	jcxz	dl4

dl1:	shl	ax,1			; shift SI:DI:DX:AX left 1 bit
	rcl	dx,1
	rcl	di,1
	rcl	si,1
	cmp	si,cx			; compare high words of rem, divisor
	ja	dl2
	jb	dl3
	cmp	di,bx			; compare low words
	jb	dl3
dl2:	sub	di,bx			; remainder = remainder - divisor
	sbb	si,cx
	inc	ax			; set low bit of AX
dl3:	dec	[bitCount]		; repeat
	jne	dl1
	jmp	short dl5
;
; We can use the DIV instruction, since the divisor is no more than 16 bits;
; we use two divides to avoid quotient overflow.  And since the remainder must
; be less than the divisor, it cannot be more than 16 bits either.
;
; This is also the only path that has to worry about divide-by-zero, since zero
; is a 16-bit divisor.
;
dl4:	mov	cx,ax			; save low dividend
	mov	ax,dx			; divide high dividend
	sub	dx,dx			; DX:AX is new dividend
	div	bx			; AX is high quotient
	xchg	ax,cx			; move to CX, restore low dividend
	div	bx			; AX is low quotient
	mov	di,dx			; SI:DI = remainder
	mov	dx,cx			; DX:AX = quotient

dl5:	test	[signDividend],-1	; negate remainder if dividend neg
	jns	dl6
	neg 	si
	neg	di			; subtract SI:DI from 0 with carry
	sbb	si,0

dl6:	mov	cl,[signDivisor]	; negate quotient if signs opposite
	xor	cl,[signDividend]
	jns	dl7
	neg 	dx
	neg	ax			; subtract DX:AX from 0 with carry
	sbb	dx,0

dl7:	cmp	[resultType],0
	je	dl8
	mov	[divA].OFF,di		; return remainder
	mov	[divA].SEG,si
	jmp	short dl9
dl8:	mov	[divA].OFF,ax		; return quotient
	mov	[divA].SEG,dx
dl9:	LEAVE
	ret	4
ENDPROC	evalDivLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalModLong
;
; Inputs:
;	2 32-bit values on stack (popped)
;
; Outputs:
;	1 32-bit remainder on stack (pushed)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	evalModLong,FAR
	mov	al,1
	jmp	evalDivModLong
ENDPROC	evalModLong

CODE	ENDS

	end
