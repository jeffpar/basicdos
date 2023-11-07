;
; BASIC-DOS Operating System Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

IFNDEF DEBUG
REG_CHECK	equ	0	; no REG_FRAME marker on stack
ELSE
REG_CHECK	equ	2	; add a DEBUG marker before REG_FRAME
ENDIF

WS_TEMP		struc		; REG_WS workspace used for CTRLC dispatching
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

REG_AL		equ 	REG_AX.LOB
REG_AH		equ 	REG_AX.HIB
REG_BL		equ 	REG_BX.LOB
REG_BH		equ 	REG_BX.HIB
REG_CL		equ 	REG_CX.LOB
REG_CH		equ 	REG_CX.HIB
REG_DL		equ 	REG_DX.LOB
REG_DH		equ 	REG_DX.HIB

;
; Temp register definitions: an alternate use of the REG_WS workspace
;
TMP_AX		equ	REG_WS.JMP_IP
TMP_BX		equ	REG_WS.JMP_CS
TMP_CX		equ	REG_WS.RET_IP
TMP_DX		equ	REG_WS.RET_CS
TMP_ES		equ	REG_WS.RET_FL

TMP_AL		equ	TMP_AX.LOB
TMP_AH		equ	TMP_AX.HIB
TMP_BL		equ	TMP_BX.LOB
TMP_BH		equ	TMP_BX.HIB
TMP_CL		equ	TMP_CX.LOB
TMP_CH		equ	TMP_CX.HIB
TMP_DL		equ	TMP_DX.LOB
TMP_DH		equ	TMP_DX.HIB

;
; The "Floating Point Accumulator" (FAC)
; See: https://github.com/microsoft/GW-BASIC/blob/master/GWDATA.ASM#L1463
;
; In addition to the FAC (where $FAC is the offset of the exponent and $DFACL
; is the offset of the mantissa), $DFACL must be preceded by another 9 bytes
; of "EXTRA STORAGE FOR D.P. MULTIPLY" and "TEMPORARY LEAST SIGNIFICANT BYTE".
;
; Storage is also required for a second value named ARG (where $ARG is the
; offset of the exponent and $ARGLO is the offset of the mantissa), and an
; intermediate value named $DBUFF.  However, we have omitted ARG from this
; structure on the assumption that it will be provided as an API input.
;
; $FACLO and $FACM1 were also defined as intermediate portions of the FAC,
; but they were presumably used by single-precision code only (not used here).
;
FAC	struc
$DBUFF	db	8 dup (?)	; DOUBLE PRECISION BUFFER
	db	?		; padding
	db	?		; [TEMPORARY LEAST SIGNIFICANT BYTE]
	db	8 dup (?)	; EXTRA STORAGE FOR D.P. MULTIPLY
$DFACL	db	7 dup (?)	; DOUBLE PRECISION MANTISSA
$FAC	db	?		; [EXPONENT]
	db	?		; [TEMPORARY COMPLEMENT OF SIGN IN MSB]
	db	?		; padding
FAC	ends			; 1Ch bytes

;
; Session Control Block (SCB)
;
; SIDEBAR: To minimize the amount of per-process information in the IVT,
; we'll pretend all the apps we care about are well-behaved, which means if
; they want to set any of the EXIT/CTRLC/ERROR handlers, they'll use the
; DOS_SET_VECTOR function, which will update the SCB vectors below, rather
; than the actual IVT vectors (22h/23h/24h).
;
; That will save scb_switch from having to save/restore IVT vectors on every
; switch.  If it turns out I care about running non-well-behaved apps later,
; then I'll add some vector-checking logic at appropriate checkpoints (or,
; worst case, copy selected vectors in/out on session switches -- yuck).
;
SCB		struc
SCB_STATUS	db	?	; 00h: SCB status
SCB_NUM		db	?	; 01h: SCB #
SCB_SFHIN	db	?	; 02h: SFH for STDIN
SCB_SFHOUT	db	?	; 03h: SFH for STDOUT
SCB_SFHERR	db	?	; 04h: SFH for STDERR
SCB_SFHAUX	db	?	; 05h: SFH for STDAUX
SCB_SFHPRN	db	?	; 06h: SFH for STDPRN
SCB_SIG		db	?	; 07h (holds SIG_SCB in DEBUG builds)
SCB_ENVSEG	dw	?	; 08h: just a copy of SPB_ENVSEG for now
SCB_CONTEXT	dw	?	; 0Ah: CONSOLE context (from device driver)
SCB_OWNER	dw	?	; 0Ch: PSP of owner, if any
SCB_PSP		dw	?	; 0Eh: PSP active within this session
SCB_WAITID	dd	?	; 10h: wait ID if waiting, 0 if runnable
SCB_STACK	dd	?	; 14h: pointer to session stack
SCB_EXIT	dd	?	; 18h: current EXIT handler
SCB_CTRLC	dd	?	; 1Ch: current CTRLC handler
SCB_ERROR	dd	?	; 20h: current ERROR handler
SCB_DTA		dd	?	; 24h: current DTA (Disk Transfer Address)
SCB_PARENT	dw	?	; 28h: SCB of parent, if any
SCB_CTRLC_ALL	db	?	; 2Ah: 1 if CTRLC checking enabled on all calls
SCB_CTRLC_ACT	db	?	; 2Bh: 1 if CTRLC active
SCB_CTRLP_ACT	db	?	; 2Ch: 1 if CTRLP active
SCB_INDOS	db	?	; 2Dh: active DOS/DOSUTIL call count
SCB_CURDRV	db	?	; 2Eh: current drive #
SCB_SWITCHAR	db	?	; 2Fh: current switch char (eg, CHR_SLASH)
SCB_FILENAME	db    12 dup (?); 30h: buffer for drive # and filename
SCB_FAC      db size FAC dup (?); 3Ch: floating point accumulator
SCB		ends		; 58h bytes (2Ch words)
SIG_SCB		equ	'S'

