;
; BASIC-DOS Command Interpreter
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT
	org	100h

	EXTERNS	<allocText,freeAllText,genCode,freeAllCode,freeAllVars>,near
	EXTERNS	<writeStrCRLF>,near

	EXTERNS	<KEYWORD_TOKENS>,word
	EXTSTR	<COM_EXT,EXE_EXT,BAS_EXT,BAT_EXT,DIR_DEF,PERIOD>
	EXTSTR	<STD_VER,DBG_VER,HELP_FILE>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

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
;
; Before invoking ENTER, we ensure the stack is aligned with the CMD_HEAP
; structure; the BASIC-DOS loader assumes we'll be happy with a stack at the
; very top of the segment, but this allows the main module to access the heap
; via [heap] (BP) instead of loading PSP_HEAP into another register (BX).
;
	mov	bx,ds:[PSP_HEAP]
	lea	sp,[bx].STACK + size STACK
	sub	ax,ax
	push	ax

	ENTER
	mov	[heap].ORIG_SP,sp
	mov	[heap].ORIG_BP,bp
	ASSERT	Z,<cmp bp,[bx].ORIG_BP>
	mov	[heap].CMD_FLAGS,CMD_ECHO
	mov	[hFile],ax
	push	ds
	push	cs
	pop	ds
	mov	dx,offset ctrlc		; DS:DX -> CTRLC handler
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	int	21h
	pop	ds

	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDIM
	mov	bx,STDOUT
	int	21h
	mov	word ptr [heap].CON_COLS,ax

	PRINTF	<"BASIC-DOS Interpreter",13,10,13,10>
	IFDEF	MSLIB
	PRINTF	<"BASIC MATH library functions",13,10,"Copyright (c) Microsoft Corporation",13,10,13,10>
	ENDIF
;
; Check the PSP_CMDTAIL for a startup command.  Startup commands must be
; explicitly provided; there is no support for a global AUTOEXEC.BAT, since
; 1) it's likely each session will want its own startup command(s), and 2)
; it's easy enough to specify the name of any desired BAT file on any or all
; of the SHELL= lines in CONFIG.SYS.
;
; Our approach is simple (perhaps even too simple): if a tail exists, set
; INPUTOFF (which ordinarily points to INPUTBUF) to PSP_CMD_TAIL-1 instead,
; and then jump into the command-processing code below.
;
	mov	[heap].INPUTOFF,PSP_CMDTAIL - 1
	mov	word ptr [heap].INPUTBUF.INP_MAX,size INP_BUF - 1
	cmp	ds:[PSP_CMDTAIL],0
	jne	m1a			; use INPUTOFF -> PSP_CMDTAIL
;
; Since all command handlers loop back to this point, we shouldn't assume
; that these registers (eg, DS, ES) will still contain their original values.
;
m0:	push	ss
	pop	ds
	push	ss
	pop	es

m1:	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'			; AL = current drive letter
	PRINTF	<"%c",CHR_GT>,ax

	lea	dx,[heap].INPUTBUF
	mov	[heap].INPUTOFF,dx
	mov	ah,DOS_TTY_INPUT
	int	21h
	call	printCRLF

m1a:	sub	ax,ax
	mov	[swDigits],ax
	mov	[swLetters].LOW,ax
	mov	[swLetters].HIW,ax
	mov	si,[heap].INPUTOFF
	mov	cl,[si].INP_CNT
	lea	si,[si].INP_BUF
	lea	di,[heap].TOKENBUF	; ES:DI -> TOKENBUF
	mov	[di].TOK_MAX,(size TOK_BUF) / (size TOKLET)
	DOSUTIL	TOKIFY1
	jc	m0			; jump if no tokens
;
; Before trying to ID the token, let's copy it to the FILENAME buffer,
; upper-case it, and null-terminate it.
;
	mov	dh,1
	call	getToken		; DS:SI -> token #1, CX = length
	jc	m0
	mov	[pArg],si		; save original filename ptr and length
	mov	[lenArg],cx
	lea	di,[heap].FILENAME
	mov	ax,size FILENAME
	cmp	cx,ax
	jb	m1b
	xchg	cx,ax
