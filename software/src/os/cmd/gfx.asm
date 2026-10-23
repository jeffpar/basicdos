;
; BASIC-DOS Graphics Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for LINE, PAINT, PRESET, PSET, and VIEW (see gengfx.asm;
; DRAW is in gfxdraw.asm, GET and PUT are in gfximg.asm, and POINT, PMAP, and
; WINDOW are in gfxpt.asm), which draw directly into CGA video memory in video
; modes 4 and 5 (320x200, 4 colors) and 6 (640x200, 2 colors); in any other
; mode, they report an "Illegal function call" error.  The MOUSE statement and
; function are here, too (except for mouseReset and mouseCall, which are in
; sys.asm).
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
	DOSFUNC equ 1
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
vw2:	cmp	word ptr ss:[si].HIW,0	; is the coordinate on the screen?
	jne	vw8			; no
	cmp	ss:[si].LOW,dx
	ja	vw8			; no
	sub	si,4
	loop	vw1
	mov	cx,[vwX1].LOW
	mov	dx,[vwY1].LOW
	mov	si,[vwX2].LOW
	mov	di,[vwY2].LOW
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
	mov	ax,ss:[si].LOW
	mov	dx,ss:[si].HIW
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
; gfxPaint
;
; Used by "PAINT (x,y)[,[paint][,[border][,background]]]", which fills the
; area around x,y that's bounded by the border color (which defaults to the
; paint color).  Like MSBASIC, pixels that already have the paint color are
; fillable (so the fill passes through them), but a span that has nothing left
; to paint is skipped (which is what ensures that the fill ends).
;
; If background isn't -1, paint is a tile string (see ptTile) of up to 64
; bytes, which are painted on successive rows (row y gets byte y MOD length),
; aligned with the bytes of video memory; a span "has nothing left to paint"
; when it already matches its tile byte, unless that byte is the background
; byte (since an unpainted area would match it, too).
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
;	Coordinates, paint color (or tile), border color (the colors are -1
;	for the defaults), and background (-1 if not a tile) on the stack
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
	ARGVAR	ptBack,dword
	LOCVAR	ptBdr,byte		; border color
	LOCVAR	ptColor,byte		; paint color
	LOCVAR	ptMode,byte		; BH from gfxInit
	LOCVAR	ptBpp,byte		; bits per pixel (2 or 1)
	LOCVAR	ptMask,byte		; pixel mask (3 or 1)
	LOCVAR	ptFirst,byte		; mask bit of a byte's leftmost pixel
	LOCVAR	ptFull,byte		; mask of all of a byte's pixels
	LOCVAR	ptDir,byte		; direction of the seeds (1 or -1)
	LOCVAR	ptTiles,byte		; length of the tile (0 if none)
	LOCVAR	ptXor,byte		; tile byte for scanRight (see ptPat)
	LOCVAR	ptPPB,word		; pixels per byte (4 or 8)
	LOCVAR	ptMinX,word		; leftmost x (see setClip)
	LOCVAR	ptMaxX,word		; rightmost x
	LOCVAR	ptMinY,word		; top row
	LOCVAR	ptMaxY,word		; bottom row
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
	mov	word ptr [ptXor],0	; (and ptTiles)
	cmp	[ptBack].HIW,0		; a tile?
	jne	ptA			; no
	call	ptTile			; ptTiles = its length (DX:AX = -1)
ptA:	call	getColor		; BL = paint color
	push	bx
	mov	ax,[ptBorder].LOW
	mov	dx,[ptBorder].HIW
	call	getColor		; BL = border color (default is paint)
	mov	[ptBdr],bl
	pop	bx
	cmp	[ptTiles],0		; a tile?
	je	ptB			; no
	mov	bl,0			; yes (see ptPat)
ptB:	mov	[ptColor],bl
	mov	[ptMode],bh
	mov	ax,0302h		; 2 bits per pixel: AL = bpp, AH = mask
	mov	cx,0F08h		; CL = 1st bit, CH = full mask
	mov	si,4
	test	bh,bh
	jz	pt0
	mov	ax,0101h		; 1 bit per pixel
	mov	cx,0FF80h
	mov	si,8
pt0:	mov	[ptBpp],al
	mov	[ptMask],ah
	mov	[ptFirst],cl
	mov	[ptFull],ch
	mov	[ptPPB],si
	mov	si,ss:[PSP_HEAP]	; copy the clip rectangle
	mov	ax,ss:[si].GFX_DATA.GFX_VX1
	mov	[ptMinX],ax
	mov	ax,ss:[si].GFX_DATA.GFX_VX2
	mov	[ptMaxX],ax
	mov	ax,ss:[si].GFX_DATA.GFX_VY1
	mov	[ptMinY],ax
	mov	ax,ss:[si].GFX_DATA.GFX_VY2
	mov	[ptMaxY],ax
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
	call	inClip			; is it in the clip rectangle?
	jc	ptE9			; no

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
	mov	dx,[ptRow]
	call	ptPat			; AL = tile byte (CF set if background)
	jc	pt3			; the span always needs paint
	mov	[ptXor],al
	mov	cx,[ptXL]
	call	pixRef
	mov	si,[ptXR]
	mov	dl,0
	mov	bx,256			; BX = 256 (the paint color table)
	call	scanRight		; CX = first pixel that needs paint
	mov	[ptXor],0
	cmp	cx,si			; is there one?
	jbe	pt3			; yes
	jmp	pt2			; no, so skip the span
