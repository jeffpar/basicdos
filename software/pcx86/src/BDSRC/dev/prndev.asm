	include	dev.inc

DEV	segment para public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	PRN

PRN	DDH	<offset ddend,,DDATTR_CHAR,offset ddreq,offset ddint,20202020204E5250h>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

ddend	equ	$

DEV	ends

	end
