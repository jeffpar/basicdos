;
; BASIC-DOS Driver/Application Interface Entry Points
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

	extrn	init:near
;
; This must be the first object module in the image.
;
	jmp	init

	extrn	tty_echo:near
	extrn	tty_write:near
	extrn	aux_read:near
	extrn	aux_write:near
	extrn	prn_write:near
	extrn	tty_io:near
	extrn	tty_in:near
	extrn	tty_read:near
	extrn	tty_print:near
	extrn	tty_input:near
	extrn	tty_status:near
	extrn	tty_flush:near

calltbl	dw	tty_echo, tty_write, aux_read, aux_write, prn_write, tty_io
	dw	tty_in, tty_read, tty_print, tty_input, tty_status, tty_flush
callend	equ	$

	public	dosexit
dosexit	proc	far
	iret
dosexit	endp

	public	doscall
doscall	proc	far
	sti
	push	ax
	push	bx
	push	cx
	push	dx
	push	bp
	push	ds
	push	es
	push	cs
	pop	ds
	ASSUME	DS:DOS
	sub	bx,bx
	mov	es,bx
	ASSUME	ES:BIOS
	mov	bp,sp
	mov	bl,ah
	cmp	bl,(callend - calltbl) shr 1
	cmc
	jb	dc9
	add	bx,bx
	call	calltbl[bx]
dc9:	pop	es
	pop	ds
	ASSUME	DS:NOTHING
	pop	bp
	pop	dx
	pop	cx
	pop	bx
	inc	sp		; don't "pop ax" and don't disturb carry
	inc	sp
	ret	2		; don't "iret"
doscall	endp

DOS	ends

	end
