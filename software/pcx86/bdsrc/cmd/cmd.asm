;
; BASIC-DOS Command Interpreter
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT
	org	100h

	EXTNEAR	<allocText,freeAllText,genCode,freeAllCode,freeAllVars>
	EXTNEAR	<writeStrCRLF>
	EXTWORD	<KEYWORD_TOKENS>
	EXTSTR	<COM_EXT,EXE_EXT,BAS_EXT,BAT_EXT,DIR_DEF,PERIOD>
	EXTSTR	<VER_FINAL,VER_DEBUG,HELP_FILE,PIPE_NAME>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

DEFPROC	main
;
; Get the current session's screen dimensions (AL=cols, AH=rows).
;
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDIM
	mov	bx,STDOUT
	int	21h
	jnc	m0			; carry clear if BASIC-DOS
	mov	dx,offset WRONG_OS
	mov	ah,DOS_TTY_PRINT	; use DOS_TTY_PRINT instead of PRINTF
	int	21h			; since PC DOS wouldn't understand that
	ret
	DEFSTR	WRONG_OS,<"BASIC-DOS required",13,10,'$'>

m0:	mov	bx,ds:[PSP_HEAP]
	DBGINIT	STRUCT,[bx],CMD
	mov	word ptr [bx].CON_COLS,dx
	mov	ax,word ptr ds:[PSP_PFT][STDIN]
	mov	word ptr [bx].SFH_STDIN,ax
;
; Install CTRLC handler.  DS = CS only for the first instance; additional
; instances of the interpreter will have their own DS but share a common CS.
;
	push	ds
	push	cs
	pop	ds
	mov	dx,offset ctrlc		; DS:DX -> CTRLC handler
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	int	21h
	pop	ds

	PRINTF	<"BASIC-DOS Interpreter",13,10,13,10>
;
; Originally, "the plan" was to use Microsoft's MBF (Microsoft Binary Format)
; floating-point code, because who really wants to write a "new" floating-point
; emulation library from scratch?  I went down that path back in the 1980s,
; probably during my "Mandelbrot phase", but I can't find the code I wrote,
; and now that Microsoft has open-sourced GW-BASIC, it makes more sense to use
; theirs.  However, that hasn't happened yet; for now, BASIC-DOS is just an
; "Integer BASIC".  If/when that changes, MSLIB will be defined.
;
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
; INPUT_BUF (which ordinarily points to INPUTBUF) to PSP_CMD_TAIL-1 instead,
; and then jump into the command-processing code below.
;
	mov	[bx].INPUT_BUF,PSP_CMDTAIL - 1
	mov	word ptr [bx].INPUTBUF.INP_MAX,size INP_DATA - 1
	cmp	ds:[PSP_CMDTAIL],0
	jne	m2			; use INPUT_BUF -> PSP_CMDTAIL

m1:	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'			; AL = current drive letter
	PRINTF	<"%c",CHR_GT>,ax	; print drive letter and '>' symbol

	mov	[bx].CMD_ROWS,0
	lea	dx,[bx].INPUTBUF
	mov	[bx].INPUT_BUF,dx
	mov	ah,DOS_TTY_INPUT
	int	21h
	call	printCRLF

m2:	mov	si,[bx].INPUT_BUF
	mov	cl,[si].INP_CNT
	lea	si,[si].INP_DATA
	lea	di,[bx].TOKENBUF	; ES:DI -> TOKENBUF
	mov	[di].TOK_MAX,(size TOK_DATA) / (size TOKLET)
	DOSUTIL	TOKEN1
	jc	m1			; jump if no tokens

	call	parseCmd
	jmp	m1
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cleanUp
;
; Inputs:
;	None
;
; Outputs:
;	DS = ES = SS
;	BX -> CMDHEAP
;
; Modifies:
;	Any
;
DEFPROC	cleanUp
	pushf
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	bx,5			; close all non-STD handles
cu1:	mov	ah,DOS_HDL_CLOSE
	int	21h
	inc	bx
	cmp	bx,size PSP_PFT
	jb	cu1
	mov	bx,ds:[PSP_HEAP]	; and then restore the STD ones
	mov	ax,word ptr [bx].SFH_STDIN
	mov	word ptr ds:[PSP_PFT][STDIN],ax
;
; If we successfully loaded another program but then ran into some error
; before we could start the program, we MUST clean it up, and the best way
; to do that is to let normal termination processing free all the resources.
;
; So we execute it with a "suicide" option, setting its CS:IP to its own
; termination code at PSP:0.
;
	mov	cx,[bx].CMD_PROCESS	; does a loaded program exist?
	jcxz	cu9			; no
	push	bx
	mov	bp,bx
	lea	bx,[bx].EXECDATA
	mov	[bx].EPB_INIT_IP.LOW,0	; set the program's CS:IP to PSP:0
	mov	[bx].EPB_INIT_IP.HIW,cx
	call	cmdExec			; this should be a very fast "EXEC"
	pop	bx
cu9:	popf
	ret
ENDPROC	cleanUp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ctrlc
;
; CTRLC handler to clean up the last operation, reset the program stack,
; free any active code buffer, and then jump to our start address.
;
; Inputs:
;	None
;
; Outputs:
;	DS = ES = SS
;	BX -> CMDHEAP
;
; Modifies:
;	Any
;
DEFPROC	ctrlc,FAR
	call	cleanUp
	lea	sp,[bx].STACK + size STACK
	call	freeAllCode
	jmp	m1
ENDPROC	ctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parseCmd
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
DEFPROC	parseCmd
	mov	dl,0
	call	getToken		; DS:SI -> 1st token, CX = length
	jc	pc9

	mov	[bx].CMD_ARGPTR,si	; save original filename ptr and length
	mov	[bx].CMD_ARGLEN,cx

	lea	dx,[KEYWORD_TOKENS]
	DOSUTIL	TOKID			; CS:DX -> TOKTBL; identify the token
	jc	pc2
