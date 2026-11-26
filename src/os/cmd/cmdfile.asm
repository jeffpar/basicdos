;
; BASIC-DOS Command Processor: Program Files
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; cmdFile, which runs a program, BAT, or BAS file for cmd.asm, and its helper
; functions; it's separate only because cmd.asm has no symbol space for it.
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	IF DETOK
	EXTNEAR	<findProgram,openError,addPipe,pipeStages>
	ENDIF
	EXTNEAR	<freeAllVars,cmdLoad,freeIdleVars,findVar,saveChains>
	EXTNEAR	<restoreChains,compactStrs,runTransient,transParas>
	EXTNEAR	<showCursor,hideCursor,buildEnv,freeEnv,startV86>
	EXTNEAR	<chkString,cmdDone,cmdNew,cmdRunFlags,cmdStart,getToken>
	EXTSTR	<COM_EXT,EXE_EXT,BAS_EXT,BAT_EXT>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

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
	mov	dl,[si]
	sub	dl,'A'			; DL = drive number
	mov	ah,DOS_DSK_SETDRV
	int	21h			; attempt to set the drive number in DL
	mov	ax,ERR_BADDRIVE		; (for openError, if DL is invalid)
	jc	cf4a
	jmp	cf9
;
; Not a drive letter, so presumably DS:SI contains a program name.  If a
; program is running it, compact its string pool first, since the pool is
; compacted only when it runs out of room, so it may be holding blocks full
; of garbage that the new program could use.
;
cf3:	call	compactStrs
	mov	dx,offset COM_EXT
	call	findProgram		; find the program (see PATH$)
	jc	cf4a
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
cf4y:	mov	ax,ERR_INVALID		; so report an error
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
; finishes running (replacing any program that was previously loaded, which
; is freed first, along with its variables, as NEW does), and so do its
; variables, just like MSBASIC, so that it can be LIST'ed, RUN again, etc.
; Otherwise (eg, a BAT file, or a BAS file run by another BAT or BAS file), we
; free the file's blocks (eg, all text blocks) when it finishes running, but
; any variables set (ie, all var blocks) are allowed to remain in memory.
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
;
; If a program is running, its code is still being generated (see genMore),
; so we also save its code generator's state (from DEF_PARMS through DEFVARS),
; which the file's genCode changes, and restore it when the file finishes.
;
GEN_WORDS	equ	(DEFVARS + 26 - DEF_PARMS) / 2
;
; A BAT or BAS file runs in this session, which runs the pipeline's first
; command, so it can't be the target of a pipe; and when it's the first
; command, it must wait until the other commands are running, or it could
; fill the pipe with nothing reading it, so we defer it, as parseDOS defers
; an internal command, and parseDOS calls us again (with no input pipe) once
; they're running.
;
cf4b:	cmp	[bp].HDL_INPIPE,0	; is the file a pipe's target?
	jne	cf4y			; yes, so it's an error
	mov	ax,[bp].HDL_OUTPIPE
	test	ax,ax			; is the file's output a pipe?
	jz	cf4i			; no
	push	ax
	lea	di,[bp].CMD_DEFER
	mov	ax,2			; AX = ID for a deferred command
	stosw				; (see chkSwitches)
	mov	ax,offset cmdFile
	stosw
	mov	ax,[bp].CMD_ARGPTR
	stosw
	mov	ax,[bp].CMD_ARGLEN
	stosw
	pop	ax
	stosw				; and the pipe handle
	jmp	cf9

cf4i:	sub	sp,GEN_WORDS * 2
	push	cx
	push	si
	lea	si,[bp].DEF_PARMS
	mov	di,sp
	add	di,4			; ES:DI -> space for the state
	mov	cx,GEN_WORDS
	rep	movsw
	pop	si
	pop	cx
	push	[bp].DATA_STATE.DATA_ITEM	; save the caller's READ position
	push	[bp].DATA_STATE.DATA_END	; (see readData), which saveChains
	push	[bp].DATA_STATE.DATA_SEG	; resets (see freeCache)
	push	[bp].DATA_STATE.DATA_OFF
