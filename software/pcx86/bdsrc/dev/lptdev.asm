;
; BASIC-DOS Physical (LPT) Parallel Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE1,CODE2,CODE3,INIT,DATA

CODE1	segment para public 'CODE'

	public	LPT1
	DEFLEN	LPT1_LEN,<LPT1>
	DEFLEN	LPT1_INIT,<LPT1,LPT2,LPT3>
LPT1	DDH	<LPT1_LEN,,DDATTR_OPEN+DDATTR_CHAR,LPT1_INIT,-1,202020203154504Ch>
;
; Every LPT driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddlpt_cmdp		; ddlpt_cmd pointer
	DEFWORD	port_base,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE1, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddlpt_req,far
	push	dx
	mov	dx,[port_base]
	call	[ddlpt_cmdp]
	pop	dx
	ret
ENDPROC	ddlpt_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver command handler
;
; Inputs:
;	DX = port
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddlpt_cmd,far
	ret
ENDPROC	ddlpt_cmd

	DEFLBL	LPT1_END

CODE1	ends

CODE2	segment para public 'CODE'

	DEFLEN	LPT2_LEN,<LPT2>
	DEFLEN	LPT2_INIT,<LPT2,LPT3>
LPT2	DDH	<LPT2_LEN,,DDATTR_CHAR,LPT2_INIT,-1,202020203254504Ch>
;
; Every LPT driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddlpt_cmdp2		; ddlpt_cmd pointer
	DEFWORD	port_base2,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE2, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddlpt_req2,far
	push	dx
	mov	dx,[port_base2]
	call	[ddlpt_cmdp2]
	pop	dx
	ret
ENDPROC	ddlpt_req2

	DEFLBL	LPT2_END

CODE2	ends

CODE3	segment para public 'CODE'

	DEFLEN	LPT3_LEN,<LPT3,ddlpt_init>,16
	DEFLEN	LPT3_INIT,<LPT3>
LPT3	DDH	<LPT3_LEN,,DDATTR_CHAR,LPT3_INIT,-1,202020203354504Ch>
;
; Every LPT driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddlpt_cmdp3		; ddlpt_cmd pointer
	DEFWORD	port_base3,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE3, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddlpt_req3,far
	push	dx
	mov	dx,[port_base3]
	call	[ddlpt_cmdp3]
	pop	dx
	ret
ENDPROC	ddlpt_req3

	DEFLBL	LPT3_END

CODE3	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If there are no LPT ports, then the offset portion of DDPI_END will be zero.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddlpt_init,far
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	si,offset PRINTER_BASE
	mov	di,bx			; ES:DI -> DDPI
	mov	bl,byte ptr cs:[0].DDH_NAME+3
	dec	bx
	and	bx,0003h
	add	bx,bx
	mov	ax,[si+bx]		; get BIOS PRINTER port address
	test	ax,ax			; exists?
	jz	in9			; no
	mov	[port_base],ax
	mov	ax,cs:[0].DDH_NEXT_OFF	; yes, copy over the driver length
	cmp	bl,2			; LPT3?
	jne	in1			; no
	mov	ax,cs:[0].DDH_REQUEST	; use the temporary ddlpt_req offset

in1:	mov	es:[di].DDPI_END.OFF,ax
	mov	cs:[0].DDH_REQUEST,offset DEV:ddlpt_req

	mov	[ddlpt_cmdp].OFF,offset DEV:ddlpt_cmd
in2:	mov	ax,0			; this MOV will be modified
	test	ax,ax			; on the first call to contain the CS
	jnz	in3			; of the first driver (this is the
	mov	ax,cs			; easiest way to communicate between
	mov	word ptr cs:[in2+1],ax	; the otherwise fully insulated drivers)
in3:	mov	[ddlpt_cmdp].SEG,ax

in9:	ret
ENDPROC	ddlpt_init

	DEFLBL	ddlpt_init_end

INIT	ends

DATA	segment para public 'DATA'

ddlpt_end	db	16 dup(0)

DATA	ends

	end
