;
; BASIC-DOS Physical (LPT) Parallel Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dev.inc

DEV	segment para public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	LPT1

LPT1	DDH	<offset ddend,,DDATTR_CHAR,offset ddreq,offset ddint,202020203154504Ch>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

LPT2	DDH	<-1,,DDATTR_CHAR,offset ddreq,offset ddint,202020203254504Ch>
LPT3	DDH	<-1,,DDATTR_CHAR,offset ddreq,offset ddint,202020203354504Ch>

ddend	equ	$

DEV	ends

	end