;
; We arrive here if the token was recognized.  The token ID in AX determines
; the level of additional parsing required, if any.
;
pc1:	mov	dx,cs:[si].CTD_FUNC
	mov	si,[bx].CMD_ARGPTR	; restore SI (changed by TOKID)
	cmp	ax,KEYWORD_BASIC	; token ID < KEYWORD_BASIC? (40)
	jb	pc2			; yes, no code generation required
;
; The token is for a BASIC keyword, so code generation is required.
;
	mov	al,GEN_IMM
	mov	si,[bx].INPUT_BUF
	call	genCode
	call	cleanUp
	jmp	short pc9
;
; For non-BASIC commands, we have either a built-in command or an external
; program/command file.  For built-in commands, we check for switches, record
; any that we find prior to the first non-switch argument, and then invoke the
; command handler.
;
pc2:	call	parseDOS		; DS:SI -> 1st token, CX = length

pc9:	ret
ENDPROC	parseCmd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parseDOS
;
; Parse one or more DOS (ie, built-in or external) commands.  This deals
; with pipe and redirection symbols and feeds discrete commands to cmdDOS.
;
; This is effectively a wrapper around cmdDOS; if redirection support wasn't
; required, you could call cmdDOS instead.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	SI -> 1st token
;	CX = token length
;	AX = keyword ID, if any
;	CS:DX -> offset of handler, if any
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	parseDOS
;
; Scan the TOKENBUF for a redirection symbol; if one is found, save it,
; process it, replace it with a null, call cmdDOS, and then restore it and
; continue scanning TOKENBUF.
;
	push	bp
	mov	bp,bx			; use BP to access CMDHEAP instead
	ASSERT	STRUCT,[bp],CMD
	mov	al,[di].TOK_CNT
	ASSERT	Z,<test ah,ah>
	add	ax,ax
	add	ax,ax
	ASSERT	<size TOKLET>,EQ,4	; AX = end of TOKLETs
	sub	bx,bx			; BX = 0
	mov	[bp].CMD_ARG,bl		; initialize CMD_ARG
	mov	[bp].CMD_DEFER[0],bx	; no deferred command (yet)
	mov	[bp].HDL_INPIPE,bx	; no input pipe (yet)
	mov	[bp].HDL_OUTPIPE,bx	; and no output pipe (yet)
	dec	bx			; BX = -1
	mov	[bp].HDL_INPUT,bx
	mov	[bp].HDL_OUTPUT,bx
	mov	[bp].SCB_NEXT,bl
	inc	bx			; BX = 0 again (offset of 1st TOKLET)

pd1:	push	ax			; save end of TOKLETs
	sub	cx,cx
	sub	si,si
	sub	dx,dx			; DX is set if we hit a symbol
pd2:	cmp	bx,ax			; reached end of TOKLETs?
	je	pd5			; yes
	ja	pd3a			; definitely
	cmp	[di].TOK_DATA[bx].TOKLET_CLS,CLS_SYM
	je	pd4			; process symbol
	test	si,si			; do we have an initial token yet?
	jnz	pd3			; yes
	mov	si,[di].TOK_DATA[bx].TOKLET_OFF
	mov	cl,[di].TOK_DATA[bx].TOKLET_LEN
pd3:	add	bx,size TOKLET
	jmp	pd2
pd3a:	jmp	pd9
;
; There must be more tokens after the symbol; otherwise, it's a syntax error.
;
pd4:	sub	ax,size TOKLET		; reduce the limit
	cmp	bx,ax			; is there at least one more token?
	jb	pd4a			; yes
	stc
	jmp	pd9c			; bail on error

pd4a:	push	bx
	mov	al,0
	mov	bx,[di].TOK_DATA[bx].TOKLET_OFF
	xchg	[bx],al			; null-terminated (AL = symbol)
	mov	dx,bx			; DX is offset of symbol
	pop	bx
;
; Similarly, the symbol must be valid; otherwise, it's a syntax error.
;
	push	ax
	cmp	al,'|'			; pipe symbol?
	jne	pd4b			; no
	call	openPipe		; open pipe
	jc	pd4d			; bail on error
	mov	[bp].HDL_OUTPIPE,ax
	jmp	short pd4c

pd4b:	cmp	al,'>'			; output redirection symbol?
	stc
	jne	pd4d			; no
	mov	al,1			; AL = 1 (request write-only handle)
	call	openHandle		; open handle
	jc	pd4d			; bail on error

pd4c:	cmp	[bp].CMD_ARG,0		; first command on line?
	jne	pd4d			; no
	push	bx
	xchg	bx,ax			; yes, put pipe handle in BX
	mov	al,ds:[PSP_PFT][bx]	; get its SFH
	mov	ds:[PSP_PFT][STDOUT],al	; and then replace the STDOUT SFH
	pop	bx

pd4d:	pop	ax
	jc	pd9			; bail on error

pd5:	jcxz	pd8			; no valid initial token
	push	ax
	push	dx			; save the symbol and its offset

	push	si
	lea	dx,[KEYWORD_TOKENS]
	DOSUTIL	TOKID			; CS:DX -> TOKTBL; identify token
	jc	pd5a
	mov	dx,cs:[si].CTD_FUNC
pd5a:	pop	si
	jc	pd6
	cmp	[bp].HDL_OUTPIPE,0
	je	pd6
;
; We have an internal command, which must be deferred when a pipe exists.
;
	ASSERT	NZ,<test ax,ax>		; AX must be non-zero, too
	mov	[bp].CMD_DEFER[0],ax
	mov	[bp].CMD_DEFER[2],dx
	mov	[bp].CMD_DEFER[4],si
	mov	[bp].CMD_DEFER[6],cx
	mov	ax,[bp].HDL_OUTPIPE
	mov	[bp].CMD_DEFER[8],ax
	jmp	short pd6a

