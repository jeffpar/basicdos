;
; BASIC-DOS Memory Management Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<memError,genCode,clearVars,compactStrs>
	EXTBYTE	<PREDEF_VARS>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocBlock
;
; Allocates a block of memory for the given block chain.  All chains begin
; with a BLKDEF, and all blocks begin with a BLKHDR:
;
;	BLK_NEXT (segment of next block in chain)
;	BLK_SIZE (size of block, in bytes)
;	BLK_FREE (offset of next free byte in block)
;
; To be as forgiving as possible when memory is low or fragmented, chains
; consist of modest blocks that are allocated as needed (rather than large
; blocks that must grow).  We never take more than a quarter of the largest
; free memory block, so that one type of block doesn't starve the others, and
; if a block of the preferred size (BDEF_SIZE) isn't available, we keep halving
; the size (down to MIN_BLKSIZE) and trying again.  Callers that care about the
; size should check BLK_SIZE.
;
; allocBlockMin allows the caller to specify the preferred and minimum sizes,
; and allocBlockSize requires a specific size (eg, for an array).
;
; Inputs:
;	SI = offset of block chain head
;	CX = preferred size of block, in bytes (allocBlockMin, allocBlockSize)
;	DX = minimum size of block, in bytes (allocBlockMin)
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte in new block
;
; Modifies:
;	AX, DI, ES
;
MIN_BLKSIZE	equ	512
MEM_HIGH	equ	80h		; MCBTYPE_HIGH (see memory.asm)

DEFPROC	allocBlock
	push	cx
	push	dx
	mov	cx,[si].BDEF_SIZE
	mov	dx,MIN_BLKSIZE
	call	allocBlockMin
	pop	dx
	pop	cx
	ret
ENDPROC	allocBlock

DEFPROC	allocBlockSize
	push	dx
	mov	dx,cx
	call	allocBlockMin
	pop	dx
	ret
ENDPROC	allocBlockSize

DEFPROC	allocBlockMin
	push	bx
	push	cx
	mov	bx,0FFFFh
	mov	ah,DOS_MEM_ALLOC
	int	21h			; BX = largest free block (in paras)
	mov	ax,0FFFFh
	cmp	bx,4000h
	jae	ab0
	mov	ax,bx
	add	ax,ax
	add	ax,ax			; AX = 1/4 of largest block (bytes)
ab0:	cmp	cx,ax			; is the preferred size larger?
	jbe	ab1			; no
	mov	cx,ax			; yes, so use a quarter instead
	cmp	cx,dx			; but no less than the minimum
	jae	ab1
	mov	cx,dx
ab1:	mov	bx,cx
	add	bx,15
	xchg	cx,ax
	mov	cl,4
	shr	bx,cl			; BX = # paragraphs
	xchg	cx,ax
	mov	ah,DOS_MEM_ALLOC
	mov	al,[si].BDEF_SIG
	or	al,MEM_HIGH		; allocate from the top of memory, so
	int	21h			; that freed memory below stays contiguous
	jnc	ab2
	shr	cx,1			; try half the size
	cmp	cx,dx			; unless that's less than the minimum
	jae	ab1
	jmp	short ab8

ab2:	mov	es,ax
	sub	di,di
	sub	ax,ax
	stosw				; set BLK_NEXT
	mov	ax,cx
	stosw				; set BLK_SIZE
	mov	al,[si].BDEF_HDR
	cbw
	stosw				; set BLK_FREE
	mov	al,[si].BDEF_SIG
	stosw				; set BLK_SIG/BLK_PAD
	sub	ax,ax
	sub	cx,di
	shr	cx,1
	rep	stosw			; zero out the rest of the block
	jnc	ab3
	stosb
;
; Block is initialized, append to the header chain now.
;
ab3:	push	ds
	lea	di,[si].BDEF_NEXT	; DS:DI -> first segment in chain
ab4:	mov	cx,[di]			; at the end yet?
	jcxz	ab5			; yes
	mov	ds,cx
	sub	di,di
	jmp	ab4
