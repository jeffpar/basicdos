;
; BASIC-DOS Graphics Runtime Functions: Points
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The functions that convert the points of graphics statements to screen
; coordinates (see genPoint in gengfx.asm), mapping them to the viewport that
; VIEW defines and from the world coordinates that WINDOW defines, along with
; the runtime functions for WINDOW, PMAP, and POINT; the drawing functions
; (and VIEW) are in gfx.asm.
;
; World coordinates are doubles, so WINDOW requires the FPU$ driver; each
; axis has its own GFXAXIS (see GFX_WORLD), so that most of the functions
; below handle one axis at a time, with BP pointing to its GFXAXIS (since
; FPU$ functions preserve only BP and DS).
;
	GFXDEFS equ 1
	WINDEFS equ 1
	include	cmd.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<strIllegal,gfxInit,getPixel,clampCoord,getFPUFunc>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxPt, gfxStep, gfxPtD, and gfxStepD
;
; Called after the code for a point (see genPoint) to replace its x and y
; (longs, or for gfxPtD and gfxStepD, doubles) with screen coordinates (see
; mapPt), relative to the last point referenced for a STEP point (gfxStep and
; gfxStepD), and making it the last point referenced.
;
; Inputs:
;	x and y on the stack (not popped)
;
; Outputs:
;	x and y replaced
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	gfxStepD,FAR
	mov	al,7
	jmp	short gpc0
ENDPROC	gfxStepD

DEFPROC	gfxPtD,FAR
	mov	al,5
	jmp	short gpc0
ENDPROC	gfxPtD

DEFPROC	gfxStep,FAR
	mov	al,6
	jmp	short gpc0
ENDPROC	gfxStep

DEFPROC	gfxPt,FAR
	mov	al,4
gpc0:	mov	si,sp
	add	si,8			; SS:SI -> x
	call	mapPt
	ret
ENDPROC	gfxPt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mapPoint
;
; Called by getPoint (for a point that genPoint didn't convert) and gfxPoint
; to map a point with long coordinates to the screen (see mapPt).
;
; Inputs:
;	AL = 4 to make it the last point referenced, 0 if not
;	SS:SI -> x, followed by y (as ARGVARs, so y is at SI-4)
;
; Outputs:
;	CX = x, DX = y
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	mapPoint
	push	bx
	push	di
	push	es
	call	mapPt
	pop	es
	pop	di
	pop	bx
	mov	cx,ss:[si].LOW
	mov	dx,ss:[si-4].LOW
	ret
ENDPROC	mapPoint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mapPt
;
; Replaces x and y with clamped screen coordinates (see clampCoord), whose
; high words are set to GFX_MARK, so that getPoint uses them as is (a long
; coordinate can't have that high word, unless it's less than -2147418112).
; Unless it's a STEP point, a point is relative to the viewport if VIEW (but
; not VIEW SCREEN) defined one, and in world coordinates if WINDOW defined
; them (see mwCoord).
;
; Inputs:
;	AL bit 0 set for doubles, bit 1 for STEP, bit 2 for the last point
;	SS:SI -> x, followed by y (as ARGVARs, so y is at SI-4)
;
; Outputs:
;	x and y replaced
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	mapPt
	mov	bx,ss:[PSP_HEAP]
	mov	ah,ss:[bx].GFX_DATA.GFX_FLAGS
	test	ah,GF_WINDOW		; world coordinates?
	jnz	mpW			; yes
	test	ah,GF_VREL		; relative to the viewport?
	jz	mp1			; no
	or	al,8			; AL bit 3 = relative to the viewport
mp1:	test	al,1			; doubles?
	jz	mp2			; no
	push	ax
	push	si
	push	word ptr ss:[si].HIW
	push	word ptr ss:[si].LOW	; push x (a pointer to a double)
	push	word ptr ss:[si-4].HIW
	push	word ptr ss:[si-4].LOW	; push y
	mov	bx,FPU_CVT2DL
	call	fpuOp			; and convert them to longs
	pop	ax
	pop	dx			; DX:AX = y
	pop	cx
	pop	di			; DI:CX = x
	pop	si
	mov	ss:[si-4].LOW,ax
	mov	ss:[si-4].HIW,dx
	mov	ss:[si].LOW,cx
	mov	ss:[si].HIW,di
	pop	ax
	mov	bx,ss:[PSP_HEAP]
