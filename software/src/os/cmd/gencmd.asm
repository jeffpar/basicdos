;
; BASIC-DOS Code Generator
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This is the core of the code generator: genCode runs the code for a line or
; program, genMore generates it as it runs, and genCommands dispatches each
; command to its generator.  The token helpers that all the gen*.asm files
; share (eg, getNextToken) are in gentok.asm; expressions (genExpr) and the
; code-emitting helpers (eg, GENCALL's genCallCS) are in genemit.asm, except
; for genPushImm (see genPushVarPtr); and the label helpers (addLabel,
; findLabel) are in genflow.asm.
;
; Generates code for these commands:
;
;	DEFDBL/DEFINT/DEFSNG/DEFSTR	(genDefDbl, genDefInt, genDefStr)
;	LET				(genLet)
;	All DOS commands		(genDOS, generates call to callDOS)
;
; The other gen*.asm files include:
;
;	gencon.asm			console I/O (CLS, COLOR, ECHO, INPUT,
;					LINE INPUT, PRINT, WRITE)
;	gendef.asm			definitions (DATA, DEF, DIM, ERASE,
;					OPTION BASE, READ, RESTORE) and array
;					element references
;	genflow.asm			control (END, FOR/NEXT, GOSUB, GOTO,
;					IF/THEN/ELSE, ON, RETURN, WHILE/WEND)
;	genfpu.asm			floating-point support
;	gengfx.asm			graphics (CIRCLE, DRAW, GET, LINE,
;					MOUSE, PAINT, PRESET, PSET, PUT)
;	genprtf.asm			PRINTF (and its runtime function)
;	genexp.asm			expressions (genExpr)
;	gensys.asm			system (CHAIN, DEF SEG, ERROR, KEY,
;					PLAY, POKE, SOUND)
;	genfile.asm			file I/O (CLOSE, FIELD, GET #, OPEN,
;					PUT #, etc), outside the core
;	genemit.asm			code-emitting helpers (genCallCS,
;					genPushImmLong, etc)
;	gentok.asm			line and token helpers (getNextToken,
;					peekNextToken, validateOp, etc)
;
	DOSFUNC equ 1
	include	cmd.inc
	include	gen.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<allocCode,ensureRoom,keepCode,genRedir,genRedirEnd>
	EXTNEAR	<addVar,chkColon,setVarLong,setVarDouble>
	EXTNEAR	<setStr,compactStrs,genArrayRef,checkCtl>
	EXTNEAR	<memError,strPath,setPath,callDOS,rtError>
	EXTNEAR	<genExpr,genCvtType,genCallCS,genPushImmLong>
	EXTNEAR	<getNextLine,getNextSymbol,getNextToken,peekNextToken>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCode
;
; Rather than generating all the code for a program before running it, which
; delays the start of a large program, we generate only a "cap" (a call to
; genMore) and run that; genMore then generates the code for each line as the
; program reaches it (see genMore).
;
; Inputs:
;	AL = GEN flags (eg, GEN_BATCH)
;	DS:BX -> heap
;	DS:SI -> INPUTBUF (for single line) or null (for TBLKs)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	genCode
	LOCVAR	pCode,dword		; original start of generated code
	ENTER

	test	al,GEN_BATCH
	jz	gc1
	or	al,GEN_ECHO
gc1:	mov	[bx].GEN_FLAGS,al

	sub	cx,cx
	mov	[bx].ERR_CODE,cl
	mov	[bx].LINE_NUM,cx
	mov	[bx].LINE_LBL,cx
	mov	[bx].LBL_DATA[0],cx	; (see addLabel)
	mov	byte ptr [bx].GFX_DATA.GFX_MODE,cl	; see gfxInit
	mov	dx,ds
	test	si,si
	jnz	gc2
	mov	dx,[bx].TBLKDEF.BLK_NEXT
	test	dx,dx			; anything to run?
	jnz	gc1a			; yes
	jmp	gc9			; no (TODO: display a message?)
gce:	call	memError
	jmp	gc9
;
; Like MSBASIC (see CLEARC), a program starts with the default types for all
; variables (ie, any DEFINT, DEFDBL, or DEFSTR from before is forgotten).
; However, a BAT file starts with an implied DEFINT A-Z, since batch files
; rarely need floating-point variables.
;
; TODO: Since DEFVARS isn't reset when a program ends, a BAT file's types
; (implied or not) remain in effect at the prompt afterward; revisit whether
; the prompt should start over with the default types.
;
gc1a:	push	ds
	pop	es
	lea	di,[bx].DEFVARS
	mov	cl,26
	mov	al,ch
	test	[bx].GEN_FLAGS,GEN_BATCH
	jz	gc1b
	mov	al,VAR_LONG		; implied DEFINT A-Z
gc1b:	rep	stosb			; (and CX is zero again)
	mov	si,size TBLK
	mov	[bx].DATA_STATE.DATA_SEG,cx	; start READ at the first DATA item
gc2:	mov	[bx].LINE_PTR.OFF,si
	mov	[bx].LINE_PTR.SEG,dx
	mov	[bx].LINE_LEN,cx	; CX = previous length (0)

	call	allocCode
	jc	gce
	ASSUME	ES:NOTHING		; ES:DI -> code block
	mov	[pCode].OFF,di
	mov	[pCode].SEG,es

	mov	ax,OP_MOV_BP_SP		; make it easy for endProgram
	stosw				; to reset the stack and return
	GENCALL	genMore			; and cap the code
	mov	es:[BLK_FREE],di
;
; The memory model for the generated code is simple: CS is the current
; code block, SS is the heap, DS is the first var block (if any; see addVar),
; and ES is scratch.
;
; Since a BAS file can run another BAS file, we save the caller's ON ERROR
; state (see rtError), and then record the SP that the code will start with
; (which genMore also uses to end the program if it finds an error).
;
	mov	si,ds:[PSP_HEAP]
	push	[si].ERR_SP
	push	[si].ERR_NUM
	push	[si].ERR_ADDR.OFF
	push	[si].ERR_ADDR.SEG
	sub	ax,ax
	mov	[si].ERR_NUM,ax
	mov	[si].ERR_ADDR.SEG,ax
	push	bp
	push	ds
	mov	ax,sp
	sub	ax,4			; (the CALL below pushes 4 bytes)
	mov	[si].ERR_SP,ax
	mov	ds,[si].VBLKDEF.BDEF_NEXT
	ASSUME	DS:NOTHING
	call	[pCode]			; execute the code buffer
	clc
gc5:	pop	ds			; (genMore arrives here with carry set)
	ASSUME	DS:DATA
	pop	bp
	mov	si,ds:[PSP_HEAP]
	pop	[si].ERR_ADDR.SEG
	pop	[si].ERR_ADDR.OFF
	pop	[si].ERR_NUM
	pop	[si].ERR_SP
;
; If the program ended before all its code was generated (eg, END), then we
; can't keep the code (see keepCode), since there's no more code to run if
; it's run again.
;
	pushf
	jc	gc7			; error, so free the code
	test	[si].GEN_FLAGS,GEN_DONE	; was all the code generated?
	jnz	gc7			; yes (and carry is clear)
	stc				; no, so free the code
gc7:	call	keepCode		; free (or keep) the code
	call	compactStrs		; free any leftover temp strings
	popf
	jnc	gc9

	mov	bx,ds:[PSP_HEAP]
	cmp	[bx].ERR_CODE,0		; was an error already reported?
	stc
	jne	gc9			; yes (see memError)
	mov	ax,[bx].LINE_LBL	; report the line's label #, if any
	test	ax,ax
	jnz	gc8a
	mov	ax,[bx].LINE_NUM	; otherwise, its position in the file
gc8a:	PRINTF	<"Syntax error in line %d",13,10>,ax
	stc

gc9:	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].ERR_CODE,0	; (preserves carry)
	LEAVE
	ret
ENDPROC	genCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genMore
;
; The generated code calls genMore (with a far CALL) from a 5-byte placeholder,
; which is either the cap at the end of the code generated so far (see
; genCode), or a JMP that hasn't been patched yet (eg, a forward GOTO, or the
; JMP that skips a FOR or WHILE loop whose NEXT or WEND hasn't been generated
; yet; see genJmp5).  We generate lines, starting where the code ends, until
; the placeholder has been overwritten (or patched), cap the code again, and
; return to the placeholder.
;
; Since the lines are still generated in order, the generator's state (eg,
; DEFVARS, and any FOR or WHILE in progress) is the same as if genCode had
; generated them all first; however, an error (eg, a syntax error) isn't found
; until the program reaches it, and then we end the program, returning to
; genCode with carry set.
;
; Since we generate the code on the program's stack, which may be deep in
; GOSUBs by now (GOSUB leaves only GOSUB_MIN bytes; see doGosub), we first
; make sure that GEN_MIN bytes are left, which is more than enough for a
; complex line (eg, nested IFs and function calls take about 330 bytes);
; otherwise, it's an "Out of memory" error.
;
; Inputs:
;	Return address -> byte following the placeholder
;
; Outputs:
;	DS -> first var block (if any; see genCode)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
GEN_MIN	equ	768			; min stack space for generating code

