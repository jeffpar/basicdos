;
; BASIC-DOS CHAIN and MERGE
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; CHAIN replaces the running program with another, or with MERGE, merges
; another file's lines into it, and keeps running, like MSBASIC; the MERGE
; command merges a file's lines into the loaded program at the prompt, and
; RUN file runs a file (replacing the running program, if any), while RUN in
; a program restarts it.
;
; This module is not part of COMMAND's core (see CMD.LRF and HEAP.ASM): when
; only the core is loaded, genCommands refuses CHAIN, cmdDOS refuses MERGE,
; and cmdRun refuses RUN file (and RUN in a program), with "Not enough memory"
; (see genUpper).
;
	DOSFUNC equ 1
	include	cmd.inc
	include	gen.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genStr,genLong,genPushZeroLong,genPushImmByteAL,genCallCS>
	EXTNEAR	<getNextToken,peekNextToken,peekNextSymbol>
	EXTNEAR	<genInit,genMore,findLabel,genJmp5,rtError,ctrlc>
	EXTNEAR	<releaseStr,findProgram,openError,freeAllCode,freeAllVars>
	EXTNEAR	<chkProgram,cmdLoad,storeLine,nextLine,freeAllBlocks>
	EXTNEAR	<getFileName,cmdRunFlags,closeFile>
	EXTSTR	<BAS_EXT>
	EXTABS	<TOK_MERGE>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

CH_MERGE	equ	01h		; CHAIN MERGE
CH_ALL		equ	02h		; CHAIN ...,ALL
CH_RUN		equ	04h		; RUN (restart; see runFile)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genChain
;
; Generate code for "CHAIN [MERGE] file[,[line][,ALL]]", which pushes the
; filename, the line # (0 if none), and the CH_* flags for doChain.  CHAIN's
; DELETE option isn't supported.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genChain
	sub	dx,dx			; DX = CH_* flags
	mov	al,CLS_KEYWORD
	call	peekNextToken
	jbe	gch1
	cmp	al,TOK_MERGE		; CHAIN MERGE?
	jne	gch1			; no
	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT	; yes, so consume MERGE
	inc	dx			; DX = CH_MERGE
gch1:	push	dx
	call	genStr			; push the filename
	jc	gch9
	cmp	al,','			; is there a line # (or ALL)?
	jne	gch3			; no
	call	peekNextSymbol
	cmp	al,','			; is the line # omitted?
	je	gch2			; yes
	call	genLong			; push the line #
	jc	gch9
	cmp	al,','			; is ALL next?
	je	gch4			; yes
	jmp	short gch5
