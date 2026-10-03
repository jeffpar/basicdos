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

CODE    SEGMENT

	EXTNEAR	<memError>
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
; Inputs:
;	SI = offset of block chain head
;	CX = size of block, in bytes (if calling allocBlockSize)
;
; Outputs:
;	If successful, carry clear, ES:DI -> first available byte in new block
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	allocBlock
	mov	cx,[si].BDEF_SIZE
	DEFLBL	allocBlockSize,near
	push	bx
	push	cx
	mov	bx,cx
	add	bx,15
	xchg	cx,ax
	mov	cl,4
	shr	bx,cl
	xchg	cx,ax
	mov	ah,DOS_MEM_ALLOC
	mov	al,[si].BDEF_SIG
	int	21h
	jc	ab8

	mov	es,ax
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
	jnc	ab2
	stosb
;
; Block is initialized, append to the header chain now.
;
ab2:	push	ds
	lea	di,[si].BDEF_NEXT	; DS:DI -> first segment in chain
ab3:	mov	cx,[di]			; at the end yet?
	jcxz	ab4			; yes
	mov	ds,cx
	sub	di,di
	jmp	ab3
ab4:	mov	[di],es			; chain updated
	mov	di,es:[BLK_FREE]	; ES:DI -> first available byte
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
; CBLKDEF and TBLKDEF).
;
; Inputs:
;	AL = mask of chains to save
;
; Outputs:
;	SP -> CHAINS frame (on return)
;
; Modifies:
;	AX, DI
;
CHAINS		struc
CH_MASK		dw	?		; bit n set if head n was saved
CH_PREV		dw	?		; previous CHAINS frame, if any
CH_HEADS	dw	5 dup (?)	; saved CBLKDEF through TBLKDEF heads
CHAINS		ends

DEFPROC	saveChains
	pop	di			; DI = return address
	sub	sp,size CHAINS
	push	di
	push	cx
	push	si
	mov	di,sp
	add	di,6			; DI -> CHAINS frame
	mov	si,ds:[PSP_HEAP]
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
; Inputs:
;	AL = 0 to restore the saved chains, non-zero to free them
;	DI -> CHAINS frame
;
; Outputs:
;	DI -> end of CHAINS frame
;
; Modifies:
;	AH, CX, SI, DI
;
DEFPROC	restoreChains
	mov	si,ds:[PSP_HEAP]
	mov	cx,[di].CH_PREV
	mov	[si].CMD_CHAINS,cx
	mov	ah,byte ptr [di].CH_MASK
	add	di,CH_HEADS
	mov	cx,5
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
;	If successful, carry clear, ES:DI -> first available byte, CX = length
;
; Modifies:
;	AX, CX, SI, DI, ES
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
	mov	es:[CBLK_REFS],cx
ac9:	ret
ENDPROC	allocCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; growCode
;
; Makes sure there are at least CODE_SLACK bytes between the end of the code
; and the LBLREF table in a code (or function) block, by doubling the size of
; the block if necessary (up to 64K).  We first try to grow the block in place,
; and if that fails, we allocate a new block, copy the code to it (generated
; code uses only offsets within its block, so it can be copied to any segment),
; move the LBLREF table to the top of the block, replace the old block in its
; chain, and free the old block.
;
; Since the block may move, this must be called only when ES is the only
; reference to the block's segment (eg, before generating code for each line),
; and the caller must update any copy of ES afterward.
;
; Inputs:
;	ES:DI -> next unused byte in code (or function) block
;
; Outputs:
;	Carry clear if successful (ES may be different), set if out of memory
;
; Modifies:
;	AX, CX
;
CODE_SLACK	equ	2048

DEFPROC	growCode
	mov	ax,es:[CBLK_REFS]	; (FBLK_REFS is the same)
	sub	ax,di
	cmp	ax,CODE_SLACK		; enough room?
	jb	gr0			; no
	ret				; yes (carry clear)
gr0:	push	bx
	push	dx
	push	si
	push	ds
	mov	ax,es:[BLK_SIZE]
	mov	dx,0FFF0h		; DX = max block size
	cmp	ax,8000h
	jae	gr1
	add	ax,ax
	xchg	dx,ax			; DX = new block size (twice the size)