ab5:	mov	[di],es			; chain updated
	mov	di,es:[BLK_FREE]	; ES:DI -> first available byte
	pop	ds
	clc
	jmp	short ab9

ab8:	call	memError

ab9:	pop	cx
	pop	bx
	ret
ENDPROC	allocBlockMin

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
	ASSERT	NZ,<test cx,cx>
	jcxz	fb9			; ended without match, free anyway?
	cmp	cx,ax			; find a match yet?
	je	fb2			; yes
	mov	ds,cx
	sub	si,si
	jmp	fb1
fb2:	mov	ax,es:[BLK_NEXT]
	mov	[si],ax
fb9:	mov	ah,DOS_MEM_FREE		; free segment in ES
	int	21h
	pop	ds
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
	clc
	push	es
fa1:	mov	cx,[si]
	jcxz	fa9			; end of chain
	mov	es,cx
	call	freeBlock		; ES = segment of block to free
	jnc	fa1
fa9:	pop	es
	ret
ENDPROC	freeAllBlocks

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; saveChains
;
; Saves (and empties) the selected block chains in a CHAINS frame on the
; stack, and makes it the current frame (CMD_CHAINS), so that a BAT or BAS
; file run by another can't free any of its caller's blocks.  The caller
; must remove the frame with restoreChains.
;
; Bit n of the mask is set to save the nth BLKDEF in CMDHEAP (eg, 11h for
; CBLKDEF and TBLKDEF, or 3Fh for all six).
;
; Inputs:
;	AL = mask of chains to save
;	AH = non-zero to keep the new chains (see restoreChains)
;	BX -> command line (a string on the stack; see cmdFile and strArg)
;
; Outputs:
;	SP -> CHAINS frame (on return)
;
; Modifies:
;	AX, DI
;
CHAINS		struc
CH_ARGS		dw	?		; command line (strArg assumes offset 0)
CH_MASK		dw	?		; bit n set if head n was saved
CH_PREV		dw	?		; previous CHAINS frame, if any
CH_HEADS	dw	6 dup (?)	; saved CBLKDEF through ABLKDEF heads
CHAINS		ends

DEFPROC	saveChains
	push	cx
	push	si
	call	freeCache		; any loaded program must recompile
	pop	si
	pop	cx
	pop	di			; DI = return address
	sub	sp,size CHAINS
	push	di
	push	cx
	push	si
	mov	di,sp
	add	di,6			; DI -> CHAINS frame
	mov	si,ds:[PSP_HEAP]
	mov	[di].CH_ARGS,bx
	mov	[di].CH_MASK,ax
	mov	cx,di
	xchg	cx,[si].CMD_CHAINS
	mov	[di].CH_PREV,cx
	add	di,CH_HEADS
sc1:	shr	al,1
	jnc	sc2
	sub	cx,cx
	xchg	cx,[si].BDEF_NEXT
	mov	[di],cx
sc2:	inc	di
	inc	di
	add	si,size BLKDEF
	test	al,al
	jnz	sc1
	pop	si
	pop	cx
	ret
ENDPROC	saveChains

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; restoreChains
;
; Removes a CHAINS frame (see saveChains) from the list of frames.  Normally,
; we free the blocks of every chain that was saved and then restore the saved
; chain; but if the program was aborted, we free the saved blocks instead, so
; that the program that was running remains loaded.
;
; If AL is 2, the CHAINS frame decides: the high byte of CH_MASK is non-zero
; if saveChains was asked to keep the new chains (eg, for a BAS file run from
; the command prompt, which remains loaded, like MSBASIC).
;
; Inputs:
;	AL = 0 to restore the saved chains, 1 to free them, 2 to let CH_MASK
;	decide
;	DI -> CHAINS frame
;
; Outputs:
;	DI -> end of CHAINS frame
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	restoreChains
	cmp	al,2
	jne	rc0
	mov	al,byte ptr [di].CH_MASK+1
rc0:	test	al,al			; restoring the saved chains?
	jnz	rc0a			; no
	call	freeCache		; yes, so free the file's code, too
