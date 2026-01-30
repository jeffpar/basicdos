;
; BASIC-DOS Miscellaneous String Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTWORD <cr,lf>
	EXTQUAD <pi,one>

        ASSUME  CS:DOS, DS:DOS, ES:DOS, SS:DOS

DEFPROC	main
;
; Start with some simple printf tests
;
	PRINTF	<"hello world!",13,10>
	PRINTF	<"CR is %d, LF is 0x%x",13,10>,CR,LF
;	PRINTF	<"ONE is %lf, PI is %lf",13,10>,ONE,PI

	PRINTF	<"Powers of two...",13,10>
	mov	cx,1
	sub	dx,dx
m1:	PRINTF	<"%lu",13,10>,cx,dx
	shl	cx,1
	rcl	dx,1
	mov	ax,cx
	or	ax,dx
	jnz	m1
	ret
ENDPROC	main

;
; COMHEAP 0 means we don't need a heap, but BASIC-DOS will still allocate a
; minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

DOS	ends

	end
