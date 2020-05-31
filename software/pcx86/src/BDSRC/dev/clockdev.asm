;
; BASIC-DOS Physical Clock Device Driver
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

	public	CLOCK
CLOCK	DDH	<offset DEV:ddend+16,,DDATTR_CHAR,offset ddreq,offset ddint,2020244B434F4C43h>

	DEFPTR	ddpkt		; last request packet address

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddreq,far
	mov	[ddpkt].off,bx
	mov	[ddpkt].seg,es
	ret
ENDPROC	ddreq

DEFPROC	ddint,far
	ret
ENDPROC	ddint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	[ddpkt] -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
DEFPROC	ddinit,far
	push	di
	push	es
	les	di,[ddpkt]
	mov	es:[di].DDPI_END.off,offset ddinit
	mov	cs:[0].DDH_INTERRUPT,offset DEV:ddint
	pop	es
	pop	di
	ret
ENDPROC	ddinit

CODE	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
