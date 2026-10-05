;
; BASIC-DOS Graphics Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for DRAW, GET, LINE, PAINT, PRESET, PSET, and PUT (see
; gengfx.asm), which draw directly into CGA video memory in video modes 4 and
; 5 (320x200, 4 colors) and 6 (640x200, 2 colors); in any other mode, they
; report an "Illegal function call" error.
;
; Coordinates are clamped to -8192 through 8191 (so that LINE's arithmetic
; can't overflow), and pixels outside the screen are simply not drawn.
;
; The graphics state is kept in GFX_DATA (see GFX_*), whose zero-initialized
; values are the defaults.
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<ioctlCon,strIllegal,rtError,playChar,playNum,releaseStr>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

GFX_LPX		equ	GFX_DATA+0	; last point referenced (X)
GFX_LPY		equ	GFX_DATA+2	; last point referenced (Y)
GFX_SCALE	equ	GFX_DATA+4	; DRAW scale XOR 4 (byte)
GFX_COLOR	equ	GFX_DATA+5	; DRAW color + 1, or 0 for default
GFX_MODE	equ	GFX_DATA+6	; video mode + 1, or 0 if unknown
;			GFX_DATA+7	; saved video mode + 1 (see saveMode)
;
; These must match the ABLK structure in arr.asm.
;
ABLK_TYPE	equ	08h		; element type (VAR_*)
ABLK_DATA	equ	0Eh		; offset of first element

PUT_XOR		equ	0		; PUT actions (see genPut)
PUT_PSET	equ	1
PUT_PRESET	equ	2
PUT_OR		equ	3
PUT_AND		equ	4

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxDraw
;
; Used by "DRAW string", which supports these commands from MSBASIC's
; graphics macro language (in upper or lower case, with spaces ignored):
;
;	U, D, L, R [n]		move up, down, left, or right n (default 1)
;	E, F, G, H [n]		move diagonally (up and right, down and right,
;				down and left, or up and left)
;	M x,y			move to x,y, or relative to the current point
;				if x begins with + or -
;	B			prefix: move without drawing
;	N			prefix: draw, but don't move
;	C n			color
;	S n			scale (1-255; default 4), where every distance
;				(except an absolute M) is multiplied by n/4
;
; The color and scale persist from one DRAW to the next.
;
; Inputs:
;	string value (popped)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	gfxDraw,FAR
	ARGVAR	pDrawStr,dword
	LOCVAR	drFlags,byte		; bit 0 for B, bit 1 for N
	LOCVAR	drMode,byte		; BH from gfxInit
	LOCVAR	drFgnd,byte		; BL from gfxInit
	LOCVAR	drNegX,byte		; non-zero if M's x is relative
	LOCVAR	drX,word
	LOCVAR	drY,word
	ENTER
	call	gfxInit
	mov	[drMode],bh
	mov	[drFgnd],bl
	push	ds
	lds	si,[pDrawStr]
	mov	cx,ds
	jcxz	dr9			; empty string
	lodsb
	mov	cl,al
	mov	ch,0			; CX = length, DS:SI -> characters
	jmp	short dr0

dr8:	les	di,[pDrawStr]
	call	releaseStr
dr9:	pop	ds
	LEAVE
	RETURN

dr0:	mov	[drFlags],0
dr1:	call	playChar		; AL = next command
	jc	dr8
	cmp	al,'B'
	jne	dr2
	or	[drFlags],1
	jmp	dr1
dr2:	cmp	al,'N'
	jne	dr3
	or	[drFlags],2
	jmp	dr1
dr3:	cmp	al,';'
	je	dr1
	cmp	al,'C'
	jne	dr4
	call	drNum
	inc	ax
	mov	byte ptr ss:[bx].GFX_COLOR,al
	jmp	dr0
dr4:	cmp	al,'S'
	jne	dr5
	call	drNum
	cmp	ax,255
	ja	drE1
	test	al,al
	jz	drE1
	xor	al,4
	mov	byte ptr ss:[bx].GFX_SCALE,al
	jmp	dr0
dr5:	cmp	al,'M'
	jne	dr6
	call	drSigned		; AX = x
	mov	[drX],ax
	mov	[drNegX],dl		; DL = non-zero if relative
	call	playChar
	jc	drE1
	cmp	al,','
	jne	drE1
	call	drSigned		; AX = y
	cmp	[drNegX],0		; relative?
	je	dr5a			; no
	call	drScale
	xchg	[drX],ax
	call	drScale
	mov	dx,[drX]		; DX = scaled y
	jmp	short dr7		; AX = scaled x
dr5a:	xchg	dx,ax			; DX = y
	mov	ax,[drX]		; AX = x
	jmp	short dr7a		; absolute
drE1:	jmp	drErr

dr6:	push	cx
	push	di
	push	es
	push	cs
	pop	es
	mov	di,offset DRAW_DIRS
	mov	cx,8
	repne	scasb
	pop	es
	mov	ax,cx
	pop	di
	pop	cx
	jne	drE1			; not a direction
	push	ax			; AX = direction index (see DRAW_DIRS)
	call	playNum
	jnc	dr6a
	mov	ax,1			; default distance is 1
dr6a:	call	drScale			; AX = scaled distance
	pop	bx			; BX = direction index
	mov	dl,cs:DRAW_DX[bx]
	mov	dh,cs:DRAW_DY[bx]
	mov	bx,ax			; BX = distance
	sub	ax,ax
	test	dl,dl
	jz	dr6b
	mov	ax,bx
	jns	dr6b
	neg	ax
dr6b:	push	ax			; push x distance
	sub	ax,ax
	test	dh,dh
	jz	dr6c
	mov	ax,bx
	jns	dr6c
	neg	ax
dr6c:	xchg	dx,ax			; DX = y distance
	pop	ax			; AX = x distance
;
; AX and DX are the x and y distances of a relative move, which we add to the
; current point, and then draw (unless B) and update the point (unless N).
;
dr7:	mov	bx,ss:[PSP_HEAP]
	add	ax,ss:[bx].GFX_LPX
	add	dx,ss:[bx].GFX_LPY
dr7a:	push	si
	push	di
	push	cx
	mov	si,ax
	mov	di,dx			; DI:SI = new point
	mov	bx,ss:[PSP_HEAP]
	mov	cx,ss:[bx].GFX_LPX
	mov	dx,ss:[bx].GFX_LPY	; DX:CX = current point
	test	[drFlags],1		; B?
	jnz	dr7c			; yes
	mov	al,byte ptr ss:[bx].GFX_COLOR
	mov	bl,[drFgnd]
	sub	al,1
	jb	dr7b
	mov	bl,al
dr7b:	mov	bh,[drMode]
	call	maskColor
	call	drawLine
dr7c:	test	[drFlags],2		; N?
	jnz	dr7d			; yes
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].GFX_LPX,si
	mov	ss:[bx].GFX_LPY,di