m1b:	push	cx
	push	di
	rep	movsb
	mov	al,0
	stosb
	pop	si			; DS:SI -> copy of token in FILENAME
	pop	cx
	DOSUTIL	STRUPR			; DS:SI -> token, CX = length
	lea	dx,[KEYWORD_TOKENS]
	DOSUTIL	TOKID			; CS:DX -> TOKTBL; identify the token
	jc	m2
	mov	dx,cs:[si].CTD_FUNC
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
m2a:	PRINTF	<"Drive %c: invalid",13,10,13,10>,cx
m2b:	jmp	m0
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
m4a:	jmp	m8
;
; BAT files are LOAD'ed and then immediately RUN.  We may as well do the same
; for BAS files; you can always use the "LOAD" command to load without running.
;
; BAT file operation does differ in some respects.  For example, any existing
; variables remain in memory prior to executing a BAT file, but all variables
; are freed prior to running a BAS file.  Also, each line of a BAT file is
; displayed before it's executed, unless prefixed with '@'.  These differences
; are why we must call cmdRunFlags with GEN_BASIC or GEN_BATCH as appropriate.
;
; Another side-effect of an implied LOAD+RUN operation is that we free the
; loaded program (ie, all text blocks) when it finishes running.  Any variables
; set (ie, all var blocks) are allowed to remain in memory.
;
; Note that if the execution is aborted (eg, critical error, CTRLC signal),
; the program remains loaded, available for LIST'ing, RUN'ing, etc.
;
m4b:	push	dx
	call	cmdLoad
	pop	dx
	jc	m4d			; don't RUN if LOAD error
	mov	al,GEN_BASIC
	cmp	dx,offset BAS_EXT
	je	m4c
	mov	al,GEN_BATCH
m4c:	call	cmdRunFlags		; if cmdRun returns normally
	call	freeAllText		; automatically free all text blocks
m4d:	or	[heap].CMD_FLAGS,CMD_ECHO
	jmp	m0
;
; COM and EXE files are EXEC'ed, which requires building EXECDATA.
;
m5:	mov	dx,si			; DS:DX -> filename
	mov	si,[pArg]		; recover original filename ptr
	add	si,cx			; DS:SI -> cmd tail after filename
	lea	bx,[heap].EXECDATA
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
;
; Parse the cmd tail into the FCBs that we're passing along as well.
;
	lea	si,[di+1]		; DS:SI -> string for DOS_FCB_PARSE
	mov	di,PSP_FCB1		; ES:DI -> FCB to fill in
	mov	ax,(DOS_FCB_PARSE SHL 8) or 01h
	int	21h
	mov	[bx].EPB_FCB1.OFF,di
	mov	[bx].EPB_FCB1.SEG,es
	mov	di,PSP_FCB2		; ES:DI -> FCB to fill in
	mov	ax,(DOS_FCB_PARSE SHL 8) or 01h
	int	21h
	mov	[bx].EPB_FCB2.OFF,di
	mov	[bx].EPB_FCB2.SEG,es

	mov	ax,DOS_PSP_EXEC
	int	21h			; EXEC program at DS:DX
	jc	m8
	mov	ah,DOS_PSP_RETCODE
	int	21h
	mov	dl,ah
	mov	ah,0
	mov	dh,0
	PRINTF	<"Return code %d (%d)",13,10,13,10>,ax,dx
	jmp	m0

m8:	PRINTF	<"Error loading %s: %d",13,10,13,10>,dx,ax
	jmp	m0
;
; We arrive here if the token was recognized.  The token ID determines
; the level of additional parsing required, if any.
;
m9:	lea	di,[heap].TOKENBUF	; DS:DI -> token buffer
	cmp	ax,KEYWORD_BASIC	; token ID < KEYWORD_BASIC? (40)
	jb	m10			; yes, no code generation required
;
; The token is for a BASIC keyword, so code generation is required.
;
	mov	al,GEN_IMM
	lea	bx,[heap]
	mov	si,[heap].INPUTOFF
	call	genCode
	jmp	m0
