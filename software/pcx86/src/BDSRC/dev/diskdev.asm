	include	dev.inc
;
; Diskette Drive Device Driver
;
DEV	segment para public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	DRIVEA

DRIVEA 	DDH	<offset ddend,,DDATTR_BLOCK,offset ddreq,offset ddint,2020202020202041h>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

DRIVEB 	DDH	<-1,,DDATTR_BLOCK,offset ddreq,offset ddint,2020202020202042h>
DRIVEC 	DDH	<-1,,DDATTR_BLOCK,offset ddreq,offset ddint,2020202020202043h>
DRIVED 	DDH	<-1,,DDATTR_BLOCK,offset ddreq,offset ddint,2020202020202044h>

ddend	equ	$

DEV	ends

	end