dr7d:	pop	cx
	pop	di
	pop	si
	jmp	dr0
drErr:	jmp	strIllegal
ENDPROC	gfxDraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; drNum, drSigned, and drScale (gfxDraw internal functions)
;
; drNum returns AX = required number, and BX -> heap; drSigned returns AX =
; number with an optional sign, and DL = non-zero if a sign was present; and
; drScale returns AX * scale / 4.
;
DEFPROC	drNum
	call	playNum
	jc	drErr
	mov	bx,ss:[PSP_HEAP]
	ret
ENDPROC	drNum

DEFPROC	drSigned
	sub	dx,dx
	jcxz	drErr
	mov	al,[si]
	cmp	al,'+'
	je	ds1
	cmp	al,'-'
	jne	ds2
	inc	dh			; DH = 1 if negative
ds1:	inc	dx			; DL = 1 if signed
	inc	si
	dec	cx
ds2:	push	dx
	call	playNum
	pop	dx
	jc	drErr
	test	dh,dh
	jz	ds3
	neg	ax
ds3:	ret
ENDPROC	drSigned

DEFPROC	drScale
	push	bx
	push	dx
	mov	bx,ss:[PSP_HEAP]
	mov	bl,byte ptr ss:[bx].GFX_SCALE
	xor	bl,4
	mov	bh,0
	imul	bx
	sar	dx,1
	rcr	ax,1
	sar	dx,1
	rcr	ax,1
	pop	dx
	pop	bx
	ret
ENDPROC	drScale

