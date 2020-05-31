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

DOS_MALLOC	equ	48h	; allocate memory
DOS_MFREE	equ	49h	; free memory

REG_FRAME	struc
REG_ES		dw	?
REG_DS		dw	?
REG_BP		dw	?
REG_DI		dw	?
REG_SI		dw	?
REG_DX		dw	?
REG_CX		dw	?
REG_BX		dw	?
REG_AX		dw	?
REG_IP		dw	?
REG_CS		dw	?
REG_FL		dw	?
REG_FRAME	ends

FL_CARRY	equ	0001h

REG_AL		equ 	REG_AX + LO
REG_AH		equ 	REG_AX + HI
REG_BL		equ 	REG_BX + LO
REG_BH		equ 	REG_BX + HI
REG_CL		equ 	REG_CX + LO
REG_CH		equ 	REG_CX + HI
REG_DL		equ 	REG_DX + LO
REG_DH		equ 	REG_DX + HI

;
; Process Control Block (PCB)
;
PCB		struc
PCB_STATE	dw	?	; 00h: TBD
PCB_WAITID	dw	?	; 02h: Wait ID if waiting, 0 if running
PCB_STACK	dd	?	; 02h: pointer to process stack
PCB		ends

;
; Memory Control Block (MCB)
;
MCB		struc
MCB_SIG		db	?	; 00h: either MCB_NORMAL or MCB_LAST
MCB_OWNER	dw	?	; 01h: PSP segment owner (8 if owner is DOS)
MCB_PARAS	dw	?	; 03h: size of block in paragraphs
MCB_RESERVED	db     11 dup(?); 05h: reserved
MCB		ends

MCB_NORMAL	equ	4Dh
MCB_LAST	equ	5Ah

;
; System File Block (SFB)
;
; It would be tempting to call this, say, a File Control Block, but somebody
; already took the FCB name.
;
SFB		struc
SFB_HANDLES	db	?	; 00h: number of associated handles
SFB_MODE	db	?	; 01h: open mode
SFB_DRIVER	dd	?	; 02h: pointer to device driver
SFB_CONTEXT	dw	?	; 06h: segment of device context, if any
SFB		ends

ERR_INVALID	equ	1
ERR_NOFILE	equ	2
ERR_NOPATH	equ	3
ERR_MAXFILES	equ	4
ERR_ACCDENIED	equ	5
ERR_BADHANDLE	equ	6
ERR_BADMCB	equ	7	; invalid MCB found
ERR_NOMEM	equ	8	; insufficient memory
ERR_BADADDR	equ	9	; invalid memory segment
