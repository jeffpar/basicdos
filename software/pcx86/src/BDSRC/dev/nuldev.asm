	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	extrn	init:near
;
; The NUL device must be the first object module in the image.
;
	jmp	init

	public	NUL
	extrn	KBD:dword

NUL	DDH	<offset KBD,,DDATTR_CHAR,offset ddreq,offset ddint,20202020204C554Eh,offset ddinit>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

;;;;;;;;
;
; Driver initialization
;
; Returns: AX = size of device driver
;
ddinit	proc	near
	mov	ax,offset ddinit - offset NUL
	ret
ddinit	endp

DEV	ends

	end