rc0a:	mov	si,ds:[PSP_HEAP]
	mov	cx,[di].CH_PREV
	mov	[si].CMD_CHAINS,cx
	mov	ah,byte ptr [di].CH_MASK
	add	di,CH_HEADS
	mov	cx,6
rc1:	shr	ah,1
	jnc	rc3
	push	cx
	push	si
	test	al,al
	jz	rc2
	mov	si,di			; free the saved chain instead
rc2:	call	freeAllBlocks
	pop	si
	pop	cx
	test	al,al
	jnz	rc3
	push	ax
	mov	ax,[di]
	mov	[si].BDEF_NEXT,ax	; restore the saved chain
	pop	ax
rc3:	inc	di
	inc	di
	add	si,size BLKDEF
	loop	rc1
	ret
ENDPROC	restoreChains

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocCode
;
; Inputs:
;	BX -> CMDHEAP
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte
;
; Modifies:
;	AX, SI, DI, ES
;
DEFPROC	allocCode
	lea	si,[bx].CBLKDEF
	DEFLBL	allocCodeBlock,near
	call	allocBlock
	jc	ac9
;
; ES:[BLK_SIZE] is the absolute limit for generated code, but we also maintain
; ES:[CBLK_REFS] as the bottom of the block's LBLREF table, and that's the real
; limit that the code generator must be mindful of.
;
; Initialize the block's LBLREF table; it's empty when CBLK_REFS = BLK_SIZE.
;
	mov	ax,es:[BLK_SIZE]
	mov	es:[CBLK_REFS],ax
ac9:	ret
ENDPROC	allocCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ensureRoom
;
; Makes sure there's room in the code (or function) block for at least the
; specified number of bytes (plus a JMPF), before the LBLREF table.  The code
; generator calls this at "safe points" (eg, before every command, expression
; token, and operator; see CODE_ROOM), where no code that has already been
; generated depends on the code that follows being in the same block.
;
; If there isn't enough room in a code block, we allocate another code block
; (preferably CBLKLEN bytes, but we'll settle for less), and end the current
; block with a JMPF to the new block (whereas a function block can't be
; extended, so that's an error).  Code blocks never move, since generated code
; may contain the addresses of other code blocks (eg, in JMPFs and FORSLOTs).
;
; Inputs:
;	AX = # of bytes required
;	ES:DI -> next unused byte in code (or function) block
;
; Outputs:
;	Carry clear if successful (ES:DI may be a new code block), set if not
;
; Modifies:
;	AX
;
DEFPROC	ensureRoom
	push	cx
	mov	cx,es:[CBLK_REFS]	; (FBLK_REFS is the same)
	sub	cx,di			; CX = bytes available
	sub	cx,5			; minus a JMPF
	jb	er1			; not even that much room
	cmp	cx,ax			; enough?
	jae	er9			; yes (carry clear)
er1:	cmp	es:[BLK_SIG],SIG_CBLK	; code block?
	stc
	jne	er9			; no
	push	dx
	push	si
	push	ds
	push	es
	push	di
	add	ax,size CBLK + 5
	xchg	dx,ax			; DX = minimum size of new block
	mov	cx,CBLKLEN		; CX = preferred size
	cmp	cx,dx
	jae	er2
	mov	cx,dx
er2:	push	ss
	pop	ds
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].CBLKDEF
	call	allocBlockMin		; ES:DI -> new code block
	jc	er8
	mov	ax,es:[BLK_SIZE]
	mov	es:[CBLK_REFS],ax
	mov	cx,es			; CX:DX -> new code block
	mov	dx,di
	pop	di
	pop	es			; ES:DI -> current code block
	mov	al,OP_JMPF
	stosb
	xchg	ax,dx
	stosw
	xchg	ax,cx
	stosw				; JMPF to the new code block
	mov	es:[BLK_FREE],di
	mov	es,ax
	mov	di,cx			; ES:DI -> new code block
	clc
	jmp	short er8a
er8:	pop	di
	pop	es
er8a:	pop	ds
	pop	si
	pop	dx
er9:	pop	cx
	ret
ENDPROC	ensureRoom

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; shrinkCode
;
; Inputs:
;	ES:DI -> next unused byte
;
; Outputs:
;	If successful, code block in ES is shrunk
;
; Modifies:
;	AX
;
DEFPROC	shrinkCode
	push	bx
	push	cx
	mov	es:[BLK_FREE],di
	mov	bx,di
	add	bx,15
	mov	cl,4
	shr	bx,cl
	mov	ah,DOS_MEM_REALLOC
	int	21h
	jc	sc9
	mov	es:[BLK_SIZE],di
sc9:	pop	cx
	pop	bx
	ret
ENDPROC	shrinkCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeCode
;
; Inputs:
;	ES -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	freeCode
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].CBLKDEF
	jmp	freeBlock