mp2:	call	mpCoord			; convert x
	sub	si,4
	inc	bx
	inc	bx			; (GFX_LPY follows GFX_LPX, and so on)
	call	mpCoord			; convert y
	add	si,4
	ret

mpW:	push	bp
	push	si
	lea	bp,[bx].GFX_WORLD	; BP -> GFXAXIS for x
	sub	di,di			; DI = 0 for x, 2 for y
mw1:	push	ax
	push	di
	push	si
	mov	dx,ss:[bx+di].GFX_DATA.GFX_LPX
	call	mwCoord			; AX = screen coordinate
	pop	si
	pop	di
	pop	cx			; CL = flags
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[si].LOW,ax
	mov	word ptr ss:[si].HIW,GFX_MARK
	test	cl,4			; is it the last point?
	jz	mw2			; no
	mov	ss:[bx+di].GFX_DATA.GFX_LPX,ax
	mov	[bp].WIN_LP,ax		; (and WIN_L is its world coordinate)
mw2:	xchg	ax,cx			; AL = flags
	sub	si,4
	add	bp,GFXAXIS_LEN		; BP -> GFXAXIS for y
	inc	di
	inc	di
	cmp	di,4
	jb	mw1
	pop	si
	pop	bp
	ret
ENDPROC	mapPt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mpCoord
;
; Inputs:
;	AL = flags (see mapPt; bit 3 is set if relative to the viewport)
;	BX = heap (plus 2 for y)
;	SS:SI -> coordinate
;
; Outputs:
;	Coordinate replaced
;
; Modifies:
;	CX, DX, DI
;
DEFPROC	mpCoord
	mov	cx,ax			; CL = flags
	mov	ax,ss:[si].LOW
	mov	dx,ss:[si].HIW		; DX:AX = coordinate
	mov	di,ss:[bx].GFX_DATA.GFX_LPX
	test	cl,2			; STEP?
	jnz	mc1			; yes, so add the last coordinate
	mov	di,ss:[bx].GFX_DATA.GFX_VX1
	test	cl,8			; relative to the viewport?
	jnz	mc1			; yes, so add its origin
	sub	di,di
mc1:	add	ax,di
	adc	dx,0
	test	di,di
	jns	mc2
	dec	dx			; (sign-extended)
mc2:	call	clampCoord		; AX = clamped coordinate
	mov	ss:[si].LOW,ax
	mov	word ptr ss:[si].HIW,GFX_MARK
	test	cl,4			; is it the last point?
	jz	mc9			; no
	mov	ss:[bx].GFX_DATA.GFX_LPX,ax
mc9:	xchg	ax,cx			; AL = flags
	ret
ENDPROC	mpCoord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mwCoord
;
; Maps a world coordinate to the screen.  A STEP coordinate is added to the
; last point's world coordinate (see worldLP), and the last point's world
; coordinate (WIN_L) is updated if AL bit 2 is set (mapPt updates WIN_LP).
;
; Inputs:
;	AL = flags (see mapPt)
;	DX = last point (screen coordinate)
;	SS:SI -> coordinate
;	BP -> GFXAXIS
;
; Outputs:
;	AX = screen coordinate (clamped)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	mwCoord
	test	al,2			; STEP?
	jz	mw3			; no
	push	ax
	push	si
	call	worldLP			; WIN_L = the last point
	pop	si
	pop	ax
	mov	di,WIN_T
	call	mwLoad			; push the coordinate (as a double)
	mov	ax,WIN_L
	mov	di,ax
	mov	bx,FPU_ADD
	call	fpuOp2			; WIN_L += the coordinate
	jmp	short mw5
