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
EOD	dd	-1

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
        ASSUME	CS:DEV, DS:BIOS, ES:BIOS, SS:BIOS

	public	devinit
devinit	proc	far
;
; Initialize each device driver.
;
	mov	si,BIOS_END	; DS:SI -> first driver
;
; Create a DDPI packet on the stack.
;
	sub	sp,(size DDPI + 1) AND 0FFFEh
	mov	bx,sp
	mov	[bx].DDP_LEN,size DDP
	mov	[bx].DDP_UNIT,0
	mov	[bx].DDP_CMD,DDC_INIT

i1:	cmp	si,di		; reached the end of drivers?
	jae	i9		; yes
	push	bx		; save packet address
	mov	dx,[si]		; DX = original size of this driver
	mov	ax,si
	mov	cl,4
	shr	ax,cl
	mov	[bx].DDPI_END.off,0
	mov	[bx].DDPI_END.seg,ax
	push	ax		; AX = segment of driver
	push	[si].DDH_STRATEGY
	mov	bp,sp
	call	dword ptr [bp]	; far call to DDH_STRATEGY
	pop	ax
	push	[si].DDH_INTERRUPT
	call	dword ptr [bp]	; far call to DDH_INTERRUPT
	pop	ax
	pop	ax		; recover the driver segment
	mov	bx,[bx].DDPI_END.off
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
	push	bx
	push	si
	add	bx,si		; BX = dest address
	add	si,dx		; SI = source address
i2:	cmp	si,di
	jae	i3
	mov	cx,[si]
	mov	[bx],cx
	add	si,2
	add	bx,2
	jmp	i2
i3:	mov	di,bx		; new end of drivers
	pop	si
	pop	dx

i4:	test	dx,dx
	jz	i8		; jump if driver not required
	sub	cx,cx		; AX:CX -> driver header
	xchg	[DD_LIST].off,cx
	mov	[si].DDH_NEXT_OFF,cx
	xchg	[DD_LIST].seg,ax
	mov	[si].DDH_NEXT_SEG,ax
i8:	add	si,dx		; SI -> next driver (after adding original size)
	pop	bx		; BX -> packet on the stack again
	jmp	i1

i9:	add	sp,(size DDPI + 1) AND 0FFFEh
	ret
devinit	endp

DEV	ends

	end
