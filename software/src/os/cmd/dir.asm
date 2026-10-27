;
; BASIC-DOS Directory Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSFFB equ 1
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<getFileName,getToken,chkStrVar,newStr>
	EXTNEAR	<printCRLF,findFile,addString,releaseStr>
	EXTBYTE	<CMD_PATH>
	EXTSTR	<DIR_DEF,PIPE_NAME,COM_EXT,BAS_EXT>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdChdir
;
; Change the current directory of a drive (eg, "CD SUBDIR"), or if nothing
; (or only a drive) is specified, display the drive's current directory.
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
DEFPROC	cmdChdir
	mov	dl,[bx].CMD_ARG
	sub	cx,cx			; no default
	call	getFileName		; DS:SI -> directory, CX = length
	jc	ch2			; nothing specified
	cmp	cx,2			; only a drive?
	jne	ch1			; no
	cmp	byte ptr [si+1],':'
	je	ch3			; yes
ch1:	mov	dx,si
	mov	ah,DOS_DSK_CHDIR
	int	21h
	jc	ch1a
	ret
ch1a:	mov	dx,offset VERB_CD
	jmp	fileError

ch2:	mov	ah,DOS_DSK_GETDRV
	int	21h			; AL = current drive #
	add	al,'A'			; AL = drive letter
	jmp	short ch4
ch3:	lodsb				; AL = drive letter
ch4:	call	getCwd			; DS:SI -> path
	jc	ch8
	PRINTF	<"%c:%c%s",13,10,13,10>,cx,dx,si
	ret
ch8:	EPRINTF	<"Unable to find %c:">,<13,10,13,10>,ax,cx
	stc
	ret
ENDPROC	cmdChdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdCopy
;
; Copy the specified input file to the specified output file, creating the
; output file if it doesn't exist (or truncating it if it does).  Like DOS,
; if the input is a device (eg, "COPY CON TEST.TXT"), CTRLZ ends the copy.
;
; If the output is omitted, it's the input filename (without any drive or
; path) in the current directory; if it's a drive or directory, the input
; filename is copied there.  An input filespec with wildcards copies every
; matching file (see walkFiles), and then the output must be a drive or
; directory (or omitted).  DOS keeps a file from being copied onto itself,
; since it can't be opened for writing while it's open for reading.
;
; Input files separated by '+' (eg, "COPY A+B+C D") are concatenated into the
; output file, which must be specified (see copyCat).  Any switches (eg, /B)
; are ignored, since files are always copied as binary data.
;
; cmdType uses cmdCopy with STDOUT as the output (so wildcards work, too),
; and like DOS, CTRLZ ends the output of every file (see copyData).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdType
	ASSERT	STRUCT,[bx],CMD
	mov	[bx].HDL_OUTPUT,STDOUT
	DEFLBL	cmdCopy,near
	push	di
	lea	di,[bx].LINEBUF + 128
	inc	cx
	rep	movsb			; move input filespec out of the way
	pop	di
	mov	dl,[bx].CMD_ARG
	call	getToken		; was an input filespec specified?
	jc	cp7			; no
	lea	si,[bx].LINEBUF + 128	; DS:SI -> input filespec
	mov	cx,si			; CX = non-zero (for TYPE)
	cmp	[bx].HDL_OUTPUT,0	; do we already have an output (TYPE)?
	jge	cp3			; yes
	push	si
	inc	dx			; DL = index of output filespec
	sub	cx,cx			; (no default)
	call	getFileName		; DS:SI -> output filespec in LINEBUF
	lea	di,[bx].LINEBUF		; DI -> output filename buffer
	jc	cp2			; no output, so use input filename
	call	scanSpec		; any wildcards in the output?
	test	ah,ah
	jnz	cp5			; yes
	lea	di,[bx].LINEBUF
	add	di,cx			; DI -> end of output filespec
	call	chkDir			; is the output a directory?
	jnc	cp2			; yes (DI -> where to append input)
	sub	di,di			; no, so the output is a file
cp2:	mov	cx,di			; CX = output data for copyFile
	pop	si
	push	si
cp2a:	lodsb				; is the input a list of files
	cmp	al,'+'			; to concatenate?
	je	cp4			; yes
	test	al,al
	jnz	cp2a
	pop	si
cp3:	call	scanSpec		; any wildcards in the input?
	test	ah,ah
	jz	copyFile		; no
	jcxz	cp6			; yes, but the output is a single file
	mov	dx,offset copyWild
	call	walkFiles		; copy all the matching files
	jnc	cp9
	test	ax,ax			; was the error already reported?
	jz	cp8			; yes
	jmp	openError		; no, so report it now
cp4:	pop	si
	test	cx,cx			; the output must be a file
	jnz	cp6
	jmp	copyCat
cp5:	pop	si
cp6:	PRINTF	<"Invalid output",13,10,13,10>
	jmp	short cp8
cp7:	jmp	noFile
cp8:	stc
cp9:	ret
ENDPROC	cmdType

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copyFile
;
; Copy one input file (or device) to an output file (or device): open the
; input, open the output, copy the data, and then close them both.  If the
; output is already open (eg, STDOUT for TYPE), it's used and left open.
; Like DOS, the output gets the input file's date and time (a concatenated
; copy keeps the current date and time; see copyCat).  copyWild (for
; walkFiles) prints the input filename first.
;
; Inputs:
;	BX -> CMDHEAP
;	SS:SI -> input filename
;	CX = 0 if LINEBUF contains the output filename; otherwise, CX -> where
;	to append the input filename (without any drive or path) in LINEBUF
;
; Outputs:
;	Carry clear if successful; otherwise, carry set and AX = 0 (the error
;	was reported)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	copyWild
	PRINTF	<"%s",13,10>,si
	DEFLBL	copyFile,near
	call	openInput		; open the input file
	jc	cf8
	cmp	[bx].HDL_OUTPUT,0	; do we already have an output?
	jge	cf3			; yes
	jcxz	cf2			; LINEBUF contains the output filename
	call	scanSpec		; DI -> input name (sans drive/path)
	xchg	si,di
	mov	di,cx
cf1:	lodsb				; append it to the output
	stosb
	test	al,al
	jnz	cf1
cf2:	lea	si,[bx].LINEBUF		; SI -> output filename
	call	openOutput		; open the output file
	jnc	cf3
	cmp	ax,ERR_SHARE		; is the output the input file?
	jne	cf8			; no
	PRINTF	<"File cannot be copied onto itself",13,10,13,10>
	jmp	short cf9
