;
; BASIC-DOS Command Interpreter
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT
	org	100h

	EXTERNS	<allocText,freeText,genImmediate>,near

	EXTERNS	<KEYWORD_TOKENS,heap>,word
	EXTSTR	<COM_EXT,EXE_EXT,DIR_DEF,PERIOD>
	EXTSTR	<SYS_MEM,DOS_MEM,FREE_MEM>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

DEFPROC	main
	LOCVAR	iArg,byte		; # of first non-switch argument
	LOCVAR	pArg,word		; saves arg ptr command handler
	LOCVAR	lenArg,word		; saves arg len command handler
	LOCVAR	pHandler,word		; saves address of command handler
	LOCVAR	swDigits,word		; bit mask of digit switches, if any
	LOCVAR	swLetters,dword		; bit mask of letter switches, if any
	LOCVAR	hFile,word		; file handle
	LOCVAR	numLine,word		; current line number
	LOCVAR	offLine,word		; offset of current line
	ENTER
	lea	bx,[heap]
	mov	[bx].ORIG_SP.SEG,ss
	mov	[bx].ORIG_SP.OFF,sp
	mov	[bx].ORIG_BP,bp
	mov	[hFile],0

	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	mov	dx,offset ctrlc
	int	21h

	push	bx
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDIM
	mov	bx,STDOUT
	int	21h
	pop	bx
	mov	word ptr [bx].CON_COLS,ax

	PRINTF	<"BASIC-DOS Interpreter",13,10,13,10>
	IFDEF	MSLIB
	PRINTF	<"BASIC MATH library functions",13,10,"Copyright (c) Microsoft Corporation",13,10,13,10>
	ENDIF

	mov	word ptr [bx].INPUTBUF.INP_MAX,size INP_BUF
;
; Since all command handlers loop back to this point, we shouldn't assume
; that any registers (eg, BX, ES) will still be set to their original values.
;
m1:	push	cs
	pop	es
	lea	bx,[heap]
	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'		; AL = current drive letter
	PRINTF	"%c>",ax

	lea	dx,[bx].INPUTBUF
	mov	ah,DOS_TTY_INPUT
	int	21h
	PRINTF	<13,10>

	sub	ax,ax
	mov	[swDigits],ax
	mov	[swLetters].OFF,ax
	mov	[swLetters].SEG,ax
	mov	si,dx
	add	si,offset INP_BUF
	lea	di,[bx].TOKENBUF
	mov	[di].TOK_MAX,(size TOK_BUF) / (size TOKLET)
	mov	ax,DOS_UTL_TOKIFY1
	int	21h
	xchg	cx,ax		; CX = token count from AX
	jcxz	m1		; jump if no tokens
;
; Before trying to ID the token, let's copy it to the FILENAME buffer,
; upper-case it, and null-terminate it.
;
	mov	dh,1
	call	getToken	; DS:SI -> token #1, CX = length
	jc	m1
	lea	di,[bx].FILENAME
	mov	ax,size FILENAME
	cmp	cx,ax
	jb	m1a
	xchg	cx,ax
m1a:	push	cx
	push	di
	rep	movsb
	mov	al,0
	stosb
	pop	si		; DS:SI -> copy of token in FILENAME
	pop	cx
	mov	ax,DOS_UTL_STRUPR
	int	21h		; DS:SI -> upper-case token, CX = length
	lea	dx,[KEYWORD_TOKENS]
	mov	ax,DOS_UTL_TOKID
	int	21h		; identify the token
	jc	m2
	mov	[pHandler],dx
	jmp	m9		; token ID in AX
;
; First token is unrecognized, so we'll assume it's either a drive
; specification or a program name.
;
m2:	mov	dx,si		; DS:DX -> FILENAME
	cmp	cl,2		; two characters only?
	jne	m3		; no
	cmp	byte ptr [si+1],':'
	jne	m3		; not a valid drive specification
	mov	cl,[si]		; CL = drive letter
	mov	dl,cl
	sub	dl,'A'		; DL = drive number
	cmp	dl,26
	jae	m2a		; out of range
	mov	ah,DOS_DSK_SETDRV
	int	21h		; attempt to set the drive number in DL
	jnc	m2b		; success
