	include	dev.inc
;
; Diskette Drive Device Driver
;
DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	DRIVEA

DRIVEA 	DDH	<offset DRIVEB,,DDATTR_BLOCK,offset ddreq,offset ddint,2020202020202041h,offset ddinit>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

DRIVEB 	DDH	<offset DRIVEC,,DDATTR_BLOCK,offset ddreq,offset ddint,2020202020202042h,offset ddinit>
DRIVEC 	DDH	<offset DRIVED,,DDATTR_BLOCK,offset ddreq,offset ddint,2020202020202043h,offset ddinit>
DRIVED 	DDH	<           -1,,DDATTR_BLOCK,offset ddreq,offset ddint,2020202020202044h,offset ddinit>

;;;;;;;;
;
; Driver initialization
;
; Returns: AX = size of device driver
;
ddinit	proc	near
	mov	ax,offset ddinit - offset DRIVEA
	ret
ddinit	endp

DEV	ends

	end