ENDPROC	freeCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeAllCode
;
; Frees all code blocks and resets the CBLK chain.
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
DEFPROC	freeAllCode
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].CBLKDEF
	jmp	freeAllBlocks
ENDPROC	freeAllCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocFunc
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
DEFPROC	allocFunc
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].FBLKDEF
	jmp	allocCodeBlock
ENDPROC	allocFunc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeFunc
;
; Inputs:
;	ES -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	freeFunc
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].FBLKDEF
	jmp	freeBlock
ENDPROC	freeFunc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocText
;
; Inputs:
;	None
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte (check
;	BLK_SIZE for the size of the block, which may be less than TBLKLEN)
;
; Modifies:
;	AX, SI, DI, ES
;
DEFPROC	allocText
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].TBLKDEF
	jmp	allocBlock
ENDPROC	allocText

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeAllText
;
; Frees all text blocks and resets the TBLK chain.
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
DEFPROC	freeAllText
	call	freeCache		; the program's code goes with its text
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].TBLKDEF
	jmp	freeAllBlocks
ENDPROC	freeAllText

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeCache
;
; Frees the code (if any) that genCode cached for the loaded program, which
; must be done whenever the program's text or variables are freed, since the
; code depends on both.  The next READ position (see readData) also depends
; on the text, so it's reset, too.
;
; Modifies:
;	CX, SI
;
DEFPROC	freeCache
	mov	si,ds:[PSP_HEAP]
	mov	word ptr [si].DATA_STATE[2],0
	lea	si,[si].CODE_CACHE
	jmp	freeAllBlocks
ENDPROC	freeCache

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; keepCode
;
; Called by genCode when the generated code has finished running: if the code
; was generated for the loaded program (as opposed to a command line) and it
; ran without error, we keep it (in CODE_CACHE) so that RUN can simply run it
; again (see runCache); otherwise, it's freed.
;
; Inputs:
;	Carry set if the code failed (eg, a syntax error)
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	keepCode
	jc	kc8
	mov	si,ds:[PSP_HEAP]
	mov	ax,ss
	cmp	[si].LINE_PTR.SEG,ax	; did we run the loaded program?
	je	kc8			; no
	call	freeCache		; yes, so keep its code
	mov	si,ds:[PSP_HEAP]
	sub	ax,ax
	xchg	ax,[si].CBLKDEF.BDEF_NEXT
	mov	[si].CODE_CACHE,ax
	ret
kc8:	jmp	freeAllCode
ENDPROC	keepCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resetVars
;
; Used by RUN to give a program a fresh set of variables: normally, we free
; them all, but if the program's code was kept (see keepCode), its variables
; must remain where they are, so we just clear them instead (like CLEAR).
;
; Inputs:
;	BX -> CMDHEAP
;
; Modifies:
;	Any but AX and BX
;
DEFPROC	resetVars
	cmp	[bx].CODE_CACHE,0
	jne	rsv1
	jmp	freeAllVars
rsv1:	push	ax
	push	bx
	mov	[bx].OPT_BASE,0
	push	cs
	call	clearVars		; (a FAR function)
	pop	bx
	pop	ax
	ret
