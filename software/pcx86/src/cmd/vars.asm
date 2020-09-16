;
; BASIC-DOS Variable Management
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:CODE, ES:NOTHING, SS:CODE

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
; is limited to MAX_VARNAME.
;
; Note that, except for numbers (integers and floating point values), the
; variable data is generally a far pointer to the actual data; for example, a
; string variable is just a far pointer to a location inside a string pool.
;
; Inputs:
;	AL = VAR_*
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
	call	findVar
	jnc	av10
	push	di
	push	es
	mov	di,ds:[PSP_HEAP]
	mov	es,[di].VARS_BLK.BLK_NEXT
	ASSERT	STRUCT,es:[0],VBLK
	mov	di,es:[VBLK_FREE]
	push	ax

	cmp	cx,MAX_VARNAME
	jbe	av0
	mov	cx,MAX_VARNAME
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
	and	al,MAX_VARNAME
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
; setVarLong
;
; Input stack:
;	pointer to var data
;	32-bit value
;
; Output stack:
;	None
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	setVarLong,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	pop	ax
	pop	bx			; BX:AX = 32-bit value
	pop	di
	pop	es			; ES:DI -> var data
	stosw
	xchg	ax,bx
	stosw
	push	dx			; ie, "JMP DX:CX"
	push	cx
	ret
ENDPROC	setVarLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; appendStr
;
; This is the first function that must consider how the string pool will work.
;
; The pool will consist of zero or more blocks, each block will contain zero
; or more strings, and each string will consist of:
;
;	length byte (1-255)
;	characters (up to 255 of them)
;
; We can reserve length zero by saying that all empty strings will have a
; null pointer.  This means that length of zero can be used to indicate unused
; pool space.
;
; This simplistic model makes it easy to append to a string if it's followed
; by enough unused bytes.
;
; Input stack:
;	pointer to target string data
;	pointer to source string data
;
; Output stack:
;	pointer to target string data
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	appendStr,FAR
	ARGVAR	pTarget,dword
	ARGVAR	pSource,dword
	ENTER
	push	ds
	lds	si,[pSource]
	les	di,[pTarget]
;
; If the source string pointer is null (ie, an empty string), that's
; the easiest case of all; there's nothing to do.  We'll assume that checking
; the offset is sufficient, since all our blocks begin with headers, so a
; non-zero offset should be impossible.
;
	test	si,si
	jz	as0
;
; If the target string pointer is null, it can simply "inherit" the source.
;
	test	di,di
	jnz	as1
	mov	[pTarget].OFF,si
	mov	[pTarget].SEG,ds
as0:	jmp	as9
;
; Get length of target string at ES:DI into CL, and verify that the new
; string will still be within limits.
;
as1:	mov	dl,es:[di]
	mov	cl,dl
	mov	al,[si]
	add	dl,al
	jc	as8			; resulting string would be too big
;
; If the target string does NOT reside in a string pool block, then it must
; always be copied.
;
	cmp	es:[SBLK_SIG],SIG_SBLK
	jne	as2			; target must be copied
;
; Check the target string to see if there's any (and enough) space after it.
;
	mov	ch,0
	mov	bx,di			; BX -> target also
	add	di,cx
	inc	di			; DI -> 1st byte after string
	mov	cx,es:[SBLK_SIZE]
	sub	cx,di			; CX = max possible chars available
	mov	ah,0			; AX = length of source string
	cmp	cx,ax			; less than we need?
	jb	as2			; yes, target must be copied instead
	mov	cx,ax
	push	ax
	push	di
	mov	al,0
	rep	scasb			; zeros all the way?
	pop	di
	pop	ax
	jne	as2			; no, target must be copied instead
;
; Finally, an answer: we can simply copy the source to the end of the target.
;
	inc	si
	mov	cx,ax			; CX = length of source string
	rep	movsb			; copied
	add	es:[bx],al		; update length of target string
	ASSERT	NC
	jmp	short as9		; all done
