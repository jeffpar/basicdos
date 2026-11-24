;
; BASIC-DOS Graphics Runtime Functions: DRAW
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The runtime function for DRAW (see genDraw in gengfx.asm), which uses the
; drawing functions in gfx.asm, and the parsing functions that it shares with
; PLAY (see snd.asm and strvar.asm).
;
	GFXDEFS equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<strIllegal,playChar,playNum,releaseStr,execStr>
	EXTNEAR	<gfxInit,gfxMode,maskColor,drawLine,gfxPaint>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

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
;	A n			angle n (0-3), rotating moves by n * 90 degrees
;	TA n			angle n degrees (-360 to 360), counterclockwise
;	P paint,border		paint the area around the current point (as
;				PAINT does)
;	Xvariable;		draw the commands in a string variable
;
; Any number can be "=variable;" instead (see playNum), and semicolons can
; separate commands.  Relative moves are rotated by the angle (see drRotate).
; The color, scale, and angle persist from one DRAW to the next.
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
	LOCVAR	drDepth,byte		; # of X commands in progress
	LOCVAR	drAsp,byte		; aspect ratio * 256 (see drRotate)
	LOCVAR	drInv,word		; 1 / aspect ratio * 256
	LOCVAR	drX,word
	LOCVAR	drY,word
	ENTER
	call	gfxInit
	mov	[drMode],bh
	mov	[drFgnd],bl
	mov	[drDepth],0
	mov	ax,213			; 5/6 * 256 in 320x200 mode
	mov	dx,307			; 6/5 * 256
	test	bh,bh
	jz	dr0a
	mov	ax,107			; 5/12 * 256 in 640x200 mode
	mov	dx,615			; 12/5 * 256
dr0a:	mov	[drAsp],al
	mov	[drInv],dx
	push	ds
	lds	si,[pDrawStr]
	mov	cx,ds
	jcxz	dr9			; empty string
	lodsb
	mov	cl,al
	mov	ch,0			; CX = length, DS:SI -> characters
	jmp	short dr0

dr8:	cmp	[drDepth],0		; end of an X command's string?
	je	dr8a			; no
	dec	[drDepth]
	pop	cx
	pop	si
	pop	ds			; yes, so resume the string that had it
	jmp	short dr0
dr8a:	les	di,[pDrawStr]
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
	mov	byte ptr ss:[bx].GFX_DATA.GFX_COLOR,al
	jmp	dr0
dr4:	cmp	al,'S'
	jne	dr4a
	call	drNum
	cmp	ax,255
	ja	drE0
	test	al,al
	jz	drE0
	xor	al,4
	mov	byte ptr ss:[bx].GFX_DATA.GFX_SCALE,al
	jmp	dr0
drE0:	jmp	drErr
dr4a:	cmp	al,'A'
	jne	dr4c
	call	drNum			; AX = n
	cmp	ax,3
	ja	drE0
	mov	dl,90
	mul	dl			; AX = n * 90
dr4b:	mov	ss:[bx].GFX_DATA.GFX_ANGLE,ax
	jmp	dr0
dr4c:	cmp	al,'T'
	jne	dr4d
	call	playChar
	jc	drE0
	cmp	al,'A'
	jne	drE0
	call	drSigned		; AX = degrees
	mov	bx,ss:[PSP_HEAP]
	add	ax,360			; AX = 0 to 720, if valid
	cmp	ax,720
	ja	drE0
	sub	dx,dx
	mov	di,360
	div	di
	xchg	ax,dx			; AX = degrees MOD 360
	jmp	dr4b
dr4d:	cmp	al,'P'
	jne	dr4e
	call	drNum			; AX = paint color
	push	ax
	call	playChar
	jc	drE0
	cmp	al,','
	jne	drE0
	call	drNum			; AX = border color
	pop	dx			; DX = paint color
	push	ds
	push	si
	push	cx
	mov	di,GFX_MARK
	push	di
	push	ss:[bx].GFX_DATA.GFX_LPX
	push	di
	push	ss:[bx].GFX_DATA.GFX_LPY
	sub	di,di
	push	di
	push	dx
	push	di
	push	ax
	dec	di
	push	di
	push	di			; (no tile)
	push	cs
	call	gfxPaint		; paint at the current point
	call	gfxMode			; (ES -> video memory again)
	pop	cx
	pop	si
	pop	ds
	jmp	dr0
