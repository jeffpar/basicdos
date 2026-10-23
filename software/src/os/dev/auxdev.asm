;
; BASIC-DOS Logical (AUX) Serial Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; AUX forwards every request to COM1 (see comdev.asm), which follows us in the
; driver chain, if the BIOS found a serial port; otherwise, WRITE requests
; fail ("not ready"), and all other requests succeed without doing anything.
;
	include	macros.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	AUX
AUX	DDH	<offset DEV:ddaux_end+16,,DDATTR_CHAR,offset ddaux_init,-1,2020202020585541h>

	DEFPTR	com_req,0		; COM1's request handler (once found)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;	DDP updated (by COM1, if there is one)
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddaux_req,far
	cmp	[com_req].SEG,0		; have we found COM1?
	jne	dar3			; yes
	lds	si,dword ptr cs:[0]	; DS:SI -> next driver (DDH_NEXT_OFF)
dar1:	cmp	si,-1			; end of the driver chain?
	je	dar8			; yes
	cmp	word ptr [si].DDH_NAME,'OC'
	jne	dar2
	cmp	word ptr [si].DDH_NAME+2,'1M'
	je	dar2a			; we found "COM1"
dar2:	lds	si,dword ptr [si]	; (DDH_NEXT_OFF)
	jmp	dar1
dar2a:	mov	ax,[si].DDH_REQUEST
	mov	[com_req].OFF,ax
	mov	[com_req].SEG,ds
dar3:	jmp	[com_req]		; COM1 finishes the request
dar8:	cmp	es:[bx].DDP_CMD,DDC_WRITE
	jne	dar9			; no other request does anything
	mov	es:[bx].DDP_STATUS,DDSTAT_ERROR + DDERR_NOTREADY
dar9:	ret
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