pt3:	mov	cx,[ptXL]
	mov	dx,[ptRow]
	mov	bl,[ptColor]
	mov	bh,[ptMode]
	cmp	[ptTiles],0		; a tile?
	je	pt3a			; no
	call	ptPat
	mov	bl,al			; BL = tile byte
	or	bh,80h			; (which hline uses as is)
pt3a:	call	hline			; fill the span
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

pt9:	mov	ax,ds
	mov	es,ax
	mov	ah,DOS_MEM_FREE
	int	21h
	pop	ds
	cmp	[ptTiles],0		; a tile?
	je	pt9a			; no
	les	di,[ptPaint]
	call	releaseStr		; yes, so release it
pt9a:	LEAVE
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
; ptTile (gfxPaint internal function, using its frame)
;
; Checks the tile string (ptPaint): like MSBASIC, its length must be 1 to 64,
; and it can't have more than two consecutive background bytes (ptBack), or
; painting might never end (since such bytes always need paint).
;
; Outputs:
;	ptTiles = length of the tile
;	DX:AX = -1 (the default paint color)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	ptTile
	push	bx
	push	ds
	lds	si,[ptPaint]
	mov	cx,ds
	jcxz	pti8			; empty string
	lodsb
	mov	ah,0
	mov	cx,ax			; CX = length
	dec	ax
	cmp	ax,63			; is it 1 to 64?
	ja	pti8			; no
	mov	[ptTiles],cl
	mov	dx,cx
	add	dx,cx
	add	dx,cx			; DX = # to check (3 times around)
	sub	cx,cx			; CX = # consecutive background bytes
pti1:	mov	ax,dx
	dec	ax
	div	[ptTiles]		; AH = (DX - 1) MOD length
	mov	bl,ah
	mov	bh,0
	mov	al,[si+bx]
	cmp	al,byte ptr [ptBack]	; background?
	je	pti2			; yes
	sub	cx,cx
	jmp	short pti3
pti2:	inc	cx
	cmp	cx,3			; three (or more) in a row?
	jae	pti8			; yes
pti3:	dec	dx
	jnz	pti1
	pop	ds
	pop	bx
	mov	ax,-1
	cwd
	ret
pti8:	pop	ds
	jmp	strIllegal
ENDPROC	ptTile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ptPat (gfxPaint internal function, using its frame)
;
; Inputs:
;	DX = row
;
; Outputs:
;	AL = the row's tile byte (0 if there's no tile)
;	Carry set if it's the background byte (see gfxPaint)
;
; Modifies:
;	AX
;
DEFPROC	ptPat
	mov	al,0
	cmp	[ptTiles],al		; a tile? (carry is clear)
	je	pq9			; no
	push	si
	push	ds
	mov	ax,dx
	div	[ptTiles]		; AH = row MOD length
	mov	al,ah
	cbw
	lds	si,[ptPaint]
	add	si,ax
	mov	al,[si+1]		; AL = tile byte
	pop	ds
	pop	si
	cmp	al,byte ptr [ptBack]	; background?
	clc
	jne	pq9			; no
	stc
pq9:	ret
ENDPROC	ptPat

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
	cmp	dx,[ptMinY]		; is the row in the clip rectangle?
	jl	ps9			; no
	cmp	dx,[ptMaxY]
	jg	ps9			; no
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
;	AX, CX, DX, DI
;
DEFPROC	scanLeft
sl1:	cmp	cx,[ptMinX]		; at the left edge?
	jle	sl9			; yes
	cmp	ah,[ptFirst]		; leftmost pixel of the byte?
	jne	sl3			; no
	mov	dx,cx
	sub	dx,[ptPPB]
	cmp	dx,[ptMinX]		; yes; is there a whole byte to skip?
	jl	sl2			; no
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
	xor	al,[ptXor]
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
	xor	al,[ptXor]
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
	call	gfxMode
	mov	ax,[psColor].LOW
	mov	dx,[psColor].HIW
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
	cmp	word ptr ss:[si].HIW,GFX_MARK
	jne	gp1			; it hasn't been converted (see gfxPt)
	mov	cx,ss:[si].LOW
	mov	dx,ss:[si-4].LOW
	ret
gp1:	push	bx
	mov	bx,ss:[PSP_HEAP]
	test	ss:[bx].GFX_DATA.GFX_FLAGS,GF_VREL OR GF_WINDOW
	pop	bx
	jz	gp2			; no mapping is required
	mov	al,4			; (and it becomes the last point)
	jmp	mapPoint
gp2:	mov	ax,ss:[si-4].LOW
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
	mov	al,IOCTL_GETMODE
	call	ioctlCon		; DL = video mode
	pop	cx
	jc	gi9
	mov	al,dl
	inc	ax
	mov	bx,ss:[PSP_HEAP]
	mov	byte ptr ss:[bx].GFX_DATA.GFX_MODE,al
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
	push	di
	mov	di,ss:[PSP_HEAP]
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
	inc	ax			; AX = 1 (show the pointer)
	call	mouseCall
	or	byte ptr ss:[bx].GFX_DATA.MOUSE_STATE,MS_ON
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
gm1:	mov	di,[mouseNum].LOW
	cmp	[mouseNum].HIW,0
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
gm8:	mov	[retMouse].LOW,ax
	mov	[retMouse].HIW,0
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
