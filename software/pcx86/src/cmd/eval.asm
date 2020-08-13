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
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
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
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
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
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
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
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
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
; be less than the divisor, it can't be more than 16 bits either.
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
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	evalModLong,FAR
	mov	al,1
	jmp	evalDivModLong
ENDPROC	evalModLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalExpLong
;
; Since the long version of exponentiation supports only long base (expA) and
; power (expB) args, we can consider these discrete power cases:
;
;	<0, =0, =1, power-of-two, and anything else
;
; If <0, negate the power, calculate the result, and return 1/result;
; however, note that the long division of 1 by any possible result here can
; only produce 1, -1, or 0|underflow.
;
; If =0, return 1.
;
; If =1, return base.
;
; If >1, return base if base=0 or base=1; if base=-1, then return 1 if power
; is even or -1 if power is odd.
;
; If power-of-two, return base shifted left power times, which may result in
; zero|overflow (guaranteed if power >= 32).
;
; Otherwise, we can perform repeated multiplication until power is exhausted
; or the result becomes zero|overflow; can never take more than 32 iterations.
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalExpLong,FAR
	ARGVAR	expA,dword
	ARGVAR	expB,dword
	ENTER
	;...
	LEAVE
	ret	4
ENDPROC	evalExpLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalNegLong
;
; Inputs:
;	1 32-bit arg on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	evalNegLong,FAR
	ARGVAR	negA,dword
	ENTER
	neg 	[negA].SEG
	neg	[negA].OFF
	sbb	[negA].SEG,0
	LEAVE
	ret
ENDPROC	evalNegLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalNotLong
;
; Inputs:
;	1 32-bit arg on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalNotLong,FAR
	ARGVAR	notA,dword
	ENTER
	not 	[negA].SEG
	not	[negA].OFF
	LEAVE
	ret
ENDPROC	evalNotLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalImpLong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalImpLong,FAR
	ARGVAR	impA,dword
	ARGVAR	impB,dword
	ENTER
	;...
	LEAVE
	ret	4
ENDPROC	evalImpLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalEqvLong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalEqvLong,FAR
	ARGVAR	eqvA,dword
	ARGVAR	eqvB,dword
	ENTER
	;...
	LEAVE
	ret	4
ENDPROC	evalEqvLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalXorLong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalXorLong,FAR
	ARGVAR	xorA,dword
	ARGVAR	xorB,dword
	ENTER
	mov	ax,[xorB].OFF
	xor	[xorA].OFF,ax
	mov	ax,[xorB].SEG
	xor	[xorA].SEG,ax
	LEAVE
	ret	4
ENDPROC	evalXorLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalOrLong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalOrLong,FAR
	ARGVAR	orA,dword
	ARGVAR	orB,dword
	ENTER
	mov	ax,[orB].OFF
	xor	[orA].OFF,ax
	mov	ax,[orB].SEG
	xor	[orA].SEG,ax
	LEAVE
	ret	4
ENDPROC	evalOrLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalAndLong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalAndLong,FAR
	ARGVAR	andA,dword
	ARGVAR	andB,dword
	ENTER
	mov	ax,[andB].OFF
	xor	[andA].OFF,ax
	mov	ax,[andB].SEG
	xor	[andA].SEG,ax
	LEAVE
	ret	4
ENDPROC	evalAndLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalEQLong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalEQLong,FAR
	ARGVAR	eqA,dword
	ARGVAR	eqB,dword
	ENTER
	;...
	LEAVE
	ret	4
ENDPROC	evalEQLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalNELong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalNELong,FAR
	ARGVAR	neA,dword
	ARGVAR	neB,dword
	ENTER
	;...
	LEAVE
	ret	4
ENDPROC	evalNELong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalLTLong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalLTLong,FAR
	ARGVAR	ltA,dword
	ARGVAR	ltB,dword
	ENTER
	;...
	LEAVE
	ret	4
ENDPROC	evalLTLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalGTLong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalGTLong,FAR
	ARGVAR	gtA,dword
	ARGVAR	gtB,dword
	ENTER
	;...
	LEAVE
	ret	4
ENDPROC	evalGTLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalLELong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalLELong,FAR
	ARGVAR	leA,dword
	ARGVAR	leB,dword
	ENTER
	;...
	LEAVE
	ret	4
ENDPROC	evalLELong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalGELong
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX
;
DEFPROC	evalGELong,FAR
	ARGVAR	geA,dword
	ARGVAR	geB,dword
	ENTER
	;...
	LEAVE
	ret	4
ENDPROC	evalGELong

CODE	ENDS

	end
