;
; BASIC-DOS System Initialization Code
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	extrn	dosexit:near, doscall:near

	ASSUME	CS:DOS, DS:BIOS, ES:BIOS, SS:BIOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; System initialization
;
; Everything after "init" will be recycled.
;
	public	init
init	proc	far
	int 3
	push	cs
	pop	ds
	ASSUME	DS:DOS
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