pd6:	push	bx			; cmdDOS can modify most registers
	push	di			; so save anything not already saved
	push	ds
	mov	bx,bp
	call	cmdDOS
	pop	ds
	pop	di
	pop	bx

pd6a:	pop	si			; restore the symbol and its offset
	pop	ax
	jc	pd9
	test	si,si			; does a symbol offset exist?
	jz	pd9			; no, we must be done
	mov	[si],al			; restore symbol

pd8:	add	bx,size TOKLET
	mov	ax,bx
	shr	ax,1
	shr	ax,1
	mov	[bp].CMD_ARG,al
	sub	ax,ax
	xchg	[bp].HDL_OUTPIPE,ax
	mov	[bp].HDL_INPIPE,ax
	pop	ax			; restore end of TOKLETs
	jmp	pd1			; loop back for more commands, if any

pd9:	jc	pd9c
	mov	ax,[bp].CMD_DEFER[0]
	test	ax,ax			; is there a deferred command?
	jz	pd9c			; no
	js	pd9a			; yes, but it's external (-1)

	mov	si,[bp].CMD_DEFER[8]	; SI = pipe handle
	mov	dl,ds:[PSP_PFT][si]	; get its SFH
	mov	ds:[PSP_PFT][STDOUT],dl	; and then replace the STDOUT SFH

	mov	dx,[bp].CMD_DEFER[2]
	mov	si,[bp].CMD_DEFER[4]
	mov	cx,[bp].CMD_DEFER[6]
	mov	[bp].CMD_ARG,0
	mov	bx,bp
	call	cmdDOS			; invoke deferred internal command
	jmp	short pd9b

pd9a:	call	cmdExec			; invoke deferred external command

pd9b:	sub	cx,cx			; CX = 0 for "truncating" write
	mov	bx,[bp].HDL_INPIPE
	mov	ah,DOS_HDL_WRITE
	int	21h			; issue final write
	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the pipe
	mov	cl,SCB_NONE
	xchg	cl,[bp].SCB_NEXT
	cmp	cl,SCB_NONE
	je	pd9c
	DOSUTIL	WAITEND

pd9c:	call	cleanUp
	pop	ax			; discard end of TOKLETs
	pop	bp
	ret
ENDPROC	parseDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDOS
;
; Process any non-BASIC command.  We allow such commands inside both BAS and
; BAT files, with the caveat that the rest of the line is treated as a DOS
; command (eg, you can't use a colon to append another BASIC command).
;
; If AX is non-zero, we have a built-in command; DX should be the handler.
; Otherwise, we call cmdFile to load an external program or command file.
;
; TODO: There are still ambiguities to resolve.  For example, a simple DOS
; command like "B:" will generate a syntax error if present in a BAS/BAT file.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	SI -> 1st token
;	CX = token length
;	AX = keyword ID, if any
;	CS:DX -> offset of handler, if any
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	cmdDOS
	test	ax,ax			; has command already been ID'ed?
	jnz	cd1			; yes
	call	cmdFile			; no, assume it's an external file
	jmp	short cd9

cd1:	push	dx
	mov	dx,0FF01h		; DL = 1 (DH = 0FFh for no limit)
	push	ax			; to limit token parsing if needed
	DOSUTIL	PARSESW			; parse switch tokens
	mov	[bx].CMD_ARG,dl		; update index of 1st non-switch token
	pop	ax
	cmp	ax,KEYWORD_FILE		; does token require a filespec? (20)
	jb	cd8			; no
;
; The token is for a command that expects a filespec, so fix up the next
; token (index in DL).  If there is no token, use defaults from SI and CX.
;
	mov	si,offset DIR_DEF
	mov	cx,DIR_DEF_LEN - 1
	call	getFileName

cd8:	pop	dx			; DX = handler again
	test	dx,dx
	jz	cd9
	call	dx			; call the token handler
	clc				; TODO: make handlers set/clear carry
cd9:	ret
ENDPROC	cmdDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdExec
;
; Execute a previously loaded program (EXECDATA must already be filled in).
;
; Inputs:
;	BP -> CMDHEAP
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdExec
	sub	bx,bx
	xchg	bx,[bp].CMD_PROCESS
	test	bx,bx
	jz	ce9
	mov	ah,DOS_PSP_SET
	int	21h
	lea	bx,[bp].EXECDATA
	DEFLBL	cmdStart,near
	mov	ax,DOS_PSP_EXEC2
	int	21h			; start program specified by ES:BX
	mov	ah,DOS_PSP_RETCODE
	int	21h
	ASSERT	STRUCT,[bp],CMD
	mov	word ptr [bp].EXIT_CODE,ax
	mov	dl,ah			; AL = exit code, DL = exit type
	PRINTF	<"Return code %bd (%bd)",13,10,13,10>,ax,dx
ce9:	ret
ENDPROC	cmdExec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdFile
;
; Process an external command file (ie, COM/EXE/BAT/BAS file).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	SI -> 1st token
;	CX = token length
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	cmdFile
	push	bp
	mov	bp,bx
	mov	[bp].CMD_ARGPTR,si	; save original filename ptr
	mov	[bp].CMD_ARGLEN,cx
	lea	di,[bp].LINEBUF
	mov	ax,15
	cmp	cx,ax
	jb	cf1
	xchg	cx,ax
cf1:	push	cx
	push	di
	rep	movsb
	mov	al,0
	stosb
	pop	si			; DS:SI -> copy of token in LINEBUF
	pop	cx
	DOSUTIL	STRUPR			; DS:SI -> token, CX = length
;
; Determine whether DS:SI contains a drive specification or a program name.
;
cf2:	cmp	cl,2			; two characters only?
	jne	cf3			; no
	cmp	byte ptr [si+1],':'
	jne	cf3			; not a valid drive specification
	mov	cl,[si]			; CL = drive letter
	mov	dl,cl
	sub	dl,'A'			; DL = drive number
	cmp	dl,26
	jae	cf2a			; out of range
	mov	ah,DOS_DSK_SETDRV
	int	21h			; attempt to set the drive number in DL
	jnc	cf2x			; success
cf2a:	PRINTF	<"Drive %c: invalid",13,10,13,10>,cx
cf2x:	jmp	cf9
;
; Not a drive letter, so presumably DS:SI contains a program name.
;
cf3:	mov	dx,offset PERIOD
	call	chkString		; any periods in string at DS:SI?
	jnc	cf4			; yes
;
; There's no period, so append extensions in a well-defined order (ie, .COM,
; .EXE, .BAT, and finally .BAS).
;
	mov	dx,offset COM_EXT