DEFPROC	genMore,FAR
	mov	bx,ss:[PSP_HEAP]
	lea	ax,[bx].STACK + GEN_MIN
	cmp	sp,ax			; is there enough stack space?
	jae	gm0			; yes
	mov	al,7			; "Out of memory"
	jmp	rtError
gm0:	push	bp
	mov	bp,sp
	sub	word ptr [bp+2],5	; return to the placeholder
	push	ss
	pop	ds
	ASSUME	DS:DATA
	mov	bx,ds:[PSP_HEAP]
	mov	ax,[bx].CBLKDEF.BDEF_NEXT
gm1:	mov	es,ax			; find the last code block
	mov	ax,es:[BLK_NEXT]
	test	ax,ax
	jnz	gm1
	mov	di,es:[BLK_FREE]
	sub	di,5			; ES:DI -> cap

gm2:	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a line
	jc	gm8
	call	getNextLine
	jc	gm6			; no more lines
	call	genRedir		; any ":>" redirection?
	jc	gm8			; yes, but it's invalid
	push	ax
	push	dx
	push	cx
	call	genCommands		; generate code
	pop	cx
	pop	dx
	pop	ax
	jc	gm8
	test	ax,ax			; was the line redirected?
	jz	gm3			; no
	mov	si,ds:[PSP_HEAP]
	mov	[si].LINE_LEN,ax	; restore the line's length
	call	genRedirEnd		; and end the redirection
	jc	gm8
