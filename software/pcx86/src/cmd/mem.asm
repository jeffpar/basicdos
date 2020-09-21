;
; BASIC-DOS Memory Management Functions
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

	IFDEF	DEBUG
	EXTSTR	<SYS_MEM,DOS_MEM,FREE_MEM>
	ENDIF	; DEBUG

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocBlock
;
; Allocates a block of memory for the given block chain.  All blocks must
; begin with the following:
;
;	BLK_NEXT (segment of next block in chain)
;	BLK_SIZE (size of block, in bytes)
;	BLK_FREE (offset of next free byte in block)
;
; Inputs:
;	CX = size of block, in bytes
;	SI = offset of block chain head
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte in new block
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	allocBlock
	push	bx
	push	cx
	mov	bx,cx
	add	bx,15
	xchg	cx,ax
	mov	cl,4
	shr	bx,cl
	xchg	cx,ax
	mov	ah,DOS_MEM_ALLOC
	int	21h
	jc	ab8

	mov	es,ax
	sub	di,di
	sub	ax,ax
	stosw				; set BLK_NEXT
	mov	ax,cx
	stosw				; set BLK_SIZE
	mov	al,[si].BLK_HDR
	cbw
	stosw				; set BLK_FREE
	mov	al,[si].BLK_SIG
	stosw				; set BLK_SIG/BLK_PAD
	cmp	al,SIG_VBLK
	jne	ab1
	dec	di
	mov	al,VAR_LONG
	stosb				; initialize VBLK_ZERO
	sub	ax,ax
	stosw
	stosw
ab1:	sub	ax,ax
	sub	cx,di
	shr	cx,1
	rep	stosw			; zero out the rest of the block
	jnc	ab2
	stosb
;
; Block is initialized, append to the header chain now.
;
ab2:	push	ds
	mov	di,si			; DS:DI -> first segment in chain
ab3:	mov	cx,[di]			; at the end yet?
	jcxz	ab4			; yes
	mov	ds,cx
	sub	di,di
	jmp	ab3
ab4:	mov	[di],es			; chain updated
	mov	di,es:[CBLK_FREE]	; ES:DI -> first available byte
	pop	ds
	clc
	jmp	short ab9

ab8:	call	memError

ab9:	pop	cx
	pop	bx
	ret
ENDPROC	allocBlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeBlock
;
; Frees a block of memory for the given block chain.
;
; Inputs:
;	ES = segment of block
;	SI = offset of block chain head
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	CX, SI
;
DEFPROC	freeBlock
	push	ax
	push	ds			; DS:SI -> first segment in chain
	mov	ax,es
fb1:	mov	cx,[si]
	jcxz	fb9			; ended without match, free anyway
	cmp	cx,ax			; find a match yet?
	je	fb2			; yes
	mov	ds,cx
	sub	si,si
	jmp	fb1
fb2:	mov	ax,es:[CBLK_NEXT]
	mov	[si],ax
	pop	ds
fb9:	mov	ah,DOS_MEM_FREE
	int	21h
	pop	ax
	ret
ENDPROC	freeBlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeAllBlocks
;
; Frees all blocks of memory for the given block chain.
;
; Inputs:
;	SI = offset of block chain head
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	CX, SI
;
DEFPROC	freeAllBlocks
	push	es
fa1:	mov	cx,[si]
	jcxz	fa9			; end of chain
	mov	es,cx
	call	freeBlock		; ES = segment of block to free
	jmp	fa1
fa9:	pop	es
	ret
ENDPROC	freeAllBlocks

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocCode
;
; Inputs:
;	None
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte, CX = length
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	allocCode
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].CODE_BLK
	mov	cx,CBLKLEN
	jmp	allocBlock
ENDPROC	allocCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeCode
;
; Frees all code blocks and resets the CODE_BLK chain.
;
; Inputs:
;	None
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	CX, SI
;
DEFPROC	freeCode
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].CODE_BLK
	jmp	freeAllBlocks
ENDPROC	freeCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocText
;
; Inputs:
;	CX = text block size (in bytes)
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte, CX = length
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	allocText
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].TEXT_BLK
	jmp	allocBlock
ENDPROC	allocText

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeText
;
; Frees all text blocks and resets the TEXT_BLK chain.
;
; Inputs:
;	None
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	CX, SI
;
DEFPROC	freeText
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].TEXT_BLK
	jmp	freeAllBlocks