;
; For non-BASIC commands, check for switches, record any that we find prior
; to the first non-switch argument, and then invoke the command handler.
;
m10:	call	cmdDOS
	jmp	m0
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdTest
;
; Process test commands.  Our first test command is a pipe test: the logical
; equivalent of "TYPE CONFIG.SYS | CASE".  Once the plumbing is working, we'll
; add support for parsing pipe syntax from the command-line, so that you can
; actually type that command.
;
; Here are the basic steps for our first pipe test:
;
;	1) Open a pipe ("PIPE$")
;	2) Create an SPB (Session Parameter Block)
;	3) Set the SPB's STDIN SFH to the pipe's SFH
;	4) Set the SPB's STDOUT SFH to our own STDOUT SFH
;	5) Load and start "CASE.COM" using the SPB
;	6) Temporarily set our own STDOUT SFH to the pipe's SFH
;	7) Invoke cmdType to perform "TYPE CONFIG.SYS"
;	8) Restore our own STDOUT SFH to its original value
;	9) Close the pipe
;
; The ordering of the steps above is somewhat aribtrary and may be changed
; and/or condensed over time, but we have to start somewhere.
;
; Inputs:
;	DS:DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
	IFDEF	DEBUG
DEFPROC	cmdTest
	ret
ENDPROC	cmdTest
	ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDOS
