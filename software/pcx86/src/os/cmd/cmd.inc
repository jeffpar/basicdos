;
; BASIC-DOS Command Include File
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc
	include	parser.inc
;
; Build options: set DETOK to 0 to remove support for loading tokenized BAS
; files (see detok.asm); they will then be reported as invalid files again.
;
DETOK	equ	1

DGROUP	group	CODE,DATA

CODE    SEGMENT word public 'CODE'
CODE	ENDS

DATA    SEGMENT word public 'CODE'
DATA	ENDS

;
; CTOKDEF is an extended version of TOKDEF containing function pointers.
;
CTOKDEF		struc
CTD_ID		db	?	; ID of token
CTD_LEN		db	?	; length of token string
CTD_OFF		dw	?	; offset of token string
CTD_FUNC	dw	?	; extended token data: function
CTOKDEF		ends

DEFTOK	macro	sym,val,func,pub
	LOCAL	N1
	IFNB	<pub>			;; define TOK_sym only if requested
	public	TOK_&sym		;; (to conserve symbol space)
TOK_&sym equ val
	ENDIF
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
	CTOKDEF	<val,len,offset DGROUP:N1,0>
	ELSE
	CTOKDEF	<val,len,offset DGROUP:N1,offset func>
	ENDIF
DATA	ENDS
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
CBLKLEN		equ	4096		; preferred code block size
CODE_ROOM	equ	160		; room required at "safe points"
CBLK_SIG	equ	BLK_SIG
SIG_CBLK	equ	'C'		; must match MCBTYPE_CBLK

;
; Function Block (FBLK) definitions
;
FBLK		struc
FBLK_HDR	db size	BLKHDR dup (?)	; 00h
FBLK_REFS	dw	?		; 08h: bottom of LBLREF stack, if any
FBLK		ends
FBLKLEN		equ	4096		; preferred function block size
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

;
; Additional parameter types for predefined functions: VAR_CHAR accepts either
; a character code or a string (whose first character code is used), and
; VAR_LSKIP is an optional VAR_LONG that's skipped if a string is supplied
; instead (eg, the starting position in INSTR([n,]a$,b$)).
;
VAR_CHAR	equ	VAR_LONG OR 01h
VAR_LSKIP	equ	VAR_LONG OR 02h

VBLK		struc
VBLK_HDR	db size	BLKHDR dup (?)	; 00h
VBLK		ends
VBLKLEN		equ	4096		; preferred var block size
VBLK_SIG	equ	BLK_SIG
SIG_VBLK	equ	'V'		; must match MCBTYPE_VBLK

;
; String Block (SBLK) definitions
;
SBLK		struc
SBLK_HDR	db size	BLKHDR dup (?)	; 00h
SBLK		ends
SBLKLEN		equ	4096		; preferred string block size
SBLK_SIG	equ	BLK_SIG
SIG_SBLK	equ	'S'		; must match MCBTYPE_SBLK

;
; Text Block (TBLK) definitions
;
TBLK		struc
TBLK_HDR	db size	BLKHDR dup (?)	; 00h
TBLK		ends
TBLKLEN		equ	4096		; preferred text block size
TBLK_SIG	equ	BLK_SIG
SIG_TBLK	equ	'T'		; must match MCBTYPE_TBLK

;
; Operator definition structure
;
OPDEF		struc
OP_CHR		db	?		; ASCII character
OP_PREC		db	?		; precedence value
OP_IDX		db	?		; index (OPEVAL_*) of evaluator
OPDEF		ends

;
; Operator indexes into OPEVAL (operator evaluator) tables
;
OPEVAL_NEG	equ	1		; output type matches promoted input(s)
OPEVAL_EXP	equ	2
OPEVAL_MUL	equ	3
OPEVAL_DIV	equ	4
OPEVAL_ADD	equ	5
OPEVAL_SUB	equ	6
OPEVAL_EQ	equ	7		; output type is int w/promoted inputs
OPEVAL_NE	equ	8
OPEVAL_LT	equ	9
OPEVAL_GT	equ	10
OPEVAL_LE	equ	11
OPEVAL_GE	equ	12
OPEVAL_NOT	equ	13		; output type matches demoted input(s)
OPEVAL_IDIV	equ	14
OPEVAL_MOD	equ	15
OPEVAL_SHL	equ	16
OPEVAL_SHR	equ	17
OPEVAL_AND	equ	18
OPEVAL_OR	equ	19
OPEVAL_XOR	equ	20
OPEVAL_EQV	equ	21
OPEVAL_IMP	equ	22