;
; DRAW_DIRS is in reverse, so that the count that REPNE SCASB leaves in CX is
; the direction's index in DRAW_DX and DRAW_DY (ie, U, D, L, R, E, F, G, H).
;
DRAW_DIRS	db	"HGFERLDU"
DRAW_DX		db	0, 0, -1, 1, 1, 1, -1, -1
DRAW_DY		db	-1, 1, 0, 0, -1, 1, 1, -1

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
; gfxLastPt
;
; Used by "LINE -(x,y)": pushes the last point referenced (as two longs).
;
; Inputs:
;	None
;
; Outputs:
;	X and Y on the stack
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	gfxLastPt,FAR
	pop	cx
	pop	si			; SI:CX = return address
	mov	bx,ss:[PSP_HEAP]
	mov	ax,ss:[bx].GFX_LPX
	cwd
	push	dx
	push	ax
	mov	ax,ss:[bx].GFX_LPY
	cwd
	push	dx
	push	ax
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
	call	gfxInit
	mov	ax,[lnColor].LOW
	mov	dx,[lnColor].HIW
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
	mov	al,byte ptr [lnBox]
	cmp	al,1
	jae	ln1
	call	drawLine		; draw a line
	jmp	short ln9
ln1:	ja	ln3
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
	jmp	short ln9
ln3:	cmp	dx,di			; draw a filled box
	jle	ln4
	xchg	dx,di			; make sure DX <= DI
ln4:	push	di
	mov	di,dx
	call	drawLine		; draw each row
	pop	di
	inc	dx
	cmp	dx,di
	jle	ln4
ln9:	LEAVE
	RETURN
ENDPROC	gfxLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxPaint
;
; Used by "PAINT (x,y)[,[paint][,border]]", which fills the area around x,y
; that's bounded by the border color (which defaults to the paint color).
; Like MSBASIC, pixels that already have the paint color are fillable (so the
; fill passes through them), but a span that has nothing left to paint is
; skipped (which is what ensures that the fill ends).
;
; We use a "span fill": each seed (initially, x,y) fills the horizontal span
; of fillable pixels around it, and then adds seeds for the fillable spans in
; the next row (in the seed's direction), and in the row it came from, but
; only where the span extends beyond its parent span (which was already
; filled), until no seeds remain.  The seeds are kept in
; a temporary block of memory (up to PT_SEEDS of them), and if it overflows,
; some areas may be left unfilled.
;
; To scan rows quickly, the block also contains two 256-byte tables that map
; every possible screen byte to a mask of its boundary pixels and a mask of
; its pixels that don't have the paint color (with bits from ptFirst down to
; 1, for the pixels from left to right), so that we can test a pixel with
; XLAT, and skip entire bytes that are fillable (or not).
;
; Inputs:
;	Coordinates, paint color, and border color (the colors are -1 for
;	the defaults) on the stack
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
PT_SEEDS	equ	2000		; preferred maximum # of seeds
PT_TABLE	equ	512		; size of the tables (seeds follow them)

DEFPROC	gfxPaint,FAR
	ARGVAR	ptX,dword
	ARGVAR	ptY,dword
	ARGVAR	ptPaint,dword
	ARGVAR	ptBorder,dword
	LOCVAR	ptBdr,byte		; border color
	LOCVAR	ptColor,byte		; paint color
	LOCVAR	ptMode,byte		; BH from gfxInit
	LOCVAR	ptBpp,byte		; bits per pixel (2 or 1)
	LOCVAR	ptMask,byte		; pixel mask (3 or 1)
	LOCVAR	ptFirst,byte		; mask bit of a byte's leftmost pixel
	LOCVAR	ptFull,byte		; mask of all of a byte's pixels
	LOCVAR	ptDir,byte		; direction of the seeds (1 or -1)
	LOCVAR	ptPPB,word		; pixels per byte (4 or 8)
	LOCVAR	ptMaxX,word		; rightmost x (319 or 639)
	LOCVAR	ptTop,word		; offset of the next seed
	LOCVAR	ptMax,word		; offset of the last possible seed
	LOCVAR	ptXL,word		; left end of the current span
	LOCVAR	ptXR,word		; right end of the current span
	LOCVAR	ptRow,word		; row of the current span
	LOCVAR	ptPL,word		; left end of the parent span
	LOCVAR	ptPR,word		; right end of the parent span
	LOCVAR	ptSR,word		; right end of the range to seed
	ENTER
	call	gfxInit
	mov	ax,[ptPaint].LOW
	mov	dx,[ptPaint].HIW
	call	getColor		; BL = paint color
	push	bx
	mov	ax,[ptBorder].LOW
	mov	dx,[ptBorder].HIW
	call	getColor		; BL = border color (default is paint)
	mov	[ptBdr],bl
	pop	bx
	mov	[ptColor],bl
	mov	[ptMode],bh
	mov	ax,0302h		; 2 bits per pixel: AL = bpp, AH = mask
	mov	cx,0F08h		; CL = 1st bit, CH = full mask
	mov	dx,319
	mov	si,4
	test	bh,bh
	jz	pt0
	mov	ax,0101h		; 1 bit per pixel
	mov	cx,0FF80h
	mov	dx,639
	mov	si,8
