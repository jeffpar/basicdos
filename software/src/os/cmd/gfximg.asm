;
; BASIC-DOS Graphics GET and PUT
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for GET and PUT (see gengfx.asm), which copy rectangles
; of CGA video memory to and from integer arrays (see arr.inc); the rest of
; the graphics runtime functions are in gfx.asm.
;
	include	cmd.inc
	include	arr.inc

CODE    SEGMENT

	EXTNEAR	<strIllegal,gfxInit,getPoint,pixAddr,rowAddr>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

PUT_XOR		equ	0		; PUT actions (see genPut)
PUT_PSET	equ	1
PUT_PRESET	equ	2
PUT_OR		equ	3
PUT_AND		equ	4

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxGet
;
; Used by "GET (x1,y1)-(x2,y2),array", which stores the rectangle's pixels in
; an integer array, in MSBASIC's format: the width in bits, the height, and
; then the pixels, packed MSB first into rows of bytes.  Every element holds
; 16 bits (sign-extended), so that the array contains the same values that it
; would in MSBASIC.
;
; Each row is copied a byte at a time, shifting the screen bytes left to align
; the rectangle's left edge, and masking the unused bits of the last byte.
;
; Inputs:
;	2 pairs of coordinates, and the array variable, on the stack
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	gfxGet,FAR
	ARGVAR	gtX1,dword
	ARGVAR	gtY1,dword
	ARGVAR	gtX2,dword
	ARGVAR	gtY2,dword
	ARGVAR	gtArray,dword
	LOCVAR	gtShift,byte		; bit offset of the left edge
	LOCVAR	gtMask,byte		; mask for the last byte of each row
	LOCVAR	gtOdd,byte		; toggled for every byte stored
	LOCVAR	gtBytes,word		; bytes per row
	LOCVAR	gtRows,word		; rows remaining
	LOCVAR	gtByte0,word		; offset of the left edge within a row
	ENTER
	lea	si,[gtX1]
	call	getRect			; CX,DX = top left, SI,DI = bottom rt
	push	ds
	mov	ax,si
	sub	ax,cx
	inc	ax			; AX = width (in pixels)
	mov	si,di
	sub	si,dx
	inc	si			; SI = height
	mov	[gtRows],si
	push	cx
	lds	di,[gtArray]
	call	getImage		; DS:DI -> 1st element (checks size)
	pop	ax			; AX = left
	mov	si,[di]			; SI = width in bits
	add	di,8			; DS:DI -> 3rd element
	call	bitPos			; CL = shift, AX = byte offset
	mov	[gtShift],cl
	mov	[gtByte0],ax
	mov	ax,si
	call	rowBytes		; AX = bytes per row, CH = last mask
	mov	[gtBytes],ax
	mov	[gtMask],ch
	mov	[gtOdd],0
gt1:	call	rowAddr			; AX = offset of row DX
	add	ax,[gtByte0]
	mov	si,ax			; ES:SI -> 1st screen byte
	mov	cx,[gtBytes]
gt2:	mov	ah,es:[si]
	mov	al,es:[si+1]
	inc	si
	push	cx
	mov	cl,[gtShift]
	shl	ax,cl
	pop	cx
	mov	al,ah			; AL = next byte of the image
	cmp	cx,1			; last byte of the row?
	jne	gt3			; no
	and	al,[gtMask]
gt3:	call	gtPut
	loop	gt2
	inc	dx
	dec	[gtRows]
	jnz	gt1
	pop	ds
	LEAVE
	RETURN
ENDPROC	gfxGet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gtPut (gfxGet internal function, using its frame)
;
; Stores the byte in AL in the next element (low byte first).
;
; Modifies:
;	AX, DI
;
DEFPROC	gtPut
	not	[gtOdd]
	cmp	[gtOdd],0
	je	gtp1
	mov	ah,0
	mov	[di],ax
	mov	word ptr [di+2],0
	ret
gtp1:	mov	[di+1],al
	cbw
	mov	al,ah
	mov	[di+2],ax		; sign-extend the 16 bits
	add	di,4
	ret
