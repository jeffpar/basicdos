;
; BASIC-DOS Program Editing Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Every line of the loaded program is stored in the program's text blocks as
; a label # (a word, zero if the line has none), a length (a byte), and the
; line's text (without the label # or the space following it).  cmdLoad fills
; the text blocks from a file; the functions here edit them in place: numbered
; lines typed at the prompt (see enterLine), AUTO, DELETE, and EDIT.  LIST and
; SAVE are here, too.
;
; Lines are kept in the order they were loaded (or entered); a new line is
; inserted before the first line with a larger label #, after any unlabeled
; lines that precede it.  An unlabeled line belongs to the nearest labeled
; line preceding it, so LIST and DELETE include it with that line.
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<allocText,freeCache,memError,writeStrCRLF,printCRLF>
	EXTNEAR	<getToken,getFileName,chkExt,addString,openOutput>
	EXTNEAR	<writeOutput,writeError,openError,noFile>
	EXTSTR	<BAS_EXT>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

EDIT_LINE	equ	EDIT_STATE+0	; line # to edit at the next prompt
EDIT_INC	equ	EDIT_STATE+2	; AUTO increment (0 if not AUTO)
MAX_LINE	equ	65529		; largest line # (as in MSBASIC)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdAuto
;
; Process "AUTO [line][,increment]", which prompts for program lines
; beginning with the given line # (default 10), which is advanced by the
; increment (default 10) after each line is entered (see editPrompt).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdAuto
	call	chkProgram
	jc	au9
	mov	al,','
	call	getRange		; AX = line #, DX = increment
	jc	au9
	jcxz	au1			; no comma, so use the default
	cmp	dx,-1			; was an increment specified?
	jne	au2			; yes
au1:	mov	dx,10
au2:	test	ax,ax			; was a line # specified?
	jnz	au3			; yes
	mov	ax,10
au3:	mov	[bx].EDIT_LINE,ax
	mov	[bx].EDIT_INC,dx
