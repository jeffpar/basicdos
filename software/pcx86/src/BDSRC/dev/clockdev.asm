	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	CLOCK
	extrn	DRIVEA:dword

CLOCK	DDH	<offset DRIVEA,,DDATTR_CHAR,offset ddreq,offset ddint,2020244B434F4C43h,offset ddinit>

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
	mov	ax,offset ddinit - offset CLOCK
	ret
ddinit	endp

DEV	ends

	end