ENDPROC	gtPut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxPut
;
; Used by "PUT (x,y),array[,action]", which draws an image stored by GET,
; combining it with the screen (see PUT_*).  As in MSBASIC, the entire image
; must be on the screen.
;
; The image is drawn a byte at a time: each screen byte of a row is the
; previous and current image bytes shifted right to align them with the
; screen, which is then combined with the screen (see putOps), masking the
; first and last bytes of the row.  Everything in the inner loop is kept in
; registers:
;
;	AL = next screen byte, BL = previous image byte, BH = toggle for
;	loading image bytes (2 per element), CL = shift, CH = # screen bytes
;	left in the row, DL = mask, DH = # image bytes left in the row,
;	DS:SI -> image, and ES:DI -> screen
;
; Inputs:
;	Coordinates, the array variable, and the action on the stack
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	gfxPut,FAR
	ARGVAR	puX,dword
	ARGVAR	puY,dword
	ARGVAR	puArray,dword
	ARGVAR	puAction,dword
	LOCVAR	puShift,byte		; bit offset of the left edge
	LOCVAR	puFirst,byte		; mask for the 1st screen byte of a row
	LOCVAR	puLast,byte		; mask for the last screen byte
	LOCVAR	puBytes,byte		; image bytes per row
	LOCVAR	puDest,byte		; screen bytes per row
	LOCVAR	puOp,word		; function for the action (see putOps)
	LOCVAR	puRows,word		; rows remaining
	LOCVAR	puRow,word		; offset of the current row
	LOCVAR	puCount,word		; # elements in the array
	ENTER
	call	gfxInit
	lea	si,[puX]
	call	getPoint		; DX:CX = top left
	push	ds
	push	cx
	push	dx
	lds	di,[puArray]
	call	getArray		; DS:DI -> 1st element, AX = # elements
	pop	dx
	pop	cx
	mov	[puCount],ax
	cmp	ax,2
	jb	puErr
	mov	si,[di]			; SI = width in bits
	mov	ax,[di+4]		; AX = height
	mov	[puRows],ax
	test	ax,ax
	jz	pu0
	test	si,si
	jz	pu0
;
; Verify that the image is entirely on the screen.
;
	push	cx
	push	dx
	add	dx,ax
	dec	dx			; DX = bottom
	mov	ax,si
	mov	cl,1
	sub	cl,bh
	shr	ax,cl			; AX = width in pixels
	pop	cx
	push	cx
	xchg	cx,dx			; CX = left, DX = bottom
	add	cx,ax
	dec	cx			; CX = right
	call	chkPixel		; is the bottom right on the screen?
	pop	dx
	pop	cx
	jc	puErr
	call	chkPixel		; and the top left?
	jnc	puOK
puErr:	jmp	strIllegal
pu0:	jmp	pu9

puOK:	mov	ax,cx
	call	bitPos			; CL = shift, AX = byte offset
	mov	[puShift],cl
	push	ax
	call	rowAddr			; AX = offset of the top row
	pop	cx
	add	ax,cx
	mov	[puRow],ax
	mov	ax,si
	call	rowBytes		; AX = image bytes per row
	cmp	ax,81
	jae	puErr
	mov	[puBytes],al
	mul	[puRows]
	inc	ax
	shr	ax,1
	add	ax,2			; AX = # elements required
	cmp	ax,[puCount]
	ja	puErr
	mov	al,[puShift]
	mov	ah,0
	add	ax,si			; AX = bits spanned on the screen
	call	rowBytes		; AX = screen bytes per row, CH = mask
	mov	[puDest],al
	mov	[puLast],ch
	mov	cl,[puShift]
	mov	al,0FFh
	shr	al,cl
	mov	[puFirst],al
	mov	bl,byte ptr [puAction]
	mov	bh,0
	add	bx,bx
	mov	ax,cs:PUT_OPS[bx]
	mov	[puOp],ax
	lea	si,[di+8]		; DS:SI -> 3rd element
	mov	bh,0			; BH = 0 (load the low byte next)
	mov	cl,[puShift]

pu1:	mov	di,[puRow]		; ES:DI -> 1st screen byte of the row
	mov	ch,[puDest]
	mov	dh,[puBytes]
	mov	dl,[puFirst]
	mov	bl,0			; BL = previous image byte
pu2:	mov	al,0
	dec	dh			; any image bytes left?
	js	pu4			; no (use zero)
	xor	bh,0FFh			; yes, so load the next one
	mov	al,[si]
	jnz	pu4
	mov	al,[si+1]
	add	si,4
pu4:	mov	ah,bl			; AX = previous:current
	mov	bl,al
	shr	ax,cl			; AL = next screen byte
	cmp	ch,1			; last screen byte of the row?
	jne	pu5			; no
	and	dl,[puLast]
pu5:	call	[puOp]
	inc	di
	mov	dl,0FFh
	dec	ch
	jnz	pu2
	mov	ax,[puRow]		; advance to the next row
	add	ax,2000h
	cmp	ax,4000h		; was it an odd row?
	jb	pu6			; no
	sub	ax,4000h-80		; yes
pu6:	mov	[puRow],ax
	dec	[puRows]
	jnz	pu1
pu9:	pop	ds
	LEAVE
	RETURN
ENDPROC	gfxPut

PUT_OPS		dw	opXor, opPset, opPreset, opOr, opAnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putOps (opXor, opPset, opPreset, opOr, and opAnd)
;
; Inputs:
;	AL = image byte
;	DL = mask
;	ES:DI -> screen byte
;
; Outputs:
;	The masked bits of the screen byte are combined with the image byte
;
; Modifies:
;	AX, DL
;
DEFPROC	opXor
	and	al,dl
	xor	es:[di],al
	ret
ENDPROC	opXor

DEFPROC	opPreset
	not	al			; fall into opPset
ENDPROC	opPreset

DEFPROC	opPset
	mov	ah,es:[di]
	xor	al,ah
	and	al,dl
	xor	es:[di],al
	ret
