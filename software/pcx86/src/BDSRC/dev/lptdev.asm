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

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	LPT1

LPT1	DDH	<offset DEV:LPT2,,DDATTR_CHAR,offset ddreq,offset DEV:ddinit,202020203154504Ch>

ddpkt	dd	?		; last request packet address

ddreq	proc	far
	mov	[ddpkt].off,bx
	mov	[ddpkt].seg,es
	ret
ddreq	endp

ddint	proc	far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	es
	les	di,[ddpkt]
	; ...
i9:	pop	es
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ddint	endp

CODE1	ends

CODE2	segment para public 'CODE'

LPT2_LEN	= 20h
LPT2_INIT	= (offset DEV:ddinit) + 40h
LPT2	DDH	<LPT2_LEN,,DDATTR_CHAR,offset ddreq,LPT2_INIT,202020203254504Ch>

CODE2	ends

CODE3	segment para public 'CODE'

LPT3_LEN	= 20h + (((ddinit_end - ddinit) + 15) AND 0FFF0h) + 16
LPT3_INIT	= (offset DEV:ddinit) + 20h
LPT3	DDH	<LPT3_LEN,,DDATTR_CHAR,offset ddreq,LPT3_INIT,202020203354504Ch>

CODE3	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If there are no LPT ports, then the offset portion of DDPI_END will be zero.
; place a zero in DDH_NEXT_OFF.
;
; Inputs:
;	[ddpkt] -> DDPI
;
; Output:
;	DDPI's DDPI_END updated
;
ddinit	proc	far
	int 3
	pushf
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	ds
	push	es
	les	di,[ddpkt]
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	si,offset PRINTER_BASE
	mov	bl,byte ptr cs:[0].DDH_NAME+3
	and	bx,0003h
	dec	bx
	mov	ax,[si+bx]		; get BIOS PRINTER port address
	test	ax,ax			; exists?
	jz	in9			; no
	mov	ax,cs:[0].DDH_NEXT_OFF	; yes, copy over the driver length
	cmp	bl,2			; LPT3?
	jne	in8			; no
	mov	ax,20h			; yes, just keep the header
in8:	mov	es:[di].DDPI_END.off,ax
	mov	cs:[0].DDH_INTERRUPT,offset DEV:ddint
in9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	popf
	ret
ddinit	endp

ddinit_end	equ		$

INIT	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