;
; A line may generate no code at all (eg, REM or DATA), in which case the cap
; is still there, or it may generate another placeholder in the cap's place
; (eg, "GOTO 100"), in which case we keep going, too.  If some other code
; happens to begin with a far CALL to the same offset, we just generate more.
;
gm3:	lds	si,dword ptr [bp+2]	; DS:SI -> placeholder
	cmp	byte ptr [si],OP_CALLF	; still a call to genMore?
	jne	gm4			; no
	cmp	word ptr [si+1],offset genMore
gm4:	push	ss
	pop	ds
	je	gm2			; yes, so generate another line
	GENCALL	genMore			; cap the code again
	mov	bx,ds:[PSP_HEAP]
gm5:	mov	es:[BLK_FREE],di
	mov	ds,[bx].VBLKDEF.BDEF_NEXT
	ASSUME	DS:NOTHING
	pop	bp
	ret

gm6:	push	ss
	pop	ds
	ASSUME	DS:DATA
	call	checkCtl		; any FOR without NEXT (etc)?
	jc	gm8			; yes
	mov	al,OP_RETF		; terminate the code
	stosb
	mov	bx,ds:[PSP_HEAP]
	or	[bx].GEN_FLAGS,GEN_DONE
	jmp	gm5
;
; To end the program, we reset SP the same way that END does (see genEnd),
; discard genCode's return address, and finish up in genCode.
;
gm8:	mov	bx,ds:[PSP_HEAP]
	mov	sp,[bx].ERR_SP
	pop	ax
	pop	ax
	stc
	jmp	gc5
