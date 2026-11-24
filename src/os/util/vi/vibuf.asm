;
; BASIC-DOS Visual Editor: Buffer and Screen Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
;
; The text (gap buffer) access and modification functions, and the screen
; functions.
;
	DOSFUNC equ 1
	include	vi.inc

CODE	SEGMENT word public 'CODE'

	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:CODE	; ES = text segment

	EXTNEAR	<setMsg>
	EXTBYTE	<fCtrlC,MEM_ERR>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Text access functions
;
; Unless otherwise noted, they take a logical offset in BX and return
; another in BX, and modify only AX.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getc
;
; Outputs:
;	If carry clear, AL = character at BX; carry set if BX >= V_LEN
;
; Modifies:
;	AL
;
DEFPROC	getc
	cmp	bx,[bp].V_LEN
	cmc
	jc	gc9			; past the end
	push	bx
	cmp	bx,[bp].V_GS		; before the gap?
	jb	gc1			; yes
	add	bx,[bp].V_GL
gc1:	mov	al,es:[bx]
	pop	bx
	clc
gc9:	ret
ENDPROC	getc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; incB, decB
;
; Outputs:
;	BX incremented (or decremented), unless that would move it past the
;	end (or the start) of the text, in which case carry is set
;
DEFPROC	incB
	inc	bx
	cmp	bx,[bp].V_LEN
	cmc				; carry set if BX >= V_LEN
	jnc	ib9
	dec	bx
ib9:	ret
ENDPROC	incB

DEFPROC	decB
	test	bx,bx
	stc
	jz	dcb9
	dec	bx
	clc
dcb9:	ret
ENDPROC	decB

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; lineStart
;
; Outputs:
;	BX = start of the line containing BX (carry clear)
;
DEFPROC	lineStart
ls1:	test	bx,bx
	jz	ls9
	dec	bx
	call	getc
	cmp	al,CHR_LINEFEED
	jne	ls1
	inc	bx
ls9:	ret
ENDPROC	lineStart

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; lineEnd
;
; Outputs:
;	BX = offset of the LF ending the line (carry set if past the end)
;
DEFPROC	lineEnd
le1:	call	getc
	jc	le9
	cmp	al,CHR_LINEFEED
	je	le9			; (carry clear)
	inc	bx
	jmp	le1
le9:	ret
ENDPROC	lineEnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; nextLine
;
; Outputs:
;	BX = start of the next line; if there's no next line, carry is set
;	and BX = V_LEN
;
DEFPROC	nextLine
	call	lineEnd
	jc	nl9
	inc	bx
	cmp	bx,[bp].V_LEN
	cmc				; carry set if BX >= V_LEN
nl9:	ret
ENDPROC	nextLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; prevLine
;
; Outputs:
;	BX = start of the previous line; if there's no previous line, carry
;	is set and BX = 0
;
DEFPROC	prevLine
	call	lineStart
	test	bx,bx
	stc
	jz	pl9
	dec	bx
	call	lineStart
pl9:	ret
ENDPROC	prevLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; downN, upN
;
; Inputs:
;	BX = start of a line
;	CX = # lines to move down (or up)
;
; Outputs:
;	BX = start of the line, stopping at the last (or first) line
;	AX = # lines moved (downN only)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	downN
	sub	ax,ax
	jcxz	dn9
dn1:	mov	dx,bx
	push	ax
	call	nextLine
	pop	ax
	jc	dn8
	inc	ax
	loop	dn1
	ret
dn8:	mov	bx,dx
dn9:	ret
ENDPROC	downN

DEFPROC	upN
	jcxz	un9
un1:	call	prevLine
	loop	un1
un9:	ret
ENDPROC	upN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; firstNonBlank
;
; Outputs:
;	BX = first non-blank character of the line containing BX
;
DEFPROC	firstNonBlank
	call	lineStart
fn1:	call	getc
	cmp	al,CHR_SPACE
	je	fn2
	cmp	al,CHR_TAB
	jne	fn9
fn2:	inc	bx
	jmp	fn1
