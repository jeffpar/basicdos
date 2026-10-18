;
; BASIC-DOS Operating System Interfaces
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The INT 21h and INT 32h function numbers are in dosfunc.inc, so that only
; modules that call DOS pay for them.  Drivers that don't need the program
; interfaces (FCB, PSP, EPB, SPB, FFB, and COMHEAP) can define DOSDEV to skip
; them, saving MASM symbol space.
;

;
; DOS interrupt vector table (IVT) usage
;
INT_DOSTERM	equ	20h	; terminate program
INT_DOSFUNC	equ	21h	; DOS function interface
INT_DOSEXIT	equ	22h	; exit return address
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

	IFNDEF	DOSDEV
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
	ENDIF	; DOSDEV

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
; Memory Control Block (MCB), which precedes every memory block (see
; DV_MCB_HEAD for the first one)
;
MCB		struc
MCB_SIG		db	?	; 00h: either MCBSIG_NEXT or MCBSIG_LAST
MCB_OWNER	dw	?	; 01h: owner (PSP segment if > 8)
MCB_PARAS	dw	?	; 03h: size of block in paragraphs
MCB_TYPE	db	?	; 05h: MCBTYPE_* (see below)
MCB_RESERVED	dw	?	; 06h
MCB_NAME	db	8 dup(?); 08h: name of process (zero if none)
MCB		ends

MCBSIG_NEXT	equ	4Dh	; 'M'
MCBSIG_LAST	equ	5Ah	; 'Z'

MCBOWNER_NONE	equ	0	; free memory block
MCBOWNER_SYSTEM	equ	0008h	; owned by the system

;
; Memory block types for DOS_MEM_ALLOC (AL), which records the type in the
; block's MCB (MCB_TYPE), so that MEM can describe the block
;
MCBTYPE_NONE	equ	0	; no specified block type
MCBTYPE_ABLK	equ	'A'	; array block
MCBTYPE_CBLK	equ	'C'	; code block
MCBTYPE_FBLK	equ	'F'	; function block
MCBTYPE_SBLK	equ	'S'	; string block
MCBTYPE_TBLK	equ	'T'	; text block
MCBTYPE_VBLK	equ	'V'	; variable block
MCBTYPE_HIGH	equ	80h	; flag (OR with any type) to allocate from the top

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
; Critical error (INT 24h) flags passed to the handler in AH
;
CRERR_WRITE	equ	01h	; set if the request was a write
CRERR_AREA	equ	06h	; area: 0 reserved, 2 FAT, 4 directory, 6 data
CRERR_FAILOK	equ	08h	; set if FAIL is allowed
CRERR_RETRYOK	equ	10h	; set if RETRY is allowed
CRERR_IGNOREOK	equ	20h	; set if IGNORE is allowed

	IFNDEF	DOSDEV
;
; Program Segment Prefix (PSP)
;
PSP		struc
PSP_TERMCALL	dw	?	; 00h: INT 20h terminate call
PSP_PARAS	dw	?	; 02h: paragraphs available
PSP_SCB		db	?	; 04h: BASIC-DOS: session #
PSP_CALL5	db	?	; 05h: far call (9Ah)
PSP_SIZE	dw	?	; 06h: size of PSP segment
PSP_FCSEG	dw	?	; 08h: far call segment
PSP_EXIT	dd	?	; 0Ah: original INT 22h vector
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
PSP_DOSCALL	db	3 dup(?); 50h: INT 21h/RETF
PSP_RAWKEYS	db	?	; 53h: BASIC-DOS: non-zero if raw keys enabled
		db	2 dup(?); 54h: unused
PSP_DIGITS	dw	?	; 56h: digit switches (see DOS_UTL_PARSESW)
PSP_LETTERS	dd	?	; 58h: letters switches (see DOS_UTL_PARSESW)
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
	ENDIF	; DOSDEV

;
; Exit types (returned with exit code on DOS_PSP_RETCODE calls)
;
EXTYPE_NORMAL	equ	0	; normal termination
EXTYPE_CTRLC	equ	1	; CTRLC termination
EXTYPE_ERROR	equ	2	; critical error termination
EXTYPE_KEEP	equ	3	; INT 21h AH=31h (keep process)
EXTYPE_DVERR	equ	4	; BASIC-DOS: divide error
EXTYPE_OVERR	equ	5	; BASIC-DOS: overflow error
EXTYPE_ABORT	equ	6	; BASIC-DOS: abort session (via CTRL-ALT-DEL)

	IFNDEF	DOSDEV
;
; Find File Block (FFB)
;
FFB		struc
FFB_DRIVE	db	?	; 00h: drive #
FFB_SATTR	db	?	; 01h: search attributes
FFB_FILESPEC	db    11 dup (?); 02h: filespec
FFB_DIRCLN	dw	?	; 0Dh: directory (1st cluster) to search
FFB_RESERVED	db     4 dup (?); 0Fh: reserved
FFB_DIRNUM	dw	?	; 13h: DIRENT #
FFB_ATTR	db	?	; 15h: file attr
FFB_TIME	dw	?	; 16h: file time
FFB_DATE	dw	?	; 18h: file date
FFB_SIZE	dd	?	; 1Ah: file size
FFB_NAME	db    13 dup (?); 1Eh: file name (null-terminated)
FFB		ends		; 2Bh
	ENDIF	; DOSDEV

