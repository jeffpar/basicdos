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

dd_first	dw	-1,?		; head of driver list (initially empty)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Device driver initialization
;
; Entry:
;	SI = end of drivers (start is BIOS_END)
;	DI = CFG_FILE contents
;
; Exit:
;	SI = new end of drivers
;
; Modifies:
;	AX, BX, CX, DX, SI, BP
;
        ASSUME	CS:DEV, DS:BIOS, ES:BIOS, SS:BIOS

	public	init
init	proc	far
	int 3
	push	di
;
; Initialize each device driver.
;
	mov	di,BIOS_END	; DS:DI -> first driver
;
; Create a DDPI packet on the stack.
;
	sub	sp,size DDPI
	mov	bx,sp
	mov	[bx].DDP_LEN,size DDP
	mov	[bx].DDP_UNIT,0
	mov	[bx].DDP_CMD,DDC_INIT

i1:	cmp	di,si		; reached the end of drivers?
	jae	i9		; yes
	mov	dx,[di]		; DX = original size of this driver
	mov	ax,di
	mov	cl,4
	shr	ax,cl
	mov	[bx].DDPI_END.off,0
	mov	[bx].DDPI_END.seg,ax
	push	ax		; AX = segment of driver
	push	[di].DDH_STRATEGY
	mov	bp,sp
	call	dword ptr [bp]	; far call to DDH_STRATEGY
	pop	ax
	push	[di].DDH_INTERRUPT
	call	dword ptr [bp]	; far call to DDH_INTERRUPT
	pop	ax
	pop	ax		; recover the driver segment
	mov	bx,[bx].DDPI_END.off
	add	bx,15
	and	bx,0FFF0h
;
; Whereas DI was the original (paragraph-aligned) address of the driver,
; and DI+DX was the end of the driver, DI+BX is the new end of driver. So,
; if DX == BX, there's nothing to move; otherwise, we need to move everything
; from DI+DX through SI to DI+BX, and then update SI (new end of drivers).
;
	cmp	dx,bx
	je	i3
	push	bx
	push	di
	add	bx,di		; BX = dest address
	add	di,dx		; DI = source address
i2:	mov	cx,[di]
	mov	[bx],cx
	add	di,2
	add	bx,2
	cmp	di,si
	jb	i2
	mov	si,bx		; new end of drivers
	pop	di
	pop	bx

i3:	test	bx,bx
	jz	i8		; jump if driver not required
	sub	cx,cx		; AX:CX -> driver header
	xchg	[dd_first].off,cx
	mov	[di].DDH_NEXT_OFF,cx
	xchg	[dd_first].seg,ax
	mov	[di].DDH_NEXT_SEG,ax
i8:	add	di,dx		; DI -> next driver (after adding original size)
	jmp	i1

i9:	add	sp,size DDPI
	pop	di
	ret
init	endp

DEV	ends

	end
