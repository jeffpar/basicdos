;
; BASIC-DOS File I/O Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for CLOSE, FIELD, GET #, INPUT [#], LINE INPUT [#], LSET,
; OPEN, PRINT #, PUT #, RSET, and WRITE (see genfile.asm), and for the CVD,
; CVI, CVL, EOF, LOC, LOF, MKD$, MKI$, and MKL$ functions.
;
; Each OPEN file (#1 to #FILE_MAX) has a FILE_SLOT-byte slot in FILE_DATA,
; with its handle (0 if the file isn't open), its mode (FM_*), and for random
; access, its record length, the last record # used, and a far pointer to its
; FIELD table (see setField); a file opened by a program is closed when the
; command that ran the program ends, along with its handle (see syncFiles).
;
; Nothing is buffered between statements: INPUT # and LINE INPUT # read a
; chunk of the file into LINEBUF, take the next item (or line) from it, and
; seek back to the end of that item, and GET # and PUT # build each record in
; LINEBUF, so there's nothing to discard (or keep in sync) when another
; command or program runs.  INPUT and LINE INPUT (from the keyboard) read a
; line into LINEBUF and take items from it, much like INPUT # (see inputLine).
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<rtError,allocStr,releaseStr,openMode,setStr>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

FILE_MAX	equ	4		; max OPEN files (#1-#4)
FILE_SLOT	equ	10		; size of each file's slot
FS_RLEN		equ	FILE_DATA+2	; record length (byte)
FS_REC		equ	FILE_DATA+4	; last record # (word)
FS_FIELDS	equ	FILE_DATA+6	; FIELD table (dword; see setField)
FILE_CUR	equ	FILE_DATA+40	; handle for INPUT (see selectInput)
FILE_POS	equ	FILE_DATA+42	; position in the INPUT line (byte)
KBD_HDL		equ	0FFh		; FILE_CUR "handle" for INPUT

FM_INPUT	equ	01h		; masks for getFile (1 SHL mode)
FM_OUTPUT	equ	02h
FM_APPEND	equ	04h
FM_RANDOM	equ	08h

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openFile
;
; Used by "OPEN file [FOR INPUT|OUTPUT|APPEND|RANDOM] AS #n [LEN=reclen]".
; As in MSBASIC, an error is a runtime error (eg, "File not found"), which
; ON ERROR can handle.  A random access file's record length must be from 1
; to 255 (since GET # and PUT # build records in LINEBUF).
;
; Inputs:
;	string value (popped)
;	16-bit mode (popped): 0 for INPUT, 1 for OUTPUT, 2 for APPEND, 3 for
;	RANDOM (as OPEN without FOR implies)
;	32-bit file number (popped)
;	32-bit record length (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	openFile,FAR
	ARGVAR	pName,dword
	ARGVAR	wMode,word
	ARGVAR	lNum,dword
	ARGVAR	lRecLen,dword
	ENTER
	push	ds
	mov	ax,[lNum].LOW
	call	getSlot			; SS:BX -> slot
	mov	al,55			; "File already open"
	cmp	ss:[bx].FILE_DATA,0
	jne	of9
	mov	ax,[lRecLen].LOW
	dec	ax
	or	ax,[lRecLen].HIW
	cmp	ax,255			; is the record length 1-255?
	mov	al,5			; "Illegal function call"
	jae	of9			; no
	push	ss
	pop	es
	mov	di,ss:[PSP_HEAP]
	lea	di,[di].LINEBUF
	mov	dx,di			; ES:DX -> LINEBUF
	lds	si,[pName]		; DS:SI -> filename
	sub	cx,cx
	test	si,si			; empty string?
	jz	of1			; yes
	lodsb
	mov	cl,al
	rep	movsb			; copy the filename to LINEBUF
of1:	xchg	ax,cx
	stosb				; and null-terminate it
	les	di,[pName]
	call	releaseStr
	push	ss
	pop	ds			; DS:DX -> filename
	mov	ax,[wMode]
	push	ax
	call	openMode		; AX = handle
	pop	cx			; CL = mode
	jc	of8
	mov	ah,cl
	mov	word ptr ss:[bx].FILE_DATA,ax	; record the handle and mode
	mov	ax,[lRecLen].LOW
	mov	word ptr ss:[bx].FS_RLEN,ax	; record length
	sub	ax,ax
	mov	word ptr ss:[bx].FS_REC,ax	; no records used yet
	mov	word ptr ss:[bx].FS_FIELDS+2,ax	; and no FIELD table
	pop	ds
	LEAVE
	RETURN
of8:	mov	cl,55			; "File already open" (elsewhere)
	cmp	al,ERR_SHARE
	je	of8a
	mov	cl,53			; "File not found"
	cmp	al,ERR_NOFILE
	je	of8a
	mov	cl,75			; "Path/File access error"
of8a:	xchg	ax,cx
of9:	jmp	rtError
ENDPROC	openFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; closeFile
;
; Used by "CLOSE [#n]", which closes file n, or all files if n is zero.
; Closing a file that isn't open does nothing.
;
; Inputs:
;	32-bit file number (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	closeFile,FAR
	ARGVAR	lCloseNum,dword
	ENTER
	mov	ax,[lCloseNum].LOW
	test	ax,ax			; all files?
	jnz	cf2			; no
	mov	cx,FILE_MAX
cf1:	mov	ax,cx
	call	closeSlot
	loop	cf1
	jmp	short cf9
cf2:	call	closeSlot
cf9:	LEAVE
	RETURN
ENDPROC	closeFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; closeSlot
;
; Inputs:
;	AX = file number
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX
;
DEFPROC	closeSlot
	call	getSlot			; SS:BX -> slot
	mov	al,0
	xchg	al,ss:[bx].FILE_DATA	; AL = handle (and zero it)
	test	al,al			; was the file open?
	jz	cs9			; no
	mov	bl,al
	mov	bh,0			; BX = handle
	mov	ah,DOS_HDL_CLOSE
	int	21h
cs9:	ret
ENDPROC	closeSlot

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileOut
;
; Used by "PRINT #n" and "WRITE #n" to make file n STDOUT (like redirOut,
; which does the same for ":>"), until redirEnd restores STDOUT; the handle
; that we record for redirEnd to close is 0FFh, which isn't a valid handle,
; so the file stays open.
;
; Inputs:
;	32-bit file number (popped)
;	[pOutW] -> redirection word (in the code block)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	fileOut,FAR
	ARGVAR	lOutNum,dword
	ARGVAR	pOutW,dword
	ENTER
	mov	ax,[lOutNum].LOW
	mov	dl,FM_OUTPUT OR FM_APPEND
	call	getFile			; AL = handle
	mov	bl,al
	mov	bh,0
	mov	al,ss:[PSP_PFT][bx]	; AL = SFH of the file
	xchg	al,ss:[PSP_PFT][STDOUT]	; AL = previous STDOUT SFH
	mov	ah,0FFh			; AH = handle for redirEnd
	les	di,[pOutW]
	stosw				; record the redirection
	LEAVE
	RETURN
ENDPROC	fileOut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; selectInput
;
; Used by "INPUT #n" and "LINE INPUT #n" to select file n for fileItem.
;
; Inputs:
;	32-bit file number (popped)
;	16-bit flag (popped): 0 for INPUT #, 1 for LINE INPUT #
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	selectInput,FAR
	ARGVAR	lInNum,dword
	ARGVAR	wInLine,word
	ENTER
	mov	ax,[lInNum].LOW
	mov	dl,FM_INPUT
	call	getFile			; AL = handle
	mov	cx,[wInLine]
	mov	ah,cl
	mov	bx,ss:[PSP_HEAP]
	mov	word ptr ss:[bx].FILE_CUR,ax
	LEAVE
	RETURN
ENDPROC	selectInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileItem
;
; Used by "INPUT #" (and "LINE INPUT #") for each variable, to get the next
; item (or line) of the file selected by selectInput, as a string; genReadVars
; then converts it to the variable's type, as READ does with DATA items.
;
; As in MSBASIC, leading spaces, tabs, CRs, and LFs are skipped, and an item
; ends at a comma, CR, or LF, or for a numeric variable, a space or tab, too;
; a quoted item ends at its closing quote, and may contain commas.  A line
; (for LINE INPUT #) ends at a CR or LF.  CRLF counts as one delimiter, and
; a CTRLZ marks the end of the file.  Reading past the end of the file is an
; "Input past end" error.
;
; Inputs:
;	32-bit return value
;	16-bit variable type (popped)
;
; Outputs:
;	32-bit return value updated (the item's string value)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	fileItem,FAR
	RETVAR	retFI,dword
	ARGVAR	wFIType,word
	LOCVAR	fiEnd,word		; end of the data read
	LOCVAR	fiFile,word		; handle and LINE flag
	ENTER
	push	ds
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	bx,ds:[PSP_HEAP]
	mov	ax,word ptr [bx].FILE_CUR
	mov	[fiFile],ax
;
;
; Read as much of the file as LINEBUF will hold, up to any CTRLZ, unless
; it's INPUT (from the keyboard), which already read a line into LINEBUF.
;
fi0:	mov	bx,ds:[PSP_HEAP]
	cmp	al,KBD_HDL		; keyboard?
	jne	fi0a			; no
	lea	si,[bx].LINEBUF+1
	lodsb				; AL = # characters
	mov	ah,0
	mov	di,si
	add	di,ax			; DI -> end of the line
	mov	[fiEnd],di
	mov	al,[bx].FILE_POS
	add	si,ax			; SI -> next character
	jmp	short fi2
fi0a:	lea	dx,[bx].LINEBUF		; DS:DX -> LINEBUF
	mov	bx,[fiFile]
	mov	bh,0			; BX = handle
	mov	cx,255
	mov	ah,DOS_HDL_READ
	int	21h			; AX = # bytes read
	jnc	fi1
	sub	ax,ax			; (treat an error like the end)
fi1:	mov	si,dx			; SI -> data
	xchg	cx,ax			; CX = # bytes read
	mov	di,si
	add	di,cx
	mov	[fiEnd],di		; save the end of the data
	mov	di,si
	jcxz	fi2
	mov	al,CHR_CTRLZ
	repne	scasb			; any CTRLZ?
	jne	fi2			; no (DI -> end of data)
	dec	di			; yes (DI -> CTRLZ)
fi2:	mov	dx,[wFIType]		; DL = variable type
	mov	ax,[fiFile]
	test	ah,ah			; LINE INPUT?
	jz	fi3			; no
	jmp	fi7			; yes
;
; Skip leading whitespace, and then find the end of the item.
;
fi3:	cmp	si,di
	jae	fiEOF
	lodsb
	cmp	al,' '
	je	fi3
	cmp	al,CHR_TAB
	je	fi3
	cmp	al,CHR_RETURN
	je	fi3
	cmp	al,CHR_LINEFEED
	je	fi3
	dec	si
	mov	cx,si			; CX -> start of item
	cmp	al,'"'			; quoted item?
	jne	fi5			; no
	inc	si
	inc	cx
fi4:	cmp	si,di			; find the closing quote
	jae	fi4a
	lodsb
	cmp	al,'"'
	jne	fi4
	dec	si
fi4a:	mov	bx,si			; BX -> end of item
	cmp	si,di
	jae	fi4c
	inc	si			; skip the closing quote
fi4b:	cmp	si,di			; and anything up to the delimiter
	jae	fi4c
	lodsb
	cmp	al,','
	je	fi4c
	cmp	al,CHR_RETURN
	je	fi4d
	cmp	al,CHR_LINEFEED
	jne	fi4b
fi4c:	jmp	fi9
fi4d:	jmp	fi8a
;
; If we ran out of data, but LINEBUF was full (eg, of blank lines), there
; may be more, so read again; otherwise, we're at the end of the file.
;
fiEOF:	mov	cx,si
	mov	bx,si			; (an empty item)
	mov	ax,[fiFile]
	cmp	al,KBD_HDL		; keyboard?
	je	fi4c			; yes, so the item is empty
	cmp	di,[fiEnd]		; did a CTRLZ end the data?
	jne	fiX			; yes
	mov	bx,ds:[PSP_HEAP]
	lea	ax,[bx].LINEBUF + 255
	cmp	ax,di			; was LINEBUF full?
	jne	fiX			; no
	mov	ax,[fiFile]
	jmp	fi0			; yes, so read more
fiX:	mov	al,62			; "Input past end"
	jmp	rtError

fi5:	cmp	si,di			; find the end of the unquoted item
	jae	fi6
	mov	al,[si]
	cmp	al,','
	je	fi6
	cmp	al,CHR_RETURN
	je	fi6
	cmp	al,CHR_LINEFEED
	je	fi6
	cmp	dl,VAR_STR		; string variable?
	je	fi5a			; yes (spaces don't end the item)
	cmp	al,' '
	je	fi6
	cmp	al,CHR_TAB
	je	fi6
fi5a:	inc	si
	jmp	fi5
fi6:	mov	bx,si			; BX -> end of item
fi6a:	cmp	bx,cx			; remove trailing whitespace
	jbe	fi8
	mov	al,[bx-1]
	cmp	al,' '
	je	fi6b
	cmp	al,CHR_TAB
	jne	fi8
fi6b:	dec	bx
	jmp	fi6a
;
; LINE INPUT # takes everything up to the end of the line.
;
fi7:	cmp	si,di
	jae	fiEOF
	mov	cx,si			; CX -> start of line
fi7a:	cmp	si,di
	jae	fi7b
	mov	al,[si]
	cmp	al,CHR_RETURN
	je	fi7b
	cmp	al,CHR_LINEFEED
	je	fi7b
	inc	si
	jmp	fi7a
fi7b:	mov	bx,si			; BX -> end of line
;
; Consume the delimiter at SI (if any), and if it's a CR, a following LF.
;
fi8:	cmp	si,di
	jae	fi9
	lodsb
	cmp	al,CHR_RETURN
	jne	fi9
fi8a:	cmp	si,di
	jae	fi9
	cmp	byte ptr [si],CHR_LINEFEED
	jne	fi9
	inc	si
;
; The item is from CX to BX, and SI is the end of what we used, so seek back
; over the rest of the data, and then return the item as a string.
;
fi9:	push	cx
	push	bx
	mov	ax,[fiFile]
	cmp	al,KBD_HDL		; keyboard?
	jne	fi9b			; no
	mov	bx,ds:[PSP_HEAP]
	lea	ax,[bx].LINEBUF+2
	sub	ax,si
	neg	ax
	mov	[bx].FILE_POS,al	; save the position in the line
	jmp	short fi9a
fi9b:	mov	dx,[fiEnd]
	sub	dx,si			; DX = # bytes not used
	jz	fi9a
	neg	dx
	mov	cx,-1			; CX:DX = -DX
	mov	bx,[fiFile]
	mov	bh,0			; BX = handle
	mov	ax,DOS_HDL_SEEKCUR
	int	21h
fi9a:	pop	cx
	pop	si			; SI -> start of item
	sub	cx,si			; CX = length of item
	sub	ax,ax
	cwd				; DX:AX = empty string
	jcxz	fi10
	call	allocStr		; ES:DI -> new string
	mov	ax,di
	mov	dx,es			; DX:AX = string value
	inc	di
	rep	movsb			; copy the item to it
fi10:	mov	[retFI].OFF,ax
	mov	[retFI].SEG,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	fileItem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeValue
;
; Used by "WRITE [#n,]" for each value: numbers are written without leading
; or trailing spaces, strings are written in quotes, and the values are
; separated by commas, ending with CRLF after the last one.
;
; Inputs:
;	value (popped): 32-bit VAR_LONG, or a far pointer to a VAR_STR
;	or VAR_DOUBLE
;	16-bit type of the value (popped)
;	16-bit flag (popped): zero if more values follow
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	writeValue,FAR
	ARGVAR	wvValue,dword
	ARGVAR	wvType,word
	ARGVAR	wvLast,word
	ENTER
	push	ds
	mov	ax,[wvValue].OFF
	mov	dx,[wvValue].SEG
	mov	cx,[wvType]		; CL = type
	cmp	cl,VAR_LONG
	jne	wv1
	PRINTF	<"%ld">,ax,dx		; DX:AX = 32-bit value
	jmp	short wv8
wv1:	cmp	cl,VAR_DOUBLE
	jne	wv2
	PRINTF	<"%f">,ax,dx		; DX:AX -> double
	jmp	short wv8
wv2:	xchg	si,ax
	mov	ds,dx			; DS:SI -> string
	sub	cx,cx
	test	si,si			; empty string?
	jz	wv3			; yes
	lodsb
	mov	cl,al			; CX = length
wv3:	PRINTF	<34,"%.*ls",34>,cx,si,ds
	les	di,[wvValue]
	call	releaseStr
wv8:	mov	ax,[wvLast]
	test	al,al			; more values?
	jnz	wv9			; no
	PRINTF	<",">
	jmp	short wv10
wv9:	PRINTF	<13,10>
wv10:	pop	ds
	LEAVE
	RETURN
ENDPROC	writeValue

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileEof (EOF)
;
; Returns -1 (true) if file n (open for INPUT) is at its end (or at a CTRLZ),
; or 0 (false) if not.
;
; Inputs:
;	32-bit return value
;	32-bit file number (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	fileEof,FAR
	RETVAR	retEof,dword
	ARGVAR	lEofNum,dword
	ENTER
	push	ds
	mov	ax,[lEofNum].LOW
	mov	dl,FM_INPUT OR FM_RANDOM
	call	getFile			; AL = handle
	mov	bl,al
	mov	bh,0			; BX = handle
	push	ss
	pop	ds
	push	ax			; (room for one byte)
	mov	dx,sp			; DS:DX -> room
	mov	cx,1
	mov	ah,DOS_HDL_READ
	int	21h			; read the next byte, if any
	pop	cx			; CL = byte
	mov	dx,-1			; DX = -1 (true)
	jc	fe9			; (treat an error like the end)
	dec	ax			; was a byte read?
	jnz	fe9			; no
	push	cx
	mov	cx,dx			; CX:DX = -1
	mov	ax,DOS_HDL_SEEKCUR
	int	21h			; yes, so seek back over it
	pop	cx
	mov	dx,-1
	cmp	cl,CHR_CTRLZ		; was it a CTRLZ?
	je	fe9			; yes
	inc	dx			; no, so DX = 0 (false)
fe9:	mov	[retEof].LOW,dx
	mov	[retEof].HIW,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	fileEof

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; inputLine
;
; Used by "INPUT [prompt;|,]var[,var]..." and "LINE INPUT [prompt;]var$" to
; display the prompt (followed by "? " if requested) and read a line from the
; keyboard into LINEBUF, where fileItem then finds the items for each var.
; Unlike MSBASIC, missing items are simply empty (or zero), and extra items
; are ignored, rather than asking the user to "Redo from start".
;
; Inputs:
;	prompt string (popped)
;	16-bit flags (popped): bit 0 to display "? ", bit 1 for LINE INPUT
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	inputLine,FAR
	ARGVAR	pPrompt,dword
	ARGVAR	wInFlags,word
	ENTER
	push	ds
	lds	si,[pPrompt]		; DS:SI -> prompt
	sub	cx,cx
	test	si,si			; is there one?
	jz	il1			; no
	lodsb
	mov	cl,al
	PRINTF	<"%.*ls">,cx,si,ds
	les	di,[pPrompt]
	call	releaseStr
il1:	mov	ax,[wInFlags]
	test	al,1			; display "? "?
	jz	il2			; no
	PRINTF	<"? ">
il2:	push	ss
	pop	ds
	mov	bx,ds:[PSP_HEAP]
	lea	dx,[bx].LINEBUF		; DS:DX -> LINEBUF
	mov	word ptr [bx].LINEBUF,254; (INP_MAX = 254, INP_CNT = 0)
	mov	ah,DOS_TTY_INPUT
	int	21h
	PRINTF	<13,10>
	mov	ax,[wInFlags]
	shr	al,1
	mov	ah,al			; AH = 1 for LINE INPUT
	mov	al,KBD_HDL
	mov	word ptr [bx].FILE_CUR,ax
	mov	byte ptr [bx].FILE_POS,0	; start of the line
	pop	ds
	LEAVE
	RETURN
ENDPROC	inputLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileLof (LOF)
;
; Returns the size of file n, in bytes.
;
; Inputs:
;	32-bit return value
;	32-bit file number (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	fileLof,FAR
	RETVAR	retLof,dword
	ARGVAR	lLofNum,dword
	ENTER
	mov	ax,[lLofNum].LOW
	call	seekCur			; DX:AX = position (BX = handle)
	push	dx
	push	ax
	sub	cx,cx
	mov	dx,cx
	mov	ax,DOS_HDL_SEEKEND
	int	21h			; DX:AX = size
	mov	[retLof].LOW,ax
	mov	[retLof].HIW,dx
	pop	dx
	pop	cx			; CX:DX = position
	mov	ax,DOS_HDL_SEEKBEG
	int	21h			; restore the position
	LEAVE
	RETURN
ENDPROC	fileLof

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileLoc (LOC)
;
; Returns the last record # used by GET # or PUT # for a random access file,
; or for any other file, the position divided by 128 (as in MSBASIC).
;
; Inputs:
;	32-bit return value
;	32-bit file number (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	fileLoc,FAR
	RETVAR	retLoc,dword
	ARGVAR	lLocNum,dword
	ENTER
	mov	ax,[lLocNum].LOW
	call	seekCur			; DX:AX = position (CL = mode)
	cmp	cl,3			; random access?
	jne	fl1			; no
	mov	bx,si
	mov	ax,word ptr ss:[bx].FS_REC
	sub	dx,dx
	jmp	short fl9
fl1:	mov	cx,7
fl2:	shr	dx,1
	rcr	ax,1
	loop	fl2			; DX:AX = position / 128
fl9:	mov	[retLoc].LOW,ax
	mov	[retLoc].HIW,dx
	LEAVE
	RETURN
ENDPROC	fileLoc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; seekCur
;
; Inputs:
;	AX = file number (any mode)
;
; Outputs:
;	DX:AX = file position, BX = handle, CL = mode, SS:SI -> slot
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	seekCur
	mov	dl,FM_INPUT OR FM_OUTPUT OR FM_APPEND OR FM_RANDOM
	call	getFile			; AL = handle, AH = mode
	mov	si,bx
	mov	bl,al
	mov	bh,0			; BX = handle
	push	ax
	sub	cx,cx
	mov	dx,cx
	mov	ax,DOS_HDL_SEEKCUR
	int	21h			; DX:AX = position
	pop	cx
	mov	cl,ch			; CL = mode
	ret
ENDPROC	seekCur

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fieldVar
;
; Used by "FIELD #n,width AS var$[,...]" for each field, to record its width
; and variable in the FIELD table, which genField reserves in the code block:
; a count byte, followed by a 5-byte entry (width and far pointer to the
; variable) for each field.  setField then makes it the file's FIELD table.
;
; Inputs:
;	far pointer to the field's entry (popped)
;	32-bit width (popped)
;	far pointer to the variable (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	fieldVar,FAR
	ARGVAR	pFvEntry,dword
	ARGVAR	lFvWidth,dword
	ARGVAR	pFvVar,dword
	ENTER
	les	di,[pFvEntry]
	mov	ax,[lFvWidth].LOW
	cmp	[lFvWidth].HIW,0
	jne	fvX
	cmp	ax,255
	ja	fvX
	stosb				; record the width
	mov	ax,[pFvVar].OFF
	stosw				; and the variable
	mov	ax,[pFvVar].SEG
	stosw
	LEAVE
	RETURN
fvX:	mov	al,50			; "FIELD overflow"
	jmp	rtError
ENDPROC	fieldVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setField
;
; Used by "FIELD #n,..." (after fieldVar has filled in the FIELD table) to
; make it the FIELD table for random access file n, whose record length must
; be at least as large as all the fields.
;
; Inputs:
;	32-bit file number (popped)
;	far pointer to FIELD table (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	setField,FAR
	ARGVAR	lFldNum,dword
	ARGVAR	pFldTbl,dword
	ENTER
	push	ds
	mov	ax,[lFldNum].LOW
	mov	dl,FM_RANDOM
	call	getFile			; SS:BX -> slot
	lds	si,[pFldTbl]
	lodsb
	cbw
	xchg	cx,ax			; CX = # fields
	sub	dx,dx			; DX = total width
	mov	ah,dh
sfd1:	lodsb
	add	dx,ax
	add	si,4
	loop	sfd1
	mov	al,ss:[bx].FS_RLEN
	mov	ah,0
	cmp	dx,ax			; do the fields fit in a record?
	ja	fvX			; no
	mov	ax,[pFldTbl].OFF
	mov	word ptr ss:[bx].FS_FIELDS,ax
	mov	ax,[pFldTbl].SEG
	mov	word ptr ss:[bx].FS_FIELDS+2,ax
	pop	ds
	LEAVE
	RETURN
ENDPROC	setField

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileRecord
;
; Used by "GET #n[,rec]" and "PUT #n[,rec]" to read or write a record of
; random access file n (the record after the last one used, if rec is
; omitted, which genRecord indicates with -1).  GET # sets each FIELD variable
; to its part of the record (any part of the record past the end of the file
; is zeros), and PUT # writes each FIELD variable to its part of the record
; (padded with spaces).
;
; Inputs:
;	32-bit file number (popped)
;	32-bit record number (popped)
;	16-bit flag (popped): 0 for GET #, 1 for PUT #
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	fileRecord,FAR
	ARGVAR	lRecNum,dword
	ARGVAR	lRecRec,dword
	ARGVAR	wRecPut,word
	ENTER
	push	ds
	mov	ax,[lRecNum].LOW
	mov	dl,FM_RANDOM
	call	getFile			; SS:BX -> slot
	mov	ax,[lRecRec].LOW
	mov	cx,[lRecRec].HIW
	inc	cx			; next record?
	jnz	fr1			; no
	sub	ax,ax
	jmp	short fr2
fr1:	dec	cx			; is the record # 1-65535?
	jnz	frX			; no
	test	ax,ax
	jz	frX
fr2:	call	seekRecord		; CX = record length
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	di,ds:[PSP_HEAP]
	lea	di,[di].LINEBUF
	mov	dx,di			; DS:DX -> record (in LINEBUF)
	push	cx
	mov	ax,[wRecPut]
	test	al,al			; PUT?
	mov	al,' '
	jnz	fr3			; yes, so fill it with spaces
	mov	al,0			; no, so fill it with zeros
fr3:	rep	stosb
	pop	cx
	mov	ax,[wRecPut]
	push	bx
	push	ax
	mov	ah,DOS_HDL_READ
	test	al,al			; PUT?
	jz	fr4			; no
	call	doFields		; yes, so build the record first
	mov	ah,DOS_HDL_WRITE
fr4:	mov	bl,ss:[bx].FILE_DATA
	mov	bh,0			; BX = handle
	int	21h			; read or write the record
	pop	ax
	pop	bx
	test	al,al			; GET?
	jnz	fr9			; no
	call	doFields		; yes, so set the variables
fr9:	pop	ds
	LEAVE
	RETURN
frX:	mov	al,63			; "Bad record number"
	jmp	rtError
ENDPROC	fileRecord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; seekRecord
;
; Inputs:
;	AX = record # (or 0 for the record after the last one used)
;	SS:BX -> slot
;
; Outputs:
;	CX = record length, and the file is positioned at the record
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	seekRecord
	test	ax,ax
	jnz	sr1
	mov	ax,word ptr ss:[bx].FS_REC
	inc	ax
	jz	frX			; there's no next record
sr1:	mov	word ptr ss:[bx].FS_REC,ax
	dec	ax
	mov	cl,ss:[bx].FS_RLEN
	mov	ch,0
	push	cx
	mul	cx
	mov	cx,dx
	xchg	dx,ax			; CX:DX = position of the record
	push	bx
	mov	bl,ss:[bx].FILE_DATA
	mov	bh,0			; BX = handle
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	pop	bx
	pop	cx
	ret
ENDPROC	seekRecord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doFields
;
; For GET #, set each FIELD variable to its part of the record, or for PUT #,
; copy each FIELD variable to its part of the record.
;
; Inputs:
;	AL = 0 for GET #, 1 for PUT #
;	SS:BX -> slot
;	SS:DX -> record (in LINEBUF)
;	DS = ES = SS
;
; Outputs:
;	None
;
; Modifies:
;	AX, SI, DI, ES
;
DEFPROC	doFields
	push	bx
	push	cx
	push	dx
	les	di,dword ptr ss:[bx].FS_FIELDS
	mov	cx,es
	jcxz	df9			; there's no FIELD table
	mov	cl,es:[di]
	mov	ch,0			; CX = # fields
	inc	di			; ES:DI -> 1st entry
	mov	si,dx			; SS:SI -> 1st field in the record
df1:	push	cx
	push	ax
	push	es
	push	di
	push	si
	mov	cl,es:[di]
	mov	ch,0			; CX = width of the field
	test	al,al			; PUT?
	jnz	df4			; yes
;
; GET #: set the variable to a new string with the field's contents.
;
	sub	ax,ax
	cwd				; DX:AX = empty string
	jcxz	df2
	call	allocStr		; ES:DI -> new string
	mov	ax,di
	mov	dx,es
	inc	di
	rep	movsb			; copy the field to it
df2:	mov	bx,sp
	les	di,ss:[bx+2]		; ES:DI -> entry
	push	word ptr es:[di+3]
	push	word ptr es:[di+1]	; push pointer to the variable
	push	dx
	push	ax			; push the string
	push	cs
	call	setStr
	jmp	short df8
;
; PUT #: copy the variable's string (up to the field's width) to the field.
;
df4:	les	di,es:[di+1]		; ES:DI -> variable
	push	ds
	lds	bx,es:[di]		; DS:BX -> its string
	test	bx,bx			; empty?
	jz	df6			; yes
	mov	al,[bx]
	mov	ah,0			; AX = length
	cmp	ax,cx
	jae	df5
	xchg	cx,ax			; CX = length (shorter than the field)
df5:	mov	di,si
	push	ss
	pop	es			; ES:DI -> field
	lea	si,[bx+1]		; DS:SI -> string
	rep	movsb
df6:	pop	ds
df8:	pop	si
	pop	di
	pop	es
	mov	al,es:[di]
	mov	ah,0
	add	si,ax			; SI -> next field in the record
	add	di,5			; DI -> next entry
	pop	ax
	pop	cx
	loop	df1
df9:	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	doFields

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; lsetStr
;
; Used by "LSET var$ = string" and "RSET var$ = string", which set the
; variable to the string, left-justified (LSET) or right-justified (RSET),
; padded with spaces (or truncated) to the variable's FIELD width; if the
; variable isn't a FIELD variable, its current length is used instead.
;
; Inputs:
;	far pointer to variable (popped)
;	string value (popped)
;	16-bit flag (popped): 0 for LSET, 1 for RSET
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	lsetStr,FAR
	ARGVAR	pLsVar,dword
	ARGVAR	pLsStr,dword
	ARGVAR	wLsRight,word
	ENTER
	push	ds
	mov	cx,FILE_MAX
	mov	bx,ss:[PSP_HEAP]	; look for the variable in FIELD tables
ls1:	push	cx
	cmp	ss:[bx].FILE_DATA,0	; is the file open?
	je	ls3			; no
	les	di,dword ptr ss:[bx].FS_FIELDS
	mov	ax,es
	test	ax,ax			; is there a FIELD table?
	jz	ls3			; no
	mov	cl,es:[di]
	mov	ch,0			; CX = # fields
	inc	di
ls2:	mov	ax,es:[di+1]
	cmp	ax,[pLsVar].OFF
	jne	ls2a
	mov	ax,es:[di+3]
	cmp	ax,[pLsVar].SEG
	jne	ls2a
	pop	cx			; found it
	mov	al,es:[di]		; AL = its width
	jmp	short ls5
ls2a:	add	di,5
	loop	ls2
ls3:	add	bx,FILE_SLOT
	pop	cx
	loop	ls1
	lds	si,[pLsVar]
	lds	si,[si]			; DS:SI -> variable's string
	mov	al,0
	test	si,si			; empty?
	jz	ls5			; yes
	mov	al,[si]			; AL = its length
ls5:	mov	ah,0
	xchg	cx,ax			; CX = width
	sub	ax,ax
	cwd				; DX:AX = empty string
	jcxz	ls8
	call	allocStr		; ES:DI -> new string
	push	di
	inc	di
	mov	dx,di			; DX -> its characters
	push	cx
	mov	al,' '
	rep	stosb			; fill it with spaces
	pop	cx			; CX = width
	lds	si,[pLsStr]		; DS:SI -> string
	test	si,si			; empty?
	jz	ls7			; yes
	lodsb
	mov	ah,0			; AX = its length
	mov	di,dx
	cmp	ax,cx			; longer than the width?
	jae	ls6			; yes, so copy only the width
	test	byte ptr [wLsRight],1	; RSET?
	jz	ls5a			; no
	add	di,cx
	sub	di,ax			; DI -> where to right-justify it
ls5a:	xchg	cx,ax			; CX = # characters to copy
ls6:	rep	movsb
ls7:	pop	ax
	mov	dx,es			; DX:AX = new string
ls8:	push	dx
	push	ax
	les	di,[pLsStr]
	call	releaseStr
	pop	ax
	pop	dx
	push	[pLsVar].SEG
	push	[pLsVar].OFF
	push	dx
	push	ax
	push	cs
	call	setStr
	pop	ds
	LEAVE
	RETURN
ENDPROC	lsetStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileMkd (MKD$), fileMkl (MKL$), and fileMki (MKI$)
;
; Returns a string with the 8 bytes of a double (in IEEE format, unlike the
; MBF format of MSBASIC), the 4 bytes of a long, or the 2 low bytes of a long,
; for writing to a random access file (see CVD, CVL, and CVI).
;
; Inputs:
;	32-bit return value
;	32-bit long or far pointer to double (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	fileMkd,FAR
	RETVAR	retMk,dword
	ARGVAR	vMk,dword
	mov	cx,8
	jmp	short mk1
	DEFLBL	fileMkl,near
	mov	cx,4
	jmp	short mk1
	DEFLBL	fileMki,near
	mov	cx,2
mk1:	ENTER
	push	ds
	push	ss
	pop	ds
	lea	si,[vMk]		; DS:SI -> long
	cmp	cl,8			; MKD$?
	jne	mk2			; no
	lds	si,[vMk]		; DS:SI -> double
mk2:	call	allocStr		; ES:DI -> new string
	mov	ax,di
	mov	dx,es			; DX:AX = string value
	inc	di
	rep	movsb
	mov	[retMk].OFF,ax
	mov	[retMk].SEG,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	fileMkd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileCvd (CVD), fileCvl (CVL), and fileCvi (CVI)
;
; Converts the first 8 bytes of a string to a double, the first 4 bytes to
; a long, or the first 2 bytes to a long (sign-extended); a shorter string
; is an "Illegal function call" error.
;
; Inputs:
;	32-bit return value (or for CVD, a far pointer to the double)
;	string value (popped)
;
; Outputs:
;	32-bit return value (or double) updated
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	fileCvd,FAR
	RETVAR	retCv,dword
	ARGVAR	sCv,dword
	mov	cx,8
	jmp	short cv1
	DEFLBL	fileCvl,near
	mov	cx,4
	jmp	short cv1
	DEFLBL	fileCvi,near
	mov	cx,2
cv1:	ENTER
	push	ds
	lds	si,[sCv]		; DS:SI -> string
	test	si,si			; empty?
	jz	cvX			; yes
	lodsb
	cmp	al,cl			; long enough?
	jb	cvX			; no
	push	ss
	pop	es
	lea	di,[retCv]		; ES:DI -> long
	cmp	cl,8			; CVD?
	jne	cv2			; no
	les	di,[retCv]		; ES:DI -> double
cv2:	cmp	cl,2			; CVI?
	jne	cv3			; no
	lodsw
	cwd
	stosw
	xchg	ax,dx
	stosw
	jmp	short cv4
cv3:	rep	movsb
cv4:	les	di,[sCv]
	call	releaseStr
	pop	ds
	LEAVE
	RETURN
cvX:	mov	al,5			; "Illegal function call"
	jmp	rtError
ENDPROC	fileCvd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; syncFiles
;
; Called by cleanUpTo after it closes the handles that a command opened, so
; that any OPEN file whose handle was closed is marked closed, too.
;
; Inputs:
;	SS:BX -> CMDHEAP
;
; Outputs:
;	None
;
; Modifies:
;	CX, SI, DI
;
DEFPROC	syncFiles
	lea	si,[bx].FILE_DATA
	mov	cx,FILE_MAX
sf1:	mov	di,ss:[si]
	and	di,0FFh			; DI = handle (0 if none)
	cmp	byte ptr ss:[PSP_PFT][di],SFH_NONE
	jne	sf2
	mov	ss:[si],ch		; zero the handle (CH is zero)
sf2:	add	si,FILE_SLOT
	loop	sf1
	ret
ENDPROC	syncFiles

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getFile
;
; Inputs:
;	AX = file number
;	DL = modes allowed (FM_* bits)
;
; Outputs:
;	AL = handle, AH = mode, SS:BX -> slot (otherwise, a "Bad file number"
;	error if the file isn't open, or a "Bad file mode" error)
;
; Modifies:
;	AX, BX
;
DEFPROC	getFile
	call	getSlot
	mov	ax,word ptr ss:[bx].FILE_DATA	; AL = handle, AH = mode
	test	al,al			; is the file open?
	jz	gsX			; no
	push	cx
	mov	cl,ah
	mov	ch,1
	shl	ch,cl			; CH = 1 SHL mode
	test	ch,dl			; is the mode allowed?
	pop	cx
	jz	gfX			; no
	ret
gfX:	mov	al,54			; "Bad file mode"
	jmp	rtError
ENDPROC	getFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getSlot
;
; Inputs:
;	AX = file number
;
; Outputs:
;	SS:BX -> slot (ie, its FILE_DATA); otherwise, a "Bad file number" error
;
; Modifies:
;	AX, BX
;
DEFPROC	getSlot
	dec	ax
	cmp	ax,FILE_MAX		; is the file number valid?
	jae	gsX			; no
	mov	bx,FILE_SLOT
	push	dx
	mul	bx			; AX = offset of slot
	pop	dx
	xchg	bx,ax
	add	bx,ss:[PSP_HEAP]	; SS:BX.FILE_DATA -> slot
	ret
gsX:	mov	al,52			; "Bad file number"
	jmp	rtError
ENDPROC	getSlot

CODE	ENDS

	end
