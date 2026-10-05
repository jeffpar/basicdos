;
; BASIC-DOS Graphics Runtime Functions: CIRCLE
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The runtime function for CIRCLE (see genCircle in gengfx.asm), which uses
; the drawing functions in gfx.asm.
;
; The algorithm is the same as MSBASIC's (see CIRCLE in msb/ADVGRP.ASM), so
; that the same pixels are drawn, and like MSBASIC, it uses only integer math:
; the angles and aspect, which are doubles, are converted to fixed-point values
; without FPU$ (see dblFix).
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<strIllegal,gfxInit,getColor,getPoint,setLastPt,clampCoord>
	EXTNEAR	<setPixel,drawLine>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

CI_SLINE	equ	01h		; draw a line to the start
CI_ELINE	equ	02h		; draw a line to the end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gfxCircle
;
; Used by "CIRCLE (x,y),r[,[color][,[start][,[end][,aspect]]]]".  The start
; and end angles (in radians, drawn counter-clockwise) and the aspect are
; pointers to doubles (or null if omitted), and a negative angle also draws
; a line from the center to that end of the arc.  The default aspect is 5/6
; in 320x200 mode and 5/12 in 640x200 mode; if the aspect is less than 1, r
; is the x radius, otherwise it's the y radius.
;
; We draw an octant of a circle (using a "midpoint" algorithm, with doubled
; coordinates for rounding), reflecting each point into all 8 octants, with
; the y (or x) offsets scaled by the aspect.  Each point also has a "count"
; (its position around the circle, from 0 to 8 times the number of points per
; octant), so an arc is simply the points whose counts are between the counts
; that the start and end angles correspond to.
;
; Inputs:
;	See above
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	gfxCircle,FAR
	ARGVAR	ciX,dword
	ARGVAR	ciY,dword
	ARGVAR	ciR,dword
	ARGVAR	ciColor,dword
	ARGVAR	ciStart,dword
	ARGVAR	ciEnd,dword
	ARGVAR	ciAspect,dword
	LOCVAR	ciLines,byte		; CI_SLINE and/or CI_ELINE
	LOCVAR	ciOuter,byte		; non-zero to plot points outside SC-EC
	LOCVAR	ciScaleX,byte		; non-zero to scale x instead of y
	LOCVAR	ciAsp,word		; aspect (or 1 / aspect) * 256
	LOCVAR	ciNP,word		; # of points per octant
	LOCVAR	ciNP2,word		; ciNP * 2
	LOCVAR	ciSC,word		; start count
	LOCVAR	ciEC,word		; end count
	LOCVAR	ciCX,word		; center x
	LOCVAR	ciCY,word		; center y
	LOCVAR	ciSum,word		; midpoint algorithm sum
	LOCVAR	ciYP,word		; y' (the current point's count)
	LOCVAR	ciA,word		; reflected offsets (see ciPlot8)
	LOCVAR	ciB,word
	LOCVAR	ciC,word
	LOCVAR	ciD,word
	ENTER
	call	gfxInit
	mov	ax,213			; default aspect: 5/6 * 256 (320x200)
	test	bh,bh
	jz	ci0
	mov	ax,107			; or 5/12 * 256 (640x200)
ci0:	mov	[ciAsp],ax
	mov	ax,[ciColor].LOW
	mov	dx,[ciColor].HIW
	call	getColor		; BL = color
	lea	si,[ciX]
	call	getPoint
	call	setLastPt
	mov	[ciCX],cx
	mov	[ciCY],dx
	push	bx
	mov	ax,[ciR].LOW
	mov	dx,[ciR].HIW
	call	clampCoord
	test	ax,ax
	jns	ci0a
	jmp	ciErr			; the radius must not be negative
ci0a:
	push	ax			; save the radius
	mov	dx,46341		; 65536 * SQR(2) / 2
	mul	dx
	add	ax,8000h
	adc	dx,0
	mov	[ciNP],dx		; NP = radius * SQR(2) / 2 (rounded)
	shl	dx,1
	mov	[ciNP2],dx