ENDPROC	freeText

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocVars
;
; Allocates a var block if one is not already allocated.
;
; Inputs:
;	None
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte, CX = length
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	allocVars
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].VARS_BLK
	cmp	[si].BLK_NEXT,0
	jne	al9
	mov	cx,VBLKLEN
	jmp	allocBlock
al9:	ret
ENDPROC	allocVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeVars
;
; Frees all VBLKS and resets the chain.
;
; Inputs:
;	None
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	CX, SI
;
DEFPROC	freeVars
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].VARS_BLK
	jmp	freeAllBlocks
ENDPROC	freeVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocStrSpace
;
; Allocates an SBLK and adds it to the STRS_BLK chain.
;
; Inputs:
;	None
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte, CX = length
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	allocStrSpace
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].STRS_BLK
	mov	cx,SBLKLEN
	jmp	allocBlock
ENDPROC	allocStrSpace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeStrSpace
;
; Frees all SBLKs and resets the STRS_BLK chain.
;
; Inputs:
;	None
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	CX, SI
;
DEFPROC	freeStrSpace
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].STRS_BLK
	jmp	freeAllBlocks
ENDPROC	freeStrSpace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addVar
;
; Variables start with a byte length (the length of the name), followed by
; the name of the variable, followed by the variable data.  The name length
; is limited to VAR_NAMELEN.
;
; Note that, except for numbers (integers and floating point values), the
; variable data is generally a far pointer to the actual data; for example, a
; string variable is just a far pointer to a location inside a string pool.
;
; Inputs:
;	AL = CLS_VAR_*
;	CX = length of name
;	DS:SI -> variable name
;
; Outputs:
;	If carry clear, AH = var type, DX -> var data
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	addVar
	and	al,VAR_TYPE		; convert CLS_VAR_* to VAR_TYPE
	call	findVar
	jnc	av10

	push	di
	push	es
	mov	di,ds:[PSP_HEAP]
	mov	es,[di].VARS_BLK.BLK_NEXT
	ASSERT	STRUCT,es:[0],VBLK
	mov	di,es:[VBLK_FREE]
	push	ax

	cmp	cx,VAR_NAMELEN
	jbe	av0
	mov	cx,VAR_NAMELEN
av0:	push	di
	add	di,cx
	mov	dl,2			; minimum associated data size
	cmp	al,VAR_INT
	jbe	av1
	mov	dl,4
	cmp	al,VAR_DOUBLE
	jb	av1
	mov	dl,8
av1:	mov	dh,0
	add	di,dx
	inc	di			; one for the length byte
	cmp	es:[VBLK_SIZE],di	; enough room?
	pop	di
	jb	av9			; no (carry set)
;
; Build the new variable at ES:DI, with combined length and type in the
; first byte, the variable name in the following bytes, and zero-initialized
; data in the remaining bytes.
;
	mov	ah,al			; AH = var type
	or	al,cl
	stosb
av2:	lodsb				; rep movsb would be nice here
	cmp	al,'a'			; but we upper-case the var name now
	jb	av3
	sub	al,20h
av3:	stosb
	loop	av2
	mov	cl,dl
	mov	al,0
	mov	dx,di			; DX = offset of variable's data
	rep	stosb
	mov	es:[VBLK_FREE],di
	cmp	es:[VBLK_SIZE],di
	ASSERT	AE
	je	av8
	stosb				; ensure there's always a zero after
av8:	jmp	retVar

av9:	pop	ax
	pop	es
	pop	di
av10:	ret
ENDPROC	addVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findVar
;
; Inputs:
;	CX = length of name
;	DS:SI -> variable name
;
; Outputs:
;	If carry clear, AH = var type, DX -> var data
;	If carry set, AH = VAR_LONG, DX -> zero constant
;
; Modifies:
;	AH, DX
;
DEFPROC	findVar
	push	di
	push	es
	mov	di,ds:[PSP_HEAP]
	mov	es,[di].VARS_BLK.BLK_NEXT
	ASSERT	STRUCT,es:[0],VBLK
	mov	di,size VBLK_HDR	; ES:DI -> first var in block
	push	ax

