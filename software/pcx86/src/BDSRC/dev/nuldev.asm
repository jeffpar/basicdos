	include	dev.inc
;
; The NUL device.
;
; NOTE: This file must be named something OTHER than "NUL.ASM", because in
; DOS, all filenames of the form "NUL.*" are ignored (ie, treated as references
; to the "NUL" device).
;

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	extrn	init:near
;
; The NUL device must be the first object module in the image.
;
	jmp	init

	public	NUL

NUL	DDH	<-1,DDATTR_CHAR,offset ddreq,offset ddint>
	db	"NUL     "
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