;
; Convert the start and end angles (if any) to counts.
;
	sub	ax,ax
	mov	[ciLines],al
	mov	[ciOuter],al
	mov	[ciScaleX],al
	mov	[ciSC],ax		; default start count is 0
	dec	ax
	mov	[ciEC],ax		; default end count is "infinity"
	push	ds
	lds	si,[ciStart]
	mov	cl,CI_SLINE
	call	ciCount
	jc	ci1
	mov	[ciSC],ax
ci1:	lds	si,[ciEnd]
	mov	cl,CI_ELINE
	call	ciCount
	jc	ci2
	mov	[ciEC],ax
ci2:	mov	ax,[ciSC]
	cmp	[ciEC],ax		; is the end count >= the start count?
	jae	ci3			; yes
	xchg	ax,[ciEC]		; no, so swap them, and plot the points
	mov	[ciSC],ax		; outside them instead
	dec	[ciOuter]
	mov	al,[ciLines]
	ASSERT	CI_SLINE,EQ,1
	ASSERT	CI_ELINE,EQ,2
	shr	al,1			; swap the line flags, too
	jnc	ci2a
	or	al,CI_ELINE
ci2a:	mov	[ciLines],al
;
; Get the aspect (or its inverse, if it's > 1) as a fraction of 256.
;
ci3:	mov	ax,[ciAsp]		; AX = default aspect
	lds	si,[ciAspect]
	mov	cx,ds
	jcxz	ci6			; no aspect
	call	dblFix			; DX:AX = aspect * 65536
	cmp	dx,1			; is the aspect > 1?
	jb	ci5			; no
	ja	ci4a			; yes
	test	ax,ax
	jz	ci5			; no (it's exactly 1)
ci4a:	dec	[ciScaleX]		; yes, so scale x by 1 / aspect
	mov	bx,ax
	mov	cx,dx			; CX:BX = aspect * 65536
	mov	dx,0100h
	sub	ax,ax			; DX:AX = 2^24
ci4b:	jcxz	ci4c			; reduce CX:BX to 16 bits
	shr	cx,1
	rcr	bx,1
	shr	dx,1
	rcr	ax,1
	jmp	ci4b
ci4c:	push	bx
	shr	bx,1
	add	ax,bx
	adc	dx,0			; (round)
	pop	bx
	div	bx			; AX = (1 / aspect) * 256
	jmp	short ci6
ci5:	add	ax,128			; AX = aspect * 256 (rounded)
	adc	dx,0
	mov	al,ah
	mov	ah,dl
ci6:	pop	ds
	mov	[ciAsp],ax
	pop	ax			; AX = radius
	pop	bx			; BL = color, BH = mode
;
; The main loop, where SI = X (doubled) and DI = Y (doubled); see CIRCLE in
; msb/ADVGRP.ASM.
;
	shl	ax,1
	xchg	si,ax			; X = radius * 2
	sub	di,di			; Y = 0
	mov	[ciSum],di		; SUM = 0
ci7:	test	di,1			; is Y even?
	jnz	ci8			; no
	push	si
	push	di
	lea	ax,[si+1]
	shr	ax,1			; AX = (X + 1) / 2
	lea	dx,[di+1]
	shr	dx,1			; DX = (Y + 1) / 2
	call	ciPlot8
	pop	di
	pop	si
	cmp	di,si			; done when Y >= X
	jae	ci9
ci8:	mov	ax,[ciSum]
	inc	ax
	add	ax,di
	add	ax,di			; SUM = SUM + 2 * Y + 1
	js	ci8a
	sub	ax,si
	sub	ax,si
	inc	ax			; SUM = SUM - 2 * X + 1
	dec	si			; X = X - 1
ci8a:	mov	[ciSum],ax
	inc	di			; Y = Y + 1
	jmp	ci7
ci9:	LEAVE
	RETURN
ciErr:	jmp	strIllegal
ENDPROC	gfxCircle

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ciCount (gfxCircle internal function, using its frame)
;
; Converts an angle (in radians) to a point count, which is the angle's
; fraction of a circle (2 * PI) times 8 times the # of points per octant.
;
; Inputs:
;	DS:SI -> angle (double), or null if none
;	CL = line flag to set if the angle is negative
;
; Outputs:
;	Carry clear if AX = count, set if there's no angle
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	ciCount
	mov	ax,ds
	cmp	ax,1			; is there an angle?
	jb	cc9			; no
	test	byte ptr [si+7],80h	; is it negative?
	jz	cc1			; no
	or	[ciLines],cl		; yes
cc1:	call	dblFix			; DX:AX = abs(angle) * 65536
	cmp	dx,6			; is the angle more than 2 * PI?
	ja	ciErr			; yes
	mov	cx,10430		; 65536 / (2 * PI)
	mov	bx,ax
	xchg	ax,dx
	mul	cx
	xchg	bx,ax			; BX = high word * 10430
	mul	cx			; DX = (low word * 10430) / 65536
	add	bx,dx			; BX = fraction of a circle * 65536
	jc	ciErr			; (the angle is more than 2 * PI)
	mov	ax,[ciNP]
	shl	ax,1
	shl	ax,1
	shl	ax,1			; AX = # of points in the circle
	mul	bx
	add	ax,8000h
	adc	dx,0
	xchg	ax,dx			; AX = count (rounded)
	clc
cc9:	ret
ENDPROC	ciCount

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ciPlot8 (gfxCircle internal function, using its frame)
;
; Plots the 8 reflections of point (X',Y') of the first octant, where X' is
; the x offset and Y' is the y offset (up) from the center, along with their
; counts; see CPLOT8 in msb/ADVGRP.ASM.  With fx() and fy() scaling (or not)
; the x and y offsets:
;
;	A = fx(X'), B = fy(Y'), C = fx(Y'), D = fy(X')
;
; Inputs:
;	AX = X', DX = Y'
;	BL = color, BH = mode, ES -> video memory
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	ciPlot8
	mov	[ciYP],dx
	push	ax
	push	dx
	call	ciScale			; DX = scaled X'
	mov	[ciA],ax		; (assuming fx() doesn't scale)
	mov	[ciD],dx
	pop	ax
	call	ciScale			; DX = scaled Y'
	mov	[ciC],ax
	mov	[ciB],dx
	pop	ax
	cmp	[ciScaleX],0		; does fx() scale?
	je	cp1			; no
	mov	ax,[ciA]		; yes, so swap A and D, and B and C
	xchg	ax,[ciD]
	mov	[ciA],ax
	mov	ax,[ciB]
	xchg	ax,[ciC]
	mov	[ciB],ax
cp1:	mov	cx,[ciYP]
	mov	ax,[ciA]		; (A,-B), count Y'
	mov	dx,[ciB]
	neg	dx
	call	ciPoint
	add	cx,[ciNP2]
	mov	ax,[ciC]		; (-C,-D), count 2 * NP + Y'
	neg	ax
	mov	dx,[ciD]
	neg	dx
	call	ciPoint
	add	cx,[ciNP2]
	mov	ax,[ciA]		; (-A,B), count 4 * NP + Y'
	neg	ax
	mov	dx,[ciB]
	call	ciPoint
	add	cx,[ciNP2]
	mov	ax,[ciC]		; (C,D), count 6 * NP + Y'
	mov	dx,[ciD]
	call	ciPoint
	mov	cx,[ciNP2]
	sub	cx,[ciYP]
	mov	ax,[ciC]		; (C,-D), count 2 * NP - Y'
	mov	dx,[ciD]
	neg	dx
	call	ciPoint
	add	cx,[ciNP2]
	mov	ax,[ciA]		; (-A,-B), count 4 * NP - Y'
	neg	ax
	mov	dx,[ciB]
	neg	dx
	call	ciPoint
	add	cx,[ciNP2]
	mov	ax,[ciC]		; (-C,D), count 6 * NP - Y'
	neg	ax
	mov	dx,[ciD]
	call	ciPoint
	add	cx,[ciNP2]
	mov	ax,[ciA]		; (A,B), count 8 * NP - Y'
	mov	dx,[ciB]		; (fall into ciPoint)
ENDPROC	ciPlot8

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ciPoint (gfxCircle internal function, using its frame)
;
; Plots a point (or draws a line from it to the center) if its count is
; part of the arc; see CPLOT in msb/ADVGRP.ASM.
;
; Inputs:
;	AX = x offset, DX = y offset (down) from the center
;	CX = count
;	BL = color, BH = mode, ES -> video memory
;
; Modifies:
;	AX, DX, SI, DI
;
DEFPROC	ciPoint
	push	cx
	add	ax,[ciCX]
	add	dx,[ciCY]
	xchg	cx,ax			; CX = x, DX = y, AX = count
	cmp	ax,[ciSC]
	je	cpt4			; the start count
	jb	cpt2			; before the start count
	cmp	ax,[ciEC]
	je	cpt5			; the end count
	ja	cpt2			; after the end count
	cmp	[ciOuter],0		; between the counts, so plot only
	je	cpt7			; if we're plotting the inner points
	jmp	short cpt9
cpt2:	cmp	[ciOuter],0		; outside the counts, so plot only
	jne	cpt7			; if we're plotting the outer points
	jmp	short cpt9
cpt4:	test	[ciLines],CI_SLINE
	jmp	short cpt6
cpt5:	test	[ciLines],CI_ELINE
cpt6:	jz	cpt7
	mov	si,[ciCX]		; draw a line to the center
	mov	di,[ciCY]
	call	drawLine
	jmp	short cpt9
cpt7:	call	setPixel
cpt9:	pop	cx
	ret
ENDPROC	ciPoint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ciScale (gfxCircle internal function, using its frame)
;
; Scales an offset by the aspect (a fraction of 256), rounding like SCALE in
; msb/ADVGRP.ASM.
;
; Inputs:
;	AX = offset (non-negative)
;
; Outputs:
;	AX = offset, DX = scaled offset
;
; Modifies:
;	DX
;
DEFPROC	ciScale
	push	ax
	mov	dx,[ciAsp]
	cmp	dx,256			; is the aspect 1?
	jae	cs8			; yes
	mul	dx
	add	ax,128
	adc	dx,0
	mov	dh,dl
	mov	dl,ah			; DX = (offset * aspect + 128) / 256
	pop	ax
	ret
cs8:	pop	ax
	mov	dx,ax
	ret
ENDPROC	ciScale

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dblFix
;
; Converts the absolute value of a double to a 16.16 fixed-point value,
; directly from its IEEE 754 bits (1 sign bit, 11 exponent bits biased by 1023,
; and 52 fraction bits with an implied leading 1), so FPU$ isn't required.
;
; Inputs:
;	DS:SI -> double
;
; Outputs:
;	DX:AX = abs(value) * 65536, rounded (or FFFFFFFFh if it doesn't fit)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	dblFix
	push	di
	mov	ax,[si+6]
	mov	bx,ax
	and	bx,7FF0h		; BX = exponent (shifted left 4)
	jz	df8			; zero (or too small to matter)
	mov	cl,4
	shr	bx,cl			; BX = biased exponent
	and	ax,0Fh
	mov	cl,11
	shl	ax,cl
	or	ah,80h
	xchg	dx,ax			; DX = 1 + the top 4 fraction bits
	mov	ax,[si+4]
	mov	di,ax
	mov	cl,5
	shr	ax,cl
	or	dx,ax			; DX = top 16 bits of 1.fraction
	mov	ax,di
	mov	cl,11
	shl	ax,cl
	mov	di,[si+2]
	mov	cl,5
	shr	di,cl
	or	ax,di			; DX:AX = 1.fraction * 2^31
	mov	cx,1023 + 31 - 16
	sub	cx,bx			; CX = # of bits to shift right
	jle	df9			; too large
	cmp	cx,32
	ja	df8			; too small
df1:	shr	dx,1
	rcr	ax,1
	loop	df1
	adc	ax,0			; round
	adc	dx,0
	jmp	short df9x
df8:	sub	ax,ax
	cwd
	jmp	short df9x
df9:	mov	ax,-1
	cwd
df9x:	pop	di
	ret
ENDPROC	dblFix

CODE	ENDS

	end
