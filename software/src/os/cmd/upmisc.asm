;
; BASIC-DOS Runtime for Less Common BASIC Statements and Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The functions behind the statements in genmisc.asm, and CSRLIN, PEEK, POS,
; RND, SCREEN, SGN, and TAB.  This module is linked after CONST.OBJ, so it's
; outside COMMAND's core (see CMD.LRF): genFuncExpr reports "Not enough memory"
; for these functions if only the core was loaded.
;
	DOSFUNC equ 1
	GFXDEFS equ 1
	include	cmd.inc
	include	str.inc
	include	8086.inc

CODE	SEGMENT

	EXTNEAR	<getArgs,getMode,ioctlCon,mouseCall,strIllegal,allocStr>
	EXTNEAR	<rtError>
	EXTWORD	<CODE_DS>

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setScreen
;
; Used by "SCREEN [mode][,burst]" (any additional arguments are ignored).
;
; Mode is 0 for text, 1 for 320x200 graphics, or 2 for 640x200 graphics, and
; burst enables color in mode 0 if it's non-zero, and disables it in mode 1.
; SCREEN 0 keeps the current width (40 columns after SCREEN 1, 80 after
; SCREEN 2), and omitted values keep their current settings.  Nothing happens
; if STDOUT doesn't support video modes, or if the video mode is unchanged.
;
; Every combination of these settings is an index into MODE_TBL:
;
;	index = mode * 4 + 2 (if color is disabled) + 1 (if 80 columns)
;
; and MODE_INFO maps video modes 0-7 back to their indexes.
;
; Inputs:
;	N numeric expressions pushed on stack (only 1st 2 are processed)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	setScreen,FAR
	call	getArgs			; AX = mode, DX = burst
	push	dx
	push	ax
	call	getMode			; BL = index, BH = video mode
	pop	ax
	pop	dx
	jc	ss9			; not supported
	test	ax,ax			; mode omitted?
	js	ss2			; yes
	cmp	al,2
	ja	ss8
	and	bl,3			; keep the color and width bits
	shl	al,1
	shl	al,1
	or	bl,al
	cmp	al,4			; SCREEN 1?
	jne	ss2			; no
	and	bl,NOT 1		; yes, so it's 40 columns
ss2:	test	dx,dx			; burst omitted?
	js	ss4			; yes
	cmp	dx,1			; carry set if burst is zero
	sbb	al,al			; AL = -1 if burst is zero
	test	bl,0Ch			; graphics mode?
	jz	ss3			; no
	not	al			; yes, so burst has the opposite effect
ss3:	and	al,2			; AL = 2 if color is disabled
	and	bl,NOT 2
	or	bl,al

ss4:	mov	cl,bh			; CL = current video mode
	mov	bh,0
	mov	al,cs:MODE_TBL[bx]	; AL = new video mode
	cmp	al,cl			; any change?
	je	ss9			; no
	xchg	cx,ax			; CL = new video mode
	mov	bx,ss:[PSP_HEAP]
	mov	word ptr ss:[bx].GFX_DATA.GFX_FLAGS,0	; (and GFX_MODE)
;
; If a program whose mode was saved selects a graphics mode (4-6), mark the
; saved mode, so that restoreMode restores it when the program ends.
;
	mov	al,cl
	sub	al,4
	cmp	al,3			; is it a graphics mode?
	jae	ss5			; no
	cmp	byte ptr ss:[bx].GFX_DATA.GFX_SAVED,0	; is a mode saved?
	je	ss5			; no
	or	byte ptr ss:[bx].GFX_DATA.GFX_SAVED,80h
ss5:	push	cx
	mov	ax,2
	call	mouseCall		; hide the mouse pointer, if any
	pop	cx
	mov	al,IOCTL_SETMODE
	call	ioctlCon
	pushf
	mov	ax,1
	call	mouseCall		; and show it again (in the new mode)
	popf
	jc	ss8			; the adapter doesn't support the mode
ss9:	ret
ss8:	jmp	strIllegal
ENDPROC	setScreen

MODE_TBL	db	1,3,0,2,4,6,5,6,6,6,6,6

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setWidth
;
; Used by "WIDTH 40" and "WIDTH 80".  Like MSBASIC, WIDTH in a graphics mode
; selects SCREEN 1 (40) or SCREEN 2 (80); see setScreen for details.
;
; Inputs:
;	N numeric expressions pushed on stack (only the 1st is processed)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	setWidth,FAR
	call	getArgs			; AX = width
	push	ax
	call	getMode			; BL = index, BH = video mode
	pop	ax
	jc	ss9			; not supported
	and	bl,NOT 1		; presume 40 columns
	cmp	ax,40
	je	sw1
	cmp	ax,80
	jne	ss8
	inc	bx			; 80 columns
