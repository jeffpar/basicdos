;
; BASIC-DOS Operating System Interfaces
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

VERSION_MAJOR	equ	0
VERSION_MINOR	equ	21
VERSION_REV	equ	1

VERSION_STR	macro
		db	'0' + VERSION_MAJOR
		db	'.'
		db	'0' + VERSION_MINOR / 10
		db	'0' + VERSION_MINOR MOD 10
		IF VERSION_REV
		db	'A' + VERSION_REV - 1
		ENDIF
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
INT_DOSCALL5	equ	30h	; vector w/FAR JMP (overwrites vector 31h, too)
INT_DOSUTIL	equ	32h	; DOS utility interface

;
; INT_DOSFUNC functions
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
DOS_FCB_OPEN	equ	0Fh	; open FCB (DS:DX)
DOS_DSK_GETDRV	equ	19h	; get current drive (AL)
DOS_DSK_SETDTA	equ	1Ah	; set DTA (DS:DX)
DOS_FCB_SETREL	equ	24h	; set relative record for FCB (DS:DX)
DOS_MSC_SETVEC	equ	25h	; set vector (AL) to addr (DS:DX)
DOS_PSP_COPY	equ	26h	; copy PSP to segment (DX)
DOS_FCB_RBREAD	equ	27h	; read (CX) records for FCB (DS:DX)
DOS_FCB_PARSE	equ	29h	; parse filespec (DS:SI) into FCB (ES:DI)
DOS_MSC_GETDATE	equ	2Ah	; get date (CX=year, DH=mon, DL=day, AL=wkday)
DOS_MSC_SETDATE	equ	2Bh	; set date (CX=year, DH=mon, DL=day)
DOS_MSC_GETTIME	equ	2Ch	; get time (CH=hour, CL=min, DH=sec, DL=1/100s)
DOS_MSC_SETTIME	equ	2Dh	; set time (CH=hour, CL=min, DH=sec, DL=1/100s)
DOS_DSK_GETDTA	equ	2Fh	; get DTA (ES:BX)
DOS_MSC_GETVER	equ	30h	; get version (AL,AH,BH,BL,CX)
DOS_DSK_GETDPB	equ	32h	; get DPB (DS:BX, AL=FFh if invalid drive)
DOS_MSC_CTRLC	equ	33h	; get/set CTRLC state
DOS_MSC_GETVEC	equ	35h	; get vector (AL) addr (ES:BX)
DOS_DSK_GETINFO	equ	36h	; get disk info; eg, available clusters (BX)
DOS_MSC_GETSWC	equ   3700h	; get switch char (DL) (undocumented)
DOS_MSC_SETSWC	equ   3701h	; set switch char (DL) (undocumented)
DOS_HDL_CREATE	equ	3Ch	; create handle for device/file (DS:DX)
DOS_HDL_OPEN	equ	3Dh	; open handle for device/file (DS:DX)
DOS_HDL_OPENRO	equ   3D00h	; open handle for R/O access
DOS_HDL_OPENWO	equ   3D01h	; open handle for W/O access
DOS_HDL_OPENRW	equ   3D02h	; open handle for R/W access
DOS_HDL_CLOSE	equ	3Eh	; close handle (BX)
DOS_HDL_READ	equ	3Fh	; read (CX) bytes at (DS:DX) with handle (BX)
DOS_HDL_WRITE	equ	40h	; write (CX) bytes at (DS:DX) with handle (BX)
DOS_HDL_SEEK	equ	42h	; seek to (CX:DX) w/method (AL) and handle (BX)
DOS_HDL_SEEKBEG	equ   4200h	; seek from beginning
DOS_HDL_SEEKCUR	equ   4201h	; seek from current position
DOS_HDL_SEEKEND	equ   4202h	; seek from end
DOS_HDL_IOCTL	equ   	44h	; send device request (AL) for handle (BX)
DOS_MEM_ALLOC	equ	48h	; allocate (BX) paras (returns segment AX)
DOS_MEM_FREE	equ	49h	; free segment (ES)
DOS_MEM_REALLOC	equ	4Ah	; reallocate size of segment (ES) to paras (BX)
DOS_PSP_EXEC	equ   4B00h	; load program (DS:DX) with EPB (ES:BX)
DOS_PSP_EXEC1	equ   4B01h	; load program w/o starting (undocumented)
DOS_PSP_EXEC2	equ   4B02h	; start program (BASIC-DOS only)
DOS_PSP_EXIT	equ	4Ch	; exit program with return code (AL)
DOS_PSP_RETCODE	equ	4Dh	; return exit code (AL) and exit type (AH)
DOS_DSK_FFIRST	equ	4Eh	; find first filespec (DS:DX) with attr (CX)
DOS_DSK_FNEXT	equ	4Fh	; find next filespec (DTA)
DOS_PSP_SET	equ	50h	; set current PSP (BX) (undocumented)
DOS_PSP_GET	equ	51h	; get current PSP (BX) (undocumented)
DOS_MSC_GETVARS	equ	52h	; get variables pointer (ES:BX) (undocumented)
DOS_PSP_CREATE	equ	55h	; create PSP in segment (DX) (undocumented)

