;
; BASIC-DOS Directory Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<countLine,chkString,getFileName,getToken>
	EXTNEAR	<openInput,openOutput,openError,readInput,writeOutput>
	EXTNEAR	<writeError,closeInput,closeOutput,fileError>
	EXTSTR	<DIR_DEF,PERIOD>

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
ch8:	PRINTF	<"Unable to find %c: (%d)",13,10,13,10>,cx,ax
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
; cmdType uses cmdCopy with STDOUT as the output (so wildcards work, too).
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
; copyWild (for walkFiles) prints the input filename first.
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
cf7a:	call	writeError		; report a failure to update the file
	jmp	short cf9
cf8:	call	openError		; report error (AX) opening file (SI)
cf9:	sub	ax,ax			; AX = 0 (the error was reported)
	stc
	ret

cf3:	push	bx
	mov	bx,[bx].HDL_INPUT
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDATA
	int	21h			; DX bit 7 set if input is a device
	pop	bx
	jnc	cf3a
	sub	dx,dx
cf3a:	and	dx,80h
	mov	di,dx			; DI is non-zero if input is a device
	mov	si,PSP_DTA		; SI -> DTA (used as a read buffer)
cf4:	mov	cx,size PSP_DTA		; CX = number of bytes to read
	call	readInput
	jc	cf9
	test	ax,ax			; anything read?
	jz	cf7			; no
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
	jc	cf9
	test	di,di			; did input end with CTRLZ?
	jns	cf4			; no
cf7:	call	closeInput		; close the input
	call	closeOutput		; and the output (if we opened it)
	jc	cf7a
	ret