m2a:	PRINTF	<"Drive %c: invalid",13,10>,cx
m2b:	jmp	m1
;
; Not a drive letter, so presumably a program name.
;
m3:	mov	di,dx		; ES:DI -> FILENAME
	mov	al,'.'
	push	cx
	push	di
	repne	scasb		; any periods in FILENAME?
	pop	di
	pop	cx
	je	m4		; yes
;
; First we're going to append .EXE, not because we prefer .EXE (we don't),
; but because if no .EXE exists, we want to revert to .COM.
;
	push	cx
	push	di
	add	di,cx		; append .EXE
	mov	si,offset EXE_EXT
	mov	cx,EXE_EXT_LEN
	rep	movsb
	pop	di
	mov	ah,DOS_DSK_FFIRST
	int	21h		; find file (DS:DX) with attributes (CX = 0)
	pop	cx
	jnc	m5

	push	cx
	add	di,cx		; append .COM
	mov	si,offset COM_EXT
	mov	cx,COM_EXT_LEN
	rep	movsb
	pop	cx
	jmp	m5
;
; The token contains a period, so let's verify the extension is valid
; (ie, .COM or .EXE); we don't want people running, say, "CONFIG.SYS".
;
m4:	mov	si,offset COM_EXT
	mov	di,dx
	mov	ax,DOS_UTL_STRSTR
	int	21h		; verify FILENAME contains either .COM
	jnc	m5
	mov	si,offset EXE_EXT
	int	21h		; or .EXE
	mov	ax,ERR_INVALID
	jc	m8		; looks like neither, so report an error
;
; It looks like we have a valid program name, so prepare to exec.
;
m5:	lea	si,[bx].INPUTBUF.INP_BUF
	add	si,cx		; DS:SI -> cmd tail after filename
	lea	bx,[bx].EXECDATA
	mov	[bx].EPB_ENVSEG,0
	mov	di,PSP_CMDTAIL
	push	di
	mov	[bx].EPB_CMDTAIL.OFF,di
	mov	[bx].EPB_CMDTAIL.SEG,es
	inc	di		; use our cmd tail space to build a new tail
	mov	cx,-1
m6:	lodsb
	stosb
	inc	cx
	cmp	al,CHR_RETURN
	jne	m6
	pop	di
	mov	[di],cl		; set the cmd tail length
	mov	[bx].EPB_FCB1.OFF,PSP_FCB1
	mov	[bx].EPB_FCB1.SEG,es
	mov	[bx].EPB_FCB2.OFF,PSP_FCB2
	mov	[bx].EPB_FCB2.SEG,es

	mov	ax,DOS_PSP_EXEC
	int	21h		; exec program at DS:DX
	jc	m8
	mov	ah,DOS_PSP_RETCODE
	int	21h
	mov	dl,ah
	mov	ah,0
	mov	dh,0
	PRINTF	<13,10,"Return code %d (%d)",13,10>,ax,dx
	jmp	m1
m8:	PRINTF	<"Error loading %s: %d",13,10>,dx,ax
	jmp	m1
;
; We arrive here if the token was recognized.  The token ID determines
; the level of additional parsing required, if any.
;
m9:	lea	di,[bx].TOKENBUF; DS:DI -> token buffer
	cmp	ax,20		; token ID < 20?
	jb	m10		; yes, token is not part of "the language"
;
; The token is for a recognized keyword, so retokenize the line.
;
	lea	si,[bx].INPUTBUF.INP_BUF
	mov	ax,DOS_UTL_TOKIFY2
	int	21h
	call	genImmediate	; DX = code generator (from 1st token)
	jmp	m1
;
; For non-BASIC commands, check for any switches first and record any that
; we find prior to the first non-switch argument.
;
m10:	call	parseSW		; parse all switch arguments, if any
	cmp	ax,10		; token ID < 10?
	jb	m20		; yes, command does not use a filespec