ENDPROC	resetVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; runCode
;
; Used by RUN: if the loaded program's code was kept (see keepCode), we run it
; again, the same way genCode runs it (see the ON ERROR setup there);
; otherwise, genCode generates (and runs) it.
;
; Inputs:
;	AL = GEN flags
;	BX -> CMDHEAP
;	SI = 0
;
; Outputs:
;	Carry clear if successful
;
; Modifies:
;	Any
;
DEFPROC	runCode
	cmp	[bx].CODE_CACHE,0	; is the program's code still around?
	jne	rcd1			; yes
	jmp	genCode
rcd1:	mov	[bx].GEN_FLAGS,al
	mov	byte ptr [bx].GFX_DATA+6,0	; see gfxInit
	mov	ax,[bx].TBLKDEF.BLK_NEXT
	mov	[bx].LINE_PTR.SEG,ax	; (see keepCode)
	sub	ax,ax
	mov	[bx].DATA_STATE[2],ax	; start READ at the first DATA item
	xchg	ax,[bx].CODE_CACHE
	mov	[bx].CBLKDEF.BDEF_NEXT,ax; the code is running again
	push	ax
	mov	ax,size CBLK
	push	ax
	mov	di,sp			; SS:DI -> the code
	push	[bx].ERR_SP
	push	[bx].ERR_NUM
	push	[bx].ERR_ADDR.OFF
	push	[bx].ERR_ADDR.SEG
	sub	ax,ax
	mov	[bx].ERR_NUM,ax
	mov	[bx].ERR_ADDR.SEG,ax
	mov	cx,[bx].VBLKDEF.BDEF_NEXT
	push	bp
	push	ds
	mov	ax,sp
	sub	ax,4			; (the CALL below pushes 4 bytes)
	mov	[bx].ERR_SP,ax
	mov	ds,cx
	ASSUME	DS:NOTHING
	call	dword ptr ss:[di]	; execute the code
	pop	ds
	ASSUME	DS:DATA
	pop	bp
	mov	si,ds:[PSP_HEAP]
	pop	[si].ERR_ADDR.SEG
	pop	[si].ERR_ADDR.OFF
	pop	[si].ERR_NUM
	pop	[si].ERR_SP
	add	sp,4
	clc
	call	keepCode		; keep the code again
	call	compactStrs		; free any leftover temp strings
	clc
	ret
ENDPROC	runCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocVars
;
; Allocates a var block if one is not already allocated.
;
; Inputs:
;	BX -> CMDHEAP
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte, CX = length
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	allocVars
	lea	si,[bx].VBLKDEF
	cmp	[si].BDEF_NEXT,0
	jne	al9
	jmp	allocBlock
al9:	ret
ENDPROC	allocVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocTempVars
;
; Allocates a temp var block and makes it active, returning previous chain.
;
; Inputs:
;	None
;
; Outputs:
;	If carry clear, DX = segment of previous block chain
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	allocTempVars
	push	di
	push	es
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].VBLKDEF
	sub	dx,dx
	xchg	[si].BDEF_NEXT,dx
	call	allocBlock
	pop	es
	pop	di
	ret
ENDPROC	allocTempVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; updateTempVars
;
; Adds the specified block(s) to the var block chain.
;
; Inputs:
;	DX = segment of block(s) to restore
;
; Outputs:
;	None
;
; Modifies:
;	SI
;
DEFPROC	updateTempVars
	push	es
	mov	si,ds:[PSP_HEAP]	; we know there's only one block
	mov	es,[si].VBLKDEF.BDEF_NEXT
	mov	es:[BLK_NEXT],dx	; so we can simply update its BLK_NEXT
	pop	es
	ret
ENDPROC	updateTempVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeTempVars
;
; Frees the first (temp) var block.
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
DEFPROC	freeTempVars
	push	es
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].VBLKDEF
	mov	es,[si].BDEF_NEXT
	call	freeBlock
	pop	es
	ret