;
; Process any non-BASIC command.  We allow such commands inside both BAS and
; BAT files, with the caveat that the rest of the line is treated as a DOS
; command (eg, you can't use a colon to append another BASIC command).
;
; TODO: There are still ambiguities to resolve.  For example, a simple DOS
; command like "B:" will generate a syntax error if present in a BAS/BAT file.
;
; Inputs:
;	AX = keyword ID
;	DS:DI -> TOKENBUF
;	CS:DX -> offset of handler
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDOS
	push	dx
	call	parseSW			; parse all switch arguments, if any
	cmp	ax,KEYWORD_FILE		; does token require a filespec? (20)
	jb	nb8			; no
;
; The token is for a command that expects a filespec, so fix up the next
; token (index in DH).  If there is no token, then use defaults loaded into
; SI and CX.
;
	call	getToken		; DH = 1st non-switch argument (or -1)
	jnc	nb1
	push	cs
	pop	ds
	mov	si,offset DIR_DEF
	mov	cx,DIR_DEF_LEN - 1
	jmp	short nb2
nb1:	mov	ax,size FILENAME-1	; DS:SI -> token, CX = length
	cmp	cx,ax
	jbe	nb2
	xchg	cx,ax
nb2:	push	di
	lea	di,[heap].FILENAME
	push	cx
	push	di
	rep	movsb
	mov	byte ptr es:[di],0
	pop	si			; DS:SI -> copy of token in FILENAME
	pop	cx
	pop	di
	push	ss
	pop	ds
	DOSUTIL	STRUPR			; DS:SI -> token, CX = length

nb8:	pop	cx			; CX = handler (originally in DX)
	jcxz	nb9
	lea	bx,[heap]
	call	cx			; call the token handler
nb9:	ret
ENDPROC	cmdDOS

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
;	DS:DI -> TOKENBUF
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
psw1:	call	getToken
	jc	psw8
	lodsb
	cmp	al,dl			; starts with SWITCHAR?
	je	psw2			; yes
	mov	[iArg],dh		; update iArg with first non-switch
	jmp	short psw7		; no
psw2:	lodsb				; consume option chars
	cmp	al,'a'			; until we reach non-alphanumeric char
	jb	psw3
	sub	al,20h
psw3:	sub	al,'0'
	jb	psw7			; not alphanumeric
	cmp	al,16
	jae	psw5
	lea	bx,[swDigits]
psw4:	mov	cl,al
	mov	ax,1
	shl	ax,cl
	mov	[bx],ax			; set bit in word at [bx]
	jmp	psw2			; go back for more option chars
psw5:	sub	al,'A'-'0'
	jb	psw7			; not alphanumeric
	cmp	al,16			; in the range of the first 16?
	jae	psw6			; no
	lea	bx,[swLetters].LOW
	jmp	psw4
psw6:	sub	al,16
	cmp	al,10			; in the range of the next 10?
	jae	psw7			; no
	lea	bx,[swLetters].HIW
	jmp	psw4
psw7:	inc	dh			; advance to next token
	jmp	psw1
psw8:	mov	dh,[iArg]		; DH = first non-switch (-1 if none)
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
;	DS:DI -> TOKENBUF
;
; Outputs:
;	If carry clear, DS:SI -> token, CX = length, and ZF set
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
	sub	ch,ch			; clear CF and set ZF
	pop	bx
gt9:	ret
ENDPROC	getToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ctrlc
;
; CTRLC handler: resets the program stack, closes any open file, frees any
; active code buffer, and then jumps to our start address.
;
; Inputs:
;	None
;
; Outputs:
;	DS = ES = SS
;	SP and BP reset
;
; Modifies:
;	Any
;
DEFPROC	ctrlc,FAR
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	bx,ds:[PSP_HEAP]
	mov	sp,[bx].ORIG_SP
	mov	bp,[bx].ORIG_BP
	call	closeFile
	call	freeAllCode
	jmp	m0
ENDPROC	ctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDate
;
; Set a new system date (eg, "MM-DD-YY", "MM/DD/YYYY").  Omitted portions
; of the date string default to the current date's values.  This intentionally
; differs from cmdTime, where omitted portions always default to zero.
;
; Inputs:
;	DS:DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDate
	mov	ax,offset promptDate
	call	getInput		; DS:SI -> string
	jc	gt9			; do nothing on empty string
	mov	bh,'-'
	call	getValues
	xchg	dx,cx			; DH = month, DL = day, CX = year
	cmp	cx,100
	jae	cdt1
	add	cx,1900			; 2-digit years are automatically
	cmp	cx,1980			; adjusted to 4-digit years 1980-2079
	jae	cdt1
	add	cx,100
cdt1:	mov	ah,DOS_MSC_SETDATE
	int	21h			; set the date
	test	al,al			; success?
	stc
	jz	promptDate		; yes, display new date and return
	PRINTF	<"Invalid date",13,10>
	cmp	[di].TOK_CNT,0		; did we process a command-line token?
	je	cdt9			; yes
	jmp	cmdDate

	DEFLBL	promptDate,near
	DOSUTIL	GETDATE			; GETDATE returns packed date
	xchg	dx,cx
	jnc	cdt9			; if caller's carry clear, skip output
	pushf
	PRINTF	<"Current date is %.3W %M-%02D-%Y",13,10>,ax,ax,ax,ax
	popf				; do we need a prompt?
	jz	cdt9			; no
	PRINTF	<"Enter new date: ">
	test	ax,ax			; clear CF and ZF
cdt9:	ret
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
	mov	[pArg],si
	mov	[lenArg],cx
;
; If filespec begins with ":", extract drive letter, and if it ends
; with ":" as well, append DIR_DEF ("*.*").
;
dir1:	push	bp
	mov	dl,0			; DL = default drive #
	mov	di,cx			; DI = length of filespec
	cmp	cx,2
	jb	dir2
	cmp	byte ptr [si+1],':'
	jne	dir2
	mov	al,[si]
	sub	al,'A'-1
	jb	dirx
	mov	dl,al			; DL = specific drive # (1-based)
dir2:	mov	ah,DOS_DSK_GETINFO
	int	21h			; get disk info for drive
	jnc	dir3
dirx:	jmp	dir8
;
; We primarily want the cluster size, in bytes, which this call doesn't
; provide directly; we must multiply bytes per sector (CX) by sectors per
; cluster (AX).
;
dir3:	mov	bp,bx			; BP = available clusters
	mul	cx			; DX:AX = bytes per cluster
	xchg	bx,ax			; BX = bytes per cluster

	add	di,si			; DI -> end of filespec
	cmp	byte ptr [di-1],':'
	jne	dir3a
	push	si
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	REPMOV	byte,CS
	pop	si

dir3a:	sub	cx,cx			; CX = attributes
	mov	dx,si			; DX -> filespec
	mov	ah,DOS_DSK_FFIRST
	int	21h
	jc	dirx
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
	DOSUTIL	STRLEN
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
	jmp	dir1

dir8:	PRINTF	<"Unable to find %s (%d)",13,10,13,10>,si,ax
	pop	bp

dir9:	ret
ENDPROC	cmdDir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdExit
;
; Inputs:
;	None
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
; If a keyword is specified, display help for that keyword; otherwise,
; display a list of all keywords.
;
; Inputs:
;	DS:DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdHelp
	mov	dh,[iArg]		; is there a non-switch argument?
	call	getToken
	jnc	doHelp
	jmp	h5			; no
;
; Identify the second token (DS:SI) with length CX.
;
	DEFLBL	doHelp,near
	lea	dx,[KEYWORD_TOKENS]
	DOSUTIL	TOKID			; CS:DX -> TOKTBL
	jc	h4			; unknown
;
; CS:SI -> CTOKDEF.  Load CTD_TXT_OFF into DX and CTD_TXT_LEN into CX.
;
	mov	dx,cs:[si].CTD_TXT_OFF
	mov	cx,cs:[si].CTD_TXT_LEN
	jcxz	h3			; no help indicated
	push	ds
	push	cs
	pop	ds
	mov	si,offset HELP_FILE	; DS:SI -> filename
	push	dx
	call	openFile
	pop	dx
	pop	ds
	jc	h3
	push	cx
	sub	cx,cx
	call	seekFile		; seek to 0:DX
	pop	cx
	mov	al,CHR_CTRLZ
	push	ax
	sub	sp,cx			; allocate CX bytes from the stack
	mov	si,sp
	call	readFile		; read CX bytes into DS:SI
	jc	h2c
;
; Keep track of the current line's available characters (DL) and maximum
; characters (DH), and print only whole words that will fit.
;
	mov	dl,[heap].CON_COLS	; DL = # available chars
	dec	dx			; DL = # available chars - 1
	mov	dh,dl
h2:	call	getWord			; AX = next word length
	test	al,al			; any more words?
	jz	h2c			; no
	cmp	al,dl			; will it fit on the line?
	jbe	h2a			; yes
	cmp	al,dh			; is it too large regardless?
	jbe	h2b			; no
h2a:	call	printChars		; print # chars in AL
	call	printSpace		; print whitespace that follows
	jz	h2c			; if ZF set, must have hit CHR_CTRLZ
	jmp	h2
h2b:	call	printNewLine
	jmp	h2

h2c:	add	sp,cx			; deallocate the stack space
	pop	ax
	call	closeFile
	ret

h3:	PRINTF	<"No help available",13,10>
	ret

h4:	PRINTF	<"Unknown command: %.*s",13,10>,cx,si
	ret
;
; Print all keywords with ID < KEYWORD_CLAUSE (200).
;
h5:	mov	si,offset KEYWORD_TOKENS
	lods	word ptr cs:[si]	; AL = # tokens, AH = size CTOKDEF
	mov	cl,al
	mov	ch,0			; CX = # tokens
	mov	al,ah
	cbw
	xchg	di,ax			; DI = size CTOKDEF
	mov	dl,8			; DL = # chars to be printed so far
h6:	cmp	cs:[si].CTD_ID,KEYWORD_CLAUSE
	jae	h8			; ignore token IDs >= 200
	push	dx
	mov	dl,cs:[si].CTD_LEN
	mov	dh,0
	PRINTF	<"%-8.*ls">,dx,cs:[si].CTD_OFF,cs
	pop	dx
	add	dl,al
	cmp	cl,1
	je	h7
	cmp	dl,[heap].CON_COLS
	jb	h8
h7:	call	printCRLF
	mov	dl,8
h8:	add	si,di			; SI -> next CTOKDEF
	loop	h6
h9:	ret
ENDPROC	cmdHelp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getWord
;
; Inputs:
;	DS:SI -> characters to print
;
; Outputs:
;	AX = # of characters in next non-whitespace sequence (ie, "word")
;
; Modifies:
;	AX
;
DEFPROC	getWord
	push	si
gw1:	lodsb
	cmp	al,' '
	ja	gw1
	dec	si
	pop	ax
	sub	si,ax
	xchg	si,ax
	ret
ENDPROC	getWord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printChar
;
; Inputs:
;	AL = character
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	printChar
	push	dx
	xchg	dx,ax
	mov	ah,DOS_TTY_WRITE
	int	21h
	pop	dx
	ret
ENDPROC	printChar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printChars
;
; Inputs:
;	CX = character count
;	DS:SI -> characters to print
;	DL = avail characters on line
;	DH = maximum characters on line
;
; Outputs:
;	SI, DL updated as appropriate
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	printChars
	push	ax
	push	cx
	cbw
	xchg	cx,ax			; CX = count
pc1:	lodsb
	cmp	al,'*'			; just skip asterisks for now
	je	pc8
	cmp	al,'\'			; lines ending with backslash
	jne	pc2			; trigger a single newline and
	call	skipSpace		; skip remaining whitespace
	pop	cx
	pop	ax
	ret
pc2:	call	printChar
pc8:	loop	pc1
pc9:	pop	cx
	pop	ax
	sub	dl,al			; reduce available chars on line
	ret
ENDPROC	printChars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printSpace
;
; Inputs:
;	DS:SI -> characters to print
;	DL = avail characters on line
;	DH = maximum characters on line
;
; Outputs:
;	SI, DL updated as appropriate
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	printSpace
ps1:	cmp	dl,1			; if current line is almost full
	jle	skipSpace		; print CRLF and then skip all space
	lodsb
	cmp	al,CHR_TAB
	je	ps2
	cmp	al,CHR_SPACE
	ja	ps8
	jb	ps5
ps2:	call	printChar
	dec	dx
	jmp	ps1
ps5:	dec	si
	call	printNewLine
	DEFLBL	skipSpace,near
	call	printNewLine
ps7:	lodsb
	cmp	al,CHR_CTRLZ		; end of text?
	je	ps8			; yes
	cmp	al,CHR_SPACE		; non-whitespace?
	ja	ps8			; yes
	jmp	ps7			; keep looping
ps8:	dec	si
ps9:	ret
ENDPROC	printSpace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printNewLine
;
; Inputs:
;	DL = avail characters on line
;	DH = maximum characters on line
;
; Outputs:
;	DL = DH
;
; Modifies:
;	AX, DX
;
DEFPROC	printNewLine
	mov	dl,dh			; reset available characters in DL
	DEFLBL	printCRLF,near		; the most efficient CR/LF output ever!
	PRINTF	<13,10>
	ret
ENDPROC	printNewLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdKeys
;
; Inputs:
;	DS:DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdKeys
	jmp	doHelp
ENDPROC	cmdKeys

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdList
;
; Inputs:
;	DS:DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdList
	lea	si,[heap].TBLKDEF
l2:	mov	cx,[si].BLK_NEXT
	jcxz	l9			; nothing left to parse
	mov	ds,cx
	ASSUME	DS:NOTHING
	mov	si,size TBLK
l3:	cmp	si,ds:[BLK_FREE]
	jae	l2			; advance to next block in chain
	lodsw
	test	ax,ax			; is there a label #?
	jz	l4			; no
	PRINTF	<"%5d">,ax
l4:	PRINTF	<CHR_TAB>
	call	writeStrCRLF
	jmp	l3
l9:	ret
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
	ASSUME	DS:DATA
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

lf1b:	call	freeAllText		; free any pre-existing blocks
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
	lea	bx,[heap].LINEBUF
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

lf6:	push	dx
	DOSUTIL	ATOI32D			; DS:SI -> decimal string
	ASSERT	Z,<test dx,dx>		; DX:AX is the result but keep only AX
	mov	[lineLabel],ax
	pop	dx
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
	mov	es:[BLK_FREE],di
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

lf10:	PRINTF	<"Invalid file format",13,10,13,10>

lf11:	call	freeAllText
	stc

lf12:	pushf
	call	closeFile
	popf
	ret
ENDPROC	cmdLoad

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdNew
;
; Inputs:
;	DS:DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdNew
	call	freeAllText
	call	freeAllVars
	ret
ENDPROC	cmdNew

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdRestart
;
; Inputs:
;	DS:DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdRestart
	DOSUTIL	RESTART			; this shouldn't return
	ret				; but just in case...
ENDPROC	cmdRestart

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdRun
;
; Inputs:
;	AL = GEN_BASIC or GEN_BATCH (if calling cmdRunFlags)
;	DS:DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdRun
	mov	al,GEN_BASIC		; RUN implies GEN_BASIC behavior
	DEFLBL	cmdRunFlags,near
	cmp	al,GEN_BASIC
	jne	cr1			; BASIC programs
	call	freeAllVars		; always gets a fresh set of variables
cr1:	sub	si,si
	lea	bx,[heap]
	ASSERT	Z,<cmp bx,ds:[PSP_HEAP]>
	call	genCode
	ret
ENDPROC	cmdRun

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdTime
;
; Set a new system time (eg, "HH:MM:SS.DD")  Any portion of the time string
; that's omitted defaults to zero.  TIME /P prompts for a new time, and TIME /D
; displays the difference between the current time and the previous time.
;
; Inputs:
;	DS:DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdTime
	mov	al,'D'			; /D present?
	call	checkSW
	jz	ctm3			; no

	sub	ax,ax			; set ZF
	DOSUTIL	GETTIME
	push	cx			; CX:DX = current time
	push	dx
	call	printTime
	pop	dx
	pop	cx
	push	cx
	push	dx
	sub	dl,[heap].PREV_TIME.LOW.LOB
	jnb	cmt1a
	add	dl,100			; adjust hundredths
	stc
cmt1a:	sbb	dh,[heap].PREV_TIME.LOW.HIB
	jnb	cmt1b
	add	dh,60			; adjust seconds
	stc
cmt1b:	sbb	cl,[heap].PREV_TIME.HIW.LOB
	jnb	cmt1c
	add	cl,60			; adjust minutes
	stc
cmt1c:	sbb	ch,[heap].PREV_TIME.HIW.HIB
	jnb	cmt1d
	add	ch,24			; adjust hours
cmt1d:	mov	al,ch
	cbw				; AX = hours
	mov	bl,cl
	mov	bh,0			; BX = minutes
	mov	cl,dh
	mov	ch,0			; CX = seconds
	mov	dh,0			; DX = hundredths
	PRINTF	<"Elapsed time is %2d:%02d:%02d.%02d",13,10>,ax,bx,cx,dx
	pop	[heap].PREV_TIME.LOW
	pop	[heap].PREV_TIME.HIW
ctm2:	ret

ctm3:	mov	ax,offset promptTime
	call	getInput		; DS:SI -> string
	jc	ctm2			; do nothing on empty string
	mov	bh,':'
	call	getValues
	mov	ah,DOS_MSC_SETTIME
	int	21h			; set the time
	test	al,al			; success?
	stc
	jz	promptTime		; yes, display new time and return
	PRINTF	<"Invalid time",13,10>
	cmp	[di].TOK_CNT,0		; did we process a command-line token?
	je	ctm9			; yes
	jmp	cmdTime

	DEFLBL	promptTime,near
	jnc	ctm8
	DOSUTIL	GETTIME			; GETTIME returns packed time
	mov	[heap].PREV_TIME.LOW,dx
	mov	[heap].PREV_TIME.HIW,cx
	DEFLBL	printTime,near
	mov	cl,dh
	mov	ch,0			; CX = seconds
	mov	dh,0			; DX = hundredths
	pushf
	PRINTF	<"Current time is %2H:%02N:%02d.%02d",13,10>,ax,ax,cx,dx
	popf
	jz	ctm8
	PRINTF	<"Enter new time: ">
	test	ax,ax			; clear CF and ZF
ctm8:	mov	cx,0			; instead of retaining current values
	mov	dx,cx			; set all defaults to zero
ctm9:	ret
ENDPROC	cmdTime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdVer
;
; Prints the BASIC-DOS version.
;
; Inputs:
;	DS:DI -> TOKENBUF
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
ver9:	PRINTF	<13,10,"BASIC-DOS Version %d.%d%d %ls",13,10,13,10>,ax,dx,bx,cx,cs
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
; Open the specified file; used by "LOAD" and "TYPE".  As an added bonus,
; return the size of the file in DX:AX.
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
	push	cx
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
of9:	pop	cx
	pop	bx
	ret
	DEFLBL	openError,near
	PRINTF	<"Unable to open %s (%d)",13,10,13,10>,dx,ax
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
	PRINTF	<"Unable to read file",13,10,13,10>
	stc
rf9:	pop	bx
	ret
ENDPROC	readFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; seekFile
;
; Seek to the specified position.
;
; Inputs:
;	CX:DX = absolute position
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	seekFile
	push	bx
	mov	bx,[hFile]
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	pop	bx
	ret
ENDPROC	seekFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findFile
;
; Find the filename at DS:SI.  I originally used DOS_DSK_FFIRST to find it,
; but that returns its results in the DTA, which may be where the command
; we're processing is still located (eg, if it was passed in via PSP_CMDTAIL).
;
; Since this function is always looking for a specific file (no wildcards),
; we may as well use open and close.
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
	push	dx
	call	openFile		; returns file size too, but we
	jc	ff9			; don't care (TODO: any perf impact)?
	call	closeFile
ff9:	pop	dx
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
	DOSUTIL	STRSTR			; if carry clear, DI updated
	pop	si
	ret
ENDPROC	chkString

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getInput
;
; Use by cmdDate and cmdTime to set DS:SI to an input string.
;
; Inputs:
;	AX = prompt function
;	DS:DI -> TOKENBUF
;
; Outputs:
;	CX, DX = default values from caller-supplied function
;	DS:SI -> CR-terminated string
;	Carry clear if input exists, carry set if no input provided
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	getInput
	mov	dh,[iArg]
	call	getToken
	jnc	gi1
;
; No input was provided, and we don't prompt unless /P was specified.
;
	push	ax
	mov	al,'P'
	call	checkSW
	pop	ax
	stc
;
; The prompt function performs three important steps:
;
;   1)	Load current values in CX, DX
;   2)	If CF is set, print current values
;   3)	If ZF is clear, prompt for new values and clear CF
;
gi1:	call	ax			; AX = caller-supplied function
	jbe	gi9			; if CF or ZF set, we're done
