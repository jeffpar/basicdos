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

DOS	segment para public 'CODE'

	extrn	dosexit:near, doscall:near

	ASSUME	CS:DOS, DS:BIOS, ES:BIOS, SS:BIOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; System initialization
;
; Everything after "dosinit" will be recycled.
;
	public	dosinit
dosinit	proc	far
	int 3
;
; First, let's move all our init code out of the way, to the top of
; available memory.
;
; Size is in Kb (2^10 units), we need size in paragraphs (2^4 units), so
; shift left 6 bits.  Then calculate init code size in paras and subtract.
;
	mov	ax,[MEMORY_SIZE]	; AX = available memory in Kb
	mov	cl,6
	shl	ax,cl			; AX = available memory in paras
	sub	ax,(offset dosinit_end - offset dosinit + 15) SHR 4
	mov	dx,offset dosinit
	mov	cl,4
	shr	dx,cl
	sub	ax,dx			; AX = segment adjusted for ORG addr
	push	es
	mov	es,ax
	ASSUME	ES:NOTHING
	mov	si,offset dosinit
	mov	di,si
	mov	cx,(offset dosinit_end - offset dosinit) SHR 1
	rep	movs word ptr es:[di],word ptr cs:[si]
	pop	es
	ASSUME	ES:BIOS
	push	ax			; push new segment on stack
	mov	ax,offset dosinit2
	push	ax			; push new offset on stack
	ret				; far return to dosinit2
dosinit2:				; now running in upper memory
	push	cs
	pop	ds
	ASSUME	DS:DOS			; DS valid for init code/data only
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
dosinit	endp

int_tbl	dw	dosexit, doscall, 0

dosinit_end equ $

DOS	ends

	end
