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
LPT1_LEN	= (((LPT1_END - LPT1) + 15) AND 0FFF0h)
LPT1_INIT	= (((LPT1_END - LPT1) + 15) AND 0FFF0h) + (((LPT2_END - LPT2) + 15) AND 0FFF0h) + (((LPT3_END - LPT3) + 15) AND 0FFF0h)
LPT1	DDH	<LPT1_LEN,,DDATTR_CHAR,offset DEV:ddreq,LPT1_INIT,202020203154504Ch>

ddpkt	dd	?		; last request packet address
ddfunp	dd	?		; ddfun pointer

        ASSUME	CS:CODE1, DS:NOTHING, ES:NOTHING, SS:NOTHING

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
	call	[ddfunp]
	pop	es
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ddint	endp

ddfun	proc	far
	ret
ddfun	endp

LPT1_END equ $

CODE1	ends

CODE2	segment para public 'CODE'

LPT2_LEN	= (((LPT2_END - LPT2) + 15) AND 0FFF0h)
LPT2_INIT	= (((LPT2_END - LPT2) + 15) AND 0FFF0h) + (((LPT3_END - LPT3) + 15) AND 0FFF0h)
LPT2	DDH	<LPT2_LEN,,DDATTR_CHAR,offset DEV:ddreq,LPT2_INIT,202020203254504Ch>

ddpkt2	dd	?		; last request packet address
ddfunp2	dd	?		; ddfun pointer

        ASSUME	CS:CODE2, DS:NOTHING, ES:NOTHING, SS:NOTHING

ddreq2	proc	far
	mov	[ddpkt2].off,bx
	mov	[ddpkt2].seg,es
	ret
ddreq2	endp

ddint2	proc	far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	es
	les	di,[ddpkt2]
	call	[ddfunp2]
	pop	es
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ddint2	endp

LPT2_END equ $

CODE2	ends

CODE3	segment para public 'CODE'

LPT3_LEN	= (((LPT3_END - LPT3) + 15) AND 0FFF0h) + (((ddinit_end - ddinit) + 15) AND 0FFF0h) + 16
LPT3_INIT	= (((LPT3_END - LPT3) + 15) AND 0FFF0h)
LPT3	DDH	<LPT3_LEN,,DDATTR_CHAR,offset DEV:ddreq,LPT3_INIT,202020203354504Ch>

ddpkt3	dd	?		; last request packet address
ddfunp3	dd	?		; ddfun pointer

        ASSUME	CS:CODE3, DS:NOTHING, ES:NOTHING, SS:NOTHING

ddreq3	proc	far
	mov	[ddpkt3].off,bx
	mov	[ddpkt3].seg,es
	ret
ddreq3	endp

ddint3	proc	far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	es
	les	di,[ddpkt3]
	call	[ddfunp3]
	pop	es
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ddint3	endp

LPT3_END equ $

CODE3	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If there are no LPT ports, then the offset portion of DDPI_END will be zero.
;
; Inputs:
;	[ddpkt] -> DDPI
;
; Output:
;	DDPI's DDPI_END updated
;
        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

ddinit	proc	far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	ds
	push	es
	les	di,cs:[ddpkt]
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	si,offset PRINTER_BASE
	mov	bl,byte ptr cs:[0].DDH_NAME+3
	dec	bx
	and	bx,0003h
	add	bx,bx
	mov	ax,[si+bx]		; get BIOS PRINTER port address
	test	ax,ax			; exists?
	jz	in9			; no
	mov	ax,cs:[0].DDH_NEXT_OFF	; yes, copy over the driver length
	cmp	bl,2			; LPT3?
	jne	in7			; no
	mov	ax,cs:[0].DDH_INTERRUPT	; use the temporary ddint offset instead
in7:	mov	es:[di].DDPI_END.off,ax
	mov	cs:[0].DDH_INTERRUPT,offset DEV:ddint
	mov	[ddfunp].off,offset ddfun
	mov	ax,cs:[ddfuns]
	test	ax,ax
	jnz	in8
	mov	ax,cs
	mov	cs:[ddfuns],ax
in8:	mov	[ddfunp].seg,ax
in9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ddinit	endp

ddfuns		dw	?

ddinit_end	equ	$

INIT	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