mw3:	mov	di,WIN_T
	test	al,4			; is it the last point?
	jz	mw4			; no
	mov	di,WIN_L		; yes, so it's the new WIN_L
	test	al,1			; a double?
	jz	mw4			; no
	push	ds
	push	si
	lds	si,ss:[si]		; DS:SI -> double
	push	ss
	pop	es
	add	di,bp			; ES:DI -> WIN_L
	mov	cx,4
	rep	movsw
	pop	si
	pop	ds
	push	ss
	lea	ax,[bp].WIN_L
	push	ax			; push a pointer to WIN_L
	jmp	short mw5
mw4:	call	mwLoad			; push the coordinate (as a double)
mw5:	mov	ax,WIN_W1
	mov	di,WIN_T
	mov	bx,FPU_SUB
	call	fpuOp2			; WIN_T = the coordinate - WIN_W1
	mov	ax,WIN_S
	mov	di,WIN_T
	mov	bx,FPU_MUL
	call	fpuOp2			; WIN_T *= WIN_S
	mov	bx,FPU_CVT1DL
	call	fpuOp			; and convert WIN_T to a long
	pop	ax
	pop	dx			; DX:AX = WIN_T
	add	ax,[bp].WIN_B
	adc	dx,0
	jmp	clampCoord
ENDPROC	mwCoord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mwLoad
;
; Pushes a pointer to a coordinate's double, converting a long coordinate to
; a double first.
;
; Inputs:
;	AL bit 0 set if the coordinate is a double
;	DI = GFXAXIS field for the double, if the coordinate is a long
;	SS:SI -> coordinate
;	BP -> GFXAXIS
;
; Outputs:
;	Pointer to a double on the stack
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	mwLoad
	pop	cx			; CX = return address
	push	word ptr ss:[si].HIW
	push	word ptr ss:[si].LOW	; push the coordinate
	push	cx
	test	al,1			; a double?
	jnz	ml9			; yes
	mov	bx,FPU_CVT1LD
	jmp	fpuOpDst		; no, so convert it
ml9:	ret
ENDPROC	mwLoad

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; worldLP
;
; Makes sure that WIN_L is the world coordinate of the last point referenced,
; which it is if the last point hasn't changed since WIN_L was set (eg, by
; DRAW); otherwise, WIN_L is set from the last point (see unmapCoord).
;
; Inputs:
;	DX = last point (screen coordinate)
;	BP -> GFXAXIS
;
; Outputs:
;	WIN_L and WIN_LP updated, if necessary
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	worldLP
	cmp	dx,[bp].WIN_LP		; is WIN_L the last point?
	jne	wl1			; no
	ret
wl1:	mov	[bp].WIN_LP,dx
	xchg	ax,dx
	mov	di,WIN_L		; fall into unmapCoord
ENDPROC	worldLP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; unmapCoord
;
; Maps a screen coordinate to a world coordinate: (AX - WIN_B) / WIN_S +
; WIN_W1.
;
; Inputs:
;	AX = screen coordinate
;	DI = GFXAXIS field for the world coordinate
;	BP -> GFXAXIS
;
; Outputs:
;	World coordinate stored
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	unmapCoord
	push	di
	sub	ax,[bp].WIN_B
	cwd
	push	dx
	push	ax
	mov	bx,FPU_CVT1LD
	call	fpuOpDst		; [DI] = AX - WIN_B
	mov	ax,WIN_S
	mov	bx,FPU_DIV
	call	um1			; [DI] /= WIN_S
	mov	ax,WIN_W1
	mov	bx,FPU_ADD
	call	um1			; [DI] += WIN_W1
	pop	ax
	pop	ax
	pop	di
	ret
um1:	mov	di,sp
	mov	di,ss:[di+6]		; DI = the field again
	jmp	short fpuOp2
