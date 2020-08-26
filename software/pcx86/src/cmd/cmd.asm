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

	EXTERNS	<allocText,freeText,genCode>,near

	EXTERNS	<KEYWORD_TOKENS>,word
	EXTSTR	<COM_EXT,EXE_EXT,BAS_EXT,BAT_EXT,DIR_DEF,PERIOD>
	EXTSTR	<STD_VER,DBG_VER>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

DEFPROC	main
	LOCVAR	iArg,byte		; # of first non-switch argument
	LOCVAR	pArg,word		; saves arg ptr command handler
	LOCVAR	lenArg,word		; saves arg len command handler
	LOCVAR	pHandler,word		; saves address of command handler
	LOCVAR	swDigits,word		; bit mask of digit switches, if any
	LOCVAR	swLetters,dword		; bit mask of letter switches, if any
	LOCVAR	hFile,word		; file handle
	LOCVAR	lineLabel,word		; current line label
	LOCVAR	lineOffset,word		; current line offset
	LOCVAR	pTextLimit,word		; current text block limit

	ENTER
	mov	[hFile],0
	mov	bx,ds:[PSP_HEAP]
	mov	[bx].ORIG_SP.SEG,ss
	mov	[bx].ORIG_SP.OFF,sp
	mov	[bx].ORIG_BP,bp
	push	ds
	push	cs
	pop	ds
	mov	dx,offset ctrlc		; DS:DX -> CTRLC handler
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	int	21h
	pop	ds

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
m1:	push	ss
	pop	ds
	push	ss
	pop	es
	mov	bx,ds:[PSP_HEAP]
	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'			; AL = current drive letter
	PRINTF	"%c>",ax

	lea	dx,[bx].INPUTBUF
	mov	ah,DOS_TTY_INPUT
	int	21h
	PRINTF	<13,10>

	sub	ax,ax
	mov	[swDigits],ax
	mov	[swLetters].LOW,ax
	mov	[swLetters].HIW,ax
	mov	si,dx
	mov	cl,[si].INP_CNT
	lea	si,[si].INP_BUF
	lea	di,[bx].TOKENBUF	; ES:DI -> TOKENBUF
	mov	[di].TOK_MAX,(size TOK_BUF) / (size TOKLET)
	mov	ax,DOS_UTL_TOKIFY1
	int	21h
	jc	m1			; jump if no tokens
;
; Before trying to ID the token, let's copy it to the FILENAME buffer,
; upper-case it, and null-terminate it.
;
	mov	dh,1
	call	getToken		; DS:SI -> token #1, CX = length
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
	pop	si			; DS:SI -> copy of token in FILENAME
	pop	cx
	mov	ax,DOS_UTL_STRUPR
	int	21h			; DS:SI -> token, CX = length
	lea	dx,[KEYWORD_TOKENS]
	mov	ax,DOS_UTL_TOKID	; CS:DX -> TOKTBL
	int	21h			; identify the token
	jc	m2
	mov	[pHandler],dx
	jmp	m9			; token ID in AX
;
; First token is unrecognized, so we'll assume DS:SI contains either
; a drive specification or a program name.
;
m2:	cmp	cl,2			; two characters only?
	jne	m3			; no
	cmp	byte ptr [si+1],':'
	jne	m3			; not a valid drive specification
	mov	cl,[si]			; CL = drive letter
	mov	dl,cl
	sub	dl,'A'			; DL = drive number
	cmp	dl,26
	jae	m2a			; out of range
	mov	ah,DOS_DSK_SETDRV
	int	21h			; attempt to set the drive number in DL
	jnc	m2b			; success
m2a:	PRINTF	<"Drive %c: invalid",13,10>,cx
m2b:	jmp	m1
;
; Not a drive letter, so presumably DS:SI contains a program name.
;
m3:	mov	dx,offset PERIOD
	call	chkString		; any periods in string at DS:SI?
	jnc	m4			; yes