;
; The token is for a command that expects a filespec, so fix up the next
; token (index in DH).  If there is no token, then we use the defaults loaded
; into SI and CX.
;
	mov	si,offset DIR_DEF
	mov	cx,DIR_DEF_LEN - 1
	call	getToken	; DH = 1st non-switch argument (or -1)
	jc	m20
	lea	di,[bx].FILENAME; DS:SI -> token, CX = length
	mov	ax,size FILENAME-1
	cmp	cx,ax
	jbe	m19
	xchg	cx,ax
m19:	push	cx
	push	di
	rep	movsb
	mov	byte ptr es:[di],0
	pop	si		; DS:SI -> copy of token in FILENAME
	pop	cx
	mov	ax,DOS_UTL_STRUPR
	int	21h		; DS:SI -> upper-case token, CX = length

m20:	mov	[pArg],si
	mov	[lenArg],cx
	call	[pHandler]	; call token handler
	jmp	m1
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parseSW
;
; Switch tokens start with the system's SWITCHAR and may contain 1 or more
; alphanumeric characters, each of which is converted to a bit in either
; swDigits or swLetters.
;
; Actually, alphanumeric is not entirely true anymore: in swDigits, we now
; capture anything from '0' to '?'.
;
; Inputs:
;	DS:DI -> BUF_TOKEN
;
; Outputs:
;	DH = # of first non-switch argument (-1 if none)
;
; Modifies:
;	CX, DX
;
DEFPROC	parseSW
	push	ax
	push	bx
	mov	[iArg],-1
	mov	ax,DOS_MSC_GETSWC
	int	21h		; DL = SWITCHAR
	mov	dh,2		; start with the second token
ps1:	call	getToken
	jc	ps8
	lodsb
	cmp	al,dl		; starts with SWITCHAR?
	je	ps2		; yes
	mov	[iArg],dh	; update iArg with first non-switch arg
	jmp	short ps7	; no
ps2:	lodsb			; consume option chars
	cmp	al,'a'		; until we reach a non-alphanumeric char
	jb	ps3
	sub	al,20h
ps3:	sub	al,'0'
	jb	ps7		; not alphanumeric
	cmp	al,16
	jae	ps5
	lea	bx,[swDigits]
ps4:	mov	cl,al
	mov	ax,1
	shl	ax,cl
	mov	[bx],ax		; set corresponding bit in the word at [bx]
	jmp	ps2		; go back for more option chars
ps5:	sub	al,'A'-'0'
	jb	ps7		; not alphanumeric
	cmp	al,16		; in the range of the first 16?
	jae	ps6		; no
	lea	bx,[swLetters].OFF
	jmp	ps4
ps6:	sub	al,16
	cmp	al,10		; in the range of the next 10?
	jae	ps7		; no
	lea	bx,[swLetters].SEG
	jmp	ps4
ps7:	inc	dh		; advance to next token
	jmp	ps1
ps8:	mov	dh,[iArg]	; DH = first non-switch argument (-1 if none)
	pop	bx
	pop	ax
	ret
ENDPROC	parseSW

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; checkSW
;
; Inputs:
;	AL = letter or digit (or special characters, such as ':' and '?')
;
; Outputs:
;	ZF clear if switch letter present, set otherwise
;
; Modifies:
;	AX, CX
;
DEFPROC	checkSW
	push	bx
	lea	bx,[swDigits]
	sub	al,'A'
	jae	cs1
	add	al,'A'-'0'
	jmp	short cs2
cs1:	lea	bx,[swLetters]
	cmp	al,16
	jb	cs2
	sub	al,16
	add	bx,2
cs2:	xchg	cx,ax
	mov	ax,1
	shl	ax,cl
	test	[bx],ax
	pop	bx
	ret
ENDPROC	checkSW

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getToken
;
; Inputs:
;	DH = token # (1-based)
;	DS:DI -> BUF_TOKEN
;
; Outputs:
;	If carry clear, DS:SI -> token, CX = length
;
; Modifies:
;	CX, SI
;
DEFPROC	getToken
	cmp	[di].TOK_CNT,dh
	jb	gt9
	push	bx
	mov	bl,dh
	mov	bh,0
	dec	bx		; BX = 0-based index
	add	bx,bx
	add	bx,bx		; BX = BX * 4 (size TOKLET)
	mov	si,[di+bx].TOK_BUF.TOKLET_OFF
	mov	cl,[di+bx].TOK_BUF.TOKLET_LEN
	mov	ch,0
	pop	bx