ENDPROC	freeTempVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeAllVars
;
; Free all SBLKs, FBLKs, VBLKs, and ABLKs, and reset OPTION BASE.
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
DEFPROC	freeAllVars
	call	freeCache		; (the code depends on the vars)
	call	freeStrSpace
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].FBLKDEF
	call	freeAllBlocks
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].VBLKDEF
	call	freeAllBlocks
	mov	si,ds:[PSP_HEAP]
	mov	[si].OPT_BASE,0
	lea	si,[si].ABLKDEF
	jmp	freeAllBlocks
ENDPROC	freeAllVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeIdleVars
;
; Frees all var blocks (and string space) if there are no variables, user
; functions, or arrays, so that the memory is available to external programs
; (see cmdFile); the blocks are allocated again when they're needed.
;
; Inputs:
;	DS = heap segment
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	freeIdleVars
	call	freeCache		; free any cached code, too
	mov	si,ds:[PSP_HEAP]
	mov	ax,[si].FBLKDEF.BDEF_NEXT
	or	ax,[si].ABLKDEF.BDEF_NEXT
	jnz	fiv9			; there are functions or arrays
	mov	cx,[si].VBLKDEF.BDEF_NEXT
	jcxz	fiv8			; there are no var blocks
	push	es
	mov	es,cx
	mov	cx,es:[BLK_NEXT]	; more than one var block?
	jcxz	fiv1			; no
	pop	es
	ret
fiv1:	cmp	byte ptr es:[size VBLK],VAR_NONE
	pop	es
	jne	fiv9			; there are variables
fiv8:	jmp	freeAllVars
fiv9:	ret
ENDPROC	freeIdleVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocStrSpace
;
; Allocates an SBLK and adds it to the SBLK chain.
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
	lea	si,[si].SBLKDEF
	jmp	allocBlock
ENDPROC	allocStrSpace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeStrSpace
;
; Frees all SBLKs and resets the SBLK chain.
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
	lea	si,[si].SBLKDEF
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
; This function must also reserve the total space required for the var data.
; That's 1 word for VAR_PARM, 2 words for VAR_LONG and VAR_STR, 4 words for
; VAR_DOUBLE, and (1 + parm count + 2) words for VAR_FUNC.
;
; Inputs:
;	AH = var type (VAR_*)
;	AL = parm count (if AH = VAR_FUNC)
;	CX = length of name
;	DS:SI -> variable name
;
; Outputs:
;	If carry clear, AH = var type, DX:SI -> var data
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	addVar
	push	bx
	push	di
	push	es
	ASSERT	C,<cmp cx,256>		; validate size (and that CH is zero)
	mov	bx,ax			; save var type
	mov	di,si			; save var name
	call	findVar
	jnc	av1x

	mov	al,bh			; AL = var type
	mov	si,di			; restore var name to SI
;
; New vars are added to the last var block (which is NOT the first block
; while a DEF with parameters is being generated, since the first block is
; then a temp block for the parameters), and if there's no room, another
; var block is added to the chain.
;
	mov	di,ds:[PSP_HEAP]
	mov	es,[di].VBLKDEF.BDEF_NEXT
av0:	ASSERT	STRUCT,es:[0],VBLK
	mov	di,es:[BLK_NEXT]
	test	di,di			; is this the last block?
	jz	av0a			; yes
	mov	es,di
	jmp	av0
av0a:	mov	di,es:[BLK_FREE]

	DPRINTF	'b',<"adding variable %.*ls\r\n">,cx,si,ds

av0b:	sub	dx,dx
	cmp	cx,VAR_NAMELEN
	jbe	av1
	mov	cx,VAR_NAMELEN
av1:	push	di
	add	di,cx
	inc	dx
	inc	dx
	cmp	al,VAR_LONG
	jb	av3
	inc	dx
	inc	dx
	cmp	al,VAR_DOUBLE
	jb	av3
	ja	av2
	add	dx,dx
	jmp	short av3
av1x:	jmp	short av9

av2:	cmp	al,VAR_ARRAY		; arrays are a 4-byte pointer
	je	av3
	ASSERT	Z,<cmp al,VAR_FUNC>
	mov	dl,bl			; DX = parm count
	add	dx,dx			; DX = DX * 2
	add	dx,6			; DX += return type + code ptr
