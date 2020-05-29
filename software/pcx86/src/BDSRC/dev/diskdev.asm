;
; BASIC-DOS Physical Diskette Drive Device Driver
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

	public	DRIVE
DRIVE 	DDH	<offset DEV:ddend+16,,DDATTR_BLOCK,offset ddreq,offset ddint,2020202020202041h>

ddpkt	dd	?		; last request packet address

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

ddreq	proc	far
	mov	[ddpkt].off,bx
	mov	[ddpkt].seg,es
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	[ddpkt] -> DDPI
;
; Output:
;	DDPI's DDPI_END updated
;
ddinit	proc	far
	push	di
	push	es
	les	di,[ddpkt]
	mov	es:[di].DDPI_END.off,offset ddinit
	mov	cs:[0].DDH_INTERRUPT,offset DEV:ddint
	pop	es
	pop	di
	ret
ddinit	endp

CODE	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