ENDPROC	unmapCoord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fpuOp2, fpuOpDst, and fpuOp
;
; Call an FPU$ function that operates on the stack (see FPUTBL); fpuOp2
; pushes a pointer to the GFXAXIS field at AX (as the top operand) and sets
; ES:DI to the GFXAXIS field at DI (for the result), fpuOpDst does only the
; latter, and fpuOp does neither.
;
; Inputs:
;	BX = FPUTBL offset
;	AX = GFXAXIS field (fpuOp2 only)
;	DI = GFXAXIS field (fpuOp2 and fpuOpDst only)
;	BP -> GFXAXIS
;	Operands on the stack (beneath the return address)
;
; Outputs:
;	As returned by the function
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	fpuOp2
	pop	cx
	push	ss
	add	ax,bp
	push	ax			; push a pointer to the field at AX
	push	cx
	DEFLBL	fpuOpDst,near
	push	ss
	pop	es
	add	di,bp			; ES:DI -> the field at DI
	DEFLBL	fpuOp,near
	call	getFPUFunc		; DX:AX -> the function
	pop	cx
	push	cs
	push	cx			; (so that it returns to our caller)
	push	dx
	push	ax
	db	0CBh			; RETF to the function
ENDPROC	fpuOp2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setScale
;
; If WINDOW is in effect, maps its world coordinates to the viewport (or the
; screen): for each axis, the world coordinates are sorted, WIN_B is set to
; the screen coordinate of the smaller (WIN_W1), which for y is the bottom of
; the viewport (unless WINDOW SCREEN), and WIN_S is set to the number of
; pixels per world unit (negative for y, unless WINDOW SCREEN).  An "Illegal
; function call" error occurs if the world coordinates are equal.
;
; Inputs:
;	The viewport (or screen) in GFX_VX1 through GFX_VY2 (see gfxInit)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	setScale
	mov	bx,ss:[PSP_HEAP]
	test	ss:[bx].GFX_DATA.GFX_FLAGS,GF_WINDOW
	jz	ss9			; no WINDOW
	push	bp
	lea	bp,[bx].GFX_WORLD	; BP -> GFXAXIS for x
	sub	ax,ax
	call	ssAxis
	add	bp,GFXAXIS_LEN		; BP -> GFXAXIS for y
	mov	ax,2
	call	ssAxis
	pop	bp
ss9:	ret
ENDPROC	setScale

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ssAxis (setScale internal function)
;
; Inputs:
;	AX = 0 for x, 2 for y
;	BP -> GFXAXIS
;
; Outputs:
;	WIN_B and WIN_S updated (and WIN_W1 and WIN_W2 sorted)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	ssAxis
	mov	bx,ss:[PSP_HEAP]
	mov	dl,ss:[bx].GFX_DATA.GFX_FLAGS
	mov	di,ax
	mov	cx,ss:[bx+di].GFX_DATA.GFX_VX1
	mov	si,ss:[bx+di].GFX_DATA.GFX_VX2
	test	al,al			; y?
	jz	sa1			; no
	test	dl,GF_WSCRN		; does y increase downward?
	jnz	sa1			; yes
	xchg	cx,si			; no, so WIN_W1 is at the bottom
sa1:	mov	[bp].WIN_B,cx
	mov	[bp].WIN_LP,8000h	; (WIN_L is no longer the last point)
	sub	si,cx
	xchg	ax,si
	cwd
	push	dx
	push	ax			; push the number of pixels (signed)
	push	ss
	lea	ax,[bp].WIN_W2
	push	ax
	mov	ax,WIN_W1
	mov	di,WIN_T
	mov	bx,FPU_SUB
	call	fpuOp2			; WIN_T = WIN_W2 - WIN_W1
	pop	ax
	pop	ax
	mov	ax,word ptr [bp+WIN_T+6]
	test	ax,ax			; is WIN_T negative?
	jns	sa3			; no
	and	byte ptr [bp+WIN_T+7],7Fh
	sub	di,di
	mov	cx,4
sa2:	mov	dx,word ptr [bp+di+WIN_W1]
	xchg	dx,word ptr [bp+di+WIN_W2]
	mov	word ptr [bp+di+WIN_W1],dx
	inc	di			; swap WIN_W1 and WIN_W2
	inc	di
	loop	sa2
sa3:	test	ax,7FF0h		; is WIN_T zero (or denormal)?
	jz	sa8			; yes
	mov	di,WIN_S
	mov	bx,FPU_CVT1LD
	call	fpuOpDst		; WIN_S = the number of pixels
	mov	ax,WIN_T
	mov	di,WIN_S
	mov	bx,FPU_DIV
	call	fpuOp2			; WIN_S /= WIN_T
	pop	ax
	pop	ax
	ret
