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

VERSION_MAJOR	equ	0
VERSION_MINOR	equ	0
VERSION_REV	equ	2

VERSION_STR	macro
		db	'0' + VERSION_MAJOR
		db	'.'
		db	'0' + VERSION_MINOR
		db	'0' + VERSION_REV
		endm
;
; DOS interrupt vector table (IVT) usage
;
INT_DOSTERM	equ	20h	; terminate program
INT_DOSFUNC	equ	21h	; DOS function interface
INT_DOSEXRET	equ	22h	; exec return address
INT_DOSCTRLC	equ	23h	; CTRL-C notification address
INT_DOSERROR	equ	24h	; critical error notification address
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

;
; DOS functions
;
DOS_PSP_TERM	equ	00h	; same function as INT 20h
DOS_TTY_ECHO	equ	01h	; read char (AL) from CON and echo
DOS_TTY_WRITE	equ	02h	; write char (DL) to CON
DOS_AUX_READ	equ	03h	; read char (AL) from AUX
DOS_AUX_WRITE	equ	04h	; write char (DL) to AUX
DOS_PRN_WRITE	equ	05h	; write char (DL) to PRN
DOS_TTY_IO	equ	06h	; read (AL) from CON or write (DL) to CON
DOS_TTY_IN	equ	07h	; read char (AL) from CON
DOS_TTY_READ	equ	08h	; read char (AL) from CON; checks CTRLC
DOS_TTY_PRINT	equ	09h	; write string (DS:DX) to CON
DOS_TTY_INPUT	equ	0Ah	; read line (DS:DX) from CON
DOS_TTY_STATUS	equ	0Bh	; get CON status (AL = 0 if nothing, or FFh)
DOS_TTY_FLUSH	equ	0Ch	; flush and invoke 01h, 06h, 07h, 08h, or 0Ah
DOS_DSK_RESET	equ	0Dh	; disk reset

DOS_UTL		equ	18h
DOS_UTL_STRLEN	equ   1800h	; return string (DS:SI) length (AX)
DOS_UTL_ATOI	equ   1801h	; convert string (DS:SI) to number (AX)
DOS_UTL_ITOA	equ   1802h	; convert number (DX:SI) to string (ES:DI)
DOS_UTL_PRINTF	equ   1803h	; printf to console
DOS_UTL_SPRINTF	equ   1804h	; sprintf to buffer (ES:DI)
DOS_UTL_GETDEV	equ   1805h	; get DDH (ES:DI) for device (DS:SI)
DOS_UTL_IOCTL	equ   1806h	; issue IOCTL to device (ES:DI)
DOS_UTL_LOAD	equ   1807h	; load program (DS:DX) into SCB (CL)
DOS_UTL_START	equ   1808h	; start SCB (CL)
DOS_UTL_STOP	equ   1809h	; stop SCB (CL)
DOS_UTL_UNLOAD	equ   180Ah	; unload program from SCB (CL)
DOS_UTL_YIELD	equ   180Bh	; yield
DOS_UTL_SLEEP	equ   180Ch	; sleep DX milliseconds
DOS_UTL_WAIT	equ   180Dh	; wait until end wait
DOS_UTL_ENDWAIT	equ   180Eh	; end wait
DOS_UTL_HOTKEY	equ   180Fh	; CON detected hotkey (DL) (eg, CTRLC, CTRLP)
DOS_UTL_STDLEN	equ   1824h	; like STRLEN but with 24h as terminator

DOS_MSC_SETVEC	equ	25h	; set vector (AL) to addr (DS:DX)
DOS_PSP_CREATE	equ	26h	; create PSP (DX = segment)
DOS_MSC_CTRLC	equ	33h	; get/set CTRLC state
DOS_MSC_GETVEC	equ	35h	; get vector (AL) addr (ES:BX)
DOS_HDL_OPEN	equ	3Dh	; open handle for device/file (DS:DX)
DOS_HDL_CLOSE	equ	3Eh	; close handle (BX)
DOS_HDL_READ	equ	3Fh	; read (CX) bytes at (DS:DX) with handle (BX)
DOS_HDL_WRITE	equ	40h	; write (CX) bytes at (DS:DX) with handle (BX)
DOS_HDL_SEEK	equ	42h	; seek to (CX:DX) w/method (AL) and handle (BX)

