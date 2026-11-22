;
; BASIC-DOS MSG Library
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; MSG.DLL is an NE library (see MSG.DEF) with the one function of OS/2's MSG
; module that LINK386 imports; see DOSCALLS.ASM for how these libraries are
; found and how their functions are called.
;
	DOSFUNC equ 1
	include	macros.inc
	include	dosapi.inc

CODE	segment word public 'CODE'

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosTrueGetMessage (ordinal 2)
;
; A program calls DosGetMessage, which its linker's library supplies: that
; adds a pointer to the program's own message segment and jumps here.  OS/2
; looks for the message there and then in the message file (eg, OSO001.MSG,
; for OS/2's own messages).  BASIC-DOS has no message files, and LINK386's
; message segment is empty, so no message is ever found.
;
; Inputs:
;	[BP+28] -> table of pointers to insertion strings (far pointer)
;	[BP+26] = # of insertion strings
;	[BP+22] -> buffer for the message (far pointer)
;	[BP+20] = size of the buffer
;	[BP+18] = message number
;	[BP+14] -> message file's name (far pointer)
;	[BP+10] -> where to store the message's length (far pointer)
;	[BP+6] -> the program's message segment (far pointer)
;
; Outputs:
;	AX = ERR_NOFILE (and the length stored is 0)
;
DEFPROC	DOSTRUEGETMESSAGE,FAR
	push	bp
	mov	bp,sp
	push	di
	push	es
	les	di,[bp+10]
	sub	ax,ax
	stosw
	mov	al,ERR_NOFILE
	pop	es
	pop	di
	pop	bp
	ret	26
ENDPROC	DOSTRUEGETMESSAGE

CODE	ends

	end