sa8:	jmp	strIllegal
ENDPROC	ssAxis

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxRadD
;
; Called after the code for a CIRCLE radius that's a double (see genCircle)
; to replace it with a radius in pixels (see rdScale), whose high word is set
; to GFX_MARK, so that getRadius uses it as is.
;
; Inputs:
;	radius (a pointer to a double) on the stack (not popped)
;
; Outputs:
;	radius replaced
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	gfxRadD,FAR
	mov	si,sp
	add	si,4			; SS:SI -> radius
	push	bp
	push	si
	push	word ptr ss:[si].HIW
	push	word ptr ss:[si].LOW	; push the radius
	call	rdScale			; AX = radius (in pixels)
	pop	si
	pop	bp
	mov	ss:[si].LOW,ax
	mov	word ptr ss:[si].HIW,GFX_MARK
	ret
ENDPROC	gfxRadD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getRadius
;
; Called by gfxCircle for its radius, which is in world units (of x) if
; WINDOW is in effect, unless gfxRadD converted it already.
;
; Inputs:
;	SS:SI -> radius
;
; Outputs:
;	AX = radius (in pixels, clamped; see clampCoord)
;
; Modifies:
;	AX, DX
;
DEFPROC	getRadius
	mov	ax,ss:[si].LOW
	mov	dx,ss:[si].HIW
	cmp	dx,GFX_MARK		; converted already?
	je	gr9			; yes
	push	bx
	mov	bx,ss:[PSP_HEAP]
	test	ss:[bx].GFX_DATA.GFX_FLAGS,GF_WINDOW
	jz	gr8			; no WINDOW
	push	cx
	push	si
	push	di
	push	es
	push	bp
	push	dx
	push	ax			; push the radius
	lea	bp,[bx].GFX_WORLD	; BP -> GFXAXIS for x
	mov	di,WIN_T
	mov	bx,FPU_CVT1LD
	call	fpuOpDst		; convert it to a double
	call	rdScale			; AX = radius (in pixels)
	pop	bp
	pop	es
	pop	di
	pop	si
	pop	cx
	pop	bx
	ret
gr8:	pop	bx
	jmp	clampCoord
gr9:	ret
ENDPROC	getRadius

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; rdScale
;
; Inputs:
;	radius (a pointer to a double) on the stack (popped)
;
; Outputs:
;	AX = radius (in pixels, clamped), multiplied by the x scale (WIN_S)
;	if WINDOW is in effect
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES, BP
;
DEFPROC	rdScale
	pop	cx
	pop	ax
	pop	dx
	push	cx
	push	dx
	push	ax			; (the radius goes above our return)
	mov	bx,ss:[PSP_HEAP]
	lea	bp,[bx].GFX_WORLD	; BP -> GFXAXIS for x
	test	ss:[bx].GFX_DATA.GFX_FLAGS,GF_WINDOW
	jz	rs1			; no WINDOW
	mov	ax,WIN_S
	mov	di,WIN_T
	mov	bx,FPU_MUL
	call	fpuOp2			; WIN_T = the radius * WIN_S
rs1:	mov	bx,FPU_CVT1DL
	call	fpuOp			; and convert it to a long
	pop	ax
	pop	dx
	jmp	clampCoord
ENDPROC	rdScale

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxWindow
;
; Used by "WINDOW [SCREEN] (x1,y1)-(x2,y2)", which defines the world
; coordinates of the viewport (or the screen): the smaller x is on the left,
; and the smaller y is at the bottom (or with SCREEN, at the top).
;
; Inputs:
;	screen (1 if SCREEN, 0 if not), and x1, y1, x2, and y2 (pointers to
;	doubles), on the stack
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	gfxWindow,FAR
	ARGVAR	wnScreen,dword
	ARGVAR	wnX1,dword
	ARGVAR	wnY1,dword
	ARGVAR	wnX2,dword
	ARGVAR	wnY2,dword
	ENTER
	call	gfxInit			; (which also clips to the screen)
	mov	bx,ss:[PSP_HEAP]
	mov	al,GF_WINDOW
	cmp	byte ptr [wnScreen],0	; SCREEN?
	je	wn1			; no
	or	al,GF_WSCRN