au9:	ret
ENDPROC	cmdAuto

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDelete
;
; Process "DELETE [line][-[line]]", which deletes the specified range of
; lines (at least one line # must be specified).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDelete
	call	chkProgram
	jc	de9
	mov	al,'-'
	call	getRange		; AX = 1st line #, DX = last line #
	jc	de9
	inc	dx			; was a last line # specified?
	jnz	de1			; yes
	test	ax,ax			; was a 1st line # specified?
	jnz	de1			; yes
	jmp	syntaxError		; no
de1:	dec	dx
	call	freeCache		; (the program must be recompiled)
	mov	si,offset delLine
	jmp	walkLines
de9:	ret
ENDPROC	cmdDelete

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdEdit
;
; Process "EDIT line", which displays the line for editing at the next prompt
; (see editPrompt).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdEdit
	call	chkProgram
	jc	ed9
	mov	al,'-'
	call	getRange		; AX = line #
	jc	ed9
	xchg	dx,ax			; DX = line #
	call	findLine
	jc	ed8			; not found
	jne	ed8			; not found
	mov	[bx].EDIT_LINE,dx
	mov	word ptr [bx].EDIT_INC,0
	ret
ed8:	PRINTF	<"Undefined line number",13,10,13,10>
	stc
ed9:	ret
ENDPROC	cmdEdit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdList
;
; Process "LIST [line][-[line]]", which lists the specified range of lines
; (or all lines).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdList
	mov	al,'-'
	call	getRange		; AX = 1st line #, DX = last line #
	jc	de9
	mov	si,offset listLine
	jmp	short walkLines
ENDPROC	cmdList

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdSave
;
; Process "SAVE file", which saves the loaded program as a text file (with
; a BAS extension if none is specified).
;
; The file is closed here, rather than by cleanUp, so that we can report a
; failure to update the file's directory entry (ie, its size).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdSave
	mov	dl,[bx].CMD_ARG
	sub	cx,cx			; (no default filename)
	call	getFileName		; DS:SI -> filename, CX = length
	jnc	sv1
	jmp	noFile
sv1:	call	chkExt			; does the filename have an extension?
	jnc	sv2			; yes
	mov	dx,offset BAS_EXT	; no, so add one
	call	addString
sv2:	call	openOutput
	jnc	sv3
	jmp	openError		; report error (AX) opening file (SI)
sv3:	sub	ax,ax
	mov	dx,-1			; save every line
	mov	si,offset saveLine
	call	walkLines
	jc	sv9			; (the error was reported)
	push	bx
	mov	bx,[bx].HDL_OUTPUT
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	bx
	jnc	sv9
	jmp	writeError
sv9:	ret
ENDPROC	cmdSave

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; walkLines
;
; Calls a function for every line whose label # (or if it has none, the
; label # of the nearest labeled line preceding it) is within a range.
;
; Inputs:
;	BX -> CMDHEAP
;	AX = 1st line #
;	DX = last line #
;	SI = function (called with ES:DI -> line and CX = its length; it
;	must return DI -> next line (or carry set to stop), and preserve BX)
;
; Outputs:
;	Carry set if the function stopped the walk
;
; Modifies:
;	Any but BX
;
DEFPROC	walkLines
	push	bp
	push	si			; [bp+6]: function
	push	dx			; [bp+4]: last line #
	push	ax			; [bp+2]: 1st line #
	sub	ax,ax
	push	ax			; [bp]: label # of the current line
	mov	bp,sp
	call	firstLine
wl1:	jc	wl8			; no more lines
	test	ax,ax			; does the line have a label #?
	jz	wl2			; no
	mov	[bp],ax			; yes, so it's the current label #
wl2:	mov	ax,[bp]
	cmp	ax,[bp+2]
	jb	wl3			; before the range
	cmp	ax,[bp+4]
	ja	wl3			; after the range
	call	word ptr [bp+6]		; call the function
	jc	wl9
	call	getLine			; ES:DI -> next line
	jmp	wl1
wl3:	call	nextLine
	jmp	wl1
wl8:	clc
wl9:	lea	sp,[bp+8]		; (LEA preserves the carry flag)
	pop	bp
	ret
ENDPROC	walkLines

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; listLine
;
; Lists a line (see walkLines).
;
; Inputs:
;	ES:DI -> line
;
; Outputs:
;	DI -> next line (carry clear)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	listLine
	mov	ax,es:[di]
	test	ax,ax			; does the line have a label #?
	jz	li1			; no
	PRINTF	<"%5u">,ax
li1:	PRINTF	<CHR_TAB>
	push	ds
	push	es
	pop	ds
	lea	si,[di+2]		; DS:SI -> length-prefixed text
	call	writeStrCRLF
	mov	di,si
	pop	ds
	clc
	ret
ENDPROC	listLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; saveLine
;
; Writes a line to the output file (see walkLines).
;
; Inputs:
;	BX -> CMDHEAP
;	ES:DI -> line
;
; Outputs:
;	DI -> next line (carry set if error)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	saveLine
	mov	ax,es:[di]
	test	ax,ax			; does the line have a label #?
	jz	sa1			; no
	push	es
	push	di
	push	ds
	pop	es
	lea	di,[bx].LINEBUF
	mov	si,di
	call	putNum			; store the label # and a space
	mov	cx,di
	sub	cx,si			; CX = # of characters
	pop	di
	pop	es
	call	writeOutput		; write them
	jc	sa9
sa1:	push	ds
	push	es
	pop	ds
	lea	si,[di+2]
	lodsb
	mov	ah,0
	xchg	cx,ax			; DS:SI -> text, CX = length
	jcxz	sa2
	call	writeOutput		; write the text
sa2:	pop	ds
	jc	sa9
	add	si,cx
	mov	di,si			; DI -> next line
	mov	ax,(CHR_LINEFEED SHL 8) OR CHR_RETURN
	push	ax
	mov	si,sp
	mov	cl,2
	call	writeOutput		; write CR/LF from the stack
	pop	ax
sa9:	ret
ENDPROC	saveLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; syntaxError
;
; Outputs:
;	Carry set
;
; Modifies:
;	AX
;
DEFPROC	syntaxError
	PRINTF	<"Syntax error",13,10,13,10>
	stc
	ret
ENDPROC	syntaxError

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getRange
;
; Parses the optional range argument of AUTO, DELETE, EDIT, and LIST (eg,
; "10", "10-", "-20", or "10-20"; AUTO separates its values with a comma).
;
; Inputs:
;	AL = separator
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	If carry clear, AX = 1st value (0 if none), DX = 2nd value (0FFFFh if
;	none, or the 1st value if there was no separator), and CX = 0 if there
;	was a value but no separator; otherwise, carry set (and a message was
;	printed)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	getRange
	push	ax
	mov	dl,1			; DL = 1st arg (not CMD_ARG, since a
	call	getToken		; range like "-20" looks like a switch)
	pop	dx			; DL = separator
	jnc	gr1
	sub	ax,ax			; no token, so the range is everything
	mov	dx,-1
	mov	cx,dx
	ret
gr1:	add	cx,si			; CX -> end of token
	call	getNum			; AX = 1st value
	cmp	[si],dl			; followed by the separator?
	mov	dx,ax			; (if not, the 2nd value is the 1st)
	jne	gr3			; no
	inc	si
	push	ax
	mov	dx,si
	call	getNum			; AX = 2nd value
	cmp	si,dx			; any digits?
	xchg	dx,ax			; DX = 2nd value
	jne	gr2			; yes
	mov	dx,-1			; no, so there's no limit
gr2:	pop	ax
	cmp	si,cx			; was the entire token used?
	jne	syntaxError		; no
	ret				; (carry clear, CX non-zero)
gr3:	cmp	si,cx			; was the entire token used?
	jne	syntaxError		; no
	sub	cx,cx			; CX = 0 (no separator, carry clear)
	ret
ENDPROC	getRange

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNum
;
; Converts the decimal digits (if any) at DS:SI to a value; values larger
; than MAX_LINE are limited to 65530-65539, so they're never valid line #s.
;
; Inputs:
;	DS:SI -> digits
;
; Outputs:
;	AX = value (0 if no digits), DS:SI -> first non-digit
;
; Modifies:
;	AX, SI
;
DEFPROC	getNum
	push	dx
	sub	dx,dx
gn1:	lodsb
	sub	al,'0'
	cmp	al,10			; decimal digit?
	jae	gn9			; no
	cbw
	xchg	ax,dx			; AX = value, DX = digit
	cmp	ax,MAX_LINE / 10 + 1
	jb	gn2
	mov	ax,MAX_LINE / 10 + 1	; (the result stays invalid)
gn2:	add	ax,ax
	add	dx,ax			; DX = value * 2 + digit
	add	ax,ax
	add	ax,ax
	add	dx,ax			; DX = value * 10 + digit
	jmp	gn1
gn9:	dec	si
	xchg	ax,dx
	pop	dx
	ret
ENDPROC	getNum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; putNum
;
; Stores a value in decimal, followed by a space.
;
; Inputs:
;	AX = value
;	ES:DI -> buffer
;
; Outputs:
;	ES:DI -> next byte in buffer
;
; Modifies:
;	AX, DI
;
DEFPROC	putNum
	push	cx
	push	dx
	mov	cx,10
	push	cx			; push a non-digit (10) as a marker
pn1:	sub	dx,dx
	div	cx
	push	dx			; push the next digit
	test	ax,ax
	jnz	pn1
pn2:	pop	ax
	add	al,'0'
	cmp	al,'0'+10		; was it the marker?
	je	pn3			; yes
	stosb
	jmp	pn2
pn3:	mov	al,CHR_SPACE
	stosb
	pop	dx
	pop	cx
	ret
ENDPROC	putNum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkProgram
;
; Used by commands that can't be used while a program is running.
;
; Inputs:
;	BX -> CMDHEAP
;
; Outputs:
;	Carry set if a program is running (and a message was printed)
;
; Modifies:
;	AX
;
DEFPROC	chkProgram
	cmp	[bx].CBLKDEF.BDEF_NEXT,0; is a program running?
	je	cp9			; no (carry clear)
	PRINTF	<"Not allowed in a program",13,10,13,10>
	stc
cp9:	ret
ENDPROC	chkProgram

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; editPrompt
;
; Called by the main loop instead of prompting for a command when there's a
; line to edit (see cmdAuto and cmdEdit): the input buffer is filled with the
; line # and the line's text (if any), and displayed for editing.  If AUTO is
; active, a numbered line is added to the program and the next line # is set;
; anything else (including a numbered line with no text) ends AUTO.
;
; Inputs:
;	AX = line # to edit
;	BX -> CMDHEAP
;	DS = ES = SS
;
; Outputs:
;	Carry set if the input was processed; otherwise, carry clear (and the
;	input in INPUTBUF should be processed as usual)
;
; Modifies:
;	Any but BX
;
DEFPROC	editPrompt
	xchg	dx,ax			; DX = line #
	call	findLine		; ES:DI -> line, if any
	mov	si,di
	jc	ep1			; not found
	je	ep2			; found (CX = length)
ep1:	sub	cx,cx			; no text
ep2:	push	ds
	push	es
	push	ds
	pop	es
	lea	di,[bx].INPUTBUF.INP_DATA
	xchg	ax,dx
	call	putNum			; store the line # and a space
	pop	ds
	add	si,3			; DS:SI -> line's text
	lea	ax,[bx].INPUTBUF.INP_DATA + 254
	sub	ax,di			; AX = room left (INP_CNT max is 254)
	cmp	cx,ax
	jbe	ep3
	xchg	cx,ax
ep3:	rep	movsb
	pop	ds
	lea	ax,[bx].INPUTBUF.INP_DATA
	sub	di,ax
	xchg	ax,di
	mov	[bx].INPUTBUF.INP_CNT,al
	lea	dx,[bx].INPUTBUF
	mov	[bx].INPUT_BUF,dx
	sub	ax,ax
	mov	[bx].EDIT_LINE,ax	; (so that CTRLC ends any editing)
	xchg	ax,[bx].EDIT_INC	; AX = AUTO increment, if any
	push	ax
	DOSUTIL	EDITLN,2		; display and edit the line
	call	printCRLF
	pop	dx			; DX = AUTO increment
	test	dx,dx			; AUTO?
	jz	ep9			; no (carry clear)
	lea	si,[bx].INPUTBUF.INP_DATA
	mov	cl,[bx].INPUTBUF.INP_CNT
	push	dx
	call	parseLine		; AX = line #, CX = length of text
	pop	dx
	jc	ep8			; not a numbered line, so AUTO is done
	jcxz	ep7			; no text, so AUTO is done
	push	ax
	push	dx
	call	storeLine
	pop	dx
	pop	ax
	jc	ep7
	add	ax,dx			; AX = next line #
	jc	ep7
	cmp	ax,MAX_LINE
	ja	ep7
	mov	[bx].EDIT_LINE,ax
	mov	[bx].EDIT_INC,dx
ep7:	stc
	jmp	short ep9
ep8:	clc
ep9:	push	ss
	pop	es
	ret
ENDPROC	editPrompt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; enterLine
;
; Called by the main loop with every line of input: if the line begins with
; a line # (followed by a space or nothing), it's added to the program,
; replacing any line with the same #; if nothing follows the line #, the line
; with that # is deleted.
;
; Inputs:
;	BX -> CMDHEAP
;	DS:SI -> input (with length CL)
;
; Outputs:
;	Carry set if not a numbered line (SI and CL unchanged); otherwise,
;	carry clear (the line was processed)
;
; Modifies:
;	AX, DX (and anything but BX, DS, and ES if carry clear)
;
DEFPROC	enterLine
	call	parseLine
	jc	el9
	push	es
	call	storeLine
	pop	es
	clc
el9:	ret
ENDPROC	enterLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parseLine
;
; Inputs:
;	DS:SI -> input (with length CL)
;
; Outputs:
;	If carry clear, AX = line #, DS:SI -> text, CX = length of text;
;	otherwise, the input doesn't begin with a line # (SI and CL unchanged)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	parseLine
	mov	dx,si
	call	getNum			; AX = line #, SI -> next character
	cmp	si,dx			; any digits?
	je	pl8			; no
	cmp	byte ptr [si],CHR_SPACE	; followed by a space or nothing?
	ja	pl8			; no
	jb	pl1
	inc	si			; skip one space (as cmdLoad does)
pl1:	mov	ch,0
	add	cx,dx			; CX -> end of input
	sub	cx,si			; CX = length of text (carry clear)
	ret
pl8:	mov	si,dx
	stc
	ret
ENDPROC	parseLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; storeLine
;
; Adds a line to the program, replacing any line with the same label #; if
; the line has no text, the line with that label # (if any) is deleted.
;
; Inputs:
;	AX = line #
;	BX -> CMDHEAP
;	DS:SI -> text (with length CX)
;
; Outputs:
;	Carry set if error (and a message was printed)
;
; Modifies:
;	Any but BX and DS
;
DEFPROC	storeLine
	dec	ax
	cmp	ax,MAX_LINE		; is the line # valid (1-MAX_LINE)?
	inc	ax
	jae	sl8			; no
	xchg	dx,ax			; DX = line #
	mov	[bx].ERR_CODE,0		; (so that memError reports errors)
	push	cx
	push	si
	call	freeCache		; (the program must be recompiled)
	cmp	[bx].TBLKDEF.BLK_NEXT,0	; does the program have a text block?
	jne	sl1			; yes (carry clear)
	call	allocText		; no, so allocate one
sl1:	pop	si
	pop	cx
	jc	sl9
	push	cx
	push	si
	call	findLine		; ES:DI -> line, if any
	pop	si
	pop	cx
	jc	sl2			; not found
	jne	sl2			; not found
	call	delLine			; delete the existing line
sl2:	jcxz	sl7			; nothing to insert
	jmp	short insLine
sl7:	clc
sl9:	ret
sl8:	jmp	syntaxError
ENDPROC	storeLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; insLine
;
; Inserts a line at ES:DI.  If the text block doesn't have enough room, it's
; split in two (see splitBlock), and the line is added to the end of the first
; block or, if it still doesn't fit, to the start of the second.
;
; Inputs:
;	BX -> CMDHEAP
;	DX = label #
;	DS:SI -> text (with length CX)
;	ES:DI -> insertion point
;
; Outputs:
;	Carry set if error (and a message was printed)
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	insLine
	call	tryLine
	jnc	il9
	call	splitBlock
	jc	il9
	call	tryLine			; try the end of the current block
	jnc	il9
	mov	es,es:[BLK_NEXT]
	mov	di,size TBLK
	call	tryLine			; and then the start of the next one
	jnc	il9
	jmp	memError
il9:	ret
ENDPROC	insLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tryLine
;
; Inputs:
;	DX = label #
;	DS:SI -> text (with length CX)
;	ES:DI -> insertion point
;
; Outputs:
;	Carry set if there's not enough room in the text block (no changes);
;	otherwise, carry clear and the line was inserted
;
; Modifies:
;	AX (and CX, SI, DI if successful)
;
DEFPROC	tryLine
	push	si
	mov	si,es:[BLK_FREE]	; SI = end of the block's lines
	mov	ax,si
	add	ax,cx
	add	ax,3			; AX = new end
	cmp	es:[BLK_SIZE],ax	; enough room?
	jb	tl9			; no
	mov	es:[BLK_FREE],ax
	push	cx
	push	di
	push	ds
	mov	cx,si
	sub	cx,di			; CX = # bytes to move (carry clear)
	dec	si			; SI -> last byte to move
	xchg	di,ax
	dec	di			; DI -> its new location
	push	es
	pop	ds
	std
	rep	movsb			; make room for the line
	cld
	pop	ds
	pop	di
	pop	cx
	xchg	ax,dx
	stosw				; store the label #
	xchg	ax,dx
	mov	al,cl
	stosb				; store the length
tl9:	pop	si
	jc	tl10
	rep	movsb			; and store the text
tl10:	ret
ENDPROC	tryLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; splitBlock
;
; Moves all the lines at ES:DI onward to a new text block, which (because
; allocText adds it to the end of the chain) we move to follow ES.
;
; Inputs:
;	BX -> CMDHEAP
;	ES:DI -> split point
;
; Outputs:
;	Carry set if error (and a message was printed); ES:DI unchanged
;
; Modifies:
;	AX
;
DEFPROC	splitBlock
	push	cx
	push	dx
	push	si
	push	di
	push	es
	mov	cx,di			; CX = split point
	mov	dx,es			; DX = current block
	call	allocText		; ES:DI -> new block
	jc	sb9
	push	ds
	mov	si,cx			; SI = split point
	mov	ax,es			; AX = new block
	mov	ds,dx			; DS = current block
	mov	cx,ds:[BLK_NEXT]
	cmp	cx,ax			; is the new block next already?
	je	sb2			; yes
	mov	ds:[BLK_NEXT],ax	; no, so insert it here
	mov	es:[BLK_NEXT],cx
sb1:	mov	ds,cx			; and remove it from the end
	mov	cx,ds:[BLK_NEXT]
	cmp	cx,ax
	jne	sb1
	mov	word ptr ds:[BLK_NEXT],0
	mov	ds,dx
sb2:	mov	cx,ds:[BLK_FREE]
	sub	cx,si			; CX = # bytes to move
	mov	ax,di
	add	ax,cx
	cmp	es:[BLK_SIZE],ax	; enough room in the new block?
	jb	sb8			; no
	mov	es:[BLK_FREE],ax
	mov	ds:[BLK_FREE],si
	rep	movsb
sb8:	pop	ds
	jnc	sb9
	call	memError
sb9:	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	ret
ENDPROC	splitBlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; delLine
;
; Deletes a line (see walkLines, too).
;
; Inputs:
;	ES:DI -> line
;
; Outputs:
;	DI -> next line (carry clear)
;
; Modifies:
;	AX
;
DEFPROC	delLine
	push	cx
	push	si
	push	di
	push	ds
	mov	al,es:[di+2]
	mov	ah,0
	add	ax,3			; AX = size of the line
	mov	si,di
	add	si,ax			; SI -> next line
	mov	cx,es:[BLK_FREE]
	sub	es:[BLK_FREE],ax
	sub	cx,si			; CX = # bytes to move (carry clear)
	push	es
	pop	ds
	rep	movsb
	pop	ds
	pop	di
	pop	si
	pop	cx
	ret
ENDPROC	delLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findLine
;
; Finds the first line whose label # is greater than or equal to DX.
;
; Inputs:
;	BX -> CMDHEAP
;	DX = line #
;
; Outputs:
;	If carry clear, ES:DI -> line, CX = its length, and ZF set if its label
;	# is DX; otherwise, ES:DI -> end of the last text block (if any)
;
; Modifies:
;	AX, CX, DI, ES
;
DEFPROC	findLine
	call	firstLine
fl1:	jc	fl9
	test	ax,ax			; does the line have a label #?
	jz	fl2			; no
	cmp	ax,dx
	jae	fl9			; (ZF set if equal)
fl2:	call	nextLine
	jmp	fl1
fl9:	ret
ENDPROC	findLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; firstLine (nextLine, getLine)
;
; Inputs:
;	BX -> CMDHEAP (firstLine)
;	ES:DI -> current line, CX = its length (nextLine)
;	ES:DI -> next line, or the end of a text block (getLine)
;
; Outputs:
;	If carry clear, ES:DI -> line, AX = label #, CX = length; otherwise,
;	ES:DI -> end of the last text block (if any)
;
; Modifies:
;	AX, CX, DI, ES
;
DEFPROC	firstLine
	mov	cx,[bx].TBLKDEF.BLK_NEXT
	stc
	jcxz	nl9			; no text blocks
	mov	es,cx
	mov	di,size TBLK
	jmp	short nl1
	DEFLBL	nextLine,near
	add	di,cx
	add	di,3			; skip the label #, length, and text
	DEFLBL	getLine,near
nl1:	cmp	es:[BLK_FREE],di	; still in the same text block?
	ja	nl2			; yes (carry clear)
	mov	cx,es:[BLK_NEXT]
	stc
	jcxz	nl9			; no more text blocks
	mov	es,cx
	mov	di,size TBLK
	jmp	nl1
nl2:	mov	ax,es:[di]		; AX = label #
	mov	cl,es:[di+2]
	mov	ch,0			; CX = length
nl9:	ret
ENDPROC	firstLine

CODE	ENDS

	end