;
; Request new values.
;
	push	dx
	lea	si,[heap].LINEBUF
	mov	byte ptr [si],12	; max of 12 chars (including CR)
	mov	dx,si
	mov	ah,DOS_TTY_INPUT
	int	21h
	call	printCRLF
	pop	dx
	inc	si
	cmp	byte ptr [si],1		; set carry if no characters
	inc	si			; skip ahead to characters, if any
	ret

gi9:	mov	[di].TOK_CNT,0		; zero count to prevent reprocessing
	ret
ENDPROC	getInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getValues
;
; Used by cmdDate and cmdTime to get a series of delimited values.
;
; Inputs:
;	BH = default delimiter
;	SI -> DS-relative string data (CR-terminated)
;
; Outputs:
;	CH, CL, DH, DL
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	getValues
	call	getValue
	jc	gvs2
	mov	ch,al			; CH = 1st value (eg, month)

gvs2:	call	getValue
	jc	gvs3
	mov	cl,al			; CL = 2nd value (eg, day)

gvs3:	cmp	bh,':'
	jne	gvs4
	mov	bh,'.'

gvs4:	call	getValue
	jc	gvs5
	mov	dx,ax			; DX = 3rd value (eg, year)

gvs5:	cmp	bh,'-'			; are we dealing with a date?
	je	gvs9			; yes

	mov	dh,al			; DH = 3rd value (eg, seconds)
	push	dx
	push	di
	mov	bl,10			; BL = base 10
	lea	dx,[si+2]
	mov	di,-1			; DI = -1 (no validation data)
	DOSUTIL	ATOI16			; DS:SI -> string
	jc	gvs8
	sub	dx,si			; too many digits?
	jc	gvs6			; yes
	je	gvs7			; no, exactly 2 digits
	mov	dl,10			; one digit must be multiplied by 10
	mul	dl
	jmp	short gvs7
