	include	dos.inc

DOS	segment word public 'CODE'

	extrn	dosexit:near, doscall:near

	public	drivers
drivers	dd	?		; head of driver chain

	ASSUME	CS:DOS, DS:BIOS, ES:BIOS, SS:BIOS

;;;;;;;;
;
; System initialization
;
; Everything after "init" will be recycled.
;
	public	init
init	proc	far
	push	cs
	pop	ds
	ASSUME	DS:DOS
;
; Save head of driver chain (it was passed on the stack).
;
	pop	[drivers].off
	pop	[drivers].seg
;
; Initialize all the DOS vectors.
;
	mov	si,offset int_tbl
	mov	di,INT_DOS_EXIT * 4
i1:	lodsw
	test	ax,ax
	jz	i9
	stosw
	mov	ax,cs
	stosw
	jmp	i1

i9:	int 3
	jmp	i9
init	endp

int_tbl	dw	dosexit, doscall, 0

DOS	ends

	end