gr1:	cmp	dx,es:[BLK_SIZE]	; can the block grow at all?
	jbe	gr7			; no
	mov	bx,dx
	add	bx,15
	mov	cl,4
	shr	bx,cl			; BX = # paragraphs
	mov	ah,DOS_MEM_REALLOC
	int	21h			; grow block ES in place
	jc	gr2			; unable
	push	es
	pop	ds			; DS = ES = block
	call	moveRefs
	jmp	short gr8

gr2:	mov	al,es:[BLK_SIG]		; AL = block type
	mov	ah,DOS_MEM_ALLOC
	int	21h			; AX = new block
	jc	gr7
	push	es
	pop	ds			; DS = old block
	mov	es,ax			; ES = new block
	push	di
	mov	cx,di
	sub	si,si
	sub	di,di
	rep	movsb			; copy the header and all the code
	pop	di
	call	moveRefs		; move the LBLREF table
	mov	ax,ds			; AX = old block
	push	ss
	pop	ds			; DS = heap
	mov	si,ds:[PSP_HEAP]
	lea	cx,[si].FBLKDEF
	lea	si,[si].CBLKDEF
	cmp	es:[BLK_SIG],SIG_CBLK	; which chain is the block in?
	je	gr3
	mov	si,cx			; DS:SI -> chain head
gr3:	cmp	[si],ax			; is this the link to the old block?
	je	gr4			; yes
	mov	ds,[si]
	sub	si,si			; DS:SI -> next link
	jmp	gr3
gr4:	mov	[si],es			; link to the new block instead
	push	es
	mov	es,ax
	mov	ah,DOS_MEM_FREE
	int	21h			; free the old block
	pop	es
	jmp	short gr8

gr7:	stc
	jmp	short gr8a
gr8:	clc
gr8a:	pop	ds
	pop	si
	pop	dx
	pop	bx
	ret
;
; moveRefs moves the LBLREF table from the top of block DS to the top (DX) of
; block ES, and updates CBLK_REFS and BLK_SIZE.  The table may overlap itself
; (if DS is ES), so we copy it backward.
;
moveRefs:
	push	di
	mov	si,ds:[BLK_SIZE]
	mov	cx,si
	sub	cx,ds:[CBLK_REFS]	; CX = size of the LBLREF table
	mov	di,dx
	sub	di,cx
	mov	es:[CBLK_REFS],di
	mov	es:[BLK_SIZE],dx
	mov	di,dx
	dec	si
	dec	di
	std
	rep	movsb
	cld
	pop	di
	ret
ENDPROC	growCode

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
	lea	si,[si].TBLKDEF
	jmp	allocBlockSize
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
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].TBLKDEF
	jmp	freeAllBlocks
ENDPROC	freeAllText

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
; Free all FBLKs and VBLKs.
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
	call	freeStrSpace
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].FBLKDEF
	call	freeAllBlocks
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].VBLKDEF
	call	freeAllBlocks
	ret
ENDPROC	freeAllVars

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
	mov	di,ds:[PSP_HEAP]
	mov	es,[di].VBLKDEF.BDEF_NEXT
	ASSERT	STRUCT,es:[0],VBLK
	mov	di,es:[BLK_FREE]

	DPRINTF	'b',<"adding variable %.*ls\r\n">,cx,si,ds

	sub	dx,dx
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

av2:	ASSERT	Z,<cmp al,VAR_FUNC>
	mov	dl,bl			; DX = parm count
	add	dx,dx			; DX = DX * 2
	add	dx,6			; DX += return type + code ptr
av3:	add	di,dx
	inc	di			; one for the length byte
	cmp	es:[BLK_SIZE],di	; enough room?
	pop	di
	jb	av9			; no (carry set)
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
	stc				; TODO: if AX (CS) always less than
	jmp	short fv9		; DX (ES), carry will already be set

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
	cmp	ah,bl			; do the types match?
	je	fv8			; yes
	test	bh,bh			; predefined var?
	jz	fv8			; yes
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
	jae	gvl1
	add	cx,2			; other values are at least 4 bytes
	cmp	ah,VAR_DOUBLE
	jb	gvl9
	add	cx,4			; VAR_DOUBLE is 8 bytes
	jmp	short gvl9
gvl1:	add	cx,4			; VAR_FUNC also has 4-byte addr
	mov	al,es:[di+1]		; AL = VAR_FUNC or VAR_ARRAY length
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
