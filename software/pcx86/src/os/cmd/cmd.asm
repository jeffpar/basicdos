;
; BASIC-DOS Command Processor
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<allocText,freeAllText,genCode,freeAllCode,freeAllVars>
	IF DETOK
	EXTNEAR	<loadTokens,chkExt,getCwd,cmdDel>
	EXTNEAR	<openInput,openError,closeInput,readInput,seekInput>
	EXTNEAR	<openHandle,syncFiles>
	ENDIF
	EXTNEAR	<freeIdleVars,resetVars,runCode,findVar>
	EXTNEAR	<enterLine,editPrompt,chkProgram>
	EXTNEAR	<writeStrCRLF,saveChains,restoreChains,compactStrs>
	EXTNEAR	<saveMode,restoreMode,runTransient,transParas,resSum>
	EXTBYTE	<CMD_PATH,MSG_DRIVE>
	EXTWORD	<CMD_REFS,TRANS_SUM>
	EXTABS	<TOK_ERASE,TOK_DEL>
	EXTWORD	<KEYWORD_TOKENS>
	EXTSTR	<COM_EXT,EXE_EXT,BAS_EXT,BAT_EXT,DIR_DEF>
	EXTSTR	<VER_FINAL,VER_DEBUG,HELP_FILE,PIPE_NAME,FPU_NAME>
	EXTSTR	<FPU_HW,FPU_SW,FPU_OFF>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

DEFPROC	main
;
; If we're the copy that owns the shared code (ie, CS = DS), the loader has
; already put our heap and stack in RES_HEAP (see COMHEAP), so we just record
; what we need to reload the transient portion later (see runTransient in
; res.asm).
;
	mov	ax,cs
	mov	dx,ds
	cmp	ax,dx			; do we own the shared code?
	jne	m0z			; no
	call	resSum
	mov	[TRANS_SUM],ax		; record the checksum of the transient
	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'			; and the drive it was loaded from
	mov	[CMD_PATH],al
	mov	[MSG_DRIVE],al
m0z:	inc	cs:[CMD_REFS]
;
; Get the current session's screen dimensions (AL=cols, AH=rows).
;
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDIM
	mov	bx,STDOUT
	int	21h
	jnc	m0			; carry clear if BASIC-DOS

;	mov	dx,offset WRONG_OS
;	mov	ah,DOS_TTY_PRINT	; use DOS_TTY_PRINT instead of PRINTF
;	int	21h			; since PC DOS wouldn't understand that
;	ret
;	DEFSTR	WRONG_OS,<"BASIC-DOS required",13,10,'$'>

	mov	dx,(25 SHL 8) OR 80	; STDOUT doesn't support GETDIM; use 80x25

m0:	mov	bx,ds:[PSP_HEAP]
	DBGINIT	STRUCT,[bx],CMD
	mov	word ptr [bx].CON_COLS,dx
	mov	ax,word ptr ds:[PSP_PFT][STDIN]
	mov	word ptr [bx].SFH_STDIN,ax
	mov	ax,DOS_MSC_GETPCH
	int	21h			; DL = path char (fixed at boot)
	mov	[bx].PATH_CHAR,dl
;
; Install CTRLC handler.  DS = CS only for the first instance; additional
; instances of this processor will have their own DS but share a common CS.
;
	push	ds
	push	cs
	pop	ds
	mov	dx,offset ctrlc		; DS:DX -> CTRLC handler
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	int	21h
;
; Get the address of the FPU$ driver's function table (FPUTBL), which the
; code generator uses for all floating-point operations, along with the FPU
; type, so we can report how floating-point operations will be performed.
; If there's no FPU$ driver, FPU_TABLE remains zero, which also disables
; doubles (see getNextToken and genExpr).
;
	push	bx
	mov	si,offset FPU_OFF	; SI -> "support disabled"
	mov	dx,offset FPU_NAME	; DS:DX -> FPU_NAME
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	m0a
	xchg	bx,ax			; BX = handle
	mov	si,offset FPU_TABLE	; DS:SI -> FPU_TABLE
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETFPU
	int	21h			; DH = FPU type
	mov	ah,DOS_HDL_CLOSE
	int	21h
	mov	si,offset FPU_SW	; SI -> "software installed"
	test	dh,dh			; FPUTYPE_NONE?
	jz	m0a			; yes
	mov	si,offset FPU_HW	; SI -> "hardware installed"
m0a:	pop	bx
	pop	ds

	PRINTF	<"BASIC-DOS Command Processor",13,10,"Floating-point %ls",13,10,13,10>,si,cs
;
; NOTE: The original plan was to use Microsoft's MBF (Microsoft Binary Format)
; floating-point code from GW-BASIC, but BASIC-DOS will instead implement its
; own IEEE 754 64-bit floating-point support, so no MBF-related code (or MSLIB
; option) is used.  Until then, BASIC-DOS is just an "Integer BASIC".
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
	or	[bx].CMD_FLAGS,CMD_NOECHO
	cmp	ds:[PSP_CMDTAIL],0
	jne	m2			; use INPUT_BUF -> PSP_CMDTAIL