gch2:	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT	; consume the comma
	call	genPushZeroLong		; (no line #)
gch4:	mov	al,CLS_VAR
	call	getNextToken
	jbe	gch8
	cmp	cx,3			; is the name ALL?
	jne	gch8			; no (eg, DELETE)
	cmp	al,'A'
	jne	gch8
	mov	ax,[si+1]
	and	ax,0DFDFh		; (upper-case the rest)
	cmp	ax,'LL'
	jne	gch8
	pop	dx
	or	dl,CH_ALL
	push	dx
	jmp	short gch5
gch3:	call	genPushZeroLong		; no line #
gch5:	pop	ax			; AL = CH_* flags
	GENPUSHB al
	GENCALL	doChain
	ret
gch8:	stc
gch9:	pop	dx
	ret
ENDPROC	genChain

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doChain
;
; Used by "CHAIN [MERGE] file[,[line][,ALL]]", which replaces the running
; program, as MSBASIC does: the file's lines replace the program's text (or,
; with MERGE, are merged into it), the variables are freed (unless ALL is
; given), and the program starts again at the line (or its first line), with
; the stack (and therefore any GOSUBs and FOR loops) reset to where it was
; when the program started (see ERR_SP in genCode), and no ON ERROR handler.
;
; The file is found before anything is freed, so a missing file is a runtime
; error (which an ON ERROR handler can catch); if the file can't be loaded
; after that, the program ends (via ctrlc).
;
; Inputs:
;	string value (filename)
;	32-bit line # (0 if none)
;	CH_* flags
;
; Outputs:
;	None (does not return)
;
DEFPROC	doChain,FAR
	ARGVAR	pName,dword
	ARGVAR	lineNum,dword
	ARGVAR	chFlags,word
	ENTER
	push	ss
	pop	ds
	ASSUME	DS:DATA
	mov	bx,ds:[PSP_HEAP]
	cmp	[lineNum].HIW,0		; is the line # out of range?
	mov	al,5			; ("Illegal function call")
	jne	dc8			; yes
	les	di,[pName]		; ES:DI -> filename
	ASSUME	ES:NOTHING
	call	releaseStr		; (which leaves the string intact)
	mov	si,di
	mov	ax,es
	push	ss
	pop	es
	ASSUME	ES:DATA
	lea	di,[bx].LINEBUF
	push	di
	sub	cx,cx
	test	si,si			; empty string?
	jz	dc1			; yes
	mov	ds,ax			; DS:SI -> filename
	ASSUME	DS:NOTHING
	lodsb
	mov	cl,al
	rep	movsb			; copy it to LINEBUF
	push	ss
	pop	ds
	ASSUME	DS:DATA
dc1:	pop	si			; SI -> LINEBUF
dc2:	cmp	di,si			; remove any trailing spaces
	je	dc3			; (eg, MUSIC.BAS's "MARCH ")
	cmp	byte ptr [di-1],' '
	jne	dc3
	dec	di
	jmp	dc2
dc3:	mov	[di],cl			; null-terminate the name
	mov	cx,di
	sub	cx,si			; CX = length of the name
	DOSUTIL	STRUPR
	mov	dx,offset BAS_EXT
	call	findProgram		; LINEBUF = the file's name, if found
	mov	al,53			; ("File not found")
	jnc	dc4
dc8:	jmp	rtError
;
; We've found the file, so the current program is done: discard its stack
; and its code, and its variables too, unless ALL was given.  runFile also
; enters here (at dc4a), with BX -> CMDHEAP, CX = CH_* flags, DX = line #,
; and the file's name in LINEBUF (unless CH_RUN keeps the program's text).
;
dc4:	mov	cx,[chFlags]
	mov	dx,[lineNum].LOW
dc4a:	mov	sp,[bx].ERR_SP
	push	dx
	push	cx
	call	freeAllCode
	pop	ax			; AL = CH_* flags
	test	al,CH_ALL		; keeping the variables?
	jnz	dc5			; yes
	call	freeAllVars
dc5:	test	al,CH_RUN		; restarting the program?
	jnz	dc5a			; yes
	lea	si,[bx].LINEBUF		; DS:SI -> the file's name
	test	al,CH_MERGE
	jnz	dc6
	mov	dx,offset BAS_EXT
	call	cmdLoad			; replace the program's text
	jmp	short dc6a
dc5a:	mov	al,[bx].GEN_FLAGS	; keep the program's text, and
	and	al,GEN_BATCH		; restart a BAT file as one
	jnz	dc6c
	jmp	short dc6b
dc6:	call	mergeFile		; or merge the file's lines into it
dc6a:	jc	dc9			; error (and a message was printed)
	mov	bx,ds:[PSP_HEAP]
dc6b:	mov	al,GEN_BASIC
dc6c:	sub	si,si
	call	genInit			; ES:DI -> the program's new code
	jbe	dc9			; (or there's nothing to run)
	ASSUME	ES:NOTHING
	pop	dx			; DX = line #
	mov	si,di			; SI -> where to start
	test	dx,dx			; was a line # given?
	jz	dc7			; no
;
; Start at the line the way GOTO does: generate a placeholder that becomes a
; JMP to the line once genMore reaches it (see genGoto).  Since the code may
; be kept for RUN (see keepCode), which must start at the first line, the code
; begins with a JMP around the placeholder, and we start just past that JMP.
;
	inc	di
	inc	di			; ES:DI -> the cap
	mov	ax,OP_JMPS OR (7 SHL 8)	; (skips the next 7 bytes)
	stosw
	mov	si,di
	mov	ax,OP_MOV_BP_SP
	stosw
	xchg	ax,dx			; AX = line #
	call	findLabel		; add a reference to the line
	call	genJmp5			; and generate its placeholder
	GENCALL	genMore			; and then the cap again
	mov	es:[BLK_FREE],di
dc7:	sub	ax,ax
	mov	[bx].ERR_NUM,ax		; no error or ON ERROR handler
	mov	[bx].ERR_ADDR.SEG,ax
	mov	ds,[bx].VBLKDEF.BDEF_NEXT
	ASSUME	DS:NOTHING
	push	es
	push	si
	ret				; jump to the new code
dc9:	jmp	ctrlc
ENDPROC	doChain

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMerge
;
; Process "MERGE file", which merges the lines of a BAS file into the loaded
; program (see mergeFile).  The file is found the same way LOAD finds it (see
; findProgram), but only as a .BAS file.  A running program must use CHAIN
; MERGE instead.
;
; Inputs:
;	BX -> CMDHEAP
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	cmdMerge
	call	chkProgram		; is a program running?
	jc	cm9			; yes
	mov	dx,offset BAS_EXT
	call	findProgram		; find the file
	jnc	mergeFile
	jmp	openError		; report error (AX) opening file (SI)
cm9:	ret
ENDPROC	cmdMerge

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; runFile
;
; Process "RUN [file]" when a file is given or a program is running (see
; cmdRun), as in MSBASIC.  The file is a BAS file, found the same way MERGE
; finds it (see findProgram), and if it isn't found, RUN fails like any other
; command (see cmdDOS).  At the prompt, RUN file is LOAD file followed by RUN.
; In a program, RUN file replaces the program, as CHAIN file does (see
; doChain), and RUN alone restarts the program (as a BAT file, if it is one),
; and either way, all open files are closed first.  An empty string variable
; (eg, RUN E$) is the same as RUN alone.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	Carry set if the file couldn't be found or loaded; otherwise, whatever
;	RUN returns (in a program, it doesn't return)
;
; Modifies:
;	Any
;
DEFPROC	runFile
	mov	dl,[bx].CMD_ARG
	sub	cx,cx			; (no default)
	call	getFileName		; DS:SI -> filename, CX = length
	mov	al,CH_RUN		; AL = CH_* flags (if there's no file)
	jc	rf1			; there's no file (or it's empty)
	mov	dx,offset BAS_EXT
	call	findProgram		; find the file
	jc	rf8
	mov	al,0			; AL = CH_* flags (none)
rf1:	cmp	[bx].CBLKDEF.BDEF_NEXT,0; is a program running?
	jne	rf3			; yes
	test	al,al			; is there a file?
	jnz	rf2			; no
	mov	dx,offset BAS_EXT
	call	cmdLoad			; yes, so load it
	jc	rf9
rf2:	mov	al,GEN_BASIC
	jmp	cmdRunFlags		; and run it
rf3:	push	ax
	push	bx
	sub	ax,ax
	push	ax
	push	ax			; push 0 (all files)
	push	cs
	call	closeFile		; close them (a FAR function)
	pop	bx
	pop	cx			; CX = CH_* flags
	sub	dx,dx			; DX = line # (none)
	jmp	dc4a			; replace or restart the program
rf8:	jmp	openError		; report error (AX) opening file (SI)
rf9:	ret
ENDPROC	runFile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mergeFile
;
; Loads a file into text blocks of its own (see cmdLoad), and then adds each
; of its lines to the program, replacing any line with the same # (see
; storeLine).  Every line must be numbered, except blank lines, which are
; skipped.
;
; Inputs:
;	BX -> CMDHEAP
;	DS:SI -> filename
;
; Outputs:
;	Carry clear if successful, set if error (and a message was printed)
;
; Modifies:
;	Any
;
DEFPROC	mergeFile
	sub	ax,ax
	xchg	ax,[bx].TBLKDEF.BLK_NEXT; set the program's text aside
	push	ax
	mov	dx,offset BAS_EXT
	call	cmdLoad			; and load the file
	mov	bx,ds:[PSP_HEAP]
	pop	ax
	xchg	ax,[bx].TBLKDEF.BLK_NEXT; AX = the file's text
	push	ax			; (until it's freed below)
	jc	mf8
	mov	es,ax
	ASSUME	ES:NOTHING
	mov	di,size TBLK - 3
	sub	cx,cx
mf1:	call	nextLine		; ES:DI -> line (AX = #, CX = length)
	cmc
	jnc	mf8			; no more lines
	test	ax,ax			; an unnumbered line?
	jnz	mf2			; no
	jcxz	mf1			; yes, but it's blank, so skip it
mf2:	push	cx
	push	di
	push	es
	lea	si,[di+3]
	lea	di,[bx].LINEBUF
	push	di
	push	es
	push	ss
	pop	es
	pop	ds			; DS:SI -> the line's text
	ASSUME	DS:NOTHING
	push	cx
	rep	movsb			; copy it to LINEBUF
	pop	cx
	pop	si			; SI -> LINEBUF
	push	ss
	pop	ds
	ASSUME	DS:DATA
	call	storeLine		; and add it to the program
	pop	es
	pop	di
	pop	cx
	jnc	mf1
mf8:	mov	si,sp			; SI -> the file's text
	pushf
	call	freeAllBlocks		; free it
	popf
	pop	ax
	ret
ENDPROC	mergeFile

CODE	ENDS

	end
