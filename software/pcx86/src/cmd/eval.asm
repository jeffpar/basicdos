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
	mov	ax,[addB].LOW
	add	[addA].LOW,ax
	mov	ax,[addB].HIW
	adc	[addA].HIW,ax
	into
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
	mov	ax,[subB].LOW
	sub	[subA].LOW,ax
	mov	ax,[subB].HIW
	sbb	[subA].HIW,ax
	into
	LEAVE
	ret	4
ENDPROC	evalSubLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalMulLong
;
; I now load mulA in SI:BX and mulB into AX:CX, convert them to positive
; values, multiply, and then negate the result if the signs differ; the
; previous approach seemed to work fine, but it's harder to optimize when
; both inputs have a magnitude of 16 bits or less, harder to detect overflow
; conditions, and less obvious that it works for all signed inputs.
;
; TODO: Overflow detection is still slightly complicated by 80000000h, both
; as an input value (because it can't be negated) and as an output value
; (since it can be produced by two positive values such as 20000h and 4000h).
;
; Example: -123123123 (F8A9 4A4D) * 91283123 (0570 DEB3)
;
;	a) load mulA (F8A9 4A4D) and negate: 0756 B5B3 (SI:BX)
;	b) load mulB: 0570 DEB3 (AX:CX)
;	c) multiply AX * BX (0570 * B5B3): 03DB FD50 (DX:AX)
;	d) multiply SI * CX (0756 * DEB3): 0661 B522 (DX:AX)
;	e) add B522 to FD50, resulting in B272
;	f) multiply BX * CX (B5B3 * DEB3): 9E10 4629 (DX:AX)
;	g) add B272 to 9E10, resulting in 5082 (with carry)
;	h) negate 5082 4629, resulting in AF7D B9D7
;
;			0756B5B3
;			0570DEB3
;		      x --------
;			16042119
;		       50B9CEB1
;		      66BDEFCA
;		     5F673A17
;		    00000000
;		   335EF7E5
;		  24B18C7F
;		 00000000
;		 ---------------
;		0027EDDE50824629
;		FFD81221AF7DB9D7 (negated)
;
; In this example, the OPCHECK macro will trigger a warning, because our
; JavaScript test environment comes up with AF7DB9D8 instead; it does all its
; multiplication in floating-point, which is limited to 52 significant bits,
; so some accuracy is lost in the low 32 bits.
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
DEFPROC	evalMulLong,FAR
	ARGVAR	mulA,dword
	ARGVAR	mulB,dword
	ENTER

	mov	bx,[mulA].LOW
	mov	ax,[mulA].HIW		; AX:BX = mulA

	cwd				; DX = 0 or -1
	xor	bx,dx
	xor	ax,dx			; flip all the bits in AX:BX (or not)
	sub	bx,dx
	sbb	ax,dx			; AX:BX = abs(mulA)
	xchg	si,ax			; SI:BX = abs(mulA)

	mov	cx,[mulB].LOW
	mov	ax,[mulB].HIW		; AX:CX = mulB

	cwd				; DX = 0 or -1
	xor	cx,dx
	xor	ax,dx			; flip all the bits in AX:CX (or not)
	sub	cx,dx
	sbb	ax,dx			; AX:CX = abs(mulB)

	sub	di,di			; clear overflow indicator
	mov	dx,si			; save SI
	or	si,ax			; are both SI and AX zero?
	jz	ml1			; yes, just need one multiply
	mov	si,dx			; restore SI

	test	si,si			; if both high words are non-zero
	jz	ml0			; signal overflow
	test	ax,ax			; (no impact if either one is zero)
	jz	ml0
	inc	di

ml0:	mul	bx
	xchg	si,ax			; SI = mulB.HIW (AX) * mulA.LOW (BX)
	or	di,dx			; any bits in DX triggers an overflow
	mul	cx
	add	si,ax			; SI += mulA.HIW (AX) * mulB.LOW (CX)
	adc	di,0			; any carry triggers an overflow
	or	di,dx			; any bits in DX triggers an overflow