pt0:	mov	[ptBpp],al
	mov	[ptMask],ah
	mov	[ptFirst],cl
	mov	[ptFull],ch
	mov	[ptMaxX],dx
	mov	[ptPPB],si
	lea	si,[ptX]
	call	getPoint		; DX:CX = seed
	call	setLastPt
	push	ds
	push	cx
	mov	bx,(PT_TABLE + PT_SEEDS * 8) SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	21h			; AX = segment of table and seeds
	jnc	pt1
	cmp	bx,(PT_TABLE + 64) SHR 4
	jb	ptE			; if there's not enough memory, try
	mov	ah,DOS_MEM_ALLOC	; the largest block available
	int	21h
	jnc	pt1
ptE:	jmp	ptErr
pt1:	mov	cl,4
	shl	bx,cl
	sub	bx,8
	mov	[ptMax],bx		; ptMax = offset of the last seed
	pop	cx
	mov	ds,ax
	call	ptTable			; build the table
	mov	[ptTop],PT_TABLE
	mov	[ptRow],dx
	mov	[ptDir],1
	mov	[ptXL],7FFFh		; the first seed has no parent span
	mov	[ptXR],7FFEh
	call	ptPush			; push the first seed
	cmp	dx,200			; is it on the screen?
	jae	ptE9			; no
	cmp	cx,[ptMaxX]
	ja	ptE9

pt2:	mov	si,[ptTop]
	cmp	si,PT_TABLE		; any seeds left?
	ja	pt2a			; yes
ptE9:	jmp	pt9
pt2a:	sub	si,8
	mov	[ptTop],si
	mov	cx,[si]
	mov	dl,[si+2]
	mov	dh,0			; DX:CX = next seed
	mov	al,[si+3]
	mov	[ptDir],al
	mov	ax,[si+4]
	mov	[ptPL],ax
	mov	ax,[si+6]
	mov	[ptPR],ax
	mov	[ptRow],dx
	sub	bx,bx			; BX = 0 (for XLAT)
	call	pixRef			; ES:DI, AH -> pixel
	mov	al,es:[di]
	xlat
	test	al,ah			; is the seed still fillable?
	jnz	pt2			; no
	push	cx
	push	di
	push	ax
	call	scanLeft		; CX = left end of the span
	mov	[ptXL],cx
	pop	ax
	pop	di
	pop	cx
	mov	si,[ptMaxX]
	mov	dl,0			; DL = 0 (scan fillable pixels)
	call	scanRight		; CX = right end of the span + 1
	dec	cx
	mov	[ptXR],cx
	mov	cx,[ptXL]
	mov	dx,[ptRow]
	call	pixRef
	mov	si,[ptXR]
	mov	dl,0
	mov	bx,256			; BX = 256 (the paint color table)
	call	scanRight		; CX = first pixel that needs paint
	cmp	cx,si			; is there one?
	jbe	pt3			; yes
	jmp	pt2			; no, so skip the span
pt3:	mov	cx,[ptXL]
	mov	dx,[ptRow]
	mov	bl,[ptColor]
	mov	bh,[ptMode]
	call	hline			; fill the span
	mov	al,[ptDir]
	cbw
	add	dx,ax			; DX = the next row in this direction
	mov	cx,[ptXL]
	mov	si,[ptXR]
	call	ptSeeds			; seed all of it
	neg	[ptDir]
	mov	al,[ptDir]
	cbw
	mov	dx,[ptRow]
	add	dx,ax			; DX = the row we came from
	mov	cx,[ptXL]
	mov	si,[ptPL]
	dec	si
	cmp	si,[ptXR]
	jle	pt4
	mov	si,[ptXR]		; SI = min(ptXR, ptPL-1)
