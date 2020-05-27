;
; BASIC-DOS Driver/Application Interfaces
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	bios.inc

INT_DOS_EXIT	equ	20h
INT_DOS_CALL	equ	21h

DOS_EXIT	equ	00h	; same function as INT 20h
DOS_TTY_ECHO	equ	01h	; read KBD and echo (AL := char)
DOS_TTY_WRITE	equ	02h	; write SCR (DL = char)
DOS_AUX_READ	equ	03h	; read AUX (AL := char)
DOS_AUX_WRITE	equ	04h	; write AUX (DL = char)
DOS_PRN_WRITE	equ	05h	; write PRN (DL = char)
DOS_TTY_IO	equ	06h	; read KBD (AL := char) or write SCR (DL = char)
DOS_TTY_IN	equ	07h	; read KBD (AL := char)
DOS_TTY_READ	equ	08h	; read KBD (AL := char)
DOS_TTY_PRINT	equ	09h	; write (DS:DX) string to SCR
DOS_TTY_INPUT	equ	0Ah	; read (DS:DX) line from KBD
DOS_TTY_STATUS	equ	0Bh	; get KBD status (AL := 0 if nothing, or FFh)
DOS_TTY_FLUSH	equ	0Ch	; flush and invoke 01h, 06h, 07h, 08h, or 0Ah

DOS_OPEN	equ	3Dh	; TBD

REG_FRAME	struc
REG_ES		dw	?
REG_DS		dw	?
REG_BP		dw	?
REG_DX		dw	?
REG_CX		dw	?
REG_BX		dw	?
REG_AX		dw	?
REG_IP		dw	?
REG_CS		dw	?
REG_FL		dw	?
REG_FRAME	ends
