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
	sub	cx,cx
	mov	dx,offset filespec
	mov	ah,DOS_DSK_FFIRST
	int	21h
	jnc	f1
	PRINTF	<"unable to find %s: %d",13,10>,dx,ax
	jmp	short s1

f1:	lea	ax,ds:[80h].FFB_NAME
	mov	dx,ds:[80h].FFB_DATE
	mov	cx,ds:[80h].FFB_TIME
	PRINTF	<"%-12s %.3W %.3F-%02D-%02X %2G:%02N%A",13,10>,ax,dx,dx,dx,dx,cx,cx,cx
	mov	ah,DOS_DSK_FNEXT
	int	21h
	jnc	f1

s1:	sub	dx,dx
s2:	PRINTF	<"sleeping %dms...">,dx
	mov	ax,DOS_UTL_SLEEP
	int	21h
	PRINTF	<13,10,"feeling refreshed!",13,10>
	add	dx,1000
	cmp	dx,10000
	jbe	s2
	int	20h
ENDPROC	main

filespec	db	"*.*",0

;
; COMHEAP 0 means we don't need a heap, but the system will still allocate
; a minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
