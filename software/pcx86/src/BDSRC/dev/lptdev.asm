;
; BASIC-DOS Physical (LPT) Parallel Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dev.inc

DEV	group	CODE1,CODE2,CODE3,INIT,DATA

CODE1	segment para public 'CODE'

	public	LPT1
	DEFLEN	LPT1_LEN,<LPT1>
	DEFLEN	LPT1_INIT,<LPT1,LPT2,LPT3>
LPT1	DDH	<LPT1_LEN,,DDATTR_OPEN+DDATTR_CHAR,LPT1_INIT,-1,202020203154504Ch>

	DEFPTR	ddfunp		; ddfun pointer
	DEFWORD	port_base,0

        ASSUME	CS:CODE1, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddreq,far
	push	dx
	mov	dx,[port_base]
	call	[ddfunp]
	pop	dx
	ret
ENDPROC	ddreq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver function handler
;
; Inputs:
;	DX = port
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddfun,far
	push	ax
	push	bx
	push	cx
	push	si
	push	ds
	;...
	pop	ds
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	ddfun

	DEFLBL	LPT1_END

CODE1	ends

CODE2	segment para public 'CODE'

	DEFLEN	LPT2_LEN,<LPT2>
	DEFLEN	LPT2_INIT,<LPT2,LPT3>
LPT2	DDH	<LPT2_LEN,,DDATTR_CHAR,LPT2_INIT,-1,202020203254504Ch>

	DEFPTR	ddfunp2		; ddfun pointer
	DEFWORD	port_base2,0

        ASSUME	CS:CODE2, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddreq2,far
	push	dx
	mov	dx,[port_base2]
	call	[ddfunp2]
	pop	dx
	ret
ENDPROC	ddreq2

	DEFLBL	LPT2_END

CODE2	ends

CODE3	segment para public 'CODE'

	DEFLEN	LPT3_LEN,<LPT3,ddinit>,16
	DEFLEN	LPT3_INIT,<LPT3>
LPT3	DDH	<LPT3_LEN,,DDATTR_CHAR,LPT3_INIT,-1,202020203354504Ch>

	DEFPTR	ddfunp3		; ddfun pointer
	DEFWORD	port_base3,0

        ASSUME	CS:CODE3, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddreq3,far
	push	dx
	mov	dx,[port_base3]
	call	[ddfunp3]
	pop	dx
	ret
ENDPROC	ddreq3

	DEFLBL	LPT3_END

CODE3	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

DEFPROC	ddinit,far
	push	ax
	push	bx
	push	si
	push	di
	push	ds
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
	mov	ax,cs:[0].DDH_REQUEST	; use the temporary ddreq offset instead

in1:	mov	es:[di].DDPI_END.off,ax
	mov	cs:[0].DDH_REQUEST,offset DEV:ddreq

	mov	[ddfunp].off,offset DEV:ddfun
in2:	mov	ax,0			; this MOV will be modified
	test	ax,ax			; on the first call to contain the CS
	jnz	in3			; of the first driver (this is the
	mov	ax,cs			; easiest way to communicate between
	mov	word ptr cs:[in2+1],ax	; the otherwise fully insulated drivers)
in3:	mov	[ddfunp].seg,ax

in9:	pop	ds
	pop	di
	pop	si
	pop	bx
	pop	ax
	ret
ENDPROC	ddinit

	DEFLBL	ddinit_end

INIT	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
