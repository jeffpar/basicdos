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
; Perform some preliminary BIOS data initialization; in particular,
; DDINT_ENTER and DDINT_LEAVE entry points for hardware interrupt handlers.
;
	mov	word ptr [DDINT_ENTER],(OP_RETF SHL 8) OR OP_STC
	mov	[DDINT_LEAVE],OP_IRET
;
; Initialize each device driver.
;
	mov	si,offset BIOS_END; DS:SI -> first driver
;
; Create a DDPI packet on the stack.
;
	sub	sp,DDP_MAXSIZE
	mov	bp,sp
	INIT_STRUC [bp],DDP
	mov	word ptr [bp].DDP_LEN,size DDP
	mov	[bp].DDP_CMD,DDC_INIT
	mov	[bp].DDP_STATUS,0

i1:	cmp	si,di		; reached the end of drivers?
	jb	i2		; no
	jmp	i9		; yes
i2:	mov	dx,[si]		; DX = original size of this driver
	mov	ax,si
	mov	cl,4
	shr	ax,cl
	mov	[bp].DDPI_END.OFF,0
	mov	[bp].DDPI_END.SEG,ax
	push	ss
	pop	es
	ASSUME	ES:NOTHING
	mov	bx,bp		; ES:BX -> packet
	push	ax		; AX = segment of driver
	push	[si].DDH_REQUEST
;
; Just as in dev_request, we no longer force drivers to preserve all registers.
;
	push	dx
	push	si
	push	di
	push	bp
	push	ds

	call	dword ptr [bp-4]; far call to DDH_REQUEST

	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx

	pop	ax		; toss DDH_REQUEST address
	pop	ax		; recover the driver segment

	sub	bx,bx
	mov	es,bx
	ASSUME	ES:BIOS
	mov	bx,[bp].DDPI_END.OFF
	add	bx,15
	and	bx,0FFF0h
;
; Whereas SI was the original (paragraph-aligned) address of the driver,
; and SI+DX was the end of the driver, SI+BX is the new end of driver. So,
; if DX == BX, there's nothing to move; otherwise, we need to move everything
; from SI+DX through DI to SI+BX, and update DX and DI (new end of drivers).
;
	cmp	dx,bx
	je	i4

	push	si
	mov	cx,di
	lea	di,[si+bx]	; DI = dest address
	add	si,dx		; SI = source address
	sub	cx,si
;
; If the driver *increased* its footprint, then we need to flip this move
; around (start at the high address and move down to low address); otherwise,
; we'll end up trashing some of the memory we're moving.
;
	cmp	di,si
	jb	i3
	add	si,cx
	sub	si,2
	add	di,cx
	sub	di,2
	std
i3:	shr	cx,1
	rep	movsw		; DI = new end of drivers
	cld
	pop	si
	mov	dx,bx

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
	mov	[FDC_DEVICE].OFF,cx
	mov	[FDC_DEVICE].SEG,ax
	mov	al,[bp].DDPI_UNITS
	mov	[FDC_UNITS],al
	pop	ax
;
; Link the driver into the chain.  I originally chained them in reverse:
;
;	xchg	[DD_LIST].OFF,cx
;	mov	[si].DDH_NEXT_OFF,cx
;	xchg	[DD_LIST].SEG,ax
;	mov	[si].DDH_NEXT_SEG,ax
;
; because it's simpler, but later decided to keep the list in memory order.
;
; In addition, I now store the next available segment in the SEG portion of the
; final driver pointer (-1 in the OFF portion still means end of list).
;
i7:	push	di
	lea	di,[DD_LIST]
i7a:	cmp	es:[di].DDH_NEXT_OFF,-1
	je	i7b
	les	di,es:[di]
	jmp	i7a
i7b:	mov	es:[di].DDH_NEXT_OFF,cx
	mov	es:[di].DDH_NEXT_SEG,ax
	mov	cl,4
	shr	bx,cl
	add	bx,ax
	mov	[si].DDH_NEXT_SEG,bx
	mov	[si].DDH_NEXT_OFF,-1
	pop	di

i8:	add	si,dx		; SI -> next driver (after adding original size)
	jmp	i1

i9:	add	sp,DDP_MAXSIZE
	ret
ENDPROC	devinit

DEV	ends

	end