wn1:	and	ss:[bx].GFX_DATA.GFX_FLAGS,NOT (GF_WINDOW OR GF_WSCRN)
	or	ss:[bx].GFX_DATA.GFX_FLAGS,al
	push	ss
	pop	es
	lea	di,[bx].GFX_WORLD
	lea	si,[wnX1]
	mov	dx,2
wn2:	call	wnCopy			; x1 (or x2)
	add	di,GFXAXIS_LEN-8
	call	wnCopy			; y1 (or y2)
	sub	di,GFXAXIS_LEN		; (ES:DI -> WIN_W2 for x)
	dec	dx
	jnz	wn2
	call	setScale
	LEAVE
	RETURN
ENDPROC	gfxWindow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; wnCopy (gfxWindow internal function)
;
; Copies the double that the pointer at SS:SI points to to ES:DI, and then
; advances SI to the next pointer (at SI-4).
;
; Modifies:
;	CX, SI, DI
;
DEFPROC	wnCopy
	push	ds
	push	si
	lds	si,ss:[si]
	mov	cx,4
	rep	movsw
	pop	si
	pop	ds
	sub	si,4
	ret
ENDPROC	wnCopy

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxWindowOff
;
; Used by "WINDOW", which ends world coordinates.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	BX
;
DEFPROC	gfxWindowOff,FAR
	mov	bx,ss:[PSP_HEAP]
	and	ss:[bx].GFX_DATA.GFX_FLAGS,NOT (GF_WINDOW OR GF_WSCRN)
	ret
