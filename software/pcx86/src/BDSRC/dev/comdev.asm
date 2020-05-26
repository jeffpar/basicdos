	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	COM1
	extrn	PRN:dword

COM1	DDH	<offset COM2,,DDATTR_CHAR,offset ddreq,offset ddint,20202020314D4F43h,offset ddinit>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

COM2	DDH	<offset COM3,,DDATTR_CHAR,offset ddreq,offset ddint,20202020324D4F43h,offset ddinit>
COM3	DDH	<offset COM4,,DDATTR_CHAR,offset ddreq,offset ddint,20202020334D4F43h,offset ddinit>
COM4	DDH	< offset PRN,,DDATTR_CHAR,offset ddreq,offset ddint,20202020344D4F43h,offset ddinit>

;;;;;;;;
;
; Driver initialization
;
; Entry: DS:SI -> DDH, SS = BIOS
;
; Returns: AX = size of device driver, zero to remove
;
ddinit	proc	near
	ASSUME	DS:DEV, ES:NOTHING, SS:BIOS
	sub	ax,ax
	sub	bx,bx
	mov	bl,byte ptr [si].DDH_NAME+3
	sub	bl,31h
	add	bx,bx
	cmp	[RS232_BASE][bx],ax
	je	i9		; return zero in AX, indicating removal
	mov	ax,offset ddinit - offset COM1
i9:	ret
ddinit	endp

DEV	ends

	end