cf3:	push	bx
	mov	bx,[bx].HDL_INPUT
	mov	ax,DOS_HDL_GETTIME
	int	21h			; CX = time, DX = date (0 for a device)
	pop	bx
	push	cx
	push	dx
	call	copyData		; copy (and close) the input
	pop	dx
	pop	cx
	jc	cf9
	test	dx,dx			; does the input have a date?
	jz	cf3c			; no (it's a device)
	push	bx
	mov	bx,[bx].HDL_OUTPUT
	mov	ax,DOS_HDL_SETTIME
	int	21h			; give the output the input's date and time
	pop	bx
cf3c:	call	closeOutput		; close the output (if we opened it)
	jnc	cf9a
cf7a:	call	writeError		; report a failure to update the file
	jmp	short cf9
cf8:	call	openError		; report error (AX) opening file (SI)
cf9:	sub	ax,ax			; AX = 0 (the error was reported)
	stc
cf9a:	ret
ENDPROC	copyWild

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copyCat
;
; Concatenate input files separated by '+' (eg, "A+B+C") into the output file
; (in LINEBUF), which is created first (or truncated if it exists).
;
; Inputs:
;	BX -> CMDHEAP
;	SS:SI -> input filenames
;
; Outputs:
;	Carry clear if successful; otherwise, carry set (the error was reported)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	copyCat
	push	si
	lea	si,[bx].LINEBUF		; SI -> output filename
	call	openOutput		; open the output file
	pop	si
	jnc	cc1
	lea	si,[bx].LINEBUF
	jmp	short cc8
cc1:	mov	di,si			; DI -> next input filename
cc2:	lodsb
	cmp	al,'+'			; end of this filename?
	je	cc3			; yes
	test	al,al			; end of all the filenames?
	jnz	cc2			; no
cc3:	mov	byte ptr [si-1],0	; null-terminate this filename
	push	ax			; AL = '+' if more filenames follow
	push	si			; SI -> next filename (if any)
	mov	si,di
	call	openInput		; open this input file
	jc	cc7
	call	copyData		; copy (and close) it
	pop	si
	pop	ax
	jc	cc9
	cmp	al,'+'			; more filenames?
	je	cc1			; yes
	call	closeOutput		; no, so close the output
	jnc	cc9a
	call	writeError		; report a failure to update the file
	jmp	short cc9
cc7:	pop	cx
	pop	cx
cc8:	call	openError		; report error (AX) opening file (SI)
cc9:	stc
cc9a:	ret
ENDPROC	copyCat

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copyData
;
; Copy the data from the input file (or device) to the output file (or
; device), and then close the input.  Like DOS, CTRLZ ends the data from a
; device, and for TYPE (ie, when the output is STDOUT), from a file, too.
;
; Inputs:
;	BX -> CMDHEAP
;	HDL_INPUT and HDL_OUTPUT are open
;
; Outputs:
;	Carry clear if successful; otherwise, carry set (the error was reported)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	copyData
	push	bx
	mov	bx,[bx].HDL_INPUT
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDATA
	int	21h			; DX bit 7 set if input is a device
	pop	bx
	jnc	cf3a
	sub	dx,dx
cf3a:	and	dx,80h
	cmp	[bx].HDL_OUTPUT,STDOUT	; is this TYPE?
	jne	cf3b			; no
	inc	dx			; yes, so CTRLZ ends a file, too
cf3b:	mov	di,dx			; DI is non-zero if CTRLZ ends the data
	mov	si,PSP_DTA		; SI -> DTA (used as a read buffer)
cf4:	mov	cx,size PSP_DTA		; CX = number of bytes to read
	call	readInput
	jc	cy9
	test	ax,ax			; anything read?
	jz	cy7			; no
	xchg	cx,ax			; CX = number of bytes to write
	test	di,di			; is input a device?
	jz	cf6			; no
	push	di
	mov	di,si
	mov	dx,cx			; DX = number of bytes read
	mov	al,CHR_CTRLZ
	repne	scasb			; any CTRLZ?
	pop	di
	xchg	cx,dx			; CX = number of bytes read
	jne	cf6			; no
	sub	cx,dx			; yes, so write only bytes before it
	dec	cx
	mov	di,-1			; and then stop
cf6:	call	writeOutput
	jc	cy9
	test	di,di			; did input end with CTRLZ?
	jns	cf4			; no
cy7:	call	closeInput		; close the input
	clc
cy9:	ret
ENDPROC	copyData

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdRen
;
; Rename or move one file or directory.  A directory target retains the
; source name; an explicit name can change both its name and its parent.
; Both paths are relative to the current directory, unless qualified.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	DS:SI -> source filename in LINEBUF, CX = length
;
; Outputs:
;	Carry clear on success; otherwise the error is reported and carry set
;
; Modifies:
;	Any
;
DEFPROC	cmdRen
	push	di
	call	scanSpec
	pop	di
	test	ah,ah
	jnz	rn8			; wildcards are not supported
	mov	dl,[bx].CMD_ARG
	push	cx
	call	getToken		; a source is required
	pop	cx
	jc	rn8
	lea	si,[bx].LINEBUF
	push	di
	lea	di,[bx].LINEBUF+128
	inc	cx
	rep	movsb			; retain source while parsing target
	pop	di
	inc	dx
	sub	cx,cx
	call	getFileName		; destination in LINEBUF
	jc	rn8
	push	si
	push	cx
	inc	dx
	call	getToken		; no extra arguments
	pop	cx
	pop	si
	jnc	rn8
	call	scanSpec
	test	ah,ah
	jnz	rn8
	mov	di,si
	add	di,cx
	call	chkDir			; append the source name for a directory
	jc	rn2
	push	di
	lea	si,[bx].LINEBUF+128
	call	scanSpec
	mov	si,di
	pop	di
rn1:	lodsb
	stosb
	test	al,al
	jnz	rn1
rn2:	lea	dx,[bx].LINEBUF+128
	lea	di,[bx].LINEBUF
	mov	ah,DOS_DSK_RENAME
	int	21h
	jc	rn7
	ret
rn7:	mov	si,dx
	mov	dx,offset VERB_REN
	jmp	fileError
rn8:	PRINTF	<"Syntax error",13,10,13,10>
	stc
	ret
ENDPROC	cmdRen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDel
;
; Delete the specified file.  A filespec with wildcards
; deletes every matching file (see walkFiles); like PC DOS, a filename of
; "*.*" asks "Are you sure (Y/N)?" first, until Y or N is entered.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDel
	push	ds
	push	si
	mov	dl,[bx].CMD_ARG
	call	getToken		; was a filename specified?
	jc	de1			; no
	call	chkStrVar		; yes, but is it empty (eg, "" or X$)?
de1:	pop	si			; (if so, cmdDOS replaced it with *.*)
	pop	ds
	jc	de7			; no filename
;
; Like REN, DEL rejects extra arguments, so that an MSBASIC-style expression
; (eg, DEL "TEMP" + N$) is an error, rather than deleting the wrong file.
;
	inc	dx
	call	getToken		; any other argument?
	jnc	rn8			; yes (see cmdRen)
	call	scanSpec		; any wildcards?
	mov	dx,offset delFile
	test	ah,ah
	jz	de6			; no
	cmp	word ptr [di],2E2Ah	; DI -> filename; is it "*.*"?
	jne	de5			; no
	cmp	word ptr [di+2],002Ah
	jne	de5			; no
de3:	PRINTF	<"Are you sure (Y/N)? ">
	push	dx
	push	si
	lea	si,[bx].LINEBUF+128	; (past the filespec in LINEBUF)
	mov	word ptr [si].INP_MAX,2	; 1 char (plus CR)
	mov	dx,si
	mov	ah,DOS_TTY_INPUT
	int	21h
	call	printCRLF
	mov	al,[si].INP_DATA
	pop	si
	pop	dx
	and	al,0DFh			; upper-case the response
	cmp	al,'N'
	je	de9			; no (and carry is clear)
	cmp	al,'Y'
	jne	de3			; neither, so ask again
de5:	call	walkFiles		; yes, delete all matching files
	jmp	short de6a
de6:	call	dx
de6a:	jnc	de9
	mov	dx,offset VERB_DEL
	jmp	fileError
	DEFLBL	noFile,near
de7:	PRINTF	<"Missing filename",13,10,13,10>
de8:	stc
de9:	ret
ENDPROC	cmdDel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; delFile
;
; Delete one file (for cmdDel and walkFiles).
;
; Inputs:
;	DS:SI -> filename
;
; Outputs:
;	Carry clear if successful, set if error (AX = error #)
;
; Modifies:
;	AX, DX
;
DEFPROC	delFile
	mov	dx,si			; DS:DX -> filename
	mov	ah,DOS_DSK_DELETE
	int	21h
	ret
ENDPROC	delFile

;
; walkFiles and scanSpec are shared with the FIND and WC utilities.
;
UTIL_PCH equ byte ptr ss:[bx].PATH_CHAR
	include	util.inc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkDir
;
; Determine whether a filespec refers to a directory: it either ends with ":"
; or the path char, or "filespec/*.*" either succeeds or fails with ERR_NOFILE
; (any other error, like ERR_NOPATH or a drive that isn't ready, means it's not
; a directory).  For DIR and COPY.
;
; Inputs:
;	SS:BX -> CMDHEAP
;	SS:SI -> filespec
;	SS:DI -> end of filespec (its null terminator)
;
; Outputs:
;	If carry clear, the filespec is a directory, it now ends with ":" or
;	the path char, and DI -> its (new) null terminator; otherwise, carry is
;	set and the filespec is unchanged
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	chkDir
	mov	al,[di-1]
	cmp	al,':'			; does filespec end with ":"
	je	cd9			; or the path char?
	mov	ah,ss:[bx].PATH_CHAR
	cmp	al,ah
	je	cd9			; yes (and carry is clear)
	push	di
	mov	al,ah
	stosb				; append the path char
	push	si
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	REPS	MOVS,ES,CS,BYTE		; and DIR_DEF
	pop	si
	mov	dx,si			; DS:DX -> filespec (CX is zero)
	mov	ah,DOS_DSK_FFIRST
	int	21h
	pop	di
	jnc	cd8			; it's a directory
	cmp	ax,ERR_NOFILE		; is it an empty directory?
	je	cd8			; yes
	mov	byte ptr [di],0		; no, so remove the path char, etc
	stc
	ret
cd8:	inc	di			; keep the path char
	mov	byte ptr [di],0
	clc
cd9:	ret
ENDPROC	chkDir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getCwd
;
; Get the current directory of a drive (eg, for CD and the prompt).
;
; Inputs:
;	AL = drive letter (upper-case)
;	BX -> CMDHEAP
;
; Outputs:
;	CL = drive letter, DL = path char, DS:SI -> LINEBUF
;	If carry clear, LINEBUF contains the path (without the drive or
;	leading path char); otherwise, AX = error code
;
; Modifies:
;	AX, CX, DX, SI, DS
;
DEFPROC	getCwd
	xchg	cx,ax			; CL = drive letter
	mov	dl,cl
	sub	dl,'A'-1		; DL = 1-based drive #
	lea	si,[bx].LINEBUF
	push	ss
	pop	ds			; DS:SI -> buffer
	mov	ah,DOS_DSK_GETCWD
	int	21h
	mov	dl,[bx].PATH_CHAR	; DL = path char
	ret
ENDPROC	getCwd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strCurDir (CURDIR$)
;
; Returns the current drive and directory (eg, "C:/SAMPLES"), as CD displays.
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strCurDir,FAR
	RETVAR	retDir,dword
	LOCVAR	dirBuf,byte,68
	ENTER
	push	ds
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	ah,DOS_DSK_GETDRV
	int	21h			; AL = current drive #
	add	al,'A'
	mov	ah,':'
	lea	di,[dirBuf]
	stosw				; "d:"
	mov	bx,ds:[PSP_HEAP]
	mov	al,[bx].PATH_CHAR
	stosb				; path char
	mov	si,di			; DS:SI -> rest of buffer
	mov	dl,0			; DL = 0 (current drive)
	mov	ah,DOS_DSK_GETCWD
	int	21h
	mov	cx,64
	mov	al,0
	repne	scasb			; find the null
	pop	ds
	lea	si,[dirBuf]
	lea	cx,[di-1]
	sub	cx,si			; CX = length
	call	newStr
	mov	[retDir].OFF,ax
	mov	[retDir].SEG,dx
	LEAVE
	RETURN
ENDPROC	strCurDir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getExists (EXISTS)
;
; Returns -1 (true) if a file or directory matching the filespec (which may
; contain wildcards) exists, or 0 (false) if not; eg:
;
;	IF NOT EXISTS("OBJ") THEN MD OBJ
;
; EXISTS uses a temporary DTA, so that it doesn't disturb a DIR$ search.
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
DEFPROC	getExists,FAR
	RETVAR	retExists,dword
	ARGVAR	pSpec,dword
	LOCVAR	findBuf,byte,<size FFB + 1>
	ENTER
	push	ds
	push	ss
	pop	ds
	lea	dx,[findBuf]		; DS:DX -> temporary DTA
	mov	ah,DOS_DSK_SETDTA
	int	21h
	les	di,[pSpec]
	mov	cx,16h			; hidden, system, and directory attrs
	call	findSpec
	cmc
	sbb	ax,ax			; AX = -1 if found, 0 if not
	mov	[retExists].LOW,ax
	mov	[retExists].HIW,ax
	mov	dx,PSP_DTA
	mov	ah,DOS_DSK_SETDTA
	int	21h			; restore the DTA
	pop	ds
	LEAVE
	RETURN
ENDPROC	getExists

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strDir (DIR$)
;
; Returns the first file or directory matching the filespec (which may contain
; wildcards), or if the filespec is omitted (or empty), the next match.  The
; result contains the match's attributes (1 byte), time (2), date (2), and
; size (4), followed by its name; it's empty if there are no (more) matches.
; The default attributes (16h) include hidden, system, and directory entries;
; 8 finds the volume label.  eg:
;
;	F$ = DIR$("*.BAS")
;	WHILE F$ <> "" : PRINT MID$(F$, 10) : F$ = DIR$ : WEND
;
; Inputs:
;	32-bit return value
;	string value (popped)
;	32-bit attributes (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strDir,FAR
	RETVAR	retFind,dword
	ARGVAR	pFindSpec,dword
	ARGVAR	findAttr,dword
	ENTER
	push	ds
	les	di,[pFindSpec]
	mov	cx,[findAttr].LOW	; CX = attributes
	test	di,di			; filespec omitted (or empty)?
	jz	sd1			; yes
	call	findSpec
	jmp	short sd2
sd1:	push	ss
	pop	ds
	mov	ah,DOS_DSK_FNEXT
	int	21h
sd2:	mov	cx,0			; CX = 0 (empty result) if no match
	jc	sd3
	mov	si,PSP_DTA + FFB_NAME
	DOSUTIL	STRLEN			; AX = name length
	add	ax,FFB_NAME - FFB_ATTR	; plus attributes, time, date, and size
	xchg	cx,ax
	mov	si,PSP_DTA + FFB_ATTR	; SS:SI -> result
sd3:	call	newStr
	mov	[retFind].OFF,ax
	mov	[retFind].SEG,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	strDir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findSpec
;
; Copy a filespec string to LINEBUF (null-terminated), release the string,
; and find the first match (for EXISTS and DIR$).
;
; Inputs:
;	ES:DI = string value
;	CX = attributes
;
; Outputs:
;	DS = SS; if carry clear, the DTA contains the first match;
;	otherwise, AX = error code
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	findSpec
	push	cx
	push	es
	push	di
	push	es
	pop	ds
	mov	si,di			; DS:SI -> filespec
	push	ss
	pop	es
	mov	di,ss:[PSP_HEAP]
	lea	di,[di].LINEBUF
	mov	dx,di			; ES:DX -> LINEBUF
	sub	cx,cx
	test	si,si			; empty string?
	jz	fs1			; yes
	lodsb
	mov	cl,al
	rep	movsb			; copy the filespec to LINEBUF
fs1:	xchg	ax,cx
	stosb				; and null-terminate it
	pop	di
	pop	es
	call	releaseStr
	push	ss
	pop	ds			; DS:DX -> filespec
	pop	cx			; CX = attributes
	mov	ah,DOS_DSK_FFIRST
	int	21h
	ret
ENDPROC	findSpec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strPath (PATH$)
;
; Returns the directories that COMMAND searches for programs (see setPath
; and findProgram).  PATH$ is kept in CMDHEAP (PATH_BUF), so unlike other
; variables, it survives NEW, CLEAR, RUN, etc.
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strPath,FAR
	RETVAR	retPath,dword
	ENTER
	mov	si,ss:[PSP_HEAP]
	lea	si,[si].PATH_BUF
	mov	cl,ss:[si]
	mov	ch,0
	inc	si			; SS:SI -> characters, CX = length
	call	newStr
	mov	[retPath].OFF,ax
	mov	[retPath].SEG,dx
	LEAVE
	RETURN
ENDPROC	strPath

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setPath (PATH$ = string)
;
; Copies up to 120 characters of the string to PATH_BUF (as a length byte,
; the characters, and a null).
;
; Input stack:
;	string value
;
; Output stack:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	setPath,FAR
	ARGVAR	pPath,dword
	ENTER
	push	ds
	push	ss
	pop	es
	mov	di,es:[PSP_HEAP]
	lea	di,[di].PATH_BUF	; ES:DI -> PATH_BUF
	lds	si,[pPath]
	sub	cx,cx
	test	si,si			; empty string?
	jz	sp1			; yes
	lodsb
	mov	cl,al			; CX = length
	cmp	cl,120
	jbe	sp1
	mov	cl,120
sp1:	mov	al,cl
	stosb
	rep	movsb
	mov	al,0
	stosb
	pop	ds
	les	di,[pPath]
	call	releaseStr
	LEAVE
	RETURN
ENDPROC	setPath

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; initEnv
;
; Sets up the environment that programs receive (see buildEnv), sets PATH$
; from our own environment's PATH, if any (eg, when MAKE runs "COMMAND /C"),
; and checks the command tail for /C, which runs the rest of the tail as a
; command and then exits.
;
; The environment is a block of its own, allocated from the top of memory, so
; that it's never left after our memory block, where it would keep our
; transient portion from being reused while it's set aside (see runTransient).
; If there's no room for it, programs get no environment (see buildEnv).
;
; Inputs:
;	BX -> CMDHEAP
;	DS = ES = SS
;
; Outputs:
;	CMD_SINGLE set in CMD_FLAGS if /C was specified
;
; Modifies:
;	AX, CX, DX, SI, DI
;
ENV_LEN	equ	176			; environment size (see buildEnv)

DEFPROC	initEnv
	push	bx
	mov	bx,ENV_LEN SHR 4
	mov	ax,(DOS_MEM_ALLOC SHL 8) OR MCBTYPE_HIGH
	int	21h			; AX = environment segment
	pop	bx
	jnc	ie1
	sub	ax,ax			; no room, so no environment
ie1:	mov	[bx].EXECDATA.EPB_ENVSEG,ax
	push	ds
	mov	ds,ds:[PSP_ENVSEG]
	mov	ax,ds
	test	ax,ax			; do we have an environment?
	jz	ie6			; no
	sub	si,si			; DS:SI -> environment
ie2:	cmp	byte ptr [si],0		; end of the environment?
	je	ie6			; yes
	cmp	word ptr [si],'AP'	; "PATH="?
	jne	ie3
	cmp	word ptr [si+2],'HT'
	jne	ie3
	cmp	byte ptr [si+4],'='
	je	ie4			; yes
ie3:	lodsb				; no, so skip to the next variable
	test	al,al
	jnz	ie3
	jmp	ie2
ie4:	add	si,5
	lea	di,[bx].PATH_BUF+1	; ES:DI -> PATH_BUF characters
	mov	dx,di
	mov	cx,120
ie5:	lodsb
	test	al,al
	jz	ie5a
	stosb
	loop	ie5
ie5a:	mov	byte ptr es:[di],0
	sub	di,dx
	xchg	ax,di			; AL = length
	mov	es:[bx].PATH_BUF,al
ie6:	pop	ds
	mov	si,PSP_CMDTAIL
	lodsb
	cbw
	xchg	cx,ax			; CX = length of tail
	jcxz	ie9
ie7:	lodsb
	cmp	al,CHR_SPACE		; skip leading whitespace
	ja	ie8
	loop	ie7
	ret
ie8:	cmp	al,'/'			; "/C" (as the C runtime uses)?
	je	ie8a
	cmp	al,[bx].SWITCH_CHAR	; or the switch char?
	jne	ie9
ie8a:	mov	al,[si]
	or	al,20h
	cmp	al,'c'
	jne	ie9
	cmp	byte ptr [si+1],CHR_SPACE
	ja	ie9
	mov	word ptr [si-1],(CHR_SPACE SHL 8) OR CHR_SPACE
	or	[bx].CMD_FLAGS,CMD_SINGLE; blank the switch and set the flag
ie9:	ret
ENDPROC	initEnv

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; buildEnv
;
; Builds the environment that programs receive (EPB_ENVSEG), with COMSPEC
; (for programs like MAKE that run commands with "COMMAND /C") and PATH (from
; PATH$), so that it's up-to-date for the next program.
;
; Inputs:
;	BP -> CMDHEAP
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	buildEnv
	push	ax
	push	si
	push	di
	push	es
	mov	es,[bp].EXECDATA.EPB_ENVSEG
	mov	ax,es
	test	ax,ax			; is there an environment?
	jz	be9			; no
	sub	di,di			; ES:DI -> environment
	mov	si,offset ENV_VARS
	call	be2			; copy "COMSPEC="
	push	si
	mov	si,offset CMD_PATH
	call	be2			; copy COMMAND's path
	stosb				; and null-terminate it
	pop	si
	call	be2			; copy "PATH="
	lea	si,[bp].PATH_BUF+1
be1:	lods	byte ptr ss:[si]	; copy PATH$ (and its null)
	stosb
	test	al,al
	jnz	be1
	stosb				; end the environment
be9:	pop	es
	pop	di
	pop	si
	pop	ax
	ret
be2:	lods	byte ptr cs:[si]
	test	al,al
	jz	be3
	stosb
	jmp	be2
be3:	ret
ENDPROC	buildEnv

ENV_VARS	db	"COMSPEC=",0,"PATH=",0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findProgram
;
; Find the program named at DS:SI, first as specified, and then (if the name
; contains no drive or path) in each directory listed in PATH$, separated by
; semicolons (eg, "A:\;A:\EXT;A:\SAMPLES").  If the name has no extension,
; .COM, .EXE, .BAT, and .BAS are tried, in that order, starting with DX (eg,
; LOAD starts with .BAT).  A name longer than 64 characters isn't searched.
;
; Inputs:
;	SS:BX -> CMDHEAP
;	DS:SI -> null-terminated name in LINEBUF
;	CX = length of name
;	DX -> first extension to try (COM_EXT or BAT_EXT)
;
; Outputs:
;	If carry clear, LINEBUF contains the name of the program found (with
;	any directory from PATH$ in front), and CX = its length (not including
;	any extension that was added)
;	If carry set, AX = error #, and LINEBUF contains the original name
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	findProgram
	push	bp
	mov	bp,dx			; BP -> first extension
	call	tryProgram		; try the name as specified
	jc	fp0
fp9:	pop	bp
	ret
fp0:	push	ax			; save the error
	cmp	cx,64			; is the name too long to search
	ja	fp8			; for (see the copy at LINEBUF+190)?
	mov	dl,[bx].PATH_CHAR
	mov	di,si
fp1:	mov	al,[di]
	inc	di
	cmp	al,':'			; drive specified?
	je	fp8			; yes, so don't search
	cmp	al,dl			; path specified?
	je	fp8			; yes, so don't search
	test	al,al
	jnz	fp1
	push	cx			; save the original length
	inc	cx
	lea	di,[si+190]
	push	si
	rep	movsb			; and the name, at the end of LINEBUF
	pop	si
	lea	dx,[bx].PATH_BUF+1	; DX -> PATH$ characters
fp2:	mov	di,si			; DI -> LINEBUF
	xchg	dx,si
fp3:	lodsb				; copy the next directory
	cmp	al,';'
	je	fp4
	stosb
	test	al,al
	jnz	fp3
	dec	di			; (the null isn't part of it)
fp4:	xchg	dx,si			; DX -> following directory, if any
	push	ax			; AL = 0 if there isn't one
	mov	cx,di
	sub	cx,si			; CX = length of directory
	jcxz	fp7			; skip an empty directory
	cmp	cx,63
	ja	fp7			; and one that's too long
	mov	al,[bx].PATH_CHAR
	cmp	[di-1],al		; does it end with the path char?
	je	fp5			; yes
	stosb				; no, so add one
fp5:	push	si
	add	si,190
fp5a:	lodsb				; append the name
	stosb
	test	al,al
	jnz	fp5a
	pop	si
	lea	cx,[di-1]
	sub	cx,si			; CX = length of the new name
	DOSUTIL	STRUPR
	push	dx
	mov	dx,bp
	call	tryProgram
	pop	dx
	jnc	fp10			; found it
fp7:	pop	ax
	test	al,al			; was that the last directory?
	jnz	fp2			; no
	pop	cx			; restore the original length
	push	cx
	inc	cx
	mov	di,si
	push	si
	add	si,190
	rep	movsb			; and the original name
	pop	si
	pop	cx
fp8:	pop	ax			; restore the original error
	stc
	jmp	fp9
fp10:	add	sp,6			; discard AL, length, and error
	jmp	fp9			; (carry is clear)
ENDPROC	findProgram

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; tryProgram
;
; Inputs:
;	SS:BX -> CMDHEAP
;	DS:SI -> null-terminated name
;	CX = length of name
;	DX -> first extension to try (if the name has none)
;
; Outputs:
;	If carry clear, the program exists (and any extension that was needed
;	has been appended to the name); otherwise, AX = error # and the name is
;	unchanged
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	tryProgram
	call	chkExt			; any extension?
	jnc	tp8			; yes
tp1:	mov	di,si
	call	addString		; append the next extension
	call	findFile
	jnc	tp9
	add	dx,COM_EXT_LEN
	cmp	dx,offset BAS_EXT
	jbe	tp1
	mov	di,si
	add	di,cx
	mov	byte ptr [di],0		; every extension failed, so remove it
	mov	ax,ERR_NOFILE
	stc
tp9:	ret
tp8:	jmp	findFile
ENDPROC	tryProgram

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMkdir
;
; Create a directory (MD), or with cmdRmdir, remove a directory (RD).
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
DEFPROC	cmdMkdir
	mov	al,DOS_DSK_MKDIR
	jmp	short md1
	DEFLBL	cmdRmdir,near
	mov	al,DOS_DSK_RMDIR
md1:	push	ax
	mov	dl,[bx].CMD_ARG
	sub	cx,cx			; no default
	call	getFileName		; DS:SI -> directory
	pop	ax
	jc	md8
	mov	ah,al
	mov	dx,si
	push	ax
	int	21h
	pop	dx			; DH = function
	jnc	md9
	cmp	dh,DOS_DSK_MKDIR
	mov	dx,offset VERB_MD
	je	md7
	mov	dx,offset VERB_RD
md7:	jmp	fileError
md8:	jmp	noFile			; report a missing name
md9:	ret
ENDPROC	cmdMkdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkExt
;
; Check the last component of a path (DS:SI) for a period, so that periods
; in directory names (eg, "..") aren't mistaken for an extension.
;
; Inputs:
;	SS:BX -> CMDHEAP
;	DS:SI -> null-terminated path
;
; Outputs:
;	If carry clear, DI points to the period; otherwise, DI = SI
;
; Modifies:
;	DI
;
DEFPROC	chkExt
	push	ax
	push	bx
	push	dx
	push	si
	mov	dl,ss:[bx].PATH_CHAR	; DL = path char
	mov	bx,si			; BX = DI if there's no period
	mov	di,bx
ce1:	lodsb
	cmp	al,'.'
	jne	ce2
	lea	di,[si-1]		; DI -> period
ce2:	cmp	al,dl			; path char?
	jne	ce3			; no
	mov	di,bx			; yes, so forget any earlier period
ce3:	test	al,al
	jnz	ce1
	cmp	bx,di
	cmc				; carry set if DI = BX (no period)
	pop	si
	pop	dx
	pop	bx
	pop	ax
	ret
ENDPROC	chkExt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openInput
;
; Open the specified input file; used by "COPY", "LOAD", etc.
;
; Inputs:
;	SS:BX -> CMDHEAP
;	DS:SI -> filename
;
; Outputs:
;	If carry clear, HDL_INPUT is updated
;
; Modifies:
;	AX, DX
;
DEFPROC	openInput
	mov	dx,si			; DX -> filename
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	oi9
	ASSERT	STRUCT,ss:[bx],CMD
	mov	ss:[bx].HDL_INPUT,ax	; save file handle
oi9:	ret
ENDPROC	openInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openOutput
;
; Create (or truncate) the specified output file; used by "COPY", "SAVE", etc.
;
; Inputs:
;	SS:BX -> CMDHEAP
;	DS:SI -> filename
;
; Outputs:
;	If carry clear, HDL_OUTPUT is updated
;
; Modifies:
;	AX, DX
;
DEFPROC	openOutput
	push	cx
	mov	dx,si			; DX -> filename
	sub	cx,cx			; CX = attributes (none)
	mov	ah,DOS_HDL_CREATE
	int	21h
	pop	cx
	jc	oo9
	ASSERT	STRUCT,ss:[bx],CMD
	mov	ss:[bx].HDL_OUTPUT,ax	; save file handle
oo9:	ret
ENDPROC	openOutput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openError
;
; Report an error opening a file, or with fileError, any other file or
; directory operation (eg, "Unable to delete X.TXT"; DEBUG builds also
; display the error #, as in "Unable to delete X.TXT (5)").
;
; Inputs:
;	AX = error # (ERR_NOTREADY is reported as "Drive not ready",
;	ERR_NOSESSION as "No sessions available to run X", ERR_NOMEMORY as
;	"Unable to load X", and ERR_NOFILE or ERR_NOPATH as "Unable to find X")
;	DS:SI -> filename
;	CS:DX -> verb (fileError only; eg, "delete")
;
; Outputs:
;	Carry set
;
; Modifies:
;	None
;
DEFPROC	openError
	push	dx
	mov	dx,offset VERB_OPEN
	call	fileError
	pop	dx
	ret
	DEFLBL	fileError,near
	push	ax
	push	dx
	cmp	ax,ERR_NOTREADY		; drive not ready?
	jne	fer1			; no
	PRINTF	<"Drive not ready",13,10,13,10>
	jmp	fer2
fer1:	cmp	ax,ERR_NOSESSION	; no session for a pipeline command?
	jne	fer3			; no
	push	bx
	push	di
	mov	bx,si
	sub	di,di			; DI -> last period (none yet)
fer1a:	mov	al,[bx]
	inc	bx
	cmp	al,'.'
	jne	fer1b
	lea	di,[bx-1]
fer1b:	test	al,al
	jnz	fer1a
	test	di,di			; any period?
	jnz	fer1c			; yes
	lea	di,[bx-1]		; no, so use the whole name
fer1c:	sub	di,si			; DI = length of name without extension
	PRINTF	<"No sessions available to run %.*s",13,10,13,10>,di,si
	pop	di
	pop	bx
	jmp	short fer2
fer3:	cmp	ax,ERR_NOMEMORY		; not enough memory?
	jne	fer4			; no
	mov	dx,offset VERB_LOAD	; yes, so report "Unable to load X"
fer4:	cmp	ax,ERR_NOFILE		; file not found?
	je	fer5			; yes
	cmp	ax,ERR_NOPATH		; path not found?
	jne	fer6			; no
fer5:	mov	dx,offset VERB_FIND	; yes, so report "Unable to find X"
fer6:	EPRINTF	<"Unable to %ls %s">,<13,10,13,10>,ax,dx,cs,si
fer2:	pop	dx
	pop	ax
	stc
	ret
ENDPROC	openError

VERB_OPEN	db	"open",0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openPipe
;
; Open a pipe.  If successful, the caller will use the handle (AX)
; to extract the corresponding SFH from PSP_PFT and store it in both the
; current session's PSP_PFT STDOUT slot and the next session's SPB_SFHIN.
;
; Inputs:
;	None
;
; Outputs:
;	If carry clear, AX is new pipe handle; otherwise, AX is error
;
; Modifies:
;	AX
;
DEFPROC	openPipe
	push	dx
	push	ds
	push	cs
	pop	ds
	mov	dx,offset PIPE_NAME	; DS:DX -> PIPE_NAME
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jnc	op1
	push	si
	mov	si,dx
	call	openError		; report error (AX) opening file (SI)
	pop	si
op1:	pop	ds
	pop	dx
	ret
ENDPROC	openPipe

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pipeStages
;
; Count the commands of the pipeline that follow the current command (ie,
; the command fed by its output pipe, plus one for every '|' after that), so
; that DOS can set aside memory for the sessions they will need (see
; load_program).  The symbol following the current command has been
; null-terminated (see parseDOS), which is why HDL_OUTPIPE accounts for it.
;
; Inputs:
;	BP -> CMDHEAP
;
; Outputs:
;	CH = number of commands that follow, CL = 0
;
; Modifies:
;	CX
;
DEFPROC	pipeStages
	push	ax
	push	bx
	push	si
	push	di
	sub	cx,cx
	cmp	[bp].HDL_OUTPIPE,cx	; is our output a pipe?
	je	pst1			; no
	inc	ch			; yes, count the command it feeds
pst1:	lea	di,[bp].TOKENBUF	; DI -> TOKENBUF
	mov	al,[bp].CMD_ARG
	mov	ah,0
	add	ax,ax
	add	ax,ax
	ASSERT	<size TOKLET>,EQ,4	; AX = offset of our 1st TOKLET
	xchg	bx,ax
	mov	al,[di].TOK_CNT
	mov	ah,0
	add	ax,ax
	add	ax,ax			; AX = end of TOKLETs
pst2:	cmp	bx,ax
	jae	pst9
	cmp	[di].TOK_DATA[bx].TOKLET_CLS,CLS_SYM
	jne	pst3
	mov	si,[di].TOK_DATA[bx].TOKLET_OFF
	cmp	byte ptr [si],'|'	; another pipe symbol?
	jne	pst3			; no
	inc	ch
pst3:	add	bx,size TOKLET
	jmp	pst2
pst9:	pop	di
	pop	si
	pop	bx
	pop	ax
	ret
ENDPROC	pipeStages

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; endPipes
;
; Wait for every session running a command of the current pipeline (see
; PIPE_SCB) to end, after ending them if AL is non-zero (eg, when another
; command of the pipeline failed).
;
; Inputs:
;	AL = non-zero to end the sessions first
;	BX -> CMDHEAP
;
; Outputs:
;	PIPE_SCB is zero, carry clear
;
; Modifies:
;	CX
;
DEFPROC	endPipes
	mov	cx,32			; CL = SCB # (counting down from 32)
ep1:	dec	cx
	shl	[bx].PIPE_SCB.LOW,1
	rcl	[bx].PIPE_SCB.HIW,1
	jnc	ep3
	push	ax
	test	al,al
	jz	ep2
	DOSUTIL	END			; end the program in session CL
ep2:	DOSUTIL	WAITEND			; and wait for the session to end
	pop	ax
ep3:	jcxz	ep9
	jmp	ep1
ep9:	clc
	ret
ENDPROC	endPipes

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addPipe
;
; Record a session running a command of the current pipeline (see endPipes).
;
; Inputs:
;	BP -> CMDHEAP
;	CL = SCB #
;
; Modifies:
;	AX, DX
;
DEFPROC	addPipe
	push	cx
	mov	ch,0
	mov	ax,1
	cwd				; DX:AX = 1
	jcxz	ap2
ap1:	shl	ax,1
	rcl	dx,1
	loop	ap1
ap2:	or	[bp].PIPE_SCB.LOW,ax
	or	[bp].PIPE_SCB.HIW,dx
	pop	cx
	ret
ENDPROC	addPipe

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; closeInput
;
; Close the input file handle (HDL_INPUT), or with closeOutput, the output
; file handle (HDL_OUTPUT), and mark it unused (-1).  A handle that we didn't
; open (eg, STDOUT for TYPE) is left alone.
;
; Inputs:
;	BX -> CMDHEAP
;
; Outputs:
;	If carry set, the file couldn't be closed (AX = error #)
;
; Modifies:
;	AX
;
DEFPROC	closeInput
	mov	ax,HDL_INPUT
	jmp	short ci1
	DEFLBL	closeOutput,near
	mov	ax,HDL_OUTPUT
ci1:	push	bx
	ASSERT	STRUCT,[bx],CMD
	add	bx,ax			; BX -> handle
	mov	ax,-1
	xchg	ax,[bx]			; AX = handle
	cmp	ax,STDPRN		; did we open it?
	jle	ci8			; no
	xchg	bx,ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	jmp	short ci9
ci8:	mov	[bx],ax			; restore the handle
	clc
ci9:	pop	bx
	ret
ENDPROC	closeInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; readInput
;
; Read CX bytes from the default file into the buffer at DS:SI.
;
; Inputs:
;	BX -> CMDHEAP
;	CX = number of bytes
;	DS:SI -> buffer
;
; Outputs:
;	If carry clear, AX = number of bytes read
;	If carry set, an error message was printed
;
; Modifies:
;	AX, DX
;
DEFPROC	readInput
	push	bx
	mov	dx,si
	ASSERT	STRUCT,[bx],CMD
	mov	bx,[bx].HDL_INPUT
	mov	ah,DOS_HDL_READ
	int	21h
	jnc	ri9
	PRINTF	<"Unable to read file",13,10,13,10>
	stc
ri9:	pop	bx
	ret
ENDPROC	readInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; seekInput
;
; Seek to the specified position of the input file.
;
; Inputs:
;	BX -> CMDHEAP
;	CX:DX = absolute position
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	seekInput
	push	bx
	ASSERT	STRUCT,[bx],CMD
	mov	bx,[bx].HDL_INPUT
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	pop	bx
	ret
ENDPROC	seekInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeOutput
;
; Write CX bytes to the default file from the buffer at DS:SI.
;
; Inputs:
;	SS:BX -> CMDHEAP
;	CX = number of bytes
;	DS:SI -> buffer
;
; Outputs:
;	If carry clear, AX = number of bytes written
;	If carry set, an error message was printed
;
; Like PC DOS, BASIC-DOS doesn't treat running out of disk space as an error;
; it simply writes fewer bytes than requested, so we must check for that, too
; (but only for files, since it doesn't mean anything for devices).
;
; Modifies:
;	AX, DX
;
DEFPROC	writeOutput
	push	bx
	mov	dx,si
	ASSERT	STRUCT,ss:[bx],CMD
	mov	bx,ss:[bx].HDL_OUTPUT
	mov	ah,DOS_HDL_WRITE
	int	21h
	jc	wo8
	cmp	ax,cx			; were all the bytes written?
	jae	wo8			; yes (carry clear)
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDATA
	int	21h			; DX bit 7 set if output is a device
	jc	wo7
	test	dl,80h			; device?
	jnz	wo8			; yes (carry clear)
wo7:	pop	bx
	PRINTF	<"Insufficient disk space",13,10,13,10>
	stc
	ret
	DEFLBL	writeError,near
	PRINTF	<"Unable to write file",13,10,13,10>
	stc
	ret
wo8:	pop	bx
	jc	writeError
	ret
ENDPROC	writeOutput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openHandle
;
; Open a handle for redirection.  An input handle requires an existing file
; (or device), whereas an output handle creates the file if it doesn't exist
; (or truncates it if it does).  An append handle opens an existing file and
; seeks to the end, or creates the file if it can't be opened.  As with any
; other filename, the name can be quoted or a string variable (see openVar).
;
; Inputs:
;	AL = 0 for input (read-only), 1 for output (create/truncate),
;	or 2 for append
;	DI -> TOKENBUF
;	BX = token offset
;	BP -> CMDHEAP
;
; Outputs:
;	BX = next token offset
;	If carry clear, AX is new handle; otherwise, the error was reported
;
; Modifies:
;	AX, BX
;
DEFPROC	openHandle
	push	cx
	push	dx
	push	si
	push	di
	sub	cx,cx
	add	bx,size TOKLET
	mov	si,[di].TOK_DATA[bx].TOKLET_OFF
	mov	cl,[di].TOK_DATA[bx].TOKLET_LEN
	lea	dx,[bp].LINEBUF		; DX -> buffer for the name
	call	openVar			; AX = handle (or error)
	pop	di
	pop	si
	pop	dx
	pop	cx
	ret
ENDPROC	openHandle

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openVar
;
; Open a file (or device) for redirection (see openName), using a name that
; can be quoted or a string variable (see chkStrVar), such as the name after
; ">" (see openHandle) or ":>" (see redirOut).
;
; Inputs:
;	AL = 0 for input, 1 for output, or 2 for append (see openHandle)
;	SS:SI -> name, CX = length
;	SS:DX -> buffer for the null-terminated name (eg, LINEBUF)
;	DS = SS
;
; Outputs:
;	If carry clear, AX is new handle; otherwise, the error was reported
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	openVar
	push	ax
	call	chkStrVar		; DS:SI -> name (eg, F$'s value)
	pop	ax
	jnc	ov1
	jmp	noFile			; report a missing name
ov1:	push	ss
	pop	es
	mov	di,dx
	rep	movsb
	mov	es:[di],cl		; null-terminate the name (CX is zero)
	push	ss
	pop	ds			; DS:DX -> name (fall into openName)
ENDPROC	openVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openName
;
; Open a file (or device) for redirection, as described for openHandle;
; openVar uses this, too.  openMode (for OPEN; see openFile) does the same,
; without reporting an error.  Like MSBASIC (whose FCB opens are read-only
; for a read-only file), random access opens a read-only file for reading.
;
; Inputs:
;	AL = 0 for input, 1 for output, or 2 for append (see openHandle),
;	or 3 for random access (openMode only; like append, without the seek)
;	DS:DX -> null-terminated name
;
; Outputs:
;	If carry clear, AX is new handle; otherwise, AX is error (reported
;	by openName only)
;
; Modifies:
;	AX
;
DEFPROC	openName
	call	openMode
	jnc	on9
	push	si
	mov	si,dx
	call	openError		; report error (AX) opening file (SI)
	pop	si
on9:	ret
ENDPROC	openName

DEFPROC	openMode
	push	bx
	push	cx
	mov	ah,DOS_HDL_OPEN
	cmp	al,1			; input handle?
	jb	oh0b			; yes (AL = 0 for read-only access)
	je	oh0a			; no, output handle
	mov	cl,al			; CL = 2 (append) or 3 (random)
	mov	al,MODE_ACC_RW
	int	21h			; so try opening an existing file
	jnc	oh0d
	cmp	ax,ERR_ACCDENIED	; is the file read-only?
	jne	oh0a			; no, so create it
	cmp	cl,3			; random access?
	jne	oh0c			; no (and carry is set)
	mov	ax,DOS_HDL_OPENRO	; yes, so open it for reading
	jmp	short oh0b
oh0d:	cmp	cl,3			; random access?
	je	oh0c			; yes (carry is clear)
	xchg	bx,ax			; BX = handle
	push	dx
	sub	cx,cx
	sub	dx,dx
	mov	ax,DOS_HDL_SEEKEND
	int	21h			; seek to the end of the file
	pop	dx
	xchg	ax,bx			; AX = handle
	clc
	jmp	short oh0c
oh0a:	sub	cx,cx			; CX = attributes (none)
	mov	ah,DOS_HDL_CREATE
oh0b:	int	21h
oh0c:	pop	cx
	pop	bx
	ret
ENDPROC	openMode

VERB_CD		db	"change to",0
VERB_DEL	db	"delete",0
	public	VERB_FIND
VERB_FIND	db	"find",0
VERB_LOAD	db	"load",0
VERB_MD		db	"create",0
VERB_RD		db	"remove",0
VERB_REN	db	"rename",0

CODE	ENDS

	end
