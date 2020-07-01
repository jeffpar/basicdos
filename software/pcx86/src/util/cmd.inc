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
TOKDATA	SEGMENT word public 'CODE'
	DEF_TOKEN <len,val,offset DGROUP:N1,offset func>
TOKDATA	ENDS
STRDATA	SEGMENT word public 'CODE'
N1	label	byte
	db	str
	len = offset $ - offset N1
STRDATA	ENDS
	endm

;
; Define the command workspace as a structure
;
CMD_WS		struc
INPUT		db	size BUF_INPUT dup (?)
TOKENS		db	size BUF_TOKENS dup (?)
FILENAME	db	16 dup (?)
STACK		dw	1024 dup (?)
CMD_WS		ends
