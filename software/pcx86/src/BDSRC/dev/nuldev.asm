	include	dev.inc

DEV	segment para public 'CODE'

	public	NUL
NUL	DDH	<offset ddend,,DDATTR_CHAR,offset ddreq,offset ddint,20202020204C554Eh>

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

ddend	equ	$

DEV	ends

	end