ENDPROC	genMore

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCommands
;
; Generate code for one or more commands.
;
; As in MSBASIC, a command that begins with a variable (or array element)
; followed by '=' is an implicit LET.  This applies only to commands processed
; here (eg, in BAS/BAT files, after THEN or ELSE, or after a colon); a command
; line must still use LET, because parseCmd sends any non-keyword command to
; parseDOS.
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
DEFPROC	genCommands
	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a command
	jnc	gcInit
gcr9:	ret
gcInit:	mov	dx,bx			; DX -> TOKLETs (for implicit LET)
	mov	al,CLS_KEYWORD
	call	getNextToken
	jb	gcs0
	je	gcr9			; out of tokens
	mov	cx,cs:[si].CTD_FUNC	;
	cmp	al,KEYWORD_BASIC	; BASIC keyword?
	jb	gcs2			; no
	jcxz	gcs8			; no command address
;
; If the keyword is alone (eg, "CIRCLE") and its generator fails, then it's
; presumably the name of a program to run (eg, CIRCLE.BAS), so we discard any
; code the generator produced and treat it as a DOS command instead.
;
	push	cx
	mov	al,CLS_ANY
	call	peekNextToken		; any tokens after the keyword?
	pop	cx
	jnz	gcs3			; yes
	push	bx
	push	di
	cmp	cx,ds:[PSP_CODESIZE]	; generator loaded (see genUpper)?
	cmc				; no, so treat it as a failure
	jc	gcs3c
	call	cx			; call the generator function
gcs3c:	pop	si
	pop	dx
	jnc	gcs4
	mov	di,si			; it failed, so discard its code
	mov	bx,dx
	jmp	short gcs1d		; and treat the keyword as a command
;
; If the next token is a colon that a previous command didn't consume (eg,
; "CLS:PRINT"), skip it; otherwise, it must be a DOS command.
;
gcs0:	cmp	ah,CLS_SYM
	jne	gcs1
	mov	si,[bx].TOKLET_OFF
	cmp	byte ptr [si],':'
	jne	gcs1
	add	bx,size TOKLET
	jmp	genCommands

gcs1:	test	ah,CLS_VAR		; variable (ie, implicit LET)?
	jz	gcs1b			; no
	push	bx
	mov	bx,dx
	mov	al,CLS_VAR
	call	getNextToken
	jbe	gcs1a
	call	getNextSymbol
	jbe	gcs1a
	cmp	al,'='			; assignment?
	je	gcs1L			; yes
	cmp	al,'('			; array element assignment?
	jne	gcs1a			; no
gcs1L:	pop	ax			; discard saved BX
	mov	bx,dx			; rewind to the variable
	mov	cx,offset genLet
	jmp	short gcs3
gcs1a:	pop	bx
;
; A failed keyword lookup may leave BX on the first token (eg, a leading
; path character or a quote).  genDOS expects BX past that token, so rewind
; and consume it explicitly, skipping any leading whitespace as usual.
;
gcs1b:	mov	bx,dx
	mov	al,CLS_ANY
	call	getNextToken
gcs1d:	sub	ax,ax			; call genDOS w/o an ID
;
; For non-BASIC keywords, generate callDOS code with a pointer to the
; full command-line and the keyword handler.  callDOS will then perform
; the traditional parse-and-execute logic.
;
gcs2:	cbw				; AX = keyword ID
	mov	dx,cx			; DX = handler address
	mov	cx,offset genDOS

gcs3:	cmp	cx,ds:[PSP_CODESIZE]	; generator loaded (see genUpper)?
	jb	gcs3a			; yes
	call	memError		; no, so report "Not enough memory"
	jmp	short gcs4		; (with carry set)
gcs3a:	call	cx			; call dedicated generator function
gcs4:	mov	es:[BLK_FREE],di
	jnc	gcs10
	ret
;
; A keyword with no generator (eg, ELSE) ends the commands, and we leave it
; for the caller (eg, genIf), returning AX = CLS_KEYWORD and the keyword ID.
;
gcs8:	sub	bx,size TOKLET		; (this clears carry, too)
gcs9:	ret
;
; A command must be followed by a colon or the end of the line (or by a
; keyword with no generator, like ELSE, which ends the commands for the
; caller); anything else (eg, the END in "PRINT 2 END") is a syntax error,
; rather than the start of another command.  Since getNextToken consumes the
; colon that ends a scan, the command may have consumed the colon already.
;
gcs10:	cmp	[bx - size TOKLET].TOKLET_CLS,CLS_SYM
	jne	gcs10a
	mov	si,[bx - size TOKLET].TOKLET_OFF
	cmp	byte ptr [si],':'	; did the command end with a colon?
	je	gcs11			; yes
