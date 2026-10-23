;
; BASIC-DOS Command Include File
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSPSP equ 1
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
SIG_CBLK	equ	MCBTYPE_CBLK

;
; Function Block (FBLK) definitions
;
FBLK		struc
FBLK_HDR	db size	BLKHDR dup (?)	; 00h
FBLK_REFS	dw	?		; 08h: bottom of LBLREF stack, if any
FBLK		ends
FBLKLEN		equ	4096		; preferred function block size
FBLK_SIG	equ	BLK_SIG
SIG_FBLK	equ	MCBTYPE_FBLK

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
SIG_VBLK	equ	MCBTYPE_VBLK

;
; String Block (SBLK) definitions
;
SBLK		struc
SBLK_HDR	db size	BLKHDR dup (?)	; 00h
SBLK		ends
SBLKLEN		equ	4096		; preferred string block size
SBLK_SIG	equ	BLK_SIG
SIG_SBLK	equ	MCBTYPE_SBLK

;
; Text Block (TBLK) definitions
;
TBLK		struc
TBLK_HDR	db size	BLKHDR dup (?)	; 00h
TBLK		ends
TBLKLEN		equ	4096		; preferred text block size
TBLK_SIG	equ	BLK_SIG
SIG_TBLK	equ	MCBTYPE_TBLK

;
; Array Block (ABLK) signature (see arr.inc for the ABLK definitions)
;
SIG_ABLK	equ	MCBTYPE_ABLK

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
GEN_DONE	equ	20h		; all code generated (see genMore)

;
; Global command flags.  We rely on the entire heap being zeroed
; on startup, so all defaults should be zero.  So, for example, since
; ECHO is ON by default, a "NOECHO" bit must be set to turn it OFF.
;
CMD_NOECHO	equ	01h		; set if ECHO turned off
CMD_SINGLE	equ	02h		; set if /C (exit after the command)

;
; Graphics and mouse state (see GFX_DATA in CMDHEAP)
;
GFXDATA		struc
GFX_LPX		dw	?		; 00h: last point referenced (X)
GFX_LPY		dw	?		; 02h: last point referenced (Y)
GFX_SCALE	db	?		; 04h: DRAW scale XOR 4
GFX_COLOR	db	?		; 05h: DRAW color + 1, or 0 for default
GFX_MODE	db	?		; 06h: video mode + 1, or 0 if unknown
GFX_SAVED	db	?		; 07h: saved video mode + 1 (see saveMode)
MOUSE_X		dw	?		; 08h: position of the last MOUSE(0) event
MOUSE_Y		dw	?		; 0Ah
MOUSE_STATE	db	?		; 0Ch: MS_* bits
		db	?		; 0Dh: (unused)
GFX_COLORS	dw	?		; 0Eh: colors saved with GFX_SAVED
GFXDATA		ends

MS_ON		equ	01h		; set by MOUSE ON
MS_GFX		equ	02h		; pointer hidden (see mouseGfx)

