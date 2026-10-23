;
; BASIC-DOS Logical (PRN) Parallel Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; PRN forwards every request to LPT1 (see lptdev.asm), which follows us in the
; driver chain, if the BIOS found a parallel port; otherwise, WRITE and IOCTL
; requests fail ("not ready"), and all other requests succeed without doing
; anything.
;
	include	macros.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	PRN
PRN	DDH	<offset DEV:ddprn_end+16,,DDATTR_CHAR,offset ddprn_init,-1,20202020204E5250h>

	DEFPTR	lpt_req,0		; LPT1's request handler (once found)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;	DDP updated (by LPT1, if there is one)
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddprn_req,far
	cmp	[lpt_req].SEG,0		; have we found LPT1?
	jne	dpr3			; yes
	lds	si,dword ptr cs:[0]	; DS:SI -> next driver (DDH_NEXT_OFF)
dpr1:	cmp	si,-1			; end of the driver chain?
	je	dpr8			; yes
	cmp	word ptr [si].DDH_NAME,'PL'
	jne	dpr2
	cmp	word ptr [si].DDH_NAME+2,'1T'
	je	dpr2a			; we found "LPT1"
dpr2:	lds	si,dword ptr [si]	; (DDH_NEXT_OFF)
	jmp	dpr1
dpr2a:	mov	ax,[si].DDH_REQUEST
	mov	[lpt_req].OFF,ax
	mov	[lpt_req].SEG,ds
dpr3:	jmp	[lpt_req]		; LPT1 finishes the request
dpr8:	mov	al,es:[bx].DDP_CMD
	cmp	al,DDC_WRITE
	je	dpr8a
	cmp	al,DDC_IOCTLIN
	jne	dpr9			; no other request does anything
dpr8a:	mov	es:[bx].DDP_STATUS,DDSTAT_ERROR + DDERR_NOTREADY
dpr9:	ret
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
