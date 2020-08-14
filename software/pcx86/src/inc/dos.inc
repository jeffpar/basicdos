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
VERSION_REV	equ	6

VERSION_STR	macro
		db	'0'+VERSION_MAJOR,'.','0'+VERSION_MINOR,'0'+VERSION_REV
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
DOS_DSK_SETDRV	equ	0Eh	; set current drive (DL), return # drives (AL)

DOS_UTL		equ	18h	; BASIC-DOS utility functions
DOS_UTL_STRLEN	equ   1800h	; return string (DS:SI) length (AX)
DOS_UTL_STRSTR	equ   1801h	; find string (DS:SI) in string (ES:DI)
DOS_UTL_STRUPR	equ   1803h	; upper-case string (DS:SI)
DOS_UTL_PRINTF	equ   1804h	; printf to console
DOS_UTL_DPRINTF	equ   1805h	; printf to DEBUG context, if any
DOS_UTL_SPRINTF	equ   1806h	; sprintf to buffer (ES:DI)
DOS_UTL_ATOI16	equ   1807h	; convert string (DS:SI) to number (AX)
DOS_UTL_ATOI32	equ   1808h	; convert string (DS:SI) to number (AX)
DOS_UTL_ITOA	equ   1809h	; convert number (DX:SI) to string (ES:DI)
DOS_UTL_TOKIFY1	equ   180Bh	; tokenize string (DS:SI) using GENERIC syntax
DOS_UTL_TOKIFY2	equ   180Ch	; tokenize string (DS:SI) using BASIC syntax
DOS_UTL_TOKID	equ   180Dh	; convert string (DS:SI) into token ID
DOS_UTL_GETDEV	equ   1810h	; get DDH (ES:DI) for device (DS:SI)
DOS_UTL_IOCTL	equ   1811h	; issue IOCTL to device (ES:DI)
DOS_UTL_LOAD	equ   1812h	; load program (DS:DX) into SCB (CL)
DOS_UTL_START	equ   1813h	; start SCB (CL)
DOS_UTL_STOP	equ   1814h	; stop SCB (CL)
DOS_UTL_UNLOAD	equ   1815h	; unload program from SCB (CL)
DOS_UTL_YIELD	equ   1816h	; yield
DOS_UTL_SLEEP	equ   1817h	; sleep DX milliseconds
DOS_UTL_WAIT	equ   1818h	; wait until end wait
DOS_UTL_ENDWAIT	equ   1819h	; end wait
DOS_UTL_HOTKEY	equ   181Ah	; CON detected hotkey (DL) (eg, CTRLC, CTRLP)
DOS_UTL_LOCK	equ   181Bh	; lock current SCB
DOS_UTL_UNLOCK	equ   181Ch	; unlock current SCB
DOS_UTL_QRYMEM	equ   181Dh	; query memory block N (CL)
DOS_UTL_QRYHDL	equ   181Eh	; query system file handle N (CL)
DOS_UTL_ABORT	equ   181Fh	; abort with exit code (DL) and exit type (DH)
DOS_UTL_STDLEN	equ   1824h	; like STRLEN but w/24h (dollar) as terminator

DOS_DSK_GETDRV	equ	19h	; get current drive (AL)
DOS_DSK_SETDTA	equ	1Ah	; set DTA (DS:DX)
DOS_MSC_SETVEC	equ	25h	; set vector (AL) to addr (DS:DX)
DOS_PSP_CREATE	equ	26h	; create PSP (DX = segment)
DOS_DSK_GETDTA	equ	2Fh	; get DTA (ES:BX)
DOS_DSK_GETDPB	equ	32h	; get DPB (DS:BX, AL=FFh if invalid drive)
DOS_MSC_CTRLC	equ	33h	; get/set CTRLC state
DOS_MSC_GETVEC	equ	35h	; get vector (AL) addr (ES:BX)
DOS_DSK_GETINFO	equ	36h	; get disk info; eg, available clusters (BX)
DOS_MSC_GETSWC	equ   3700h	; get switch char (DL)
DOS_MSC_SETSWC	equ   3701h	; set switch char (DL)
DOS_HDL_OPEN	equ	3Dh	; open handle for device/file (DS:DX)
DOS_HDL_CLOSE	equ	3Eh	; close handle (BX)
DOS_HDL_READ	equ	3Fh	; read (CX) bytes at (DS:DX) with handle (BX)
DOS_HDL_WRITE	equ	40h	; write (CX) bytes at (DS:DX) with handle (BX)
DOS_HDL_SEEK	equ	42h	; seek to (CX:DX) w/method (AL) and handle (BX)
DOS_HDL_IOCTL	equ   	44h	; send device request (AL) for handle (BX)