dr4e:	cmp	al,'X'
	jne	dr5
	lea	di,[drDepth]
	call	execStr			; DS:SI -> the X command's string
	jnc	dr4f
	jmp	dr8			; (it's empty)
dr4f:	jmp	dr0
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
	mov	bx,ss:[PSP_HEAP]
	test	ss:[bx].GFX_DATA.GFX_FLAGS,GF_VREL
	jz	dr7a			; absolute
	add	ax,ss:[bx].GFX_DATA.GFX_VX1
	add	dx,ss:[bx].GFX_DATA.GFX_VY1
	jmp	short dr7a		; relative to the viewport
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
dr7:	call	drRotate
	mov	bx,ss:[PSP_HEAP]
	add	ax,ss:[bx].GFX_DATA.GFX_LPX
	add	dx,ss:[bx].GFX_DATA.GFX_LPY
dr7a:	push	si
	push	di
	push	cx
	mov	si,ax
	mov	di,dx			; DI:SI = new point
	mov	bx,ss:[PSP_HEAP]
	mov	cx,ss:[bx].GFX_DATA.GFX_LPX
	mov	dx,ss:[bx].GFX_DATA.GFX_LPY	; DX:CX = current point
	test	[drFlags],1		; B?
	jnz	dr7c			; yes
	mov	al,byte ptr ss:[bx].GFX_DATA.GFX_COLOR
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
	mov	ss:[bx].GFX_DATA.GFX_LPX,si
	mov	ss:[bx].GFX_DATA.GFX_LPY,di
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
	mov	bl,byte ptr ss:[bx].GFX_DATA.GFX_SCALE
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; drRotate (gfxDraw internal function, using its frame)
;
; Rotates a relative move counterclockwise by the DRAW angle (A or TA), with
; the distances scaled by the aspect ratio (drAsp and drInv), so that rotated
; figures keep their shape.  For multiples of 90 degrees, we use the same
; integer arithmetic as MSBASIC (see DOMOVR in msb/ADVGRP.ASM), so that A
; draws the same pixels; for other angles, we use SIN_TABLE.
;
; Inputs:
;	AX = x distance, DX = y distance
;
; Outputs:
;	AX = rotated x distance, DX = rotated y distance
;
; Modifies:
;	AX, DX
;
DEFPROC	drRotate
	push	bx
	push	cx
	push	si
	push	di
	mov	bx,ss:[PSP_HEAP]
	mov	cx,ss:[bx].GFX_DATA.GFX_ANGLE
	jcxz	dro9			; no rotation
	mov	si,ax			; SI = x
	mov	di,dx			; DI = y
	mov	ax,cx
	mov	bl,90
	div	bl			; AL = angle / 90
	test	ah,ah			; a multiple of 90?
	jnz	dro5			; no
	test	al,1			; 90 or 270?
	jz	dro3			; no (180)
	push	ax
	mov	ax,si
	mov	bl,[drAsp]
	call	goScale
	neg	ax
	xchg	ax,di			; DI = -x * aspect, AX = y
	mov	bx,[drInv]
	call	scaleInv
	xchg	si,ax			; SI = y / aspect
	pop	ax
dro3:	test	al,2			; 180 or 270?
	jz	dro4			; no
	neg	si
	neg	di
dro4:	xchg	ax,si
	mov	dx,di
	jmp	short dro9
;
; x' = x * cos + y * sin / aspect, and y' = y * cos - x * sin * aspect
;
dro5:	mov	ax,cx			; AX = angle
	push	ax
	call	getSin
	xchg	bx,ax			; BX = sin
	pop	ax
	add	ax,90
	call	getSin
	xchg	cx,ax			; CX = cos
	mov	ax,di
	call	mulFix			; AX = y * sin
	push	bx
	mov	bx,[drInv]
	call	scaleInv
	pop	bx
	push	ax
	mov	ax,si
	call	mulFix			; AX = x * sin
	push	bx
	mov	bl,[drAsp]
	call	goScale
	pop	bx
	push	ax
	mov	bx,cx
	mov	ax,di
	call	mulFix			; AX = y * cos
	pop	dx
	sub	ax,dx
	xchg	di,ax			; DI = y'
	mov	ax,si
	call	mulFix			; AX = x * cos
	pop	dx
	add	ax,dx			; AX = x'
	mov	dx,di
dro9:	pop	di
	pop	si
	pop	cx
	pop	bx
	ret
ENDPROC	drRotate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; goScale, scaleInv, mulFix, and getSin (drRotate internal functions)
;
; goScale returns AX * BL / 256, and scaleInv returns AX * BX / 256 (as
; AX * BH + AX * BL / 256), both rounded as MSBASIC does (see GOSCAL in
; msb/ADVGRP.ASM); mulFix returns AX * BX / 16384 (rounded), and getSin
; returns the sine of AX degrees (0-449), * 16384.
;
; Modifies:
;	AX
;
DEFPROC	goScale
	push	dx
	push	ax
	test	ax,ax
	jns	gs1
	neg	ax
gs1:	mov	dl,bl
	mov	dh,0
	mul	dx			; DX:AX = abs(AX) * BL
	add	ax,80h
	adc	dx,0
	mov	al,ah
	mov	ah,dl			; AX = (DX:AX + 128) / 256
	pop	dx
	test	dx,dx			; was the input negative?
	jns	gs2			; no
	neg	ax
gs2:	pop	dx
	ret
ENDPROC	goScale

DEFPROC	scaleInv
	push	dx
	push	ax
	mov	dl,bh
	mov	dh,0
	imul	dx
	xchg	dx,ax			; DX = AX * BH
	pop	ax
	call	goScale
	add	ax,dx
	pop	dx
	ret
ENDPROC	scaleInv

DEFPROC	mulFix
	push	dx
	imul	bx
	add	ax,2000h
	adc	dx,0
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	xchg	ax,dx			; AX = (DX:AX + 8192) / 16384
	pop	dx
	ret
ENDPROC	mulFix

DEFPROC	getSin
	push	bx
	push	dx
	sub	dx,dx			; DX = 0 (positive)
	cmp	ax,360
	jb	gsn1
	sub	ax,360
gsn1:	cmp	ax,180
	jb	gsn2
	sub	ax,180			; sin(a + 180) = -sin(a)
	dec	dx
gsn2:	cmp	ax,90
	jbe	gsn3
	neg	ax
	add	ax,180			; sin(180 - a) = sin(a)
gsn3:	xchg	bx,ax
	add	bx,bx
	mov	ax,cs:SIN_TABLE[bx]
	xor	ax,dx
	sub	ax,dx			; (negate AX if DX is -1)
	pop	dx
	pop	bx
	ret
ENDPROC	getSin

SIN_TABLE	dw	0,286,572,857,1143,1428,1713,1997
		dw	2280,2563,2845,3126,3406,3686,3964,4240
		dw	4516,4790,5063,5334,5604,5872,6138,6402
		dw	6664,6924,7182,7438,7692,7943,8192,8438
		dw	8682,8923,9162,9397,9630,9860,10087,10311
		dw	10531,10749,10963,11174,11381,11585,11786,11982
		dw	12176,12365,12551,12733,12911,13085,13255,13421
		dw	13583,13741,13894,14044,14189,14330,14466,14598
		dw	14726,14849,14968,15082,15191,15296,15396,15491
		dw	15582,15668,15749,15826,15897,15964,16026,16083
		dw	16135,16182,16225,16262,16294,16322,16344,16362
		dw	16374,16382,16384

;
; DRAW_DIRS is in reverse, so that the count that REPNE SCASB leaves in CX is
; the direction's index in DRAW_DX and DRAW_DY (ie, U, D, L, R, E, F, G, H).
;
DRAW_DIRS	db	"HGFERLDU"
DRAW_DX		db	0, 0, -1, 1, 1, 1, -1, -1
DRAW_DY		db	-1, 1, 0, 0, -1, 1, 1, -1

CODE	ENDS

	end