;
; INT_DOSUTIL functions
;
DOS_UTL_STRLEN	equ	00h	; return string (DS:SI) length (AX)
DOS_UTL_STRSTR	equ	01h	; find string (DS:SI) in string (ES:DI)
DOS_UTL_STRUPR	equ	03h	; upper-case string (DS:SI)
DOS_UTL_PRINTF	equ	04h	; printf to console
DOS_UTL_DPRINTF	equ	05h	; printf to DEBUG context, if any
DOS_UTL_SPRINTF	equ	06h	; sprintf to buffer (ES:DI)
DOS_UTL_ITOA	equ	07h	; convert number (DX:SI) to string (ES:DI)
DOS_UTL_ATOI16	equ	08h	; convert string (DS:SI) to 16-bit number (AX)
DOS_UTL_ATOI32	equ	09h	; convert string (DS:SI) to 32-bit number (AX)
DOS_UTL_ATOI32D	equ	0Ah	; convert decimal string (DS:SI) to number (AX)
DOS_UTL_TOKIFY1	equ	0Bh	; tokenize string (DS:SI) using GENERIC syntax
DOS_UTL_TOKIFY2	equ	0Ch	; tokenize string (DS:SI) using BASIC syntax
DOS_UTL_TOKID	equ	0Dh	; convert string (DS:SI) into token ID (AX)
DOS_UTL_RESTART	equ	0Eh	; restart ("reboot") the system
DOS_UTL_GETDEV	equ	0Fh	; get DDH (ES:DI) for device (DS:SI)
DOS_UTL_IOCTL	equ	10h	; issue IOCTL to device (ES:DI)
DOS_UTL_LOAD	equ	11h	; load program (DS:DX) into session (CL)
DOS_UTL_START	equ	12h	; start session (CL)
DOS_UTL_STOP	equ	13h	; stop session (CL)
DOS_UTL_END	equ	14h	; end session (CL)
DOS_UTL_WAITEND	equ	15h	; wait for session to end (CL)
DOS_UTL_YIELD	equ	16h	; yield
DOS_UTL_SLEEP	equ	17h	; sleep (DX) milliseconds
DOS_UTL_WAIT	equ	18h	; wait on ID (DX:DI) until end wait
DOS_UTL_ENDWAIT	equ	19h	; end wait on ID (DX:DI)
DOS_UTL_HOTKEY	equ	1Ah	; CON detected hotkey (DL) (eg, CTRLC, CTRLP)
DOS_UTL_LOCK	equ	1Bh	; lock current session
DOS_UTL_UNLOCK	equ	1Ch	; unlock current session
DOS_UTL_QRYMEM	equ	1Dh	; query memory block N (CL)
DOS_UTL_QRYHDL	equ	1Eh	; query system file handle N (CL)
DOS_UTL_ABORT	equ	1Fh	; abort with exit code (DL) and exit type (DH)
DOS_UTL_GETDATE	equ	20h	; get date (AX) in "packed" format
DOS_UTL_GETTIME	equ	21h	; get time (AX) in "packed" format
DOS_UTL_INCDATE	equ	22h	; increment date (CX=year, DH=month, DL=day)
DOS_UTL_READLN	equ	23h	; read line (DS:DX) from CON
DOS_UTL_STDLEN	equ	24h	; like STRLEN but w/24h ('$') as terminator
DOS_UTL_HDLCTL	equ	(DOS_HDL_IOCTL + 80h)

