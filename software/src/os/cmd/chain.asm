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
; command merges a file's lines into the loaded program at the prompt.
; RESUME and RESUME NEXT, which resume at (or after) the statement with an
; error, are here too (see genResumeAt), since they also change the program's
; course from outside the program's own code.
;
; This module is not part of COMMAND's core (see CMD.LRF and HEAP.ASM): when
; only the core is loaded, genCommands refuses CHAIN, and cmdDOS refuses
; MERGE, with "Not enough memory" (see genUpper), as genResume does RESUME
; and RESUME NEXT; genInit then skips scanResume.
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
	EXTNEAR	<endErr>
	EXTSTR	<BAS_EXT>
	EXTABS	<TOK_MERGE,TOK_NEXT>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

CH_MERGE	equ	01h		; CHAIN MERGE
CH_ALL		equ	02h		; CHAIN ...,ALL

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
; and its code, and its variables too, unless ALL was given.
;
dc4:	mov	cx,[chFlags]
	mov	dx,[lineNum].LOW
	mov	sp,[bx].ERR_SP
	push	dx
	push	cx
	call	freeAllCode
	pop	ax			; AL = CH_* flags
	test	al,CH_ALL		; keeping the variables?
	jnz	dc5			; yes
	call	freeAllVars
dc5:	lea	si,[bx].LINEBUF		; DS:SI -> the file's name
	test	al,CH_MERGE
	jnz	dc6
	mov	dx,offset BAS_EXT
	call	cmdLoad			; replace the program's text
	jmp	short dc6a
dc6:	call	mergeFile		; or merge the file's lines into it
dc6a:	jc	dc9			; error (and a message was printed)
	mov	bx,ds:[PSP_HEAP]
	mov	al,GEN_BASIC
	sub	si,si
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genResumeAt
;
; Generate code for "RESUME [0]" or "RESUME NEXT" (genResume comes here, via
; genUpper), which pushes 0 for RESUME or 1 for RESUME NEXT for resumeStmt.
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
DEFPROC	genResumeAt
	mov	al,CLS_DEC
	call	getNextToken		; skip the 0, if any
	mov	al,CLS_KEYWORD
	call	peekNextToken
	mov	dl,0			; DL = 0 for RESUME
	jbe	gra1			; no keyword
	cmp	al,TOK_NEXT
	jne	gra1			; not NEXT (eg, ELSE)
	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT	; consume NEXT
	inc	dx			; DL = 1 for RESUME NEXT
gra1:	xchg	ax,dx
	GENPUSHB al			; push the flag
	GENCALL	resumeStmt
	clc
	ret
ENDPROC	genResumeAt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resumeStmt
;
; Used by "RESUME [0]" and "RESUME NEXT", to end error handling (see endErr)
; and resume at the start of the statement with the error, or at the code
; that follows it (see findStmt), with the stack as it was at the start of
; that statement, so that, as in MSBASIC, any GOSUBs it was in are still
; active.
;
; Inputs:
;	16-bit flag (AL = 0 for RESUME, 1 for RESUME NEXT)
;
; Outputs:
;	None (does not return)
;
DEFPROC	resumeStmt,FAR
	mov	bx,sp
	mov	cx,ss:[bx+4]		; CL = flag
	call	endErr			; SI = SP of the statement
	les	di,ss:[si-4]		; ES:DI -> return address (see rtError)
	mov	sp,si
	xchg	ax,cx
	call	findStmt		; DX:AX -> where to resume
	jc	rsm9
	mov	bp,ss:[bx].ERR_SP	; reset BP and DS (see rtError)
	mov	ds,ss:[bx].VBLKDEF.BLK_NEXT
	push	dx
	push	ax
	ret				; (a RETF, since this is a FAR proc)
;
; If the statement can't be found (eg, it was generated before CHAIN MERGE
; added the RESUME), it's still an error in the error handler, which ends the
; program.
;
rsm9:	inc	byte ptr ss:[bx].ERR_NUM.HIB
	mov	al,20			; "RESUME without error"
	jmp	rtError
ENDPROC	resumeStmt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findStmt
;
; Finds the statement whose code contains the return address of a failed
; call (or for RESUME NEXT, the code that follows that statement), using the
; CTL_STMT entries that mark every statement (see addStmt) in a program that
; uses RESUME or RESUME NEXT (see scanResume).
;
; The statement is the last one marked before the return address, in the
; order that the code was generated (ie, in block order, and then in IP order,
; which is the reverse of an LBLREF table's order, since its newest entries
; come first).  The code that follows it is at the next mark whose IF depth
; isn't deeper, which skips any THEN or ELSE blocks of the statement (or of
; the IF whose THEN block it ends); if there isn't one, the code that follows
; is at the end of the code generated so far, where genMore is called (or the
; final RETF is).
;
; Inputs:
;	AL = 0 for the statement, 1 for the code that follows it
;	ES:DI -> return address
;	SS:BX -> heap
;
; Outputs:
;	If carry clear, DX:AX -> address
;
; Modifies:
;	AX, CX, DX, SI, BP, ES
;
DEFPROC	findStmt
	mov	dx,es			; DX:DI -> return address
	test	dx,dx			; is there one?
	jnz	fs0			; yes
fs8:	stc
	ret
fs0:	push	ax			; save the flag
	sub	cx,cx			; CX = block of the statement (none yet)
	mov	ax,ss:[bx].CBLKDEF.BDEF_NEXT