;
; There's no period, so append extensions in a well-defined order:
; .COM, .EXE, .BAT, and finally .BAS.
;
	mov	dx,offset COM_EXT
m3a:	call	addString
	call	findFile
	jnc	m4
	add	dx,COM_EXT_LEN
	cmp	dx,offset BAS_EXT
	jbe	m3a
	mov	dx,di			; DX -> FILENAME
	add	di,cx			; every extension failed
	mov	byte ptr [di],0		; so clear the last one we tried
	mov	ax,ERR_NOFILE		; and report an error
	jmp	short m4a
;
; The filename contains a period, so let's verify the extension and the
; action; for example, only .COM or .EXE files should be EXEC'ed (it would
; not be a good idea to execute, say, CONFIG.SYS).
;
m4:	mov	dx,offset COM_EXT
	call	chkString
	jnc	m5
	mov	dx,offset EXE_EXT
	call	chkString
	jnc	m5
	mov	dx,offset BAT_EXT
	call	chkString
	jnc	m4b
	mov	dx,offset BAS_EXT
	call	chkString
	jnc	m4b
	mov	dx,di			; filename was none of the above
	mov	ax,ERR_INVALID		; so report an error
m4a:	jmp	short m8
;
; BAT files are LOAD'ed and then immediately RUN.  We'll do the same for
; BAS files, too.  Use the "LOAD" command to load without running.
;
m4b:	call	cmdLoad
	jc	m4c			; don't RUN if there was a LOAD error
	mov	bx,ds:[PSP_HEAP]	; don't assume cmdLoad preserved BX
	call	cmdRun
m4c:	jmp	m1
;
; COM and EXE files are EXEC'ed, which requires building EXECDATA.
;
m5:	mov	dx,si			; DS:DX -> filename
	lea	si,[bx].INPUTBUF.INP_BUF
	add	si,cx			; DS:SI -> cmd tail after filename
	lea	bx,[bx].EXECDATA
	mov	[bx].EPB_ENVSEG,0
	mov	di,PSP_CMDTAIL
	push	di
	mov	[bx].EPB_CMDTAIL.OFF,di
	mov	[bx].EPB_CMDTAIL.SEG,es
	inc	di			; use our tail space to build new tail
	mov	cx,-1
m6:	lodsb
	stosb
	inc	cx
	cmp	al,CHR_RETURN
	jne	m6
	pop	di
	mov	[di],cl			; set the cmd tail length
	mov	[bx].EPB_FCB1.OFF,PSP_FCB1
	mov	[bx].EPB_FCB1.SEG,es
	mov	[bx].EPB_FCB2.OFF,PSP_FCB2
	mov	[bx].EPB_FCB2.SEG,es

	mov	ax,DOS_PSP_EXEC
	int	21h			; EXEC program at DS:DX
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
m9:	lea	di,[bx].TOKENBUF	; DS:DI -> token buffer
	cmp	ax,20			; token ID < 20?
	jb	m10			; yes, token not part of "the language"
;
; The token is for a recognized keyword, so generate code.
;
	lea	si,[bx].INPUTBUF
	call	genCode
	jmp	m1
;
; For non-BASIC commands, check for any switches first and record any that
; we find prior to the first non-switch argument.
;
m10:	call	parseSW			; parse all switch arguments, if any
	cmp	ax,10			; token ID < 10?
	jb	m20			; yes, command does not use a filespec
;
; The token is for a command that expects a filespec, so fix up the next
; token (index in DH).  If there is no token, then use defaults loaded into
; SI and CX.
;
	call	getToken		; DH = 1st non-switch argument (or -1)
	jnc	m18
	push	cs
	pop	ds
	mov	si,offset DIR_DEF
	mov	cx,DIR_DEF_LEN - 1
	jmp	short m19
