	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	public	LPT1
	extrn	CLOCK:dword

LPT1	DDH	<offset LPT2,,DDATTR_CHAR,offset ddreq,offset ddint,202020203154504Ch,offset ddinit>

ddreq	proc	far
	ret
ddreq	endp

ddint	proc	far
	ret
ddint	endp

LPT2	DDH	<offset LPT3,,DDATTR_CHAR,offset ddreq,offset ddint,202020203254504Ch,offset ddinit>
LPT3	DDH	<offset CLOCK,,DDATTR_CHAR,offset ddreq,offset ddint,202020203354504Ch,offset ddinit>

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
	cmp	[PRINTER_BASE][bx],ax
	je	i9		; return zero in AX, indicating removal
	mov	ax,offset ddinit - offset LPT1
i9:	ret
ddinit	endp

DEV	ends

	end
