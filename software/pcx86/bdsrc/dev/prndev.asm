;
; BASIC-DOS Logical (PRN) Parallel Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	PRN
PRN	DDH	<offset DEV:ddprn_end+16,,DDATTR_CHAR,offset ddprn_init,-1,20202020204E5250h>

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
DEFPROC	ddprn_req,far
	ret
ENDPROC	ddprn_req

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
DEFPROC	ddprn_init,far
	mov	es:[bx].DDPI_END.OFF,offset ddprn_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddprn_req
	ret
ENDPROC	ddprn_init

CODE	ends

DATA	segment para public 'DATA'

ddprn_end	db	16 dup(0)

DATA	ends

	end