ENDPROC	opPset

DEFPROC	opOr
	and	al,dl
	or	es:[di],al
	ret
ENDPROC	opOr

DEFPROC	opAnd
	not	dl
	or	al,dl
	and	es:[di],al
	ret
ENDPROC	opAnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getArray
;
; Inputs:
;	DS:DI -> array variable
;
; Outputs:
;	DS:DI -> 1st element
;	AX = # of elements
;	(an "Illegal function call" error occurs if the array isn't an
;	integer array that has been dimensioned)
;
; Modifies:
;	AX, DI, DS
;
DEFPROC	getArray
	mov	ax,[di].SEG		; AX = array block, if any
	test	ax,ax
	jz	ga9
	mov	ds,ax
	cmp	byte ptr ds:[ABLK_TYPE],VAR_LONG
	jne	ga9
	mov	di,ds:[ABLK_DATA]
	mov	ax,ds:[BLK_FREE]
	sub	ax,di
	shr	ax,1
	shr	ax,1
	ret
ga9:	jmp	strIllegal
ENDPROC	getArray

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getImage
;
; Verifies that an integer array is large enough for an image.
;
; Inputs:
;	AX = width (in pixels), SI = height
;	DS:DI -> array variable
;	BH = mode (see gfxInit)
;
; Outputs:
;	DS:DI -> 1st element, which is set to the width in bits, and the
;	2nd element is set to the height (an "Illegal function call" error
;	occurs if the array is too small)
;	AL = bits per pixel
;
; Modifies:
;	AX, CX, DI, DS
;
DEFPROC	getImage
	push	dx
	mov	cl,1
	sub	cl,bh
	shl	ax,cl			; AX = width in bits
	push	ax
	add	ax,7
	shr	ax,1
	shr	ax,1
	shr	ax,1			; AX = bytes per row
	mul	si			; AX = total bytes
	inc	ax
	shr	ax,1
	add	ax,2			; AX = total elements required
	push	ax
	call	getArray		; AX = # elements available
	pop	cx
	cmp	ax,cx
	jb	ga9
	pop	ax
	mov	[di],ax			; 1st element = width in bits
	mov	word ptr [di+2],0
	mov	[di+4],si		; 2nd element = height
	mov	word ptr [di+6],0
	mov	al,2
	sub	al,bh			; AL = bits per pixel
	pop	dx
	ret
ENDPROC	getImage

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getRect
;
; Inputs:
;	SS:SI -> x1 (an ARGVAR, followed by y1, x2, and y2)
;
; Outputs:
;	CX,DX = top left, SI,DI = bottom right (an "Illegal function call"
;	error occurs if any part of the rectangle is off the screen)
;	BH = mode, ES -> video memory (see gfxInit)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	getRect
	call	gfxInit
	push	si
	sub	si,8
	call	getPoint
	pop	si
	push	cx
	push	dx
	call	getPoint
	mov	si,cx
	mov	di,dx
	pop	dx
	pop	cx
	cmp	cx,si
	jle	gr1
	xchg	cx,si
gr1:	cmp	dx,di
	jle	gr2
	xchg	dx,di
gr2:	call	chkPixel
	jc	gr9
	push	cx
	push	dx
	mov	cx,si
	mov	dx,di
	call	chkPixel
	pop	dx
	pop	cx
	jc	gr9
	ret
gr9:	jmp	strIllegal
ENDPROC	getRect

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkPixel
;
; Inputs:
;	CX = x, DX = y
;	BH = mode (see gfxInit)
;
; Outputs:
;	Carry set if the pixel is off the screen
;
; Modifies:
;	None
;
DEFPROC	chkPixel
	push	ax
	push	cx
	push	di
	call	pixAddr
	pop	di
	pop	cx
	pop	ax
	ret
ENDPROC	chkPixel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; bitPos
;
; Inputs:
;	AX = x
;	BH = mode (see gfxInit)
;
; Outputs:
;	AX = offset of x's byte within a row
;	CL = bit offset of x within the byte (from the high bit)
;
; Modifies:
;	AX, CL
;
DEFPROC	bitPos
	test	bh,bh			; 2 bits per pixel?
	jnz	bp1			; no
	shl	ax,1			; yes
bp1:	mov	cl,al
	and	cl,7
	shr	ax,1
	shr	ax,1
	shr	ax,1
	ret
ENDPROC	bitPos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; rowBytes
;
; Inputs:
;	AX = # of bits
;
; Outputs:
;	AX = # of bytes
;	CH = mask for the bits in the last byte
;
; Modifies:
;	AX, CX
;
DEFPROC	rowBytes
	mov	cl,al
	and	cl,7			; CL = # bits in the last byte
	mov	ch,0FFh
	jz	rb1			; (0 means all 8)
	neg	cl
	add	cl,8
	shl	ch,cl
rb1:	add	ax,7
	shr	ax,1
	shr	ax,1
	shr	ax,1
	ret
ENDPROC	rowBytes

CODE	ENDS

	end
