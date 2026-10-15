;
; BASIC-DOS Sleep Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: SLEEP seconds
;
; Waits the specified number of seconds (CTRL-C stops it early).  If no
; number is specified, a usage message is displayed and the exit code is 1.
;
	include	macros.inc
	include	dosapi.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	si,PSP_CMDTAIL+1
s1:	lodsb
	cmp	al,' '			; skip leading whitespace
	je	s1
	cmp	al,9
	je	s1
	dec	si
	DOSUTIL	ATOI32D			; DX:AX = # of seconds
	jc	s8			; no digits
	test	dx,dx
	js	s8			; negative
	mov	bx,1000
	xchg	cx,ax			; CX = low word of seconds
	xchg	ax,dx
	mul	bx
	xchg	cx,ax			; CX = high word * 1000
	mul	bx			; DX:AX = low word * 1000
	add	cx,dx
	xchg	dx,ax			; CX:DX = # of milliseconds
	DOSUTIL	SLEEP
	int	20h

s8:	PRINTF	<"Usage: SLEEP seconds",13,10>
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	main

;
; COMHEAP 0 means we don't need a heap, but BASIC-DOS will still allocate a
; minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