fv1:	mov	al,es:[di]
	inc	di
	test	al,al			; end of variables in the block?
	jnz	fv2			; no
	stc
	mov	ah,VAR_LONG
	mov	dx,offset VBLK_ZERO + 1
	jmp	short retVar		; yes

fv2:	mov	ah,al
	and	ah,VAR_TYPE
	and	al,VAR_NAMELEN
	cmp	al,cl			; do the name lengths match?
	jne	fv6			; no

	push	ax
	push	cx
	push	si
	push	di
fv3:	lodsb				; rep cmpsb would be nice here
	cmp	al,'a'			; especially since it doesn't use AL
	jb	fv4			; but tokens are not upper-cased first
	sub	al,20h
fv4:	scasb
	jne	fv5
	loop	fv3
	mov	dx,di			; DX -> variable data
fv5:	pop	di
	pop	si
	pop	cx
	pop	ax
	je	retVar			; match!

fv6:	add	al,2			; add at least 2 bytes for data
	cmp	ah,VAR_INT		; just an INT?
	jbe	fv7			; yes, good enough
	add	al,2			; add 2 more data bytes
	cmp	ah,VAR_DOUBLE		; good enough?
	jb	fv7			; yes
	add	al,4			; no, add 4 more (for a total of 8)
fv7:	cbw
	add	di,ax			; bump to next variable
	jmp	fv1			; keep looking

	DEFLBL	retVar,near
	mov	di,dx
	pop	dx
	mov	al,dl			; AH = var type (AL unchanged)
	mov	dx,di			; DX -> var data

fv9:	pop	es
	pop	di
	ret
ENDPROC	findVar

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
	IFDEF	DEBUG
	mov	al,'D'
	call	checkSW
	jz	mem0
	inc	dx
	ENDIF	; DEBUG

mem0:	ENTER
	mov	[memSwitches],dx
;
; Before we get into memory blocks, show the amount of memory reserved
; for the BIOS and disk buffers.
;
	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING

	IFDEF	DEBUG
	sub	bx,bx
	mov	ax,es
	push	di
	mov	di,cs
	mov	si,offset SYS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
	ENDIF	; DEBUG
;
; Next, dump the list of resident built-in device drivers.
;
drv1:	cmp	di,-1
	je	drv9

	IFDEF	DEBUG
	lea	si,[di].DDH_NAME
	mov	bx,es
	mov	cx,bx
	mov	ax,es:[di].DDH_NEXT_SEG
	sub	ax,cx		; AX = # paras
	push	di
	mov	di,bx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
	ENDIF	; DEBUG

	les	di,es:[di]
	jmp	drv1
;
; Next, dump the size of the operating system, which resides between the
; built-in device drivers and the first memory block.
;
drv9:	mov	di,es:[2]	; ES:[2] is mcb_limit
	mov	[memLimit],di

	IFDEF	DEBUG
	mov	ax,es:[0]	; ES:[0] is mcb_head
	mov	bx,es		; ES = DOS data segment
	sub	ax,bx
	mov	di,cs
	mov	si,offset DOS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	ENDIF	; DEBUG
;
; Next, examine all the memory blocks and display those that are used.
;
	sub	cx,cx
	mov	[memFree],cx

mem1:	mov	dl,0		; DL = 0 (query all memory blocks)

	IFDEF	DEBUG
	mov	di,cs		; DI:SI -> default owner name
	mov	si,offset SYS_MEM
	ENDIF	; DEBUG

	DOSUTIL	DOS_UTL_QRYMEM
	jc	mem9		; all done
	test	ax,ax		; free block (is OWNER zero?)
	jne	mem2		; no
	add	[memFree],dx	; yes, add to total free paras
;
; Let's include free blocks in the report now, too.
;
	IFDEF	DEBUG
	mov	si,offset FREE_MEM
	; jmp	short mem8
	ENDIF	; DEBUG
mem2:
	IFDEF	DEBUG
	mov	ax,dx		; AX = # paras
	push	cx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	cx
	ENDIF	; DEBUG

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
	IFDEF	DEBUG
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
	ENDIF	; DEBUG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; memError
;
; Inputs:
;	AX = error #
;
; Outputs:
;	Carry set
;
; Modifies:
;	AX
;
DEFPROC	memError
	PRINTF	<"Not enough memory (%#06x)",13,10>,ax
	stc
	ret
ENDPROC	memError

CODE	ENDS

	end
