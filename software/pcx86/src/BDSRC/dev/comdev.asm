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
COM1_LEN	= (((COM1_END - COM1) + 15) AND 0FFF0h)
COM1_INIT	= (((COM1_END - COM1) + 15) AND 0FFF0h) + (((COM2_END - COM2) + 15) AND 0FFF0h) + (((COM3_END - COM3) + 15) AND 0FFF0h) + (((COM4_END - COM4) + 15) AND 0FFF0h)
COM1	DDH	<COM1_LEN,,DDATTR_CHAR,offset DEV:ddreq,COM1_INIT,20202020314D4F43h>

	DEFPTR	ddpkt		; last request packet address
	DEFPTR	ddfunp		; ddfun pointer

        ASSUME	CS:CODE1, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddreq,far
	mov	[ddpkt].off,bx
	mov	[ddpkt].seg,es
	ret
ENDPROC	ddreq

DEFPROC	ddint,far
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
ENDPROC	ddint

DEFPROC	ddfun,far
	ret
ENDPROC	ddfun

	DEFLBL	COM1_END

CODE1	ends

CODE2	segment para public 'CODE'

	public	COM2
COM2_LEN	= ((COM2_END - COM2) + 15) AND 0FFF0h
COM2_INIT	= (((COM2_END - COM2) + 15) AND 0FFF0h) + (((COM3_END - COM3) + 15) AND 0FFF0h) + (((COM4_END - COM4) + 15) AND 0FFF0h)
COM2	DDH	<COM2_LEN,,DDATTR_CHAR,offset DEV:ddreq,COM2_INIT,20202020324D4F43h>

	DEFPTR	ddpkt2		; last request packet address
	DEFPTR	ddfunp2		; ddfun pointer

        ASSUME	CS:CODE2, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddreq2,far
	mov	[ddpkt2].off,bx
	mov	[ddpkt2].seg,es
	ret
ENDPROC	ddreq2

DEFPROC	ddint2,far
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
ENDPROC	ddint2

	DEFLBL	COM2_END

CODE2	ends

CODE3	segment para public 'CODE'

	public	COM3
COM3_LEN	= (((COM3_END - COM3) + 15) AND 0FFF0h)
COM3_INIT	= (((COM3_END - COM3) + 15) AND 0FFF0h) + (((COM4_END - COM4) + 15) AND 0FFF0h)
COM3	DDH	<COM3_LEN,,DDATTR_CHAR,offset DEV:ddreq,COM3_INIT,20202020334D4F43h>

	DEFPTR	ddpkt3		; last request packet address
	DEFPTR	ddfunp3		; ddfun pointer

        ASSUME	CS:CODE3, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddreq3,far
	mov	[ddpkt3].off,bx
	mov	[ddpkt3].seg,es
	ret
ENDPROC	ddreq3

DEFPROC	ddint3,far
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
ENDPROC	ddint3

	DEFLBL	COM3_END

CODE3	ends

CODE4	segment para public 'CODE'

	public	COM4
COM4_LEN	= (((COM4_END - COM4) + 15) AND 0FFF0h) + (((ddinit_end - ddinit) + 15) AND 0FFF0h) + 16
COM4_INIT	= (((COM4_END - COM4) + 15) AND 0FFF0h)
COM4	DDH	<COM4_LEN,,DDATTR_CHAR,offset DEV:ddreq,COM4_INIT,20202020344D4F43h>

	DEFPTR	ddpkt4		; last request packet address
	DEFPTR	ddfunp4		; ddfun pointer

        ASSUME	CS:CODE4, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddreq4,far
	mov	[ddpkt4].off,bx
	mov	[ddpkt4].seg,es
	ret
ENDPROC	ddreq4

DEFPROC	ddint4,far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	es
	les	di,[ddpkt4]
	call	[ddfunp4]
	pop	es
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	ddint4

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
;	[ddpkt] -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddinit,far
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
	mov	si,offset RS232_BASE
	mov	bl,byte ptr cs:[0].DDH_NAME+3
	dec	bx
	and	bx,0003h
	add	bx,bx
	mov	ax,[si+bx]		; get BIOS RS232 port address
	test	ax,ax			; exists?
	jz	in9			; no
	mov	ax,cs:[0].DDH_NEXT_OFF	; yes, copy over the driver length
	cmp	bl,3			; COM4?
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
ENDPROC	ddinit

	DEFWORD	ddfuns

	DEFLBL	ddinit_end

INIT	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