;
; We must copy the target + source to a new location.  Combined length is DL.
; Use findStrSpace to find a sufficiently large space.
;
as2:	push	si			; push source
	push	ds
	push	di			; push target
	push	es
	call	findStrSpace		; DL = # bytes required
	pop	ds
	pop	si			; recover target in DS:SI
	jc	as4			; error
	mov	al,dl
	mov	bx,di
	mov	dx,es			; DX:BX = new string address
	stosb				; start with the new combined length
	mov	ah,0
	xchg	al,[si]
	mov	cx,ax
as3:	mov	al,0
	xchg	al,[si]
	inc	si
	stosb
	loop	as3
as4:	pop	ds			; recover source in DS:SI
	pop	si
	jc	as8
	lodsb
	mov	cl,al
	rep	movsb			; copy all the source bytes, too

as8:	jc	as9
	mov	[pTarget].OFF,bx
	mov	[pTarget].SEG,dx

as9:	pop	ds
	LEAVE
	ret	4			; clean off the source string pointer
ENDPROC	appendStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeStr
;
; Zero all the bytes referenced by the target variable.
;
; Inputs:
;	ES:DI -> string to free
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DI
;
DEFPROC	freeStr
	mov	cl,es:[di]		; CL = string length
	mov	ch,0			; CX = length
	inc	cx			; CX = length + length byte
	mov	al,0
	rep	stosb			; zero away
	ret
ENDPROC	freeStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setStr
;
; Input stack:
;	pointer to target string variable
;	pointer to source string data
;
; Output stack:
;	None
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	setStr,FAR
	ARGVAR	pTargetVar,dword
	ARGVAR	pSource,dword
	ENTER
	les	di,[pTargetVar]
	DBGBRK
;
; The general case involves storing the source address in the target variable
; after first zeroing all the bytes referenced by the target variable.
;
; However, there are a number of simple yet critical cases to check for first.
; For example, is the target is null?  If so, no further checks required.
;
	les	di,es:[di]
	test	di,di
	jz	ss8
;
; The target has a valid pointer, but before we zero its bytes, see if source
; and target are identical; if so, nothing to do at all.
;
	cmp	di,si
	jne	ss1
	mov	ax,es
	cmp	ax,[pSource].SEG
	je	ss9

ss1:	call	freeStr
;
; Transfer the pointer from DS:SI to the target variable now.
;
ss8:	push	ds
	les	di,[pTargetVar]
	lds	si,[pSource]
	mov	es:[di].OFF,si
	mov	es:[di].SEG,ds
	pop	ds

ss9:	LEAVE
	ret	8			; clean the stack
ENDPROC	setStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findStrSpace
;
; Inputs:
;	DX = # bytes required (not counting length byte)
;
; Outputs:
;	If successful, carry clear, ES:DI -> available space
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	findStrSpace
	push	si
	push	ds
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].STRS_BLK
	mov	ah,0

fss1:	mov	cx,[si]
	jcxz	fss6			; end of chain

	mov	es,cx
	mov	di,size SBLK_HDR	; ES:DI -> next location to check
	mov	bx,es:[SBLK_SIZE]	; BX = limit

fss2:	cmp	di,bx
	jae	fss4
fss2a:	mov	al,es:[di]
	test	al,al
	jz	fss3
	add	di,ax
	inc	di
	jmp	fss2

fss3:	add	di,dx
	cmp	di,bx
	ja	fss4			; not enough room, even if free
	sub	di,dx			; rewind DI
	mov	cx,dx			; CX = # bytes required
	rep	scasb
	je	fss5
	dec	di			; rewind DI to the non-matching byte
	jmp	fss2a			; and continue scanning

fss4:	push	es
	pop	ds
	sub	si,si			; DS:SI -> SBLK_NEXT
	jmp	fss1

fss5:	sub	di,dx			; ES:DI -> available space
	jmp	short fss9

fss6:	call	allocStrSpace		; ES:DI -> new space (if carry clear)

fss9:	pop	ds
	pop	si
	ret
ENDPROC	findStrSpace

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
