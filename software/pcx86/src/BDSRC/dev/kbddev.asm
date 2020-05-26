	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	KBD
	extrn	SCR:dword

KBD	DDH	<offset SCR,,DDATTR_CHAR,offset ddreq,offset ddint,202020202044424Bh,offset ddinit>

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
	mov	ax,offset ddinit - offset KBD
	ret
ddinit	endp

DEV	ends

	end
