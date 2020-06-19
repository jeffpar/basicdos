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

INT_DOSTERM	equ	20h	; terminate program
INT_DOSFUNC	equ	21h	; DOS function interface
INT_DOSABORT	equ	22h	; handler for program termination notification
INT_DOSCTRLC	equ	23h	; handler for CTRL-C notification
INT_DOSERROR	equ	24h	; handler for critical error notification
INT_DISKREAD	equ	25h	; absolute disk read
INT_DISKWRITE	equ	26h	; absolute disk write
INT_DOSTSR	equ	27h	; terminate-and-stay-resident
INT_DOSIDLE	equ	28h	; idle notification
INT_FASTCON	equ	29h	; fast console I/O (installed by CON driver)
INT_DOSNET	equ	2Ah	; network check
INT_DOSRES1	equ	2Bh	; reserved
INT_DOSRES2	equ	2Ch	; reserved
INT_DOSRES3	equ	2Dh	; reserved
INT_DOSCMD	equ	2Eh	; COMMAND.COM operation
INT_DOSMULTI	equ	2Fh	; multiplex function interface
INT_DOSCALL5	equ	30h	; vector has FAR JMP (overwrites vector 31h too)

DOS_PSP_QUIT	equ	00h	; same function as INT 20h
DOS_TTY_ECHO	equ	01h	; read CON and echo (AL := char)
DOS_TTY_WRITE	equ	02h	; write CON (DL = char)
DOS_AUX_READ	equ	03h	; read AUX (AL := char)
DOS_AUX_WRITE	equ	04h	; write AUX (DL = char)
DOS_PRN_WRITE	equ	05h	; write PRN (DL = char)
DOS_TTY_IO	equ	06h	; read CON (AL := char) or write CON (DL = char)
DOS_TTY_IN	equ	07h	; read CON (AL := char)
DOS_TTY_READ	equ	08h	; read CON (AL := char)
DOS_TTY_PRINT	equ	09h	; write (DS:DX) string to CON
DOS_TTY_INPUT	equ	0Ah	; read (DS:DX) line from CON
DOS_TTY_STATUS	equ	0Bh	; get CON status (AL := 0 if nothing, or FFh)
DOS_TTY_FLUSH	equ	0Ch	; flush and invoke 01h, 06h, 07h, 08h, or 0Ah

DOS_UTIL_STRLEN		equ	1800h	; return str (DS:SI) len (AX)
DOS_UTIL_ATOI		equ	1801h	; convert str (DS:SI) to num (AX)
DOS_UTIL_ITOA		equ	1802h	; convert num (DX:SI) to str (ES:DI)
DOS_UTIL_PRINTF		equ	1803h	; printf to console
DOS_UTIL_SPRINTF	equ	1804h	; sprintf to buffer (ES:DI)
DOS_UTIL_GETDEV		equ	1805h	; get DDH (ES:DI) for device (DS:SI)
DOS_UTIL_IOCTL		equ	1806h	; issue IOCTL to device (ES:DI)
DOS_UTIL_LOAD		equ	1807h	; load program (DS:DX) into SCB (CL)
DOS_UTIL_START		equ	1808h	; start SCB (CL)
DOS_UTIL_STOP		equ	1809h	; stop SCB (CL)
DOS_UTIL_UNLOAD		equ	180Ah	; unload program from SCB (CL)
DOS_UTIL_YIELD		equ	180Bh	; yield
DOS_UTIL_SLEEP		equ	180Ch	; sleep CX:DX ticks
DOS_UTIL_WAIT		equ	180Dh	; wait until end wait
DOS_UTIL_ENDWAIT	equ	180Eh	; end wait
DOS_UTIL_STDLEN		equ	1824h	; like STRLEN but with 24h as terminator

DOS_PSP_CREATE	equ	26h	; create PSP (DX = segment)
DOS_HDL_OPEN	equ	3Dh	; open handle for device/file (DS:DX)
DOS_HDL_CLOSE	equ	3Eh	; close handle (BX)
DOS_HDL_READ	equ	3Fh	; read (CX) bytes at (DS:DX) with handle (BX)
DOS_HDL_WRITE	equ	40h	; write (CX) bytes at (DS:DX) with handle (BX)
DOS_HDL_SEEK	equ	42h	; seek to (CX:DX) w/method (AL) and handle (BX)

DOS_MEM_ALLOC	equ	48h	; allocate memory
DOS_MEM_FREE	equ	49h	; free memory
DOS_MEM_REALLOC	equ	4Ah	; reallocate memory

DOS_PSP_SET	equ	50h	; set current PSP (BX)
DOS_PSP_GET	equ	51h	; get current PSP (BX)

REG_FRAME	struc		; register frame created by dos_func
REG_BP		dw	?
REG_DI		dw	?	; arranged for LES DI instructions
REG_ES		dw	?
REG_SI		dw	?	; arranged for LDS SI instructions
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
FL_ZERO		equ	0040h
FL_SIGN		equ	0080h
FL_TRAP		equ	0100h
FL_INTS		equ	0200h
FL_DOWN		equ	0400h
FL_OVFL		equ	0800h

REG_AL		equ 	(REG_AX.LO)
REG_AH		equ 	(REG_AX.HI)
REG_BL		equ 	(REG_BX.LO)
REG_BH		equ 	(REG_BX.HI)
REG_CL		equ 	(REG_CX.LO)
REG_CH		equ 	(REG_CX.HI)
REG_DL		equ 	(REG_DX.LO)
REG_DH		equ 	(REG_DX.HI)