;
; Unlike PC DOS, every BAT file (like every BAS file) starts with ECHO OFF,
; including one run by a startup command, so an ECHO ON in one BAT file
; doesn't affect the next one.
;
m1:	or	[bx].CMD_FLAGS,CMD_NOECHO
	mov	[bx].CMD_ROWS,0
;
; If there's a program line to edit (see cmdAuto and cmdEdit), editPrompt
; displays it for editing instead of prompting for a command.
;
	mov	ax,[bx].EDIT_STATE	; AX = line # to edit, if any
	test	ax,ax
	jz	m1a
	call	editPrompt
	jc	m1			; input was processed
	jmp	short m2

m1a:	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'			; AL = current drive letter
	push	ds
	call	getCwd			; DS:SI -> current directory path
	jnc	m1b
	mov	byte ptr [si],0		; (no path if it's unavailable)
m1b:	PRINTF	<"%c:%c%s",CHR_GT>,cx,dx,si
	pop	ds

	lea	dx,[bx].INPUTBUF
	mov	[bx].INPUT_BUF,dx
	mov	ah,DOS_TTY_INPUT
	int	21h
	call	printCRLF

m2:	mov	si,[bx].INPUT_BUF
	mov	cl,[si].INP_CNT
	lea	si,[si].INP_DATA
	cmp	byte ptr [si],'@'	; skip any leading '@' (which
	jne	m3			; getNextLine also skips in BAT
	inc	si			; files and BASIC commands)
	dec	cx
m3:	call	enterLine		; is it a numbered program line?
	jnc	m1			; yes, and it's been processed
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
	mov	bx,ss:[PSP_HEAP]	; restore the original STD handles
	mov	ax,word ptr ss:[bx].SFH_STDIN
	mov	dx,0			; and close all non-STD handles
;
; parseDOS uses cleanUpTo instead, with the STD handles and open handles that
; existed before the command, so that a command run by a program doesn't undo
; the program's own redirection (eg, "PROG > FILE", where PROG runs another
; command).
;
; Inputs (for cleanUpTo):
;	AX = STDIN and STDOUT SFHs to restore (see getHandles)
;	DX = mask of non-STD handles to leave open (bit 0 for handle 5)
;
	DEFLBL	cleanUpTo,near
	pushf
	push	ss
	pop	ds
	push	ss
	pop	es
	push	ax
	mov	bx,5
cu1:	shr	dx,1			; leave this handle open?
	jc	cu2			; yes
	mov	ah,DOS_HDL_CLOSE
	int	21h
cu2:	inc	bx
	cmp	bx,size PSP_PFT
	jb	cu1
	pop	ax
	mov	word ptr ds:[PSP_PFT][STDIN],ax
	mov	bx,ds:[PSP_HEAP]
	call	syncFiles		; update OPEN files, too
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
	call	restoreMode		; restore the video mode, if necessary