fn9:	ret
ENDPROC	firstNonBlank

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; advCol
;
; Inputs:
;	AL = character
;	DX = display column
;
; Outputs:
;	DX = display column after the character (TABs stop every 8 columns,
;	and control characters are displayed as "^" plus a letter)
;
DEFPROC	advCol
	cmp	al,CHR_TAB
	jne	ac1
	or	dx,7
	inc	dx
	ret
ac1:	inc	dx
	cmp	al,CHR_SPACE		; control character?
	jb	ac2			; yes
	cmp	al,CHR_DEL		; DEL (displayed as "^?")?
	jne	ac9			; no
ac2:	inc	dx
ac9:	ret
ENDPROC	advCol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dispCol
;
; Outputs:
;	AX = display column of BX (BX unchanged)
;
; Modifies:
;	AX, CX
;
DEFPROC	dispCol
	push	bx
	push	dx
	mov	cx,bx
	call	lineStart
	sub	dx,dx
dc1:	cmp	bx,cx
	jae	dc9
	call	getc
	call	advCol
	inc	bx
	jmp	dc1
dc9:	xchg	ax,dx
	pop	dx
	pop	bx
	ret
ENDPROC	dispCol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; colToOff
;
; Inputs:
;	BX = start of a line
;	AX = display column
;
; Outputs:
;	BX = offset of the character displayed at that column (or the LF,
;	if the line is shorter)
;
; Modifies:
;	AX
;
DEFPROC	colToOff
	push	cx
	push	dx
	xchg	cx,ax			; CX = column
	sub	dx,dx
co1:	call	getc
	jc	co9
	cmp	al,CHR_LINEFEED
	je	co9
	call	advCol			; DX = column after this character
	cmp	cx,dx			; does the character span CX?
	jb	co9			; yes
	inc	bx
	jmp	co1
co9:	pop	dx
	pop	cx
	ret
ENDPROC	colToOff

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; countLines
;
; Outputs:
;	AX = # LFs before BX (BX unchanged)
;
; Modifies:
;	AX
;
DEFPROC	countLines
	push	cx
	push	dx
	push	di
	sub	dx,dx
	mov	cx,bx
	cmp	cx,[bp].V_GS
	jbe	cn1
	mov	cx,[bp].V_GS
cn1:	sub	di,di
	call	scanLF
	mov	cx,bx
	sub	cx,[bp].V_GS
	jbe	cn2
	mov	di,[bp].V_GS
	add	di,[bp].V_GL
	call	scanLF
cn2:	xchg	ax,dx
	pop	di
	pop	dx
	pop	cx
	ret
scanLF:	mov	al,CHR_LINEFEED
sl1:	jcxz	sl9
	repne	scasb
	jne	sl9
	inc	dx
	jmp	sl1
sl9:	ret
ENDPROC	countLines

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; gotoLine
;
; Inputs:
;	CX = line # (1-based)
;
; Outputs:
;	BX = first non-blank character of the line (or the last line)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	gotoLine
	sub	bx,bx
	dec	cx
	call	downN
	jmp	firstNonBlank
ENDPROC	gotoLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clampCur
;
; In command mode, the cursor must be on a character, not the LF at the end
; of a (non-empty) line.
;
; Modifies:
;	AX, BX
;
DEFPROC	clampCur
	mov	bx,[bp].V_CUR
	call	getc
	jnc	cc1
	mov	bx,[bp].V_LEN		; past the end, so use the last LF
	dec	bx
	mov	al,CHR_LINEFEED
cc1:	cmp	al,CHR_LINEFEED
	jne	cc9
	call	decB
	jc	cc9
	call	getc
	cmp	al,CHR_LINEFEED		; was the line empty?
	je	cc8			; yes
	dec	bx
cc8:	inc	bx
cc9:	mov	[bp].V_CUR,bx
	ret
