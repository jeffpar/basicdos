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
;	DI = next available load address (updated on return)
;
        ASSUME	CS:DEV, DS:BIOS, ES:BIOS, SS:BIOS

	public	init
init	proc	far
	int 3
	push	di		; push next available load address
;
; Initialize each device driver.
;
	mov	di,BIOS_END	; DS:DI -> first driver
i1:	cmp	di,si
	jae	i2
	mov	ax,di
	mov	cl,4
	shr	ax,cl
	push	ax
	push	[di].DDH_STRATEGY
	mov	bp,sp
	call	dword ptr [bp]
	pop	ax
	pop	ax
	sub	cx,cx
	xchg	[dd_first].off,cx
	xchg	[di].DDH_NEXT_OFF,cx
	xchg	[dd_first].seg,ax
	mov	[di].DDH_NEXT_SEG,ax
	add	di,cx
	jmp	i1

i2:	pop	di
	ret
init	endp

DEV	ends

	end