;
; File Control Block (FCB)
;
; Only these 4 FCB fields fit in PSP_FCB1 and PSP_FCB2.  FCBF defines
; the "full" FCB structure.
;
FCB		struc
FCB_DRIVE	db	?	; 00h: set to 1-based drive # on OPEN
FCB_NAME	db     11 dup(?); 01h: upper-cased on OPEN
FCB_CURBLK	dw	?	; 0Ch: set to 0 on OPEN
FCB_RECSIZE	dw	?	; 0Eh: set to 128 on OPEN
FCB		ends

FCBF		struc		; the "full" FCB structure
FCBF_FCB	db size FCB dup(?)
FCBF_FILESIZE	dd	?	; 10h: from DIRENT.DIR_SIZE on OPEN
FCBF_DATE	dw	?	; 14h: from DIRENT.DIR_DATE on OPEN
FCBF_TIME	dw	?	; 16h: from DIRENT.DIR_TIME on OPEN
;
; The next 8 bytes are reserved.  PC DOS 2.0 appears to define them as:
;
FCBF_DEVICE	db	?	; 18h: bit 7 set if logical device
FCBF_CLN	dw	?	; 19h: 1st cluster number
FCBF_CLN_REL	dw	?	; 1Bh: relative 0-based cluster number
FCBF_CLN_CUR	dw	?	; 1Dh: current cluster number
FCBF_UNUSED	db	?	; 1Fh
;
; The next two fields are NOT initialized on OPEN.  Set CURREC (along with
; CURBLK) before a sequential read or write, and set RELREC before a random
; read or write.
;
FCBF_CURREC	db	?	; 20h: cur record (0-127; 128 records/block)
FCBF_RELREC	dd	?	; 21h: rel record (3 bytes if RECSIZE >= 64)
FCBF		ends

;
; Extended FCBs are FCBs preceded by the following 7 bytes.
;
FCBEX		struc
FCBEX_FLAG	db	?	; -07h: flag byte containing 0FFh
FCBEX_RESERVED	db	5 dup(?); -06h to -02h
FCBEX_ATTR	db	?	; -01h: file attributes
FCBEX		ends

FCBERR_OK	equ	00h	; read successful
FCBERR_EOF	equ	01h	; EOF, empty record
FCBERR_DTA	equ	02h	; DTA too small
FCBERR_PARTIAL	equ	03h	; EOF, partial record

;
; Modes for DOS_HDL_OPEN
;
MODE_ACC_RO	equ	00h
MODE_ACC_WO	equ	01h
MODE_ACC_RW	equ	02h
MODE_COMPAT	equ	00h
MODE_DENY_RW	equ	10h
MODE_DENY_WR	equ	20h
MODE_DENY_RD	equ	30h
MODE_DENY_NONE	equ	40h
MODE_INHERIT	equ	80h

;
; Methods for DOS_HDL_SEEK
;
SEEK_BEG	equ	0	; or use DOS_HDL_SEEKBEG
SEEK_CUR	equ	1	; or use DOS_HDL_SEEKCUR
SEEK_END	equ	2	; or use DOS_HDL_SEEKEND