m18:	lea	di,[bx].FILENAME	; DS:SI -> token, CX = length
	mov	ax,size FILENAME-1
	cmp	cx,ax
	jbe	m19
	xchg	cx,ax
m19:	push	cx
	push	di
	rep	movsb
	mov	byte ptr es:[di],0
	pop	si			; DS:SI -> copy of token in FILENAME
	pop	cx
	push	ss
	pop	ds
	mov	ax,DOS_UTL_STRUPR
	int	21h			; DS:SI -> token, CX = length
	mov	[pArg],si
	mov	[lenArg],cx
m20:	cmp	[pHandler],0		; does handler exist?
	je	m99			; no
	call	[pHandler]		; call the token handler
m99:	jmp	m1
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
;	CX, DX, SI
;
DEFPROC	parseSW
	push	ax
	push	bx
	mov	[iArg],-1
	mov	ax,DOS_MSC_GETSWC
	int	21h			; DL = SWITCHAR
	mov	dh,2			; start with the second token
ps1:	call	getToken
	jc	ps8
	lodsb
	cmp	al,dl			; starts with SWITCHAR?
	je	ps2			; yes
	mov	[iArg],dh		; update iArg with first non-switch
	jmp	short ps7		; no
ps2:	lodsb				; consume option chars
	cmp	al,'a'			; until we reach non-alphanumeric char
	jb	ps3
	sub	al,20h
ps3:	sub	al,'0'
	jb	ps7			; not alphanumeric
	cmp	al,16
	jae	ps5
	lea	bx,[swDigits]
ps4:	mov	cl,al
	mov	ax,1
	shl	ax,cl
	mov	[bx],ax			; set bit in word at [bx]
	jmp	ps2			; go back for more option chars
ps5:	sub	al,'A'-'0'
	jb	ps7			; not alphanumeric
	cmp	al,16			; in the range of the first 16?
	jae	ps6			; no
	lea	bx,[swLetters].LOW
	jmp	ps4
ps6:	sub	al,16
	cmp	al,10			; in the range of the next 10?
	jae	ps7			; no
	lea	bx,[swLetters].HIW
	jmp	ps4
ps7:	inc	dh			; advance to next token
	jmp	ps1
ps8:	mov	dh,[iArg]		; DH = first non-switch (-1 if none)
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
	dec	bx			; BX = 0-based index
	add	bx,bx
	add	bx,bx			; BX = BX * 4 (size TOKLET)
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
;	None
;
; Outputs:
;	DS = SS
;	DS:BX -> heap
;	SP and BP reset
;
; Modifies:
;	Any
;
DEFPROC	ctrlc,FAR
	push	ss
	pop	ds
	mov	bx,ds:[PSP_HEAP]
	mov	sp,[bx].ORIG_SP.OFF
	mov	bp,[bx].ORIG_BP
	call	closeFile
	jmp	m1
ENDPROC	ctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDate
;
; Inputs:
;	DS:BX -> heap
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
	mov	dl,0			; DL = default drive #
	mov	di,cx			; DI = length of filespec
	cmp	cx,2
	jb	dir0
	cmp	byte ptr [si+1],':'
	jne	dir0
	mov	al,[si]
	sub	al,'A'-1
	jb	dir0a
	mov	dl,al			; DL = specific drive # (1-based)
dir0:	mov	ah,DOS_DSK_GETINFO
	int	21h			; get disk info for drive
	jnc	dir1
dir0a:	jmp	dir8
;
; We primarily want the cluster size, in bytes, which this call doesn't
; provide directly; we must multiply bytes per sector (CX) by sectors per
; cluster (AX).
;
dir1:	mov	bp,bx			; BP = available clusters
	mul	cx			; DX:AX = bytes per cluster
	xchg	bx,ax			; BX = bytes per cluster

dir2:	add	di,si			; DI -> end of filespec
	cmp	byte ptr [di-1],':'
	jne	dir3
	push	si
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	REPMOV	byte,CS
	pop	si

