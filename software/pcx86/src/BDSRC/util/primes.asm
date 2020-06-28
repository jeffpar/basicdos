;
; BASIC-DOS Primes Demo
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main

	LOCVAR	maxDivisor,word,1
	LOCVAR	maxSquared,word,1
	LOCVAR	advSquared,word,1
	ENTER

	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	mov	dx,offset ctrlc
	int	21h
;
; One simple rule is that if you haven't found a perfect divisor of a number
; before reaching the square root of that number, the number must be prime.
;
; Since we're working through the dividends incrementally, we can simply
; increment maxDivisor whenever the next dividend reaches the square of
; maxDivisor (maxSquared).  And while we could recalculate maxSquared
; each time maxDivisor changes, each successive square (ie, 9, 16, 25, 36)
; is just the sum of the previous square and the next odd number (advSquared).
;
	mov	[maxDivisor],2
	mov	[maxSquared],4	; current square of maxDivisor
	mov	[advSquared],5	; amount to advance maxSquared

	sub	si,si		; SI = # of primes this line

	mov	bx,2		; BX = first dividend

m1:	mov	cx,3		; CX = first (odd) divisor
m2:	cmp	cx,[maxDivisor]	; is divisor too large now?
	jae	m3		; yes, must be prime
	mov	ax,bx
	sub	dx,dx
	div	cx		; AX = quotient, DX = remainder
	test	dx,dx
	jz	m4		; no remainder, so AX is not a prime
	add	cx,2
	jmp	m2		; try next (odd) divisor

m3:	PRINTF	<"%u ">,bx
	inc	si
	cmp	si,5
	jb	m4
	PRINTF	<13,10>
	sub	si,si

m4:	inc	bx		; BX = next dividend
	jz	m9		; wrapped around to zero, all done
	or	bx,1		; bump it to odd if it isn't odd already

m5:	cmp	bx,[maxSquared]	; dividend below square of max divisor?
	jb	m1		; yes
	inc	[maxDivisor]
	mov	ax,[advSquared]
	add	[maxSquared],ax	; this wraps around, but so does the dividend
	add	ax,2
	mov	[advSquared],ax
	jmp	m1

m9:	LEAVE
	ret
ENDPROC	main

DEFPROC	ctrlc,FAR
	PRINTF	<"CTRL-C detected, aborting...",13,10>
	stc
	ret
ENDPROC	ctrlc

;
; COMHEAP 0 means we don't need a heap, but the system will still allocate
; a minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
