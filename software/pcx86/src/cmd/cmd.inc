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

GETTOKEN macro	num				;; get token num (1-N)
	LOCAL	gt1
	cmp	[di].TOK_CNT,num		;; at least num tokens?
	jb	gt1				;; no
	lea	si,[bx].INPUTBUF.INP_BUF
	mov	cl,[di+(num-1)*(size TOKBUF)].TOK_BUF.TOKBUF_OFF
	mov	ch,0				;; CX = token offset
	add	si,cx
	mov	cl,[di+(num-1)*(size TOKBUF)].TOK_BUF.TOKBUF_LEN
gt1:
	endm
;
; Define the command workspace as a structure
;
CMD_WS		struc
ORIG_SP		dd	?
INPUTBUF	db	size BUF_INPUT dup (?)
TOKENBUF	db	size BUF_TOKENS dup (?)
FILENAME	db	16 dup (?)		; filename template
EXECDATA	db	size EPB dup (?)	; Exec Parameter Block
STACK		dw	512 dup (?)
CMD_WS		ends