cf3a:	call	addString
	call	findFile
	jnc	cf4
	add	dx,COM_EXT_LEN
	cmp	dx,offset BAS_EXT
	jbe	cf3a
	mov	dx,di			; DX -> LINEBUF
	add	di,cx			; every extension failed
	mov	byte ptr [di],0		; so clear the last one we tried
	mov	ax,ERR_NOFILE		; and report an error
	jmp	short cf4a
;
; The filename contains a period, so let's verify the extension and the
; action; for example, only .COM or .EXE files should be EXEC'ed (it would
; not be a good idea to execute, say, CONFIG.SYS).
;
cf4:	mov	dx,offset COM_EXT
	call	chkString
	jnc	cf5
	mov	dx,offset EXE_EXT
	call	chkString
	jnc	cf5
	mov	dx,offset BAT_EXT
	call	chkString
	jnc	cf4b
	mov	dx,offset BAS_EXT
	call	chkString
	jnc	cf4b
	mov	si,di			; filename was none of the above
	mov	ax,ERR_INVALID		; so report an error
cf4a:	jmp	cf8
;
; BAT files are LOAD'ed and then immediately RUN.  We may as well do the same
; for BAS files; you can always use the LOAD command to load without running.
;
; BAT file operation does differ in some respects.  For example, any existing
; variables remain in memory prior to executing a BAT file, but all variables
; are freed prior to running a BAS file.  Also, each line of a BAT file is
; displayed before it's executed, unless prefixed with '@' or an ECHO command
; has turned echo off.  These differences are why we must call cmdRunFlags with
; GEN_BASIC or GEN_BATCH as appropriate.
;
; Another side-effect of an implied LOAD+RUN operation is that we free the
; loaded program (ie, all text blocks) when it finishes running.  Any variables
; set (ie, all var blocks) are allowed to remain in memory.
;
; Note that if the execution is aborted (eg, critical error, CTRLC signal),
; the program remains loaded, available for LIST'ing, RUN'ing, etc.
;
cf4b:	call	cmdLoad
	jc	cf4d			; don't RUN if LOAD error
	mov	al,GEN_BASIC
	cmp	dx,offset BAS_EXT
	je	cf4c
	mov	al,GEN_BATCH
cf4c:	call	cmdRunFlags		; if cmdRun returns normally
	call	freeAllText		; automatically free all text blocks
cf4d:	jmp	cf9
;
; COM and EXE files must be loaded via either DOS_PSP_EXEC or DOS_UTL_LOAD.
;
cf5:	DOSUTIL	STRLEN			; AX = length of filename in LINEBUF
	mov	dx,si			; DS:DX -> filename
	mov	si,[bp].CMD_ARGPTR	; recover original filename
	add	si,cx			; DS:SI -> tail after original filename
	sub	cx,cx
	cmp	[bp].CMD_ARG,cl		; is this the first command?
	jne	cf6			; no, use DOS_UTL_LOAD instead
	lea	bx,[bp].EXECDATA
	mov	[bx].EPB_ENVSEG,cx	; set ENVSEG to zero for now
	mov	di,dx			; we used to set DI to PSP_CMDTAIL
	add	di,ax			; but the filename is now in LINEBUF
	inc	di			; so use the remaining space in LINEBUF
	push	di
	mov	[bx].EPB_CMDTAIL.OFF,di
	mov	[bx].EPB_CMDTAIL.SEG,es
	inc	di			; use our tail space to build new tail
cf5a:	lodsb
	cmp	al,CHR_RETURN		; command line may end with CHR_RETURN
	jbe	cf5b			; or null; we don't really care
	stosb
	inc	cx			; store and count all other characters
	jmp	cf5a
cf5b:	mov	al,CHR_RETURN		; regardless how the command line ends,
	stosb				; terminate the tail with CHR_RETURN
	pop	di
	mov	[di],cl			; set the cmd tail length
	mov	[bx].EPB_FCB1.OFF,-1	; let the EXEC function build the FCBs
	mov	ax,DOS_PSP_EXEC1
	int	21h			; load program at DS:DX
	jc	cf5e
;
; Unfortunately, at this late stage, if a pipe exists, we must defer the EXEC.
;
	cmp	[bp].HDL_OUTPIPE,0
	je	cf5c
	mov	[bp].CMD_DEFER[0],-1	; set deferred EXEC code (-1)
	mov	ah,DOS_PSP_GET
	int	21h
	mov	[bp].CMD_PROCESS,bx	; save new PSP for the deferred EXEC
	mov	bx,ss
	mov	ah,DOS_PSP_SET
	int	21h			; and finally, revert to our own PSP
	jmp	short cf5d

cf5c:	call	cmdStart
cf5d:	jmp	short cf9

cf5e:	mov	si,dx
	jmp	cf8
;
; Use DOS_UTL_LOAD to load the external program into a background session.
;
cf6:	mov	di,dx			; DI -> filename in LINEBUF
	push	di
	add	di,ax			; DI -> null
cf6a:	lodsb
	cmp	al,CHR_RETURN		; tail may end with CHR_RETURN
	jbe	cf6b			; or null; we don't really care
	stosb
	jmp	cf6a
