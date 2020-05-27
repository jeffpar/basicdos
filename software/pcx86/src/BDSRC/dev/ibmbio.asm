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

EOD	dw	0ffffh		; end-of-drivers marker

;;;;;;;;
;
; Driver initialization
;
        ASSUME	CS:DEV, DS:BIOS, ES:BIOS, SS:NOTHING

	public	init
init	proc	far
;
; Let's make sure we're running on a safe stack.
;
	push	ds
	pop	ss
	mov	sp,offset BIOS_STACK
	ASSUME	SS:BIOS
;
; Initialize each device driver, by calling its "init" handler.
;
	push	ds
	push	es
	mov	si,BIOS_END
	push	cs
	pop	ds		; DS:SI -> NUL device
	ASSUME	DS:NOTHING
i1:	mov	[si].DDH_NEXT_SEG,cs
	call	[si].DDH_INIT
	test	ax,ax		; keep driver?
	jnz	i2		; yes
;
; For now, all we do for unwanted drivers is remove the header from the
; chain.  That means the DDH_NEXT field of the *previous* driver must be
; changed *this* driver's DDH_NEXT field.  Since the NUL device is never
; removed, ES:DI will always be valid if/when we get here.
;
	mov	ax,[si].DDH_NEXT_OFF
	mov	es:[di].DDH_NEXT_OFF,ax
	mov	ax,[si].DDH_NEXT_SEG
	mov	es:[di].DDH_NEXT_SEG,ax
	jmp	short i3

i2:	push	ds
	pop	es
	mov	di,si		; save DS:SI in ES:DI only if we're keeping it

i3:	lds	si,dword ptr [si].DDH_NEXT_OFF
	cmp	si,-1
	jne	i1
	pop	es
	pop	ds
	ASSUME	DS:BIOS,ES:BIOS
;
; Load IBMDOS.COM next....
;
	int 3

init	endp

DEV	ends

	end
