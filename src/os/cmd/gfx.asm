;
; BASIC-DOS Graphics Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for LINE, PRESET, PSET, and VIEW (see gengfx.asm; DRAW
; is in gfxdraw.asm, PAINT is in gfxpaint.asm, GET and PUT are in gfximg.asm,
; and POINT, PMAP, and WINDOW are in gfxpt.asm), which draw directly into CGA
; video memory in video modes 4 and 5 (320x200, 4 colors) and 6 (640x200, 2
; colors); in any other mode, they report an "Illegal function call" error.
; The MOUSE statement and function are here, too (except for mouseReset and
; mouseCall, which are in sys.asm).
;
; Coordinates are clamped to -8192 through 8191 (so that LINE's arithmetic
; can't overflow), and pixels outside the screen (or the viewport that VIEW
; defines; see GFX_VX1) are simply not drawn.  The points that genPoint has
; converted (see gfxPt in gfxpt.asm) are already clamped, and marked as such
; (see GFX_MARK).
;
; The graphics state is kept in GFX_DATA (see GFX_*), whose zero-initialized
; values are the defaults.
;
	GFXDEFS equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<ioctlCon,strIllegal,rtError,mouseCall,mouseReset,mapPoint>
	EXTNEAR	<setScale,releaseStr>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxLastPt
;
; Used by "LINE -(x,y)": pushes the last point referenced (as two longs,
; marked as converted; see gfxPt).
;
; Inputs:
;	None
;
; Outputs:
;	X and Y on the stack
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	gfxLastPt,FAR
	pop	cx
	pop	si			; SI:CX = return address
	mov	bx,ss:[PSP_HEAP]
	mov	ax,GFX_MARK
	push	ax
	push	ss:[bx].GFX_DATA.GFX_LPX
	push	ax
	push	ss:[bx].GFX_DATA.GFX_LPY
	push	si
	push	cx
	ret
ENDPROC	gfxLastPt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxLine
;
; Used by "LINE [(x1,y1)]-(x2,y2)[,[color][,B[F]]]", where box is 0 for a
; line, 1 for a box (B), or 2 for a filled box (BF).
;
; Inputs:
;	2 pairs of coordinates, color (-1 for the default), and box, on the
;	stack
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	gfxLine,FAR
	ARGVAR	lnX1,dword
	ARGVAR	lnY1,dword
	ARGVAR	lnX2,dword
	ARGVAR	lnY2,dword
	ARGVAR	lnColor,dword
	ARGVAR	lnBox,dword
	ENTER
	call	gfxMode
	mov	ax,[lnColor].LW
	mov	dx,[lnColor].HW
	call	getColor		; BL = color
	lea	si,[lnX1]
	call	getPoint
	push	cx
	push	dx			; save the 1st point
	lea	si,[lnX2]
	call	getPoint
	call	setLastPt		; the 2nd point is the last point
	mov	si,cx
	mov	di,dx			; DI:SI = 2nd point
	pop	dx
	pop	cx			; DX:CX = 1st point
	call	mouseArea		; hide the mouse pointer, if necessary
	mov	al,byte ptr [lnBox]
	test	al,al			; a box?
	jnz	ln1			; yes
	call	drawLine		; no, draw a line
	jmp	short ln9
ln1:	call	drawBox
ln9:	LEAVE
	RETURN
ENDPROC	gfxLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; drawBox
;
; Inputs:
;	AL = 1 for a box, 2 for a filled box
;	CX = x1, DX = y1, SI = x2, DI = y2
;	BL = color, BH = mode (see gfxInit)
;	ES -> video memory
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	drawBox
	push	cx
	push	dx
	push	si
	push	di
	cmp	al,1
	ja	db3
	push	di			; draw a box
	mov	di,dx
	call	drawLine		; top
	pop	di
	push	cx
	mov	cx,si
	call	drawLine		; right
	pop	cx
	push	dx
	mov	dx,di
	call	drawLine		; bottom
	pop	dx
	mov	si,cx
	call	drawLine		; left
	jmp	short db9
db3:	cmp	dx,di			; draw a filled box
	jle	db4
	xchg	dx,di			; make sure DX <= DI
db4:	push	di
	mov	di,dx
	call	drawLine		; draw each row
	pop	di
	inc	dx
	cmp	dx,di
	jle	db4
