;
; BASIC-DOS System Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for CHAIN, DEF SEG, MOUSE, PEEK, and POKE (see gensys.asm),
; and for READ and RESTORE (see gendef.asm); PLAY and SOUND are in snd.asm.
;
	DOSFUNC equ 1
	include	cmd.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<callDOS,releaseStr,strIllegal,allocStr,rtError,findVar>
	EXTNEAR	<ctrlc>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doChain
;
; Used by "CHAIN file", which runs the file like any other command.
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
DEFPROC	doChain,FAR
	ARGVAR	pChainStr,dword
	ENTER
	les	di,[pChainStr]
	mov	ax,es
	test	ax,ax			; empty string?
	jz	dcX			; yes
	sub	ax,ax
	push	ax			; no handler
	push	ax			; no keyword ID
	mov	al,es:[di]
	push	ax			; length of command line
	push	es
	inc	di
	push	di			; pointer to command line
	dec	di
	call	releaseStr		; (callDOS copies it before using it)
	push	cs
	call	callDOS
	jc	dcY			; CHAIN failed, so end the program
	LEAVE
	RETURN
dcX:	jmp	strIllegal
dcY:	jmp	ctrlc
ENDPROC	doChain

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; defSeg
;
; Used by "DEF SEG=segment" (and, via defSegBasic, by "DEF SEG", which selects
; BASIC's own data segment; ie, our heap).  We store the segment XOR SS, so
; that the zero-initialized default is the heap.
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
	call	getSeg
	xchg	bx,ax
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
; readData
;
; Used by "READ var[,var]...", which calls us for each var, to get the next
; DATA item as a string.  Rather than collecting DATA items when the program
; is generated, we scan the program's text for them as needed, keeping track
; of where we are in DATA_STATE (see genCode, runCode, and freeCache, which
; reset it).  A quoted item may contain commas and colons (but not quotes),
; and an unquoted item ends at a comma, colon, or the end of the line, with
; leading and trailing whitespace removed.
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated (the item's string value)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	readData,FAR
	RETVAR	retItem,dword
	ENTER
	push	ds
	mov	di,ss:[PSP_HEAP]
	mov	si,ss:[di].DATA_STATE.DATA_OFF
	mov	dx,ss:[di].DATA_STATE.DATA_END
	mov	cx,ss:[di].DATA_STATE.DATA_SEG
	jcxz	rdt0			; start at the first line
	mov	ds,cx
	test	dx,dx			; at the start of a line?
	jz	rdt1			; yes
	cmp	byte ptr ss:[di].DATA_STATE.DATA_ITEM,0
	je	rdt3			; look for another DATA statement
	jmp	rdt6			; get the next DATA item

rdtX:	mov	al,4			; "Out of DATA"
	jmp	rtError

rdt0:	mov	cx,ss:[di].TBLKDEF.BLK_NEXT
	jcxz	rdtX			; there's no program text
	mov	ds,cx
	mov	si,size TBLK
rdt1:	cmp	si,ds:[BLK_FREE]	; any more lines in this block?
	jb	rdt2			; yes
	mov	cx,ds:[BLK_NEXT]	; no, so go to the next block
	jcxz	rdtX			; there are no more
	mov	ds,cx
	mov	si,size TBLK
	jmp	rdt1
rdt2:	lodsw				; skip the line's label #
	lodsb
	mov	ah,0
	mov	dx,si
	add	dx,ax			; DX = end of the line
;
; Check the statement at DS:SI for DATA (or REM, which ends the line).
;
rdt3:	call	dataSkip		; skip whitespace
	mov	cx,dx
	sub	cx,si			; CX = # chars left on the line
	jbe	rdtN			; none
	cmp	byte ptr [si],"'"	; remark?
	je	rdtN			; yes
	mov	ax,[si]
	and	ax,0DFDFh		; (upper-case letters)
	cmp	cx,3
	jb	rdt4
	cmp	ax,'ER'			; "RE"?
	jne	rdt3a
	mov	al,[si+2]
	and	al,0DFh
	cmp	al,'M'			; "REM"?
	je	rdtN			; yes, so skip the line
rdt3a:	cmp	cx,4
	jb	rdt4
	cmp	ax,'AD'			; "DA"?
	jne	rdt4
	mov	ax,[si+2]
	and	ax,0DFDFh
	cmp	ax,'AT'			; "DATA"?
	jne	rdt4
	cmp	cx,4			; anything after it?
	je	rdt3b			; no
	mov	al,[si+4]
	and	al,0DFh
	sub	al,'A'
	cmp	al,26			; another letter (eg, "DATAX")?
	jb	rdt4			; yes
rdt3b:	add	si,4			; DS:SI -> 1st DATA item
	jmp	short rdt6
;
; Skip the statement (ie, up to a colon outside of quotes, or a remark).
;
rdt4:	cmp	si,dx
	jae	rdtN
	lodsb
	cmp	al,'"'
	je	rdt5
	cmp	al,"'"
	je	rdtN
	cmp	al,':'
	je	rdt3
	jmp	rdt4
rdt5:	cmp	si,dx
	jae	rdtN
	lodsb
	cmp	al,'"'
	jne	rdt5
	jmp	rdt4
rdtN:	mov	si,dx			; go to the next line
	jmp	rdt1
;
; Get the DATA item at DS:SI (from CX to BX).
;
rdt6:	call	dataSkip		; skip whitespace
	mov	cx,si			; CX -> start of item
	mov	bx,si			; BX -> end of item
	cmp	si,dx
	jae	rdt9			; the item is empty
	cmp	byte ptr [si],'"'	; quoted item?
	jne	rdt7			; no
	inc	si
	mov	cx,si
rdt6a:	cmp	si,dx
	jae	rdt6b
	lodsb
	cmp	al,'"'
	jne	rdt6a
	dec	si			; SI -> closing quote
rdt6b:	mov	bx,si
	jmp	short rdt9

rdt7:	cmp	si,dx
	jae	rdt8
	mov	al,[si]
	cmp	al,','
	je	rdt8
	cmp	al,':'
	je	rdt8
	inc	si
	jmp	rdt7
rdt8:	mov	bx,si			; remove trailing whitespace
rdt8a:	cmp	bx,cx
	jbe	rdt9
	mov	al,[bx-1]
	cmp	al,' '
	je	rdt8b
	cmp	al,CHR_TAB
	jne	rdt9
rdt8b:	dec	bx
	jmp	rdt8a
;
; Find the delimiter that follows the item: a comma means there are more
; items, whereas a colon (or the end of the line) ends the DATA statement.
;
rdt9:	mov	ah,1			; AH = 1 (more items)
rdt9a:	cmp	si,dx
	jae	rdt9b
	lodsb
	cmp	al,','
	je	rdt9c
	cmp	al,':'
	jne	rdt9a
rdt9b:	mov	ah,0			; AH = 0 (no more items)
rdt9c:	mov	di,ss:[PSP_HEAP]
	mov	ss:[di].DATA_STATE.DATA_OFF,si
	mov	ss:[di].DATA_STATE.DATA_SEG,ds
	mov	ss:[di].DATA_STATE.DATA_END,dx
	mov	byte ptr ss:[di].DATA_STATE.DATA_ITEM,ah
	mov	si,cx
	mov	cx,bx
	sub	cx,si			; CX = length of item
	sub	ax,ax
	cwd				; DX:AX = empty string
	jcxz	rdt10
	call	allocStr		; ES:DI -> new string
	mov	ax,di
	mov	dx,es			; DX:AX = string value
	inc	di
	rep	movsb			; copy the item to it
rdt10:	mov	[retItem].OFF,ax
	mov	[retItem].SEG,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	readData

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dataSkip
;
; Inputs:
;	DS:SI -> text
;	DX = end of text
;
; Outputs:
;	DS:SI -> first character that isn't a space or tab (or DX)
;
; Modifies:
;	AL, SI
;
DEFPROC	dataSkip
dsk1:	cmp	si,dx
	jae	dsk9
	mov	al,[si]
	cmp	al,' '
	je	dsk2
	cmp	al,CHR_TAB
	jne	dsk9
dsk2:	inc	si
	jmp	dsk1
dsk9:	ret
ENDPROC	dataSkip

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; restoreData
;
; Used by "RESTORE [line]": with no line # (zero), the next READ starts over
; with the first DATA item; otherwise, it starts with the first DATA item at
; or after the specified line (which must exist).
;
; Inputs:
;	32-bit line # (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	restoreData,FAR
	ARGVAR	dataLine,dword
	ENTER
	push	ds
	mov	di,ss:[PSP_HEAP]
	sub	ax,ax
	mov	ss:[di].DATA_STATE.DATA_SEG,ax	; start over
	mov	dx,[dataLine].LOW
	test	dx,dx			; line # specified?
	jz	rst9			; no
	mov	cx,ss:[di].TBLKDEF.BLK_NEXT
rst1:	jcxz	rst8			; no more blocks
	mov	ds,cx
	mov	si,size TBLK
rst2:	cmp	si,ds:[BLK_FREE]	; any more lines in this block?
	jae	rst3			; no
	cmp	[si],dx			; is this the line?
	je	rst4			; yes
	mov	al,[si+2]
	mov	ah,0
	add	si,ax
	add	si,3			; skip the label #, length, and text
	jmp	rst2
rst3:	mov	cx,ds:[BLK_NEXT]
	jmp	rst1
rst4:	mov	ss:[di].DATA_STATE.DATA_OFF,si
	mov	ss:[di].DATA_STATE.DATA_SEG,ds
	mov	word ptr ss:[di].DATA_STATE.DATA_END,0
rst9:	pop	ds
	LEAVE
	RETURN
rst8:	mov	al,8			; "Undefined line number"
	jmp	rtError
ENDPROC	restoreData

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strToLong
;
; Converts a string value to a long, for READ when there's no FPU$ driver
; (and therefore no doubles, which VAL requires).
;
; Inputs:
;	32-bit return value
;	string value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strToLong,FAR
	RETVAR	retLong,dword
	ARGVAR	pLongStr,dword
	ENTER
	push	ds
	sub	ax,ax
	cwd				; DX:AX = 0
	lds	si,[pLongStr]
	test	si,si			; empty string?
	jz	stl9			; yes
	lodsb
	mov	cl,al
	mov	ch,0			; DS:SI -> string, CX = length
	mov	bl,10
	DOSUTIL	ATOI32			; DX:AX = value
	les	di,[pLongStr]
	call	releaseStr
stl9:	mov	[retLong].LOW,ax
	mov	[retLong].HIW,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	strToLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getStrVar
;
; Used for "=variable;" in PLAY and DRAW strings (eg, PLAY "O=J;"), which
; uses the value of the named numeric variable.  The name ends at a semicolon
; (or the end of the string), and the variable's type comes from its suffix,
; if any (eg, "J%"), or else from the default type of its first letter (eg,
; DEFINT I-N).  A double is rounded to a long, and as in MSBASIC, a variable
; that doesn't exist yet has a value of zero.
;
; Inputs:
;	DS:SI -> name (CX = # characters left in the string)
;
; Outputs:
;	AX = value (carry clear), DS:SI and CX advanced past the name and ';'
;	(an "Illegal function call" error occurs if the name is invalid)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	getStrVar
	push	bx
	push	es
	push	bp
	mov	bp,sp
	sub	sp,VAR_NAMELEN+1	; (room for the name)
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> name buffer
	sub	bx,bx			; BX = length of name
gsv1:	jcxz	gsv2
	lodsb
	dec	cx
	cmp	al,';'			; end of name?
	je	gsv2			; yes
	cmp	al,'a'
	jb	gsv1a
	cmp	al,'z'
	ja	gsv1a
	sub	al,20h			; (upper-case it)
gsv1a:	cmp	bl,VAR_NAMELEN		; room for another character?
	jae	gsvX			; no
	stosb
	inc	bx
	jmp	gsv1
gsv2:	test	bx,bx			; any name?
	jz	gsvX			; no
	mov	ah,VAR_LONG
	mov	al,es:[di-1]		; AL = last character of name
	cmp	al,'%'
	je	gsv3
	mov	ah,VAR_DOUBLE
	cmp	al,'!'
	je	gsv3
	cmp	al,'#'
	je	gsv3
	mov	al,es:[bp-(VAR_NAMELEN+1)]
	sub	al,'A'			; AL = index of 1st letter
	cmp	al,26
	jae	gsvX
	cbw
	mov	di,ss:[PSP_HEAP]
	add	di,ax
	mov	ah,ss:[di].DEFVARS	; AH = default type for that letter
	test	ah,ah			; set?
	jnz	gsv4			; yes
	mov	ah,VAR_LONG		; no, so it's VAR_LONG without an FPU$
	cmp	word ptr cs:[FPU_TABLE].SEG,0
	je	gsv4			; driver, and VAR_DOUBLE otherwise
	mov	ah,VAR_DOUBLE
	jmp	short gsv4
gsvX:	jmp	strIllegal
gsv3:	dec	bx			; (the suffix isn't part of the name)
gsv4:	push	cx
	push	si
	push	ds
	push	ss
	pop	ds			; (findVar requires DS = heap)
	lea	si,[bp-(VAR_NAMELEN+1)]
	mov	cx,bx			; DS:SI -> name, CX = length
	call	findVar			; DX:SI -> var data
	jnc	gsv4a
	sub	ax,ax			; no such var, so its value is zero
	jmp	short gsv8
gsv4a:	mov	es,dx
	cmp	ah,VAR_LONG
	jne	gsv5
	mov	ax,es:[si]		; AX = value
	jmp	short gsv8
gsv5:	cmp	ah,VAR_DOUBLE
	jne	gsvX
	lds	di,cs:[FPU_TABLE]	; DS:DI -> FPUTBL
	mov	ax,ds
	test	ax,ax
	jz	gsvX
	push	ax
	push	[di].FPU_CVT1DL		; push the conversion function address
	mov	di,sp
	push	es
	push	si			; push a pointer to the double
	call	dword ptr ss:[di]	; and replace it with a long
	pop	ax			; AX = value
	add	sp,6			; (discard the high word, address)
gsv8:	pop	ds
	pop	si
	pop	cx
	mov	sp,bp
	pop	bp
	pop	es
	pop	bx
	clc
	ret
ENDPROC	getStrVar

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
; mouseReset
;
; Resets the mouse, if any (which hides the pointer), and clears MOUSE_STATE.
; restoreMode also calls this when a BAS program ends.
;
; Inputs:
;	None
;
; Outputs:
;	AX = -1 if there's a mouse
;	BX -> CMDHEAP
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	mouseReset
	sub	ax,ax
	call	mouseCall
	mov	bx,ss:[PSP_HEAP]
	mov	byte ptr ss:[bx].GFX_DATA.MOUSE_STATE,0
	ret
ENDPROC	mouseReset

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseCall
;
; Issues an INT 33h function, if the MOUSE$ driver (or any other mouse
; driver) is installed.
;
; Inputs:
;	AX = function (and BX, CX, DX as required)
;
; Outputs:
;	Same as the function; if there's no mouse, carry is set and AX, BX,
;	CX, and DX are zero
;
DEFPROC	mouseCall
	push	ds
	push	bx
	sub	bx,bx
	mov	ds,bx
	cmp	ds:[INT_MOUSE * 4].SEG,bx
	pop	bx
	pop	ds
	je	mc8
	int	INT_MOUSE
	clc
	ret
mc8:	sub	ax,ax
	cwd
	mov	bx,ax
	mov	cx,ax
	stc
	ret
ENDPROC	mouseCall

CODE	ENDS

	end