cf6b:	mov	al,0			; regardless how the tail ends,
	stosb				; null-terminate the new command line
	pop	si			; SI -> new command line
	sub	sp,size SPB
	mov	di,sp			; ES:DI -> SPB on stack
	sub	ax,ax
	stosw				; SPB_ENVSEG <- 0
	mov	ax,si
	stosw				; SPB_CMDLINE.OFF
	mov	ax,ds
	stosw				; SPB_CMDLINE.SEG
	mov	al,[bp].SFH_STDIN
	mov	bx,[bp].HDL_INPIPE
	test	bx,bx
	jz	cf7
	mov	al,ds:[PSP_PFT][bx]
cf7:	stosb				; SPB_SFHIN
	mov	al,[bp].SFH_STDOUT
	mov	bx,[bp].HDL_OUTPIPE
	test	bx,bx
	jz	cf7a
	mov	al,ds:[PSP_PFT][bx]
cf7a:	stosb				; SPB_SFHOUT
	mov	al,ds:[PSP_PFT][STDERR]
	stosb				; SPB_SFHERR
	mov	al,ds:[PSP_PFT][STDAUX]
	stosb				; SPB_SFHAUX
	mov	al,ds:[PSP_PFT][STDPRN]
	stosb				; SPB_SFHPRN
	mov	bx,sp			; ES:BX -> SPB on stack
	DOSUTIL	LOAD			; load CMDLINE into an SCB
	lea	sp,[bx + size SPB]	; clean up the stack
	jc	cf8
	mov	[bp].SCB_NEXT,cl
	DOSUTIL	START			; start the SCB # specified in CL
	jmp	short cf9
cf8:	call	openError		; report error (AX) opening file (SI)
cf9:	pop	bp
	ret
ENDPROC	cmdFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getFileName
;
; Inputs:
;	SI = default filespec
;	CX = default filespec length (zero if no default)
;	DL = token # (0-based)
;	DI -> TOKENBUF
;
; Outputs:
;	If carry clear, DS:SI -> filespec, CX = length
;
; Modifies:
;	CX, SI
;
DEFPROC	getFileName
	call	getToken		; DL = 1st non-switch argument
	jnc	gf1
	jcxz	gf9			; bail if no default was provided
	push	cs			; assumes default is in CS segment
	pop	ds
	jmp	short gf2
gf1:	mov	ax,15			; DS:SI -> token, CX = length
	cmp	cx,ax
	jbe	gf2
	xchg	cx,ax
gf2:	push	di
	lea	di,[bx].LINEBUF
	push	cx
	push	di
	rep	movsb
	mov	byte ptr es:[di],0
	pop	si			; DS:SI -> copy of token in LINEBUF
	pop	cx
	pop	di
	push	ss
	pop	ds
	DOSUTIL	STRUPR			; DS:SI -> token, CX = length
	clc
gf9:	ret
ENDPROC	getFileName

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getToken
;
; Inputs:
;	DL = token # (0-based)
;	DI -> TOKENBUF
;
; Outputs:
;	If carry clear, DS:SI -> token, CX = length (and ZF set)
;
; Modifies:
;	CX, SI
;
DEFPROC	getToken
	cmp	dl,[di].TOK_CNT
	cmc
	jb	gt9
	push	bx
	mov	bl,dl
	mov	bh,0			; BX = 0-based index
	add	bx,bx
	add	bx,bx			; BX = BX * 4 (size TOKLET)
	ASSERT	<size TOKLET>,EQ,4
	cmp	[di].TOK_DATA[bx].TOKLET_CLS,CLS_SYM
	stc				; treat symbol as end-of-tokens
	je	gt8
	mov	si,[di].TOK_DATA[bx].TOKLET_OFF
	mov	cl,[di].TOK_DATA[bx].TOKLET_LEN
	ASSERT	NB,<cmp byte ptr [si],1>
	sub	ch,ch			; set ZF on success, too
gt8:	pop	bx
gt9:	ret
ENDPROC	getToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdCopy
;
; Copy the specified input file to the specified output file.
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
DEFPROC	cmdCopy
	ASSERT	STRUCT,[bx],CMD
	call	openInput		; SI -> filename
	jc	openError		; report error (AX) opening file (SI)
	cmp	[bx].HDL_OUTPUT,0	; do we already have an output file?
	jge	cc1			; yes
	mov	dl,[bx].CMD_ARG
	inc	dx			; DL = DL + 1
	sub	cx,cx			; no default filespec in this case
	call	getFileName
	jnc	cc0
	PRINTF	<"Missing output file",13,10>
	jmp	short cc9
cc0:	call	openOutput
	jc	openError
cc1:	mov	si,PSP_DTA		; SI -> DTA (used as a read buffer)
cc2:	mov	cx,size PSP_DTA		; CX = number of bytes to read
	call	readInput
	jc	cc8
	test	ax,ax			; anything read?
	jz	cc8			; no
	xchg	cx,ax			; CX = number of bytes to write
	call	writeOutput
	jnc	cc2
;
; NOTE: We no longer explicitly close the input and output files, either on
; success or failure, simply because we now rely on the cleanUp function to be
; invoked at the end of every command -- which, among other things, closes all
; non-STD file handles that are still open.
;
cc8:	ret
	DEFLBL	openError,near		; report error (AX) opening file (SI)
	push	ax
	PRINTF	<"Unable to open %s (%d)",13,10,13,10>,si,ax
	pop	ax
cc9:	stc
	ret
ENDPROC	cmdCopy

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDate
;
; Set a new system date (eg, "MM-DD-YY", "MM/DD/YYYY").  Omitted portions
; of the date string default to the current date's values.  This intentionally
; differs from cmdTime, where omitted portions always default to zero.
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
DEFPROC	cmdDate
	mov	ax,offset promptDate
	call	getInput		; DS:SI -> string
	jc	cc9			; do nothing on empty string
	mov	ah,'-'
	call	getValues
	xchg	dx,cx			; DH = month, DL = day, CX = year
	cmp	cx,100
	jae	dt1
	add	cx,1900			; 2-digit years are automatically
	cmp	cx,1980			; adjusted to 4-digit years 1980-2079
	jae	dt1
	add	cx,100
