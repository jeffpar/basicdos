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
	; mov	dx,offset msg
	; mov	ah,DOS_TTY_PRINT
	; int	21h
	PRINTF	<"hello world",13,10>
	mov	dx,36
	sub	cx,cx
	mov	ax,DOS_UTIL_SLEEP
	int	21h
	jmp	main
	int	20h
ENDPROC	main

; msg	db	"hello world",13,10,'$'

CODE	ENDS

	end	main
