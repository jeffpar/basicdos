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

DEV	group	CODE1,CODE2,CODE3,CODE4,INIT,DATA

CODE1	segment para public 'CODE'

	public	COM1
	DEFLEN	COM1_LEN,<COM1>
	DEFLEN	COM1_INIT,<COM1,COM2,COM3,COM4>
COM1	DDH	<COM1_LEN,,DDATTR_OPEN+DDATTR_CHAR,COM1_INIT,-1,20202020314D4F43h>

	DEFPTR	ddcom_cmdp		; ddcom_cmd pointer
	DEFWORD	port_base,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE1, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req,far
	push	dx
	mov	dx,[port_base]
	call	[ddcom_cmdp]
	pop	dx
	ret
ENDPROC	ddcom_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver command handler
;
; Inputs:
;	DX = port
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddcom_cmd,far
	ret
ENDPROC	ddcom_cmd

	DEFLBL	COM1_END

CODE1	ends

CODE2	segment para public 'CODE'

	public	COM2
	DEFLEN	COM2_LEN,<COM2>
	DEFLEN	COM2_INIT,<COM2,COM3,COM4>
COM2	DDH	<COM2_LEN,,DDATTR_CHAR,COM2_INIT,-1,20202020324D4F43h>

	DEFPTR	ddcom_cmdp2		; ddcom_cmd pointer
	DEFWORD	port_base2,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE2, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req2,far
	push	dx
	mov	dx,[port_base2]
	call	[ddcom_cmdp2]
	pop	dx
	ret
ENDPROC	ddcom_req2

	DEFLBL	COM2_END

CODE2	ends

CODE3	segment para public 'CODE'

	public	COM3
	DEFLEN	COM3_LEN,<COM3>
	DEFLEN	COM3_INIT,<COM3,COM4>
COM3	DDH	<COM3_LEN,,DDATTR_CHAR,COM3_INIT,-1,20202020334D4F43h>

	DEFPTR	ddcom_cmdp3		; ddcom_cmd pointer
	DEFWORD	port_base3,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE3, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req3,far
	push	dx
	mov	dx,[port_base3]
	call	[ddcom_cmdp3]
	pop	dx
	ret
ENDPROC	ddcom_req3

	DEFLBL	COM3_END

CODE3	ends

CODE4	segment para public 'CODE'

	public	COM4
	DEFLEN	COM4_LEN,<COM4,ddcom_init>,16
	DEFLEN	COM4_INIT,<COM4>
COM4	DDH	<COM4_LEN,,DDATTR_CHAR,COM4_INIT,-1,20202020344D4F43h>

	DEFPTR	ddcom_cmdp4		; ddcom_cmd pointer
	DEFWORD	port_base4,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE4, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req4,far
	push	dx
	mov	dx,[port_base4]
	call	[ddcom_cmdp4]
	pop	dx
	ret
ENDPROC	ddcom_req4

	DEFLBL	COM4_END

CODE4	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If there are no COM ports, then the offset portion of DDPI_END will be zero.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_init,far
	push	ax
	push	bx
	push	si
	push	di
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	si,offset RS232_BASE
	mov	di,bx			; ES:DI -> DDPI
	mov	bl,byte ptr cs:[0].DDH_NAME+3
	dec	bx
	and	bx,0003h
	add	bx,bx
	mov	ax,[si+bx]		; get BIOS RS232 port address
	test	ax,ax			; exists?
	jz	in9			; no
	mov	[port_base],ax
	mov	ax,cs:[0].DDH_NEXT_OFF	; yes, copy over the driver length
	cmp	bl,3			; COM4?
	jne	in1			; no
	mov	ax,cs:[0].DDH_REQUEST	; use the temporary ddcom_req offset

in1:	mov	es:[di].DDPI_END.off,ax
	mov	cs:[0].DDH_REQUEST,offset DEV:ddcom_req

	mov	[ddcom_cmdp].off,offset DEV:ddcom_cmd
in2:	mov	ax,0			; this MOV will be modified
	test	ax,ax			; on the first call to contain the CS
	jnz	in3			; of the first driver (this is the
	mov	ax,cs			; easiest way to communicate between
	mov	word ptr cs:[in2+1],ax	; the otherwise fully insulated drivers)
in3:	mov	[ddcom_cmdp].seg,ax

in9:	pop	ds
	pop	di
	pop	si
	pop	bx
	pop	ax
	ret
ENDPROC	ddcom_init

	DEFLBL	ddcom_init_end

INIT	ends

DATA	segment para public 'DATA'

ddcom_end	db	16 dup(0)

DATA	ends

	end