;
; Label reference
;
; As label definitions (eg, line numbers) are encountered by the code
; generator, a LBLREF is pushed onto the current code block's LBLREF table.
;
; Similarly, a LBLREF is pushed whenever a label reference (eg, GOTO line)
; is encountered.  If the label reference cannot be resolved immediately,
; then LBL_IP is the current IP + LBL_RESOLVE, indicating that the IP is for
; a JMP waiting to be resolved.  Since LBL_RESOLVE is the high bit of the IP,
; code blocks must be smaller than 32K (they're normally CBLKLEN bytes; see
; ensureRoom).
;
; LBL_NUM values of CTL_FOR and CTL_WHILE (which are not valid line numbers)
; mark open FOR and WHILE statements (see genFor and genWhile), and CTL_DONE
; marks closed ones.
;
LBLREF		struc
LBL_NUM		dw	?		; label number
LBL_IP		dw	?		; instruction pointer for label
LBLREF		ends
LBL_RESOLVE	equ	8000h
CTL_FOR		equ	0FFFFh
CTL_WHILE	equ	0FFFEh
CTL_DONE	equ	0FFFDh

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
; Global command flags.  We rely on the entire heap being zeroed
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
ABLKDEF		db size BLKDEF dup (?)	; 01Eh: array block chain
INPUTBUF	db size INPBUF dup (?)	; 024h
TOKENBUF	db size TOKBUF dup (?)	; 126h
HDL_INPUT	dw	?		; 328h: 0 if unused
HDL_OUTPUT	dw	?		; 32Ah: 0 if unused
HDL_INPIPE	dw	?		; 32Ch: 0 if unused
HDL_OUTPIPE	dw	?		; 32Eh: 0 if unused
SCB_NEXT	db	?		; 330h: SCB_NONE (-1) if unused
SFH_STDIN	db	?		; 331h: original STDIN
SFH_STDOUT	db	?		; 332h: original STDOUT
CMD_SIG		db	?		; 333h: SIG_CMD
CMD_ARG		db	?		; 334h: index of 1st arg
ERR_CODE	db	?		; 335h
CON_COLS	db	?		; 336h: # cols in console
CON_ROWS	db	?		; 337h: # rows in console
CMD_ROWS	db	?		; 338h: # lines printed for cmd
CMD_FLAGS	db	?		; 339h: see CMD_* flags
GEN_FLAGS	db	?		; 33Ah: see GEN_* flags
DEF_PARMS	db	?		; 33Bh
CMD_ARGPTR	dw	?		; 33Ch: offset of current arg
CMD_ARGLEN	dw	?		; 33Eh: length of current arg
CMD_DEFER	dw    5 dup (?)		; 340h: regs for deferred command
EXIT_CODE	db	?		; 34Ah: exit code from last EXEC
EXIT_TYPE	db	?		; 34Bh: exit type from last EXEC
LINE_NUM	dw	?		; 34Ch
LINE_LEN	dw	?		; 34Eh
LINE_PTR	dd	?		; 350h
PREV_TIME	dd	?		; 354h: last time displayed by cmdTime
RND_SEED	dd	?		; 358h: pseudo-random number seed
INPUT_BUF	dw	?		; 35Ch: input offset (default INPUTBUF)
TOKLET_NEXT	dw	?		; 35Eh
TOKLET_END	dw	?		; 360h
LINEBUF		db  256 dup (?)		; 362h
DEFVARS		db   26 dup (?)		; 462h: default types for 26 letters
EXECDATA	db size EPB dup (?)	; 47Ch: Exec Parameter Block
CMD_PROCESS	dw	?		; 492h: PSP of loaded process, if any
HDL_OUTFILE	dw	?		; 494h: 0 if unused (see parseDOS)
DEF_TYPE	db	?		; 496h: return type of DEF in progress
OPT_BASE	db	?		; 497h: OPTION BASE (0 or 1)
CMD_CHAINS	dw	?		; 498h: CHAINS frame (see saveChains)
LINE_LBL	dw	?		; 49Ah: line # of LINE_NUM (0 if none)
PEEK_SEG	dw	?		; 49Ch: DEF SEG segment XOR SS
ERR_SP		dw	?		; 49Eh: program SP for ON ERROR
ERR_NUM		dw	?		; 4A0h: last error # (HI set if active)
ERR_ADDR	dd	?		; 4A2h: ON ERROR handler (0 if none)
PLAY_STATE	dw    4 dup (?)		; 4A6h: PLAY/SOUND state (see doPlay)
GFX_DATA	dw    4 dup (?)		; 4AEh: graphics state (see gfx.asm)
CODE_CACHE	dw	?		; 4B6h: cached code (see keepCode)
EDIT_STATE	dw    2 dup (?)		; 4B8h: line to edit (see edit.asm)
DATA_STATE	dw    4 dup (?)		; 4BCh: next DATA item (see sys.asm)
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
STACK		dw  486 dup (?)		; 4C4h
CMDHEAP		ends			; 890h
SIG_CMD		equ	'H'

	ASSERT	<SIZE CMDHEAP>,EQ,890h

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
