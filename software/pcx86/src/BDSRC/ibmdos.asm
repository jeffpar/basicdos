	include	dos.inc

DOS	segment word public 'CODE'

	extrn	dosexit:near, doscall:near

	public	drivers
drivers	dd	?		; head of driver chain

	ASSUME	CS:DOS, DS:BIOS, ES:BIOS, SS:BIOS
;
; System initialization
;
; Everything after "init" is discarded.
;
; The head of the driver chain is pushed on the stack.
;
	public	init
init	proc	far
	int 3
	push	cs
	pop	ds
	ASSUME	DS:DOS
	pop	[drivers].off
	pop	[drivers].seg
	mov	si,offset int_tbl
	mov	di,INT_DOS_EXIT * 4
i1:	lods	word ptr cs:[si]
	test	ax,ax
	jz	i9
	stosw
	mov	ax,cs
	stosw
	jmp	i1
i9:	jmp	i9
init	endp

int_tbl	dw	dosexit, doscall, 0

DOS	ends

	end
