;
; BASIC-DOS Command Include File
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc

DGROUP	group	CODE,DATA

CODE    SEGMENT word public 'CODE'
CODE	ENDS

DATA    SEGMENT word public 'CODE'
DATA	ENDS

;
; CTOKDEF is an extended version of TOKDEF containing function pointers,
; as well as TXT file offsets and lengths.
;
CTOKDEF		struc
CTD_ID		db	?	; ID of token
CTD_LEN		db	?	; length of token string
CTD_OFF		dw	?	; offset of token string
CTD_FUNC	dw	?	; extended token data: function
CTD_TXT_OFF	dw	?	; extended token data: TXT offset
CTD_TXT_LEN	dw	?	; extended token data: TXT length
CTOKDEF		ends

DEFTOK	macro	sym,val,func
	LOCAL	N1
	public	TOK_&sym
TOK_&sym equ val
	IFNB <func>
	EXTNEAR	<func>
	ENDIF
CODE	SEGMENT
N1	label	byte
	db	"&sym&"
	len = offset $ - offset N1
CODE	ENDS
DATA	SEGMENT
	faddr = 0
	IFB <func>
	CDEFTOK	val,%(len),<offset DGROUP:N1>,0,<TXT_&sym&_OFF>,<TXT_&sym&_LEN>
	ELSE
	CDEFTOK	val,%(len),<offset DGROUP:N1>,<offset func>,<TXT_&sym&_OFF>,<TXT_&sym&_LEN>
	ENDIF
DATA	ENDS
	endm

CDEFTOK	macro	val,len,off,func,txt_off,txt_len
	IFNDEF txt_off
	;;  IF1
	;; %OUT No definition for txt_off
	;;  ENDIF
	CTOKDEF	<val,len,off,func,0,0>
	ELSE
	CTOKDEF	<val,len,off,func,txt_off,txt_len>
	ENDIF
	endm

DEFTOKENS macro tbl,val
DATA	SEGMENT
	public	tbl
tbl	TOKTBL	<val,size CTOKDEF>
DATA	ENDS
	endm

NUMTOKENS macro tbl,val
DATA	SEGMENT
val = ((offset $ - offset tbl) - 2) / (size CTOKDEF)
DATA	ENDS
	endm

;
; Keywords with IDs >= BASIC support code generation.
;
; Keywords are defined in the KEYWORD_TOKENS table in const.asm.
;
KEYWORD_FILE	equ	20		; file-based command
KEYWORD_BASIC	equ	40		; BASIC keywords
KEYWORD_CLAUSE	equ	200		; secondary keywords (eg, THEN, ELSE)

;
; Each of our block chains begins with a BLKDEF, so that a common set of
; block functions (eg, allocBlock) can work with any chain, and each block
; begins with a BLKHDR.
;
BLKDEF		struc
BDEF_NEXT	dw	?		; next block seg, if any
BDEF_SIZE	dw	?		; default size for block allocations
BDEF_HDR	db	?		; eg, size CBLK
BDEF_SIG	db	?		; eg, SIG_CBLK
BLKDEF		ends

BLKHDR		struc
BLK_NEXT	dw	?		; 00h: next block seg, if any
BLK_SIZE	dw	?		; 02h: size of block, in bytes
BLK_FREE	dw	?		; 04h: offset of next free byte
BLK_SIG		db	?		; 06h
BLK_PAD		db	?		; 07h
BLKHDR		ends

;
; Code Block (CBLK) definitions
;
CBLK		struc
CBLK_HDR	db size	BLKHDR dup (?)	; 00h
CBLK_REFS	dw	?		; 08h: bottom of LBLREF stack, if any
CBLK		ends
CBLKLEN		equ	4096		; default code block size
CBLK_SIG	equ	BLK_SIG
SIG_CBLK	equ	'C'		; must match MCBTYPE_CBLK

;
; Function Block (FBLK) definitions
;
FBLK		struc
FBLK_HDR	db size	BLKHDR dup (?)	; 00h
FBLK_REFS	dw	?		; 08h: bottom of LBLREF stack, if any
FBLK		ends
FBLKLEN		equ	1024		; default code block size
FBLK_SIG	equ	BLK_SIG
SIG_FBLK	equ	'F'		; must match MCBTYPE_FBLK

;
; Parameter flags
;
; Predefined functions can have optional parameters; user-defined functions
; cannot, only because there is currently no syntax for declaring them and
; their corresponding default value.
;
PARM_OPT_ZERO	equ	00h		; optional parameter (default is zero)
PARM_OPT_ONE	equ	01h		; optional parameter (default is one)
PARM_REQUIRED	equ	0FFh		; required parameter

