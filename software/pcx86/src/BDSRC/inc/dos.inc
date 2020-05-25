	include	bios.inc

INT_DOS_EXIT	EQU	20h
INT_DOS_CALL	EQU	21h

DOS_EXIT	EQU	00h	; same function as INT 20h
DOS_TTY_ECHO	EQU	01h	; read KBD and echo (AL := char)
DOS_TTY_WRITE	EQU	02h	; write SCR (DL = char)
DOS_AUX_READ	EQU	03h	; read AUX (AL := char)
DOS_AUX_WRITE	EQU	04h	; write AUX (DL = char)
DOS_PRN_WRITE	EQU	05h	; write PRN (DL = char)
DOS_TTY_IO	EQU	06h	; read KBD (AL := char) or write SCR (DL = char)
DOS_TTY_IN	EQU	07h	; read KBD (AL := char)
DOS_TTY_READ	EQU	08h	; read KBD (AL := char)
DOS_TTY_PRINT	EQU	09h	; write (DS:DX) string to SCR
DOS_TTY_INPUT	EQU	0Ah	; read (DS:DX) line from KBD
DOS_TTY_STATUS	EQU	0Bh	; get KBD status (AL := 0 if nothing, or FFh)
DOS_TTY_FLUSH	EQU	0Ch	; flush and invoke 01h, 06h, 07h, 08h, or 0Ah

DOS_OPEN	EQU	3Dh	; TBD

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
