;
; BASIC-DOS Physical (COM) Serial Device Driver
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

	public	COM1

COM1	DDH	<offset ddend,,DDATTR_CHAR,offset ddreq,offset ddint,20202020314D4F43h>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

COM2	DDH	<-1,,DDATTR_CHAR,offset ddreq,offset ddint,20202020324D4F43h>
COM3	DDH	<-1,,DDATTR_CHAR,offset ddreq,offset ddint,20202020334D4F43h>
COM4	DDH	<-1,,DDATTR_CHAR,offset ddreq,offset ddint,20202020344D4F43h>

ddend	equ	$

DEV	ends

	end
