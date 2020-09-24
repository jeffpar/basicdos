;
; BASIC-DOS Command Include File
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	bios.inc
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

SC_GENPB	equ	71h		; do GENPUSHB
SC_CALFN	equ	72h		; call function
SC_PEKTK	equ	73h		; peek token
SC_GETTK	equ	74h		; get token
SC_LENTK	equ	75h		; check token length
SC_MATCH	equ	76h		; if token matches CLS...
SC_MASYM	equ	77h		; if CLS_SYM token matches char...
SC_NEXTK	equ	78h		; get next token
SC_GENFN	equ	79h		; do GENCALL

SCF_GENXNUM	equ	0		; -> genExprNum
SCF_GENXSTR	equ	1		; -> genExprStr
SCF_PRTARGS	equ	2		; -> printArgs

;
; Keywords with IDs >= GENCODE require code generation.
; For IDs < GENCODE, an ID >= FILESPEC expect a filespec.
;
; Keywords are defined in the KEYWORD_TOKENS table in const.asm.
;
KEYWORD_FILESPEC  equ	20
KEYWORD_GENCODE   equ	40
KEYWORD_LANGUAGE  equ	60
KEYWORD_SECONDARY equ	200		; secondary keywords (eg, THEN, ELSE)

;
; Each of our block chains begins with a BLK_DEF, so that a common set of
; block functions (eg, allocBlock) can work with any chain.
;
BLK_DEF		struc
BLK_NEXT	dw	?		; next block seg, if any
BLK_HDR		db	?		; eg, size CBLK_HDR
BLK_SIG		db	?		; eg, SIG_CBLK
BLK_DEF		ends

;
; Code Block (CBLK) definitions
;
CBLK_HDR	struc
CBLK_NEXT	dw	?		; 00h: next code block seg, if any
CBLK_SIZE	dw	?		; 02h: size of code block, in bytes
CBLK_FREE	dw	?		; 04h: offset of next free byte
CBLK_SIG	db	?		; 06h
CBLK_PAD	db	?		; 07h
CBLK_REFS	dw	?		; 08h: bottom of LBLREF stack, if any
CBLK_HDR	ends
CBLKLEN		equ	4096		; default code block size
SIG_CBLK	equ	'C'

;
; Variable Block (VBLK) definitions
;
; VAR_TYPE (E0h) encompasses the following variable types in dosapi.inc
;
; VAR_NONE	equ	000h
; VAR_INT	equ	020h	; 2 bytes of var data (TBD)
; VAR_LONG	equ	040h	; 4 bytes of var data
; VAR_SINGLE	equ	060h	; 4 bytes of var data
; VAR_STR	equ	080h	; 4 bytes of ptr data (ptr)
; VAR_ARRAY	equ	0A0h	; 4 bytes of var data (ptr)
; VAR_FUNC	equ	0C0h	; 4 bytes of var data (ptr)
; VAR_DOUBLE	equ	0E0h	; 8 bytes of var data
;
VAR_NAMELEN	equ	01Fh		; max chars allowed in var name

;
; Internal variable types (used by printArgs)
;
VAR_SEMI	equ	VAR_NONE OR 01h
VAR_COMMA	equ	VAR_NONE OR 02h
VAR_NEWLINE	equ	VAR_NONE OR 03h

VAR_TSTR	equ	VAR_STR  OR 01h	; 4 bytes of ptr data (temp string ptr)

VBLK_HDR	struc
VBLK_NEXT	dw	?		; next var block seg, if any
VBLK_SIZE	dw	?		; size of var block, in bytes
VBLK_FREE	dw	?		; offset of next free byte
VBLK_SIG	db	?
VBLK_PAD	db	?
VBLK_HDR	ends
VBLKLEN		equ	1024		; default var block size
SIG_VBLK	equ	'V'

;
; String Block (SBLK) definitions
;
SBLK_HDR	struc
SBLK_NEXT	dw	?		; next string block seg, if any
SBLK_SIZE	dw	?		; size of string block, in bytes
SBLK_FREE	dw	?		; offset of next free byte
SBLK_SIG	db	?
SBLK_PAD	db	?
SBLK_HDR	ends
SBLKLEN		equ	2048		; default string block size
SIG_SBLK	equ	'P'

;
; Text Block (TBLK) definitions
;
; TODO: Increase default TBLKLEN after we've finished testing the small size.
;
TBLK_HDR	struc
TBLK_NEXT	dw	?		; next text block seg, if any
TBLK_SIZE	dw	?		; size of text block, in bytes
TBLK_FREE	dw	?		; offset of next free byte
TBLK_SIG	db	?
TBLK_PAD	db	?
TBLK_HDR	ends
TBLKLEN		equ	1024		; default text block size
SIG_TBLK	equ	'T'

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

;
; Code generation helper macros
;
; GENCALL generates a call the specified function (via CX).
;
GENCALL	macro	func
	IFDIF	<func>,<cx>
	mov	cx,offset func
	ENDIF
	call	genCallFar
	endm
;
; GENPUSH generates code to push immediate 16-bit (via DX) or 32-bit
; values (via DX:CX).
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
; Global interpreter flags
;
CMD_ECHO	equ	01h		; set if ECHO is "on"

;
; Define the heap as a structure.  The first few fields (ie, all the BLK
; headers) are statically initialized, but the rest are left undefined so
; that they won't take up any space in the COM file.  The BASIC-DOS loader
; ensures that the remaining fields are zero-initialized.
;
CMD_HEAP	struc
CBLK_DEF	db	size BLK_DEF dup (?)
VBLK_DEF	db	size BLK_DEF dup (?)
SBLK_DEF	db	size BLK_DEF dup (?)
TBLK_DEF	db	size BLK_DEF dup (?)
ORIG_SP		dw	?
ORIG_BP		dw	?
CON_COLS	db	?
CON_ROWS	db	?
CMD_FLAGS	db	?		; see CMD_* flags
PREV_TIME	dd	?		; last time displayed by cmdTime
DEFVARS		db	26 dup (?)	; default var types for all 26 letters
INPUTOFF	dw	?		; input offset (defaults to INPUTBUF)
INPUTBUF	db	size BUF_INPUT dup (?)
TOKENBUF	db	size BUF_TOKEN dup (?)
LINEBUF		db	256 dup (?)
FILENAME	db	16 dup (?)	; filename template ("X:XXXXXXXX.XXX")
EXECDATA	db	size EPB dup (?); Exec Parameter Block
STACK		dw	512 dup (?)
CMD_HEAP	ends

;
; The initial stack frame created by the main function can also be
; used to access the CMD_HEAP structure, using the [heap] macro; eg:
;
;	mov	al,[heap].CON_COLS
;
; This works because we know we enter the main function with exactly 2 words
; pushed on the stack (a zero return address, and the original BP).
;
heap		equ	byte ptr [bp+4-size CMD_HEAP]
