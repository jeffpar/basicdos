;
; BASIC-DOS Function Tests
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
	sub	dx,dx
s1:	PRINTF	<"sleeping %dms...">,dx
	mov	ax,DOS_UTL_SLEEP
	int	21h
	PRINTF	<13,10,"feeling refreshed!",13,10>
	add	dx,2000
	cmp	dx,8000
	jbe	s1
	int	20h
ENDPROC	main

;
; COMHEAP 0 means we don't need a heap, but the system will still allocate
; a minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
