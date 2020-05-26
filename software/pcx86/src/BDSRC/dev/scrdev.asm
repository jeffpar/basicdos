	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	SCR
	extrn	CON:dword

SCR	DDH	<offset CON,,DDATTR_CHAR,offset ddreq,offset ddint,2020202020524353h,offset ddinit>

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
	mov	ax,offset ddinit - offset SCR
	ret
ddinit	endp

DEV	ends

	end