dt1:	mov	ah,DOS_MSC_SETDATE
	int	21h			; set the date
	test	al,al			; success?
	stc
	jz	promptDate		; yes, display new date and return
	PRINTF	<"Invalid date",13,10>
	cmp	[di].TOK_CNT,0		; did we process a command-line token?
	je	dt9			; yes
	jmp	cmdDate

	DEFLBL	promptDate,near
	DOSUTIL	GETDATE			; GETDATE returns packed date
	xchg	dx,cx
	jnc	dt9			; if caller's carry clear, skip output
	pushf
	PRINTF	<"Current date is %.3W %M-%02D-%Y",13,10>,ax,ax,ax,ax
	popf				; do we need a prompt?
	jz	dt9			; no
	PRINTF	<"Enter new date: ">
	test	ax,ax			; clear CF and ZF
dt9:	ret
ENDPROC	cmdDate

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
	mov	[bx].CMD_ARGPTR,si
	mov	[bx].CMD_ARGLEN,cx
;
; If filespec begins with ":", extract drive letter, and if it ends
; with ":" as well, append DIR_DEF ("*.*").
;
di1:	push	bp
	mov	dl,0			; DL = default drive #
	mov	di,cx			; DI = length of filespec
	cmp	cx,2
	jb	di2
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

	add	di,si			; DI -> end of filespec
	cmp	byte ptr [di-1],':'
	jne	di3a
	push	si
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	REPS	MOVS,ES,CS,BYTE
	pop	si

di3a:	sub	cx,cx			; CX = attributes
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
	PRINTF	<"%-8.*s %-3s %7ld %2M-%02D-%02X %2G:%02N%A",13,10>,ax,si,di,ds:[PSP_DTA].FFB_SIZE.LOW,ds:[PSP_DTA].FFB_SIZE.HIW,dx,dx,dx,cx,cx,cx
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
;
; For testing purposes: if /L is specified, display the directory in a "loop".
;
	pop	bp

	IFDEF	DEBUG
	TESTSW	<'L'>
	jz	di9
	call	countLine
	mov	bx,ds:[PSP_HEAP]
	mov	si,[bx].CMD_ARGPTR
	mov	cx,[bx].CMD_ARGLEN
	jmp	di1
	ENDIF	; DEBUG

di8:	PRINTF	<"Unable to find %s (%d)",13,10,13,10>,si,ax
	pop	bp

di9:	ret
ENDPROC	cmdDir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdExit
;
; Inputs:
;	BX -> CMDHEAP
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
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdHelp
	mov	dl,[bx].CMD_ARG		; is there a non-switch argument?
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
	call	openInput
	pop	dx
	pop	ds
	jc	h3
	push	cx
	sub	cx,cx
	call	seekInput		; seek to 0:DX
	pop	cx
	mov	al,CHR_CTRLZ
	push	ax
	sub	sp,cx			; allocate CX bytes from the stack
	mov	si,sp
	call	readInput		; read CX bytes into DS:SI
	jc	h2c
;
; Keep track of the current line's available characters (DL) and maximum
; characters (DH), and print only whole words that will fit.
;
	mov	dl,[bx].CON_COLS	; DL = # available chars
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
h2b:	call	printEOL
	jmp	h2

h2c:	add	sp,cx			; deallocate the stack space
	pop	ax
	call	closeInput
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
	ASSERT	STRUCT,[bx],CMD
	cmp	dl,[bx].CON_COLS
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
	cmp	al,'\'			; we need to include any backslash
	jne	gw2			; in the word length, but we're not
	inc	dx			; printing it, so increase line length
	jmp	short gw3
gw2:	cmp	al,' '
	ja	gw1
	dec	si
gw3:	pop	ax
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
pr1:	lodsb
	cmp	al,'*'			; just skip asterisks for now
	je	pr8
	cmp	al,'\'			; lines ending with backslash
	jne	pr2			; trigger a single newline and
	call	skipSpace		; skip remaining whitespace
	pop	cx
	pop	ax
	ret
pr2:	call	printChar
pr8:	loop	pr1
pr9:	pop	cx
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
	call	printEOL
	DEFLBL	skipSpace,near
	call	printEOL
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
; countLine
;
; Call this once for each line of output generated by the current command.
; When the total number of lines (CMD_ROWS) equals the total number of rows
; (CON_ROWS), display a prompt if /P was specified.
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
DEFPROC	countLine
	push	bx
	mov	bx,ds:[PSP_HEAP]
	ASSERT	STRUCT,[bx],CMD
	ASSERT	<CMD_ROWS>,EQ,<CON_ROWS+1>
	mov	ax,word ptr [bx].CON_ROWS
	inc	ah
	cmp	ah,al
	jb	cl1
	cbw
cl1:	mov	[bx].CMD_ROWS,ah
	jb	cl9
	TESTSW	<'P'>
	jz	cl9
	PRINTF	<"Press a key to continue...">
	mov	ah,DOS_TTY_READ
	int	21h
	cmp	al,CHR_RETURN
	jne	cl8
	mov	[bx].CMD_ROWS,99
	PRINTF	<13,"%27c">,ax
	jmp	short cl9
cl8:	call	printCRLF
cl9:	pop	bx
	ret
ENDPROC	countLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printEOL
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
DEFPROC	printEOL
	mov	dl,dh			; reset available characters in DL
	DEFLBL	printCRLF,near
	PRINTF	<13,10>			; print CHR_RETURN, CHR_LINEFEED
	call	countLine
	ret
ENDPROC	printEOL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdKeys
;
; Inputs:
;	DI -> TOKENBUF
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
	lea	si,[bx].TBLKDEF
li2:	mov	cx,[si].BLK_NEXT
	jcxz	li9			; nothing left to parse
	mov	ds,cx
	ASSUME	DS:NOTHING
	mov	si,size TBLK