ENDPROC	clampCur

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Text modification functions
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; moveGap
;
; Moves the gap to logical offset BX.
;
; Modifies:
;	None
;
DEFPROC	moveGap
	push	cx
	push	si
	push	di
	push	ds
	mov	cx,[bp].V_GS
	cmp	bx,cx
	je	mg8
	push	es
	pop	ds			; DS = text segment
	jb	mg1
	mov	si,cx			; move the text between the gap and BX
	add	si,[bp].V_GL		; to the start of the gap
	mov	di,cx
	mov	cx,bx
	sub	cx,di
	rep	movsb
	jmp	short mg8
mg1:	sub	cx,bx			; move the text between BX and the gap
	mov	si,[bp].V_GS		; to the end of the gap
	dec	si
	mov	di,si
	add	di,[bp].V_GL
	std
	rep	movsb
	cld
mg8:	mov	[bp].V_GS,bx
	pop	ds
	pop	di
	pop	si
	pop	cx
	ret
ENDPROC	moveGap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; makeRoom
;
; Makes sure the gap holds at least CX bytes, by growing the text segment
; (or, if it can't grow, by copying the text to a larger segment).
;
; Outputs:
;	Carry set if out of memory (and a message is displayed)
;
; Modifies:
;	None
;
DEFPROC	makeRoom
	cmp	[bp].V_GL,cx		; is the gap big enough?
	jb	mr0			; no
	ret				; yes (and carry is clear)
mr0:	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	mov	ax,[bp].V_LEN
	add	ax,cx
	jc	mr7
	mov	dx,ax			; DX = minimum size
	add	ax,GROW
	jc	mr1
	cmp	ax,0FFF0h
	jbe	mr2
mr1:	mov	ax,0FFF0h
mr2:	cmp	ax,dx			; is the new size large enough?
	jb	mr7			; no
	add	ax,15
	mov	cl,4
	shr	ax,cl
	xchg	bx,ax			; BX = paragraphs
	push	bx
	mov	ah,DOS_MEM_REALLOC
	int	21h
	mov	ax,es			; AX = new segment (the same)
	jnc	mr3
	pop	bx
	push	bx
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h
	jc	mr6
mr3:	pop	bx
	mov	cl,4
	shl	bx,cl			; BX = new size in bytes
	push	ds
	mov	dx,es			; DX = old segment
	mov	cx,[bp].V_LEN
	sub	cx,[bp].V_GS		; CX = length of text after the gap
	mov	si,[bp].V_LEN
	add	si,[bp].V_GL		; SI = old size in bytes
	mov	di,bx
	mov	ds,dx
	mov	es,ax
	dec	si
	dec	di
	std				; move the text after the gap
	rep	movsb			; to the end of the new segment
	cld
	cmp	ax,dx			; is it the same segment?
	je	mr4			; yes
	sub	si,si			; no, so copy the text before the gap
	sub	di,di
	mov	cx,[bp].V_GS
	rep	movsb
	push	es
	mov	es,dx
	mov	ah,DOS_MEM_FREE		; and free the old segment
	int	21h
	pop	es
mr4:	pop	ds
	mov	[bp].V_TSEG,es
	sub	bx,[bp].V_LEN
	mov	[bp].V_GL,bx
	clc
	jmp	short mr8
mr6:	pop	bx
mr7:	mov	si,offset MEM_ERR
	call	setMsg
mr8:	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	makeRoom

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; insChar
;
; Inputs:
;	AL = character to insert at BX
;
; Outputs:
;	BX advanced; carry set if out of memory
;
; Modifies:
;	None
;
DEFPROC	insChar
	push	cx
	mov	cx,1
	call	makeRoom
	pop	cx
	jc	ic9
	call	moveGap
	mov	es:[bx],al
	inc	bx
	mov	[bp].V_GS,bx
	dec	[bp].V_GL
	inc	[bp].V_LEN
	inc	[bp].V_UINS
ic9:	ret
ENDPROC	insChar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; insText
;
; Inputs:
;	AX = segment of the text to insert at BX (at offset 0)
;	CX = length
;
; Outputs:
;	BX advanced; carry set if out of memory
;
; Modifies:
;	None
;
DEFPROC	insText
	jcxz	it9
	call	makeRoom
	jc	it9
	call	moveGap
	push	cx
	push	si
	push	di
	push	ds
	mov	di,bx
	mov	ds,ax
	sub	si,si
	rep	movsb
	pop	ds
	pop	di
	pop	si
	pop	cx
	add	bx,cx
	mov	[bp].V_GS,bx
	sub	[bp].V_GL,cx
	add	[bp].V_LEN,cx
	add	[bp].V_UINS,cx		; (carry clear)
it9:	ret
ENDPROC	insText

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copyOut
;
; Inputs:
;	SI = text segment offset of the text to copy
;	CX = length
;
; Outputs:
;	AX = segment of a new block containing the text (0 if CX is zero);
;	carry set if out of memory (and a message is displayed)
;
; Modifies:
;	AX
;
DEFPROC	copyOut
	sub	ax,ax
	jcxz	cp9
	push	bx
	mov	bx,cx
	add	bx,15
	rcr	bx,1
	shr	bx,1
	shr	bx,1
	shr	bx,1
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h
	pop	bx
	jc	cp8
	push	cx
	push	si
	push	di
	push	ds
	push	es
	push	es
	pop	ds
	mov	es,ax
	sub	di,di
	rep	movsb
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	cx
	ret
cp8:	push	si
	push	di
	mov	si,offset MEM_ERR
	call	setMsg
	pop	di
	pop	si
cp9:	ret
ENDPROC	copyOut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setUndo, setYank
;
; Replaces the undo (or yank) block with the block in AX, freeing the old
; block unless the other one is still using it.
;
; Modifies:
;	AX
;
DEFPROC	setUndo
	xchg	ax,[bp].V_USEG
	cmp	ax,[bp].V_YSEG
	jmp	short freeSeg
ENDPROC	setUndo

DEFPROC	setYank
	xchg	ax,[bp].V_YSEG
	cmp	ax,[bp].V_USEG
	DEFLBL	freeSeg,near
	je	fs9
	test	ax,ax
	jz	fs9
	push	es
	mov	es,ax
	mov	ah,DOS_MEM_FREE
	int	21h
	pop	es
fs9:	ret
ENDPROC	setYank

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; beginChange
;
; Starts a new undo record for a change at BX.  Every change deletes (at
; most once) and then inserts at that offset.
;
; Modifies:
;	AX
;
DEFPROC	beginChange
	sub	ax,ax
	call	setUndo
	sub	ax,ax
	mov	[bp].V_UOFF,bx
	mov	[bp].V_ULEN,ax
	mov	[bp].V_UINS,ax
	or	[bp].V_FLAGS,F_MOD
;
; A change before the top line could leave our idea of the screen out of
; date, so redraw it all.
;
	cmp	bx,[bp].V_DTOP
	jae	bc9
	jmp	markAll
bc9:	ret
ENDPROC	beginChange

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cutText
;
; Deletes CX bytes at BX, saving them for undo, and if AL is non-zero,
; yanking them as well (and AH is non-zero if they're linewise).
;
; Outputs:
;	Carry set if out of memory
;
; Modifies:
;	AX, DX
;
DEFPROC	cutText
	clc
	jcxz	ct9
	call	moveGap
	push	si
	mov	si,bx
	add	si,[bp].V_GL		; SI -> the text after the gap
	xchg	dx,ax			; DL = yank flag, DH = linewise flag
	call	copyOut
	jc	ct8
	call	setUndo
	mov	[bp].V_ULEN,cx
	test	dl,dl			; yank too?
	jz	ct1			; no
	mov	ax,[bp].V_USEG
	call	setYank
	mov	[bp].V_YLEN,cx
	mov	[bp].V_YLINE,dh
ct1:	add	[bp].V_GL,cx
	sub	[bp].V_LEN,cx
	clc
ct8:	pop	si
ct9:	ret
ENDPROC	cutText

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Screen functions
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; markLine, markBelow, markAll, markStatus
;
; Mark the cursor's row, the rows from the cursor's row to the end of the
; screen, every row, or the status row, to be redrawn.
;
; Modifies:
;	AX
;
DEFPROC	markLine
	mov	al,[bp].V_CROW
	push	si
	cbw
	xchg	si,ax
	mov	[bp+si].V_RDIRTY,1
	pop	si
	ret
ENDPROC	markLine

DEFPROC	markStatus
	mov	al,[bp].V_TROWS
	jmp	short ma1
ENDPROC	markStatus

DEFPROC	markAll
	mov	al,0
	jmp	short ma1
	DEFLBL	markBelow,near
	mov	al,[bp].V_CROW
ma1:	push	si
	cbw
	xchg	si,ax
ma2:	mov	[bp+si].V_RDIRTY,1
	inc	si
	mov	ax,si
	cmp	al,[bp].V_ROWS
	jb	ma2
	pop	si
	ret
ENDPROC	markAll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clearAll
;
; Clears the screen, and marks every row to be redrawn.  Afterward, only the
; text rows scroll (see scrollScreen), which also moves the cursor to the
; first one.
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	clearAll
	call	clearScreen
	mov	dh,[bp].V_TROWS
	call	setRows
	push	di
	lea	di,[bp].V_RLEN
	mov	cx,MAXROWS
ca1:	mov	byte ptr [di],0
	inc	di
	loop	ca1
	pop	di
	jmp	markAll
ENDPROC	clearAll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clearScreen
;
; Makes every row a scrolling row again, and clears them all.
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	clearScreen
	mov	dh,[bp].V_ROWS
	call	setRows
	mov	dh,0			; DX = 0 (clear the scrolling rows)
	DEFLBL	setRows,near		; DH = # of scrolling rows
	mov	dl,0
	DEFLBL	setRowsDX,near		; DL = first row, DH = last row + 1
	mov	[bp].V_POS,-1		; (the cursor moves; see setPos)
	sub	cx,cx
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SCROLL
	mov	bx,STDOUT
	int	21h
	ret
ENDPROC	clearScreen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; refresh
;
; Makes sure the cursor is on the screen (scrolling or redrawing as needed),
; redraws any rows that need it, and positions the cursor.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	refresh
	cmp	[fCtrlC],0		; did a CTRLC mess up the screen?
	je	rf0			; no
	mov	[fCtrlC],0
	call	clearAll
rf0:	mov	bx,[bp].V_TOP
	cmp	bx,[bp].V_LEN
	jb	rf0a
	mov	bx,[bp].V_LEN
rf0a:	call	lineStart
	mov	[bp].V_TOP,bx
	mov	si,bx			; SI = top
	mov	bx,[bp].V_CUR
	call	lineStart		; BX = start of the cursor's line
	cmp	bx,si			; is it above the screen?
	jb	rf2			; yes
	push	bx
	call	findRow
	pop	bx
	jnc	rf3			; it's on the screen
	mov	cl,[bp].V_TROWS		; it's below the screen, so it will
	mov	ch,0			; be on the last row
	dec	cx
	call	upN
rf2:	mov	[bp].V_TOP,bx
;
; If the top line moved by one line, scroll the screen; otherwise, if it
; moved at all, redraw it all.
;
rf3:	mov	ax,[bp].V_TOP
	mov	di,[bp].V_DTOP		; DI = top line displayed
	cmp	ax,di
	je	rf6
	mov	[bp].V_DTOP,ax
	mov	cx,1
	push	ax
	mov	bx,di
	call	nextLine
	pop	ax
	cmp	bx,ax			; did it move down one line?
	je	rf5			; yes, so scroll up
	neg	cx
	xchg	bx,ax
	call	nextLine
	jc	rf4
	cmp	bx,di			; did it move up one line?
	je	rf5			; yes, so scroll down
rf4:	call	markAll
	jmp	short rf6
rf5:	call	scrollScreen
;
; Find the cursor's row, and make sure its column is on the screen.
;
rf6:	mov	bx,[bp].V_CUR
	call	lineStart
	mov	si,[bp].V_TOP
	call	findRow
	mov	[bp].V_CROW,dl
	mov	bx,[bp].V_CUR
	call	dispCol			; AX = column
	mov	dx,[bp].V_LEFT
	cmp	ax,dx			; left of the screen?
	jb	rf7			; yes
	mov	cl,[bp].V_COLS
	mov	ch,0
	add	dx,cx
	cmp	ax,dx			; right of the screen?
	jb	rf8			; no
rf7:	mov	cl,[bp].V_COLS		; center the column
	shr	cl,1
	mov	ch,0
	sub	ax,cx
	jnc	rf7a
	sub	ax,ax
rf7a:	mov	[bp].V_LEFT,ax
	call	markAll
rf8:	call	drawRows
	mov	bx,[bp].V_CUR
	call	dispCol
	sub	ax,[bp].V_LEFT
	mov	cl,al
	mov	ch,[bp].V_CROW
	jmp	setPos
ENDPROC	refresh

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findRow
;
; Inputs:
;	BX = start of a line
;	SI = start of the top line
;
; Outputs:
;	DL = screen row of the line; carry set if it's not on the screen
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	findRow
	sub	dx,dx
fr1:	cmp	si,bx
	je	fr9			; (carry clear)
	inc	dx
	cmp	dl,[bp].V_TROWS
	jae	fr8
	xchg	si,bx
	call	nextLine
	xchg	si,bx
	jmp	fr1
fr8:	stc
fr9:	ret
ENDPROC	findRow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scrollScreen
;
; Scrolls the text rows (see clearAll) up (CX = 1) or down (CX = -1) one row,
; and updates our record of what's on them; the exposed row must then be
; redrawn.
;
; scrollRows scrolls only the text rows from row AL down, for a line that
; was deleted (CX = 1) or inserted (CX = -1) there, by making them the only
; scrolling rows meanwhile; a terminal needs at least two, so with fewer, the
; rows are simply redrawn.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	scrollScreen
	mov	al,0
	DEFLBL	scrollRows,near
	cbw
	push	ax			; save the first row
	push	cx			; and the direction
	xchg	dx,ax			; DL = first row
	test	dl,dl			; every text row?
	jz	ss0			; yes
	mov	dh,[bp].V_TROWS
	mov	al,dh
	sub	al,dl
	cmp	al,2			; at least two rows?
	jl	ss7			; no
	call	setRowsDX
	pop	cx
	push	cx
	jc	ss7
ss0:	mov	[bp].V_POS,-1		; (the cursor moves; see setPos)
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SCROLL
	mov	bx,STDOUT
	int	21h
	pop	dx			; DX = direction
	pop	bx			; BX = first row
	pushf
	test	bx,bx
	jz	ss0a
	push	bx
	push	dx
	mov	dh,[bp].V_TROWS
	call	setRows			; every text row scrolls again
	pop	dx
	pop	bx
ss0a:	popf
	jc	ss8			; the scroll failed, so redraw it all
	push	es
	push	ss
	pop	es
	lea	di,[bp].V_RLEN
	call	shiftRows
	lea	di,[bp].V_RDIRTY
	call	shiftRows
;
; Move the rows' contents (see putRow), too; CX is the number of rows that
; shiftRows moved, and the exposed row's length is now zero.
;
	mov	al,MAXCOLS
	mul	cl
	xchg	cx,ax			; CX = # bytes to move
	mov	al,MAXCOLS
	mul	bl
	lea	di,[bp].V_SCR
	add	di,ax			; DI -> first row's contents
	lea	si,[di+MAXCOLS]
	test	dx,dx			; scrolled down?
	jns	ss0b			; no
	add	di,cx
	add	di,MAXCOLS-1
	lea	si,[di-MAXCOLS]
	std
ss0b:	rep	movsb
	cld
	pop	es
	mov	si,bx			; SI = first row
	test	dx,dx			; scrolled down?
	js	ss1			; yes
	mov	al,[bp].V_TROWS
	cbw
	dec	ax
	xchg	si,ax			; SI = last text row
ss1:	mov	[bp+si].V_RDIRTY,1
	ret
ss7:	pop	cx
	pop	ax			; AL = first row
	jmp	ma1			; redraw the rows from there down
ss8:	jmp	markAll

shiftRows:
	add	di,bx
	mov	cl,[bp].V_TROWS
	mov	ch,0
	dec	cx
	sub	cx,bx			; CX = # rows to move
	push	cx
	mov	si,di
	test	dx,dx			; scrolled down?
	js	sr1			; yes
	inc	si
	rep	movsb
	jmp	short sr2
sr1:	add	di,cx
	lea	si,[di-1]
	std
	rep	movsb
	cld
sr2:	mov	byte ptr [di],0
	pop	cx
	ret
ENDPROC	scrollScreen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; drawRows
;
; Redraws every row that's marked.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	drawRows
	mov	bx,[bp].V_TOP
	sub	cx,cx			; CL = row
dr1:	mov	si,cx
	cmp	cl,[bp].V_TROWS		; status row?
	jae	dr8			; yes
	cmp	[bp+si].V_RDIRTY,0
	je	dr2
	mov	[bp+si].V_RDIRTY,0
	push	bx
	push	cx
	call	drawRow
	pop	cx
	pop	bx
dr2:	call	nextLine
	inc	cx
	jmp	dr1
dr8:	cmp	[bp+si].V_RDIRTY,0
	je	dr9
	mov	[bp+si].V_RDIRTY,0
	lea	si,[bp].V_MSG
	mov	cl,[bp].V_MSGLEN
	test	[bp].V_MODE,MODE_INS	; insert mode?
	jz	putText			; no
	mov	si,offset INS_MSG
	mov	cl,INS_LEN
	jmp	short putText
dr9:	ret
ENDPROC	drawRows

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putText
;
; Displays text on the status row.
;
; Inputs:
;	SI -> text
;	CL = length
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	putText
	mov	ch,0
	mov	al,[bp].V_COLS
	dec	ax			; leave the last column empty
	cmp	cl,al			; (so the screen won't scroll)
	jbe	pt1
	mov	cl,al
pt1:	lea	di,[bp].V_ROWBUF
	jcxz	pt3
pt2:	lodsb
	mov	[di],al
	inc	di
	loop	pt2
pt3:	mov	cl,[bp].V_TROWS
	jmp	short putRow
ENDPROC	putText

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; drawRow
;
; Inputs:
;	BX = start of a line (or V_LEN if past the end)
;	CL = row
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	drawRow
	lea	di,[bp].V_ROWBUF
	sub	dx,dx			; DX = display column
	cmp	bx,[bp].V_LEN		; past the end?
	jb	drw1			; no
	mov	byte ptr [di],'~'
	inc	di
	jmp	short putRow
drw1:	call	getc
	jc	putRow
	cmp	al,CHR_LINEFEED
	je	putRow
	cmp	al,CHR_TAB
	jne	drw3
drw2:	mov	al,CHR_SPACE
	call	putCell
	jc	putRow
	test	dl,7
	jnz	drw2
	jmp	short drw6
drw3:	cmp	al,CHR_SPACE		; control character?
	jb	drw4			; yes
	cmp	al,CHR_DEL		; DEL?
	jne	drw5			; no
	mov	al,'?'-'@'
drw4:	push	ax
	mov	al,'^'
	call	putCell
	pop	ax
	jc	putRow
	add	al,'@'
drw5:	call	putCell
	jc	putRow
drw6:	inc	bx
	jmp	drw1
ENDPROC	drawRow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putRow
;
; Displays the row in V_ROWBUF, by writing only what differs from the row's
; current contents (see V_SCR and V_RLEN): the text after their common
; start (and before their common end, if they're the same length), plus
; enough spaces to erase whatever remains of the current contents; if that
; would take ERASE_MIN spaces or more, the rest of the row is erased instead
; (which takes a terminal about that many characters).
;
; Inputs:
;	CL = row
;	DI -> end of the row's contents in V_ROWBUF
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	putRow
	lea	dx,[bp].V_ROWBUF
	mov	ax,di
	sub	ax,dx			; AL = new length
	mov	di,cx
	and	di,0FFh			; DI = row
	push	di
	mov	bl,al			; BL = new length
	xchg	al,[bp+di].V_RLEN
	mov	bh,al			; BH = current length
	mov	al,MAXCOLS
	mul	cl
	lea	di,[bp].V_SCR
	add	di,ax			; DI -> current contents
	mov	si,dx			; SI -> new contents
	push	es
	push	ss
	pop	es
	mov	cl,bl
	cmp	cl,bh
	jbe	pr1
	mov	cl,bh
pr1:	mov	ch,0			; CX = the shorter length
	jcxz	pr2
	repe	cmpsb
	je	pr2
	dec	si
	dec	di			; back up to the first difference
pr2:	mov	ax,si
	sub	ax,dx			; AL = first column to write
	mov	cl,bl
	sub	cl,al			; CX = # characters from there
	cmp	bl,bh			; same length?
	jne	pr3			; no
	jcxz	pr3
	push	si
	push	di
	add	si,cx
	add	di,cx
	dec	si
	dec	di
	std
	repe	cmpsb			; skip their common end
	cld
	inc	cx
	pop	di
	pop	si
pr3:	mov	dx,si			; DX -> characters to write
	push	cx
	rep	movsb			; update the current contents
	pop	cx
	pop	es
	mov	ah,0			; AH = 0 (nothing to erase)
	sub	bh,bl			; BH = # spaces needed
	jbe	pr6
	cmp	bh,ERASE_MIN
	jae	pr5
pr4:	mov	byte ptr [si],CHR_SPACE
	inc	si
	inc	cx
	dec	bh
	jnz	pr4
	jmp	short pr6
pr5:	inc	ah			; AH = 1 (erase after the new contents)
pr6:	pop	di			; DI = row
	jcxz	pr7
	push	ax
	push	bx
	push	cx
	mov	cx,di
	mov	ch,cl
	mov	cl,al
	call	setPos
	pop	cx
	call	writeOut
	pop	bx
	pop	ax
pr7:	test	ah,ah
	jz	pr9
	mov	cx,di
	mov	ch,cl
	mov	cl,bl			; CL = new length
	mov	al,2
	jmp	short setPosAX
pr9:	ret
ENDPROC	putRow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putCell
;
; Inputs:
;	AL = character for display column DX
;	DI -> next position in V_ROWBUF
;
; Outputs:
;	DX and (if the column is displayed) DI advanced; carry set if the row
;	is full
;
DEFPROC	putCell
	cmp	dx,[bp].V_LEFT		; is the column displayed?
	jb	pc1			; no
	mov	[di],al
	inc	di
pc1:	inc	dx
	cmp	di,[bp].V_RLIM
	cmc				; carry set if DI >= V_RLIM
	ret
ENDPROC	putCell

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeOut
;
; Inputs:
;	DX -> data to write to STDOUT
;	CX = length (less than 256)
;
; Modifies:
;	AX, BX
;
DEFPROC	writeOut
	add	byte ptr [bp].V_POS,cl	; the cursor moves, too (see setPos)
	mov	bx,STDOUT
	mov	ah,DOS_HDL_WRITE
	int	21h
	ret
ENDPROC	writeOut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setPos
;
; Moves the cursor, unless it's there already: V_POS is the position we last
; set, plus whatever putRow has written since (a row's last column leaves it
; at a column that's never requested, so the cursor is then set again).
;
; Inputs:
;	CL = col, CH = row
;	For setPosAX only: AL = 2, and AH = 1 to erase from the new position
;	to the end of the row
;
; Modifies:
;	AX
;
DEFPROC	setPos
	mov	ax,2			; leave the cursor's visibility alone
	DEFLBL	setPosAX,near
	cmp	cx,[bp].V_POS		; is the cursor there already?
	jne	sp1			; no
	test	ah,ah			; anything to erase?
	jz	sp9			; no
sp1:	mov	[bp].V_POS,cx
	push	bx
	push	dx
	xchg	dx,ax
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SETPOS
	mov	bx,STDOUT
	int	21h
	pop	dx
	pop	bx
sp9:	ret
ENDPROC	setPos


	DEFLBL	INS_MSG,byte
		db	"-- INSERT --"
	DEFABS	INS_LEN,<$ - INS_MSG>

CODE	ENDS

	end
