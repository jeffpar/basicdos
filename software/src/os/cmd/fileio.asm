;
; BASIC-DOS File I/O Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for CLOSE, DOS, FIELD, GET #, INPUT #, IOCTL #, KEY n,
; LINE INPUT #, LPRINT, LSET, the MID$ statement, OPEN, PRINT #, PUT #, RSET,
; WIDTH device, and WRITE # (see genfile.asm), and for the CVD, CVI, CVL, DOS,
; EOF, INPUT$, IOCTL$, LOC, LOF, LPOS, MKD$, MKI$, and MKL$ functions.
; Like genfile.asm, this is outside COMMAND's core (see CMD.LRF), unlike the
; INPUT, LINE INPUT, and WRITE functions that files share with the keyboard
; and screen (see input.asm).
;
; See fileio.inc for the slot that each OPEN file has in FILE_DATA.
;
; Nothing is buffered between statements: GET # and PUT # build each record
; in LINEBUF, and INPUT # and LINE INPUT # take their items from LINEBUF, too
; (see fileItem), so there's nothing to discard (or keep in sync) when another
; command or program runs.
;
	DOSFUNC equ 1
	include	cmd.inc
	include	fileio.inc

CODE    SEGMENT

	EXTNEAR	<rtError,allocStr,releaseStr,openMode,setStr,strIllegal>
	EXTNEAR	<getByteArg,newStr,setWidth>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