gt9:	ret
ENDPROC	getToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ctrlc
;
; CTRLC handler; resets the program stack and jumps to the start address
;
; Inputs:
;	DS:SI -> user-defined token
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	ctrlc,FAR
	lea	bx,[heap]
	cli
	mov	ss,[bx].ORIG_SP.SEG
	mov	sp,[bx].ORIG_SP.OFF
	mov	bp,[bx].ORIG_BP
	sti
	jmp	m1
ENDPROC	ctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDate
;
; TBD
;
; Inputs:
;	DS:SI -> user-defined token
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDate
	ret
ENDPROC	cmdDate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDir
;
; Print a directory listing for the specified filespec.
;
; Inputs:
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
;
; If filespec begins with ":", extract drive letter, and if it ends
; with ":" as well, append DIR_DEF ("*.*").
;
	mov	dl,0		; DL = default drive #
	mov	di,cx		; DI = length of filespec
	cmp	cx,2
	jb	dir0
	cmp	byte ptr [si+1],':'
	jne	dir0
	mov	al,[si]
	sub	al,'A'-1
	jb	dir0a
	mov	dl,al		; DL = specific drive # (1-based)
dir0:	mov	ah,DOS_DSK_GETINFO
	int	21h		; get disk info for drive
	jnc	dir1
dir0a:	jmp	dir8
;
; We primarily want the cluster size, in bytes, which this call doesn't
; provide directly; we must multiply bytes per sector (CX) by sectors per
; cluster (AX).
;
dir1:	mov	bp,bx		; BP = available clusters
	mul	cx		; DX:AX = bytes per cluster
	xchg	bx,ax		; BX = bytes per cluster

dir2:	add	di,si		; DI -> end of filespec
	cmp	byte ptr [di-1],':'
	jne	dir3
	push	si
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	rep	movsb
	pop	si

dir3:	sub	cx,cx		; CX = attributes
	mov	dx,si		; DX -> filespec
	mov	ah,DOS_DSK_FFIRST
	int	21h
	jc	dir0a
;
; Use DX to maintain the total number of clusters, and CX to maintain
; the total number of files.
;
	sub	dx,dx
	sub	cx,cx

dir4:	lea	si,ds:[PSP_DTA].FFB_NAME
;
; Beginning of "stupid" code to separate filename into name and extension.
;
	push	cx
	push	dx
	mov	ax,DOS_UTL_STRLEN
	int	21h
	xchg	cx,ax		; CX = total length
	mov	di,si
	push	si
	mov	si,offset PERIOD
	mov	ax,DOS_UTL_STRSTR
	int	21h		; if carry clear, DI is updated
	pop	si
	jc	dir5
	mov	ax,di
	sub	ax,si		; AX = partial filename length
	inc	di		; DI -> character after period
	jmp	short dir6
dir5:	mov	ax,cx		; AX = complete filename length
	mov	di,si
	add	di,ax
;
; End of "stupid" code (which I'm tempted to eliminate, but since it's done...)
;
dir6:	mov	dx,ds:[PSP_DTA].FFB_DATE
	mov	cx,ds:[PSP_DTA].FFB_TIME
	ASSERT	Z,<cmp ds:[PSP_DTA].FFB_SIZE.SEG,0>
	PRINTF	<"%-8.*s %-3s %7ld %2M-%02D-%02X %2G:%02N%A",13,10>,ax,si,di,ds:[PSP_DTA].FFB_SIZE.OFF,ds:[PSP_DTA].FFB_SIZE.SEG,dx,dx,dx,cx,cx,cx
;
; Update our totals
;
	mov	ax,ds:[PSP_DTA].FFB_SIZE.OFF
	mov	dx,ds:[PSP_DTA].FFB_SIZE.SEG
	lea	cx,[bx-1]
	add	ax,cx		; add cluster size - 1 to file size
	adc	dx,0
	div	bx		; # clusters = file size / cluster size
	pop	dx
	pop	cx
	add	dx,ax		; update our cluster total
	inc	cx		; and increment our file total

	mov	ah,DOS_DSK_FNEXT
	int	21h
	jc	dir7
	jmp	dir4

