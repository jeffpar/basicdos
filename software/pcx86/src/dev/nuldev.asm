;
; BASIC-DOS Logical (NUL) Device Driver
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

	public	NUL
NUL	DDH	<offset DEV:ddnul_end+16,,DDATTR_CHAR,offset ddnul_init,-1,20202020204C554Eh>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddnul_req,far
	ret
ENDPROC	ddnul_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddnul_init,far
	mov	es:[bx].DDPI_END.OFF,offset ddnul_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddnul_req
	ret
ENDPROC	ddnul_init

CODE	ends

DATA	segment para public 'DATA'

ddnul_end	db	16 dup(0)

DATA	ends

	end