;
; Predefined Process File Table (PFT) numbers
;
STDIN		equ	0
STDOUT		equ	1
STDERR		equ	2
STDAUX		equ	3
STDPRN		equ	4

SFH_NONE	equ	0FFh	; if this SFH is in a PFT entry, it's unused
SCB_NONE	equ	0FFh

;
; Critical error (INT 24h) response codes
;
CRERR_IGNORE	equ	0	; ignore the error
CRERR_RETRY	equ	1	; retry the operation
CRERR_ABORT	equ	2	; abort program via INT 23h
CRERR_FAIL	equ	3	; fail the system call in progress

;
; Program Segment Prefix (PSP)
;
PSP		struc
PSP_ABORT	dw	?	; 00h: INT 20h
PSP_PARAS	dw	?	; 02h: paragraphs available
PSP_SCB		db	?	; 04h: BASIC-DOS: session #
PSP_FARCALL	db	?	; 05h: far call (9Ah)
PSP_SIZE	dw	?	; 06h: size of PSP segment
PSP_FCSEG	dw	?	; 08h: far call segment
PSP_EXRET	dd	?	; 0Ah: original INT 22h vector
PSP_CTRLC	dd	?	; 0Eh: original INT 23h vector
PSP_ERROR	dd	?	; 12h: original INT 24h vector
PSP_PARENT	dw	?	; 16h: PSP of parent (zero if none)
PSP_PFT		db     20 dup(?); 18h: Process File Table
PSP_ENVSEG	dw	?	; 2Ch
PSP_STACK	dd	?	; 2Eh: BASIC-DOS: last program stack ptr
PSP_HDLFREE	dw	?	; 32h: available handles
PSP_HDLPTR	dd	?	; 34h: initially 0FFFF:0018h
PSP_SHAREPSP	dd	?	; 38h
PSP_DTAPREV	dd	?	; 3Ch: BASIC-DOS: prev DTA (restored on return)
PSP_START	dd	?	; 40h: BASIC-DOS: initial program address
PSP_CODESIZE	dw	?	; 44h: BASIC-DOS: code size (see COMHEAP)
PSP_CHECKSUM	dw	?	; 46h: BASIC-DOS: code checksum (see COMHEAP)
PSP_HEAPSIZE	dw	?	; 48h: BASIC-DOS: heap size (see COMHEAP)
PSP_HEAP	dw	?	; 4Ah: BASIC-DOS: heap offset (see COMHEAP)
		dw	?	; 4Ch
PSP_EXCODE	db	?	; 4Eh: BASIC-DOS: exit code, if any
PSP_EXTYPE	db	?	; 4Fh: BASIC-DOS: exit type (see EXTYPE_*)
PSP_DISPATCH	db	3 dup(?); 50h: INT 21h/RETF
		db	9 dup(?); 53h
PSP_FCB1	db     16 dup(?); 5Ch
PSP_FCB2	db     16 dup(?); 6Ch
		db	4 dup(?); 7Ch
PSP_CMDTAIL	db    128 dup(?); 80h: length byte, command tail, CHR_RETURN
PSP		ends

PSP_DTA		equ	PSP_CMDTAIL

;
; Exec Parameter Block (EPB)
;
EPB		struc
EPB_ENVSEG	dw	?	; 00h: seg of environment (0 to copy parent)
EPB_CMDTAIL	dd	?	; 02h: pointer to well-formed command tail
EPB_FCB1	dd	?	; 06h: pointer to FCB for PSP_FCB1
EPB_FCB2	dd	?	; 0Ah: pointer to FCB for PSP_FCB2
EPB_INIT_SP	dd	?	; 0Eh: init SS:SP (returned by DOS_PSP_EXEC1)
EPB_INIT_IP	dd	?	; 12h: init CS:IP (returned by DOS_PSP_EXEC1)
EPB		ends		; 16h