dir3:	sub	cx,cx			; CX = attributes
	mov	dx,si			; DX -> filespec
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
	xchg	cx,ax			; CX = total length
	mov	dx,offset PERIOD
	call	chkString		; does the filename contain a period?
	jc	dir5			; no
	mov	ax,di
	sub	ax,si			; AX = partial filename length
	inc	di			; DI -> character after period
	jmp	short dir6
dir5:	mov	ax,cx			; AX = complete filename length
	mov	di,si
	add	di,ax
;
; End of "stupid" code (which I'm tempted to eliminate, but since it's done...)
;
dir6:	mov	dx,ds:[PSP_DTA].FFB_DATE
	mov	cx,ds:[PSP_DTA].FFB_TIME
	ASSERT	Z,<cmp ds:[PSP_DTA].FFB_SIZE.HIW,0>
	PRINTF	<"%-8.*s %-3s %7ld %2M-%02D-%02X %2G:%02N%A",13,10>,ax,si,di,ds:[PSP_DTA].FFB_SIZE.LOW,ds:[PSP_DTA].FFB_SIZE.HIW,dx,dx,dx,cx,cx,cx
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
	jc	dir7
	jmp	dir4

dir7:	xchg	ax,dx			; AX = total # of clusters used
	mul	bx			; DX:AX = total # bytes
	PRINTF	<"%8d file(s) %8ld bytes",13,10>,cx,ax,dx
	xchg	ax,bp			; AX = total # of clusters free
	mul	bx			; DX:AX = total # bytes free
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
;	DS:BX -> heap
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdExit
	int	20h			; terminates the current process
	ret				; unless it can't (ie, no parent)
ENDPROC	cmdExit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdHelp
;
; For now, all this does is print the names of all supported commands.
;
; Inputs:
;	DS:BX -> heap
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdHelp
	mov	si,offset KEYWORD_TOKENS
	lods	word ptr cs:[si]	; AL = # tokens, AH = size TOKDEF
	mov	cl,al
	mov	ch,0			; CX = # tokens
	mov	al,ah
	cbw
	xchg	di,ax			; DI = size TOKDEF
	mov	dl,8			; DL = # chars to be printed so far
h1:	cmp	cs:[si].TOKDEF_ID,100
	jae	h3			; ignore token IDs >= 100
	push	dx
	mov	dl,cs:[si].TOKDEF_LEN
	mov	dh,0
	PRINTF	<"%-8.*ls">,dx,cs:[si].TOKDEF_OFF,cs
	pop	dx
	add	dl,al
	cmp	cl,1
	je	h2
	cmp	dl,[bx].CON_COLS
	jb	h3
h2:	PRINTF	<13,10>
	mov	dl,8
h3:	add	si,di			; SI -> next TOKDEF
	loop	h1
h9:	ret
ENDPROC	cmdHelp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdList
;
; Inputs:
;	DS:BX -> heap
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdList
	ret
ENDPROC	cmdList

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdLoad
;
; Opens the specified file and loads it into one or more text blocks.
;
; TODO: Shrink the final text block to the amount of text actually loaded.
;
; Inputs:
;	DS:BX -> heap
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	Carry clear if successful, set if error (the main function doesn't
;	care whether this succeeds, but other callers do).
;
; Modifies:
;	Any
;
DEFPROC	cmdLoad
	mov	dx,offset PERIOD
	call	chkString
	jnc	lf1			; period exists, use filename as-is
	mov	dx,offset BAS_EXT
	call	addString

lf1:	call	openFile		; open the specified file
	jnc	lf1b
	cmp	si,di			; was there an extension?
	jne	lf1a			; yes, give up
	mov	dx,offset BAT_EXT
	call	addString
	sub	di,di			; zap DI so that we don't try again
	jmp	lf1
lf1a:	jmp	openError

