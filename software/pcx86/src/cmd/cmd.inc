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

DEFTOK	macro	sym,val,str,func
	LOCAL	N1
	public	sym
sym	equ	val
CODE	SEGMENT
N1	label	byte
	db	str
	len = offset $ - offset N1
CODE	ENDS
DATA	SEGMENT
	IFB <func>
	TOKDEF	<val,len,offset DGROUP:N1>
	ELSE
	TOKDEF	<val,len,offset DGROUP:N1,offset func>
	ENDIF
DATA	ENDS
	endm

DEFTOKENS macro tbl,val
DATA	SEGMENT
	public	tbl
tbl	TOKTBL	<val,size TOKDEF>
DATA	ENDS
	endm

NUMTOKENS macro tbl,val
DATA	SEGMENT
val = ((offset $ - offset tbl) - 2) / (size TOKDEF)
DATA	ENDS
	endm

PUSHNUM	macro	val
	local	lbl
	call	lbl
	dw	val
lbl:
	endm

BLK_DEF		struc
BLK_NEXT	dw	?		; next block seg, if any
BLK_HDR		db	?		; eg, size CBLK_HDR
BLK_SIG		db	?		; eg, CBLKSIG
BLK_DEF		ends

;
; Code Block (CBLK) definitions
;
CBLK_HDR	struc
CBLK_NEXT	dw	?		; next code block seg, if any
CBLK_SIZE	dw	?		; size of code block, in bytes
CBLK_FREE	dw	?		; offset of next free byte
CBLK_RESERVED	db	?
CBLK_PADDING	db	?
CBLK_HDR	ends
CBLKLEN		equ	1024		; default code block size
CBLKSIG		equ	'C'

;
; Variable Block (VBLK) definitions
;
MAX_VARNAME	equ	01Fh		; max chars allowed in var name
VAR_TYPE	equ	0E0h
VAR_NONE	equ	000h
VAR_INT		equ	020h		; 2 bytes of var data
VAR_LONG	equ	040h		; 4 bytes of var data
VAR_SINGLE	equ	060h		; 4 bytes of var data
VAR_STR		equ	080h		; 4 bytes of ptr data (ptr)
VAR_ARRAY	equ	0A0h		; 4 bytes of var data (ptr)
VAR_FUNC	equ	0C0h		; 4 bytes of var data (ptr)
VAR_DOUBLE	equ	0E0h		; 8 bytes of var data

;
; Pseudo-variable types (used by printArgs)
;
VAR_SEMI	equ	VAR_NONE OR 01h
VAR_COMMA	equ	VAR_NONE OR 02h
VAR_NEWLINE	equ	VAR_NONE OR 03h

VBLK_HDR	struc
VBLK_NEXT	dw	?		; next var block seg, if any
VBLK_SIZE	dw	?		; size of var block, in bytes
VBLK_FREE	dw	?		; offset of next free byte
VBLK_RESERVED	db	?
VBLK_ZERO	db	VAR_LONG
		dd	0		; zero constant
VBLK_HDR	ends
VBLKSIG		equ	'V'
VBLKLEN		equ	1024		; default var block size

;
; String Block (SBLK) definitions
;
SBLK_HDR	struc
SBLK_NEXT	dw	?		; next string block seg, if any
SBLK_SIZE	dw	?		; size of string block, in bytes
SBLK_FREE	dw	?		; offset of next free byte
SBLK_RESERVED	db	?
SBLK_PADDING	db	?
SBLK_HDR	ends
SBLKSIG		equ	'P'
SBLKLEN		equ	2048		; default string block size

;
; Text Block (TBLK) definitions
;
; TODO: Increase default TBLKLEN after we've finished testing the small size.
;
TBLK_HDR	struc
TBLK_NEXT	dw	?		; next text block seg, if any
TBLK_SIZE	dw	?		; size of text block, in bytes
TBLK_FREE	dw	?		; offset of next free byte
TBLK_RESERVED	db	?
TBLK_PADDING	db	?
TBLK_HDR	ends
TBLKSIG		equ	'T'
TBLKLEN		equ	1024		; default text block size

;
; Operator Definition
;
OPDEF		struc
OP_CHR		db	?		; ASCII character
OP_PREC		db	?		; precedence value
OP_ARGS		db	?		; # of operator arguments
OP_EVAL		dw	?		; offset of evaluator
OPDEF		ends

;
; Code generation macros
;
GENCALL	macro	func
	IFDIF	<func>,<cx>
	mov	cx,offset func
	ENDIF
	call	genCallFar
	endm

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

GENPUSHB macro	val
	IFDIF	<val>,<ah>
	mov	ax,OP_MOV_AL OR (val SHL 8)
	ELSE
	mov	al,OP_MOV_AL
	ENDIF
	call	genPushImmByte
	endm
;
; PUSHSTR copies the string at DS:SI with length CL into the code segment,
; pushing the far address of that string and then "leaping" over the string.
;
PUSHSTR	macro
	mov	al,OP_PUSH_CS
	stosb
	mov	al,OP_CALL
	stosb
	mov	ax,cx
	inc	ax			;; +1 for length byte
	stosw
	mov	al,cl
	stosb				;; store the length byte
	rep	movsb			;; followed by all the characters
	endm

PUSH_DS_DX macro
	mov	al,OP_PUSH_DS
	stosb
	mov	al,OP_MOV_AX		;; "MOV AX,offset var data"
	stosb
	xchg	ax,dx			;; where DX is the offset of var data
	stosw
	mov	al,OP_PUSH_AX
	stosb
	endm
;
; Define the heap as a structure
;
CMD_HEAP	struc
CODE_BLK	db	size BLK_DEF dup (?)
VARS_BLK	db	size BLK_DEF dup (?)
STRS_BLK	db	size BLK_DEF dup (?)
TEXT_BLK	db	size BLK_DEF dup (?)
ORIG_SP		dd	?
ORIG_BP		dw	?
CON_COLS	db	?
CON_ROWS	db	?
INPUTBUF	db	size BUF_INPUT dup (?)
TOKENBUF	db	size BUF_TOKEN dup (?)
LINEBUF		db	256 dup (?)
FILENAME	db	16 dup (?)	; filename template ("X:XXXXXXXX.XXX")
EXECDATA	db	size EPB dup (?); Exec Parameter Block
STACK		dw	512 dup (?)
CMD_HEAP	ends