dir7:	xchg	ax,dx		; AX = total # of clusters used
	mul	bx		; DX:AX = total # bytes
	PRINTF	<"%8d file(s) %8ld bytes",13,10>,cx,ax,dx
	xchg	ax,bp		; AX = total # of clusters free
	mul	bx		; DX:AX = total # bytes free
	PRINTF	<"%25ld bytes free",13,10>,ax,dx
;
; For testing purposes: if /L is specified, display the directory in a "loop".
;
	pop	bp
	mov	al,'L'
	call	checkSW
	jz	dir9
	mov	si,[pArg]
	mov	cx,[lenArg]
	jmp	cmdDir

dir8:	PRINTF	<"Unable to find %s (%d)",13,10>,si,ax
	pop	bp

dir9:	ret
ENDPROC	cmdDir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdExit
;
; Inputs:
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdExit
	int	20h		; terminates the current process
	ret			; unless it can't (ie, if there's no parent)
ENDPROC	cmdExit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdHelp
;
; For now, all this does is print the names of all supported commands.
;
; Inputs:
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdHelp
	mov	si,offset KEYWORD_TOKENS
	lodsw			; AL = # tokens, AH = size TOKDEF
	mov	cl,al
	mov	ch,0		; CX = # tokens
	mov	al,ah
	cbw
	xchg	di,ax		; DI = size TOKDEF
	mov	dl,8		; DL = # chars to be printed so far
h1:	cmp	[si].TOKDEF_ID,100
	jae	h3		; ignore token IDs >= 100
	push	dx
	mov	dl,[si].TOKDEF_LEN
	mov	dh,0
	PRINTF	<"%-8.*s">,dx,[si].TOKDEF_OFF
	pop	dx
	add	dl,al
	cmp	cl,1
	je	h2
	cmp	dl,[bx].CON_COLS
	jb	h3
h2:	PRINTF	<13,10>
	mov	dl,8
h3:	add	si,di		; SI -> next TOKDEF
	loop	h1
	ret
ENDPROC	cmdHelp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdList
;
; Inputs:
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdList
	stc
li9:	ret
ENDPROC	cmdList

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdLoad
;
; Opens the specified file and loads it into one or more text blocks.
;
; Inputs:
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdLoad
	call	openFile
	jc	li9
;
; Since the open succeeded, toss any existing text block(s).
;
	call	freeText
	lea	bx,[bx].LINEBUF
	sub	cx,cx		; DS:SI contains zero bytes at the moment
	mov	di,TBLKLEN	; initialize DI to memory limit
;
; For every complete line at DS:SI, determine the line number (if any), and
; then add the line number (2 bytes), line length (1 byte), and line contents
; (not including any leading space or terminating CR/LF) to the text block.
;
lf1:	jcxz	lf4
	push	cx
	mov	dx,si		; save SI
lf2:	lodsb
	cmp	al,CHR_RETURN
	je	lf3
	loop	lf2
lf3:	xchg	si,dx		; restore SI; DX is how far we got
	pop	cx
	je	lf5		; we found the end of a line; process it
;
; The end of the current line is not contained in our buffer, so "slide"
; everything at DS:SI down to LINEBUF, fill in the rest of LINEBUF, and try
; again.
;
	cmp	si,bx		; is the current line already at LINEBUF?
	je	lf4x		; yes, report a file format error
	push	cx
	push	di
	push	es
	push	ds
	pop	es
	mov	di,bx
	push	cx
	rep	movsb
	pop	es
	pop	di
	pop	cx
lf4:	mov	si,bx		; DS:SI has been adjusted
;
; At DS:SI+CX, read (size LINEBUF - CX) more bytes.
;
	push	cx
	push	si
	add	si,cx
	mov	ax,size LINEBUF
	sub	ax,cx
	xchg	cx,ax
	call	readFile
	pop	si
	pop	cx
	jc	lf4x
	add	cx,ax
	jcxz	lf4y		; if we've exhausted the file, we're done
	jmp	lf1
