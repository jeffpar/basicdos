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
	sub	bp,bp		; BP = # of primes this line
	mov	bx,2		; BX = first dividend
m1:	mov	cx,2		; CX = first divisor
m2:	mov	ax,bx
	cmp	cx,ax		; is divisor too large now?
	jae	m3		; yes, must be a prime
	sub	dx,dx
	div	cx		; AX = quotient, DX = remainder
	test	dx,dx
	jz	m4		; no remainder, so AX is not a prime
	inc	cx
	jmp	m2		; try next divisor

m3:	PRINTF	<"%u ">,ax
	inc	bp
	cmp	bp,5
	jb	m4
	PRINTF	<13,10>
	sub	bp,bp

m4:	inc	bx		; BX = next dividend
	jmp	m1
ENDPROC	main

;
; COMHEAP 0 means we don't need a heap, but the system will still allocate
; a minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