;
; Session Parameter Block (SPB)
;
SPB		struc
SPB_ENVSEG	dw	?	; 00h: seg of environment (0 to copy caller)
SPB_CMDLINE	dd	?	; 02h: pointer to command line (NOT just tail)
SPB_SFHIN	db	?	; 06h: SFH for STDIN  (SFH_NONE for default)
SPB_SFHOUT	db	?	; 07h: SFH for STDOUT (SFH_NONE for default)
SPB_SFHERR	db	?	; 08h: SFH for STDERR (SFH_NONE for default)
SPB_SFHAUX	db	?	; 09h: SFH for STDAUX (SFH_NONE for default)
SPB_SFHPRN	db	?	; 0Ah: SFH for STDPRN (SFH_NONE for default)
		db	?	; 0Bh: padding
SPB		ends		; 0Ch

;
; Exit types (returned with exit code on DOS_PSP_RETCODE calls)
;
EXTYPE_NORMAL	equ	0	; normal termination
EXTYPE_CTRLC	equ	1	; CTRLC termination
EXTYPE_ERROR	equ	2	; critical error termination
EXTYPE_KEEP	equ	3	; INT 21h AH=31h (keep process)
EXTYPE_DVERR	equ	4	; BASIC-DOS: divide error
EXTYPE_OVERR	equ	5	; BASIC-DOS: overflow error
EXTYPE_RESET	equ	6	; BASIC-DOS: reset (via CTRL-ALT-DEL)

;
; Find File Block (FFB)
;
FFB		struc
FFB_DRIVE	db	?	; 00h: drive #
FFB_SATTR	db	?	; 01h: search attributes
FFB_FILESPEC	db    11 dup (?); 02h: filespec
FFB_RESERVED	db     6 dup (?); 0Dh: reserved
FFB_DIRNUM	dw	?	; 13h: DIRENT #
FFB_ATTR	db	?	; 15h: file attr
FFB_TIME	dw	?	; 16h: file time
FFB_DATE	dw	?	; 18h: file date
FFB_SIZE	dd	?	; 1Ah: file size
FFB_NAME	db    13 dup (?); 1Eh: file name (null-terminated)
FFB		ends		; 2Bh

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
PF_BYTE   equ	80h		; byte value (8 bits); default is 16

BUFLEN	equ	120		; max stack space to use as printf buffer

;
; Input buffer (eg, as used by DOS_TTY_INPUT)
;
INPBUF		struc
INP_MAX		db	?
INP_CNT		db	?
INP_DATA	db	256 dup (?)
INPBUF		ends

;
; Token data (eg, as generated by DOS_UTL_TOKIFY)
;
; Whereas INP_DATA consists of bytes, TOK_DATA consists of TOKLETs.
;
TOKLET		struc
TOKLET_CLS	db	?	; 00h: token class
TOKLET_LEN	db	?	; 01h: token length
TOKLET_OFF	dw	?	; 02h: token offset
TOKLET		ends

TOKBUF		struc
TOK_MAX		db	?
TOK_CNT		db	?
TOK_DATA	db	128 * (size TOKLET) dup (?)
TOKBUF		ends

TOKTYPE_BASIC	equ	0	; default parsing
TOKTYPE_GENERIC	equ	1	; generic whitespace-separated parsing

;
; TOKTYPE_BASIC parsing includes some knowledge of BASIC variable types
; (eg, CLS_VAR_LONG), which is why these variable types are defined here
; rather than in the interpreter.
;
VAR_NONE	equ	000h
VAR_PARM	equ	020h	; 2 bytes of var data (var type, parm offset)
VAR_LONG	equ	040h	; 4 bytes of var data
VAR_STR		equ	060h	; 4 bytes of ptr data (string ptr)
VAR_SINGLE	equ	080h	; 4 bytes of var data
VAR_DOUBLE	equ	0A0h	; 8 bytes of var data
VAR_FUNC	equ	0C0h	; variable data based on func signature
VAR_ARRAY	equ	0E0h	; variable data based on array signature
VAR_TYPE	equ	0E0h