av3:	add	di,dx
	inc	di			; one for the length byte
	cmp	es:[BLK_SIZE],di	; room for the var and a terminator?
	pop	di
	ja	av3a			; yes
	cmp	di,size VBLK		; no, but is this block empty?
	stc
	je	av9			; yes, so the var is too large
	push	ax
	push	si
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].VBLKDEF
	call	allocBlock		; ES:DI -> new var block
	pop	si
	pop	ax
	jc	av9
	jmp	av0b
av3a:
;
; Build the new variable at ES:DI, with combined length and type in the
; first byte, the variable name in the following bytes, and zero-initialized
; data in the remaining bytes.
;
	or	al,cl
	stosb
av4:	lodsb				; rep movsb would be nice here
	cmp	al,'a'			; but we upper-case the var name now
	jb	av5
	sub	al,20h
av5:	stosb
	loop	av4
	mov	al,cl			; AL = 0
	mov	cx,dx			; CX = size of var data
	mov	dx,di			; DX = offset of var data
	rep	stosb
	mov	es:[BLK_FREE],di
	cmp	es:[BLK_SIZE],di
	ASSERT	AE
	je	av8
	stosb				; ensure there's always a zero after

av8:	mov	si,dx
	mov	dx,es			; DX:SI -> var data
	xchg	ax,bx			; restore AH, AL

av9:	pop	es
	pop	di
	pop	bx
	ret
ENDPROC	addVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findVar
;
; As in MSBASIC, a variable's type is part of its identity, so "A" (eg,
; VAR_DOUBLE after DEFDBL) and "A%" (VAR_LONG) are different variables.
; However, a VAR_FUNC or predefined var matches any type, and a VAR_PARM
; matches if its parameter type matches.
;
; Inputs:
;	AH = var type (VAR_*)
;	CX = length of name
;	DS:SI -> variable name
;
; Outputs:
;	If carry clear, AH = var type, DX:SI -> var data
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	findVar
	push	es
	push	di
	push	bx
	mov	bl,ah			; BL = requested var type
	mov	bh,0			; BH = 0 while checking PREDEF_VARS

	push	cs
	pop	es
	mov	di,offset PREDEF_VARS
	jmp	short fv1

fv0:	inc	bh
	mov	di,ds:[PSP_HEAP]
	mov	es,[di].VBLKDEF.BDEF_NEXT
	ASSERT	STRUCT,es:[0],VBLK
	mov	di,size VBLK		; ES:DI -> first var in block

fv1:	mov	al,es:[di]
	inc	di
	cmp	al,VAR_DEAD		; end of variables in the block?
	je	fv1			; no, dead byte
	ja	fv2			; no, existing variable
	mov	ax,cs			; TODO: integrate PREDEF_VARS and
	mov	dx,es			; and the rest of the var blocks better
	cmp	ax,dx
	je	fv0
	mov	ax,es:[BLK_NEXT]	; is there another var block?
	test	ax,ax
	stc
	jz	fv9			; no
	mov	es,ax
	mov	di,size VBLK		; ES:DI -> first var in next block
	jmp	fv1

fv2:	mov	ah,al
	and	ah,VAR_TYPE
	and	al,VAR_NAMELEN
	cmp	al,cl			; do the name lengths match?
	jne	fv6			; no

	push	ax
	push	cx
	push	si
	push	di
fv3:	lodsb				; TODO: rep cmpsb would be nice here
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
	jne	fv6			; no match
	test	bh,bh			; predefined var?
	jnz	fv7			; no
;
; Predefined vars match any type, except that a predefined function that
; returns a double (eg, RND) doesn't match a name with an explicit '%' suffix,
; so that a following function with the same name (eg, RND%) can match it.
;
	push	bx
	mov	bx,dx
	cmp	byte ptr es:[bx],VAR_DOUBLE
	jne	fv5a
	mov	bl,cl
	mov	bh,0
	cmp	byte ptr [si+bx],'%'
fv5a:	pop	bx
	jne	fv8
	jmp	short fv6

