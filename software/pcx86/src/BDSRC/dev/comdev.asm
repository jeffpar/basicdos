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
COM1	DDH	<offset DEV:COM2,,DDATTR_CHAR,offset ddreq,offset DEV:ddinit,20202020314D4F43h>

ddpkt	dd	?		; last request packet address

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

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

COM2_LEN	= 20h
COM2_INIT	= (offset DEV:ddinit) + 60h
COM2	DDH	<COM2_LEN,,DDATTR_CHAR,offset DEV:ddreq,COM2_INIT,20202020324D4F43h>

CODE2	ends

CODE3	segment para public 'CODE'

COM3_LEN	= 20h
COM3_INIT	= (offset DEV:ddinit) + 40h
COM3	DDH	<COM3_LEN,,DDATTR_CHAR,offset DEV:ddreq,COM3_INIT,20202020334D4F43h>

CODE3	ends

CODE4	segment para public 'CODE'

COM4_LEN	= 20h + (((ddinit_end - ddinit) + 15) AND 0FFF0h) + 16
COM4_INIT	= (offset DEV:ddinit) + 20h
COM4	DDH	<COM4_LEN,,DDATTR_CHAR,offset DEV:ddreq,COM4_INIT,20202020344D4F43h>

CODE4	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If there are no COM ports, then the offset portion of DDPI_END will be zero.
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
	mov	si,offset RS232_BASE
	mov	bl,byte ptr cs:[0].DDH_NAME+3
	and	bx,0003h
	dec	bx
	mov	ax,[si+bx]		; get BIOS RS232 port address
	test	ax,ax			; exists?
	jz	in9			; no
	mov	ax,cs:[0].DDH_NEXT_OFF	; yes, copy over the driver length
	cmp	bl,3			; COM4?
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
	ret
ddinit	endp

ddinit_end	equ		$

INIT	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