;
; If any BAT or BAS files were running other BAT or BAS files, free all the
; chains they saved (ie, the callers' blocks), since the callers are aborted
; too.  We must do this before resetting the stack, which contains the frames.
;
ctc0:	mov	di,[bx].CMD_CHAINS
	test	di,di
	jz	ctc0a
	mov	al,1
	call	restoreChains
	jmp	ctc0
ctc0a:	lea	sp,[bx].STACK + size STACK
	call	compactStrs		; free any leftover temp strings
;
; If a pipeline was running (eg, "DIR | CASE"), wait for its session to end
; (it will have received the same CTRLC), so that it can't write anything
; more to the console after we've displayed a new prompt.
;
	mov	cl,SCB_NONE
	xchg	cl,[bx].SCB_NEXT
	cmp	cl,SCB_NONE
	je	ctc1
	DOSUTIL	WAITEND
ctc1:	call	freeAllCode
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
; The token is for a BASIC keyword (or the line contains another command; see
; pc2), so code generation is required.
;
pc1a:	mov	al,GEN_IMM
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
;
; However, if a word begins with a colon (eg, "DIR : PRINT 1"), then the line
; contains more than one command, so we let genCode run them (see genDOS).
;
pc2:	push	cx
	mov	cl,[di].TOK_CNT
	mov	ch,0
	push	bx
	lea	bx,[di].TOK_DATA
pc3:	push	bx
	mov	bx,[bx].TOKLET_OFF
	cmp	byte ptr [bx],':'	; does this word begin with a colon?
	pop	bx
	je	pc4			; yes
	add	bx,size TOKLET
	loop	pc3
pc4:	pop	bx
	pop	cx
	je	pc1a			; generate code for the line
	call	parseDOS		; DS:SI -> 1st token, CX = length

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
;	Carry set if a command failed (after reporting the error); EXIT_CODE
;	(ie, ERRORLEVEL) is 1 if so, the program's return code if an external
;	program ran, and 0 otherwise
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
; We start by saving the STD handles and open handles (on the stack, below
; BP), so that when we're done, cleanUpTo can restore them.
;
	push	bp
	push	ax
	push	dx
	call	getHandles		; AX = STD handles, DX = open handles
	mov	bp,sp
	xchg	dx,[bp]			; restore DX
	xchg	ax,[bp+2]		; restore AX
	mov	bp,bx			; use BP to access CMDHEAP instead
	ASSERT	STRUCT,[bp],CMD
	mov	al,[di].TOK_CNT
	ASSERT	Z,<test ah,ah>
	add	ax,ax
	add	ax,ax
	ASSERT	<size TOKLET>,EQ,4	; AX = end of TOKLETs
	sub	bx,bx			; BX = 0
	mov	[bp].CMD_ARG,bl		; initialize CMD_ARG
	mov	[bp].EXIT_CODE,bl	; and ERRORLEVEL (until a failure)
	mov	[bp].CMD_DEFER[0],bx	; no deferred command (yet)
	mov	[bp].HDL_INPIPE,bx	; no input pipe (yet)
	mov	[bp].HDL_OUTPIPE,bx	; and no output pipe (yet)
	mov	[bp].HDL_OUTFILE,bx	; or output file
	dec	bx			; BX = -1
	mov	[bp].HDL_INPUT,bx
	mov	[bp].HDL_OUTPUT,bx
	mov	[bp].SCB_NEXT,bl
	inc	bx			; BX = 0 again (offset of 1st TOKLET)
;
; Before running anything, verify that every symbol is valid ("|", ">", or
; ">>"), follows a command, and precedes another token; otherwise, it's a
; syntax error.  Since
; a redirection filename also ends a command, this rejects a pipe following
; redirected output (eg, "DIR > TEST | CASE"), where nothing would ever write
; to the pipe, leaving CASE waiting forever.
;
	sub	cx,cx			; CX = 0 (no command yet)
pd0:	cmp	bx,ax			; reached end of TOKLETs?
	jae	pd0c			; yes
	cmp	[di].TOK_DATA[bx].TOKLET_CLS,CLS_SYM
	je	pd0a
	inc	cx			; command (or argument) exists
	jmp	short pd0b
pd0a:	jcxz	pd0x			; no command before the symbol
	cmp	[di].TOK_DATA[bx].TOKLET_LEN,1
	jne	pd0x			; not a single-character symbol
	lea	dx,[bx + size TOKLET]
	cmp	dx,ax			; is there at least one more token?
	jae	pd0x			; no
	mov	si,[di].TOK_DATA[bx].TOKLET_OFF
	sub	cx,cx			; the next symbol requires a new command
	cmp	byte ptr [si],'|'	; pipe symbol?
	je	pd0b			; yes
	cmp	byte ptr [si],'>'	; output redirection symbol?
	jne	pd0x			; no
	mov	bx,dx			; BX -> redirection filename
;
; The tokenizer returns every symbol character as a separate token, so ">>"
; is a '>' token immediately followed by another '>' token.
;
	inc	si			; SI -> next character
	cmp	[di].TOK_DATA[bx].TOKLET_OFF,si
	jne	pd0d			; next token isn't adjacent
	cmp	byte ptr [si],'>'	; is it another '>' (ie, ">>")?
	jne	pd0d			; no
	add	bx,size TOKLET		; yes, BX -> redirection filename
	cmp	bx,ax			; is there a filename?
	jae	pd0x			; no
pd0d:	cmp	[di].TOK_DATA[bx].TOKLET_CLS,CLS_SYM
	je	pd0x			; filename can't be a symbol
pd0b:	add	bx,size TOKLET
	jmp	pd0
pd0x:	push	ax			; (pd9x expects end of TOKLETs on stack)
	jmp	pd9x
pd0c:	sub	bx,bx			; BX = 0 again

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
; Symbols have already been validated (see pd0), so we can process it now.
;
pd4:	push	bx
	mov	al,0
	mov	bx,[di].TOK_DATA[bx].TOKLET_OFF
	xchg	[bx],al			; null-terminated (AL = symbol)
	mov	dx,bx			; DX is offset of symbol
	pop	bx
	push	ax
	cmp	al,'|'			; pipe symbol?
	jne	pd4b			; no
	call	openPipe		; open pipe
	jc	pd4d			; bail on error
	mov	[bp].HDL_OUTPIPE,ax
	jmp	short pd4c

pd4b:	ASSERT	Z,<cmp al,CHR_GT>	; must be output redirection
	mov	al,1			; AL = 1 (create/truncate) for ">"
	push	si
	mov	si,dx
	inc	si			; SI -> character after the symbol
	cmp	[di].TOK_DATA[bx + size TOKLET].TOKLET_OFF,si
	jne	pd4f			; next token isn't adjacent
	cmp	byte ptr [si],'>'	; is it another '>' (ie, ">>")?
	jne	pd4f			; no
	inc	ax			; AL = 2 (append) for ">>"
	add	bx,size TOKLET		; and skip the 2nd '>'
pd4f:	pop	si
	call	openHandle		; open handle
	jc	pd4d			; bail on error
;
; Output redirection applies to any command on the line, but if this isn't the
; first command (eg, "DIR | CASE > TEST"), then it's either an external program
; that cmdFile must load with this handle as its STDOUT, or an internal command
; that we must run with this handle as our STDOUT (a deferred command will have
; its own STDOUT, so replacing ours now is harmless).
;
	cmp	[bp].CMD_ARG,0		; first command on line?
	je	pd4e			; yes
	mov	[bp].HDL_OUTFILE,ax	; no, save handle for cmdFile
	jmp	short pd4e

pd4c:	cmp	[bp].CMD_ARG,0		; first command on line?
	jne	pd4d			; no
pd4e:	push	bx
	xchg	bx,ax			; yes, put pipe/file handle in BX
	mov	al,ds:[PSP_PFT][bx]	; get its SFH
	mov	ds:[PSP_PFT][STDOUT],al	; and then replace the STDOUT SFH
	pop	bx

pd4d:	pop	ax
	jnc	pd5
	jmp	pd9			; bail on error

pd5:	jcxz	pd8			; no valid initial token
	push	ax
	push	dx			; save the symbol and its offset

	push	si
	lea	dx,[KEYWORD_TOKENS]
	DOSUTIL	TOKID			; CS:DX -> TOKTBL; identify token
	jc	pd5a
	mov	dx,cs:[si].CTD_FUNC
	cmp	ax,TOK_ERASE		; ERASE (which genErase handles if
	jne	pd5b			; it's erasing arrays) is otherwise DEL
	mov	ax,TOK_DEL
	mov	dx,offset cmdDel
	jmp	short pd5a		; (carry is clear)
;
; Any other BASIC keyword here (eg, CIRCLE, when its generator found no
; arguments; see genCommands) must be the name of a file to run instead.
;
pd5b:	cmp	ax,KEYWORD_BASIC	; BASIC keyword?
	cmc				; (carry set if so)
	jnc	pd5a			; no (and carry is clear)
	sub	ax,ax			; yes, so treat it like a file
	stc
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
	mov	[bp].HDL_OUTFILE,ax
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

;
; Use the deferred command's pipe handle, not HDL_INPIPE, which will have been
; zeroed if another symbol followed the last command (eg, "DIR | CASE > TEST").
;
pd9b:	sub	cx,cx			; CX = 0 for "truncating" write
	mov	bx,[bp].CMD_DEFER[8]	; BX = deferred command's pipe handle
	mov	ah,DOS_HDL_WRITE
	int	21h			; issue final write
	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the pipe
	mov	cl,SCB_NONE
	xchg	cl,[bp].SCB_NEXT
	cmp	cl,SCB_NONE
	je	pd9c			; (carry is clear)
	DOSUTIL	WAITEND
	clc

pd9c:	pop	cx			; discard end of TOKLETs
	pop	dx			; DX = handles to leave open
	pop	ax			; AX = STD handles to restore
	call	cleanUpTo		; BX -> CMDHEAP (carry preserved)
	jnc	pd9d
	mov	[bx].EXIT_CODE,1	; a failure sets ERRORLEVEL to 1
pd9d:	pop	bp
	ret

pd9x:	PRINTF	<"Syntax error",13,10,13,10>
	stc
	jmp	pd9c			; bail on error
ENDPROC	parseDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getHandles
;
; Inputs:
;	None
;
; Outputs:
;	AX = STDIN and STDOUT SFHs (from the PSP's PFT)
;	DX = mask of open non-STD handles (bit 0 for handle 5, and so on)
;
; Modifies:
;	AX, DX
;
DEFPROC	getHandles
	push	bx
	mov	bx,size PSP_PFT - 1
	sub	dx,dx
gh1:	shl	dx,1
	cmp	byte ptr ss:[PSP_PFT][bx],SFH_NONE
	je	gh2			; handle isn't open
	inc	dx			; handle is open
gh2:	dec	bx
	cmp	bx,5
	jae	gh1
	mov	ax,word ptr ss:[PSP_PFT][STDIN]
	pop	bx
	ret
ENDPROC	getHandles

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
cd9:	ret				; (carry set if the command failed)
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
	DEFLBL	cmdDone,near
	mov	ah,DOS_PSP_RETCODE
	int	21h
	ASSERT	STRUCT,[bp],CMD
	mov	word ptr [bp].EXIT_CODE,ax
	mov	dx,word ptr [bp].SFH_STDIN
	mov	word ptr ds:[PSP_PFT][STDIN],dx	; report to the original STDOUT
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
	mov	ax,64
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
; Not a drive letter, so presumably DS:SI contains a program name.  If a
; program is running it, compact its string pool first, since the pool is
; compacted only when it runs out of room, so it may be holding blocks full
; of garbage that the new program could use.
;
cf3:	call	compactStrs
	call	chkExt			; any extension in string at DS:SI?
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
	jnc	cf4x
	mov	dx,offset EXE_EXT
	call	chkString
	jnc	cf4x
	mov	dx,offset BAT_EXT
	call	chkString
	jnc	cf4b
	mov	dx,offset BAS_EXT
	call	chkString
	jnc	cf4b
	mov	si,di			; filename was none of the above
	mov	ax,ERR_INVALID		; so report an error
cf4a:	jmp	cf8
cf4x:	jmp	cf5
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
; When a BAS file is run from the command prompt, it remains loaded after it
; finishes running (replacing any program that was previously loaded), and
; so do its variables, just like MSBASIC, so that it can be LIST'ed, RUN again,
; etc.  Otherwise (eg, a BAT file, or a BAS file run by another BAT or BAS
; file), we free the file's blocks (eg, all text blocks) when it finishes
; running, but any variables set (ie, all var blocks) are allowed to remain in
; memory.
;
; Since a BAT or BAS file may be run by another BAT or BAS file, we save (and
; empty) the code and text chains first, so that the new file can't free the
; caller's code or text, and then we restore them when the new file finishes.
; This means a BAT file can run another BAT file and continue afterward, and
; any program that was LOAD'ed before a BAT file was run remains loaded.  If a
; program is running a BAS file, which always starts with a fresh set of
; variables, then the caller's function, var, string, and array chains are
; saved and restored as well.
;
; Note that if the execution is aborted (eg, critical error, CTRLC signal),
; the program remains loaded, available for LIST'ing, RUN'ing, etc, and the
; ctrlc handler frees the blocks of any callers (see restoreChains).
;
cf4b:	push	[bp].DATA_STATE[6]	; save the caller's READ position
	push	[bp].DATA_STATE[4]	; (see readData), which saveChains
	push	[bp].DATA_STATE[2]	; resets (see freeCache)
	push	[bp].DATA_STATE[0]
;
; Copy the command line (from the filename up to the end, which is a CR or a
; null, such as a redirection symbol that parseDOS replaced) to the stack as
; a string, followed by the # of words it occupies, for ARG$ (see strArg),
; which finds it via the CHAINS frame that saveChains creates.
;
	mov	bx,[bp].CMD_ARGPTR	; BX -> command line
	push	cx
	sub	cx,cx			; CX = length of command line
cf4t:	cmp	cl,127			; (limited to a PSP command tail)
	jae	cf4u
	mov	di,bx
	add	di,cx
	cmp	byte ptr [di],CHR_RETURN; end of command line?
	jbe	cf4u			; yes
	inc	cx
	jmp	cf4t
cf4u:	mov	ax,cx
	add	ax,2
	and	al,0FEh			; AX = # bytes in string (rounded up)
	pop	di			; DI = filespec length (from CX)
	sub	sp,ax			; allocate the string
	shr	ax,1
	push	ax			; save # words in the string
	push	si
	push	di
	mov	si,bx			; SI -> command line
	mov	di,sp
	add	di,6			; ES:DI -> string space
	mov	bx,di			; BX -> string (for saveChains)
	mov	al,cl
	stosb
	rep	movsb
	pop	cx			; CX = filespec length
	pop	si			; SI -> filespec
	mov	ax,11h			; save the code and text chains
	cmp	dx,offset BAS_EXT
	jne	cf4c
	mov	ah,1			; AH = 1 to keep a BAS file loaded
					; (see restoreChains)
	cmp	[bp].CBLKDEF.BDEF_NEXT,0; is a program running?
	je	cf4c			; no
	mov	ax,3Fh			; yes, so save its var chains, too
cf4c:	call	saveChains		; SP -> CHAINS frame
	mov	bx,bp			; BX -> CMDHEAP again
	call	cmdLoad			; DS:SI -> filespec (with length CX)
	jc	cf4e			; don't RUN if LOAD error
	mov	al,GEN_BASIC
	cmp	dx,offset BAS_EXT
	je	cf4d
	mov	al,GEN_BATCH
cf4d:	call	cmdRunFlags		; if cmdRun returns normally
	mov	di,sp
	mov	al,2			; AL = 2 to keep a BAS file loaded
	clc
	jmp	short cf4f
cf4e:	mov	di,sp			; free the file's blocks
	mov	al,0			; (eg, all text blocks) and
	stc				; report the LOAD error
cf4f:	pushf
	call	restoreChains		; restore the caller's chains
	popf
	mov	sp,di			; and remove the CHAINS frame
	pop	cx			; CX = # words in the command line
cf4g:	pop	ax			; remove the command line
	loop	cf4g			; (without affecting carry)
	pop	[bp].DATA_STATE[0]	; restore the caller's READ position
	pop	[bp].DATA_STATE[2]
	pop	[bp].DATA_STATE[4]
	pop	[bp].DATA_STATE[6]
	jmp	cf9a
;
; COM and EXE files must be loaded via either DOS_PSP_EXEC or DOS_UTL_LOAD.
; If no BAT or BAS file is running, we first free the var blocks (if they're
; not being used), so that more (and less fragmented) memory is available.
;
cf5:	cmp	[bp].CBLKDEF.BDEF_NEXT,0; is a program running?
	jne	cf5x			; yes
	push	cx
	push	si
	call	freeIdleVars
	pop	si
	pop	cx
cf5x:	DOSUTIL	STRLEN			; AX = length of filename in LINEBUF
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
;
; If there are no pipes, and the transient portion can be discarded, let
; runTransient load and run the program (see res.asm).
;
	mov	ax,[bp].HDL_INPIPE
	or	ax,[bp].HDL_OUTPIPE
	jnz	cf5f
	call	transParas
	test	ax,ax
	jz	cf5f
	call	runTransient
	jc	cf5e
	call	cmdDone
	jmp	short cf5d
cf5f:	mov	ax,DOS_PSP_EXEC1
	int	21h			; load program at DS:DX
	jc	cf5e
;
; Unfortunately, at this late stage, if a pipe exists, we must defer the EXEC.
;
	cmp	[bp].HDL_OUTPIPE,0
	je	cf5c
	mov	[bp].CMD_DEFER[0],-1	; set deferred EXEC code (-1)
	mov	ax,[bp].HDL_OUTPIPE
	mov	[bp].CMD_DEFER[8],ax	; save pipe handle for parseDOS
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
	jnz	cf7a
	or	bx,[bp].HDL_OUTFILE	; output redirected to a file instead?
	jz	cf7b			; no
cf7a:	mov	al,ds:[PSP_PFT][bx]
cf7b:	stosb				; SPB_SFHOUT
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
	jmp	short cf9a		; (carry is set)
cf9:	clc
cf9a:	pop	bp
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
;	AX, CX, SI
;
; Notes:
;	If the token is the name of a string variable (eg, "DIR D$"), the
;	variable's value is used instead, and quotes are removed from a
;	quoted token (eg, "TEST$"); see chkStrVar.
;
DEFPROC	getFileName
	push	cx
	push	si			; save the default filespec
	call	getToken		; DL = 1st non-switch argument
	jc	gf0
	call	chkStrVar		; is the token a string variable?
	jnc	gf1			; no, or it has a value
gf0:	pop	si			; use the default filespec
	pop	cx
	jcxz	gf9			; bail if no default was provided
	push	cs			; assumes default is in CS segment
	pop	ds
	jmp	short gf2
gf1:	pop	ax			; discard the default filespec
	pop	ax
	mov	ax,64			; DS:SI -> token, CX = length
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
; chkStrVar
;
; If a token is quoted (eg, "TEST$"), remove the quotes; otherwise, if it's a
; string variable name (a letter, followed by letters or digits, ending with
; '$'), replace it with the variable's value (a variable that doesn't exist
; is empty, as in BASIC).  Any other token is left alone.
;
; Inputs:
;	SS:SI -> token, CX = length
;
; Outputs:
;	DS:SI -> filename, CX = length, carry clear; or carry set (and DS = SS)
;	if the filename is empty (eg, "" or an empty string variable)
;
; Modifies:
;	AX, CX, SI, DS
;
DEFPROC	chkStrVar
	cmp	byte ptr [si],'"'	; quoted?
	jne	csv1			; no
	inc	si			; yes, so remove the quotes
	dec	cx
	jcxz	csv6			; it's empty
	push	si
	add	si,cx
	cmp	byte ptr [si-1],'"'	; closing quote?
	pop	si
	jne	csv0			; no
	dec	cx
	jcxz	csv6			; it's empty
csv0:	clc
	ret

csv1:	push	si
	push	cx
	cmp	cx,2			; long enough for a string variable?
	jb	csv7			; no
	lodsb
	and	al,0DFh
	sub	al,'A'
	cmp	al,26			; does it start with a letter?
	jae	csv7			; no
	sub	cx,2			; CX = # of remaining name characters
	jcxz	csv3
csv2:	lodsb
	cmp	al,'0'
	jb	csv7
	cmp	al,'9'			; digit?
	jbe	csv2a			; yes
	and	al,0DFh
	sub	al,'A'
	cmp	al,26			; letter?
	jae	csv7			; no
csv2a:	loop	csv2
csv3:	cmp	byte ptr [si],'$'	; does it end with '$'?
	jne	csv7			; no
	pop	cx
	pop	si
	push	dx
	dec	cx			; CX = length of name (without '$')
	mov	ah,VAR_STR
	call	findVar			; DX:SI -> variable data
	jc	csv5			; no such variable, so it's empty
	mov	ds,dx
	lds	si,[si]			; DS:SI -> value (or null)
	mov	cx,ds
	jcxz	csv5			; the value is empty
	lodsb
	mov	ah,0
	xchg	cx,ax			; CX = length
	pop	dx
	clc
	ret
csv5:	pop	dx
csv6:	push	ss
	pop	ds
	stc
	ret
csv7:	pop	cx			; not a variable, so leave it alone
	pop	si
	clc
	ret
ENDPROC	chkStrVar

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
	jc	dt8			; do nothing on empty string
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
	jnz	dt2			; no
	stc				; (and ZF is set)
	call	promptDate		; display the new date
	jmp	short dt8
dt2:	PRINTF	<"Invalid date",13,10>
	cmp	[di].TOK_CNT,0		; did we process a command-line token?
	stc
	je	dt9			; yes (so report an error)
	jmp	cmdDate
dt8:	clc
	ret

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
	dec	cs:[CMD_REFS]
	int	20h			; terminates the current process
	inc	cs:[CMD_REFS]
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
	sub	cx,cx			; no, so list all HELP entries
;
; Look up the second token (DS:SI) with length CX in the HELP file.
;
	DEFLBL	doHelp,near
	push	si
	push	cx
	push	ds
	push	cs
	pop	ds
	mov	si,offset HELP_FILE	; DS:SI -> filename
	call	openInput
	pop	ds
	pop	cx
	pop	si
	jc	h3
	push	cx
	call	findHelp		; DX = offset, CX = length
	pop	ax
	jnc	h1
	push	ax
	call	closeInput
	pop	ax
	test	ax,ax			; were we just listing entries?
	jz	h9			; yes
	jmp	short h3
h1:	push	cx
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
	stc
	ret
h9:	ret
ENDPROC	cmdHelp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findHelp
;
; Searches the (open) HELP file for the entry whose first word matches the
; specified name (in any case).  Entries are separated by blank lines, and
; the matching word must be followed by a character other than a letter or
; digit, so "MID" and "MID$" both match "MID$(...)", while "DEF" doesn't
; match "DEFINT".
;
; If the name is empty, the first word of every entry is listed instead (only
; letters, digits, '$', and '%' are printed, so an entry that begins with any
; other character, like '*', is omitted).
;
; Inputs:
;	DS:SI -> name
;	CX = length of name (zero to list all entries)
;
; Outputs:
;	If carry clear, DX = offset of entry, CX = length of entry
;
; Modifies:
;	AX, CX, DX, SI, DI
;
HELP_BUFLEN	equ	128

DEFPROC	findHelp
	push	bp
	mov	bp,sp
	push	si			; [bp-2] -> name
	push	cx			; [bp-4] = length of name
	mov	ax,2
	push	ax			; [bp-6] = # consecutive LINEFEEDs
	push	ax			; [bp-8] = offset of current entry
	sub	ax,ax
	push	ax			; [bp-10] = column (if listing)
	sub	sp,HELP_BUFLEN
	sub	di,di			; DI = offset of next character
	mov	dx,-1			; DX = offset of matching entry (none)
	mov	al,dl			; AL = # name chars matched (-1 if none)
fh1:	push	ax
	push	dx
	mov	si,sp
	add	si,4			; DS:SI -> buffer
	mov	cx,HELP_BUFLEN
	call	readInput		; AX = # bytes read
	xchg	cx,ax			; CX = # bytes read
	pop	dx
	pop	ax
	jc	fh1a
	jcxz	fh1a			; end of file
	jmp	short fh2
fh1a:	jmp	fh8
fh2:	mov	ah,[si]			; AH = next character
	inc	si
	cmp	ah,CHR_RETURN
	je	fh2a
	cmp	ah,CHR_LINEFEED
	jne	fh3
	inc	word ptr [bp-6]
fh2a:	cmp	byte ptr [bp-4],0	; listing entries?
	je	fh4			; yes
	cmp	al,[bp-4]		; does the line end a matching name?
	mov	al,-1
	je	fh4a			; yes
	jmp	short fh7
fh3:	cmp	word ptr [bp-6],2	; does an entry start here?
	mov	word ptr [bp-6],0
	jb	fh4			; no
	cmp	dx,-1			; did we already find a match?
	jne	fh9			; yes, so this is the end of it
	mov	[bp-8],di
	mov	al,0			; start matching
fh4:	cmp	al,-1			; still matching (or listing)?
	je	fh7			; no
	cmp	byte ptr [bp-4],0	; listing entries?
	je	fh11			; yes
	cmp	al,[bp-4]		; entire name matched?
	jb	fh5			; not yet
	mov	al,-1
	cmp	ah,'0'			; next character must not be
	jb	fh4a			; a digit or letter
	cmp	ah,'9'
	jbe	fh7
	cmp	ah,'A'
	jb	fh4a
	cmp	ah,'Z'
	jbe	fh7
fh4a:	mov	dx,[bp-8]		; DX = offset of matching entry
	jmp	short fh7
fh5:	push	bx
	mov	bl,al
	mov	bh,0
	add	bx,[bp-2]
	mov	bl,[bx]			; BL = next character of name
	cmp	bl,'a'
	jb	fh5a
	cmp	bl,'z'
	ja	fh5a
	sub	bl,20h			; convert lower-case to upper-case
fh5a:	cmp	bl,ah
	pop	bx
	je	fh6
	mov	al,-1			; mismatch
	jmp	short fh7
fh6:	inc	ax
fh7:	inc	di
	loop	fh7a
	jmp	fh1
fh7a:	jmp	fh2
fh8:	cmp	byte ptr [bp-10],0	; end of file; is a listing line open?
	je	fh8a			; no
	push	dx
	call	printCRLF
	pop	dx
fh8a:	cmp	dx,-1			; was there a match?
	stc
	je	fh10			; no
fh9:	mov	cx,di
	sub	cx,dx			; CX = length of entry (carry clear)
fh10:	mov	sp,bp
	pop	bp
	ret
;
; Listing: print AH if it's part of the entry's first word (AL = # chars
; printed so far); otherwise, end the word by padding it to the next column.
;
fh11:	cmp	ah,'$'
	je	fh12
	cmp	ah,'%'
	je	fh12
	cmp	ah,'0'
	jb	fh13
	cmp	ah,'9'
	jbe	fh12
	cmp	ah,'A'
	jb	fh13
	cmp	ah,'Z'
	ja	fh13
fh12:	push	ax
	mov	al,ah
	call	printChar
	pop	ax
	inc	ax
	inc	byte ptr [bp-10]
	jmp	fh7
fh13:	cmp	al,0			; anything printed?
	mov	al,-1
	je	fh15			; no
fh14:	push	ax
	mov	al,' '
	call	printChar
	pop	ax
	inc	byte ptr [bp-10]
	test	byte ptr [bp-10],7	; at the next column yet?
	jnz	fh14			; no
	mov	ah,[bp-10]
	add	ah,16
	cmp	ah,[bx].CON_COLS	; is there room for another name?
	jb	fh15			; yes
	push	ax
	push	cx
	push	dx
	call	printCRLF
	pop	dx
	pop	cx
	pop	ax
	mov	byte ptr [bp-10],0
fh15:	jmp	fh7
ENDPROC	findHelp

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
	LOCVAR	lineTerm,byte		; previous line terminator
	LOCVAR	pFileExt,word

	ENTER
	ASSUME	DS:DATA
	mov	[pFileExt],dx
	mov	[lineTerm],0
	cmp	dx,offset cmdLoad	; called with an ambiguous name?
	jne	lf1a			; no
;
; TODO: LOAD inside a running BAS or BAT file would replace the running file's
; own text (and code), so for now, it's an error.
;
	call	chkProgram		; is a program running?
	jnc	lf0			; no
	jmp	lf13
lf0:	call	chkExt			; check the filename
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

lf1c:	call	freeAllText		; free any pre-existing blocks
	call	allocText		; ES:DI -> new text block
	jc	lf4y
	mov	ax,es:[BLK_SIZE]
	mov	[pTextLimit],ax
;
; For every complete line at DS:SI, determine the line label (if any), and
; then add the label # (2 bytes), line length (1 byte), and line contents
; (not including any leading space or terminating CR/LF) to the text block.
;
; Lines may be terminated by either CR/LF or LF alone.  Either CR or LF ends
; a line, and whenever a line ends with CR, a LINEFEED immediately following
; it is skipped; lineTerm remembers the terminator, in case the LINEFEED isn't
; read until the next readInput.
;
	lea	ax,[bx].LINEBUF
	mov	[pLineBuf],ax
	sub	cx,cx			; DS:SI contains zero bytes now

lf3:	jcxz	lf4
	cmp	[lineTerm],CHR_RETURN	; did the previous line end with CR?
	jne	lf3c			; no
	mov	[lineTerm],0
	cmp	byte ptr [si],CHR_LINEFEED
	jne	lf3c
	inc	si			; skip LINEFEED from the previous line
	dec	cx
	jmp	lf3

lf3c:	push	cx
	mov	dx,si			; save SI
lf3a:	lodsb
	cmp	al,CHR_RETURN
	je	lf3b
	cmp	al,CHR_LINEFEED
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
lf5:	cmp	byte ptr [si],0FEh	; MSBASIC protected (FEh) files aren't
	IF DETOK			; supported, but tokenized (FFh) files
	jb	lf5a			; are (see loadTokens)
	je	lf10
	call	loadTokens
	jc	lf10
	jmp	lf12
	ELSE
	jae	lf10			; (unless DETOK is zero)
	ENDIF
lf5a:	mov	[lineOffset],si
	push	dx
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

lf7:	dec	dx			; back up to the line terminator
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
	push	si
	call	allocText		; ES:DI -> new text block
	pop	si
	pop	cx
	jc	lf11			; unable to allocate enough memory
	mov	ax,es:[BLK_SIZE]
	mov	[pTextLimit],ax

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
	mov	[lineTerm],al		; remember terminator (CR or LF)
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
	clc
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
	sub	si,si
	ASSERT	STRUCT,[bx],CMD
	cmp	al,GEN_BASIC
	jne	ru9			; BASIC programs
	call	resetVars		; always gets a fresh set of variables
;
; BASIC programs also get their video mode restored when they end (see
; saveMode); if they're aborted instead, ctrlc takes care of it.
;
	push	ax
	call	saveMode		; AX = 1 if the mode was saved
	xchg	dx,ax
	pop	ax
	push	dx
	sub	si,si
	call	runCode			; (see runCache)
	pop	dx
	pushf
	test	dx,dx			; did we save the mode?
	jz	ru8			; no
	call	restoreMode		; yes, so restore it
ru8:	popf
	ret
ru9:	jmp	genCode
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
	jmp	short tm7

tm3:	mov	ax,offset promptTime
	call	getInput		; DS:SI -> string
	jc	tm7			; do nothing on empty string
	mov	ah,':'
	call	getValues
	mov	ah,DOS_MSC_SETTIME
	int	21h			; set the time
	test	al,al			; success?
	jnz	tm4			; no
	stc				; (and ZF is set)
	call	promptTime		; display the new time
	jmp	short tm7
tm4:	PRINTF	<"Invalid time",13,10>
	cmp	[di].TOK_CNT,0		; did we process a command-line token?
	stc
	je	tm9			; yes (so report an error)
	jmp	cmdTime
tm7:	clc
	ret

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

	end