DOS_MEM_ALLOC	equ	48h	; allocate (BX) paras (returns segment AX)
DOS_MEM_FREE	equ	49h	; free segment (ES)
DOS_MEM_REALLOC	equ	4Ah	; reallocate size of segment (ES) to paras (BX)

DOS_PSP_EXEC	equ   4B00h	; load program (DS:DX) with EPB (ES:BX)
DOS_PSP_EXIT	equ	4Ch	; exit program with return code (AL)
DOS_PSP_RETCODE	equ	4Dh	; return exit code (AL) and exit type (AH)

DOS_DSK_FFIRST	equ	4Eh	; find first filespec (DS:DX) with attr (CX)
DOS_DSK_FNEXT	equ	4Fh	; find next filespec (DTA)

DOS_PSP_SET	equ	50h	; set current PSP (BX)
DOS_PSP_GET	equ	51h	; get current PSP (BX)

IFNDEF DEBUG
REG_CHECK	equ	0	; no REG_FRAME marker on stack
ELSE
REG_CHECK	equ	2	; add a DEBUG marker before REG_FRAME
ENDIF

WS_TEMP		struc		; REG_WS workspace used for CTRLC dispatcing
JMP_IP		dw	?	; 00h
JMP_CS		dw	?	; 02h
RET_IP		dw	?	; 04h
RET_CS		dw	?	; 06h
RET_FL		dw	?	; 08h
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

REG_AL		equ 	REG_AX.LO
REG_AH		equ 	REG_AX.HI
REG_BL		equ 	REG_BX.LO
REG_BH		equ 	REG_BX.HI
REG_CL		equ 	REG_CX.LO
REG_CH		equ 	REG_CX.HI
REG_DL		equ 	REG_DX.LO
REG_DH		equ 	REG_DX.HI

;
; Temp register definitions: an alternate use of the REG_WS workspace
;
TMP_AX		equ	REG_WS.JMP_IP
TMP_BX		equ	REG_WS.JMP_CS
TMP_CX		equ	REG_WS.RET_IP
TMP_DX		equ	REG_WS.RET_CS
TMP_ES		equ	REG_WS.RET_FL

TMP_AL		equ	TMP_AX.LO
TMP_AH		equ	TMP_AX.HI
TMP_BL		equ	TMP_BX.LO
TMP_BH		equ	TMP_BX.HI
TMP_CL		equ	TMP_CX.LO
TMP_CH		equ	TMP_CX.HI
TMP_DL		equ	TMP_DX.LO
TMP_DH		equ	TMP_DX.HI

;
; Session Control Block (SCB)
;
; SIDEBAR: To miminize the amount of per-process information in the IVT,
; we'll pretend all the apps we care about are well-behaved, which means if
; they want to set any of the EXRET/CTRLC/ERROR handlers, they'll use the
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
SCB_NUM		db	?	; 01h: SCB #
SCB_SFHCON	db	?	; 02h: SFH for CON
SCB_SFHAUX	db	?	; 03h: SFH for AUX
SCB_SFHPRN	db	?	; 04h: SFH for PRN
SCB_RESERVED	db	?	; 05h (holds SCBSIG in DEBUG builds)
SCB_CURPSP	dw	?	; 06h: current PSP
SCB_WAITID	dd	?	; 08h: wait ID if waiting, 0 if runnable
SCB_STACK	dd	?	; 0Ch: pointer to session stack
SCB_EXRET	dd	?	; 10h: current EXRET handler
SCB_CTRLC	dd	?	; 14h: current CTRLC handler
SCB_ERROR	dd	?	; 18h: current ERROR handler
SCB_DTA		dd	?	; 1Ch: current DTA (Disk Transfer Address)
SCB_CONTEXT	dw	?	; 20h: CONSOLE context (from device driver)
SCB_CURDRV	db	?	; 22h: current drive #
SCB_CTRLC_ALL	db	?	; 23h: 1 if CTRLC checking enabled on all calls
SCB_CTRLC_ACT	db	?	; 24h: 1 if CTRLC active
SCB_CTRLP_ACT	db	?	; 25h: 1 if CTRLP active
SCB_SWITCHAR	db	?	; 26h: current "switchar" (default is CHR_SLASH)
SCB_PADDING	db	?
SCB		ends

SCBSIG		equ	'S'

SCSTAT_INIT	equ	01h	; set if SCB initialized
SCSTAT_LOAD	equ	02h	; set if session has loaded a program
SCSTAT_START	equ	04h	; set if session program can be started

LOCK_SCB macro
	inc	[scb_locked]
	endm

UNLOCK_SCB macro
	jmp	scb_delock
	endm