li3:	cmp	si,ds:[BLK_FREE]
	jae	li2			; advance to next block in chain
	lodsw
	test	ax,ax			; is there a label #?
	jz	li4			; no
	PRINTF	<"%5d">,ax
li4:	PRINTF	<CHR_TAB>
	call	writeStrCRLF
	jmp	li3
li9:	ret
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
;	DX -> one of: BAT_EXT, BAS_EXT, or cmdLoad
;
; Outputs:
;	Carry clear if successful, set if error (the main function doesn't
;	care whether this succeeds, but other callers do)
;
; Modifies:
;	Any except DX
;
DEFPROC	cmdLoad
	LOCVAR	lineLabel,word		; current line label
	LOCVAR	lineOffset,word		; current line offset
	LOCVAR	pTextLimit,word		; current text block limit
	LOCVAR	pLineBuf,word
	LOCVAR	pFileExt,word

	ENTER
	ASSUME	DS:DATA
	mov	[pFileExt],dx
	cmp	dx,offset cmdLoad	; called with an ambiguous name?
	jne	lf1a			; no
	mov	dx,offset PERIOD	; yes, so check it
	call	chkString
	jnc	lf1			; period exists, use filename as-is
	mov	dx,offset BAS_EXT
	call	addString

lf1:	call	openInput		; open the specified file
	jnc	lf1c
	cmp	si,di			; was there an extension?
	jne	lf1b			; yes, give up
	mov	dx,offset BAT_EXT
	call	addString
lf1a:	sub	di,di			; zap DI so that we don't try again
	jmp	lf1
lf1b:	call	openError		; report error (AX) opening file (SI)
	jmp	lf13

lf1c:	call	sizeInput		; set DX:AX to size of input file
	call	freeAllText		; free any pre-existing blocks
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
	lea	ax,[bx].LINEBUF
	mov	[pLineBuf],ax
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
	cmp	si,[pLineBuf]		; is current line already at LINEBUF?
	je	lf4y			; yes, we're done
	push	cx
	push	di
	push	es
	push	ds
	pop	es
	mov	di,[pLineBuf]
	rep	movsb
	pop	es
	pop	di
	pop	cx
lf4:	mov	si,[pLineBuf]		; DS:SI has been adjusted
;
; At DS:SI+CX, read (size LINEBUF - CX) more bytes.
;
	push	cx
	push	si
	add	si,cx
	mov	ax,size LINEBUF
	sub	ax,cx
	xchg	cx,ax
	call	readInput
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
	call	closeInput
	popf

lf13:	mov	dx,[pFileExt]		; restore DX for cmdFile calls
	LEAVE
	ret
ENDPROC	cmdLoad

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdNew
;
; Inputs:
;	DI -> TOKENBUF
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
;	DI -> TOKENBUF
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
; For GEN_BATCH files, the PC DOS 2.00 convention would be to replace every
; "%0", "%1", etc, with tokens from TOKENBUF.  That convention is unfeasible
; in BASIC-DOS because 1) that syntax doesn't jibe with BASIC, and 2) the
; values of "%0", "%1", etc can change at run-time, so a line containing any
; of those references would have to be reparsed and regenerated every time it
; was executed.
;
; That's not going to happen, so command-line arguments in BASIC-DOS need to
; be handled differently.  The good news is that BASIC never had a documented
; means of accessing command-line arguments, so we can do whatever makes the
; most sense.  And that seems to be creating a predefined string array
; (eg, _ARG$) filled with the tokens from TOKENBUF, along with a new function
; (eg, SHIFT) that shifts array values the same way the PC DOS 2.00 "SHIFT"
; command shifts arguments.
;
; And it makes sense to create that array at this point, so you can provide
; a fresh set of command-line arguments with every "RUN" invocation.
;
; Environment variables pose a similar challenge, and it's not clear that
; the first release of BASIC-DOS will support them -- but if it did, creating
; a similar predefined string array (eg, _ENV$) from an existing environment
; block would make the most sense.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	AL = GEN_BASIC or GEN_BATCH (if calling cmdRunFlags)
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
	jne	ru1			; BASIC programs
	call	freeAllVars		; always gets a fresh set of variables
ru1:	sub	si,si
	ASSERT	STRUCT,[bx],CMD
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
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdTime
	TESTSW	<'D'>			; /D present?
	jz	tm3			; no

	sub	ax,ax			; set ZF
	DOSUTIL	GETTIME
	push	cx			; CX:DX = current time
	push	dx
	call	printTime
	pop	dx
	pop	cx

	push	cx
	push	dx
	push	bx
	sub	dl,[bx].PREV_TIME.LOW.LOB
	jnb	tm1a
	add	dl,100			; adjust hundredths
	stc
tm1a:	sbb	dh,[bx].PREV_TIME.LOW.HIB
	jnb	tm1b
	add	dh,60			; adjust seconds
	stc
tm1b:	sbb	cl,[bx].PREV_TIME.HIW.LOB
	jnb	tm1c
	add	cl,60			; adjust minutes
	stc
tm1c:	sbb	ch,[bx].PREV_TIME.HIW.HIB
	jnb	tm1d
	add	ch,24			; adjust hours
tm1d:	mov	al,ch			; AL = hours
	mov	bl,cl			; BL = minutes
	mov	cl,dh			; CL = seconds, DL = hundredths
	PRINTF	<"Elapsed time is %2bu:%02bu:%02bu.%02bu",13,10>,ax,bx,cx,dx
	pop	bx
	pop	[bx].PREV_TIME.LOW
	pop	[bx].PREV_TIME.HIW
tm2:	ret

