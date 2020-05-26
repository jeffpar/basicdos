	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	KBD

KBD	DDH	<-1,DDATTR_CHAR,offset ddreq,offset ddint>
	db	"KBD     "
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