db9:	pop	di
	pop	si
	pop	dx
	pop	cx
	ret
ENDPROC	drawBox

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxView
;
; Used by "VIEW [SCREEN] (x1,y1)-(x2,y2)[,[fill][,border]]", which clips all
; drawing to the viewport, after filling it (unless fill is -1) and drawing a
; border around it (unless border is -1).  Without SCREEN, coordinates are
; relative to the viewport, too (see GF_VREL).  If WINDOW is in effect, its
; world coordinates are mapped to the new viewport.
;
; Inputs:
;	screen (1 if SCREEN, 0 if not), x1, y1, x2, y2, fill, and border, on
;	the stack
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	gfxView,FAR
	ARGVAR	vwScreen,dword
	ARGVAR	vwX1,dword
	ARGVAR	vwY1,dword
	ARGVAR	vwX2,dword
	ARGVAR	vwY2,dword
	ARGVAR	vwFill,dword
	ARGVAR	vwBorder,dword
	ENTER
	call	gfxInit
	call	setClip			; (the border is clipped to the screen)
	mov	di,ss:[PSP_HEAP]
	lea	si,[vwX1]
	mov	cx,4
	jmp	short vw1
vw8:	jmp	strIllegal
vw1:	mov	dx,ss:[di].GFX_DATA.GFX_VX2
	test	cl,1			; a y coordinate?
	jz	vw2			; no
	mov	dx,ss:[di].GFX_DATA.GFX_VY2
vw2:	cmp	word ptr ss:[si].HW,0	; is the coordinate on the screen?
	jne	vw8			; no
	cmp	ss:[si].LW,dx
	ja	vw8			; no
	sub	si,4
	loop	vw1
	mov	cx,[vwX1].LW
	mov	dx,[vwY1].LW
	mov	si,[vwX2].LW
	mov	di,[vwY2].LW
	cmp	cx,si
	jle	vw3
	xchg	cx,si			; make sure CX <= SI
vw3:	cmp	dx,di
	jle	vw4
	xchg	dx,di			; and DX <= DI
vw4:	lea	ax,[vwBorder]
	call	vwColor			; is there a border color?
	jz	vw5			; no
	dec	cx
	dec	dx
	inc	si
	inc	di
	mov	al,1
	call	drawBox			; draw the border
	inc	cx
	inc	dx
	dec	si
	dec	di
vw5:	push	bx
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].GFX_DATA.GFX_VX1,cx
	mov	ss:[bx].GFX_DATA.GFX_VY1,dx
	mov	ss:[bx].GFX_DATA.GFX_VX2,si
	mov	ss:[bx].GFX_DATA.GFX_VY2,di
	mov	al,GF_VIEW
	cmp	byte ptr [vwScreen],0	; SCREEN?
	jne	vw6			; yes
	or	al,GF_VREL
vw6:	and	ss:[bx].GFX_DATA.GFX_FLAGS,NOT (GF_VIEW OR GF_VREL)
	or	ss:[bx].GFX_DATA.GFX_FLAGS,al
	pop	bx
	lea	ax,[vwFill]
	call	vwColor			; is there a fill color?
	jz	vw7			; no
	mov	al,2
	call	drawBox			; fill the viewport
vw7:	call	setScale		; map WINDOW to the viewport, if any
	LEAVE
	RETURN
ENDPROC	gfxView

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; vwColor (gfxView internal function)
;
; Inputs:
;	SS:AX -> color (-1 if none)
;	BL = default color, BH = mode (see gfxInit)
;
; Outputs:
;	ZF set if the color is -1; otherwise, BL = color (see getColor)
;
; Modifies:
;	AX, BL
;
DEFPROC	vwColor
	push	dx
	push	si
	xchg	si,ax			; SS:SI -> color
	mov	ax,ss:[si].LW
	mov	dx,ss:[si].HW
	pop	si
	push	ax
	and	ax,dx
	inc	ax			; -1?
	pop	ax
	jz	vc9			; yes
	pushf
	call	getColor		; BL = color
	popf				; (ZF is still clear)
vc9:	pop	dx
	ret
