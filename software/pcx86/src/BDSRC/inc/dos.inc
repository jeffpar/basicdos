;
; BASIC-DOS Driver/Application Interfaces
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dev.inc

INT_DOSEXIT	equ	20h
INT_DOSFUNC	equ	21h

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

DOS_OPEN	equ	3Dh	; open handle for device/file (DS:DX)

DOS_ALLOC	equ	48h	; allocate memory
DOS_FREE	equ	49h	; free memory

REG_FRAME	struc
REG_BP		dw	?
REG_DI		dw	?
REG_ES		dw	?
REG_SI		dw	?
REG_DS		dw	?
REG_DX		dw	?
REG_CX		dw	?
REG_BX		dw	?
REG_AX		dw	?
REG_IP		dw	?
REG_CS		dw	?
REG_FL		dw	?
REG_FRAME	ends

FL_CARRY	equ	0001h

REG_AL		equ 	(REG_AX.LO)
REG_AH		equ 	(REG_AX.HI)
REG_BL		equ 	(REG_BX.LO)
REG_BH		equ 	(REG_BX.HI)
REG_CL		equ 	(REG_CX.LO)
REG_CH		equ 	(REG_CX.HI)
REG_DL		equ 	(REG_DX.LO)
REG_DH		equ 	(REG_DX.HI)

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
MCB_SIG		db	?	; 00h: either MCBSIG_NEXT or MCBSIG_LAST
MCB_OWNER	dw	?	; 01h: PSP segment owner (8 if owner is DOS)
MCB_PARAS	dw	?	; 03h: size of block in paragraphs
MCB_RESERVED	db     11 dup(?); 05h: reserved
MCB		ends

MCBSIG_NEXT	equ	4Dh
MCBSIG_LAST	equ	5Ah

;
; System File Block (SFB)
;
; System file handles are indexes into the SFB_TABLE, whereas process file
; handles are indexes into a PSP's handle table.
;
SFB		struc
SFB_NAME	db    11 dup (?); 00h: filename (E5=free,00=end)
SFB_ATTR	db	?	; 0Bh: attribute bits (see below)
SFB_DRIVER	dd	?	; 0Ch: driver pointer
SFB_CONTEXT	dw	?	; 10h: driver context
SFB_HANDLES	db	?	; 12h: number of process handles
SFB_MODE	db	?	; 13h: open mode
SFB_RESERVED	dw	?	; 14h
SFB_TIME	dw	?	; 16h: time of last write (see below)
SFB_DATE	dw	?	; 18h: date of last write (see below)
SFB_CLN		dw	?	; 1Ah: first cluster number of file
SFB_SIZE	dd	?	; 1Ch: file size
SFB		ends

MODE_ACC_READ	equ	00h
MODE_ACC_WRITE	equ	01h
MODE_ACC_BOTH	equ	02h
MODE_COMPAT	equ	00h
MODE_DENY_BOTH	equ	10h
MODE_DENY_WRITE	equ	20h
MODE_DENY_READ	equ	30h
MODE_DENY_NONE	equ	40h
MODE_INHERIT	equ	80h

ERR_INVALID	equ	1
ERR_NOFILE	equ	2
ERR_NOPATH	equ	3
ERR_MAXFILES	equ	4	; too many open files
ERR_ACCDENIED	equ	5
ERR_BADHANDLE	equ	6
ERR_BADMCB	equ	7	; invalid MCB found
ERR_NOMEM	equ	8	; insufficient memory
ERR_BADADDR	equ	9	; invalid memory segment

;
; Utility function numbers
;
DOSUTIL_STRLEN	equ	1800h
DOSUTIL_DECIMAL	equ	1801h