;
; Memory Control Block (MCB)
;
MCB		struc
MCB_SIG		db	?	; 00h: either MCBSIG_NEXT or MCBSIG_LAST
MCB_OWNER	dw	?	; 01h: owner (PSP segment if > 8)
MCB_PARAS	dw	?	; 03h: size of block in paragraphs
MCB_RESERVED	db     11 dup(?); 05h: reserved
MCB		ends

MCBSIG_NEXT	equ	4Dh	; "M"
MCBSIG_LAST	equ	5Ah	; "Z"
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
SFB_DRIVE	db	?	; 12h: drive # (-1 if not block device)
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
STDEXE		equ	5

;
; Program Segment Prefix (PSP)
;
PSP		struc
PSP_ABORT	dw	?	; 00h: INT 20h
PSP_PARAS	dw	?	; 02h: paragraphs available
PSP_SCB		db	?	; 04h: BASIC-DOS: SCB #
PSP_FARCALL	db	?	; 05h: far call (9Ah)
PSP_SIZE	dw	?	; 06h: size of PSP segment
PSP_FCSEG	dw	?	; 08h: far call segment
PSP_EXRET	dd	?	; 0Ah: original INT 22h vector
PSP_CTRLC	dd	?	; 0Eh: original INT 23h vector
PSP_ERROR	dd	?	; 12h: original INT 24h vector
PSP_PARENT	dw	?	; 16h: PSP of parent
PSP_PFT		db     20 dup(?); 18h: Process File Table
PSP_ENVSEG	dw	?	; 2Ch
PSP_STACK	dd	?	; 2Eh: BASIC-DOS: initial program stack
PSP_HDLFREE	dw	?	; 32h: available handles
PSP_HDLPTR	dd	?	; 34h: initially 0FFFF:0018h
PSP_SHAREPSP	dd	?	; 38h
PSP_DTAPREV	dd	?	; 3Ch: BASIC-DOS: prev DTA (restored on return)
PSP_START	dd	?	; 40h: BASIC-DOS: initial program address
PSP_RESERVED1	db     10 dup(?); 44h
PSP_EXCODE	db	?	; 4Eh: BASIC-DOS: exit code, if any
PSP_EXTYPE	db	?	; 4Fh: BASIC-DOS: exit type (see EXTYPE_*)
PSP_DISPATCH	db	3 dup(?); 50h: INT 21h/RETF
PSP_RESERVED2	db	9 dup(?); 53h
PSP_FCB1	db     16 dup(?); 5Ch
PSP_FCB2	db     16 dup(?); 6ch
PSP_RESERVED3	db	4 dup(?); 7Ch
PSP_CMDTAIL	db    128 dup(?); 80h: length byte, command tail, CR
PSP		ends

PSP_DTA		equ	PSP_CMDTAIL

SFH_NONE	equ	0FFh	; if this SFH is in a PFT entry, it's unused

;
; The CONIO functions need a way of telling dev_request whether or not
; STDIN I/O requests should also perform CTRLC checks; set IO_RAW if not.
;
IO_RAW		equ	0
IO_COOKED	equ	1

;
; Exec Parameter Block (EPB)
;
EPB		struc
EPB_ENVSEG	dw	?	; 00h: segment of environment (0 to copy parent)
EPB_CMDTAIL	dd	?	; 02h: pointer to well-formed command tail
EPB_FCB1	dd	?	; 06h: pointer to FCB for PSP_FCB1
EPB_FCB2	dd	?	; 0Ah: pointer to FCB for PSP_FCB2
EPB		ends

;
; Exit types (returned with exit code on DOS_PSP_RETCODE calls)
;
EXTYPE_NORMAL	equ	0	; normal termination
EXTYPE_CTRLC	equ	1	; CTRLC termination
EXTYPE_ERROR	equ	2	; critical error termination
EXTYPE_KEEP	equ	3	; INT 21h AH=31h (keep process)
EXTYPE_DVERR	equ	4	; BASIC-DOS: divide error
EXTYPE_OVERR	equ	5	; BASIC-DOS: overflow error

;
; EXE File Header
;
EXEHDR		struc
EXE_SIG		dw	?	; 00h: EXESIG
EXE_NBLAST	dw	?	; 02h: # bytes in last block (0 if full)
EXE_NBLOCKS	dw	?	; 04h: # blocks of EXE file data
EXE_NRELOCS	dw	?	; 06h: # relocation entries
EXE_PARASHDR	dw	?	; 08h: # header paras (includes reloc entries)
EXE_PARASMIN	dw	?	; 0Ah: # paras minimum additional
EXE_PARASMAX	dw	?	; 0Ch: # paras maximum additional
EXE_STACK_SEG	dw	?	; 0Eh: initial SS value
EXE_STACK_OFF	dw	?	; 10h: initial SP value
EXE_CHECKSUM	dw	?	; 12h: checksum of all words in file
EXE_START_OFF	dw	?	; 14h: initial IP value
EXE_START_SEG	dw	?	; 16h: initial CS value
EXE_OFFRELOC	dw	?	; 18h: offset of first relocation entry
EXE_OVERLAY	dw	?	; 1Ah: 0 for main program
EXEHDR		ends