DOS_MEM_ALLOC	equ	48h	; allocate memory
DOS_MEM_FREE	equ	49h	; free memory
DOS_MEM_REALLOC	equ	4Ah	; reallocate memory

DOS_PSP_EXEC	equ   4B00h	; load program (DS:DX) with EPB (ES:BX)
DOS_PSP_SET	equ	50h	; set current PSP (BX)
DOS_PSP_GET	equ	51h	; get current PSP (BX)

IFNDEF DEBUG
REG_CHECK	equ	0	; no REG_FRAME marker on stack
ELSE
REG_CHECK	equ	1	; add a DEBUG marker before REG_FRAME
ENDIF

WS_CTRLC	struc		; REG_WS workspace when used for CTRLC
JMP_IP		dw	?	; 00h
JMP_CS		dw	?	; 02h
RET_IP		dw	?	; 04h
RET_CS		dw	?	; 06h
RET_FL		dw	?	; 08h
WS_CTRLC	ends

WS_TEMP		struc		; REG_WS workspace when used as temp registers
TMP_AX		dw	?	; 00h
TMP_BX		dw	?	; 02h
TMP_CX		dw	?	; 04h
TMP_DX		dw	?	; 06h
TMP_ES		dw	?	; 08h
WS_TEMP		ends

REG_FRAME	struc		; register frame created by dos_func
REG_BP		dw	?	; 00h
REG_DI		dw	?	; 02h (in case anyone wants to use LES DI)
REG_ES		dw	?	; 04h
REG_SI		dw	?	; 06h (in case anyone wants to use LDS SI)
REG_DS		dw	?	; 08h
REG_DX		dw	?	; 0Ah
REG_CX		dw	?	; 0Ch
REG_BX		dw	?	; 0Eh
REG_AX		dw	?	; 10h
REG_WS		dw (size WS_TEMP) SHR 1 dup (?)
REG_IP		dw	?	; 1Ch
REG_CS		dw	?	; 1Eh
REG_FL		dw	?	; 20h
REG_FRAME	ends

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
; SIDEBAR: To miminize the amount of per-process information in the IVT,
; we'll pretend all the apps we care about are well-behaved, which means if
; they want to set any of the ABORT/CTRLC/ERROR handlers, they'll use the
; DOS_SET_VECTOR function, which will update the SCB vectors below, rather
; than the actual IVT vectors.
;
; That will save scb_switch from having to save/restore IVT vectors on every
; switch.  If it turns out I care about running non-well-behaved apps later,
; then I'll add some vector-checking logic at appropriate checkpoints (or,
; worst case, copy selected vectors in/out on session switches -- yuck).
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
SCB_EXRET	dd	?	; 10h: current EXRET handler
SCB_CTRLC	dd	?	; 14h: current CTRLC handler
SCB_ERROR	dd	?	; 18h: current ERROR handler
SCB_DTA		dd	?	; 1Ch: current DTA (Disk Transfer Address)
SCB		ends

SCBSIG		equ	'S'

SCSTAT_INIT	equ	01h	; set if SCB initialized
SCSTAT_LOAD	equ	02h	; set if session has loaded a program
SCSTAT_START	equ	04h	; set if session program can be started

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

;
; Program Segment Prefix (PSP)
;
PSP		struc
PSP_EXIT	dw	?	; 00h: INT 20h
PSP_PARAS	dw	?	; 02h: paragraphs available
PSP_SCB		db	?	; 04h: SCB # (normally unused in "real" DOS)
PSP_FARCALL	db	?	; 05h: far call (9Ah)
PSP_SIZE	dw	?	; 06h: size of PSP segment
PSP_FCSEG	dw	?	; 08h: far call segment
PSP_EXRET	dd	?	; 0Ah: original INT 22h vector
PSP_CTRLC	dd	?	; 0Eh: original INT 23h vector
PSP_ERROR	dd	?	; 12h: original INT 24h vector
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
; Exec Parameter Block (EPB); see
;
EPB		struc
EPB_ENVSEG	dw	?	; 00h: segment of environment (0 to copy parent)
EPB_CMDLINE	dd	?	; 02h: pointer to well-formed command-line
EPB_FCB1	dd	?	; 06h: pointer to FCB for PSP_FCB1
EPB_FCB2	dd	?	; 0Ah: pointer to FCB for PSP_FCB2
EPB		ends

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

BASICDOS_SIG	equ	'DB'	; BASIC-DOS signature word ("BD")
