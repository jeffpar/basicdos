	include	dos.inc

CODE    segment byte public 'CODE'

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

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
	push	ax
	push	bx
	push	cx
	push	dx
	push	bp
	push	ds
	push	es
	sub	bx,bx
	mov	ds,bp
	ASSUME	DS:BIOS_DATA
	mov	bp,sp
	mov	bl,ah
	cmp	bl,(callend - calltbl) shr 1
	jae	dc9
	add	bx,bx
	call	cs:calltbl[bx]
dc9:	pop	es
	pop	ds
	ASSUME	DS:NOTHING
	pop	bp
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	iret
doscall	endp

CODE	ends

	end