lf4x:	jmp	lf10
lf4y:	jmp	lf12
;
; We found the end of another line starting at DS:SI and ending at DX.
;
lf5:	mov	[offLine],si
	lodsb
	cmp	al,CHR_LINEFEED	; skip any LINEFEED from the previous line
	je	lf6
	dec	si

lf6:	push	bx
	push	dx
	mov	bl,10
	mov	ax,DOS_UTL_ATOI32; DS:SI -> numeric string
	int	21h
	ASSERT	Z,<test dx,dx>	; DX:AX is the result but we keep only AX
	mov	[numLine],ax
	pop	dx
	pop	bx
;
; We've extracted the line number, if any; skip over any intervening space.
;
	lodsb
	cmp	al,CHR_SPACE
	je	lf7
	dec	si

lf7:	dec	dx		; back up to CHR_RETURN
	sub	dx,si		; DX = # of characters on line (may be zero)
;
; Is there room for DX more bytes at ES:DI?
;
	mov	ax,di
	add	ax,dx
	add	ax,3
	cmp	ax,TBLKLEN	; does this overflow ES:DI?
	jbe	lf8		; no
;
; No, there's not enough room, so allocate another text block.
;
	push	cx
	mov	cx,TBLKLEN
	push	si
	call	allocText
	pop	si
	pop	cx
	jc	lf11		; unable to allocate enough memory
	sub	di,di		; ES:DI -> next available text location
				; ES:TBLKLEN is the limit
lf8:	mov	ax,[numLine]
	stosw
	mov	al,dl
	stosb
	push	cx
	mov	cx,dx
	IFDEF DEBUG
	PRINTF	<"line: '%-.*ls'",13,10>,cx,si,ds
	int 3
	ENDIF
	rep	movsb
	pop	cx
	mov	ax,si
	sub	ax,[offLine]
	sub	cx,ax
;
; Consume the line terminator and go back for more.
;
	lodsb
	dec	cx
	jmp	lf1

lf10:	PRINTF	<"Invalid file format",13,10>

lf11:	call	freeText

lf12:	call	closeFile
	ret
ENDPROC	cmdLoad

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMem
;
; Prints memory usage.
;
; Inputs:
;	DS:SI -> user-defined token (not used)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdMem
;
; Before we get into memory blocks, show the amount of memory reserved
; for the BIOS and disk buffers.
;
	push	bp
	push	es
	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING
	sub	bx,bx
	mov	ax,es
	push	di
	mov	di,ds
	mov	si,offset SYS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
;
; Next, dump the list of resident built-in device drivers.
;
drv1:	cmp	di,-1
	je	drv9
	lea	si,[di].DDH_NAME
	mov	bx,es
	mov	cx,bx
	mov	ax,es:[di].DDH_NEXT_SEG
	sub	ax,cx		; AX = # paras
	push	di
	mov	di,bx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	di
	les	di,es:[di]
	jmp	drv1
;
; Next, dump the size of the operating system, which resides between the
; built-in device drivers and the first memory block.
;
drv9:	mov	bx,es		; ES = DOS data segment
	mov	ax,es:[0]	; ES:[0] is mcb_head
	mov	bp,es:[2]	; ES:[2] is mcb_limit
	sub	ax,bx
	mov	di,ds
	mov	si,offset DOS_MEM
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	es
	ASSUME	ES:CODE
;
; Next, examine all the memory blocks and display those that are used.
;
	push	bp
	sub	cx,cx
	sub	bp,bp		; BP = free memory
mem1:	mov	dl,0		; DL = 0 (query all memory blocks)
	mov	di,ds		; DI:SI -> default owner name
	mov	si,offset SYS_MEM
	mov	ax,DOS_UTL_QRYMEM
	int	21h
	jc	mem9		; all done
	test	ax,ax		; free block (is OWNER zero?)
	jne	mem2		; no
	add	bp,dx		; yes, add to total free paras
;
; Let's include free blocks in the report now, too.
;
	mov	si,offset FREE_MEM
	; jmp	short mem8

mem2:	mov	ax,dx		; AX = # paras
	push	cx
	call	printKB		; BX = seg, AX = # paras, DI:SI -> name
	pop	cx
mem8:	inc	cx
	jmp	mem1