ENDPROC	vwColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxViewOff
;
; Used by "VIEW", which clips drawing to the screen again.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	gfxViewOff,FAR
	mov	bx,ss:[PSP_HEAP]
	and	ss:[bx].GFX_DATA.GFX_FLAGS,NOT (GF_VIEW OR GF_VREL)
	call	gfxInit			; (which clips to the screen again)
	call	setScale		; map WINDOW to the screen, if any
	ret
ENDPROC	gfxViewOff

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxPset
;
; Used by "PSET (x,y)[,color]" and "PRESET (x,y)[,color]" (for which
; genPset pushes a default color of 0 instead of -1).
;
; Inputs:
;	Coordinates and color (-1 for the default) on the stack
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	gfxPset,FAR
	ARGVAR	psX,dword
	ARGVAR	psY,dword
	ARGVAR	psColor,dword
	ENTER
	call	gfxMode
	mov	ax,[psColor].LW
	mov	dx,[psColor].HW
	call	getColor
	lea	si,[psX]
	call	getPoint
	call	setLastPt
	mov	si,cx
	mov	di,dx
	call	mouseArea		; hide the mouse pointer, if necessary
	call	setPixel
	LEAVE
	RETURN
ENDPROC	gfxPset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; drawLine
;
; Draws a line from DX:CX to DI:SI; horizontal lines (eg, the rows of a filled
; box) are drawn by hline instead.
;
; If both points are in the clip rectangle (the screen, or the viewport that
; VIEW defines), we use the same algorithm as MSBASIC (see
; DOGRPH in msb/GENGRP.ASM), so that the same pixels are drawn, but we update
; the video address and pixel mask as we go (see dlFast); otherwise, we use
; Bresenham's algorithm with setPixel, which clips each pixel to the screen.
;
; Inputs:
;	CX = x1, DX = y1, SI = x2, DI = y2
;	BL = color, BH = mode (see gfxInit)
;	ES -> video memory
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	drawLine
	cmp	dx,di			; horizontal?
	jne	dl0			; no
	jmp	hline			; yes
dl0:	call	inClip			; are both points in the clip rect?
	jc	dl0b			; no
	xchg	cx,si
	xchg	dx,di
	call	inClip
	xchg	cx,si
	xchg	dx,di
	jc	dl0b			; no
	jmp	dlFast			; yes
dl0b:	push	cx
	push	dx
	push	bp
	sub	sp,10
	mov	bp,sp			; [bp] = dx, [bp+2] = dy, [bp+4] = sx,
	mov	ax,si			; [bp+6] = sy, [bp+8] = err
	sub	ax,cx
	mov	word ptr [bp+4],1
	jge	dl1
	neg	ax
	neg	word ptr [bp+4]
dl1:	mov	[bp],ax			; dx = abs(x2 - x1)
	mov	ax,di
	sub	ax,dx
	mov	word ptr [bp+6],1
	jge	dl2
	neg	ax
	neg	word ptr [bp+6]
dl2:	neg	ax
	mov	[bp+2],ax		; dy = -abs(y2 - y1)
	add	ax,[bp]
	mov	[bp+8],ax		; err = dx + dy
dl3:	call	setPixel
	cmp	cx,si
	jne	dl4
	cmp	dx,di
	je	dl9
dl4:	mov	ax,[bp+8]
	add	ax,ax			; AX = e2
	cmp	ax,[bp+2]		; e2 >= dy?
	jl	dl5			; no
	push	ax
	mov	ax,[bp+2]
	add	[bp+8],ax		; err += dy
	pop	ax
	add	cx,[bp+4]		; x += sx
dl5:	cmp	ax,[bp]			; e2 <= dx?
	jg	dl3			; no
	mov	ax,[bp]
	add	[bp+8],ax		; err += dx
	add	dx,[bp+6]		; y += sy
	jmp	dl3
dl9:	add	sp,10
	pop	bp
	pop	dx
	pop	cx
	ret