ml1:	xchg	ax,bx
	mul	cx			; DX:AX = mulA.LOW (AX) * mulB.LOW (CX)
	add	dx,si			; DX += SI
	adc	di,0			; any carry triggers an overflow

	cmp	dx,8000h		; negative result?
	jb	ml5			; no
	jne	ml4			; yes, and it's not 80000000h
	test	ax,ax			; oh wait, maybe it is
	jz	ml5			; yes, it is
ml4:	or	di,1			; no, it's not, so flag it as overflow

ml5:	mov	cl,[mulA].HIW.HIB
	xor	cl,[mulB].HIW.HIB	; signs differ?
	jns	ml6			; no
	neg 	dx
	neg	ax			; subtract DX:AX from 0 with carry
	sbb	dx,0

ml6:	test	di,di			; overflow indicator set?
	jz	ml7			; no
	int	04h			; signal overflow
;
; Previous code, retained for reference.  Note that it fails to optimize the
; case where both high words are FFFFh (ie, sign-extensions of the low words),
; and makes no attempt to catch any of the many potentials for overflow.
;
; 	mov	cx,[mulA].HIW		; a small optimization:
; 	or	cx,[mulB].HIW		; if both numbers are >= 0 and < 65536
; 	jcxz	ml1			; then a single multiplication suffices
;
; 	mov	ax,[mulB].LOW
; 	mul	[mulA].HIW
; 	xchg	cx,ax			; CX = mulB.LOW * mulA.HIW
;
; 	mov	ax,[mulA].LOW
; 	mul	[mulB].HIW
; 	add	cx,ax			; CX = sum of cross product
;
; ml1:	mov	ax,[mulA].LOW
; 	mul	[mulB].LOW		; DX:AX = mulB.LOW * mulA.LOW
; 	add	dx,cx			; add cross product to upper word

ml7:	OPCHECK	OP_MUL32

	mov	[mulA].LOW,ax
	mov	[mulA].HIW,dx
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

	ENTER
	mov	[bitCount],32
	mov	[resultType],al
	mov	bx,[divA].LOW
	mov	ax,[divA].HIW		; AX:BX = dividend

	cwd				; DX = 0 or -1
	xor	bx,dx
	xor	ax,dx			; flip all the bits in AX:BX (or not)
	sub	bx,dx
	sbb	ax,dx			; AX:BX = abs(dividend)

	xchg	si,ax			; SI:BX = abs(dividend), for now

	mov	cx,[divB].LOW
	mov	ax,[divB].HIW		; AX:CX = divisor

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
; we use two divides, if necessary, to avoid quotient overflow.  And since the
; remainder must be less than the divisor, it can't be more than 16 bits, too.
;
; This is also the only path that has to worry about divide-by-zero, since zero
; is a 16-bit divisor.
;
dl4:	sub	cx,cx
	cmp	dx,bx			; can we avoid the first division?
	jb	dl4a			; yes
	xchg	cx,ax			; save low dividend
	xchg	ax,dx			; divide high dividend
	sub	dx,dx			; DX:AX is new dividend
	div	bx			; AX is high quotient
	xchg	ax,cx			; move to CX, restore low dividend
dl4a:	div	bx			; AX is low quotient
	mov	di,dx			; SI:DI = remainder
	mov	dx,cx			; DX:AX = quotient

dl5:	test	[divA].HIW.HIB,-1	; negate remainder if dividend neg
	jns	dl6
	neg 	si
	neg	di			; subtract SI:DI from 0 with carry
	sbb	si,0

dl6:	mov	cl,[divB].HIW.HIB	; negate quotient if signs opposite
	xor	cl,[divA].HIW.HIB
	jns	dl7
	neg 	dx
	neg	ax			; subtract DX:AX from 0 with carry
	sbb	dx,0