ENDPROC	copyWild

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDel
;
; Delete the specified file (also used by ERASE).  A filespec with wildcards
; deletes every matching file (see walkFiles).
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
	push	si
	mov	dl,[bx].CMD_ARG
	call	getToken		; was a filename specified?
	pop	si
	jc	de7			; no
	call	scanSpec		; any wildcards?
	mov	dx,offset delFile
	test	ah,ah
	jz	de6			; no
	call	walkFiles		; yes, delete all matching files
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; walkFiles
;
; Call a function for every file matching a filespec with wildcards (for
; COPY, DEL, and TYPE).  Since the DTA may contain the command line (or file
; data, for COPY), we use a DTA on the stack, along with a buffer for the name
; of each match (the filespec's drive and path, if any, followed by the name).
; Only normal files match (not hidden, system, or directory entries).
;
; Inputs:
;	SS:BX -> CMDHEAP
;	SS:SI -> filespec (null-terminated)
;	SS:DI -> filename portion of filespec
;	CX = data for the function
;	DX = function (called with SS:SI -> name of match, CX = data, and
;	BX -> CMDHEAP; it must preserve BX and BP, and return carry set to
;	stop, with AX = error #)
;
; Outputs:
;	Carry clear if successful, set if error (AX = error #)
;
; Modifies:
;	AX, CX, DX, DI, ES (and whatever the function modifies)
;
WF_NAME	equ	(size FFB + 1) AND 0FFFEh
WF_END	equ	WF_NAME + 80		; end of the drive and path in WF_NAME
WF_DATA	equ	WF_END + 2		; data for the function
WF_FUNC	equ	WF_DATA + 2		; function
WF_SIZE	equ	WF_FUNC + 2

DEFPROC	walkFiles
	push	bp
	push	si
	sub	sp,WF_SIZE
	mov	bp,sp
	mov	[bp+WF_DATA],cx
	mov	[bp+WF_FUNC],dx
	push	ss
	pop	es
	mov	cx,di
	sub	cx,si			; CX = length of drive and path
	lea	di,[bp+WF_NAME]
	rep	movsb			; copy them to the name buffer
	mov	[bp+WF_END],di
	mov	dx,bp			; DS:DX -> temporary DTA
	mov	ah,DOS_DSK_SETDTA
	int	21h
	mov	dx,[bp+WF_SIZE]
	mov	ah,DOS_DSK_FFIRST	; DS:DX -> filespec (CX is zero)
	int	21h
	jc	wf8
wf1:	lea	si,[bp].FFB_NAME
	mov	di,[bp+WF_END]
wf2:	lodsb				; append the matching name
	stosb
	test	al,al
	jnz	wf2
	lea	si,[bp+WF_NAME]		; SS:SI -> name of match
	mov	cx,[bp+WF_DATA]
	call	word ptr [bp+WF_FUNC]
	jc	wf8
	mov	ah,DOS_DSK_FNEXT
	int	21h
	jnc	wf1
	clc				; no more matches
wf8:	pushf
	push	ax
	mov	dx,PSP_DTA
	mov	ah,DOS_DSK_SETDTA
	int	21h			; restore the DTA
	pop	ax
	popf
	lea	sp,[bp+WF_SIZE]
	pop	si
	pop	bp
	ret
ENDPROC	walkFiles

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scanSpec
;
; Find the filename portion of a filespec (ie, after any drive or path), and
; check the filespec for wildcards.
;
; Inputs:
;	SS:BX -> CMDHEAP
;	DS:SI -> filespec (null-terminated)
;
; Outputs:
;	DI -> filename portion of filespec
;	AH = non-zero if the filespec contains wildcards
;
; Modifies:
;	AX, DI
;
DEFPROC	scanSpec
	push	si
	mov	di,si
	mov	ah,0
ss1:	lodsb
	cmp	al,'*'
	je	ss2
	cmp	al,'?'
	jne	ss3
ss2:	mov	ah,al
ss3:	cmp	al,':'
	je	ss4
	cmp	al,ss:[bx].PATH_CHAR
	jne	ss5
ss4:	mov	di,si
ss5:	test	al,al
	jnz	ss1
	pop	si
	ret
ENDPROC	scanSpec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkDir
;
; Determine whether a filespec refers to a directory: it either ends with ":"
; or the path char, or "filespec/*.*" doesn't fail with ERR_NOPATH (it either
; succeeds or fails with ERR_NOFILE).  For DIR and COPY.
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
	cmp	ax,ERR_NOPATH		; is it a directory?
	jne	cd8			; yes
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
; cmdDir
;
; Print a directory listing for the specified filespec.
;
; Inputs:
;	BX -> CMDHEAP
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDir
	push	bp
	mov	di,si
	add	di,cx			; DI -> end of filespec
	call	chkDir			; is the filespec a directory?
	jc	di1			; no
	push	si
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	REPS	MOVS,ES,CS,BYTE		; yes, so append DIR_DEF
	pop	si
;
; If filespec begins with a drive letter, get that drive's info.
;
di1:	mov	dl,0			; DL = default drive #
	cmp	byte ptr [si+1],':'
	jne	di2
	mov	al,[si]
	sub	al,'A'-1
	jb	dix
	mov	dl,al			; DL = specific drive # (1-based)
di2:	mov	ah,DOS_DSK_GETINFO
	int	21h			; get disk info for drive
	jnc	di3
dix:	jmp	di8
;
; We primarily want the cluster size, in bytes, which this call doesn't
; provide directly; we must multiply bytes per sector (CX) by sectors per
; cluster (AX).
;
di3:	mov	bp,bx			; BP = available clusters
	mul	cx			; DX:AX = bytes per cluster
	xchg	bx,ax			; BX = bytes per cluster
	mov	cx,10h			; CX = attributes (DIRATTR_SUBDIR)
	mov	dx,si			; DX -> filespec
	mov	ah,DOS_DSK_FFIRST
	int	21h
	jc	dix
;
; Use DX to maintain the total number of clusters, and CX to maintain
; the total number of files.
;
	sub	dx,dx
	sub	cx,cx
di4:	lea	si,ds:[PSP_DTA].FFB_NAME
;
; Beginning of "stupid" code to separate filename into name and extension.
;
	push	cx
	push	dx
	DOSUTIL	STRLEN
	xchg	cx,ax			; CX = total length
	cmp	byte ptr [si],'.'	; is it "." or ".."?
	je	di5			; yes, so there's no extension
	mov	dx,offset PERIOD
	call	chkString		; does the filename contain a period?
	jc	di5			; no
	mov	ax,di
	sub	ax,si			; AX = partial filename length
	inc	di			; DI -> character after period
	jmp	short di6
di5:	mov	ax,cx			; AX = complete filename length
	mov	di,si
	add	di,ax
;
; End of "stupid" code (which I'm tempted to eliminate, but since it's done...)
;
di6:	mov	dx,ds:[PSP_DTA].FFB_DATE
	mov	cx,ds:[PSP_DTA].FFB_TIME
	ASSERT	Z,<cmp ds:[PSP_DTA].FFB_SIZE.HIW,0>
	PRINTF	<"%-8.*s %-3s ">,ax,si,di
	test	ds:[PSP_DTA].FFB_ATTR,10h	; DIRATTR_SUBDIR?
	jnz	di6a
	PRINTF	<"%7ld">,ds:[PSP_DTA].FFB_SIZE,:2
	jmp	short di6b
di6a:	PRINTF	<"  ",3Ch,"DIR",3Eh>
di6b:	PRINTF	<" %2M-%02D-%02X %2G:%02N%A",13,10>,dx,dx,dx,cx,cx,cx
	call	countLine
;
; Update our totals
;
	mov	ax,ds:[PSP_DTA].FFB_SIZE.LOW
	mov	dx,ds:[PSP_DTA].FFB_SIZE.HIW
	lea	cx,[bx-1]
	add	ax,cx			; add cluster size - 1 to file size
	adc	dx,0
	div	bx			; # clusters = file size/cluster size
	pop	dx
	pop	cx
	add	dx,ax			; update our cluster total
	inc	cx			; and increment our file total

	mov	ah,DOS_DSK_FNEXT
	int	21h
	jc	di7
	jmp	di4

di7:	xchg	ax,dx			; AX = total # of clusters used
	mul	bx			; DX:AX = total # bytes
	PRINTF	<"%8d file(s) %8ld bytes",13,10>,cx,ax,dx
	call	countLine
	xchg	ax,bp			; AX = total # of clusters free
	mul	bx			; DX:AX = total # bytes free
	PRINTF	<"%25ld bytes free",13,10>,ax,dx
	pop	bp
	ret

di8:	mov	dx,offset VERB_FIND
	call	fileError
	pop	bp
	ret
ENDPROC	cmdDir

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
; cmdMkdir
;
; Create a directory (MD or MKDIR), or with cmdRmdir, remove a directory
; (RD or RMDIR).
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

VERB_CD		db	"change to",0
VERB_DEL	db	"delete",0
VERB_FIND	db	"find",0
VERB_MD		db	"create",0
VERB_RD		db	"remove",0

CODE	ENDS

	end