sw1:	test	bl,0Ch			; graphics mode?
	jz	ss4			; no
	and	bl,3			; yes, keep the color and width bits
	or	bl,4			; for SCREEN 1 (MODE_TBL maps 80 to 2)
	jmp	ss4
ENDPROC	setWidth

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getCsrlin (CSRLIN) and getPos (POS)
;
; Return the cursor's row (CSRLIN) or column (POS), starting at 1 (or 1 if
; STDOUT isn't a console).  The parameter of POS is ignored.
;
; Inputs:
;	32-bit return value
;	32-bit value (POS only; popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	getPos,FAR
	RETVAR	retPos,dword
	ARGVAR	lPos,dword
	ENTER
	call	getCol			; AX = column
	mov	[retPos].LOW,ax
	mov	[retPos].HIW,0
	LEAVE
	RETURN
ENDPROC	getPos

DEFPROC	getCsrlin,FAR
	RETVAR	retCsrlin,dword
	ENTER
	call	getCol
	mov	al,dh			; AL = row (zero-based)
	inc	ax
	mov	[retCsrlin].LOW,ax
	mov	[retCsrlin].HIW,0
	LEAVE
	RETURN
ENDPROC	getCsrlin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getScreen (SCREEN)
;
; Used by "SCREEN(row,col[,z])" to return the character code at row and col
; (starting at 1), or as in MSBASIC, its attributes if z is non-zero.  A
; position outside the console (or a STDOUT that isn't a console) is an
; illegal function call.
;
; Inputs:
;	32-bit return value
;	3 32-bit values (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	getScreen,FAR
	RETVAR	retScreen,dword
	ARGVAR	scrRow,dword
	ARGVAR	scrCol,dword
	ARGVAR	scrAttr,dword
	ENTER
	mov	cx,[scrCol].LOW
	mov	dx,[scrRow].LOW
	mov	ax,[scrCol].HIW
	or	ax,[scrRow].HIW
	or	al,ch
	or	al,dh
	or	al,ah			; are row and col both 0-255?
	jnz	gsc8			; no
	mov	ch,dl			; CL = col, CH = row
	sub	cx,0101h		; make them zero-based (0 is illegal)
	mov	al,IOCTL_GETCHAR
	call	ioctlCon		; DL = character, DH = attributes
	jc	gsc8
	mov	ax,[scrAttr].LOW
	or	ax,[scrAttr].HIW	; attributes requested?
	jz	gsc1			; no
	mov	dl,dh
gsc1:	mov	dh,0
	mov	[retScreen].LOW,dx
	mov	[retScreen].HIW,0
	LEAVE
	RETURN
gsc8:	jmp	strIllegal
ENDPROC	getScreen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getCol
;
; Inputs:
;	None
;
; Outputs:
;	AX = column (starting at 1), DH = row (zero-based)
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	getCol
	mov	al,IOCTL_GETPOS
	call	ioctlCon		; DL = col, DH = row (zero-based)
	jnc	gcl1
	sub	dx,dx			; (not supported)
gcl1:	mov	al,dl
	mov	ah,0
	inc	ax
	ret
ENDPROC	getCol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strTab (TAB)
;
; Used by "PRINT TAB(n)" to move the cursor to column n, by returning enough
; spaces to get there; if the cursor is already past column n, the string
; begins with CRLF, so the spaces start on the next line (as in MSBASIC).
;
; Inputs:
;	32-bit return value
;	32-bit column (popped)
;
; Outputs:
;	32-bit return value updated (string value)
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	strTab,FAR
	RETVAR	retTab,dword
	ARGVAR	lTab,dword
	ENTER
	call	getCol			; AX = current column
	mov	cx,[lTab].LOW
	cmp	[lTab].HIW,0
	jne	st8
	cmp	cx,254			; (room for CRLF and 253 spaces)
	ja	st8
	sub	bx,bx			; BX = 0 (no CRLF)
	jcxz	st1
	dec	cx			; CX = # spaces to column n
st1:	inc	cx
	sub	cx,ax			; CX = # spaces from current column
	jae	st2			; we're not past column n
	add	cx,ax			; we are, so start a new line
	dec	cx			; CX = # spaces from column 1
	mov	bx,CHR_RETURN OR (CHR_LINEFEED SHL 8)
	inc	cx
	inc	cx			; (and room for CRLF)
st2:	sub	ax,ax
	cwd				; DX:AX = empty string
	jcxz	st9
	call	allocStr		; ES:DI -> new string
	push	di
	inc	di
	test	bx,bx			; CRLF first?
	jz	st3			; no
	xchg	ax,bx
	stosw
	dec	cx
	dec	cx
st3:	mov	al,' '
	rep	stosb
	pop	ax
	mov	dx,es			; DX:AX = string value
st9:	mov	[retTab].OFF,ax
	mov	[retTab].SEG,dx
	LEAVE
	RETURN
st8:	jmp	strIllegal
ENDPROC	strTab

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getRnd (RND)
;
; Returns a pseudo-random double from 0 up to (but not including) 1; the
; arg is processed like getRndLong's.  The double is the next 31-bit value
; from nextRnd divided by 2^31, which we build directly (no FPU$ required).
;
; Inputs:
;	pointer to double result (in a slot)
;	1 32-bit arg on stack (popped)
;
; Outputs:
;	double result updated
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	getRnd,FAR
	RETVAR	pRnd,dword
	ARGVAR	seedRnd,dword
	ENTER
	mov	dx,[seedRnd].HIW
	mov	ax,[seedRnd].LOW
	call	nextRnd			; CX:BX = 0 to MAXINT
	sub	dx,dx			; DX = high word of the double
	mov	ax,cx
	or	ax,bx			; zero?
	jz	gr9			; yes, so the double is zero, too
	mov	dx,3FEh			; exponent for values from .5 to 1
gr1:	test	ch,40h			; is bit 30 set yet?
	jnz	gr2			; yes
	shl	bx,1
	rcl	cx,1
	dec	dx			; no, so shift and adjust the exponent
	jmp	gr1
;
; Drop bits 31 and 30 (the latter is implied by the exponent), and then
; shift the remaining 30 bits, along with the exponent in DX, by 4 more bits,
; so that the top 20 bits are in the low bits of DX and all of CX.
;
gr2:	shl	bx,1
	rcl	cx,1
	shl	bx,1
	rcl	cx,1
	mov	ax,4
gr3:	shl	bx,1
	rcl	cx,1
	rcl	dx,1
	dec	ax
	jnz	gr3
gr9:	les	di,[pRnd]
	sub	ax,ax
	stosw
	xchg	ax,bx
	stosw
	xchg	ax,cx
	stosw
	xchg	ax,dx
	stosw
	LEAVE
	RETURN
ENDPROC	getRnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getRndLong (RND%)
;
; If the arg is negative, it's used to re-seed the generator; if it's zero,
; we return the last pseudo-random number; any other value (ie, 1 to MAXINT)
; is ignored and we simply produce the next pseudo-random number.
;
; Inputs:
;	32-bit return value
;	1 32-bit arg on stack (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	getRndLong,FAR
	RETVAR	retRndLong,dword
	ARGVAR	seed,dword
	ENTER
	mov	dx,[seed].HIW
	mov	ax,[seed].LOW
	call	nextRnd
	mov	[retRndLong].HIW,cx
	mov	[retRndLong].LOW,bx
	LEAVE
	RETURN
ENDPROC	getRndLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; nextRnd
;
; Uses Marsaglia's 32-bit "xorshift" generator (x ^= x << 13; x ^= x >> 17;
; x ^= x << 5), whose bits are all equally random, and which needs no MULs.
; The state can't be zero, so a zero state (eg, initially) is replaced with
; a fixed seed; every program gets the same sequence of numbers (as in
; MSBASIC) unless it re-seeds the generator with a negative arg.
;
; Inputs:
;	DX:AX = arg (see getRndLong)
;
; Outputs:
;	CX:BX = pseudo-random number (0 to MAXINT)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	nextRnd
	mov	cx,ax
	or	cx,dx
	mov	bx,ss:[PSP_HEAP]
	mov	cx,ss:[bx].RND_SEED.HIW
	mov	bx,ss:[bx].RND_SEED.LOW
	jz	rnd9			; zero arg: return the last number
	test	dx,dx			; (its high word has the arg's sign)
	jns	rnd1
	mov	bx,ax			; negative arg: use it as the seed
	mov	cx,dx
rnd1:	mov	ax,cx
	or	ax,bx			; is the state zero?
	jnz	rnd2			; no
	mov	cx,9268h		; yes, so use a fixed seed
	mov	bx,0E8A2h
rnd2:	mov	dx,bx
	sub	ax,ax			; DX:AX = state << 16
	shr	dx,1
	rcr	ax,1
	shr	dx,1
	rcr	ax,1
	shr	dx,1
	rcr	ax,1			; DX:AX = state << 13
	xor	cx,dx
	xor	bx,ax
	mov	ax,cx
	shr	ax,1			; AX = state >> 17
	xor	bx,ax
	mov	dx,cx
	mov	ax,bx
	REPT	5
	shl	ax,1
	rcl	dx,1
	ENDM				; DX:AX = state << 5
	xor	cx,dx
	xor	bx,ax
	mov	ax,bx
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].RND_SEED.HIW,cx
	mov	ss:[bx].RND_SEED.LOW,ax
	xchg	bx,ax
rnd9:	and	cx,7FFFh		; never return a negative result
	ret
ENDPROC	nextRnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; randomize
;
; Used by "RANDOMIZE [seed]" to re-seed the random number generator (see
; nextRnd), so that the same seed always produces the same sequence.  Unlike
; MSBASIC, which prompts for a seed if there isn't one, we use the BIOS tick
; count (much like "RANDOMIZE TIMER").
;
; Inputs:
;	32-bit seed (popped)
;	16-bit flag (popped): non-zero to use the BIOS tick count instead
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	randomize,FAR
	ARGVAR	lSeed,dword
	ARGVAR	wSeedTicks,word
	ENTER
	mov	ax,[lSeed].LOW
	mov	dx,[lSeed].HIW
	mov	bx,[wSeedTicks]
	test	bl,bl			; use the BIOS tick count?
	jz	rz1			; no
	DOSUTIL	GETTIME,1		; DX:AX = BIOS tick count
rz1:	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].RND_SEED.LOW,ax
	mov	ss:[bx].RND_SEED.HIW,dx
	LEAVE
	RETURN
ENDPROC	randomize

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getSgn (SGN)
;
; Returns -1 if x is negative, 0 if x is zero, or 1 if x is positive.
;
; Inputs:
;	32-bit return value
;	far pointer to double (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, DX, SI, ES
;
DEFPROC	getSgn,FAR
	RETVAR	retSgn,dword
	ARGVAR	pSgn,dword
	ENTER
	les	si,[pSgn]
	mov	dx,es:[si+6]
	and	dh,7Fh			; clear DX's sign too, for signed zero
	mov	ax,dx
	or	ax,es:[si+4]
	or	ax,es:[si+2]
	or	ax,es:[si]		; zero?
	jz	sg9			; yes (DX:AX = 0)
	mov	ax,1
	cwd				; DX:AX = 1
	test	es:[si+6],8000h		; negative?
	jz	sg9			; no
	neg	ax
	cwd				; DX:AX = -1
sg9:	mov	[retSgn].LOW,ax
	mov	[retSgn].HIW,dx
	LEAVE
	RETURN
ENDPROC	getSgn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; defSeg
;
; Used by "DEF SEG=segment" (and, via defSegBasic, by "DEF SEG", which selects
; BASIC's own data segment; ie, our heap).  We store the segment XOR SS, so
; that the zero-initialized default is the heap.  A segment other than the
; heap comes from DOS_UTL_MAPSEG, which in protected mode is a selector for
; it, and except for video memory, a read-only one (see pokeByte).
;
; Inputs:
;	1 32-bit arg on stack (-32768 to 65535)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	defSegBasic,FAR
	mov	ax,ss
	jmp	short dfs1
ENDPROC	defSegBasic

DEFPROC	defSeg,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	pop	ax
	pop	bx			; BX:AX = segment
	push	dx
	push	cx
	call	chkWord
	xchg	bx,ax			; BX = segment
	DOSUTIL	MAPSEG,0		; AX = its selector (or segment)
	jnc	dfs1
	mov	al,7			; "Out of memory"
	jmp	rtError
dfs1:	mov	bx,ss
	xor	ax,bx
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].PEEK_SEG,ax
	ret
ENDPROC	defSeg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekByte (PEEK)
;
; Inputs:
;	32-bit return value
;	32-bit offset (popped)
;
; Outputs:
;	32-bit return value updated with the byte at DEF SEG:offset
;
; Modifies:
;	AX, BX, DX, ES
;
DEFPROC	peekByte,FAR
	RETVAR	retPeek,dword
	ARGVAR	peekOff,dword
	ENTER
	mov	ax,[peekOff].LOW
	mov	bx,[peekOff].HIW
	call	chkWord
	call	getSeg
	xchg	bx,ax
	mov	al,es:[bx]
	mov	ah,0
	mov	[retPeek].LOW,ax
	mov	[retPeek].HIW,0
	LEAVE
	RETURN
ENDPROC	peekByte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pokeByte
;
; Used by "POKE offset,value" to store value (0-255) at DEF SEG:offset.
;
; Inputs:
;	2 32-bit args on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	pokeByte,FAR
	pop	si
	pop	di			; DI:SI = return address
	pop	cx
	pop	dx			; DX:CX = value
	pop	ax
	pop	bx			; BX:AX = offset
	push	di
	push	si
	call	chkWord
	test	dx,dx
	jnz	cw8
	test	ch,ch
	jnz	cw8
	call	getSeg			; ES = DX = DEF SEG segment
;
; In protected mode, a DEF SEG segment other than the heap may be read-only
; (see defSeg), so we check it with VERW, which can run only in protected
; mode, which is when CS (a code alias) isn't the same as CODE_DS.
;
	mov	bx,ss
	cmp	dx,bx			; the heap?
	je	pb1			; yes
	mov	bx,cs
	cmp	bx,cs:[CODE_DS]		; real mode?
	je	pb1			; yes
	.286p
	verw	dx			; is the segment writable?
	.8086
	jnz	cw8			; no ("Illegal function call")
pb1:	xchg	bx,ax
	mov	es:[bx],cl
	ret
ENDPROC	pokeByte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkWord
;
; Inputs:
;	BX:AX = 32-bit value
;
; Outputs:
;	None (an "Illegal function call" error occurs if BX:AX isn't
;	-32768 to 65535, the range of segments and offsets in MSBASIC)
;
; Modifies:
;	BX
;
DEFPROC	chkWord
	test	bx,bx
	jz	cw9
	inc	bx
	jnz	cw8
	test	ax,ax
	js	cw9
cw8:	jmp	strIllegal
cw9:	ret
ENDPROC	chkWord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getSeg
;
; Inputs:
;	None
;
; Outputs:
;	ES = DEF SEG segment
;
; Modifies:
;	BX, DX, ES
;
DEFPROC	getSeg
	mov	dx,ss
	mov	bx,ss:[PSP_HEAP]
	xor	dx,ss:[bx].PEEK_SEG
	mov	es,dx
	ret
ENDPROC	getSeg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swapVars
;
; Used by "SWAP var1,var2", which exchanges the values of two variables (or
; array elements) of the same type.  A string in the pool records its owner,
; so after swapping strings, we update their owners.
;
; Inputs:
;	far pointer to 1st variable (popped)
;	far pointer to 2nd variable (popped)
;	16-bit type (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	swapVars,FAR
	ARGVAR	pSwapA,dword
	ARGVAR	pSwapB,dword
	ARGVAR	wSwapType,word
	ENTER
	push	ds
	lds	si,[pSwapA]
	les	di,[pSwapB]
	mov	ax,[wSwapType]
	mov	cx,2			; CX = # words for a long or string
	cmp	al,VAR_DOUBLE
	jne	swv1
	add	cx,cx			; or 4 for a double
swv1:	mov	ax,[si]
	xchg	ax,es:[di]
	mov	[si],ax
	inc	si
	inc	si
	inc	di
	inc	di
	loop	swv1
	mov	ax,[wSwapType]
	cmp	al,VAR_STR		; strings?
	jne	swv9			; no
	lds	si,[pSwapA]
	call	swapOwner
	lds	si,[pSwapB]
	call	swapOwner
swv9:	pop	ds
	LEAVE
	RETURN
ENDPROC	swapVars

;
; swapOwner: makes the variable at DS:SI the owner of its pool string, if any.
;
DEFPROC	swapOwner
	les	di,[si]			; ES:DI = string value
	test	di,di			; empty?
	jz	so9			; yes
	cmp	es:[BLK_SIG],SIG_SBLK	; in the pool?
	jne	so9			; no
	cmp	byte ptr es:[di-STR_HDR],STR_OWNED
	jne	so9
	mov	es:[di-STR_HDR+1],si
	mov	es:[di-STR_HDR+3],ds
so9:	ret
ENDPROC	swapOwner

CODE	ENDS

	end