lf1b:	call	freeText		; free any pre-existing blocks
	test	dx,dx
	jnz	lf2
	add	ax,TBLKLEN
	jnc	lf2a
lf2:	mov	ax,0FFFFh
lf2a:	xchg	cx,ax			; CX = size of initial text block
	mov	[pTextLimit],cx
	call	allocText
	jc	lf4y
;
; For every complete line at DS:SI, determine the line label (if any), and
; then add the label # (2 bytes), line length (1 byte), and line contents
; (not including any leading space or terminating CR/LF) to the text block.
;
	lea	bx,[bx].LINEBUF
	sub	cx,cx			; DS:SI contains zero bytes now

lf3:	jcxz	lf4
	push	cx
	mov	dx,si			; save SI
lf3a:	lodsb
	cmp	al,CHR_RETURN
	je	lf3b
	loop	lf3a
lf3b:	xchg	si,dx			; restore SI; DX is how far we got
	pop	cx
	je	lf5			; we found the end of a line
;
; The end of the current line is not contained in our buffer, so "slide"
; everything at DS:SI down to LINEBUF, fill in the rest of LINEBUF, and try
; again.
;
	cmp	si,bx			; is current line already at LINEBUF?
	je	lf4y			; yes, we're done
	push	cx
	push	di
	push	es
	push	ds
	pop	es
	mov	di,bx
	rep	movsb
	pop	es
	pop	di
	pop	cx
lf4:	mov	si,bx			; DS:SI has been adjusted
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
	jcxz	lf4y			; if file is exhausted, we're done
	jmp	lf3
lf4x:	jmp	lf10
lf4y:	jmp	lf12
;
; We found the end of another line starting at DS:SI and ending at DX.
;
lf5:	mov	[lineOffset],si
	lodsb
	cmp	al,CHR_LINEFEED		; skip LINEFEED from the previous line
	je	lf6
	dec	si

lf6:	push	bx
	push	cx
	push	dx
	mov	bl,10
	mov	cx,-1			; CX = unknown length
	mov	ax,DOS_UTL_ATOI32	; DS:SI -> numeric string
	int	21h
	ASSERT	Z,<test dx,dx>		; DX:AX is the result but keep only AX
	mov	[lineLabel],ax
	pop	dx
	pop	cx
	pop	bx
;
; We've extracted the label #, if any; skip over any intervening space.
;
	lodsb
	cmp	al,CHR_SPACE
	je	lf7
	dec	si

lf7:	dec	dx			; back up to CHR_RETURN
	sub	dx,si			; DX = # of chars on line (may be zero)
;
; Is there room for DX more bytes at ES:DI?
;
	mov	ax,di
	add	ax,dx
	add	ax,3
	cmp	ax,[pTextLimit]		; overflows the current text block?
	jbe	lf8			; no
;
; No, there's not enough room, so allocate another text block.
;
	push	cx
	mov	cx,TBLKLEN
	mov	[pTextLimit],cx
	push	si
	call	allocText
	pop	si
	pop	cx
	jc	lf11			; unable to allocate enough memory

lf8:	mov	ax,[lineLabel]
	stosw
	mov	al,dl
	stosb
	push	cx
	mov	cx,dx
	rep	movsb
	mov	es:[TBLK_FREE],di
	pop	cx
	mov	ax,si
	sub	ax,[lineOffset]
	sub	cx,ax
;
; Consume the line terminator and go back for more.
;
	lodsb
	dec	cx
	jmp	lf3

lf10:	PRINTF	<"Invalid file format",13,10>

lf11:	call	freeText
	stc

lf12:	pushf
	call	closeFile
	popf
	ret
ENDPROC	cmdLoad

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdRun
;
; Inputs:
;	DS:BX -> heap
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdRun
	sub	si,si
	call	genCode
	ret
