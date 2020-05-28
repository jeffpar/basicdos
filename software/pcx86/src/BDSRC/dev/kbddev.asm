;
; BASIC-DOS Physical (KBD) Keyboard Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dev.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	KBD

KBD	DDH	<offset DEV:ddend+16,,DDATTR_CHAR,offset ddreq,offset ddint,202020202044424Bh>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

CODE	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
