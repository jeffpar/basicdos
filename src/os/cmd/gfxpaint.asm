;
; BASIC-DOS Graphics Runtime Functions: PAINT
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The runtime function for PAINT (see gengfx.asm), which uses the drawing
; functions in gfx.asm; it's separate only because gfx.asm has no symbol space
; for it.
;
	DOSFUNC equ 1
	GFXDEFS equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<strIllegal,rtError,releaseStr>
	EXTNEAR	<getColor,getPoint,gfxInit,hline,inClip,rowAddr,setLastPt>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

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
	mov	ax,[ptPaint].LW
	mov	dx,[ptPaint].HW
	mov	word ptr [ptXor],0	; (and ptTiles)
	cmp	[ptBack].HW,0		; a tile?
	jne	ptA			; no
	call	ptTile			; ptTiles = its length (DX:AX = -1)
ptA:	call	getColor		; BL = paint color
	push	bx
	mov	ax,[ptBorder].LW
	mov	dx,[ptBorder].HW
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
ptErr:	mov	al,BERR_NOMEMORY	; "Out of memory"
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

CODE	ENDS

	end