gcs10a:	mov	al,CLS_ANY
	call	peekNextToken		; ZF set if a colon or no more tokens
	je	gcs11
	jb	gcs12
	cmp	ah,CLS_KEYWORD		; keyword?
	jne	gcs12			; no
	cmp	cs:[si].CTD_FUNC,0	; yes, but does it have a generator?
	je	gcs11			; no (eg, ELSE)
gcs12:	stc				; syntax error
	ret
gcs11:	jmp	genCommands
ENDPROC	genCommands

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genUpper
;
; Jumps to a generator that isn't part of COMMAND's core (ie, one in a module
; linked after CONST.ASM; see CMD.LRF and HEAP.ASM).  When there's too little
; memory for the entire image, the loader loads only the core (see CD_CORESIZE
; in dosapi.inc), and PSP_CODESIZE then ends at the core, so a generator at
; or beyond it isn't there, and we report "Not enough memory" instead.
;
; genCommands makes the same check before calling any keyword's generator,
; genFuncExpr makes it before calling a predefined function, and LOAD makes
; it before calling loadTokens (see edit.asm), so this is for keywords whose
; generator chooses between a core function and an upper one (eg, genLine;
; see gencon.asm), and for cmdDOS, which calls every built-in command's
; handler through here (eg, cmdAuto).  To move more functionality out of the
; core, link its modules after CONST.OBJ, and make sure nothing in the core
; calls them except through one of these checks.
;
; Inputs:
;	DX = address of the generator (or command handler)
;	Everything else as the generator expects (eg, DS:BX -> TOKLETs)
;
; Outputs:
;	Whatever the generator returns, or carry set if it isn't loaded
;
; Modifies:
;	Whatever the generator modifies
;
DEFPROC	genUpper
	cmp	dx,ds:[PSP_CODESIZE]	; is the generator loaded?
	jb	gu9			; yes
	jmp	memError		; no (which sets carry)
gu9:	jmp	dx
ENDPROC	genUpper

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDOS
;
; Generate code for DOS commands.
;
; Inputs:
;	AL = keyword ID
;	DX = handler offset
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genDOS
	push	ax
	GENPUSH	dx			; push handler offset
	pop	dx
	GENPUSH	dx			; push keyword ID
	mov	si,ds:[PSP_HEAP]
	mov	ax,[bx - size TOKLET].TOKLET_OFF
	lea	cx,[si].LINEBUF
	sub	ax,cx			; AX = # bytes preceding command
;
; A colon ends the command, unless it's part of a drive or time (see
; chkColon); quoted colons are inside string tokens, so they never get here.
;
	mov	dx,bx			; DX -> next TOKLET
gd1:	cmp	dx,[si].TOKLET_END	; any tokens left?
	jae	gd2			; no
	push	bx
	mov	bx,dx
	add	dx,size TOKLET
	mov	bx,[bx].TOKLET_OFF	; BX -> token
	cmp	byte ptr [bx],':'	; colon?
	jne	gd1a			; no
	push	ax
	push	dx
	lea	dx,[si].LINEBUF
	add	dx,ax			; DX -> start of command
	call	chkColon
	pop	dx
	pop	ax
	jc	gd1a			; the colon is part of the command
	lea	cx,[si].LINEBUF
	sub	bx,cx
	mov	cx,bx			; CX = end of command (the colon)
	pop	bx
	mov	bx,dx
	sub	bx,size TOKLET		; BX -> colon (for genCommands)
	jmp	short gd3
gd1a:	pop	bx
	jmp	gd1
gd2:	mov	[si].TOKLET_END,bx	; mark the tokens fully processed
	mov	cx,[si].LINE_LEN	; CX = end of command (end of line)
