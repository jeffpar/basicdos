	include	dev.inc

DEV	segment para public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	CLOCK

CLOCK	DDH	<offset ddend,,DDATTR_CHAR,offset ddreq,offset ddint,2020244B434F4C43h>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

ddend	equ	$

DEV	ends

	end