dl7:	OPCHECK	OP_DIV32

	cmp	[resultType],0
	je	dl8
	mov	[divA].LOW,di		; return remainder
	mov	[divA].HIW,si
	jmp	short dl9
dl8:	mov	[divA].LOW,ax		; return quotient
	mov	[divA].HIW,dx
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
; This version of exponentiation supports only long base (expA) and power
; (expB) args, so we consider these discrete power cases:
;
;	<0, =0, =1, >1, >31
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
; If base is 2, return base shifted left power times, which may result in
; zero|overflow (guaranteed if power > 31).
;
; Otherwise, perform repeated multiplication until power is exhausted or the
; result becomes zero|overflow; note that any power larger than 31 will always
; cause an overflow, since we've already eliminated bases <= 2.
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	evalExpLong,FAR
	ARGVAR	expA,dword
	ARGVAR	expB,dword
	ENTER
	mov	ax,[expB].LOW
	mov	dx,[expB].HIW
	test	dx,dx			; TODO: large and/or negative powers
	jnz	ex4
	cmp	ax,1			; power = 1?
	je	ex10			; yes, return base as-is
	inc	ax			; power = 0?
	jb	ex9			; yes, set return value to 1
;
; Power is greater than 1.  Check for simple bases.
;
	dec	ax			; undo previous power increment
	mov	cx,[expA].LOW
	mov	dx,[expA].HIW
	test	dx,dx
	jnz	ex1
	jcxz	ex10			; DX:CX is 0, return base as-is
	dec	cx
	jz	ex10			; DX:CX is 1, return base as-is
	jmp	short ex2
ex1:	inc	dx
	jnz	ex2
	inc	cx			; DX was FFFFh, is CX FFFFh too?
	jnz	ex2			; no
	test	al,1			; DX:CX = -1, so is the power odd?
	jnz	ex10			; yes, return base (-1)
	inc	cx			; DX:CX = 1
	xchg	ax,cx			; DX:AX = 1
	jmp	short ex9		; return DX:AX (1) when power is even
;
; Check base for 2, which can be shifted instead of multiplied.
;
ex2:	cmp	ax,32			; power >= 32?
	jae	ex4			; yes, return 0 (overflow)
	mov	cx,ax			; CX = shift count
	dec	cx
	mov	ax,[expA].LOW
	mov	dx,[expA].HIW		; DX:AX = base
	test	dx,dx
	jnz	ex5
	cmp	ax,2
	jne	ex5
ex3:	shl	ax,1
	rcl	dx,1
	loop	ex3
	jmp	short ex9		; return shifted base

ex4:	sub	ax,ax
	cwd
	jmp	short ex9
;
; Worst case: repetitive multiplication.
;
ex5:	push	dx
	push	ax
ex6:	push	[expA].HIW
	push	[expA].LOW
	push	cs
	call	near ptr evalMulLong
	loop	ex6
	pop	ax
	pop	dx

ex9:	mov	[expA].LOW,ax
	mov	[expA].HIW,dx
ex10:	LEAVE
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
;	None
;
DEFPROC	evalNegLong,FAR
	ARGVAR	negA,dword
	ENTER
	neg 	[negA].HIW
	neg	[negA].LOW
	sbb	[negA].HIW,0
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
;	None
;
DEFPROC	evalNotLong,FAR
	ARGVAR	notA,dword
	ENTER
	not 	[notA].HIW
	not	[notA].LOW
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
	mov	ax,[impB].LOW
	not	[impA].LOW
	or	[impA].LOW,ax
	mov	ax,[impB].HIW
	not	[impA].HIW
	or	[impA].HIW,ax
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
	mov	ax,[eqvB].LOW
	xor	[eqvA].LOW,ax
	not	[eqvA].LOW
	mov	ax,[eqvB].HIW
	xor	[eqvA].HIW,ax
	not	[eqvA].HIW
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
	mov	ax,[xorB].LOW
	xor	[xorA].LOW,ax
	mov	ax,[xorB].HIW
	xor	[xorA].HIW,ax
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
	mov	ax,[orB].LOW
	or	[orA].LOW,ax
	mov	ax,[orB].HIW
	or	[orA].HIW,ax
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
	mov	ax,[andB].LOW
	and	[andA].LOW,ax
	mov	ax,[andB].HIW
	and	[andA].HIW,ax
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
;	AX, BX, CX, DX
;
DEFPROC	evalEQLong,FAR
	mov	bx,offset evalEQ
	DEFLBL	evalRelLong,near
	ARGVAR	eqA,dword
	ARGVAR	eqB,dword
	ENTER
	mov	cx,[eqA].LOW
	mov	dx,[eqB].LOW
	mov	ax,[eqA].HIW
	cmp	ax,[eqB].HIW
	jmp	bx