pt4:	push	dx
	call	ptSeeds			; seed where we overhang on the left
	pop	dx
	mov	cx,[ptPR]
	inc	cx
	cmp	cx,[ptXL]
	jge	pt5
	mov	cx,[ptXL]		; CX = max(ptXL, ptPR+1)
pt5:	mov	si,[ptXR]
	call	ptSeeds			; and where we overhang on the right
	jmp	pt2

pt9:	push	es
	mov	ax,ds
	mov	es,ax
	mov	ah,DOS_MEM_FREE
	int	21h
	pop	es
	pop	ds
	LEAVE
	RETURN
ptErr:	mov	al,7			; "Out of memory"
	jmp	rtError
ENDPROC	gfxPaint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ptTable (gfxPaint internal function, using its frame)
;
; Builds the tables at DS:0 and DS:256 that map every screen byte to a mask of
; its boundary pixels and a mask of its pixels that need paint (see gfxPaint).
;
; Modifies:
;	AX, BX
;
DEFPROC	ptTable
	push	cx
	push	dx
	sub	bx,bx			; BX = byte value (and table offset)
ptt1:	mov	ah,0			; AH = boundary mask
	mov	ch,0			; CH = mask of pixels needing paint
	mov	dh,[ptFirst]		; DH = mask bit of the leftmost pixel
	mov	cl,8
	sub	cl,[ptBpp]		; CL = shift of the leftmost pixel
ptt2:	mov	al,bl
	shr	al,cl
	and	al,[ptMask]		; AL = pixel
	cmp	al,[ptBdr]
	jne	ptt3
	or	ah,dh			; the pixel is a boundary
ptt3:	cmp	al,[ptColor]
	je	ptt4
	or	ch,dh			; the pixel needs paint
ptt4:	shr	dh,1
	sub	cl,[ptBpp]
	jns	ptt2
	mov	[bx],ah
	mov	[bx+256],ch
	inc	bl
	jnz	ptt1
	pop	dx
	pop	cx
	ret
ENDPROC	ptTable

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ptSeeds (gfxPaint internal function, using its frame)
;
; Adds a seed (in direction ptDir, with ptXL and ptXR as its parent span) for
; every fillable span of row DX from CX to SI.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	ptSeeds
	cmp	cx,si			; is the range empty?
	jg	ps9			; yes
	cmp	dx,200			; is the row on the screen?
	jae	ps9			; no
	mov	[ptSR],si
	push	dx
	sub	bx,bx			; BX = 0 (for XLAT)
	call	pixRef			; ES:DI, AH -> pixel
	pop	dx
ps1:	mov	si,[ptSR]
	push	dx
	mov	dl,[ptFull]		; DL = non-zero (scan boundary pixels)
	call	scanRight		; CX = next fillable pixel
	pop	dx
	cmp	cx,si			; past the end?
	jg	ps9			; yes
	call	ptPush			; add a seed for the span
	push	dx
	mov	dl,0			; DL = 0 (scan fillable pixels)
	call	scanRight		; CX = next boundary pixel
	pop	dx
	jmp	ps1
ps9:	ret
ENDPROC	ptSeeds

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ptPush (gfxPaint internal function, using its frame)
;
; Adds a seed for DX:CX (with direction ptDir and parent span ptXL to ptXR),
; if there's room.
;
; Modifies:
;	SI
;
DEFPROC	ptPush
	mov	si,[ptTop]
	cmp	si,[ptMax]		; any room for another seed?
	ja	pp9			; no
	push	ax
	mov	[si],cx			; x
	mov	al,[ptDir]
	mov	ah,al
	mov	al,dl
	mov	[si+2],ax		; y and direction
	mov	ax,[ptXL]
	mov	[si+4],ax		; and the parent span
	mov	ax,[ptXR]
	mov	[si+6],ax
	pop	ax
	add	si,8
	mov	[ptTop],si