;
; Token class (CLS) bits, used during token classification.
;
CLS_OCT		equ	01h	; octal value
CLS_HEX		equ	02h	; hexadecimal value
CLS_DEC		equ	04h	; decimal value
CLS_NUM		equ	07h	; any of the above
CLS_STR		equ	08h	; string constant
CLS_VAR		equ	10h	; identifier (eg, keyword, var, keyop)
CLS_SYM		equ	20h	; symbol
CLS_KEYWORD	equ	30h	; identifier later identified as a keyword
CLS_ANY		equ	3Fh	;
CLS_DQUOTE	equ	40h	; double quotes
CLS_WHITE	equ	80h	; whitespace
CLS_VAR_LONG	equ	CLS_VAR OR VAR_LONG	; 050h (var ending with '%')
CLS_VAR_SINGLE	equ	CLS_VAR OR VAR_SINGLE	; 070h (var ending with '!')
CLS_VAR_STR	equ	CLS_VAR OR VAR_STR	; 090h (var ending with '$')
CLS_VAR_DOUBLE	equ	CLS_VAR OR VAR_DOUBLE	; 0F0h (var ending with '#')

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
TOKDEF_LEN	db	?	; length of token string
TOKDEF_OFF	dw	?	; offset of token string
TOKDEF		ends

;
; DOS error codes (not to be confused with device error codes).
;
; TODO: Make this list complete (well, more complete than this anyway).
;
ERR_INVALID	equ	1	; invalid function
ERR_NOFILE	equ	2	; file not found
ERR_NOPATH	equ	3	; path not found (no paths in BASIC-DOS, yet)
ERR_NOHANDLE	equ	4	; out of handles
ERR_ACCDENIED	equ	5	; access denied
ERR_BADHANDLE	equ	6	; invalid handle
ERR_BADMCB	equ	7	; invalid MCB
ERR_NOMEMORY	equ	8	; out of memory
ERR_BADADDR	equ	9	; invalid memory segment

ERR_BADSESSION	equ	100	; invalid session
ERR_NOSESSION	equ	101	; out of sessions

;
; MINHEAP is the minimum number of bytes we allocate for a COM binary, on
; top of the actual file size.  This is important, because unlike PC DOS,
; we don't allocate all available memory to a program when it's loaded and
; hope the program will shrink its footprint later.
;
; In addition, if a COM binary contains a COMDATA structure at the end of
; the image, it can specify its own minimum heap size.  Currently, any value
; smaller than MINHEAP is ignored.  Use the COMHEAP macro to create the
; COMDATA structure.  Dynamically allocated heap space is zero-initialized.
;
; The program's initial stack will always be at the top of "heap", or at the
; top of the program's first 64Kb, whichever is lower.
;
; The COMHEAP macro also allows a COM file to define a range of shared code
; starting at offset 100h; every copy of the program will still have its own
; memory segment in DS, ES, and SS, but only the first copy will have the same
; CS.  Successive copies will contain only the code+data that follows the end
; of the shared code, plus any requested heap space.
;
; BASIC-DOS COM programs can also obtain the offset of their heap via the
; PSP_HEAP field in the program's PSP.
;
SIG_BASICDOS	equ	'DB'	; BASIC-DOS signature word ("BD")

MINHEAP		equ	1024

COMDATA	struc
CD_CODESIZE	dw	?	; shared code size, in bytes
CD_HEAPSIZE	dw	?	; additional heap space, in paras
CD_SIG		dw	SIG_BASICDOS
COMDATA	ends

COMHEAP	macro	heap_size,code_limit
	IFB	<code_limit>
	DEFLBL	HEAP,word
code_size equ 0
data_size equ 0
	ELSE
code_size equ offset DGROUP:code_limit
data_size equ $ - code_limit
	ENDIF
heap_paras equ (heap_size - data_size + 15) SHR 4
	COMDATA <code_size,heap_paras,SIG_BASICDOS>
	endm
