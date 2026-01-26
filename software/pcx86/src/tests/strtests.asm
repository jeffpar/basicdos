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

	EXTNEAR	<bd_init>

        ASSUME  CS:DOS, DS:DOS, ES:DOS, SS:DOS

	org	100h

DEFPROC	main
;
; Ready for string testing...
;
	DBGBRK
	PRINTF	<"hello world!",13,10>
;
; In BASIC-DOS, we could also use INT 20h here, but PC DOS requires that CS
; contain the PSP being terminated when calling INT 20h (BASIC-DOS does not).
;
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
	ret			; a return is not necessary, but just in case
ENDPROC	main

;
; COMHEAP 0 means we don't need a heap, but BASIC-DOS will still allocate a
; minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

DOS	ends

	end