gd3:	sub	cx,ax			; CX = length of command
	push	ax
	GENPUSH	cx			; push length of command line
	mov	cx,[si].LINE_PTR.OFF
	pop	ax
	add	cx,ax
	mov	dx,[si].LINE_PTR.SEG	; DX:CX -> command line
	GENPUSH	dx,cx			; push pointer to command line
	GENCALL	callDOS
	ret
ENDPROC	genDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDefInt
;
; Process "DEFINT".  In BASIC-DOS, "DEFINT" really means "DEFLONG", but we'll
; continue using the original keyword.
;
; NOTE: Originally, I was concerned about parsing and updating letter ranges
; as we go, because if a syntax error occurs midway, we'll end up with partial
; changes.  Then I tried the same thing in MSBASIC, and I ended up with partial
; changes.  So there you go.
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
DEFPROC	genDefInt
	mov	al,VAR_LONG

	DEFLBL	genDefVar,near
	push	ax			; save the type (AL)
gdi1:	call	getCharToken		; check for char
	jbe	gdi8
	mov	dl,al			; DL = 1st char of range
	mov	dh,al			; DH = last char of range

	call	getNextSymbol		; check for hyphen
	jc	gdi9			; error
	jz	gdi3			; no more tokens
	cmp	al,'-'
	je	gdi2
	sub	bx,size TOKLET		; we'll revisit this token below
	jmp	short gdi3

gdi2:	call	getCharToken		; check for another char
	jbe	gdi8
	mov	dh,al			; DH = new last char of range
	cmp	dh,dl			; is the range in order?
	jb	gdi8			; no, report error
;
; For every letter from DL through DH, set DEFVARS[DL] to the type.
;
gdi3:	pop	ax
	push	ax			; AL = new default for each letter
	push	bx
	mov	cl,dh
	sub	cl,dl
	mov	ch,0
	inc	cx			; CX = # of letters to set
	mov	bx,ds:[PSP_HEAP]
	lea	bx,[bx].DEFVARS
	sub	dl,'A'
	add	bl,dl
	adc	bh,ch			; BX -> 1st letter
gdi3a:	mov	[bx],al
	inc	bx
	loop	gdi3a
	pop	bx

	call	getNextSymbol		; check for comma
	jbe	gdi7			; no more tokens (or a ':' or keyword)
	cmp	al,','
	je	gdi1
	sub	bx,size TOKLET		; leave any other symbol for the caller
gdi7:	clc
	jmp	short gdi9

gdi8:	stc
gdi9:	pop	cx			; discard the type
	ret

	DEFLBL	getCharToken,near
	mov	al,CLS_VAR		; token must be CLS_VAR
	call	getNextToken
	jbe	gct8
	dec	cx
	jnz	gct8			; and it must have a length of 1
	inc	cx
	ret
gct8:	stc
	ret
ENDPROC	genDefInt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDefDbl
;
; Process "DEFDBL".  In BASIC-DOS, floating-point will come in only one
; flavor, and this is it; "DEFSNG" is allowed, but it's treated as "DEFDBL".
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
DEFPROC	genDefDbl
	mov	al,VAR_DOUBLE
	jmp	genDefVar
ENDPROC	genDefDbl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDefStr
;
; Process "DEFSTR".
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
DEFPROC	genDefStr
	mov	al,VAR_STR
	jmp	genDefVar
ENDPROC	genDefStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLet
;
; Generate code to "LET" a variable equal some expression.  We'll start with
; 32-bit integer ("long") variables.  We'll also start with the assumption
; that it's OK to alloc the variable at "gen" time, so that the only code we
; have to generate (and execute later) is code that sets the variable, using
; its preallocated location.
;
; Inputs:
;	BX = offset of next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genLet
	mov	al,CLS_VAR
	call	getNextToken
	jbe	gl9

	and	ah,VAR_TYPE		; convert CLS_VAR_* to VAR_*
	mov	al,1			; ARRAY_PTR
	call	genArrayRef		; array element?
	jc	gl9			; error
	jnz	gl1			; yes (AH = element type)
	call	addVar			; DX:SI -> var data
	jc	gl9

	mov	cx,cs
	cmp	dx,cx			; constants (in CS) cannot be "let"
	je	gl2			; except for PATH$
	push	ax			; AH is still var type (from addVar)
	call	genPushVarPtr
	pop	ax
