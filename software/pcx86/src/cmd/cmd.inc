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

CBLK_HDR	struc
TMP16		dw	?			; temporary 16-bit eval space
CBLK_HDR	ends

;
; Other Block definitions
;
VBLK_HDR	struc
VAR_SIZE	dw	?			; size of var block
VAR_NEXT	dw	?			; offset of next free byte
VBLK_HDR	ends

VAR_INT		equ	020h			; 2 bytes of var data
VAR_LONG	equ	040h			; 4 bytes of var data
VAR_SINGLE	equ	060h			; 4 bytes of var data
VAR_STRING	equ	080h			; 4 bytes of ptr data
VAR_DOUBLE	equ	0A0h			; 8 bytes of var data
MAX_VARLEN	equ	31			; max chars allowed in var name

VBLKLEN		equ	1024			; default vars block size
DBLKLEN		equ	1024			; default data block size
TBLKLEN		equ	4096			; default text block size

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

