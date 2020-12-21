;
; BASIC-DOS Logical (AUX) Serial Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	AUX
AUX	DDH	<offset DEV:ddaux_end+16,,DDATTR_CHAR,offset ddaux_init,-1,2020202020585541h>

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
DEFPROC	ddaux_req,far
	ret
ENDPROC	ddaux_req

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
DEFPROC	ddaux_init,far
	mov	es:[bx].DDPI_END.OFF,offset ddaux_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddaux_req
	ret
ENDPROC	ddaux_init

CODE	ends

DATA	segment para public 'DATA'

ddaux_end	db	16 dup(0)

DATA	ends

	end
