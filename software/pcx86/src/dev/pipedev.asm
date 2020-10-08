;
; BASIC-DOS Pipe Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dev.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	PIPE
PIPE	DDH	<offset DEV:ddpipe_end+16,,DDATTR_CHAR,offset ddpipe_init,-1,2020202445504950h>

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
DEFPROC	ddpipe_req,far
	ret
ENDPROC	ddpipe_req

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
DEFPROC	ddpipe_init,far
	mov	es:[bx].DDPI_END.OFF,offset ddpipe_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddpipe_req
	ret
ENDPROC	ddpipe_init

CODE	ends

DATA	segment para public 'DATA'

ddpipe_end	db	16 dup(0)

DATA	ends

	end
