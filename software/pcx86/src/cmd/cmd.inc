;
; BASIC-DOS Command Include File
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DGROUP	group	CODE,DATA

CODE    SEGMENT word public 'CODE'
CODE	ENDS

DATA    SEGMENT word public 'CODE'
DATA	ENDS

DEFTOK	macro	sym,val,str,func
	LOCAL	N1
sym	equ	val
CODE	SEGMENT
N1	label	byte
	db	str
	len = offset $ - offset N1
CODE	ENDS
DATA	SEGMENT
	TOKDEF	<val,len,offset DGROUP:N1,offset func>
DATA	ENDS
	endm

DEFTOKENS macro tbl,val
DATA	SEGMENT
	public	tbl
tbl	dw	val
DATA	ENDS
	endm

NUMTOKENS macro tbl,val
DATA	SEGMENT
val = ((offset $ - offset tbl) - 2) / (size TOKDEF)
DATA	ENDS
	endm

GETTOKEN macro	num,err				;; get token num (1-N)
	cmp	[di].TOK_CNT,num		;; at least num tokens?
	jb	err				;; no
	mov	si,[di+(num-1)*(size TOKLET)].TOK_BUF.TOKLET_OFF
	mov	cl,[di+(num-1)*(size TOKLET)].TOK_BUF.TOKLET_LEN
	mov	ch,0
	endm

PUSHNUM	macro	val
	local	lbl
	call	lbl
	dw	val
lbl:
	endm

;
; Code Block definitions
;
CBLKLEN		equ	1024			; default code block size

;
; Other Block definitions
;
VAR_TYPE	equ	0E0h
VAR_NONE	equ	000h
VAR_INT		equ	020h			; 2 bytes of var data
VAR_LONG	equ	040h			; 4 bytes of var data
VAR_SINGLE	equ	060h			; 4 bytes of var data
VAR_STRING	equ	080h			; 4 bytes of ptr data (ptr)
VAR_ARRAY	equ	0A0h			; 4 bytes of var data (ptr)
VAR_FUNC	equ	0C0h			; 4 bytes of var data (ptr)
VAR_DOUBLE	equ	0E0h			; 8 bytes of var data
MAX_VARNAME	equ	01Fh			; max chars allowed in var name

VBLK_HDR	struc
VAR_NEXT	dw	?			; next var block, if any
VAR_SIZE	dw	?			; size of var block
VAR_FREE	dw	?			; offset of next free byte
VAR_ZERO	db	VAR_LONG	
		dd	0			; zero constant
VBLK_HDR	ends

VBLKLEN		equ	1024			; default vars block size

OPDEF		struc
OP_CHR		db	?			; ASCII character
OP_PREC		db	?			; precedence value
OP_EVAL		dw	?			; offset of evaluator
OPDEF		ends

;
; Define our heap as a structure
;
CMD_HEAP	struc
ORIG_SP		dd	?
INPUTBUF	db	size BUF_INPUT dup (?)
TOKENBUF	db	size BUF_TOKEN dup (?)
FILENAME	db	16 dup (?)		; filename template
EXECDATA	db	size EPB dup (?)	; Exec Parameter Block
STACK		dw	512 dup (?)
CMD_HEAP	ends

