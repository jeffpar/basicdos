;
; BASIC-DOS Memory Usage Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTSTR	<SYS_MEM,DOS_MEM,FREE_MEM>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMem
;
; Prints memory usage.
;
; Inputs:
;	DS:SI -> user-defined token (not used)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdMem
;
; Before we get into memory blocks, show the amount of memory reserved
; for the BIOS and disk buffers.
;
	push	bp
	push	es
	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING
	sub	bx,bx
	mov	ax,es
	push	di
	mov	di,cs
	mov	si,offset SYS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
;
; Next, dump the list of resident built-in device drivers.
;
drv1:	cmp	di,-1
	je	drv9
	lea	si,[di].DDH_NAME
	mov	bx,es
	mov	cx,bx
	mov	ax,es:[di].DDH_NEXT_SEG
	sub	ax,cx		; AX = # paras
	push	di
	mov	di,bx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
	les	di,es:[di]
	jmp	drv1
;
; Next, dump the size of the operating system, which resides between the
; built-in device drivers and the first memory block.
;
drv9:	mov	bx,es		; ES = DOS data segment
	mov	ax,es:[0]	; ES:[0] is mcb_head
	mov	bp,es:[2]	; ES:[2] is mcb_limit
	sub	ax,bx
	mov	di,cs
	mov	si,offset DOS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	es
	ASSUME	ES:CODE
;
; Next, examine all the memory blocks and display those that are used.
;
	push	bp
	sub	cx,cx
	sub	bp,bp		; BP = free memory
mem1:	mov	dl,0		; DL = 0 (query all memory blocks)
	mov	di,cs		; DI:SI -> default owner name
	mov	si,offset SYS_MEM
	mov	ax,DOS_UTL_QRYMEM
	int	21h
	jc	mem9		; all done
	test	ax,ax		; free block (is OWNER zero?)
	jne	mem2		; no
	add	bp,dx		; yes, add to total free paras
;
; Let's include free blocks in the report now, too.
;
	mov	si,offset FREE_MEM
	; jmp	short mem8

mem2:	mov	ax,dx		; AX = # paras
	push	cx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	cx
mem8:	inc	cx
	jmp	mem1
mem9:	xchg	ax,bp		; AX = free memory (paras)
	pop	bp		; BP = total memory (paras)
;
; Last but not least, dump the amount of free memory (ie, the sum of all the
; free blocks that we did NOT display above).
;
	mov	cx,16
	mul	cx		; DX:AX = free memory (in bytes)
	xchg	si,ax
	mov	di,dx		; DI:SI = free memory
	xchg	ax,bp
	mul	cx		; DX:AX = total memory (in bytes)
	PRINTF	<"%8ld bytes total",13,10,"%8ld bytes free",13,10>,ax,dx,si,di
	pop	bp
	ret
ENDPROC	cmdMem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printKB
;
; Converts the paragraph size in AX to Kb, by calculating AX/64 (or AX >> 6);
; however, that's a bit too granular, so we include tenths of Kb as well.
;
; Using the paragraph remainder (R), we calculate tenths (N): R/64 = N/10, so
; N = (R*10)/64.
;
; Inputs:
;	AX = size in paragraphs
;	BX = segment of memory block
;	DI:SI -> "owner" name for memory block
;
; Outputs:
;	None
;
DEFPROC	printKB
	push	ax
	push	bx
	mov	bx,64
	sub	dx,dx		; DX:AX = paragraphs
	div	bx		; AX = Kb
	xchg	cx,ax		; save Kb in CX
	xchg	ax,dx		; AX = paragraphs remainder
	mov	bl,10
	mul	bx		; DX:AX = remainder * 10
	mov	bl,64
	or	ax,31		; round up without adding
	div	bx		; AX = tenths of Kb
	ASSERT	NZ,<cmp ax,10>
	xchg	dx,ax		; save tenths in DX
	pop	bx
	pop	ax
	PRINTF	<"%#06x: %#06x %3d.%1dK %.8ls",13,10>,bx,ax,cx,dx,si,di
	ret
ENDPROC	printKB

CODE	ENDS

	end