pp9:	ret
ENDPROC	ptPush

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pixRef (gfxPaint internal function, using its frame)
;
; Inputs:
;	CX = x, DX = y (both on the screen)
;
; Outputs:
;	ES:DI -> pixel's byte
;	AH = pixel's mask bit (see gfxPaint)
;
; Modifies:
;	AX, DI
;
DEFPROC	pixRef
	call	rowAddr
	mov	di,ax
	mov	ax,cx
	push	cx
	mov	cl,[ptBpp]
	dec	cl
	mov	ch,7
	shr	ch,cl			; CH = 7 or 3 (pixels per byte - 1)
	and	ch,al
	shr	ax,1
	shr	ax,1
	cmp	cl,0			; 1 bit per pixel?
	jne	pr1			; no
	shr	ax,1
pr1:	add	di,ax			; DI = offset of the pixel's byte
	mov	cl,ch
	mov	ah,[ptFirst]
	shr	ah,cl			; AH = pixel's mask bit
	pop	cx
	ret
ENDPROC	pixRef

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scanLeft (gfxPaint internal function, using its frame)
;
; Moves left from a fillable pixel, as long as the pixels are fillable.
;
; Inputs:
;	CX = x (fillable), with ES:DI and AH from pixRef
;	BX = 0, DS:0 -> table
;
; Outputs:
;	CX = x of the leftmost fillable pixel
;
; Modifies:
;	AX, CX, DI
;
DEFPROC	scanLeft
sl1:	jcxz	sl9			; at the left edge
	cmp	ah,[ptFirst]		; leftmost pixel of the byte?
	jne	sl3			; no
	cmp	cx,[ptPPB]		; yes; is there a whole byte to skip?
	jb	sl2			; no
	mov	al,es:[di-1]
	xlat
	test	al,al			; is the previous byte all fillable?
	jnz	sl2			; no
	sub	cx,[ptPPB]		; yes, skip it
	dec	di
	jmp	sl1
sl2:	mov	ah,1			; the previous pixel is the rightmost
	dec	di			; pixel of the previous byte
	jmp	short sl4
sl3:	shl	ah,1
sl4:	mov	al,es:[di]
	xlat
	test	al,ah			; is the previous pixel fillable?
	jnz	sl9			; no
	dec	cx			; yes
	jmp	sl1
sl9:	ret
ENDPROC	scanLeft

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scanRight (gfxPaint internal function, using its frame)
;
; Moves right from a pixel, as long as the pixels are fillable (if DL is 0) or
; boundaries (if DL is non-zero), stopping after SI.
;
; Inputs:
;	CX = x, with ES:DI and AH from pixRef
;	SI = rightmost x to scan
;	DL = 0 or ptFull
;	BX = 0, DS:0 -> table
;
; Outputs:
;	CX = x of the first pixel that doesn't match (or SI + 1),
;	with ES:DI and AH updated to match
;
; Modifies:
;	AX, CX, DI
;
DEFPROC	scanRight
sr1:	cmp	cx,si			; past the end?
	jg	sr9			; yes
	cmp	ah,[ptFirst]		; leftmost pixel of the byte?
	jne	sr2			; no
	mov	al,es:[di]
	xlat
	cmp	al,dl			; does the entire byte match?
	jne	sr2			; no
	mov	ax,cx
	add	ax,[ptPPB]
	dec	ax
	cmp	ax,si			; and is it all before the end?
	mov	ah,[ptFirst]
	jg	sr2			; no
	add	cx,[ptPPB]		; yes, skip it
	inc	di
	jmp	sr1
sr2:	mov	al,es:[di]
	xlat
	and	al,ah			; AL = non-zero if a boundary
	jz	sr3
	test	dl,dl			; boundary; are we scanning those?
	jz	sr9			; no
	jmp	short sr4
sr3:	test	dl,dl			; fillable; are we scanning those?
	jnz	sr9			; no
sr4:	inc	cx
	shr	ah,1			; move to the next pixel
	jnz	sr1
	mov	ah,[ptFirst]
	inc	di
	jmp	sr1
sr9:	ret
ENDPROC	scanRight

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
	call	gfxInit
	mov	ax,[psColor].LOW
	mov	dx,[psColor].HIW
	call	getColor
	lea	si,[psX]
	call	getPoint
	call	setLastPt
	call	setPixel
	LEAVE
	RETURN