;
; Variable Block (VBLK) definitions
;
VAR_NAMELEN	equ	01Fh		; max chars allowed in var name

;
; Internal variable types (used by printArgs and others)
;
VAR_DEAD	equ	VAR_NONE OR 01h
VAR_SEMI	equ	VAR_NONE OR 02h
VAR_COMMA	equ	VAR_NONE OR 03h
VAR_NEWLINE	equ	VAR_NONE OR 04h

VAR_TSTR	equ	VAR_STR  OR 01h	; 4 bytes of ptr data (temp string ptr)

VBLK		struc
VBLK_HDR	db size	BLKHDR dup (?)	; 00h
VBLK		ends
VBLKLEN		equ	1024		; default var block size
VBLK_SIG	equ	BLK_SIG
SIG_VBLK	equ	'V'		; must match MCBTYPE_VBLK

;
; String Block (SBLK) definitions
;
SBLK		struc
SBLK_HDR	db size	BLKHDR dup (?)	; 00h
SBLK		ends
SBLKLEN		equ	2048		; default string block size
SBLK_SIG	equ	BLK_SIG
SIG_SBLK	equ	'S'		; must match MCBTYPE_SBLK

;
; Text Block (TBLK) definitions
;
; TODO: Increase default TBLKLEN after we've finished testing the small size.
;
TBLK		struc
TBLK_HDR	db size	BLKHDR dup (?)	; 00h
TBLK		ends
TBLKLEN		equ	1024		; default text block size
TBLK_SIG	equ	BLK_SIG
SIG_TBLK	equ	'T'		; must match MCBTYPE_TBLK

;
; Operator definition
;
OPDEF		struc
OP_CHR		db	?		; ASCII character
OP_PREC		db	?		; precedence value
OP_EVAL		dw	?		; offset of evaluator
OPDEF		ends

;
; Label reference
;
; As label definitions (eg, line numbers) are encountered by the code
; generator, a LBLREF is pushed onto the current code block's LBLREF table.
;
; Similarly, a LBLREF is pushed whenever a label reference (eg, GOTO line)
; is encountered.  If the label reference cannot be resolved immediately,
; then LBL_IP is the current IP + LBL_RESOLVE, indicating that the IP is for
; a JMP waiting to be resolved.
;
LBLREF		struc
LBL_NUM		dw	?		; label number
LBL_IP		dw	?		; instruction pointer for label
LBLREF		ends
LBL_RESOLVE	equ	CBLKLEN

;
; Code generation flags
;
GEN_IMM		equ	01h		; immediate mode
GEN_BASIC	equ	02h		; BAS file
GEN_BATCH	equ	04h		; BAT file
GEN_ECHO	equ	08h		; initially set if GEN_BATCH
GEN_DEF		equ	10h		; DEF function in progress

;
; Code generation helper macros
;
; GENCALL generates a call the specified function.
;
GENCALL	macro	seg,off
	IFB	<off>			;; if there's no off parameter
	 IFDIF	<seg>,<cx>
	mov	cx,offset seg		;; then seg is really a function name
	 ENDIF
	call	genCallCS		;; inside the CS segment
	ELSE
	 IFDIF	<off>,<cx>
	mov	cx,off
	 ENDIF
	 IFDIF	<seg>,<dx>
	mov	dx,seg			;; otherwise DX:CX is the function addr
	 ENDIF
	call	genCallFar
	ENDIF
	endm
;
; GENPUSH generates code to push immediate 16-bit (via DX) or 32-bit
; values (via DX:CX).
;
; Modifies: AX, DX (and CX if GENPUSH dx,cx)
;
GENPUSH	macro	val1,val2
	IFDIF	<val1>,<dx>
	mov	dx,val1
	ENDIF
	IFNB	<val2>
	IFDIF	<val2>,<cx>
	mov	cx,val2
	ENDIF
	call	genPushImmLong
	ELSE
	call	genPushImm
	ENDIF
	endm
;
; GENPUSHB generates code to push an immediate byte value (via AL, AH,
; or a constant that will be loaded via AL).
;
GENPUSHB macro	val
	IFIDN	<val>,<al>
	call	genPushImmByteAL
	ELSE
	 IFIDN	<val>,<ah>
	call	genPushImmByteAH
	 ELSE
	mov	ax,OP_MOV_AL OR (val SHL 8)
	call	genPushImmByte
	 ENDIF
	ENDIF
	endm