;
; Copy the command line (from the filename up to the end, which is a CR or a
; null, such as a redirection symbol that parseDOS replaced), with any string
; variables replaced (see copyArgs), to the stack as a string, followed by the
; # of words it occupies, for ARG$ (see strArg), which finds it via the CHAINS
; frame that saveChains creates.  The copy is made in the second half of
; LINEBUF first, since the filespec occupies the first half.
;
	push	cx
	push	si
	mov	si,[bp].CMD_ARGPTR	; SI -> command line
	lea	di,[bp].LINEBUF+128
	mov	bx,di			; BX -> copy of command line
	call	copyArgs		; CX = length of copy
	pop	si
	mov	ax,cx
	add	ax,2
	and	al,0FEh			; AX = # bytes in string (rounded up)
	pop	di			; DI = filespec length (from CX)
	sub	sp,ax			; allocate the string
	shr	ax,1
	push	ax			; save # words in the string
	push	si
	push	di
	mov	si,bx			; SI -> copy of command line
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
	cmp	[bp].CBLKDEF.BDEF_NEXT,0; is a program running?
	mov	al,3Fh			; (if so, save its var chains, too)
	jne	cf4c			; yes
;
; A BAS file run from the prompt replaces the loaded program, so we free that
; program and its variables now, as NEW does, rather than after the file runs,
; so that the file runs with the same memory every time (eg, running it again
; can't run out of memory where the first run didn't).
;
	push	cx
	push	si
	call	cmdNew
	pop	si
	pop	cx
	mov	ax,111h			; AH = 1 to keep a BAS file loaded
					; (see restoreChains)
cf4c:	call	saveChains		; SP -> CHAINS frame
	mov	bx,bp			; BX -> CMDHEAP again
	call	cmdLoad			; DS:SI -> filespec (with length CX)
	jc	cf4e			; don't RUN if LOAD error
	mov	al,GEN_BASIC
	cmp	dx,offset BAS_EXT
	je	cf4d
	mov	al,GEN_BATCH
cf4d:	call	cmdRunFlags		; carry set if the file had a syntax
	mov	di,sp			; error (so ERRORLEVEL becomes 1)
	mov	al,2			; AL = 2 to keep a BAS file loaded
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
	pop	[bp].DATA_STATE.DATA_OFF	; restore the caller's READ position
	pop	[bp].DATA_STATE.DATA_SEG
	pop	[bp].DATA_STATE.DATA_END
	pop	[bp].DATA_STATE.DATA_ITEM
;
; A file's types (DEFVARS) remain in effect at the prompt afterward (see
; genCode), so we restore DEFVARS only if a program (other than an immediate
; line, which has been generated already) is running.
;
	lahf				; AH = flags (carry set if error)
	mov	si,sp			; SI -> saved state
	push	ss
	pop	es
	lea	di,[bp].DEF_PARMS
	mov	cx,(DEFVARS - DEF_PARMS) / 2
	cmp	[bp].CBLKDEF.BDEF_NEXT,0; was a program running?
	je	cf4h			; no
	test	byte ptr [si+(GEN_FLAGS - DEF_PARMS)],GEN_IMM
	jnz	cf4h			; yes, but only an immediate line
	mov	cl,GEN_WORDS
cf4h:	rep	movsw
	add	sp,GEN_WORDS * 2
	sahf
	jmp	cf9a
;
; COM and EXE files must be loaded via either DOS_PSP_EXEC or DOS_UTL_LOAD.
; If no BAT or BAS file is running, we first free the var blocks (if they're
; not being used), so that more (and less fragmented) memory is available.
;
cf5:	call	showCursor		; (if a BAS program hid it)
	cmp	[bp].CBLKDEF.BDEF_NEXT,0; is a program running?
	jne	cf5x			; yes
	push	cx
	push	si
	call	freeIdleVars
	pop	si
	pop	cx
cf5x:	DOSUTIL	STRLEN			; AX = length of filename in LINEBUF
	mov	dx,si			; DS:DX -> filename
	mov	si,[bp].CMD_ARGPTR	; recover original filename
	add	si,[bp].CMD_ARGLEN	; DS:SI -> tail after original filename
	cmp	[bp].CMD_ARG,0		; is this the first command?
	jne	cf6			; no, use DOS_UTL_LOAD instead
	call	buildEnv		; update EPB_ENVSEG's environment
	lea	bx,[bp].EXECDATA
	mov	di,dx			; we used to set DI to PSP_CMDTAIL
	add	di,ax			; but the filename is now in LINEBUF
	inc	di			; so use the remaining space in LINEBUF
	push	di
	mov	[bx].EPB_CMDTAIL._OFF,di
	mov	[bx].EPB_CMDTAIL._SEG,es
	inc	di			; use our tail space to build new tail
	call	copyArgs		; CX = length of tail
	mov	al,CHR_RETURN		; regardless how the command line ends,
	stosb				; terminate the tail with CHR_RETURN
	pop	di
	mov	[di],cl			; set the cmd tail length
	mov	[bx].EPB_FCB1._OFF,-1	; let the EXEC function build the FCBs