ENDPROC	cmdRun

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdTime
;
; Inputs:
;	DS:BX -> heap
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
; cmdVer
;
; Prints the BASIC-DOS version.
;
; Inputs:
;	DS:BX -> heap
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	cmdVer
	mov	ah,DOS_MSC_GETVER
	int	21h
	mov	al,ah
	cbw
	mov	dl,bh
	mov	dh,ah
	mov	bh,ah
	test	cx,1
	mov	cx,offset STD_VER
	jz	ver9
	mov	cx,offset DBG_VER
ver9:	PRINTF	<"BASIC-DOS Version %d.%d%d %ls",13,10>,ax,dx,bx,cx,cs
	ret
ENDPROC	cmdver

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdType
;
; Read the specified file and write the contents to STDOUT.
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
DEFPROC	cmdType
	call	openFile		; SI -> filename
	jc	openError
	mov	si,PSP_DTA		; SI -> DTA (used as a read buffer)
ty1:	mov	cx,size PSP_DTA		; CX = number of bytes to read
	call	readFile
	jc	closeFile
	test	ax,ax			; anything read?
	jz	closeFile		; no
	mov	bx,STDOUT
	xchg	cx,ax			; CX = number of bytes to write
	mov	ah,DOS_HDL_WRITE
	int	21h
	jmp	ty1
ENDPROC	cmdType

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openFile
;
; Open the specified file; used by "LOAD" and "TYPE".
; As an added bonus, return the size of the file in DX:AX.
;
; Inputs:
;	DS:SI -> filename
;
; Outputs:
;	If carry clear, [hFile] is updated, and DX:AX is the file size
;
; Modifies:
;	AX, DX
;
DEFPROC	openFile
	push	bx
	mov	dx,si			; DX -> filename
	mov	ax,DOS_HDL_OPEN SHL 8
	int	21h
	jc	of9
	mov	[hFile],ax		; save file handle
	xchg	bx,ax			; BX = handle
	sub	cx,cx
	sub	dx,dx
	mov	ax,DOS_HDL_SEEKEND
	int	21h
	push	ax
	push	dx
	sub	cx,cx
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	pop	dx
	pop	ax
of9:	pop	bx
	ret
	DEFLBL	openError,near
	PRINTF	<"Unable to open %s (%d)",13,10>,dx,ax
	stc
	ret
ENDPROC	openFile

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
; readFile
;
; Read CX bytes from the default file into the buffer at DS:SI.
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
; findFile
;
; Find the filename at DS:SI.
;
; Inputs:
;	DS:SI -> filename
;
; Outputs:
;	Carry clear if file found, set otherwise (AX = error #)
;
; Modifies:
;	AX
;
DEFPROC	findFile
	push	cx
	push	dx
	sub	cx,cx
	mov	dx,si
	mov	ah,DOS_DSK_FFIRST
	int	21h			; find file (DS:DX) with attrs (CX=0)
	pop	dx
	pop	cx
	ret
ENDPROC	findFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addString
;
; Copy a source string (CS:DX) to the end of a target string (DS:DI).
;
; Inputs:
;	CS:DX -> source
;	DS:DI -> target (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	addString
	push	si
	push	di
	add	di,cx
	mov	si,dx
as1:	lods	byte ptr cs:[si]
	stosb
	test	al,al
	jnz	as1
	pop	di
	pop	si
	ret
ENDPROC	addString

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkString
;
; Check the target string (DS:SI) for the source string (CS:DX).
;
; Inputs:
;	CS:DX -> source
;	DS:SI -> target
;
; Outputs:
;	If carry clear, DI points to the first match; otherwise, DI = SI
;
; Modifies:
;	AX, DI
;
DEFPROC	chkString
	mov	di,si			; ES:DI -> target
	push	si
	mov	si,dx			; CS:SI -> source
	mov	ax,DOS_UTL_STRSTR
	int	21h			; if carry clear, DI updated
	pop	si
	ret
ENDPROC	chkString

CODE	ENDS

	end	main