;
; Session Control Block (SCB)
;
SCB		struc
SCB_STATUS	db	?	; 00h: SCB status
SCB_SFHCON	db	?	; 01h: SFH for CON
SCB_SFHAUX	db	?	; 02h: SFH for AUX
SCB_SFHPRN	db	?	; 03h: SFH for PRN
SCB_WAITID	dd	?	; 04h: wait ID if waiting, 0 if runnable
SCB_STACK	dd	?	; 08h: pointer to session stack
SCB_CURPSP	dw	?	; 0Ch: current PSP
SCB_CURDRV	db	?	; 0Eh: current drive #
SCB_RESERVED	db	?	; 0Fh (holds SCBSIG in DEBUG builds)
SCB		ends

SCBSIG		equ	'S'

SCSTAT_INIT	equ	01h	; set if initialized
SCSTAT_LOAD	equ	02h	; set if program is loaded

;
; Memory Control Block (MCB)
;
MCB		struc
MCB_SIG		db	?	; 00h: either MCBSIG_NEXT or MCBSIG_LAST
MCB_OWNER	dw	?	; 01h: owner (PSP segment if > 8)
MCB_PARAS	dw	?	; 03h: size of block in paragraphs
MCB_RESERVED	db     11 dup(?); 05h: reserved
MCB		ends

MCBSIG_NEXT	equ	4Dh
MCBSIG_LAST	equ	5Ah
MCBOWNER_NONE	equ	0	; free memory block
MCBOWNER_SYSTEM	equ	0008h	; owned by the system

;
; File Control Block (FCB)
;
FCB		struc
FCB_DRV		db	?	; 00h
FCB_NAME	db     11 dup(?); 01h
FCB_CURBLK	dw	?	; 0Ch
FCB_RECSIZE	dw	?	; 0Eh
FCB_FILESIZE	dd	?	; 10h
FCB_DATE	dw	?	; 14h
FCB_TIME	dw	?	; 16h
FCB		ends

;
; Program Segment Prefix (PSP)
;
PSP		struc
PSP_EXIT	dw	?	; 00h: INT 20h
PSP_PARAS	dw	?	; 02h: paragraphs available
PSP_UNUSED	db	?	; 04h
PSP_FARCALL	db	?	; 05h: far call (9Ah)
PSP_SIZE	dw	?	; 06h: size of PSP segment
PSP_FCSEG	dw	?	; 08h: far call segment
PSP_INT22	dd	?	; 0Ah: INT 22h vector
PSP_INT23	dd	?	; 0Eh: INT 23h vector
PSP_INT24	dd	?	; 12h: INT 24h vector
PSP_PARENT	dw	?	; 16h: PSP of parent
PSP_PFT		db     20 dup(?); 18h: Process File Table
PSP_ENVSEG	dw	?	; 2Ch
PSP_STACK	dd	?	; 2Eh
PSP_HDLFREE	dw	?	; 32h: available handles
PSP_HDLPTR	dd	?	; 34h: initially 0FFFF:0018h
PSP_SHAREPSP	dd	?	; 38h
PSP_RESERVED1	db     20 dup(?); 3Ch
PSP_DISPATCH	db	3 dup(?); 50h: INT 21h/RETF
PSP_RESERVED2	db	9 dup(?); 53h
PSP_FCB1	db     16 dup(?); 5Ch
PSP_FCB2	db     16 dup(?); 6ch
PSP_RESERVED3	db	4 dup(?); 7Ch
PSP_CMDLINE	db    128 dup(?); 80h
PSP		ends

SFH_NONE	equ	0FFh	; if this SFH is in a PFT entry, it's unused

;
; System File Block (SFB)
;
; For files, this is a superset of the directory entry (DIRENT).
;
; System File Handles (SFH) are indexes into the SFB table, whereas Process
; File Handles (PFH) are indexes into a PSP's Process File Table (PFT).
;
SFB		struc
SFB_NAME	db    11 dup (?); 00h: filename (E5=free,00=end)
SFB_ATTR	db	?	; 0Bh: attribute bits (see below)
SFB_DEVICE	dd	?	; 0Ch: device driver
SFB_CONTEXT	dw	?	; 10h: device context (1st cluster if file)
SFB_DRIVE	db	?	; 12h: drive #
SFB_MODE	db	?	; 13h: open mode
SFB_HANDLES	db	?	; 14h: number of process handles
SFB_RESERVED	db	?	; 15h (holds SFBSIG in DEBUG builds)
SFB_TIME	dw	?	; 16h: time of last write (see below)
SFB_DATE	dw	?	; 18h: date of last write (see below)
SFB_CLN		dw	?	; 1Ah: 1st cluster number of file
SFB_SIZE	dd	?	; 1Ch: file size
SFB_CURPOS	dd	?	; 20h: current file position
SFB_CURCLN	dw	?	; 24h: current cluster number
SFB		ends

SFBSIG		equ	'F'

MODE_ACC_READ	equ	00h
MODE_ACC_WRITE	equ	01h
MODE_ACC_BOTH	equ	02h
MODE_COMPAT	equ	00h
MODE_DENY_BOTH	equ	10h
MODE_DENY_WRITE	equ	20h
MODE_DENY_READ	equ	30h
MODE_DENY_NONE	equ	40h
MODE_INHERIT	equ	80h

SEEK_BEG	equ	0
SEEK_CUR	equ	1
SEEK_END	equ	2

;
; Predefined Process File Table (PFT) numbers
;
STDIN		equ	0
STDOUT		equ	1
STDERR		equ	2
STDAUX		equ	3
STDPRN		equ	4

ERR_INVALID	equ	1
ERR_NOFILE	equ	2
ERR_NOPATH	equ	3
ERR_MAXFILES	equ	4	; too many open files
ERR_ACCDENIED	equ	5
ERR_BADHANDLE	equ	6
ERR_BADMCB	equ	7	; invalid MCB found
ERR_NOMEM	equ	8	; insufficient memory
ERR_BADADDR	equ	9	; invalid memory segment