;
; Like MSBASIC, we draw from the point with the smaller y, along the major
; axis (the axis with the larger delta, or y if they're equal), adding the
; minor delta to a sum (which starts at half the major delta) at every point,
; and advancing along the minor axis whenever the sum reaches the major delta.
; We keep the sum biased by -major in BX, so that only its sign is checked.
;
; AH is the inverted mask of the current pixel and AL is the color bits at that
; position, so drawing a pixel is just an AND and an OR.  Moving in x rotates
; both by the # of bits per pixel (CL), and the carry from rotating AH updates
; DI when we move to another byte.  Moving down in y toggles between the even
; and odd row banks, and advances DI to the next row of the even bank.
;
dlFast:	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	cmp	di,dx			; is y2 < y1?
	jae	df1			; no
	xchg	cx,si			; yes, so swap the points
	xchg	dx,di
df1:	sub	di,dx
	sub	si,cx
	push	di			; push dy
	push	si			; push x2 - x1
	call	pixAddr			; DI -> byte, CL = shift, CH = mask
	mov	al,bl
	and	al,ch
	shl	al,cl			; AL = color bits
	mov	ah,ch
	shl	ah,cl
	not	ah			; AH = inverted mask
	mov	cl,2
	sub	cl,bh			; CL = bits per pixel
	pop	si			; SI = x2 - x1
	pop	bp			; BP = dy
	mov	ch,0			; CH = 0 if x increases
	test	si,si
	jns	df2
	neg	si			; SI = dx
	dec	ch			; CH = -1 if x decreases
df2:	cmp	bp,si			; is dy >= dx?
	jae	df5			; yes, so y is the major axis
	xchg	si,bp			; no, so x is: BP = dx, SI = dy
	mov	dx,bp
	mov	bx,bp
	shr	bx,1
	sub	bx,bp			; BX = sum - major
	inc	dx			; DX = # of points
df3:	and	es:[di],ah		; draw the pixel
	or	es:[di],al
	add	bx,si			; time to move in y?
	jl	df4			; no
	sub	bx,bp
	xor	di,2000h		; move down a row
	test	di,2000h
	jnz	df4
	add	di,80
df4:	test	ch,ch			; move in x
	jnz	df4b
	ror	al,cl			; to the right
	ror	ah,cl
	sbb	di,-1
df4a:	dec	dx
	jnz	df3
	jmp	short df9
df4b:	rol	al,cl			; to the left
	rol	ah,cl
	adc	di,-1
	jmp	df4a

df5:	mov	dx,bp			; BP = dy, SI = dx
	mov	bx,bp
	shr	bx,1
	sub	bx,bp			; BX = sum - major
	inc	dx			; DX = # of points
df6:	and	es:[di],ah		; draw the pixel
	or	es:[di],al
	add	bx,si			; time to move in x?
	jl	df7			; no
	sub	bx,bp
	test	ch,ch
	jnz	df6a
	ror	al,cl			; to the right
	ror	ah,cl
	sbb	di,-1
	jmp	short df7
df6a:	rol	al,cl			; to the left
	rol	ah,cl
	adc	di,-1
df7:	xor	di,2000h		; move down a row
	test	di,2000h
	jnz	df8
	add	di,80
df8:	dec	dx
	jnz	df6

df9:	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	drawLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getColor
;
; Inputs:
;	DX:AX = color, or -1 for the default
;	BL = default color, BH = mode (see gfxInit)
;
; Outputs:
;	BL = color (masked to fit the mode)
;
; Modifies:
;	AX, BL
;
DEFPROC	getColor
	push	ax
	and	ax,dx
	inc	ax			; -1?
	pop	ax
	jz	gc9			; yes, keep the default
	mov	bl,al			; (only the low bits matter)
	DEFLBL	maskColor,near
	mov	al,3
	test	bh,bh
	jz	gc8
	mov	al,1
gc8:	and	bl,al
gc9:	ret
ENDPROC	getColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getPoint
;
; Inputs:
;	SS:SI -> x, followed by y (as ARGVARs, so y is at SI-4)
;
; Outputs:
;	CX = x, DX = y (clamped to -8192 through 8191, unless converted
;	already; see gfxPt), mapped to the screen if VIEW or WINDOW applies
;	(see mapPoint)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	getPoint
	cmp	word ptr ss:[si].HW,GFX_MARK
	jne	gp1			; it hasn't been converted (see gfxPt)
	mov	cx,ss:[si].LW
	mov	dx,ss:[si-4].LW
	ret
gp1:	push	bx
	mov	bx,ss:[PSP_HEAP]
	test	ss:[bx].GFX_DATA.GFX_FLAGS,GF_VREL OR GF_WINDOW
	pop	bx
	jz	gp2			; no mapping is required
	mov	al,4			; (and it becomes the last point)
	jmp	mapPoint
gp2:	mov	ax,ss:[si-4].LW
	mov	dx,ss:[si-4].HW
	call	clampCoord
	push	ax
	mov	ax,ss:[si].LW
	mov	dx,ss:[si].HW
	call	clampCoord
	xchg	cx,ax
	pop	dx
	ret
ENDPROC	getPoint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clampCoord
;
; Inputs:
;	DX:AX = coordinate
;
; Outputs:
;	AX = coordinate, clamped to -8192 through 8191
;
; Modifies:
;	AX, DX
;
DEFPROC	clampCoord
	test	dx,dx
	js	cc2
	jnz	cc1
	cmp	ax,8191
	jbe	cc9
cc1:	mov	ax,8191
	ret
cc2:	inc	dx
	jnz	cc3
	cmp	ax,-8192
	jae	cc9
cc3:	mov	ax,-8192
cc9:	ret
ENDPROC	clampCoord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxInit
;
; Inputs:
;	None
;
; Outputs:
;	BH = 0 for 2 bits per pixel (modes 4 and 5), 1 for 1 (mode 6)
;	BL = default (foreground) color: 3 or 1
;	ES -> video memory
;	(an "Illegal function call" error occurs in any other mode)
;
; The mode is cached in GFX_MODE, and the segment (or, in protected mode,
; the selector) of its video memory in GFX_FRAME, so that we ask the CON
; driver for them only once per program (or after a SCREEN or WIDTH; see
; setScreen).
;
; gfxInit also hides the mouse pointer (see mouseGfx), whereas gfxMode (used
; by statements that call mouseArea themselves) doesn't.  Unless VIEW defined
; a viewport, drawing is clipped to the screen (see setClip).
;
; Modifies:
;	AX, BX, DX, ES
;
DEFPROC	gfxInit
	call	mouseGfx		; hide the mouse pointer, if necessary
	DEFLBL	gfxMode,near		; (LINE and PSET use mouseArea instead)
	mov	bx,ss:[PSP_HEAP]
	mov	dl,byte ptr ss:[bx].GFX_DATA.GFX_MODE
	dec	dl			; is the mode cached?
	jns	gi0			; yes
	push	cx
	mov	cl,1
	mov	al,IOCTL_GETMODE
	call	ioctlCon		; DX = video memory
	jc	gi8
	push	dx
	mov	cl,0
	mov	al,IOCTL_GETMODE
	call	ioctlCon		; DL = video mode
	pop	ax
gi8:	pop	cx
	jc	gi9
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].GFX_DATA.GFX_FRAME,ax
	mov	al,dl
	inc	ax
	mov	byte ptr ss:[bx].GFX_DATA.GFX_MODE,al
