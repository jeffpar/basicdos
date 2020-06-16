;
; BASIC-DOS Device Driver Initialization Code
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dev.inc

DEV	segment para public 'CODE'

;
; Because this is the last module appended to DEV_FILE, we must include
; a fake device header, so that the BOOT code will stop looking for drivers.
; It must also be a DWORD, because the BOOT code assumes that our entry
; point is CS:0004.
;
	DEFPTR	EOD,-1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Device driver initialization
;
; Entry:
;	DI = end of drivers (start is BIOS_END)
;
; Exit:
;	DI = new end of drivers
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
        ASSUME	CS:DEV, DS:BIOS, ES:BIOS, SS:NOTHING

DEFPROC	devinit,far
;
; Initialize each device driver.
;
	mov	si,BIOS_END	; DS:SI -> first driver
;
; Create a DDPI packet on the stack.
;
	sub	sp,DDP_MAXSIZE
	mov	bx,sp
	mov	word ptr [bx].DDP_LEN,size DDP
	mov	[bx].DDP_CMD,DDC_INIT
	mov	[bx].DDP_STATUS,0

i1:	cmp	si,di		; reached the end of drivers?
	jae	i9		; yes
	mov	dx,[si]		; DX = original size of this driver
	mov	ax,si
	mov	cl,4
	shr	ax,cl
	mov	[bx].DDPI_END.off,0
	mov	[bx].DDPI_END.seg,ax
	push	ax		; AX = segment of driver
	push	[si].DDH_REQUEST
	mov	bp,sp
	call	dword ptr [bp]	; far call to DDH_REQUEST
	pop	ax
	pop	ax		; recover the driver segment
	mov	bp,[bx].DDPI_END.off
	add	bp,15
	and	bp,0FFF0h
;
; Whereas SI was the original (paragraph-aligned) address of the driver,
; and SI+DX was the end of the driver, SI+BP is the new end of driver. So,
; if DX == BP, there's nothing to move; otherwise, we need to move everything
; from SI+DX through DI to SI+BP, and update DX and DI (new end of drivers).
;
	cmp	dx,bp
	je	i4

	push	si
	mov	cx,di
	lea	di,[si+bp]	; DI = dest address
	add	si,dx		; SI = source address
	sub	cx,si
;
; If the driver *increased* its footprint, then we need to flip this move
; around (start at the high address and move down to low address); otherwise,
; we'll end up trashing some of the memory we're moving.
;
	cmp	di,si
	jb	i2
	add	si,cx
	sub	si,2
	add	di,cx
	sub	di,2
	std
i2:	shr	cx,1
	rep	movsw		; DI = new end of drivers
	cld
	pop	si
	mov	dx,bp

i4:	test	dx,dx
	jz	i8		; jump if driver not required

	sub	cx,cx		; AX:CX -> driver header
;
; If this is the FDC driver, then we need to extract DDPI_UNITS from
; the request packet and update FDC_UNITS and FDC_DEVICE in the BIOS segment.
;
; TODO: Revisit this test, because it currently relies solely on the ATTR word
; indicating this is a block device.
;
	test	[si].DDH_ATTR,DDATTR_CHAR
	jnz	i7
	push	ax
	mov	[FDC_DEVICE].off,cx
	mov	[FDC_DEVICE].seg,ax
	mov	al,[bx].DDPI_UNITS
	mov	[FDC_UNITS],al
	pop	ax
;
; Link the driver into the chain.
;
i7:	xchg	[DD_LIST].off,cx
	mov	[si].DDH_NEXT_OFF,cx
	xchg	[DD_LIST].seg,ax
	mov	[si].DDH_NEXT_SEG,ax

i8:	add	si,dx		; SI -> next driver (after adding original size)
	jmp	i1

i9:	add	sp,DDP_MAXSIZE
	ret
ENDPROC	devinit

DEV	ends

	end