;
; DOS_MSC_GETVARS return structure
;
DOSVARS		struc
DV_MCB_HEAD	dw	?	; -02h: first memory segment
DV_MCB_LIMIT	dw	?	;  00h: first unavailable segment
DV_BPB_TABLE	dd	?	;  02h: offset, limit of BPBs
DV_SFB_TABLE	dd	?	;  06h: offset, limit of SFBs
DV_SCB_TABLE	dd	?	;  0Ah: offset, limit of SCBs
DV_CDIR_TABLE	dd	?	;  0Eh: offset, limit of current dirs
DV_DD_LIST	dd	?	;  12h: head of device driver list
DOSVARS		ends

;
; DOS error codes (not to be confused with device error codes).
;
; TODO: Make this list complete (well, more complete than this anyway).
;
ERR_INVALID	equ	1	; invalid function
ERR_NOFILE	equ	2	; file not found
ERR_NOPATH	equ	3	; path not found
ERR_NOHANDLE	equ	4	; out of handles
ERR_ACCDENIED	equ	5	; access denied
ERR_BADHANDLE	equ	6	; invalid handle
ERR_BADMCB	equ	7	; invalid MCB
ERR_NOMEMORY	equ	8	; out of memory
ERR_BADADDR	equ	9	; invalid memory segment
ERR_BADFORMAT	equ	11	; invalid format (eg, DEVICE= driver)
ERR_BADDRIVE	equ	15	; invalid drive
ERR_CURDIR	equ	16	; attempt to remove current directory
ERR_NOTSAME	equ	17	; not same device
ERR_NOTREADY	equ	21	; drive not ready (see dev_request)
ERR_GENFAIL	equ	31	; general failure
ERR_SHARE	equ	32	; sharing violation
ERR_DISKFULL	equ	39	; disk full

ERR_BADSESSION	equ	100	; invalid session
ERR_NOSESSION	equ	101	; out of sessions

	IFNDEF	DOSDEV
;
; MINHEAP is the minimum number of bytes we allocate for a COM binary, on
; top of the actual file size.  This is important, because unlike PC DOS,
; we don't allocate all available memory to a program when it's loaded and
; hope the program will shrink its footprint later.  However, a COM binary
; without COMDATA (see below) gets at least half of the available memory.
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
; Finally, the COMHEAP macro allows a COM file to specify a heap inside its
; image (eg, a zero-initialized area of heap_size bytes); the program then
; gets no memory beyond its image, and its initial stack is at the top of that
; heap.  For a program with shared code, only the first copy uses the heap
; inside the image (successive copies get heap space after their data, as
; usual), and checksums of the shared code skip that heap, since it changes.
;
; BASIC-DOS COM programs can also obtain the offset of their heap via the
; PSP_HEAP field in the program's PSP.
;
; Finally, a COM file can declare a "core": the part of its image, ending with
; its own COMDATA, that the loader loads by itself when there isn't enough
; memory for the entire image (see lpm in process.asm).  CD_CORESIZE in the
; COMDATA at the end of the file holds the image offset of the end of the core
; (core_end, which includes the 100h bytes of the PSP), and the program can
; tell what was loaded from PSP_CODESIZE; see HEAPDEF in os/cmd/cmd.inc for
; how COMMAND.COM uses this.
;
SIG_BASICDOS	equ	'DB'	; BASIC-DOS signature word ("BD")

MINHEAP		equ	1024

COMDATA	struc
CD_HEAPOFF	dw	?	; offset of heap inside image (0 if none)
CD_CODESIZE	dw	?	; shared code size, in bytes
CD_HEAPSIZE	dw	?	; additional heap space, in paras
CD_CORESIZE	dw	?	; offset of the end of the core (0 if none)
CD_SIG		dw	SIG_BASICDOS
COMDATA	ends

COMHEAP	macro	heap_size,code_limit,heap_off,core_end
	IFB	<code_limit>
	DEFLBL	HEAP,word
code_size equ 0
data_size equ 0
	ELSE
code_size equ offset DGROUP:code_limit
data_size equ $ - code_limit
	ENDIF
	IFB	<heap_off>
hparas equ (heap_size - data_size + 15) SHR 4
	COMDATA <0,code_size,hparas,0,SIG_BASICDOS>
	ELSE
hparas equ (heap_size + 15) SHR 4
	 IFB	<core_end>
	COMDATA <offset DGROUP:heap_off,code_size,hparas,0,SIG_BASICDOS>
	 ELSE
	COMDATA <offset DGROUP:heap_off,code_size,hparas,core_end,SIG_BASICDOS>
	 ENDIF
	ENDIF
	endm
	ENDIF	; DOSDEV