gi0:	mov	bx,0003h
	cmp	dl,6
	je	gi1
	sub	dl,4
	cmp	dl,1
	jbe	gi2
gi9:	jmp	strIllegal
gi1:	mov	bx,0101h
gi2:	push	di
	mov	di,ss:[PSP_HEAP]
	mov	es,ss:[di].GFX_DATA.GFX_FRAME
	test	ss:[di].GFX_DATA.GFX_FLAGS,GF_VIEW
	pop	di
	jz	setClip			; no viewport, so clip to the screen
	ret
ENDPROC	gfxInit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setClip
;
; Clips drawing to the screen (GFX_VX1 through GFX_VY2).
;
; Inputs:
;	BH = mode (see gfxInit)
;
; Modifies:
;	AX
;
DEFPROC	setClip
	push	di
	mov	di,ss:[PSP_HEAP]
	sub	ax,ax
	mov	ss:[di].GFX_DATA.GFX_VX1,ax
	mov	ss:[di].GFX_DATA.GFX_VY1,ax
	mov	ss:[di].GFX_DATA.GFX_VY2,199
	mov	ax,319
	test	bh,bh			; 320x200?
	jz	sc1			; yes
	mov	ax,639
sc1:	mov	ss:[di].GFX_DATA.GFX_VX2,ax
	pop	di
	ret
