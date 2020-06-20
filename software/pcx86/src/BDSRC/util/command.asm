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
	cmp	ds:[PSP_PFT][0],1
	ja	m1
	mov	ah,DOS_TTY_INPUT
	mov	dx,offset input
	int	21h
m1:	mov	dx,36
	sub	cx,cx
	mov	ax,DOS_UTIL_SLEEP
	int	21h
	jmp	main
	int	20h
ENDPROC	main

input	db	32,?,32 dup (?)

CODE	ENDS

	end	main