ENDPROC	gfxWindowOff

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxPmap (PMAP)
;
; Used by "PMAP(v,n)", which maps v from a world x (if n is 0) or y (if n is
; 1) to a physical coordinate (ie, relative to the viewport, unless VIEW
; SCREEN), or from a physical x (if n is 2) or y (if n is 3) to a world
; coordinate.  Without WINDOW, v is returned as is.
;
; Inputs:
;	pointer to double result (in a slot)
;	v (pointer to a double) and n (popped)
;
; Outputs:
;	double result updated
;
; Modifies:
;	Any
;
DEFPROC	gfxPmap,FAR
	RETVAR	retPmap,dword
	ARGVAR	pmV,dword
	ARGVAR	pmN,dword
	ENTER
	call	gfxInit
	mov	ax,[pmN].LOW
	cmp	[pmN].HIW,0
	jne	pm8
	cmp	ax,3			; is n valid (0-3)?
	ja	pm8			; no
	push	ds
	lds	si,[pmV]		; DS:SI -> v
	les	di,[retPmap]		; ES:DI -> result
	mov	bx,ss:[PSP_HEAP]
	mov	cl,ss:[bx].GFX_DATA.GFX_FLAGS
	test	cl,GF_WINDOW		; world coordinates?
	jz	pm7			; no, so return v
	pop	ds
	push	bp
	push	es
	push	di			; save the result pointer
	lea	si,[pmV]
	call	pmAxis			; BP -> GFXAXIS, DX = origin
	push	dx
	test	al,2			; to world?
	jnz	pm4			; yes
	mov	al,1			; (a double that isn't the last point)
	call	mwCoord			; AX = screen coordinate
	pop	dx
	sub	ax,dx			; AX = physical coordinate
	cwd
	pop	di
	pop	es			; ES:DI -> result
	push	dx
	push	ax
	mov	bx,FPU_CVT1LD
	call	fpuOp			; store it as a double
	pop	ax
	pop	ax
	pop	bp
	jmp	short pm9
pm4:	push	word ptr ss:[si].HIW
	push	word ptr ss:[si].LOW	; push v
	mov	bx,FPU_CVT1DL
	call	fpuOp			; and convert it to a long
	pop	ax
	pop	dx
	call	clampCoord
	pop	dx
	add	ax,dx			; AX = screen coordinate
	mov	di,WIN_T
	call	unmapCoord		; WIN_T = world coordinate
	lea	si,[bp].WIN_T
	pop	di
	pop	es			; ES:DI -> result
	pop	bp
	push	ds
	push	ss
	pop	ds			; DS:SI -> WIN_T
pm7:	mov	cx,4
	rep	movsw
	pop	ds
pm9:	LEAVE
	RETURN
pm8:	jmp	strIllegal
ENDPROC	gfxPmap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmAxis
;
; Inputs:
;	AX = 0 or 2 for x, 1 or 3 for y
;	BX = heap
;	CL = GFX_FLAGS
;
; Outputs:
;	BP -> GFXAXIS
;	DX = origin (the viewport's, if relative to it, otherwise 0)
;	DI = 0 for x, 2 for y
;
; Modifies:
;	DX, DI, BP
;
DEFPROC	pmAxis
	mov	di,ax
	and	di,1
	lea	bp,[bx].GFX_WORLD	; BP -> GFXAXIS for x
	jz	pa1
	add	bp,GFXAXIS_LEN		; BP -> GFXAXIS for y
	inc	di			; DI = 2
pa1:	sub	dx,dx
	test	cl,GF_VREL		; relative to the viewport?
	jz	pa9			; no
	mov	dx,ss:[bx+di].GFX_DATA.GFX_VX1
pa9:	ret
ENDPROC	pmAxis

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxPoint (POINT)
;
; Used by "POINT(x,y)", which returns the color of the pixel at x,y (or -1 if
; it's off the screen or outside the viewport), and "POINT(n)", which returns
; the last point referenced: its physical x (if n is 0) or y (if n is 1), or
; its world x (if n is 2) or y (if n is 3), rounded to an integer (without
; WINDOW, they're the same as 0 and 1).  A function can't tell how many
; parameters were supplied, so the default y, -128, means POINT(n) (which is
; safe, since such a y is never on the screen).
;
; Inputs:
;	32-bit return value
;	x (or n) and y (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	Any
;
DEFPROC	gfxPoint,FAR
	RETVAR	retPoint,dword
	ARGVAR	poX,dword
	ARGVAR	poY,dword
	ENTER
	call	gfxInit
	lea	si,[poX]
	cmp	[poY].LOW,-128		; POINT(n)?
	jne	po2			; no
	cmp	[poY].HIW,-1
	jne	po2			; no
	mov	ax,[poX].LOW
	cmp	[poX].HIW,0
	jne	po8
	cmp	ax,3			; is n valid (0-3)?
	ja	po8			; no
	mov	bx,ss:[PSP_HEAP]
	mov	cl,ss:[bx].GFX_DATA.GFX_FLAGS
	mov	ch,al			; CH = n
	push	bp
	call	pmAxis			; BP -> GFXAXIS, DX = origin
	mov	ax,ss:[bx+di].GFX_DATA.GFX_LPX
	sub	ax,dx			; AX = physical coordinate
	test	ch,2			; world?
	jz	po1			; no
	test	cl,GF_WINDOW		; world coordinates?
	jz	po1			; no, so it's the same
	add	ax,dx
	xchg	dx,ax			; DX = screen coordinate
	call	worldLP			; WIN_L = the last point
	push	ss
	lea	ax,[bp].WIN_L
	push	ax
	mov	bx,FPU_CVT1DL
	call	fpuOp			; convert WIN_L to a long
	pop	ax
	pop	dx
	pop	bp
	jmp	short po4
po1:	pop	bp
	jmp	short po3
po2:	mov	al,0			; (POINT doesn't change the last point)
	call	mapPoint		; CX = x, DX = y
	call	getPixel		; AL = color (carry set if off screen)
	mov	ah,0
	jnc	po3
	mov	ax,-1
po3:	cwd
po4:	mov	[retPoint].LOW,ax
	mov	[retPoint].HIW,dx
	LEAVE
	RETURN
po8:	jmp	strIllegal
ENDPROC	gfxPoint

CODE	ENDS

	end
