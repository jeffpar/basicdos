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

DEFTOK	macro	sym,val,str,func
	LOCAL	N1
sym	equ	val
STRDATA	SEGMENT word public 'CODE'
N1	label	byte
	db	str
	len = offset $ - offset N1
STRDATA	ENDS
TOKDATA	SEGMENT word public 'CODE'
	DEF_TOKEN <len,val,offset DGROUP:N1,offset func>
TOKDATA	ENDS
	endm

DEFTOKENS macro tbl,val
TOKDATA	SEGMENT word public 'CODE'
	public	tbl
tbl	dw	val
TOKDATA	ENDS
	endm

NUMTOKENS macro tbl,val
TOKDATA	SEGMENT word public 'CODE'
val = ((offset $ - offset tbl) - 2) / (size DEF_TOKEN)
TOKDATA	ENDS
	endm

GETTOKEN macro	num				;; get token num (1-N)
	LOCAL	gt1
	cmp	[di].TOK_CNT,num		;; at least num tokens?
	jb	gt1				;; no
	lea	si,[bx].INPUT.INP_BUF		;;
	add	si,[di+(num-1)*4].TOK_BUF.OFF	;; SI -> token
	mov	cx,[di+(num-1)*4].TOK_BUF.SEG	;; CX = token length
gt1:
	endm
;
; Define the command workspace as a structure
;
CMD_WS		struc
ORIG_SP		dd	?
INPUT		db	size BUF_INPUT dup (?)
TOKENS		db	size BUF_TOKENS dup (?)
FILENAME	db	16 dup (?)
EXECDATA	db	size EPB dup (?)
STACK		dw	1024 dup (?)
CMD_WS		ends
