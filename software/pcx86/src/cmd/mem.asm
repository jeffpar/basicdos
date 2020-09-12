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

	EXTERNS	<checkSW>,near

	EXTSTR	<SYS_MEM,DOS_MEM,FREE_MEM>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMem
;
; Prints memory usage.  Use /D to display segment-level detail.
;
; Inputs:
;	DS:BX -> heap (not used)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdMem
	LOCVAR	memFree,word	; free paras
	LOCVAR	memLimit,word	; max available paras
	LOCVAR	memSwitches,word
;
; Before we create our own stack frame, get any switch information
; we'll need, since it's stored on caller's stack frame.
;
	sub	dx,dx
	IFDEF DEBUG
	mov	al,'D'
	call	checkSW
	jz	mem0
	inc	dx
	ENDIF

mem0:	ENTER
	mov	[memSwitches],dx
;
; Before we get into memory blocks, show the amount of memory reserved
; for the BIOS and disk buffers.
;
	push	es		; save ES

	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING

	IFDEF DEBUG
	sub	bx,bx
	mov	ax,es
	push	di
	mov	di,cs
	mov	si,offset SYS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
	ENDIF
;
; Next, dump the list of resident built-in device drivers.
;
drv1:	cmp	di,-1
	je	drv9

	IFDEF DEBUG
	lea	si,[di].DDH_NAME
	mov	bx,es
	mov	cx,bx
	mov	ax,es:[di].DDH_NEXT_SEG
	sub	ax,cx		; AX = # paras
	push	di
	mov	di,bx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
	ENDIF

	les	di,es:[di]
	jmp	drv1
;
; Next, dump the size of the operating system, which resides between the
; built-in device drivers and the first memory block.
;
drv9:	mov	di,es:[2]	; ES:[2] is mcb_limit
	mov	[memLimit],di

	IFDEF DEBUG
	mov	ax,es:[0]	; ES:[0] is mcb_head
	mov	bx,es		; ES = DOS data segment
	sub	ax,bx
	mov	di,cs
	mov	si,offset DOS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	ENDIF

	pop	es		; restore ES
	ASSUME	ES:CODE
;
; Next, examine all the memory blocks and display those that are used.
;
	sub	cx,cx
	mov	[memFree],cx

mem1:	mov	dl,0		; DL = 0 (query all memory blocks)

	IFDEF DEBUG
	mov	di,cs		; DI:SI -> default owner name
	mov	si,offset SYS_MEM
	ENDIF

	mov	ax,DOS_UTL_QRYMEM
	int	21h
	jc	mem9		; all done
	test	ax,ax		; free block (is OWNER zero?)
	jne	mem2		; no
	add	[memFree],dx	; yes, add to total free paras
;
; Let's include free blocks in the report now, too.
;
	IFDEF DEBUG
	mov	si,offset FREE_MEM
	; jmp	short mem8
	ENDIF
mem2:
	IFDEF DEBUG
	mov	ax,dx		; AX = # paras
	push	cx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	cx
	ENDIF

mem8:	inc	cx
	jmp	mem1

mem9:	mov	ax,[memFree]	; AX = free memory (paras)
;
; Last but not least, dump the amount of free memory (ie, the sum of all the
; free blocks that we did NOT display above).
;
	mov	cx,16
	mul	cx		; DX:AX = free memory (in bytes)
	xchg	si,ax
	mov	di,dx		; DI:SI = free memory
	mov	ax,[memLimit]
	mul	cx		; DX:AX = total memory (in bytes)
	PRINTF	<"%8ld bytes",13,10,"%8ld bytes free",13,10>,ax,dx,si,di
	LEAVE
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
	IFDEF DEBUG

DEFPROC	printKB
	test	[memSwitches],1	; detail requested (/D)?
	jz	pkb9		; no
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
pkb9:	ret
ENDPROC	printKB

	ENDIF

CODE	ENDS

	end