EXESIG		equ	5A4Dh	; "MZ"

;
; Find File Block (FFB)
;
FFB		struc
FFB_DRIVE	db	?	; 00h: drive #
FFB_SATTR	db	?	; 01h: search attributes
FFB_FILESPEC	db    11 dup (?); 02h: filespec
FFB_PADDING	db     6 dup (?); 0Dh
FFB_DIRNUM	dw	?	; 13h: DIRENT #
FFB_ATTR	db	?	; 15h: file attr
FFB_TIME	dw	?	; 16h: file time
FFB_DATE	dw	?	; 18h: file date
FFB_SIZE	dd	?	; 1Ah: file size
FFB_NAME	db    13 dup (?); 1Eh: file name (null-terminated)
FFB		ends

;
; itoa flag definitions (see sprintf.asm)
;
PF_LEFT   equ	01h		; left-alignment requested
PF_HASH   equ	02h		; prefix requested (eg, "0x")
PF_ZERO   equ	04h		; zero padding requested
PF_LONG   equ	08h		; long value (32 bits); default is 16
PF_SIGN   equ	10h		; signed value
PF_WIDTH  equ	20h		; width encountered
PF_PRECIS equ	40h		; precision encountered (after '.')

BUFLEN	equ	120		; max stack space to use as printf buffer

;
; Input buffer (eg, as used by DOS_TTY_INPUT)
;
BUF_INPUT	struc
INP_MAX		db	?
INP_CNT		db	?
INP_BUF		db	128 dup (?)
BUF_INPUT	ends

;
; Token data (eg, as generated by DOS_UTL_TOKIFY)
;
; Whereas INP_BUF consists of bytes, TOK_BUF consists of TOKLETs.
;
TOKLET		struc
TOKLET_CLS	db	?	; 00h: token class
TOKLET_LEN	db	?	; 01h: token length
TOKLET_OFF	dw	?	; 02h: token offset
TOKLET		ends

BUF_TOKEN	struc
TOK_MAX		db	?
TOK_CNT		db	?
TOK_BUF		db	128 * (size TOKLET) dup (?)
BUF_TOKEN	ends

TOKTYPE_BASIC	equ	0	; default parsing
TOKTYPE_GENERIC	equ	1	; generic whitespace parsing only

;
; After DOS_UTL_TOKIFY breaks a string into tokens, use DOS_UTL_TOKID
; to identify each token, based on a table of sorted TOKDEF structures.
;
; The table must begin with two bytes: # tokens (255 max) and TOKDEF size.
;
TOKTBL		struc
TOKTBL_NUM	db	?	; # of tokens in table
TOKTBL_SIZE	db	?	; default is size TOKDEF
				; sorted array of TOKDEF structures follows
TOKTBL		ends

TOKDEF		struc
TOKDEF_ID	db	?	; ID of token
TOKDEF_LEN	db	?	; length of token text
TOKDEF_OFF	dw	?	; offset of token text
TOKDEF_DATA	dw	?	; user-defined token data
TOKDEF		ends

CLS_OCT		equ	01h	; octal value
CLS_HEX		equ	02h	; hexadecimal value
CLS_DEC		equ	04h	; decimal value
CLS_NUM		equ	07h	; any of the above
CLS_STR		equ	08h	; string constant
CLS_VAR		equ	10h	; identifier (eg, keyword or variable)
CLS_SYM		equ	20h	; any other symbol
CLS_DQUOTE	equ	40h	; inside double quotes
CLS_WHITE	equ	80h	; whitespace
CLS_VAR_INT	equ	30h	; CLS_VAR + VAR_INT
CLS_VAR_LONG	equ	50h	; CLS_VAR + VAR_LONG (var ending with '%')
CLS_VAR_SINGLE	equ	70h	; CLS_VAR + VAR_SINGLE (var ending with '!')
CLS_VAR_STR	equ	90h	; CLS_VAR + VAR_STR (var ending with '$')
CLS_VAR_DOUBLE	equ	0F0h	; CLS_VAR + VAR_DOUBLE (var ending with '#')

;
; DOS error codes (not to be confused with device error codes)
;
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