ENDPROC	setClip

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; inClip
;
; Inputs:
;	CX = x, DX = y
;
; Outputs:
;	Carry clear if the point is in the clipping rectangle (see setClip)
;
; Modifies:
;	None
;
DEFPROC	inClip
	push	bx
	mov	bx,ss:[PSP_HEAP]
	cmp	cx,ss:[bx].GFX_DATA.GFX_VX1
	jl	ic8
	cmp	cx,ss:[bx].GFX_DATA.GFX_VX2
	jg	ic8
	cmp	dx,ss:[bx].GFX_DATA.GFX_VY1
	jl	ic8
	cmp	dx,ss:[bx].GFX_DATA.GFX_VY2
	jg	ic8
	pop	bx
	clc
	ret
ic8:	pop	bx
	stc
	ret
ENDPROC	inClip

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setLastPt
;
; Inputs:
;	CX = x, DX = y
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	setLastPt
	push	bx
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].GFX_DATA.GFX_LPX,cx
	mov	ss:[bx].GFX_DATA.GFX_LPY,dx
	pop	bx
	ret
ENDPROC	setLastPt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setPixel
;
; Inputs:
;	CX = x, DX = y
;	BL = color, BH = mode (see gfxInit)
;	ES -> video memory
;
; Outputs:
;	None (pixels outside the screen aren't drawn)
;
; Modifies:
;	None
;
DEFPROC	setPixel
	push	ax
	push	cx
	push	di
	call	pixAddr			; DI, CL = shift, CH = mask
	jc	sp9
	mov	al,bl
	and	al,ch
	shl	al,cl
	shl	ch,cl
	not	ch
	and	ch,es:[di]
	or	al,ch
	mov	es:[di],al
sp9:	pop	di
	pop	cx
	pop	ax
	ret
ENDPROC	setPixel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getPixel
;
; Inputs:
;	CX = x, DX = y
;	BH = mode (see gfxInit)
;	ES -> video memory
;
; Outputs:
;	Carry clear if AL = color, set if the pixel is off the screen
;
; Modifies:
;	AL
;
DEFPROC	getPixel
	push	cx
	push	di
	push	ax
	call	pixAddr			; DI, CL = shift, CH = mask
	pop	ax
	jc	gp9
	mov	al,es:[di]
	shr	al,cl
	and	al,ch
gp9:	pop	di
	pop	cx
	ret
ENDPROC	getPixel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pixAddr
;
; CGA video memory has the even rows at B800:0000 and the odd rows at
; B800:2000, each row being 80 bytes.
;
; Inputs:
;	CX = x, DX = y
;	BH = mode (see gfxInit)
;
; Outputs:
;	Carry clear if on the screen (and in the viewport, if any), with:
;	DI = offset of the pixel's byte
;	CL = bit shift of the pixel within the byte
;	CH = pixel mask (before shifting): 3 or 1
;
; Modifies:
;	AX, CX, DI
;
DEFPROC	pixAddr
	call	inClip
	jc	pa9
	call	rowAddr
	mov	di,ax
	mov	ax,cx
	test	bh,bh			; 2 bits per pixel?
	jnz	pa2			; no
	shr	ax,1
	shr	ax,1
	add	di,ax			; DI = offset of the byte
	not	cl
	and	cl,3
	shl	cl,1			; CL = (3 - (x AND 3)) * 2
	mov	ch,3
	ret				; (carry is clear)
pa2:	shr	ax,1
	shr	ax,1
	shr	ax,1
	add	di,ax			; DI = offset of the byte
	not	cl
	and	cl,7			; CL = 7 - (x AND 7)
	mov	ch,1
	clc
	ret
pa9:	stc
	ret
ENDPROC	pixAddr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; rowAddr
;
; CGA video memory has the even rows at B800:0000 and the odd rows at
; B800:2000, each row being 80 bytes.
;
; Inputs:
;	DX = y (0-199)
;
; Outputs:
;	AX = offset of the row
;
; Modifies:
;	AX
;
DEFPROC	rowAddr
	push	dx
	mov	ax,dx
	shr	ax,1
	mov	dx,ax
	shl	ax,1
	shl	ax,1
	add	ax,dx			; AX = (y / 2) * 5
	shl	ax,1
	shl	ax,1
	shl	ax,1
	shl	ax,1			; AX = (y / 2) * 80
	pop	dx
	test	dl,1			; odd row?
	jz	ra9			; no
	add	ah,20h			; yes
ra9:	ret
ENDPROC	rowAddr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hline
;
; Draws a horizontal line from CX to SI on row DX, clipped to the screen (or
; viewport), a byte at a time (with masks for the partial bytes at either
; end).
;
; Inputs:
;	CX = x1, SI = x2, DX = y
;	BL = color (masked; see getColor), BH = mode (see gfxInit), plus 80h
;	if BL is a byte pattern instead
;	ES -> video memory
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	hline
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	mov	di,ss:[PSP_HEAP]
	cmp	dx,ss:[di].GFX_DATA.GFX_VY1
	jl	hl8x			; the row is outside the clip rectangle
	cmp	dx,ss:[di].GFX_DATA.GFX_VY2
	jg	hl8x
	cmp	cx,si
	jle	hl1
	xchg	cx,si			; CX = left, SI = right
hl1:	mov	ax,ss:[di].GFX_DATA.GFX_VX1
	cmp	si,ax
	jl	hl8x			; the line is entirely outside it
	cmp	cx,ax
	jge	hl2
	xchg	cx,ax			; (CX = leftmost x)
hl2:	mov	ax,ss:[di].GFX_DATA.GFX_VX2	; AX = rightmost x
	cmp	cx,ax
	jg	hl8x
hl3:	cmp	si,ax
	jle	hl4
	mov	si,ax
hl4:	call	rowAddr
	mov	di,ax			; DI = offset of the row
	mov	al,bl			; AL = color (or pattern)
	test	bh,1			; 2 bits per pixel?
	jnz	hl5			; no
	shl	cx,1
	shl	si,1
	inc	si			; CX, SI = bit positions
	mov	ah,55h			; (to repeat the color 4 times)
	jmp	short hl5a
hl5:	mov	ah,0FFh			; (or 8 times)
hl5a:	test	bh,bh			; is AL a pattern?
	js	hl6			; yes
	mul	ah			; no, so repeat the color
hl6:	mov	bl,al			; BL = fill pattern
	mov	ax,cx
	shr	ax,1
	shr	ax,1
	shr	ax,1			; AX = first byte
	mov	dx,si
	shr	dx,1
	shr	dx,1
	shr	dx,1			; DX = last byte
	sub	dx,ax			; DX = # bytes after the first
	add	di,ax			; ES:DI -> first byte
	and	cl,7
	mov	ah,0FFh
	shr	ah,cl			; AH = mask for the first byte
	mov	cx,si
	and	cl,7
	neg	cl
	add	cl,7
	mov	ch,0FFh
	shl	ch,cl			; CH = mask for the last byte
	test	dx,dx			; just one byte?
	jnz	hl7			; no
	and	ah,ch
	call	maskByte
hl8x:	jmp	short hl8
hl7:	call	maskByte		; the first byte
	inc	di
	mov	ah,ch			; AH = mask for the last byte
	mov	cx,dx
	dec	cx			; CX = # whole bytes
	mov	al,bl
	cld
	rep	stosb
	call	maskByte		; the last byte
hl8:	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	hline

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; maskByte
;
; Inputs:
;	AH = mask, BL = pattern
;	ES:DI -> byte
;
; Outputs:
;	The masked bits of the byte are replaced with the pattern
;
; Modifies:
;	AL
;
DEFPROC	maskByte
	mov	al,es:[di]
	xor	al,bl
	and	al,ah
	xor	es:[di],al
	ret
ENDPROC	maskByte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseOn
;
; Used by "MOUSE ON", which resets the mouse (emptying its event queue) and
; shows the pointer.  Like MSBASIC's PEN ON, nothing happens if there's no
; mouse (and the MOUSE function then returns only zeros).
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	mouseOn,FAR
	call	mouseReset		; AX = -1 if there's a mouse
	inc	ax
	jnz	mn9
	or	byte ptr ss:[bx].GFX_DATA.MOUSE_STATE,MS_ON
	inc	ax			; AX = 1 (show the pointer)
	call	mouseCall
mn9:	ret
ENDPROC	mouseOn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseOff
;
; Used by "MOUSE OFF", which resets the mouse (hiding the pointer and emptying
; its event queue).  Nothing happens if there's no mouse.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	mouseOff,FAR
	call	mouseReset
	ret
ENDPROC	mouseOff

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getMouse (MOUSE)
;
; Like MSBASIC's PEN function, MOUSE(n) returns:
;
;	0: the next button event (0 if none, 1 = left button pressed,
;	   2 = left released, 3 = right pressed, 4 = right released)
;	1: x of the event last returned by MOUSE(0)
;	2: y of the event last returned by MOUSE(0)
;	3: current x
;	4: current y
;	5: current buttons (1 = left, 2 = right, 3 = both)
;
; where positions are pixels in graphics modes, or a column and row (starting
; at 1) in text modes.  Every value is zero if there's no mouse.  If gfxInit
; hid the pointer, it's shown again.
;
; Inputs:
;	32-bit return value
;	32-bit n (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	getMouse,FAR
	RETVAR	retMouse,dword
	ARGVAR	mouseNum,dword
	ENTER
	mov	si,ss:[PSP_HEAP]
	test	byte ptr ss:[si].GFX_DATA.MOUSE_STATE,MS_GFX
	jz	gm1
	and	byte ptr ss:[si].GFX_DATA.MOUSE_STATE,NOT MS_GFX
	mov	ax,1			; show the pointer again
	call	mouseCall
gm1:	mov	di,[mouseNum].LW
	cmp	[mouseNum].HW,0
	jne	gmX
	cmp	di,5
	ja	gmX
	mov	ax,ss:[si].GFX_DATA.MOUSE_X
	cmp	di,1
	je	gm8
	mov	ax,ss:[si].GFX_DATA.MOUSE_Y
	cmp	di,2
	je	gm8
	mov	bx,di			; BX = 0 for an event, else the state
	mov	ax,MOUSE_EVENT
	call	mouseCall		; AX = event, BX = buttons, CX,DX = pos
	test	di,di
	jnz	gm3
	mov	ss:[si].GFX_DATA.MOUSE_X,cx
	mov	ss:[si].GFX_DATA.MOUSE_Y,dx
	jmp	short gm8
gm3:	xchg	ax,cx			; AX = x
	cmp	di,3
	je	gm8
	xchg	ax,dx			; AX = y
	cmp	di,4
	je	gm8
	xchg	ax,bx			; AX = buttons
gm8:	mov	[retMouse].LW,ax
	mov	[retMouse].HW,0
	LEAVE
	RETURN
gmX:	jmp	strIllegal
ENDPROC	getMouse

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseGfx and mouseArea
;
; Called by gfxInit (for the entire screen), and by LINE and PSET (for just
; the area they draw), so that if MOUSE ON is in effect, graphics statements
; (eg, GET and PAINT) never see the pointer.  The pointer is hidden with INT
; 33h function 10h (conditional off), which leaves it on the screen if it's
; not in the area, and either way, it's not shown again until the next MOUSE
; function (see getMouse).
;
; Inputs (for mouseArea):
;	CX, DX = one corner (pixels)
;	SI, DI = the opposite corner (pixels)
;	BH = mode (see gfxInit)
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	mouseGfx
	push	cx
	push	dx
	push	si
	push	di
	sub	cx,cx
	sub	dx,dx
	mov	si,7FFFh
	mov	di,si
	jmp	short ma3
ENDPROC	mouseGfx

DEFPROC	mouseArea
	push	cx
	push	dx
	push	si
	push	di
	cmp	cx,si
	jle	ma1
	xchg	cx,si
ma1:	cmp	dx,di
	jle	ma2
	xchg	dx,di
ma2:	test	bh,bh			; 320x200?
	jnz	ma3			; no
	shl	cx,1			; yes, so convert x to virtual units
	shl	si,1
ma3:	push	ax
	push	bx
	mov	bx,ss:[PSP_HEAP]
	test	byte ptr ss:[bx].GFX_DATA.MOUSE_STATE,MS_ON
	jz	ma9
	or	byte ptr ss:[bx].GFX_DATA.MOUSE_STATE,MS_GFX
	or	cx,cx			; clip negative coordinates to zero
	jns	ma4
	sub	cx,cx
ma4:	or	dx,dx
	jns	ma5
	sub	dx,dx
ma5:	or	si,si
	jns	ma6
	sub	si,si
ma6:	or	di,di
	jns	ma7
	sub	di,di
ma7:	mov	ax,10h			; hide the pointer if it's in the area
	call	mouseCall
ma9:	pop	bx
	pop	ax
	pop	di
	pop	si
	pop	dx
	pop	cx
	ret
ENDPROC	mouseArea

CODE	ENDS

	end
