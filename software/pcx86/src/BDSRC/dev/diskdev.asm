	include	dev.inc
;
; Diskette Drive (DISKDEV) Device Driver
;
DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	DDRIVE

DDRIVE 	DDH	<-1,DDATTR_BLOCK,offset ddreq,offset ddint>
	db	"A:      "
	dw	ddinit

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

ddinit	proc	far
	ret
ddinit	endp

DEV	ends

	end