;
; Global interpreter flags.  We rely on the entire heap being zeroed
; on startup, so all defaults should be zero.  So, for example, since
; ECHO is ON by default, a "NOECHO" bit must be set to turn it OFF.
;
CMD_NOECHO	equ	01h		; set if ECHO turned off

;
; Define the heap as a structure.  The first few fields (ie, all the BLKDEF
; structures) are statically initialized, but the rest are left undefined so
; that they won't take up any space in the COM file.  The BASIC-DOS loader
; ensures that the remaining fields are zero-initialized.
;
CMDHEAP		struc
CBLKDEF		db size BLKDEF dup (?)	; 000h: code block chain
FBLKDEF		db size BLKDEF dup (?)	; 006h: function block chain
VBLKDEF		db size BLKDEF dup (?)	; 00Ch: variable block chain
SBLKDEF		db size BLKDEF dup (?)	; 012h: string block chain
TBLKDEF		db size BLKDEF dup (?)	; 018h: text block chain
INPUTBUF	db size INPBUF dup (?)	; 01Eh
TOKENBUF	db size TOKBUF dup (?)	; 120h
HDL_INPUT	dw	?		; 322h: 0 if unused
HDL_OUTPUT	dw	?		; 324h: 0 if unused
HDL_INPIPE	dw	?		; 326h: 0 if unused
HDL_OUTPIPE	dw	?		; 328h: 0 if unused
SCB_NEXT	db	?		; 32Ah: SCB_NONE (-1) if unused
SFH_STDIN	db	?		; 32Bh: original STDIN
SFH_STDOUT	db	?		; 32Ch: original STDOUT
CMD_SIG		db	?		; 32Dh: SIG_CMD
CMD_ARG		db	?		; 32Eh: index of 1st arg
ERR_CODE	db	?		; 32Fh
CON_COLS	db	?		; 330h: # cols in console
CON_ROWS	db	?		; 331h: # rows in console
CMD_ROWS	db	?		; 332h: # lines printed for cmd
CMD_FLAGS	db	?		; 333h: see CMD_* flags
GEN_FLAGS	db	?		; 334h: see GEN_* flags
DEF_PARMS	db	?		; 335h
CMD_ARGPTR	dw	?		; 336h: offset of current arg
CMD_ARGLEN	dw	?		; 338h: length of current arg
CMD_DEFER	dw    5 dup (?)		; 33Ah: regs for deferred command
EXIT_CODE	db	?		; 344h: exit code from last EXEC
EXIT_TYPE	db	?		; 345h: exit type from last EXEC
LINE_NUM	dw	?		; 346h
LINE_LEN	dw	?		; 348h
LINE_PTR	dd	?		; 34Ah
PREV_TIME	dd	?		; 34Eh: last time displayed by cmdTime
RND_SEED	dd	?		; 352h: pseudo-random number seed
INPUT_BUF	dw	?		; 356h: input offset (default INPUTBUF)
TOKLET_NEXT	dw	?		; 358h
TOKLET_END	dw	?		; 35Ah
LINEBUF		db  256 dup (?)		; 35Ch
DEFVARS		db   26 dup (?)		; 45Ch: default types for 26 letters
EXECDATA	db size EPB dup (?)	; 476h: Exec Parameter Block
CMD_PROCESS	dw	?		; 48Ch: PSP of loaded process, if any
;
; The BASIC-DOS loader always set the stack pointer for a COM file to the top
; of the segment, which means we must declare our stack at the end of CMDHEAP.
; The entire heap is zero-initialized and we don't want any interrupts trashing
; memory that we rely on being zeroed.
;
; TODO: Consider adding a STACKPTR field to the COMDATA structure so that a
; COM file can request the stack be located elsewhere, since there's no way for
; us to prevent a hardware interrupt from arriving before switching stacks.
;
STACK		dw  512 dup (?)		; 48Eh
CMDHEAP		ends			; 88Eh
SIG_CMD		equ	'H'

	ASSERT	<SIZE CMDHEAP>,EQ,88Eh

;
; The initial stack frame created by the main function can also be used to
; access the CMDHEAP structure, using the [heap] equate; eg:
;
;	mov	al,[heap].CON_COLS
;
; This works because the main function explicitly aligns SP with the top
; of the STACK in CMDHEAP and then pushes exactly 2 words before setting BP.
;
heap		equ	byte ptr [bp+4-(STACK + size STACK)]
