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

	extrn	MCB_HEAD:word

	ASSUME	CS:DOS, DS:BIOS, ES:BIOS, SS:BIOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; System initialization
;
; Everything after "sysinit" will be recycled.
;
	public	sysinit
sysinit	proc	far
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
	mov	dx,ax			; DX = paragraph of end of memory
	sub	ax,(offset sysinit_end - offset sysinit + 15) SHR 4
	mov	bx,offset sysinit
	mov	cl,4
	shr	bx,cl			; BX = paragraph of sysinit
	sub	ax,bx			; AX = segment adjusted for ORG addr
	push	es
	mov	es,ax
	ASSUME	ES:NOTHING
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	si,offset sysinit
	mov	di,si
	mov	cx,(offset sysinit_end - offset sysinit) SHR 1
	rep	movsw
	pop	es
	ASSUME	ES:BIOS
	push	ax			; push new segment on stack
	mov	ax,offset sysinit2
	push	ax			; push new offset on stack
	ret				; far return to sysinit2
sysinit2:				; now running in upper memory
	ASSUME	CS:DOS,DS:DOS
;
; Initialize all the DOS vectors.
;
; NOTE: We have to be very careful with CS and DS references now.
; CS is high, valid only for init code/data, and DS is low, valid only
; for resident code/data.
;
	mov	si,offset int_tbl
	mov	di,INT_DOS_EXIT * 4
i1:	lods	word ptr cs:[si]
	test	ax,ax
	jz	i2
	stosw
	mov	ax,ds
	stosw
	jmp	i1
;
; Initialize the MCB chain.
;
i2:	mov	ax,ds
	add	bx,ax
	mov	[MCB_HEAD],bx
	mov	es,bx
	sub	di,di
	ASSUME	ES:NOTHING
	mov	al,MCB_LAST
	stosb				; mov es:[0].MCB_SIG,MCB_LAST
	sub	ax,ax
	stosw				; mov es:[0].MCB_OWNER,0
	sub	dx,bx			; DX = top para minus sysinit para
	xchg	ax,dx			; AX is now DX
	dec	ax			; AX reduced by 1 para (for MCB_HDR)
	stosw				; mov es:[0].MCB_PARAS,ax
	mov	cl,size MCB_RESERVED
	mov	al,0
	rep	stosb

i9:	jmp	i9
sysinit	endp

	extrn	dosexit:near, doscall:near

	even
int_tbl	dw	dosexit, doscall, 0

sysinit_end equ $

DOS	ends

	end