fv7:	cmp	ah,bl			; do the types match?
	je	fv8			; yes
	cmp	ah,VAR_FUNC		; function?
	je	fv8			; yes
	cmp	ah,VAR_PARM		; parameter?
	jne	fv6			; no
	xchg	dx,si
	cmp	es:[si],bl		; does the parameter type match?
	xchg	dx,si
	je	fv8			; yes

fv6:	mov	dl,al
	mov	dh,0
	add	di,dx			; DI -> past var name
	call	getVarLen
	add	di,ax
	jmp	fv1			; keep looking

fv8:	mov	si,dx
	mov	dx,es			; DX:SI -> var data
	clc

fv9:	pop	bx
	pop	di
	pop	es
	ret
ENDPROC	findVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getVar
;
; Load AX with the var data at DX:SI and advance SI.
;
; Inputs:
;	DX:SI -> var data
;
; Outputs:
;	AX = data
;
; Modifies:
;	SI
;
DEFPROC	getVar
	push	ds
	mov	ds,dx
	lodsw
	pop	ds
	ret
ENDPROC	getVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getVarLen
;
; Inputs:
;	AH = var type
;	ES:DI -> var data
;
; Outputs:
;	AX = length of var data
;
; Modifies:
;	AX
;
DEFPROC	getVarLen
	push	cx
	sub	cx,cx
	cmp	ah,VAR_PARM
	jb	gvl9
	mov	cx,2
	je	gvl9			; VAR_PARM is always 2 bytes
	cmp	ah,VAR_FUNC
	je	gvl1
	add	cx,2			; other values are 4 bytes
	cmp	ah,VAR_DOUBLE		; (including VAR_ARRAY)
	jne	gvl9
	add	cx,4			; VAR_DOUBLE is 8 bytes
	jmp	short gvl9
gvl1:	add	cx,4			; VAR_FUNC also has 4-byte addr
	mov	al,es:[di+1]		; AL = VAR_FUNC parm count
	cbw
	add	ax,ax
	add	cx,ax
gvl9:	xchg	ax,cx			; AX = length of var data
	pop	cx
	ret
ENDPROC	getVarLen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; removeVar
;
; Inputs:
;	AH = var type (VAR_*)
;	CX = length of name
;	DS:SI -> variable name
;
; Outputs:
;	If carry clear, variable removed (or does not exist)
;	If carry set, variable predefined (cannot be removed)
;
; Modifies:
;	AX, DX
;
DEFPROC	removeVar
	DPRINTF	'b',<"removing variable %.*ls\r\n">,cx,si,ds
	push	si
	call	findVar			; does var exist?
	cmc
	jnc	rv9			; exit if not
	push	di			; AH = var type, DX:SI -> var data
	mov	di,cs
	cmp	di,dx			; predefined variable?
	stc
	je	rv8			; yes

	push	es
	push	cx
	mov	es,dx
	mov	di,si			; ES:DI -> var data
	mov	dh,ah			; DH = var type
	call	getVarLen		; AX = length of var data at ES:DI
	inc	cx			; CX = total length of name
	sub	di,cx			; ES:DI -> name name
	add	cx,ax			; CX = total length of name + data

	cmp	dh,VAR_FUNC
	jne	rv1
	push	cx
	push	es
	push	di
	add	di,cx
	mov	es,es:[di-2]
	call	freeFunc		; ES = function segment
	ASSERT	NC
	pop	di
	pop	es
	pop	cx

rv1:	mov	al,VAR_DEAD
	rep	stosb
	pop	cx
	pop	es

rv8:	pop	di
rv9:	pop	si
	ret
ENDPROC	removeVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setVar
;
; Store AX in the var data at DX:SI and advance SI.
;
; Inputs:
;	AX = data
;	DX:SI -> var data
;
; Outputs:
;	None
;
; Modifies:
;	SI
;
DEFPROC	setVar
	push	ds
	mov	ds,dx
	mov	[si],ax
	add	si,2
	pop	ds
	ret
ENDPROC	setVar

CODE	ENDS

	end