ENDPROC	gfxPset

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
; drawLine
;
; Draws a line (using Bresenham's algorithm) from DX:CX to DI:SI; horizontal
; lines (eg, the rows of a filled box) are drawn by hline instead.
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
dl0:	push	cx
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
ENDPROC	drawLine

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
; getPoint
;
; Inputs:
;	SS:SI -> x, followed by y (as ARGVARs, so y is at SI-4)
;
; Outputs:
;	CX = x, DX = y (clamped to -8192 through 8191)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	getPoint
	mov	ax,ss:[si-4].LOW
	mov	dx,ss:[si-4].HIW
	call	clampCoord
	push	ax
	mov	ax,ss:[si].LOW
	mov	dx,ss:[si].HIW
	call	clampCoord
	xchg	cx,ax
	pop	dx
	ret
ENDPROC	getPoint

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
; The mode is cached in GFX_MODE, so that we ask the CON driver for it only
; once per program (or after a SCREEN or WIDTH; see setScreen).
;
; Modifies:
;	AX, BX, DX, ES
;
DEFPROC	gfxInit
	mov	bx,ss:[PSP_HEAP]
	mov	dl,byte ptr ss:[bx].GFX_MODE
	dec	dl			; is the mode cached?
	jns	gi0			; yes
	push	cx
	mov	al,IOCTL_GETMODE
	call	ioctlCon		; DL = video mode
	pop	cx
	jc	gi9
	mov	al,dl
	inc	ax
	mov	bx,ss:[PSP_HEAP]
	mov	byte ptr ss:[bx].GFX_MODE,al
gi0:	mov	bx,0003h
	cmp	dl,6
	je	gi1
	sub	dl,4
	cmp	dl,1
	jbe	gi2
gi9:	jmp	strIllegal
gi1:	mov	bx,0101h
gi2:	mov	ax,0B800h
	mov	es,ax
	ret
ENDPROC	gfxInit

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
	mov	ss:[bx].GFX_LPX,cx
	mov	ss:[bx].GFX_LPY,dx
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
;	Carry clear if on the screen, with:
;	DI = offset of the pixel's byte
;	CL = bit shift of the pixel within the byte
;	CH = pixel mask (before shifting): 3 or 1
;
; Modifies:
;	AX, CX, DI
;
DEFPROC	pixAddr
	cmp	dx,200
	jae	pa9
	call	rowAddr
	mov	di,ax
	mov	ax,cx
	test	bh,bh			; 2 bits per pixel?
	jnz	pa2			; no
	cmp	ax,320
	jae	pa9
	shr	ax,1
	shr	ax,1
	add	di,ax			; DI = offset of the byte
	not	cl
	and	cl,3
	shl	cl,1			; CL = (3 - (x AND 3)) * 2
	mov	ch,3
	ret				; (carry is clear)
pa2:	cmp	ax,640
	jae	pa9
	shr	ax,1
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
; Draws a horizontal line from CX to SI on row DX, clipped to the screen,
; a byte at a time (with masks for the partial bytes at either end).
;
; Inputs:
;	CX = x1, SI = x2, DX = y
;	BL = color, BH = mode (see gfxInit)
;	ES -> video memory
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	hline
	cmp	dx,200
	jb	hl0
	ret
hl0:	push	bx
	push	cx
	push	dx
	push	si
	push	di
	cmp	cx,si
	jle	hl1
	xchg	cx,si			; CX = left, SI = right
hl1:	mov	ax,319
	test	bh,bh
	jz	hl2
	mov	ax,639			; AX = rightmost x
hl2:	test	si,si
	js	hl8x			; the line is entirely off the screen
	cmp	cx,ax
	jg	hl8x
	test	cx,cx
	jns	hl3
	sub	cx,cx
hl3:	cmp	si,ax
	jle	hl4
	mov	si,ax
hl4:	call	rowAddr
	mov	di,ax			; DI = offset of the row
	mov	al,bl
	and	al,3
	test	bh,bh			; 2 bits per pixel?
	jnz	hl5			; no
	mov	ah,55h
	mul	ah			; AL = color repeated 4 times
	shl	cx,1
	shl	si,1
	inc	si			; CX, SI = bit positions
	jmp	short hl6
hl5:	and	al,1
	neg	al			; AL = 00h or FFh
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

CODE	ENDS

	end
