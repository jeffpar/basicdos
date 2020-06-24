;
; BASIC-DOS Command Interpreter
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
	PRINTF	<"hello world",13,10>
	mov	ah,DOS_TTY_INPUT
	mov	dx,offset input
	int	21h
	jmp	main
ENDPROC	main

input	db	32		; the rest of input doesn't need initialization

	COMHEAP	4096		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
