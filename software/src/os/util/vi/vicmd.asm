;
; BASIC-DOS Visual Editor: Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
;
; The command functions (see CMDTBL in vimove.asm).
;
	include	vi.inc

CODE	SEGMENT word public 'CODE'

	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:CODE

	EXTNEAR	<beginChange,classAt,clearAll,colToOff,copyOut,countLines>
	EXTNEAR	<cutText,decB,dispCol,downN,findRow,firstNonBlank,getc>
	EXTNEAR	<getCount,getKey,gotoLine,incB,insChar,insText,lineEnd>
	EXTNEAR	<lineStart,lookup,makeRoom,mapKey,markAll,markBelow,markLine>
	EXTNEAR	<markStatus,motionAt,moveGap,msgEnd,msgName,msgSpNum,msgStr>
	EXTNEAR	<nextLine,quit,readCmd,refresh,saveFile,setIns,setMsg,setUndo>
	EXTNEAR	<setYank,upN>
	EXTBYTE	<CMDTBL,MOTTBL>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Commands
;
; Every command is called with AL = key, BX = cursor offset, and CX = count
; (at least 1, and V_COUNT is zero if none was specified); returning carry
; set means the command failed.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdIns (i, a, I, A)
;
DEFPROC	cmdIns
	cmp	al,'a'
	jne	ci1
	call	getc
	cmp	al,CHR_LINEFEED		; appending on an empty line?
	je	ci3			; yes, so it's like 'i'
	inc	bx
	jmp	short ci3
ci1:	cmp	al,'I'
	jne	ci2
	call	firstNonBlank
	jmp	short ci3
ci2:	cmp	al,'A'
	jne	ci3
	call	lineEnd
ci3:	mov	al,1
	jmp	startIns
ENDPROC	cmdIns

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdOpen (o, O)
;
DEFPROC	cmdOpen
	push	ax
	cmp	al,'O'
	je	on2
	call	lineEnd
	jmp	short on3
on2:	call	lineStart
on3:	call	beginChange
	mov	al,CHR_LINEFEED
	call	insChar
	pop	ax
	jc	on9
	cmp	al,'O'
	jne	on4
	dec	bx			; 'O' opens the line before the LF
on4:	call	markBelow
	mov	al,0
	jmp	short startIns
on9:	ret
ENDPROC	cmdOpen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; startIns
;
; Enters insert mode, and returns when it's over (ESC, CTRLC, or a mapped
; 'i', such as INS or the WordStar CTRLV).  Other mapped keys perform their
; motions or commands, and if a command calls startIns (eg, the WordStar
; CTRLN, which is 'O'), it simply returns to the insert mode in progress.
;
; Inputs:
;	AL = 1 to begin a new change, 0 to continue the current one
;	BX = offset to insert at
;
DEFPROC	startIns
	mov	[bp].V_CUR,bx
	test	[bp].V_MODE,MODE_INS	; insert mode already?
	jz	sn0a			; no
	ret
sn0a:	push	ax
	mov	cl,1
	call	setIns			; insert mode uses a block cursor
	or	[bp].V_MODE,MODE_INS
	call	markStatus
	pop	ax
	mov	bx,[bp].V_CUR
	test	al,al
	jz	sn1
;
; A new change begins with the first inserted character, so that motions
; and commands in insert mode don't discard the previous change's undo.
;
sn0:	or	[bp].V_MODE,MODE_CHG
sn1:	mov	[bp].V_CUR,bx
	mov	[bp].V_ISTART,bx
sn2:	call	refresh
	call	getKey
	mov	bx,[bp].V_CUR
	test	ah,ah			; mapped key?
	jz	sn2a			; no
	cmp	al,'i'			; INS (or CTRLV)?
	je	sn8			; yes
	call	insMap
	jc	sn2
	jmp	sn0
sn2a:	cmp	al,CHR_ESCAPE
	je	sn9
	cmp	al,CHR_CTRLC
	je	sn9
	cmp	al,CHR_BACKSPACE
	je	sn5
	cmp	al,CHR_DEL
	je	sn5
	test	al,al			; failed read?
	jz	sn2			; yes
	cmp	al,CHR_RETURN
	jne	sn3
	mov	al,CHR_LINEFEED