;
; If there are no pipes, and the transient portion can be discarded, let
; runTransient load and run the program (see res.asm).
;
cf5a:	mov	ax,[bp].HDL_INPIPE
	or	ax,[bp].HDL_OUTPIPE
	jnz	cf5f
	call	transParas
	test	ax,ax
	jz	cf5f
	call	runTransient
	jc	cf5e
	call	cmdDone
	jmp	short cf5d
cf5f:	call	pipeStages		; CH = commands that follow
	mov	ax,DOS_PSP_EXEC6
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

cf5e:	jmp	cf10			; (out of line, for the short jumps)
;
; Use DOS_UTL_LOAD to load the external program into a background session.
;
cf6:	mov	di,dx			; DI -> filename in LINEBUF
	push	di
	add	di,ax			; DI -> null
	call	copyArgs
	mov	al,0			; regardless how the tail ends,
	stosb				; null-terminate the new command line
	pop	si			; SI -> new command line
cf6a:	sub	sp,size SPB
	mov	di,sp			; ES:DI -> SPB on stack
	sub	ax,ax
	stosw				; SPB_ENVSEG <- 0
	mov	ax,si
	stosw				; SPB_CMDLINE._OFF
	mov	ax,ds
	stosw				; SPB_CMDLINE._SEG
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
	call	pipeStages		; CH = commands that follow
	DOSUTIL	LOAD,0			; load CMDLINE into an SCB
	lea	sp,[bx + size SPB]	; clean up the stack
	jc	cf11
	call	addPipe			; record the session
	DOSUTIL	START			; start the SCB # specified in CL
	jmp	short cf9
;
; In a pipeline, our STDOUT may be a pipe by now, so make sure the error is
; reported to the original STDOUT.
;
cf8:	mov	dx,word ptr [bp].SFH_STDIN
	mov	word ptr ds:[PSP_PFT][STDIN],dx
	call	openError		; report error (AX) opening file (SI)
	jmp	short cf9a		; (carry is set)
cf9:	clc
cf9a:	pushf
	call	hideCursor		; (if a running BAS program hid it)
	popf
	pop	bp
	ret
;
; If a program couldn't be loaded for lack of memory, and freeVarsRetry
; freed some, try again: the tail and environment (cf10, from cf5e), or the
; command line (cf11), are already built.
;
cf10:	call	freeVarsRetry
	jc	cf10a
	lea	bx,[bp].EXECDATA
	jmp	cf5a
cf10a:	call	freeEnv			; (the program never ran)
	mov	si,dx