fs1:	mov	es,ax
	mov	si,es:[CBLK_REFS]
fs2:	cmp	si,es:[BLK_SIZE]	; end of this LBLREF table?
	jae	fs4			; yes
	call	isStmt			; is it a mark?
	jc	fs3			; no
	mov	ax,es
	cmp	ax,dx			; the block with the return address?
	jne	fs2a			; no
	cmp	es:[si].LBL_IP,di	; before the return address?
	jae	fs3			; no
fs2a:	mov	cx,es			; CX:BP -> the statement's mark
	mov	bp,si
	jmp	short fs4		; (the rest of the block is older)
fs3:	add	si,size LBLREF
	jmp	fs2
fs4:	mov	ax,es
	cmp	ax,dx			; was it the block with the return address?
	je	fs5			; yes
	mov	ax,es:[BLK_NEXT]
	test	ax,ax
	jnz	fs1
fs5:	pop	ax			; AL = flag
	jcxz	fs8			; no statement
	mov	es,cx
	mov	dx,es:[bp].LBL_NUM	; DX = CTL_STMT + IF depth
	test	al,al			; the code that follows?
	jnz	fs6			; yes
	mov	ax,es:[bp].LBL_IP	; no, the statement itself
	jmp	short fs7
;
; Look for the next mark that isn't deeper, starting with the next newest
; entry in the statement's block, and then in each following block, from its
; oldest entry to its newest.
;
fs6:	mov	si,bp
fs6a:	sub	si,size LBLREF
	cmp	si,es:[CBLK_REFS]	; any newer entries in this block?
	jb	fs6b			; no
	call	isStmt			; is it a mark?
	jc	fs6a			; no
	cmp	es:[si].LBL_NUM,dx	; is it deeper?
	ja	fs6a			; yes
	mov	ax,es:[si].LBL_IP
	jmp	short fs7
fs6b:	mov	ax,es:[BLK_NEXT]
	test	ax,ax			; is there another block?
	jz	fs6c			; no
	mov	es,ax
	mov	si,es:[BLK_SIZE]
	jmp	fs6a
fs6c:	mov	ax,es:[BLK_FREE]	; the end of the code generated so far
	sub	ax,5			; (a far CALL to genMore)
	test	ss:[bx].GEN_FLAGS,GEN_DONE
	jz	fs7
	add	ax,4			; (or the final RETF)
fs7:	mov	dx,es			; DX:AX -> address
	clc
	ret
ENDPROC	findStmt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; isStmt
;
; Inputs:
;	ES:SI -> LBLREF
;
; Outputs:
;	Carry clear if it's a mark (ie, CTL_STMT + an IF depth from 0 to 2)
;
; Modifies:
;	AX
;
DEFPROC	isStmt
	mov	ax,es:[si].LBL_NUM
	sub	ax,CTL_STMT
	cmp	ax,3			; CTL_STMT through CTL_STMT + 2?
	cmc				; (carry set if not)
	ret
ENDPROC	isStmt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scanResume
;
; Called by genInit before a program's code is generated, to see whether the
; program uses RESUME or RESUME NEXT (ie, RESUME not followed by a line number
; other than 0), in which case every statement must be marked (see addStmt).
; The marks take room in the code blocks, so other programs don't get them.
; We look for "RESUME" (in any case) anywhere in a line, so the word in a
; string or a remark is a false alarm, which costs only room.
;
; Inputs:
;	DS:BX -> heap
;	DX = first text block
;
; Outputs:
;	GEN_STMT1 set in GEN_FLAGS if statements must be marked
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	scanResume
	push	cx
	push	dx
	push	bp
	push	ds
sr1:	mov	ds,dx
	ASSUME	DS:NOTHING
	mov	si,size TBLK
sr2:	cmp	si,ds:[BLK_FREE]	; any more lines in this text block?
	jae	sr8			; no
	lodsw				; skip the line's label #
	lodsb
	mov	ah,0
	mov	bp,si
	add	bp,ax			; BP = end of the line
sr3:	lea	ax,[si+6]
	cmp	ax,bp			; is there room for "RESUME"?
	ja	sr7			; no
	lodsb
	and	al,0DFh
	cmp	al,'R'
	jne	sr3
	push	si
	mov	di,offset ESUME
	mov	cx,5
sr4:	lodsb
	and	al,0DFh
	cmp	al,cs:[di]
	jne	sr6
	inc	di
	loop	sr4
sr5:	cmp	si,bp			; end of the line?
	jae	sr9			; yes
	lodsb
	cmp	al,' '
	je	sr5
	sub	al,'1'
	cmp	al,9			; a line number (other than 0)?
	jae	sr9			; no, so it's RESUME, RESUME 0, or NEXT
sr6:	pop	si
	jmp	sr3
sr7:	mov	si,bp			; on to the next line
	jmp	sr2
sr8:	mov	dx,ds:[BLK_NEXT]
	test	dx,dx			; is there another text block?
	jnz	sr1			; yes
	jmp	short sr10
sr9:	pop	si
	or	ss:[bx].GEN_FLAGS,GEN_STMT1
sr10:	pop	ds
	ASSUME	DS:DATA
	pop	bp
	pop	dx
	pop	cx
	ret
ENDPROC	scanResume

ESUME	db	"ESUME"			; (see scanResume)

CODE	ENDS

	end