sn3:	and	[bp].V_FLAGS,NOT F_KEEPW
	push	ax
	test	[bp].V_MODE,MODE_CHG	; begin a new change?
	jz	sn3a			; no
	and	[bp].V_MODE,NOT MODE_CHG
	call	beginChange
	pop	ax
	push	ax
sn3a:	call	insChar
	pop	ax
	jc	sn2
	mov	[bp].V_CUR,bx
sn4:	cmp	al,CHR_LINEFEED		; new line?
	jne	sn4a			; no
	call	markBelow
	jmp	sn2
sn4a:	call	markLine
	jmp	sn2
;
; Erase the previous character (but only if it was inserted, and since the
; gap is at the cursor, that's done by shrinking the text before the gap).
;
sn5:	cmp	bx,[bp].V_ISTART
	jbe	sn2
	dec	bx
	mov	[bp].V_CUR,bx
	dec	[bp].V_GS
	inc	[bp].V_GL
	dec	[bp].V_LEN
	dec	[bp].V_UINS
	mov	al,es:[bx]		; AL = erased character
	jmp	sn4

sn8:	mov	al,0			; (INS doesn't move the cursor)
sn9:	push	ax
	and	[bp].V_MODE,NOT (MODE_INS OR MODE_CHG)
	and	[bp].V_FLAGS,NOT F_KEEPW
	call	markStatus
	mov	cl,0
	call	setIns
	pop	ax
	test	al,al
	jz	sn9b
	mov	bx,[bp].V_CUR		; ESC moves the cursor left
	call	decB
	jc	sn9b
	call	getc
	cmp	al,CHR_LINEFEED		; unless it's at the start of a line
	je	sn9b
	mov	[bp].V_CUR,bx
sn9b:	ret
ENDPROC	startIns

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; insMap
;
; Performs the motion or command of a mapped key (eg, a cursor key) in
; insert mode, with no count.
;
; Inputs:
;	AL = key
;	BX = cursor offset
;
; Outputs:
;	If carry clear, BX = new cursor offset
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	insMap
	push	ax
	test	[bp].V_FLAGS,F_KEEPW	; keep the desired column?
	jnz	im1			; yes
	call	dispCol
	mov	[bp].V_WANT,ax
im1:	pop	ax
	and	[bp].V_FLAGS,NOT F_KEEPW
	sub	cx,cx
	mov	[bp].V_COUNT,cx
	inc	cx			; CX = 1
	mov	si,offset CMDTBL
	call	lookup
	jc	im9
	cmp	si,offset MOTTBL	; is it a motion?
	jbe	im2			; no
	mov	dl,0
	call	word ptr [si-2]		; BX = new offset, DL = motion flags
	jc	im9
	test	dl,M_VERT		; vertical motion?
	jz	im9			; no (carry clear)
	or	[bp].V_FLAGS,F_KEEPW	; (carry clear)
	ret
im2:	call	word ptr [si-2]
	mov	bx,[bp].V_CUR
	clc
im9:	ret
ENDPROC	insMap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdAlias (x, X, D, C, s, S, Y)
;
; These are aliases for operator commands (eg, 'x' is "dl").
;
DEFPROC	cmdAlias
	mov	si,offset ALIASES
	call	mapKey
	mov	ah,0
	mov	[bp].V_PEND,ax		; the motion key is pending
	mov	al,[si+ALIAS_OPS-2]	; AL = operator
	jmp	short cmdOp
ENDPROC	cmdAlias

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdOp (d, c, y)
;
; Reads a motion (or the same key again, for whole lines), and deletes,
; changes, or yanks the text from the cursor to the motion's destination.
;
DEFPROC	cmdOp
	mov	[bp].V_OP,al
	push	cx
	call	getKey
	sub	cx,cx
	call	getCount		; CX = motion count (0 if none)
	pop	dx
	jcxz	op1
	mov	[bp].V_COUNT,cx
	xchg	ax,cx
	mul	dx
	xchg	ax,cx			; CX = command count * motion count
	jmp	short op2
op1:	mov	cx,dx
op2:	mov	bx,[bp].V_CUR
	cmp	al,[bp].V_OP		; same key (eg, "dd")?
	je	opLines			; yes
	mov	[bp].V_MKEY,al
;
; "cw" on a non-blank character is like "ce", except that it doesn't move
; beyond the end of the current word; so we start one character earlier.
;
	cmp	[bp].V_OP,'c'
	jne	op3
	mov	ah,al
	or	ah,20h
	cmp	ah,'w'
	jne	op3
	push	ax
	call	classAt
	test	ah,ah			; blank?
	pop	ax
	jz	op3			; yes
	sub	al,'w'-'e'
	dec	bx
	call	motionAt
	jmp	short op4		; (it can't fail)
op3:	call	motionAt		; BX = destination, DL = flags
	jc	opFail
op4:	mov	di,[bp].V_CUR
	cmp	di,bx
	jbe	op5
	xchg	di,bx			; DI = start, BX = end
op5:	test	dl,M_LINE
	jnz	opLinewise
	test	dl,M_INCL
	jz	op6
	inc	bx
;
; A word motion (eg, "dw") stops at the end of the line.
;
op6:	mov	al,[bp].V_MKEY
	or	al,20h
	cmp	al,'w'
	jne	opDo
	mov	si,bx			; SI = end
	mov	bx,di
op7:	cmp	bx,si
	jae	opDo
	call	getc
	cmp	al,CHR_LINEFEED
	je	opDo
	inc	bx
	jmp	op7
opFail:	stc
	ret

opLines:mov	di,bx
	dec	cx
	call	lineStart
	call	downN			; BX = last line
opLinewise:
	xchg	bx,di
	call	lineStart
	xchg	bx,di			; DI = start of the first line
	call	lineEnd			; BX = end of the last line
	mov	dh,1			; DH = linewise
	cmp	[bp].V_OP,'c'		; changing lines?
	je	opDo1			; yes, so keep the last LF
	inc	bx
	jmp	short opDo1
opDo:	mov	dh,0
opDo1:	mov	cx,bx
	sub	cx,di			; CX = length
	mov	bx,di			; BX = start
	cmp	[bp].V_OP,'y'
	je	opYank
	call	beginChange
	mov	al,1			; yank the text, too
	mov	ah,dh
	push	dx
	call	cutText
	pop	dx
	jc	opFail
	mov	[bp].V_CUR,bx
	mov	ax,[bp].V_USEG
	mov	cx,[bp].V_ULEN
	call	markCut
	cmp	[bp].V_OP,'c'
	jne	opd1
	mov	al,0
	jmp	startIns
opd1:	test	dh,dh			; linewise?
	jz	opRet			; no
	cmp	bx,[bp].V_LEN		; were the last lines deleted?
	jb	opd3			; no
	test	bx,bx			; were all the lines deleted?
	jnz	opd2			; no
	mov	al,CHR_LINEFEED		; yes, so add an empty line
	call	insChar
opd2:	dec	bx
	call	lineStart
opd3:	call	firstNonBlank
	mov	[bp].V_CUR,bx
opRet:	clc
	ret

opYank:	jcxz	opRet
	call	moveGap
	mov	si,bx
	add	si,[bp].V_GL
	call	copyOut
	jc	opFail
	call	setYank
	mov	[bp].V_YLEN,cx
	mov	[bp].V_YLINE,dh
	test	dh,dh			; linewise?
	jnz	opRet			; yes, so the cursor doesn't move
	mov	[bp].V_CUR,bx
	ret
ENDPROC	cmdOp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; markCut
;
; Marks the rows to redraw after cutting (or putting) text: just the
; cursor's row, unless the text includes a LF.
;
; Inputs:
;	AX = segment of the text, CX = its length
;	DH = non-zero if linewise
;
; Modifies:
;	AX, CX
;
DEFPROC	markCut
	test	dh,dh
	jnz	mc8
	jcxz	mc7
	push	di
	push	es
	mov	es,ax
	sub	di,di
	mov	al,CHR_LINEFEED
	repne	scasb
	pop	es
	pop	di
	je	mc8
mc7:	jmp	markLine
mc8:	jmp	markBelow
ENDPROC	markCut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdPut (p, P)
;
DEFPROC	cmdPut
	cmp	[bp].V_YLEN,0		; anything to put?
	stc
	je	cpt9			; no
	cmp	[bp].V_YLINE,0		; linewise?
	je	cpt2			; no
	cmp	al,'P'
	je	cpt1
	call	nextLine
	jmp	short cpt3
cpt1:	call	lineStart
	jmp	short cpt3
cpt2:	cmp	al,'P'
	je	cpt3
	call	getc
	cmp	al,CHR_LINEFEED		; on an empty line?
	je	cpt3			; yes
	inc	bx
cpt3:	call	beginChange
	push	bx
cpt4:	push	cx
	mov	ax,[bp].V_YSEG
	mov	cx,[bp].V_YLEN
	call	insText
	pop	cx
	jc	cpt5
	loop	cpt4
cpt5:	pop	ax			; AX = start
	xchg	ax,bx
	cmp	[bp].V_YLINE,0		; linewise?
	jne	cpt6			; yes
	dec	ax			; no, cursor on the last character
	xchg	bx,ax
	mov	[bp].V_CUR,bx
	mov	ax,[bp].V_YSEG
	mov	cx,[bp].V_YLEN
	mov	dh,0
	call	markCut
	clc
	ret
cpt6:	call	firstNonBlank
	mov	[bp].V_CUR,bx
	call	markBelow
	clc
cpt9:	ret
ENDPROC	cmdPut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdReplace (r)
;
DEFPROC	cmdReplace
	push	cx
	call	getKey
	pop	cx
	test	ah,ah			; non-ASCII key?
	jnz	cr8			; yes
	cmp	al,CHR_ESCAPE
	je	cr8
	cmp	al,CHR_RETURN
	jne	cr1
	mov	al,CHR_LINEFEED
cr1:	push	ax
	push	bx
	push	cx
cr2:	call	getc			; make sure there are CX characters
	cmp	al,CHR_LINEFEED		; before the end of the line
	je	cr7
	inc	bx
	loop	cr2
	pop	cx
	pop	bx
	call	beginChange
	sub	ax,ax			; no yank
	call	cutText
	pop	ax
	jc	cr9
	cmp	al,CHR_LINEFEED		; replacing with a new line?
	jne	cr3			; no
	mov	cx,1			; yes, just one
cr3:	call	insChar
	loop	cr3
	cmp	al,CHR_LINEFEED
	je	cr4
	dec	bx			; cursor on the last character
	mov	[bp].V_CUR,bx
	jmp	markLine
cr4:	mov	[bp].V_CUR,bx
	jmp	markBelow
cr7:	pop	cx
	pop	bx
	pop	ax
cr8:	stc
cr9:	ret
ENDPROC	cmdReplace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdTilde (~)
;
; Toggles the case of CX characters (up to the end of the line).
;
DEFPROC	cmdTilde
	mov	dx,bx
	push	bx
	call	lineEnd
	sub	bx,dx			; BX = characters left on the line
	cmp	cx,bx
	jbe	tt1
	mov	cx,bx
tt1:	pop	bx
	stc
	jcxz	tt9a
	call	beginChange
	sub	ax,ax
	call	cutText
	jc	tt9a
	sub	si,si
tt2:	push	ds
	mov	ds,[bp].V_USEG
	lodsb
	pop	ds
	mov	ah,al
	or	ah,20h
	cmp	ah,'a'			; letter?
	jb	tt3			; no
	cmp	ah,'z'
	ja	tt3
	xor	al,20h			; yes, toggle its case
tt3:	call	insChar
	loop	tt2
	mov	[bp].V_CUR,bx
	jmp	markLine
tt9a:	ret
ENDPROC	cmdTilde

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdJoin (J)
;
; Joins the next line to this one, replacing the LF and any leading blanks
; with a space (unless this line is empty or ends with a blank, or the next
; line is empty or starts with ')').
;
DEFPROC	cmdJoin
	call	lineEnd
	mov	dx,bx			; DX = LF
	call	incB			; is there a next line?
	jc	cj9			; no
cj1:	call	getc
	cmp	al,CHR_SPACE
	je	cj2
	cmp	al,CHR_TAB
	jne	cj3
cj2:	inc	bx
	jmp	cj1
cj3:	mov	cx,bx
	sub	cx,dx			; CX = LF plus leading blanks
	mov	bx,dx
	push	ax
	call	beginChange
	sub	ax,ax
	call	cutText
	pop	ax
	jc	cj9
	cmp	al,CHR_LINEFEED		; was the next line empty?
	je	cj8			; yes
	cmp	al,')'
	je	cj8
	call	decB
	jc	cj8
	call	getc
	inc	bx
	cmp	al,CHR_LINEFEED		; is this line empty?
	je	cj8			; yes
	cmp	al,CHR_SPACE		; does it end with a blank?
	je	cj8
	cmp	al,CHR_TAB
	je	cj8
	mov	al,CHR_SPACE
	call	insChar
	dec	bx
cj8:	mov	[bp].V_CUR,bx
	jmp	markBelow
cj9:	ret
ENDPROC	cmdJoin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdUndo (u)
;
; Undoes the last change, by deleting what it inserted and inserting what
; it deleted, which in turn becomes the change (so another 'u' redoes it).
;
DEFPROC	cmdUndo
	mov	bx,[bp].V_UOFF
	cmp	bx,-1			; anything to undo?
	stc
	je	cu9			; no
	mov	cx,[bp].V_ULEN
	call	makeRoom		; make room for the deleted text first
	jc	cu9
	call	moveGap
	mov	si,bx
	add	si,[bp].V_GL
	mov	cx,[bp].V_UINS
	call	copyOut			; AX = copy of the inserted text
	jc	cu9
	push	ax
	push	cx
	add	[bp].V_GL,cx		; delete the inserted text
	sub	[bp].V_LEN,cx
	mov	ax,[bp].V_USEG
	mov	cx,[bp].V_ULEN
	mov	[bp].V_UINS,0
	call	insText			; and insert the deleted text
	pop	[bp].V_ULEN
	pop	ax
	call	setUndo
	mov	bx,[bp].V_UOFF
	mov	[bp].V_CUR,bx
	or	[bp].V_FLAGS,F_MOD
	call	markAll
	clc
cu9:	ret
ENDPROC	cmdUndo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdSearch (/, ?)
;
DEFPROC	cmdSearch
	push	ax
	call	readCmd
	pop	ax
	jc	cs9
	jcxz	cs2			; empty, so use the previous pattern
	mov	[bp].V_PATLEN,cx
	push	es
	push	ss
	pop	es
	lea	di,[bp].V_PAT
	rep	movsb
	pop	es
cs2:	sub	al,'/'			; AL = 0 for '/'
	jz	cs3
	mov	al,1			; AL = 1 for '?'
cs3:	mov	[bp].V_SDIR,al
	mov	bx,[bp].V_CUR
	call	findPat
	jc	cs9
	mov	[bp].V_CUR,bx
cs9:	ret
ENDPROC	cmdSearch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findPat
;
; Searches for V_PAT, wrapping around the end (or start) of the text.
;
; Inputs:
;	AL = 0 to search forward from BX, 1 to search backward
;
; Outputs:
;	If carry clear, BX = offset of the match
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	findPat
	mov	si,offset NOPAT_ERR
	cmp	[bp].V_PATLEN,0		; is there a pattern?
	je	fp8			; no
	mov	cx,[bp].V_LEN
fp1:	test	al,al			; backward?
	jnz	fp2			; yes
	inc	bx
	cmp	bx,[bp].V_LEN
	jb	fp3
	sub	bx,bx
	jmp	short fp3
fp2:	test	bx,bx
	jnz	fp2a
	mov	bx,[bp].V_LEN
fp2a:	dec	bx
fp3:	call	matchAt
	jnc	fp9
	loop	fp1
	mov	si,offset FIND_ERR
fp8:	jmp	setMsg
fp9:	ret
ENDPROC	findPat

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; matchAt
;
; Outputs:
;	Carry clear if V_PAT matches the text at BX
;
; Modifies:
;	None
;
DEFPROC	matchAt
	push	ax
	push	bx
	push	cx
	push	si
	lea	si,[bp].V_PAT
	mov	cx,[bp].V_PATLEN
mat3:	call	getc
	jc	mat9
	cmp	al,[si]
	stc
	jne	mat9
	inc	si
	inc	bx
	loop	mat3
	clc
mat9:	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	matchAt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdScroll (CTRLF, CTRLB, CTRLD, CTRLU, CTRLE, CTRLY)
;
; Scrolls the screen forward or backward by pages (CTRLF and CTRLB), half
; pages (CTRLD and CTRLU, which move the cursor too), or lines (CTRLE and
; CTRLY), keeping the cursor on the screen.
;
DEFPROC	cmdScroll
	mov	dh,al			; DH = key
	mov	al,[bp].V_TROWS
	cbw
	cmp	dh,CHR_CTRLE
	je	sc2
	cmp	dh,CHR_CTRLY
	je	sc2
	shr	ax,1			; half a screen
	cmp	dh,CHR_CTRLD
	je	sc1
	cmp	dh,CHR_CTRLU
	je	sc1
	mov	al,[bp].V_TROWS
	sub	al,2			; a screen, less 2 lines
	push	dx
	mul	cx
	pop	dx
sc1:	xchg	cx,ax			; CX = # lines
sc2:	push	cx
	mov	bx,[bp].V_TOP
	call	scrollBy
	mov	[bp].V_TOP,bx
	pop	cx
	cmp	dh,CHR_CTRLD
	je	sc3
	cmp	dh,CHR_CTRLU
	jne	sc4
sc3:	mov	bx,[bp].V_CUR
	call	lineStart
	call	scrollBy
	mov	ax,[bp].V_WANT
	call	colToOff
	mov	[bp].V_CUR,bx
;
; Keep the cursor on the screen.
;
sc4:	mov	bx,[bp].V_CUR
	call	lineStart
	mov	si,[bp].V_TOP
	cmp	bx,si			; above the screen?
	jb	sc5			; yes
	push	bx
	call	findRow
	pop	bx
	jnc	sc9			; it's on the screen
	mov	bx,[bp].V_TOP
	mov	cl,[bp].V_TROWS
	mov	ch,0
	dec	cx
	call	downN
	jmp	short sc6
sc5:	mov	bx,si
sc6:	mov	ax,[bp].V_WANT
	call	colToOff
	mov	[bp].V_CUR,bx
sc9:	or	[bp].V_FLAGS,F_KEEPW
	ret
;
; Moves BX down (for CTRLD, CTRLE, and CTRLF, which are 04h-06h) or up
; CX lines.
;
scrollBy:
	cmp	dh,CHR_CTRLD
	jb	sb1
	cmp	dh,CHR_CTRLF
	ja	sb1
	push	dx
	call	downN
	pop	dx
	ret
sb1:	jmp	upN
ENDPROC	cmdScroll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdInfo (CTRLG)
;
DEFPROC	cmdInfo
	lea	dx,[bp].V_FNAME
	call	msgName
	test	[bp].V_FLAGS,F_MOD
	jz	cf1
	mov	si,offset MOD_MSG
	call	msgStr
cf1:	mov	si,offset LINE_MSG	; "line N of M"
	call	msgStr
	mov	bx,[bp].V_CUR
	call	countLines
	inc	ax
	call	msgSpNum
	mov	si,offset OF_MSG
	call	msgStr
	mov	bx,[bp].V_LEN
	call	countLines
	call	msgSpNum
	jmp	msgEnd
ENDPROC	cmdInfo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdRedraw (CTRLL)
;
DEFPROC	cmdRedraw
	jmp	clearAll
ENDPROC	cmdRedraw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdZZ (ZZ)
;
DEFPROC	cmdZZ
	call	getKey
	cmp	al,'Z'
	stc
	jne	cz9
	jmp	exX
cz9:	ret
ENDPROC	cmdZZ

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdEx (:)
;
; Supports :n (go to line n), :$, :w [file], :wq [file], :x, :q, :q!, and
; :s/old/new/[g] (with % for every line).
;
DEFPROC	cmdEx
	mov	al,':'
	call	readCmd
	jc	ex9
	call	skipSp
	cmp	al,'0'			; line number?
	jb	ex2			; no
	cmp	al,'9'
	ja	ex2
	sub	cx,cx
ex1:	lodsb
	sub	al,'0'
	cmp	al,9
	ja	ex1a
	cbw
	xchg	ax,cx
	mov	dx,10
	mul	dx
	add	cx,ax
	jmp	ex1
ex1a:	jcxz	ex9
	call	gotoLine
	jmp	short ex2a
ex2:	cmp	al,'$'			; last line?
	jne	ex3			; no
	mov	bx,[bp].V_LEN
	dec	bx
	call	firstNonBlank
ex2a:	mov	[bp].V_CUR,bx
	ret
ex3:	mov	dl,0			; DL = 1 for every line
	cmp	al,'%'
	jne	ex4
	inc	dx
	inc	si
	lodsb
	dec	si
ex4:	cmp	al,'s'
	jne	ex5
	jmp	exSub
ex5:	cmp	al,'q'
	je	exQuit
	cmp	al,'w'
	je	exWrite
	cmp	al,'x'
	je	exX
	mov	si,offset CMD_ERR
	jmp	setMsg
ex9:	ret

exQuit:	cmp	byte ptr [si+1],'!'	; forced?
	je	exq1			; yes
	test	[bp].V_FLAGS,F_MOD
	jz	exq1
	mov	si,offset MOD_ERR
	jmp	setMsg
exq1:	jmp	quit

	DEFLBL	exX,near
	test	[bp].V_FLAGS,F_MOD	; anything to write?
	jz	exq1			; no
	mov	byte ptr [bp].V_LINE,0	; write the current file
	lea	si,[bp].V_LINE
	mov	dh,1			; and quit
	jmp	short exw2

exWrite:inc	si
	mov	dh,0			; DH = 1 to quit
	cmp	byte ptr [si],'q'
	jne	exw1
	inc	dh
	inc	si
exw1:	cmp	byte ptr [si],'!'
	jne	exw1a
	inc	si
exw1a:	call	skipSp
exw2:	push	dx
	call	writeTo
	pop	dx
	jc	ex9
	test	dh,dh
	jnz	exq1
	ret
ENDPROC	cmdEx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; skipSp
;
; Outputs:
;	SI -> first non-blank character, AL = that character
;
DEFPROC	skipSp
sk1:	lodsb
	cmp	al,CHR_SPACE
	je	sk1
	dec	si
	ret
ENDPROC	skipSp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeTo
;
; Writes the file named at SI (or the current file, if it's empty); if there
; was no current file, the name becomes the current file.
;
; Outputs:
;	Carry clear if successful
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	writeTo
	lea	di,[bp].V_FNAME
	cmp	byte ptr [si],0		; name specified?
	jne	wt1			; yes
	mov	si,di
	cmp	byte ptr [si],0		; is there a current file?
	jne	wt3			; yes
	mov	si,offset NAME_ERR
	jmp	setMsg
wt1:	cmp	byte ptr [di],0		; is there a current file?
	jne	wt4			; yes, so this is another file
	mov	cx,MAXNAME-1
wt2:	lodsb
	mov	[di],al
	inc	di
	test	al,al
	loopnz	wt2
	mov	byte ptr [di],0
	lea	si,[bp].V_FNAME
wt3:	mov	dx,si
	call	saveFile
	jc	wt9
	and	[bp].V_FLAGS,NOT F_MOD
	ret
wt4:	mov	dx,si
	call	saveFile
wt9:	ret
ENDPROC	writeTo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; exSub (:s/old/new/[g])
;
; The old text must be found exactly (there are no special characters).
; The affected lines are cut as one change, and then re-inserted with the
; replacements, so a single undo restores them.
;
; Inputs:
;	DL = 1 for every line (otherwise, just the cursor's line)
;	SI -> 's'
;
DEFPROC	exSub
	inc	si
	lodsb				; AL = delimiter
	test	al,al
	jnz	es0
es0a:	mov	si,offset SUB_ERR
	jmp	setMsg
es0:	mov	ah,al
	mov	di,si			; DI -> old text
es1:	lodsb
	test	al,al
	jz	es0a
	cmp	al,ah			; end of the old text?
	jne	es1			; no
	mov	cx,si
	sub	cx,di
	dec	cx			; CX = length of the old text
	jz	es0a
	push	si			; SI -> new text
es2:	lodsb
	test	al,al
	jz	es3
	cmp	al,ah			; end of the new text?
	jne	es2			; no
	mov	byte ptr [si-1],0
	lodsb				; AL = flag, if any
es3:	sub	al,'g'
	mov	[bp].V_SUBG,al		; zero if 'g'
	mov	[bp].V_PATLEN,cx
	mov	si,di
	lea	di,[bp].V_PAT
	push	es
	push	ss
	pop	es
	rep	movsb			; copy the old text to V_PAT
	pop	es
;
; BX = start of the range and CX = its length.
;
	mov	bx,[bp].V_CUR
	call	lineStart
	push	bx
	call	nextLine
	mov	cx,bx
	pop	bx
	test	dl,dl			; every line?
	jz	es4			; no
	sub	bx,bx
	mov	cx,[bp].V_LEN
es4:	sub	cx,bx
	mov	al,[bp].V_FLAGS
	push	ax			; save the flags before the change
	call	beginChange
	sub	ax,ax
	call	cutText
	pop	ax
	mov	dh,al			; DH = saved flags
	pop	di			; DI -> new text
	jc	es9
	mov	[bp].V_CUR,bx
	mov	[bp].V_SUBN,0
	sub	si,si			; SI = offset in the cut text
	mov	dl,0			; DL = 1 after a replacement on a line
es5:	cmp	si,[bp].V_ULEN		; done?
	jae	es7			; yes
	test	dl,dl			; replaced one on this line already?
	jz	es5a			; no
	cmp	[bp].V_SUBG,0		; replacing every match?
	jne	es6			; no
es5a:	call	matchCut		; does the old text match here?
	jc	es6			; no
	add	si,[bp].V_PATLEN
	mov	dl,1
	mov	[bp].V_SUBN,dl
	push	di
es5b:	mov	al,[di]
	inc	di
	test	al,al			; end of the new text?
	jz	es5c			; yes
	call	insChar
	jnc	es5b
es5c:	pop	di
	jc	es7
	jmp	es5
es6:	push	ds
	mov	ds,[bp].V_USEG
	lodsb
	pop	ds
	call	insChar
	jc	es7
	cmp	al,CHR_LINEFEED		; new line?
	jne	es5			; no
	mov	dl,0
	jmp	es5
es7:	call	markAll
	cmp	[bp].V_SUBN,0		; any replacements?
	jne	es9			; yes
	mov	[bp].V_FLAGS,dh		; no, so the text is unchanged
	mov	si,offset FIND_ERR
	jmp	setMsg
es9:	ret
ENDPROC	exSub

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; matchCut
;
; Outputs:
;	Carry clear if V_PAT matches the cut text (in V_USEG) at SI
;
; Modifies:
;	AX, CX
;
DEFPROC	matchCut
	mov	cx,[bp].V_PATLEN
	mov	ax,[bp].V_ULEN
	sub	ax,si
	cmp	ax,cx			; enough text left to match?
	jb	mt9			; no (carry set)
	push	si
	push	di
	push	ds
	push	es
	push	ss
	pop	es
	lea	di,[bp].V_PAT
	mov	ds,[bp].V_USEG
	repe	cmpsb
	pop	es
	pop	ds
	pop	di
	pop	si
	je	mt9			; (carry clear)
	stc
mt9:	ret
ENDPROC	matchCut


;
; Aliases: each key is followed by the motion key, and ALIAS_OPS bytes later
; (in the same order), the operator.
;
ALIASES		db	'x','l','X','h','D','$','C','$','s','l','S','c'
		db	'Y','y',0
ALIAS_OPS	equ	$ - ALIASES
		db	'd',0,'d',0,'d',0,'c',0,'c',0,'c',0,'y'

MOD_MSG		db	" [Modified]",0
LINE_MSG	db	" line",0
OF_MSG		db	" of",0
NAME_ERR	db	"No file name",0
MOD_ERR		db	"No write since last change (add ! to override)",0
CMD_ERR		db	"Unknown command",0
SUB_ERR		db	"Use :s/old/new/ or :s/old/new/g",0
FIND_ERR	db	"Pattern not found",0
NOPAT_ERR	db	"No previous pattern",0

CODE	ENDS

	end