SCSTAT_INIT	equ	01h	; set if SCB initialized
SCSTAT_LOAD	equ	02h	; set if session has loaded a program
SCSTAT_START	equ	04h	; set if session program can be started
SCSTAT_ABORT	equ	08h	; set if session abort (CTRL-ALT-DEL) signalled

LOCK_SCB macro
	inc	[scb_locked]
	endm

UNLOCK_SCB macro
	jmp	scb_release
	endm
;
; Memory Control Block (MCB)
;
MCB		struc
MCB_SIG		db	?	; 00h: either MCBSIG_NEXT or MCBSIG_LAST
MCB_OWNER	dw	?	; 01h: owner (PSP segment if > 8)
MCB_PARAS	dw	?	; 03h: size of block in paragraphs
MCB_TYPE	db	?	; 05h: one of MCBTYPE values
MCB_RESERVED	dw	?	; 06h
MCB_NAME	db	8 dup(?); 08h: name of process (zero if none)
MCB		ends

MCBSIG_NEXT	equ	4Dh	; 'M'
MCBSIG_LAST	equ	5Ah	; 'Z'

MCBOWNER_NONE	equ	0	; free memory block
MCBOWNER_SYSTEM	equ	0008h	; owned by the system

MCBTYPE_NONE	equ	0	; no specified block type
MCBTYPE_CBLK	equ	'C'	; code block
MCBTYPE_FBLK	equ	'F'	; function block
MCBTYPE_VBLK	equ	'V'	; variable block
MCBTYPE_SBLK	equ	'S'	; string block
MCBTYPE_TBLK	equ	'T'	; text block

;
; System File Block (SFB)
;
; For files, the SFB begins as a superset of the directory entry
; (see DIRENT in disk.inc).  At offset 20h, additional fields are defined.
;
; System File Handles (SFH) are indexes into the SFB table (SFT), whereas
; Process File Handles (PFH) are indexes into a PSP's Process File Table (PFT).
;
SFB		struc
SFB_NAME	db    11 dup (?); 00h: filename (E5=free,00=end)
SFB_ATTR	db	?	; 0Bh: attribute bits (see DIRATTR_*)
SFB_DEVICE	dd	?	; 0Ch: device driver
SFB_CONTEXT	dw	?	; 10h: device context (1st cluster if file)
SFB_DRIVE	db	?	; 12h: drive # (-1 if not block device)
SFB_MODE	db	?	; 13h: open mode
SFB_REFS	db	?	; 14h: number of process handle references
SFB_SIG		db	?	; 15h (holds SIG_SFB in DEBUG builds)
SFB_TIME	dw	?	; 16h: time of last write (see below)
SFB_DATE	dw	?	; 18h: date of last write (see below)
SFB_CLN		dw	?	; 1Ah: 1st cluster number of file
SFB_SIZE	dd	?	; 1Ch: file size
SFB_CURPOS	dd	?	; 20h: current file position
SFB_CURCLN	dw	?	; 24h: current cluster number
SFB_FLAGS	db	?	; 26h: see SFBF_* (initially zero)
		db	?	; 27h: padding
SFB_OWNER	dw	?	; 28h: PSP of owner (used if SFBF_FCB set)
SFB_FCB		dd	?	; 2Ah: FCB address, if SFBF_FCB set
SFB		ends
SIG_SFB		equ	'F'

SFBF_FCB	equ	01h	; SFB opened for FCB (see fcb_open)

SFH_NONE	equ	0FFh	; if this SFH is in a PFT entry, it's unused

;
; The CONIO functions need a way of telling dev_request whether or not
; STDIN I/O requests should also perform CTRLC checks; set IO_RAW if not.
;
IO_RAW		equ	0
IO_COOKED	equ	1
IO_DIRECT	equ	-1

;
; EXE File Header
;
EXEHDR		struc
EXE_SIG		dw	?	; 00h: SIG_EXE
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
SIG_EXE		equ	5A4Dh	; "MZ"