;
; Protected mode can't run a real-mode program, but a V86 machine can, so
; startV86 (which isn't part of the core; see genUpper) runs it in one, if
; it's loaded and there can be one.
;
	cmp	ax,ERR_BADMODE		; a real-mode program?
	jne	cf8			; no
	mov	dx,offset startV86
	cmp	dx,ds:[PSP_CODESIZE]	; is startV86 loaded?
	jae	cf8			; no
	call	dx			; (it reports any error)
	jmp	cf9a
cf11:	call	freeVarsRetry
	jc	cf8
	jmp	cf6a
ENDPROC	cmdFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeVarsRetry
;
; When a program can't be loaded for lack of memory, and no BAT or BAS file
; is running (it would need its variables), frees all the variables, as CLEAR
; does, so that cmdFile can try again.  Since nothing is freed if there are
; no variables, a second failure is reported.
;
; Inputs:
;	AX = error code
;	BP -> CMDHEAP
;
; Outputs:
;	Carry clear if variables were freed, set if not
;
; Modifies:
;	CX
;
DEFPROC	freeVarsRetry
	cmp	ax,ERR_NOMEMORY		; not enough memory?
	jne	fvr8			; no
	cmp	[bp].CBLKDEF.BDEF_NEXT,0; is a program running?
	jne	fvr8			; yes
	mov	cx,[bp].FBLKDEF.BDEF_NEXT
	or	cx,[bp].VBLKDEF.BDEF_NEXT
	or	cx,[bp].ABLKDEF.BDEF_NEXT
	jz	fvr8			; there are no variables to free
	push	si
	call	freeAllVars
	pop	si
	clc
	ret
fvr8:	stc
	ret
ENDPROC	freeVarsRetry

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
	mov	ax,127			; DS:SI -> token, CX = length (up to
	cmp	cx,ax			; 127, so that the copy and its null fit
	jbe	gf2			; in half of LINEBUF; eg, "COPY A+B+C D")
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
; is empty, as in BASIC).  Any other token, including a function name (eg,
; PATH$, so that "COMMAND /C PRINT PATH$" prints the new COMMAND's PATH$),
; is left alone.
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
	push	si			; (in case it's a function)
	push	dx
	dec	cx			; CX = length of name (without '$')
	mov	ah,VAR_STR
	call	findVar			; DX:SI -> variable data
	jc	csv5			; no such variable, so it's empty
	cmp	ah,VAR_STR		; a string variable (not a function)?
	jne	csv4			; no
	mov	ds,dx
	lds	si,[si]			; DS:SI -> value (or null)
	mov	cx,ds
	jcxz	csv5			; the value is empty
	lodsb
	mov	ah,0
	xchg	cx,ax			; CX = length
	pop	dx
	pop	ax			; (carry is clear)
	ret
csv4:	pop	dx
	inc	cx			; CX = length of the token
	jmp	short csv7a
csv5:	pop	dx
	pop	ax
csv6:	push	ss
	pop	ds
	stc
	ret
csv7:	pop	cx			; not a variable, so leave it alone
csv7a:	pop	si
	clc
	ret
ENDPROC	chkStrVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copyArgs
;
; Copies the rest of the current token (eg, the program name) and the
; arguments that follow, up to the CR or null that ends them, for an external
; command.  As for DOS commands, an unquoted argument that's a string variable
; name is replaced with its value (see chkStrVar), which is quoted if it
; contains whitespace, and an empty value removes the argument.  At most 126
; characters are copied (the most that PSP_CMDTAIL can hold); copyArgsTo
; copies up to AX instead (eg, when the tail already has a part of its own).
;
; Inputs:
;	DS:SI -> current token (DS = SS)
;	ES:DI -> buffer
;	AX -> end of buffer (copyArgsTo only)
;
; Outputs:
;	DI -> end of copy, CX = length of copy
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	copyArgs
	lea	ax,[di+126]		; AX -> end of buffer
	DEFLBL	copyArgsTo,near
	push	bx
	push	dx
	push	di
	xchg	bx,ax			; BX -> end of buffer
	sub	dx,dx			; DL = # arguments, DH = 1 if quoting
	jmp	short ca3		; (the current token isn't an argument)
ca1:	call	caPut
ca2:	lodsb
	cmp	al,CHR_RETURN		; end of the arguments?
	jbe	ca9			; yes
	cmp	al,'"'			; quote?
	jne	ca2a			; no
	xor	dh,1			; yes, so toggle quoting
	jmp	ca1
ca2a:	test	dh,dh			; copy a quoted character
	jnz	ca1
	cmp	al,CHR_SPACE		; or whitespace as is
	jbe	ca1
	dec	si
	inc	dx
ca3:	push	si			; save the start of the token
ca3a:	lodsb
	cmp	al,CHR_SPACE
	ja	ca3a
	dec	si
	pop	ax
	push	si			; save the end of the token
	xchg	si,ax			; SI -> token
	sub	ax,si
	xchg	cx,ax			; CX = length
	test	dl,dl			; is the token an argument?
	jz	ca4			; no
	call	chkStrVar		; DS:SI -> value, CX = length
	jc	ca6			; it's empty, so remove it
ca4:	jcxz	ca6
	push	cx
	push	si
	mov	ah,0			; AH = 0 (no quotes)
ca4a:	lodsb
	cmp	al,CHR_SPACE		; whitespace?
	ja	ca4b			; no
	mov	ah,'"'			; yes, so the value needs quotes
ca4b:	loop	ca4a
	pop	si
	pop	cx
	call	caQuote
ca5:	lodsb
	call	caPut
	loop	ca5
	call	caQuote
ca6:	push	ss
	pop	ds
	pop	si			; SI -> end of the token
	jmp	ca2
ca9:	pop	cx
	neg	cx
	add	cx,di			; CX = length of copy
	pop	dx
	pop	bx
	ret
caQuote:
	mov	al,ah
	test	al,al			; any quote?
	jz	cq9			; no
caPut:	cmp	di,bx			; room for another character?
	jae	cq9			; no
	stosb
cq9:	ret
ENDPROC	copyArgs

CODE	ENDS

	end