FM_INPUT	equ	01h		; masks for getFile (1 SHL mode)
FM_OUTPUT	equ	02h
FM_APPEND	equ	04h
FM_RANDOM	equ	08h
FM_DEVICE	equ	10h		; a device opened without FOR, eg COM1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openFile
;
; Used by "OPEN file [FOR INPUT|OUTPUT|APPEND|RANDOM] AS #n [LEN=reclen]".
; As in MSBASIC, an error is a runtime error (eg, "File not found"), which
; ON ERROR can handle.  A random access file's record length must be from 1
; to 255 (since GET # and PUT # build records in LINEBUF).
;
; Also as in MSBASIC, "SCRN:" is the screen (ie, the session's console, CON),
; a device opened without FOR (eg, "COM1:300,E,7,2"; see ddcom_open) can be
; used for both input and output (mode 4; see FM_DEVICE), and if a device's
; name (eg, "COM1:") can't be opened, it's a "Device unavailable" error.
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
	jb	of0b			; yes
of9:	jmp	rtError
of0b:	push	ss
	pop	es
	mov	di,ss:[PSP_HEAP]
	lea	di,[di].LINEBUF
	mov	dx,di			; ES:DX -> LINEBUF
	lds	si,[pName]		; DS:SI -> filename
	sub	cx,cx
	test	si,si			; empty string?
	jz	of1			; yes
	call	chkScrn			; "SCRN:"?
	jne	of0			; no
	push	cs
	pop	ds
	mov	si,offset CON_NAME	; DS:SI -> "CON" instead
of0:	lodsb
	mov	cl,al
	cmp	cl,5			; long enough for a device name?
	jb	of0a			; no
	cmp	byte ptr [si+4],':'	; a device name (eg, "COM1:")?
	jne	of0a			; no
	mov	byte ptr [wMode+1],68	; yes (for "Device unavailable")
of0a:	rep	movsb			; copy the filename to LINEBUF
of1:	xchg	ax,cx
	stosb				; and null-terminate it
	les	di,[pName]
	call	releaseStr
	push	ss
	pop	ds			; DS:DX -> filename
	mov	ax,[wMode]
	push	ax
	call	openMode		; AX = handle
	pop	cx			; CL = mode (and CH = 68 for a device)
	jc	of8
	cmp	cl,3			; random access?
	jne	of2			; no
	push	ax
	push	bx
	xchg	bx,ax			; BX = handle
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDATA
	int	21h			; DL bit 7 is set for a device
	pop	bx
	pop	ax
	jc	of2
	test	dl,80h			; a device?
	jz	of2			; no
	inc	cx			; yes, so it's mode 4 (FM_DEVICE)
of2:	mov	ah,cl
	mov	word ptr ss:[bx].FILE_DATA,ax	; record the handle and mode
	mov	ax,[lRecLen].LOW
	mov	word ptr ss:[bx].FS_RLEN,ax	; record length
	sub	ax,ax
	mov	word ptr ss:[bx].FS_REC,ax	; no records used yet
	mov	word ptr ss:[bx].FS_FIELDS+2,ax	; and no FIELD table
	pop	ds
	LEAVE
	RETURN
of8:	mov	cl,ch			; CL = 68 for a device name
	test	cl,cl			; a device name?
	jnz	of8a			; yes ("Device unavailable")
	mov	cl,55			; "File already open" (elsewhere)
	cmp	al,ERR_SHARE
	je	of8a
	mov	cl,53			; "File not found"
	cmp	al,ERR_NOFILE
	je	of8a
	mov	cl,75			; "Path/File access error"
of8a:	xchg	ax,cx
	jmp	rtError
ENDPROC	openFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; closeFile
;
; Used by "CLOSE [#n]", which closes file n, or all files if n is zero.
; Closing a file that isn't open does nothing.  A failed close is a runtime
; error; DOS closes the handle even when its metadata commit fails, so its
; slot must still be marked closed.
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
	jnc	cs9
	mov	al,57			; "Device I/O error"
	jmp	rtError
cs9:	ret
ENDPROC	closeSlot

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileOut
;
; Used by "PRINT #n" and "WRITE #n" to make file n STDOUT (like redirOut,
; which does the same for ":>"), until redirEnd restores STDOUT; we record the
; file's handle for redirEnd with bit 7 set, so that it leaves the file open
; and checks for a printer error instead (see chkOut).
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
	mov	dl,FM_OUTPUT OR FM_APPEND OR FM_DEVICE
	call	getFile			; AL = handle
	mov	bl,al
	mov	bh,0
	mov	al,ss:[PSP_PFT][bx]	; AL = SFH of the file
	xchg	al,ss:[PSP_PFT][STDOUT]	; AL = previous STDOUT SFH
	mov	ah,bl
	or	ah,80h			; AH = handle for redirEnd (see above)
	les	di,[pOutW]
	stosw				; record the redirection
	LEAVE
	RETURN
ENDPROC	fileOut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; prnOut
;
; Used by "LPRINT" to make PRN (the process's STDPRN) STDOUT, like fileOut,
; until redirEnd restores STDOUT (and checks for a printer error).
;
; Inputs:
;	[pPrnW] -> redirection word (in the code block)
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	prnOut,FAR
	ARGVAR	pPrnW,dword
	ENTER
	mov	al,ss:[PSP_PFT][STDPRN]	; AL = SFH of PRN
	xchg	al,ss:[PSP_PFT][STDOUT]	; AL = previous STDOUT SFH
	mov	ah,STDPRN OR 80h	; AH = handle (see fileOut)
	les	di,[pPrnW]
	stosw				; record the redirection
	LEAVE
	RETURN
ENDPROC	prnOut

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
	mov	dl,FM_INPUT OR FM_DEVICE
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
; fileEof (EOF)
;
; Returns -1 (true) if file n (open for INPUT) is at its end (or at a CTRLZ),
; or 0 (false) if not.  For a device that reports how many bytes are waiting
; (eg, COM1; see inCount), it's true if none are, as in MSBASIC.
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
	mov	dl,FM_INPUT OR FM_RANDOM OR FM_DEVICE
	call	getFile			; AL = handle
	mov	bl,al
	mov	bh,0			; BX = handle
	call	inCount			; AX = # bytes waiting (eg, for COM1)
	jc	fe0			; not a device that reports it
	cmp	ax,1			; carry set if none
	sbb	dx,dx			; DX = -1 (true) if none
	jmp	short fe9
fe0:	push	ss
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
; or for any other file, the position divided by 128 (as in MSBASIC), except
; for a device that reports how many bytes are waiting (eg, COM1; see
; inCount), which returns that number (at most 255), as MSBASIC does.
;
; Inputs:
;	32-bit return value
;	32-bit file number (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	fileLoc,FAR
	RETVAR	retLoc,dword
	ARGVAR	lLocNum,dword
	ENTER
	mov	ax,[lLocNum].LOW
	call	seekCur			; DX:AX = position (CL = mode)
	xchg	di,ax			; DX:DI = position
	call	inCount			; AX = # bytes waiting (eg, for COM1)
	jc	fl0			; not a device that reports it
	sub	dx,dx
	cmp	ax,255			; more than 255?
	jbe	fl9			; no
	mov	ax,255
	jmp	short fl9
fl0:	xchg	ax,di			; DX:AX = position
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
	mov	dl,FM_INPUT OR FM_OUTPUT OR FM_APPEND OR FM_RANDOM OR FM_DEVICE
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
; inCount
;
; Returns the number of bytes waiting to be read from a device that reports
; it with IOCTL_INSTATUS (eg, COM1; see ddcom_ioctl).
;
; Inputs:
;	BX = handle
;
; Outputs:
;	If carry clear, AX = # bytes
;
; Modifies:
;	AX
;
DEFPROC	inCount
	push	dx
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDATA
	int	21h			; DL bit 7 is set for a device
	jc	ic9
	shl	dl,1			; is it a device?
	cmc
	jc	ic9			; no
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_INSTATUS
	int	21h			; DX = # bytes (if the driver has it)
	xchg	ax,dx
ic9:	pop	dx
	ret
ENDPROC	inCount

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strInput (INPUT$)
;
; Returns a string of n characters (1-255) read from file f (opened for INPUT,
; or a device opened without FOR, eg, COM1), or if f is 0 (or omitted), from
; the keyboard, without displaying them; as in MSBASIC, every key counts (eg,
; ENTER), and an extended key is a zero followed by its scan code.  Reading
; past the end of a file is an "Input past end" error.
;
; Inputs:
;	32-bit return value
;	32-bit count (popped)
;	32-bit file number (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strInput,FAR
	RETVAR	retInput,dword
	ARGVAR	lInCount,dword
	ARGVAR	lInFile,dword
	ENTER
	push	ds
	mov	ax,[lInCount].LOW
	mov	dx,[lInCount].HIW
	call	getByteArg		; AX = count (0-255)
	xchg	cx,ax			; CX = count
	jcxz	snX			; (it must be 1-255)
	push	ss
	pop	ds
	mov	si,ds:[PSP_HEAP]
	lea	dx,[si].LINEBUF		; DS:DX -> LINEBUF
	mov	ax,[lInFile].LOW
	test	ax,ax			; from the keyboard?
	jnz	sn2			; no
	mov	di,dx
	push	cx
sn1:	mov	ah,DOS_TTY_READ
	int	21h			; AL = next key (not displayed)
	mov	[di],al
	inc	di
	loop	sn1
	pop	cx
	jmp	short sn8
sn2:	push	dx
	mov	dl,FM_INPUT OR FM_DEVICE
	call	getFile			; AL = handle
	pop	dx
	mov	bl,al
	mov	bh,0			; BX = handle
	mov	ah,DOS_HDL_READ
	int	21h			; AX = # bytes read
	jc	sn9
	cmp	ax,cx			; were there enough?
	jb	sn9			; no
sn8:	mov	si,dx			; SS:SI -> characters
	call	newStr			; DX:AX = string
	mov	[retInput].OFF,ax
	mov	[retInput].SEG,dx
	pop	ds
	LEAVE
	RETURN
sn9:	mov	al,62			; "Input past end"
	jmp	rtError
snX:	jmp	strIllegal
ENDPROC	strInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; keyDef
;
; Used by "KEY n,string", which in MSBASIC makes function key n (1-10) type
; the string.  BASIC-DOS doesn't assign strings to the function keys (they
; always return their key codes, as they do after KEY n,"" in MSBASIC), so we
; only check the key number.
;
; Inputs:
;	32-bit key number (popped)
;	string value (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	keyDef,FAR
	ARGVAR	lKeyNum,dword
	ARGVAR	pKeyStr,dword
	ENTER
	les	di,[pKeyStr]
	call	releaseStr
	mov	ax,[lKeyNum].LOW
	mov	dx,[lKeyNum].HIW
	call	getByteArg		; AX = key number (0-255)
	dec	ax
	cmp	ax,10			; is it 1-10?
	jae	kdX			; no
	LEAVE
	RETURN
kdX:	jmp	strIllegal
ENDPROC	keyDef

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; widthDev
;
; Used by "WIDTH device,width", where device is a string (eg, "COM1:"): for
; "SCRN:", it's the same as WIDTH width (see setWidth); BASIC-DOS doesn't
; insert line breaks in any other device's output, so for any other device,
; we only check that the width is 1-255 (where 255, as in MSBASIC, means that
; lines are never broken).
;
; Inputs:
;	string value (popped)
;	32-bit width (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	widthDev,FAR
	ARGVAR	pDev,dword
	ARGVAR	lDevWidth,dword
	ENTER
	push	ds
	sub	cx,cx
	lds	si,[pDev]		; DS:SI -> device name
	test	si,si			; empty string?
	jz	wd1			; yes
	call	chkScrn			; "SCRN:"?
	jne	wd1			; no
	inc	cx			; CX = 1 for "SCRN:"
wd1:	les	di,[pDev]
	call	releaseStr
	pop	ds
	jcxz	wd2
	push	[lDevWidth].HIW
	push	[lDevWidth].LOW
	push	cx			; (1 argument; see getArgs)
	push	cs
	call	near ptr setWidth	; WIDTH "SCRN:",n is WIDTH n
	jmp	short wd9
wd2:	mov	ax,[lDevWidth].LOW
	mov	dx,[lDevWidth].HIW
	call	getByteArg		; AX = width (0-255)
	test	ax,ax			; is it 1-255?
	jz	kdX			; no
wd9:	LEAVE
	RETURN
ENDPROC	widthDev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkScrn
;
; Inputs:
;	DS:SI -> string (at its length byte)
;
; Outputs:
;	ZF set if the string is "SCRN:" (in any case)
;
; Modifies:
;	AX
;
DEFPROC	chkScrn
	push	cx
	push	si
	push	di
	mov	di,offset SCRN_NAME
	mov	cx,6			; (the length byte, too)
cks1:	lodsb
	and	al,0DFh			; (see SCRN_NAME)
	inc	di
	cmp	al,cs:[di-1]
	loope	cks1			; (ZF stays set if every byte matches)
	pop	di
	pop	si
	pop	cx
	ret
ENDPROC	chkScrn

;
; SCRN_NAME is "SCRN:" (with its length), with each byte ANDed with 0DFh, as
; chkScrn does to every byte of the name (which upper-cases the letters).
;
SCRN_NAME	db	5,"SCRN",':' AND 0DFh
CON_NAME	db	3,"CON"

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
; DOS failures raise "Device I/O error" ("Permission denied" for a PUT to a
; read-only file); a short PUT raises "Disk full".
; Failed operations preserve the last completed record number.
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
	LOCVAR	frLast,word
	ENTER
	push	ds
	mov	ax,[lRecNum].LOW
	mov	dl,FM_RANDOM
	call	getFile			; SS:BX -> slot
	mov	dx,word ptr ss:[bx].FS_REC
	mov	[frLast],dx		; retain the last completed record on error
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
	jc	frIO
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
	pop	si			; SI = GET/PUT flag; AX is the DOS result
	pop	bx
	jc	frIO
	test	si,si			; GET?
	jz	fr5			; yes (short reads retain the zero padding)
	cmp	ax,cx			; was the entire PUT record written?
	je	fr9			; yes
	mov	al,61			; "Disk full"
	jmp	short frErr
fr5:	sub	ax,ax			; AL = 0 for GET's doFields
	call	doFields		; yes, so set the variables
fr9:	pop	ds
	LEAVE
	RETURN
frX:	mov	al,63			; "Bad record number"
	jmp	rtError
frIO:	cmp	al,ERR_ACCDENIED	; a PUT to a read-only file?
	mov	al,70			; "Permission denied"
	je	frErr			; yes
	mov	al,57			; "Device I/O error"
frErr:	mov	dx,[frLast]
	mov	word ptr ss:[bx].FS_REC,dx
	jmp	rtError
ENDPROC	fileRecord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileIoctl
;
; Used by "IOCTL [#]n,code[,value|string[,value]]" to send an IOCTL request
; (DOS_HDL_IOCTL) to the device or volume open as file n (see genIoctl).
; A failure is a runtime error: "Permission denied" (70) for a write-protect
; error, "Disk not ready" (71), "Disk media error" (72) for unknown media or
; a sector not found, "Illegal function call" (5) for a request the driver
; doesn't support, and otherwise "Device I/O error" (57).
;
; Inputs:
;	32-bit file number (popped)
;	32-bit IOCTL code (popped)
;	32-bit value or string pointer (popped)
;	32-bit second value (popped)
;	16-bit type (popped): VAR_STR (low byte) if the first value is a string
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	fileIoctl,FAR
	ARGVAR	lIoNum,dword
	ARGVAR	lIoCode,dword
	ARGVAR	lIoCX,dword
	ARGVAR	lIoDX,dword
	ARGVAR	wIoType,word
	ENTER
	push	ds
	mov	ax,[lIoNum].LOW
	mov	dl,FM_INPUT OR FM_OUTPUT OR FM_APPEND OR FM_RANDOM OR FM_DEVICE
	call	getFile			; AL = handle
	mov	bl,al
	mov	bh,0			; BX = handle
	mov	cx,[lIoCX].LOW		; CX = first value
	cmp	byte ptr [wIoType],VAR_STR ; is the first value a string?
	jne	io1			; no
	lds	si,[lIoCX]		; yes, DS:SI -> string
	sub	cx,cx
	test	si,si			; empty string?
	jz	io1			; yes
	lodsb
	mov	cl,al			; CX = length, DS:SI -> data
io1:	mov	dx,[lIoDX].LOW		; DX = second value
	mov	ax,[lIoCode].LOW
	mov	ah,DOS_HDL_IOCTL
	int	21h
	pushf
	push	ax
	cmp	byte ptr [wIoType],VAR_STR
	jne	io2
	les	di,[lIoCX]
	call	releaseStr
io2:	pop	ax
	popf
	jc	io8
	pop	ds
	LEAVE
	RETURN
io8:	jmp	ioctlErr
ENDPROC	fileIoctl

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
; fileIoctlStr (IOCTL$)
;
; Used by "IOCTL$(n,code[,value])" to send an IOCTL request to the device or
; volume open as file n, with LINEBUF as the request's data (CX = 255 and DX =
; value), and return the data the driver stored there as a string, using the
; count it returned in DX (eg, a PARTINFO from IOCTL_GETPART); an empty string
; means the driver returned nothing.  Errors are reported as for IOCTL #.
;
; Inputs:
;	32-bit return value
;	32-bit file number (popped)
;	32-bit IOCTL code (popped)
;	32-bit value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	fileIoctlStr,FAR
	RETVAR	retIoctl,dword
	ARGVAR	lIsNum,dword
	ARGVAR	lIsCode,dword
	ARGVAR	lIsVal,dword
	ENTER
	push	ds
	mov	ax,[lIsNum].LOW
	mov	dl,FM_INPUT OR FM_OUTPUT OR FM_APPEND OR FM_RANDOM OR FM_DEVICE
	call	getFile			; AL = handle
	mov	bl,al
	mov	bh,0			; BX = handle
	mov	si,ss:[PSP_HEAP]
	lea	si,[si].LINEBUF
	push	ss
	pop	ds			; DS:SI -> LINEBUF
	mov	cx,255			; CX = its length
	mov	dx,[lIsVal].LOW
	mov	ax,[lIsCode].LOW
	mov	ah,DOS_HDL_IOCTL
	int	21h			; DX = # bytes stored
	jc	ioctlErr
	sub	ax,ax
	mov	[retIoctl].OFF,ax
	mov	[retIoctl].SEG,ax	; return an empty string
	cmp	dx,255
	jbe	is1
	mov	dx,255
is1:	mov	cx,dx			; CX = # bytes (1-255)
	jcxz	is9			; none
	call	allocStr		; ES:DI -> new string
	mov	[retIoctl].OFF,di
	mov	[retIoctl].SEG,es
	inc	di
	rep	movsb			; copy the data from LINEBUF
is9:	pop	ds
	LEAVE
	RETURN
ENDPROC	fileIoctlStr

;
; ioctlErr converts the DOS error in AL to a BASIC error (see fileIoctl and
; dosCall).
;
DEFPROC	ioctlErr
	mov	si,offset IOCTL_ERRS
ie1:	cmp	cs:[si],al		; does the DOS error match?
	je	ie2			; yes
	cmp	byte ptr cs:[si],0	; end of table?
	je	ie2			; yes
	inc	si
	inc	si
	jmp	ie1
ie2:	mov	al,cs:[si+1]		; AL = BASIC error number
	jmp	rtError
ENDPROC	ioctlErr

;
; DOS_ERRS maps the other DOS errors that dosCall may encounter, and then
; continues with IOCTL_ERRS.
;
DOS_ERRS	db	ERR_INVALID,5, ERR_NOFILE,53, ERR_NOPATH,75
		db	ERR_ACCDENIED,70, ERR_BADHANDLE,52, ERR_SHARE,70
IOCTL_ERRS	db	19,70, ERR_NOTREADY,71, 22,5, 26,72, 27,72, 0,57

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dosCall (DOS)
;
; Used by "DOS ax[,bx[,cx[,dx|string]]]" to call DOS (INT 21h) with those
; values in AX, BX, CX, and DX, or with DS:DX -> a null-terminated copy of the
; string (in LINEBUF).  The registers that DOS returns are saved in DOS_REGS
; for the DOS function (see getDos), and a failure (carry set) is a runtime
; error: "File not found" (53), "Path/File access error" (75), "Permission
; denied" (70), "Bad file number" (52), and "Illegal function call" (5) for
; the corresponding DOS errors, and otherwise the same errors as IOCTL #.
;
; Inputs:
;	32-bit AX value (popped)
;	32-bit BX value (popped)
;	32-bit CX value (popped)
;	32-bit DX value or string pointer (popped)
;	16-bit type (popped): VAR_STR (low byte) if DX is a string
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	dosCall,FAR
	ARGVAR	lDosAX,dword
	ARGVAR	lDosBX,dword
	ARGVAR	lDosCX,dword
	ARGVAR	lDosDX,dword
	ARGVAR	wDosType,word
	ENTER
	push	ds
	mov	dx,[lDosDX].LOW		; DX = value
	cmp	byte ptr [wDosType],VAR_STR ; is it a string?
	jne	dc2			; no
	push	ss
	pop	es
	mov	di,ss:[PSP_HEAP]
	lea	di,[di].LINEBUF
	mov	dx,di			; ES:DX -> LINEBUF
	lds	si,[lDosDX]		; DS:SI -> string
	sub	cx,cx
	test	si,si			; empty string?
	jz	dc1			; yes
	lodsb
	mov	cl,al
	rep	movsb			; copy the string to LINEBUF
dc1:	xchg	ax,cx
	stosb				; and null-terminate it
	les	di,[lDosDX]
	call	releaseStr
	push	ss
	pop	ds			; DS:DX -> string
dc2:	mov	ax,[lDosAX].LOW
	mov	bx,[lDosBX].LOW
	mov	cx,[lDosCX].LOW
	int	21h
	push	bx
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].DOS_REGS[0],ax
	pop	ss:[bx].DOS_REGS[2]
	mov	ss:[bx].DOS_REGS[4],cx
	mov	ss:[bx].DOS_REGS[6],dx	; (carry is unchanged)
	jc	dc8
	pop	ds
	LEAVE
	RETURN
dc8:	mov	si,offset DOS_ERRS
	jmp	ie1
ENDPROC	dosCall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getDos (DOS)
;
; Returns register n (0 for AX, 1 for BX, 2 for CX, or 3 for DX) as DOS
; returned it to the last DOS statement (see dosCall), from 0 to 65535;
; any other n is an "Illegal function call".
;
; Inputs:
;	32-bit return value
;	32-bit register number (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, SI
;
DEFPROC	getDos,FAR
	RETVAR	retDos,dword
	ARGVAR	lDosReg,dword
	ENTER
	mov	bx,[lDosReg].LOW
	cmp	[lDosReg].HIW,0		; is the register number 0-3?
	jne	gdo8			; no
	cmp	bx,3
	ja	gdo8			; no
	add	bx,bx
	mov	si,ss:[PSP_HEAP]
	mov	ax,ss:[si+bx].DOS_REGS
	mov	[retDos].LOW,ax
	mov	[retDos].HIW,0
	LEAVE
	RETURN
gdo8:	mov	al,5			; "Illegal function call"
	jmp	rtError
ENDPROC	getDos

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
; getLpos (LPOS)
;
; Returns the printer's current column (starting at 1), which PRN (LPT1)
; reports like the console's cursor position (see IOCTL_GETPOS); 1 if there's
; no printer.  As in early versions of BASICA, the argument is ignored.
;
; Inputs:
;	32-bit return value
;	32-bit arg (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	getLpos,FAR
	RETVAR	retLpos,dword
	ARGVAR	lLpos,dword
	ENTER
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETPOS
	mov	bx,STDPRN
	int	21h			; DL = column (if there's a printer)
	jnc	glp1
	sub	dx,dx
glp1:	mov	al,dl
	mov	ah,0
	inc	ax
	mov	[retLpos].LOW,ax
	mov	[retLpos].HIW,0
	LEAVE
	RETURN
ENDPROC	getLpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; midSet
;
; Used by "MID$(var$,start[,length]) = string", which replaces characters of
; the variable, beginning at start, with as many characters of the string as
; fit (but no more than length), without changing the variable's length.  As
; in MSBASIC, start must be 1 to 255 and no more than the variable's length,
; and length must be 0 to 255 (the default is 255).  A variable's string is
; never shared (see setStr), so we can replace its characters in place.
;
; Inputs:
;	far pointer to variable (popped)
;	32-bit start and length (popped)
;	string value (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	midSet,FAR
	ARGVAR	pMsVar,dword
	ARGVAR	lMsStart,dword
	ARGVAR	lMsLen,dword
	ARGVAR	pMsStr,dword
	ENTER
	mov	ax,[lMsStart].LOW
	dec	ax			; AX = offset of start
	mov	cx,[lMsLen].LOW		; CX = length
	mov	dx,[lMsStart].HIW
	or	dx,[lMsLen].HIW		; are both less than 64K?
	jnz	ms9			; no
	cmp	ax,254			; is start 1 to 255?
	ja	ms9			; no
	cmp	cx,255			; is length 0 to 255?
	ja	ms9			; no
	push	ds
	lds	si,[pMsVar]
	les	di,[si]			; ES:DI -> variable's string
	test	di,di			; is it empty?
	jz	ms8			; yes, so start is past the end
	mov	dl,es:[di]		; DX = its length
	sub	dx,ax			; DX = # characters from start on
	jbe	ms8			; start is past the end
	cmp	cx,dx
	jbe	ms1
	mov	cx,dx			; CX = # characters to replace
ms1:	add	di,ax
	inc	di			; ES:DI -> start
	lds	si,[pMsStr]
	test	si,si			; is the string empty?
	jz	ms7			; yes
	lodsb
	mov	ah,0			; AX = its length
	cmp	cx,ax
	jbe	ms2
	xchg	cx,ax			; (it's shorter)
ms2:	rep	movsb
ms7:	pop	ds
	les	di,[pMsStr]
	call	releaseStr
	LEAVE
	RETURN
ms8:	pop	ds
ms9:	jmp	strIllegal
ENDPROC	midSet

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