gl1:	push	ax
	call	getNextSymbol
	pop	cx			; CH is now the var type
	jbe	gl9

	cmp	al,'='
	jne	gl9

	call	genExpr
	jc	gl9
;
; Like MSBASIC, assigning a long to a double variable (or vice versa) converts
; the value to the variable's type; all other mismatches are errors.
;
	push	cx
	mov	al,ch
	call	genCvtType		; TODO: generate "type mismatch" error
	pop	cx
	jc	gl9
	mov	dx,offset setVarDouble
	cmp	ch,VAR_DOUBLE		; doubles are copied by reference
	je	gl8
	mov	dx,offset setStr
	cmp	ch,VAR_STR		; strings are adopted or copied
	je	gl8
	mov	dx,offset setVarLong
gl8:	mov	cx,dx
	GENCALL	cx
	ret

gl9:	stc
	ret
;
; PATH$ is a function, but it can also be assigned (see setPath).
;
gl2:	cmp	word ptr cs:[si+2],offset strPath
	jne	gl9			; TODO: Generate a better error message
	call	getNextSymbol
	jbe	gl9
	cmp	al,'='
	jne	gl9
	call	genExpr
	jc	gl9
	mov	al,VAR_STR
	call	genCvtType
	jc	gl9
	GENCALL	setPath
	ret
ENDPROC	genLet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushVarPtr
;
; Inputs:
;	DX:SI = value to push
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	genPushVarPtr
	call	chkVarSeg
	je	gpv1
	call	genPushImm
	jmp	short gpv2
gpv1:	mov	al,OP_PUSH_DS
	stosb
gpv2:	mov	dx,si
	DEFLBL	genPushImm,near
	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushVarPtr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushVarLong
;
; Generates code to push 4-byte variable data onto stack (eg, a VAR_LONG
; integer or a VAR_STR pointer).
;
; DX:SI points to the variable data, and if DX is the first var block (see
; chkVarSeg), then the generated code can assume DS:SI; otherwise, we must
; generate code to load the segment as well.
;
; The generated code will then use a pair of LODSW instructions to load the
; variable data into AX:DX and push it on the stack (yes, ordinarily we'd use
; DX:AX, but that's not the natural order a pair of LODSW provides).
;
; Inputs:
;	DX:SI -> var data
;
; Outputs:
;	None
;
; Modifies:
;	DX, SI, DI
;
DEFPROC	genPushVarLong
	push	ax
	call	chkVarSeg
	je	gpl1
	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	ax,OP_MOV_ES_AX
	stosw
gpl1:	mov	al,OP_MOV_SI		; "MOV SI,offset var data"
	stosb
	xchg	ax,si
	stosw
	je	gpl2
	mov	al,OP_SEG_ES
	stosb
gpl2:	mov	ax,OP_LODSW OR (OP_XCHG_DX SHL 8)
	stosw
	je	gpl3
	mov	al,OP_SEG_ES
	stosb
gpl3:	mov	ax,OP_LODSW OR (OP_PUSH_AX SHL 8)
	stosw
	mov	al,OP_PUSH_DX
	stosb
	pop	ax
	ret
ENDPROC	genPushVarLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkVarSeg
;
; Checks whether DX is the first var block, which the generated code can
; access through DS (see genCode and runCode).  The first block doesn't exist
; until the first var is added (see addVar), so we check the chain itself.
; While a DEF with parameters is being generated, the first block is a temp
; block for the parameters (see allocTempVars), so globals don't match, and
; the generated code loads their segment instead, which is slower but still
; correct (and the parameters themselves are accessed through BP).
;
; Inputs:
;	DX = segment of var data
;
; Outputs:
;	ZF set if DX is the first var block
;
; Modifies:
;	None
;
DEFPROC	chkVarSeg
	push	si
	mov	si,ds:[PSP_HEAP]
	cmp	dx,[si].VBLKDEF.BDEF_NEXT
	pop	si
	ret
ENDPROC	chkVarSeg



CODE	ENDS

	end