evalEQ:	jne	evalF
	cmp	cx,dx
	jne	evalF
	jmp	short evalT
evalNE:	jne	evalT
	cmp	cx,dx
	jne	evalT
	jmp	short evalF
evalLT:	jl	evalT
	jg	evalF
	cmp	cx,dx
	jl	evalT
	jmp	short evalF
evalGT:	jg	evalT
	jl	evalF
	cmp	cx,dx
	jg	evalT
	jmp	short evalF
evalLE:	jl	evalT
	jg	evalF
	cmp	cx,dx
	jle	evalT
	jmp	short evalF
evalGE:	jg	evalT
	jl	evalF
	cmp	cx,dx
	jge	evalT
	jmp	short evalF
evalT:	mov	ax,-1
	jmp	short evalX
evalF:	sub	ax,ax
evalX:	cwd
	mov	[eqA].LOW,ax
	mov	[eqA].HIW,dx
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
;	AX, BX, CX, DX
;
DEFPROC	evalNELong,FAR
	mov	bx,offset evalNE
	jmp	evalRelLong
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
;	AX, BX, CX, DX
;
DEFPROC	evalLTLong,FAR
	mov	bx,offset evalLT
	jmp	evalRelLong
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
;	AX, BX, CX, DX
;
DEFPROC	evalGTLong,FAR
	mov	bx,offset evalGT
	jmp	evalRelLong
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
;	AX, BX, CX, DX
;
DEFPROC	evalLELong,FAR
	mov	bx,offset evalLE
	jmp	evalRelLong
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
;	AX, BX, CX, DX
;
DEFPROC	evalGELong,FAR
	mov	bx,offset evalGE
	jmp	evalRelLong
ENDPROC	evalGELong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalShlLong
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
DEFPROC	evalShlLong,FAR
	ARGVAR	shlA,dword
	ARGVAR	shlB,dword
	ENTER
	mov	dx,[shlB].HIW
	test	dx,dx
	jnz	shl8
	mov	cx,[shlB].LOW
	cmp	cx,32
	jae	shl8
	mov	dx,[shlA].HIW
	mov	ax,[shlA].LOW
shl1:	shl	ax,1
	rcl	dx,1
	loop	shl1
	jmp	short shl9
shl8:	sub	ax,ax
	cwd
shl9:	mov	[shlA].LOW,ax
	mov	[shlA].HIW,dx
	LEAVE
	ret	4
ENDPROC	evalShlLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalShrLong
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
DEFPROC	evalShrLong,FAR
	ARGVAR	shrA,dword
	ARGVAR	shrB,dword
	ENTER
	mov	dx,[shrB].HIW
	test	dx,dx
	jnz	shl8
	mov	cx,[shrB].LOW
	cmp	cx,32
	jae	shl8
	mov	dx,[shrA].HIW
	mov	ax,[shrA].LOW
shr1:	sar	dx,1
	rcr	ax,1
	loop	shr1
	jmp	short shl9
ENDPROC	evalShrLong

CODE	ENDS

	end
