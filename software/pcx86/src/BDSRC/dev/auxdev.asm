	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	AUX
	extrn	COM1:dword

AUX	DDH	<offset COM1,,DDATTR_CHAR,offset ddreq,offset ddint,2020202020585541h,offset ddinit>

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
	mov	ax,offset ddinit - offset AUX
	ret
ddinit	endp

DEV	ends

	end
