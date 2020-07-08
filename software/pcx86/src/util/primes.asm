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

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:STACK
DEFPROC	main

	LOCVAR	maxDivisor,word
	LOCVAR	maxSquared,word
	LOCVAR	advSquared,word
	ENTER

	int 3
	mov	ax,CODE
	mov	ds,ax
	mov	es,ax
	ASSUME	DS:CODE, ES:CODE

	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	mov	dx,offset ctrlc
	int	21h
;
; For each number, we test all the (odd) divisors up to the square root of
; the number, and if none divide it perfectly, then the number must be prime.
;
; Since we're working through the dividends incrementally, we can simply
; increment maxDivisor whenever the next dividend reaches the square of
; maxDivisor (maxSquared) and then advance maxSquared to next square by adding
; the next odd number (since square numbers are separated by sequential odd
; numbers).
;
	mov	[maxDivisor],2
	mov	[maxSquared],4	; current square of maxDivisor
	mov	[advSquared],5	; next odd amount to advance maxSquared by

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

m3:	PRINTF	<"%7u">,bx
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
	mov	ax,DOS_PSP_EXIT SHL 8
	int	21h
ENDPROC	main

DEFPROC	ctrlc,FAR
	PRINTF	<"CTRL-C detected, aborting...",13,10>
	stc
	ret
ENDPROC	ctrlc

CODE	ENDS

STACK	SEGMENT	STACK
	dw	512 dup (?)
STACK	ENDS

	end	main
