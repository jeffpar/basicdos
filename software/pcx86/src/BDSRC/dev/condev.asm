	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	CON
	extrn	AUX:dword

CON	DDH	<offset AUX,,DDATTR_CHAR,offset ddreq,offset ddint,20202020204E4F43h,offset ddinit>

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
	mov	ax,offset ddinit - offset CON
	ret
ddinit	endp

DEV	ends

	end