tm3:	mov	ax,offset promptTime
	call	getInput		; DS:SI -> string
	jc	tm2			; do nothing on empty string
	mov	ah,':'
	call	getValues
	mov	ah,DOS_MSC_SETTIME
	int	21h			; set the time
	test	al,al			; success?
	stc
	jz	promptTime		; yes, display new time and return
	PRINTF	<"Invalid time",13,10>
	cmp	[di].TOK_CNT,0		; did we process a command-line token?
	je	tm9			; yes
	jmp	cmdTime

	DEFLBL	promptTime,near
	jnc	tm8
	DOSUTIL	GETTIME			; GETTIME returns packed time
	mov	[bx].PREV_TIME.LOW,dx
	mov	[bx].PREV_TIME.HIW,cx

	DEFLBL	printTime,near
	mov	cl,dh			; CL = seconds, DL = hundredths
	pushf
	PRINTF	<"Current time is %2H:%02N:%02bu.%02bu",13,10>,ax,ax,cx,dx
	popf
	jz	tm8
	PRINTF	<"Enter new time: ">
	test	ax,ax			; clear CF and ZF
tm8:	mov	cx,0			; instead of retaining current values
	mov	dx,cx			; set all defaults to zero
tm9:	ret
ENDPROC	cmdTime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdType
;
; Read the specified file and write the contents to STDOUT.
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
DEFPROC	cmdType
	ASSERT	STRUCT,[bx],CMD
	mov	[bx].HDL_OUTPUT,STDOUT
	jmp	cmdCopy
ENDPROC	cmdType

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdVer
;
; Prints the BASIC-DOS version.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
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
	mov	al,ah			; AL = BASIC-DOS major version
	mov	dl,bh			; DL = BASIC-DOS minor version
	add	bl,'@'			; BL = BASIC-DOS revision
	test	cx,1			; CX bit 0 set if BASIC-DOS DEBUG ver
	mov	cx,offset VER_FINAL
	jz	ver1
	mov	cx,offset VER_DEBUG
ver1:	cmp	bl,'@'			; is revision a letter?
	ja	ver2			; yes
	mov	bl,' '			; no, change it to space
	inc	cx			; and skip the leading DEBUG space
ver2:	PRINTF	<13,10,"BASIC-DOS Version %bd.%02bd%c%ls",13,10,13,10>,ax,dx,bx,cx,cs
	ret
ENDPROC	cmdVer

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
; Open the specified output file; used by "COPY", "SAVE", etc.
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
	mov	dx,si			; DX -> filename
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	oo9
	ASSERT	STRUCT,ss:[bx],CMD
	mov	ss:[bx].HDL_OUTPUT,ax	; save file handle
oo9:	ret
ENDPROC	openOutput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; closeInput
;
; Close the default file handle.
;
; Inputs:
;	BX -> CMDHEAP
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	closeInput
	push	bx
	sub	ax,ax
	ASSERT	STRUCT,[bx],CMD
	xchg	ax,[bx].HDL_INPUT
	test	ax,ax
	jz	ci9
	xchg	bx,ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
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
; sizeInput
;
; Return the size of the input file.
;
; Inputs:
;	BX -> CMDHEAP
;
; Outputs:
;	If carry clear, DX:AX is the file size
;
; Modifies:
;	AX, DX
;
DEFPROC	sizeInput
	push	bx
	push	cx
	ASSERT	STRUCT,ss:[bx],CMD
	mov	bx,ss:[bx].HDL_INPUT	; BX = handle
	sub	cx,cx
	sub	dx,dx
	mov	ax,DOS_HDL_SEEKEND
	int	21h
	jc	si9
	push	ax
	push	dx
	sub	cx,cx
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	pop	dx
	pop	ax
si9:	pop	cx
	pop	bx
	ret
ENDPROC	sizeInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeOutput
;
; Write CX bytes to the default file frm the buffer at DS:SI.
;
; Inputs:
;	BX -> CMDHEAP
;	CX = number of bytes
;	DS:SI -> buffer
;
; Outputs:
;	If carry clear, AX = number of bytes written
;	If carry set, an error message was printed
;
; Modifies:
;	AX, DX
;
DEFPROC	writeOutput
	push	bx
	mov	dx,si
	ASSERT	STRUCT,[bx],CMD
	mov	bx,[bx].HDL_OUTPUT
	mov	ah,DOS_HDL_WRITE
	int	21h
	jnc	wo9
	PRINTF	<"Unable to write file",13,10,13,10>
	stc
wo9:	pop	bx
	ret
ENDPROC	writeOutput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; openHandle
;
; Open a handle for redirection.
;
; Inputs:
;	AL = 0 for read-only, 1 for write-only
;	DI -> TOKENBUF
;	BX = token offset
;
; Outputs:
;	BX = next token offset
;	If carry clear, AX is new handle; otherwise, AX is error
;
; Modifies:
;	AX, BX
;
DEFPROC	openHandle
	push	cx
	push	dx
	push	si
	sub	cx,cx
	add	bx,size TOKLET
	mov	si,[di].TOK_DATA[bx].TOKLET_OFF
	mov	cl,[di].TOK_DATA[bx].TOKLET_LEN
	mov	dx,si
	add	si,cx
	xchg	[si],ch			; null-terminate the token
	mov	ah,DOS_HDL_OPEN
	int	21h
	jnc	oh1
	xchg	si,dx
	call	openError		; report error (AX) opening file (SI)
	mov	si,dx
oh1:	mov	[si],ch			; restore the token separator
	pop	si
	pop	dx
	pop	cx
	ret
ENDPROC	openHandle

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
	call	openInput
	jc	ff9
	call	closeInput
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
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	AX = prompt function
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
	mov	dl,[bx].CMD_ARG
	call	getToken
	jnc	gi1
;
; No input was provided, and we don't prompt unless /P was specified.
;
	push	ax
	TESTSW	<'P'>
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
	lea	si,[bx].LINEBUF
	mov	word ptr [si].INP_MAX,12; max of 12 chars (including CR)
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
;	AH = default delimiter
;	SI -> DS-relative string data (CR-terminated)
;
; Outputs:
;	CH, CL, DH, DL
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	getValues
	push	bx
	xchg	bx,ax			; BH = default delimiter
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

gvs9:	pop	bx
	ret
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
