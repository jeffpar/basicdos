;
; BASIC-DOS Memory Management Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	bios.inc

CODE    SEGMENT

	EXTBYTE	<PREDEF_VARS,PREDEF_ZERO>

	IFDEF	DEBUG
	EXTSTR	<SYS_MEM,DOS_MEM,FREE_MEM>
	ENDIF	; DEBUG

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
; That's 2 bytes for VAR_PARM, 4 bytes for VAR_LONG and VAR_STR, and
; 2 + parm count * 2 + 4 for VAR_FUNC.
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
; Inputs:
;	CX = length of name
;	DS:SI -> variable name
;
; Outputs:
;	If carry clear, AH = var type, DX:SI -> var data
;	If carry set, AH = VAR_LONG, DX:SI -> zero constant
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	findVar
	push	es
	push	di

	push	cs
	pop	es
	mov	di,offset PREDEF_VARS
	jmp	short fv1

fv0:	mov	di,ds:[PSP_HEAP]
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
	stc
	mov	dx,cs
	mov	si,offset PREDEF_ZERO	; DX:SI -> zero constant
	lods	byte ptr cs:[si]
	mov	ah,al
	jmp	short fv9

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
	je	fv8			; match!

fv6:	mov	dl,al
	mov	dh,0
	add	di,dx			; DI -> past var name
	call	getVarLen
	add	di,ax
	jmp	fv1			; keep looking

fv8:	mov	si,dx
	mov	dx,es			; DX:SI -> var data

fv9:	pop	di
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMem
;
; Prints memory usage.  Use /D to display segment-level detail.
;
; Inputs:
;	BX -> CMDHEAP (not used)
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
	ENTER
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
drv9:	mov	ah,DOS_MSC_GETVARS
	int	21h
	mov	di,es:[bx]	; ES:BX -> mcb_limit
	mov	[memLimit],di

	IFDEF	DEBUG
	mov	ax,es:[bx-2]	; ES:BX-2 -> mcb_head
	mov	bx,es		; BX = DOS data segment
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

	DOSUTIL	QRYMEM
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
	TESTSW	<'D'>		; detail requested (/D)?
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