mem9:	xchg	ax,bp		; AX = free memory (paras)
	pop	bp		; BP = total memory (paras)
;
; Last but not least, dump the amount of free memory (ie, the sum of all the
; free blocks that we did NOT display above).
;
	mov	cx,16
	mul	cx		; DX:AX = free memory (in bytes)
	xchg	si,ax
	mov	di,dx		; DI:SI = free memory
	xchg	ax,bp
	mul	cx		; DX:AX = total memory (in bytes)
	PRINTF	<"%8ld bytes total",13,10,"%8ld bytes free",13,10>,ax,dx,si,di
	pop	bp
	ret
ENDPROC	cmdMem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdTime
;
; TBD
;
; Inputs:
;	DS:SI -> user-defined token
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdTime
	ret
ENDPROC	cmdTime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdType
;
; Reads the specified file and writes it to STDOUT.
;
; Inputs:
;	DS:SI -> user-defined token
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdType
	call	openFile	; SI -> filename
	jc	of9
	mov	si,PSP_DTA	; SI -> DTA (used as a read buffer)
ty1:	mov	cx,size PSP_DTA	; CX = number of bytes to read
	call	readFile
	jc	closeFile
	test	ax,ax		; anything read?
	jz	closeFile	; no
	mov	bx,STDOUT
	xchg	cx,ax		; CX = number of bytes to write
	mov	ah,DOS_HDL_WRITE
	int	21h
	jmp	ty1
ENDPROC	cmdType

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openFile
;
; Opens the specified file; used by commands like "LOAD" and "TYPE".
;
; Inputs:
;	DS:SI -> filename
;
; Outputs:
;	If carry clear, [hFile] is updated
;	If carry set, an error message was printed
;
; Modifies:
;	AX, BX
;
DEFPROC	openFile
	push	dx
	mov	dx,si		; DX -> filename
	mov	ax,DOS_HDL_OPEN SHL 8
	int	21h
	jc	of8
	mov	[hFile],ax	; save file handle
	jmp	short of9
of8:	PRINTF	<"Unable to open %ls (%d)",13,10>,dx,ds,ax
	stc
of9:	pop	dx
	ret
ENDPROC	openFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; readFile
;
; Reads CX bytes from the default file into the buffer at DS:SI.
;
; Inputs:
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
DEFPROC	readFile
	push	bx
	mov	dx,si
	mov	bx,[hFile]
	mov	ah,DOS_HDL_READ
	int	21h
	jnc	rf9
	PRINTF	<"Unable to read file",13,10>
	stc
rf9:	pop	bx
	ret
ENDPROC	readFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; closeFile
;
; Close the default file handle.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	closeFile
	push	bx
	mov	bx,[hFile]
	test	bx,bx
	jz	cf9
	mov	ah,DOS_HDL_CLOSE
	int	21h
	mov	[hFile],0
cf9:	pop	bx
	ret
ENDPROC	closeFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printKB
;
; Converts the paragraph size in AX to Kb, by calculating AX/64 (or AX >> 6);
; however, that's a bit too granular, so we include tenths of Kb as well.
;
; Using the paragraph remainder (R), we calculate tenths (N): R/64 = N/10, so
; N = (R*10)/64.
;
; Inputs:
;	AX = size in paragraphs
;	BX = segment of memory block
;	DI:SI -> "owner" name for memory block
;
; Outputs:
;	None
;
DEFPROC	printKB
	push	ax
	push	bx
	mov	bx,64
	sub	dx,dx		; DX:AX = paragraphs
	div	bx		; AX = Kb
	xchg	cx,ax		; save Kb in CX
	xchg	ax,dx		; AX = paragraphs remainder
	mov	bl,10
	mul	bx		; DX:AX = remainder * 10
	mov	bl,64
	or	ax,31		; round up without adding
	div	bx		; AX = tenths of Kb
	ASSERT	NZ,<cmp ax,10>
	xchg	dx,ax		; save tenths in DX
	pop	bx
	pop	ax
	PRINTF	<"%#06x: %#06x %3d.%1dK %.8ls",13,10>,bx,ax,cx,dx,si,di
	ret
ENDPROC	printKB

CODE	ENDS

	end	main