gvs6:	mov	al,-1
gvs7:	clc
gvs8:	pop	di
	pop	dx
	jc	gvs9
	mov	dl,al			; DL = 4th value (eg, hundredths)

gvs9:	ret
ENDPROC	getValues

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getValue
;
; Used by getValues to get a single delimited value.
;
; No data validation is performed here, since the DOS_MSC_SETDATE and
; DOS_MSC_SETTIME functions are required to validate their inputs.
;
; If delimiter validation fails, an out-of-bounds value (-1) is returned.
;
; Inputs:
;	BH = default delimiter
;	SI -> DS-relative string data (CR-terminated)
;
; Outputs:
;	If carry clear, AX = value (-1 if invalid delimiter)
;	If carry set, no data
;
; Modifies:
;	AX, BL, SI
;
DEFPROC	getValue
	push	di
	mov	bl,10			; BL = base 10
	mov	di,-1			; DI = -1 (no validation data)
	DOSUTIL	ATOI16			; DS:SI -> string
	sbb	di,di			; DI = -1 if no data
	mov	bl,[si]			; BL = termination character
	cmp	bl,CHR_RETURN		; CR (or null terminator)?
	jbe	gv9			; presumably
	inc	si
	cmp	bl,bh			; expected termination character?
	je	gv9			; yes
	cmp	bh,'-'			; was dash specified?
	jne	gv8			; no
	cmp	bl,'/'			; yes, so allow slash as well
	je	gv9			; no, not slash either
gv8:	or	ax,-1			; return invalid value
	sub	di,di			; and ensure carry will be clear
gv9:	add	di,1			; otherwise, set carry if no data
	pop	di
	ret
ENDPROC	getValue

CODE	ENDS

	end	main