;
; The next DATA item for READ (see DATA_STATE in CMDHEAP, and readData)
;
DATASTATE	struc
DATA_OFF	dw	?		; 00h: offset of the next character to scan
DATA_SEG	dw	?		; 02h: its text block (0 to start over)
DATA_END	dw	?		; 04h: end of its line (0 if at a line)
DATA_ITEM	dw	?		; 06h: non-zero if in a DATA statement
DATASTATE	ends

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
SFH_STDIN	db	?		; 330h: original STDIN
SFH_STDOUT	db	?		; 331h: original STDOUT
CMD_SIG		db	?		; 332h: SIG_CMD
CMD_ARG		db	?		; 333h: index of 1st arg
ERR_CODE	db	?		; 334h
CON_COLS	db	?		; 335h: # cols in console
INPUT_SYM	dw	?		; 336h: offset of '<' (see parseDOS)
CMD_FLAGS	db	?		; 338h: see CMD_* flags
EXIT_CODE	db	?		; 339h: exit code from last EXEC
CMD_ARGPTR	dw	?		; 33Ah: offset of current arg
CMD_ARGLEN	dw	?		; 33Ch: length of current arg
CMD_DEFER	dw    5 dup (?)		; 33Eh: regs for deferred command
;
; The code generator's state, from DEF_PARMS through DEFVARS.  Since a
; program's code is generated as it runs (see genMore), and the program may run
; a BAT or BAS file, cmdDOS saves this state before running the file and
; restores it afterward.
;
DEF_PARMS	db	?		; 348h
GEN_FLAGS	db	?		; 349h: see GEN_* flags
LINE_NUM	dw	?		; 34Ah
LINE_LEN	dw	?		; 34Ch
LINE_PTR	dd	?		; 34Eh
LINE_LBL	dw	?		; 352h: line # of LINE_NUM (0 if none)
LBL_DATA	dw    2 dup (?)		; 354h: label state (see addLabel)
DEFVARS		db   26 dup (?)		; 358h: default types for 26 letters
PREV_TIME	dd	?		; 372h: last time displayed by cmdTime
RND_SEED	dd	?		; 376h: pseudo-random number seed
INPUT_BUF	dw	?		; 37Ah: input offset (default INPUTBUF)
TOKLET_NEXT	dw	?		; 37Ch
TOKLET_END	dw	?		; 37Eh
LINEBUF		db  256 dup (?)		; 380h
EXECDATA	db size EPB dup (?)	; 480h: Exec Parameter Block
CMD_PROCESS	dw	?		; 496h: PSP of loaded process, if any
HDL_OUTFILE	dw	?		; 498h: 0 if unused (see parseDOS)
DEF_TYPE	db	?		; 49Ah: return type of DEF in progress
OPT_BASE	db	?		; 49Bh: OPTION BASE (0 or 1)
CMD_CHAINS	dw	?		; 49Ch: CHAINS frame (see saveChains)
PEEK_SEG	dw	?		; 49Eh: DEF SEG segment XOR SS
ERR_SP		dw	?		; 4A0h: program SP for ON ERROR
ERR_NUM		dw	?		; 4A2h: last error # (HI set if active)
ERR_ADDR	dd	?		; 4A4h: ON ERROR handler (0 if none)
ERR_LINE	dw	?		; 4A8h: line # of last error (see ERL)
PLAY_STATE	dw    4 dup (?)		; 4AAh: PLAY/SOUND state (see doPlay)
GFX_DATA	db	size GFXDATA dup (?)	; 4B2h: graphics and mouse state
CODE_CACHE	dw	?		; 4C2h: cached code (see keepCode)
EDIT_STATE	dw    2 dup (?)		; 4C4h: line to edit (see edit.asm)
DATA_STATE	db	size DATASTATE dup (?)	; 4C8h: next DATA item (see sys.asm)
PATH_CHAR	db	?		; 4D0h: path char (fixed at boot)
SWITCH_CHAR	db	?		; 4D1h: switch char (fixed at boot)
FILE_DATA	db   44 dup (?)		; 4D2h: OPEN files (see fileio.inc)
PIPE_SCB	dd	?		; 4FEh: pipeline sessions (see endPipes)
PATH_BUF	db  128 dup (?)		; 502h: PATH$ (length, 0-120 chars, null)
ENV_DATA	db  176 dup (?)		; 582h: environment (see initEnv)
DOS_REGS	dw    4 dup (?)		; 632h: AX-DX from DOS (see dosCall)
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
STACK		dw 1019 dup (?)		; 63Ah
CMDHEAP		ends			 ; E30h
SIG_CMD		equ	'H'

;
; CMDHEAP must be a multiple of 16 bytes, because the loader puts the initial
; stack pointer at the end of the heap (a whole number of paragraphs), and the
; [heap] equate below assumes that's the end of STACK.
;
	ASSERT	<SIZE CMDHEAP>,EQ,0E30h

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

;
; HEAPDEF defines the per-process heap template that ends both the core (see
; const.asm) and the entire image (see heap.asm): the block chain definitions
; (see BLKDEF), followed by the COMDATA that the loader reads from the end of
; the file (see COMHEAP in dosapi.inc), which gives the shared code size (the
; offset of lbl), the heap inside the image (RES_HEAP), and, for the entire
; image, the end of the core (core_end), so that the core alone can be loaded
; when memory is tight (see CD_CORESIZE).
;
; Only const.asm and heap.asm need HEAPDEF, and they define HEAPDEFS before
; including this file; other modules skip it, since MASM's memory is tight.
;
	IFDEF	HEAPDEFS
HEAPDEF	macro	lbl,core_end
	DEFLBL	lbl,word
	BLKDEF	<0,CBLKLEN,size CBLK,SIG_CBLK>
	BLKDEF	<0,FBLKLEN,size FBLK,SIG_FBLK>
	BLKDEF	<0,VBLKLEN,size VBLK,SIG_VBLK>
	BLKDEF	<0,SBLKLEN,size SBLK,SIG_SBLK>
	BLKDEF	<0,TBLKLEN,size TBLK,SIG_TBLK>
	BLKDEF	<0,0,size BLKHDR,SIG_ABLK>	;; array blocks (sized by DIM)
	COMHEAP	<size CMDHEAP>,lbl,RES_HEAP,<core_end>
	endm
	ENDIF	; HEAPDEFS
