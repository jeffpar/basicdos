;
; BASIC-DOS Code Generator: Control Flow
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these control flow statements:
;
;	END and STOP			(genEnd)
;	FOR ... TO ... [STEP ...]	(genFor and genNext; see FORSLOT and
;	NEXT [var[,var]...]		the forInit and forNext functions in
;					flow.asm)
;	GOSUB				(genGosub; see doGosub in flow.asm)
;	GOTO				(genGoto)
;	IF ... THEN ... [ELSE ...]	(genIf, including implied GOTOs; see
;					also: genBlock, genJmp, and genPatch)
;	ON ... GOTO/GOSUB ...		(genOn)
;	ON ERROR GOTO ...		(genOn; see onError in flow.asm)
;	RESUME line			(genResume)
;	RETURN				(genReturn, which ends a DEF block,
;					or returns from a GOSUB)
;	WHILE ... WEND			(genWhile and genWend)
;
; Every statement is compiled statically, so FOR, WHILE, and their matching
; NEXT and WEND statements are paired up as the code is generated: FOR and
; WHILE push a CTL_FOR or CTL_WHILE entry onto the code block's LBLREF table
; (see pushCtl), whose LBL_IP is the offset of the loop's body, and NEXT and
; WEND remove the innermost one (see findCtl and removeRef), or if it's the
; other kind of loop, report "NEXT without FOR" or "WEND without WHILE".  The
; body follows the 5-byte JMP that skips the loop (which NEXT or WEND patches),
; the address of the FORSLOT (for FOR) or the top of the loop (for WHILE), and
; the line # and position of the FOR or WHILE (see pushCtl).
;
; Code for a program may span several code blocks (see ensureRoom), so every
; JMP that may go to another code block (eg, GOTO, IF, and the JMPs for loops)
; is either a near JMP (if the target is in the same block) or a far JMP, and
; any JMP that's patched later occupies 5 bytes.
;
; See gencmd.asm for an overview of all the gen*.asm files.  Like gencmd.asm,
; these functions are called while generating code, with DS:BX -> TOKLETs and
; ES:DI -> code block.
;
	DOSFUNC equ 1
	GENDEFS equ 1
	include	cmd.inc
	include	gen.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,genCommands,getNextToken,codeSeg>
	EXTNEAR	<genCvtType,genTestDouble,genCallCS,genPushVarPtr>
	EXTNEAR	<genPushImm,genPushImmLong,addVar,getNextSymbol>
	EXTNEAR	<setVarLong,setVarDouble,forInit,forNext,doGosub,doReturn>
	EXTNEAR	<ensureRoom,peekNextToken,onError,offError,resumeErr,genMore>
	EXTNEAR	<compError,compErrLine,getLineNum,setErrorLevel>
	EXTNEAR	<findCtl,findLabel,pushCtl,removeRef>
	EXTABS	<TOK_ELSE,TOK_THEN,TOK_TO,TOK_STEP,TOK_GOTO,TOK_GOSUB>
	EXTABS	<TOK_ERROR>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

FS_SIZE		equ	22		; size of FORSLOT (see flow.asm)
OP_JZ_3		equ	00374h		; JZ  $+5 (eg, around a near JMP)
OP_JZ_5		equ	00574h		; JZ  $+7 (eg, around a far JMP)
OP_JNZ_5	equ	00575h		; JNZ $+7 (eg, around a far JMP)
OP_JNZ_13	equ	00D75h		; JNZ $+15 (around JMP, dword, 2 words)
OP_OR_DX_DX	equ	0D20Bh		; OR  DX,DX
OP_CMP_AX	equ	03Dh		; CMP AX,imm16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genGoto
;
; Generate code for "GOTO [line]"
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
DEFPROC	genGoto
	mov	al,CLS_DEC
	call	getNextToken
	jbe	gg9
	DOSUTIL	ATOI32D			; DS:SI -> decimal string
	call	findLabel		; DX:AX -> label (if carry clear)
;
; If carry is clear, then we found the specified label # (ie, it must have
; been a backward reference), so we can generate the correct JMP immediately.
;
; If carry is set, then the label # must be a forward reference.  findLabel
; automatically calls addLabel with LBL_RESOLVE set, so when the definition is
; finally found, this (and any other LBL_RESOLVE references) can be resolved.
;
; In the interim, we generate a placeholder that calls genMore (see genJmp5),
; which generates more code until the label definition is encountered and the
; placeholder has been overwritten with a JMP (see addLabel).
;
; Since the label may be in another code block, every GOTO occupies 5 bytes,
; which is enough for a far JMP (a near JMP is padded with NOPs).
;
	jc	gg7
	push	di
	call	emitJmp
	pop	ax
	sub	ax,di
	cmp	ax,-3			; did we generate a near JMP?
	jne	gg8			; no
	mov	ax,(OP_NOP SHL 8) OR OP_NOP
	stosw				; yes, so pad it
	jmp	short gg8
gg7:	call	genJmp5			; placeholder for the JMP
gg8:	clc
gg9:	ret
ENDPROC	genGoto

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genIf
;
; Generate code for "IF [expr] THEN [commands] ELSE [commands]"
;
; "IF" is like a unary operator: generate code for the expression, pop the
; result, and jump to the "THEN" command block if non-zero or the "ELSE"
; command block if zero.
;
; Each block of commands must go back through genCommands, which is simple
; enough, unless there is another "IF" in the block, because any subsequent
; "ELSE" belongs to the second "IF", not the first.
;
; The general structure of the generated code will look like:
;
;	call	evalEQLong (assuming an expression with '=')
;	pop	ax
;	pop	dx
;	or	ax,dx
;	jnz	thenBlock
;	jmp	elseBlock		; (5 bytes, near or far)
;    thenBlock:
;	; Generate code for "THEN" block
;	; ...
;	jmp	nextBlock (only needed if there's an "ELSE" block)
;    elseBlock:
;	; Generate code for "ELSE" block
;	; ...
;    nextBlock:
;
; Since a block may continue in another code block (see ensureRoom), every
; JMP is a 5-byte placeholder (see genJmp5) that's patched with either a near
; or far JMP once the block it skips has been generated (see patchHere).
;
; A block that begins with a line number is an implied GOTO (eg, "THEN 10"
; instead of "THEN GOTO 10").
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
DEFPROC	genIf
	call	genExpr
	jbe	gif9
	cmp	ah,CLS_KEYWORD
	jne	gif9
	cmp	al,TOK_THEN
	jne	gif9
	call	genTestDouble		; (a double is true if it's non-zero)
	jc	gif9
	add	bx,size TOKLET		; consume THEN
	mov	ax,OP_POP_DX_AX
	stosw
	mov	ax,OP_OR_AX_DX
	stosw
	mov	ax,OP_JNZ_5
	stosw
	call	genJmp5			; JMP to the ELSE block (placeholder)
	push	es
	push	dx
	call	genBlock		; generate the THEN block
	pop	si
	pop	dx			; DX:SI -> after the JMP to ELSE
	jc	gif9
	cmp	ah,CLS_KEYWORD
	jne	gif8
	cmp	al,TOK_ELSE
	jne	gif8			; no ELSE block
	add	bx,size TOKLET		; consume ELSE
	push	dx
	push	si
	call	genJmp5			; JMP to the next block (placeholder)
	pop	si
	pop	ax
	push	es
	push	dx			; save JMP to the next block
	xchg	dx,ax
	sub	si,5
	call	patchHere		; ELSE block starts here
	call	genBlock		; generate the ELSE block
	pop	si
	pop	dx			; DX:SI -> after the JMP to next
	jc	gif9
gif8:	sub	si,5
	call	patchHere		; next block starts here
	clc
	ret
gif9:	stc
	ret
ENDPROC	genIf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genBlock
;
; Generates a block of commands for genIf; a block that begins with a line
; number is an implied GOTO.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;	AX = CLS_KEYWORD and keyword ID, if a keyword (eg, ELSE) ended
;	the block
;
; Modifies:
;	Any
;
DEFPROC	genBlock
	mov	al,CLS_DEC
	call	getNextToken
	jbe	gb1			; no line number
	sub	bx,size TOKLET		; let genGoto consume the line number
	call	genGoto
	jc	gb9
gb1:	jmp	genCommands
gb9:	ret
ENDPROC	genBlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genJmp, genPatch
;
; genJmp generates a near JMP whose target will be patched later, and genPatch
; patches a JMP to jump to the next unused location in the code block.
;
; Inputs:
;	ES:DI -> code block
;	SI = offset returned by genJmp (for genPatch)
;
; Outputs:
;	DX = offset of the byte following the JMP (from genJmp)
;	Carry clear (from genPatch)
;
; Modifies:
;	AX, DX (genJmp), or AX (genPatch)
;
DEFPROC	genJmp
	mov	al,OP_JMP
	stosb
	stosw				; (offset to be patched)
	mov	dx,di
	ret
ENDPROC	genJmp

DEFPROC	genPatch
	mov	ax,di
	sub	ax,si			; AX = distance from JMP to here
	mov	es:[si-2],ax
	clc
	ret
ENDPROC	genPatch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genReturn
;
; Generate code to "RETURN [optional value]" from a DEF block, or "RETURN"
; from a GOSUB.
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
DEFPROC	genReturn
	mov	si,ds:[PSP_HEAP]
	test	[si].GEN_FLAGS,GEN_DEF	; ending a DEF block?
	jnz	gr1			; yes
	GENCALL	doReturn		; no, returning from a GOSUB
	ret
gr1:	call	genExpr
	jc	gr9
	mov	al,[si].DEF_TYPE
	call	genCvtType		; convert to the function's type
	jc	gr9
	and	[si].GEN_FLAGS,NOT GEN_DEF
gr9:	ret
ENDPROC	genReturn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genResume
;
; Generate code for "RESUME line", which ends error handling (see resumeErr)
; and jumps to the line.  RESUME (or RESUME 0) and RESUME NEXT, which resume
; at (or after) the statement with the error, aren't supported, since finding
; that statement would require marking the start of every statement's code.
; RESUME without a line number is a syntax error, which we report ourselves,
; so that RESUME alone isn't run as a program (see genCommands); RESUME 0 is
; simply a RESUME to line 0.
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
DEFPROC	genResume
	mov	al,CLS_DEC
	call	peekNextToken
	mov	al,BERR_SYNTAX		; "Syntax error"
	jbe	grs9			; no line number
	GENCALL	resumeErr
	jmp	genGoto
grs9:	jmp	compError
ENDPROC	genResume

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genEnd
;
; Generate code for "END [n]" (and "STOP [n]", which is currently the same),
; which sets ERRORLEVEL to n (default 0) and ends the program.
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
DEFPROC	genEnd
	call	genExpr			; push the value, if any
	jnc	ge1
	test	dh,dh			; were there any tokens?
	stc
	jnz	ge9			; yes, so it's an error
ge1:	jz	ge2			; no value
	mov	al,VAR_LONG
	call	genCvtType		; the value must be a long
	jnc	ge3
	ret
ge2:	GENPUSH	0,0			; push 0
ge3:	GENCALL	setErrorLevel
	mov	ax,OP_MOV_SP_BP		; same as endProgram (see genCode)
	stosw
	mov	al,OP_RETF
	stosb
	clc
ge9:	ret
ENDPROC	genEnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genFor
;
; Generate code for "FOR var = start TO limit [STEP step]", which looks like:
;
;	jmp	short around the FORSLOT
;	(FORSLOT)
;	(set var to start)
;	(push limit and step, converted to the type of var)
;	push	segment FORSLOT		; (since the code may have continued
;	push	offset FORSLOT		; in another code block by now)
;	call	forInit
;	or	ax,dx
;	jnz	body
;	jmp	next			; patched by genNext (5 bytes)
;	dd	FORSLOT			; (for genNext)
;	dw	line #, position	; (see pushCtl)
;    body:
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
DEFPROC	genFor
	mov	al,CLS_VAR
	call	getNextToken		; loop variable
	ja	gfo0
gfoX:	stc
	ret
gfo0:	and	ah,VAR_TYPE
	call	addVar			; DX:SI -> loop variable
	jc	gfoX
	cmp	ah,VAR_LONG		; must be a long or a double
	je	gfo1
	cmp	ah,VAR_DOUBLE
	jne	gfoX
gfo1:	mov	cx,ax			; CH = type
	mov	ax,OP_JMPS OR (FS_SIZE SHL 8)
	stosw
	push	es			; push FORSLOT segment
	push	di			; push FORSLOT offset
	mov	al,ch
	mov	ah,0
	stosw				; FS_TYPE and FS_PAD
	mov	ax,si
	stosw				; FS_VAR offset
	mov	ax,dx
	stosw				; FS_VAR segment
	push	cx
	mov	cx,8
	sub	ax,ax
	rep	stosw			; zero FS_LIMIT and FS_STEP
	pop	cx			; CH = type
	push	cx			; [sp] = type, [sp+2] = FORSLOT offset
	call	genPushVarPtr
	call	getNextSymbol
	jbe	gfo7x
	cmp	al,'='
	je	gfo1a
gfo7x:	jmp	gfo7
gfo1a:	call	genExpr			; initial value
	jbe	gfo7x
	call	gfoCvt
	jc	gfo7
	pop	cx
	push	cx
	push	ax
	mov	dx,offset setVarLong
	cmp	ch,VAR_DOUBLE
	jne	gfo2
	mov	dx,offset setVarDouble
gfo2:	mov	cx,dx
	GENCALL	cx			; set the loop variable
	pop	ax
	cmp	ah,CLS_KEYWORD		; TO?
	jne	gfo7
	cmp	al,TOK_TO
	jne	gfo7
	add	bx,size TOKLET		; consume TO
	call	genExpr			; limit
	jbe	gfo7
	call	gfoCvt
	jc	gfo7
	cmp	ah,CLS_KEYWORD		; STEP?
	jne	gfo3
	cmp	al,TOK_STEP
	jne	gfo7
	add	bx,size TOKLET		; consume STEP
	call	genExpr			; step
	jbe	gfo7
	call	gfoCvt
	jc	gfo7
	jmp	short gfo4
gfo3:	sub	dx,dx
	mov	cx,1
	call	genPushImmLong		; the default step is 1
	mov	dl,VAR_LONG
	call	gfoCvt
	jc	gfo7
gfo4:	pop	cx
	pop	si			; SI = FORSLOT offset
	pop	dx			; DX = FORSLOT segment
	push	dx
	push	si
	call	genPushImm		; push FORSLOT segment
	pop	dx
	push	dx
	call	genPushImm		; push FORSLOT offset
	GENCALL	forInit
	mov	ax,OP_OR_AX_DX
	stosw
	mov	ax,OP_JNZ_13
	stosw
	call	genJmp5			; JMP to NEXT (placeholder)
	pop	ax
	stosw				; FORSLOT offset
	pop	ax
	stosw				; FORSLOT segment
	mov	ax,CTL_FOR
	jmp	pushCtl
gfo7:	pop	cx
	pop	cx
	pop	cx
	stc
	ret
;
; gfoCvt converts the value (type DL) to the type of the loop variable (on
; the stack, underneath the return address), preserving AX.
;
gfoCvt:	push	ax
	push	bx
	mov	bx,sp
	mov	al,ss:[bx+7]		; AL = type (CH on the stack)
	pop	bx
	call	genCvtType
	pop	ax
	ret
ENDPROC	genFor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genNext
;
; Generate code for "NEXT [var[,var]...]", which looks like:
;
;	push	segment FORSLOT
;	push	offset FORSLOT
;	call	forNext
;	or	ax,dx
;	jz	next
;	jmp	body
;    next:
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
DEFPROC	genNext
gnx1:	call	findCtl			; DX:SI -> innermost FOR or WHILE
	cmp	ax,CTL_FOR		; is it a FOR?
	je	gnx1a			; yes
gnxE:	mov	al,BERR_NOFOR		; "NEXT without FOR"
	jmp	compError
gnx1a:	push	dx			; [sp+6] = block containing the FOR
	push	si			; [sp+4] = LBLREF offset
	push	ds
	mov	ds,dx
	mov	si,[si].LBL_IP		; SI = offset of body
	mov	ax,[si-6]		; AX = FORSLOT segment
	mov	cx,[si-8]		; CX = FORSLOT offset
	pop	ds
	push	ax			; [sp+2] = FORSLOT segment
	push	cx			; [sp] = FORSLOT offset
	mov	al,CLS_VAR
	call	getNextToken		; is there a loop variable?
	jbe	gnx3			; no
	cmp	ah,CLS_KEYWORD		; a keyword (eg, ELSE) instead?
	jne	gnx2			; no
	sub	bx,size TOKLET		; yes, so leave it for the caller
	jmp	short gnx3
gnx2:	and	ah,VAR_TYPE
	call	addVar			; DX:SI -> loop variable
	jc	gnx7
	push	es
	push	bx
	mov	bx,sp
	mov	es,ss:[bx+6]		; ES = FORSLOT segment
	mov	bx,ss:[bx+4]		; ES:BX -> FORSLOT
	cmp	si,es:[bx+2]		; is it the loop variable?
	jne	gnx6			; no
	cmp	dx,es:[bx+4]
gnx6:	pop	bx
	pop	es
	jne	gnx7			; no
gnx3:	mov	si,sp
	mov	dx,ss:[si+2]
	call	genPushImm		; push FORSLOT segment
	mov	si,sp
	mov	dx,ss:[si]
	call	genPushImm		; push FORSLOT offset
	GENCALL	forNext
	mov	ax,OP_OR_AX_DX
	stosw
	pop	ax
	pop	ax
	pop	si			; SI = LBLREF offset
	pop	dx			; DX = block containing the FOR
	mov	ax,OP_JZ_3		; JZ around a near JMP
	mov	cx,es
	cmp	cx,dx			; is the FOR in this block?
	je	gnx4			; yes
	mov	ax,OP_JZ_5		; no, so JZ around a far JMP
gnx4:	stosw
	push	es
	mov	es,dx
	mov	ax,es:[si].LBL_IP	; DX:AX -> body
	call	removeRef		; the FOR is done
	pop	es
	push	ax
	call	emitJmp			; jump back to the body
	pop	si
	sub	si,13			; DX:SI -> the FOR's JMP
	call	patchHere		; patch it to jump here
	call	getNextSymbol		; another variable (eg, "NEXT I,J")?
	jc	gnx9
	jz	gnx9			; no (carry clear)
	cmp	al,','
	jne	gnx8
	jmp	gnx1
gnx8:	stc
gnx9:	ret
;
; A NEXT whose variable isn't the innermost FOR's is also "NEXT without FOR".
;
gnx7:	pop	si
	pop	si
	pop	si
	pop	si
	jmp	gnxE
ENDPROC	genNext

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genWhile
;
; Generate code for "WHILE expr", which looks like:
;
;    top:
;	(push expr)
;	pop	ax
;	pop	dx
;	or	ax,dx
;	jnz	body
;	jmp	wend			; patched by genWend (5 bytes)
;	dd	top			; (for genWend)
;	dw	line #, position	; (see pushCtl)
;    body:
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
DEFPROC	genWhile
	push	es			; save address of top
	push	di
	call	genExpr
	jbe	gwh8
	call	genTestDouble		; (a double is true if it's non-zero)
	jc	gwh8
	mov	ax,OP_POP_DX_AX
	stosw
	mov	ax,OP_OR_AX_DX
	stosw
	mov	ax,OP_JNZ_13
	stosw
	call	genJmp5			; JMP to WEND (placeholder)
	pop	ax
	stosw				; top offset
	pop	ax
	stosw				; top segment
	mov	ax,CTL_WHILE
	jmp	pushCtl
gwh8:	pop	ax
	pop	ax
	stc
	ret
ENDPROC	genWhile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genWend
;
; Generate code for "WEND", which jumps back to the top of the WHILE.
;
; Inputs:
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genWend
	call	findCtl			; DX:SI -> innermost FOR or WHILE
	cmp	ax,CTL_WHILE		; is it a WHILE?
	je	gwe1			; yes
	mov	al,BERR_NOWHILE		; "WEND without WHILE"
	jmp	compError
gwe1:	push	es
	mov	es,dx
	mov	ax,es:[si].LBL_IP	; AX = offset of body
	call	removeRef		; the WHILE is done
	pop	es
	xchg	si,ax			; SI = offset of body
	push	ds
	mov	ds,dx
	mov	ax,[si-8]
	mov	cx,[si-6]		; CX:AX -> top
	pop	ds
	push	dx
	push	si
	mov	dx,cx
	call	emitJmp			; jump back to the top
	pop	si
	pop	dx
	sub	si,13			; DX:SI -> the WHILE's JMP
	call	patchHere		; patch it to jump here
	clc
	ret
ENDPROC	genWend

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genJmp5
;
; Generates a 5-byte placeholder for a JMP (near or far) whose target will be
; patched later (see patchHere).  The placeholder is a call to genMore, which
; generates more code until the placeholder has been patched, in case the
; program reaches it first (eg, a FOR that skips its loop before the NEXT has
; been generated).
;
; Inputs:
;	ES:DI -> code block
;
; Outputs:
;	DX = offset of the byte following the placeholder
;
; Modifies:
;	CX, DX, DI
;
DEFPROC	genJmp5
	GENCALL	genMore
	mov	dx,di
	ret
ENDPROC	genJmp5

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; emitJmp
;
; Generates a near JMP if the target is in the same code block, otherwise a
; far JMP.
;
; Inputs:
;	DX:AX -> target
;	ES:DI -> code block
;
; Outputs:
;	ES:DI updated (3 bytes for a near JMP, 5 bytes for a far JMP)
;
; Modifies:
;	AX, DI
;
DEFPROC	emitJmp
	push	cx
	mov	cx,es
	cmp	cx,dx			; is the target in this block?
	jne	ej1			; no
	sub	ax,di
	sub	ax,3			; AX = 16-bit displacement
	xchg	cx,ax
	mov	al,OP_JMP
	stosb
	xchg	cx,ax
	stosw
	jmp	short ej9
ej1:	push	dx
	call	codeSeg			; DX = target's code segment
	xchg	cx,ax
	mov	al,OP_JMPF
	stosb
	xchg	cx,ax
	stosw				; the offset of a far JMP
	xchg	ax,dx
	stosw				; and the segment
	xchg	ax,dx
	pop	dx
ej9:	pop	cx
	ret
ENDPROC	emitJmp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; patchJmp
;
; Inputs:
;	ES:SI -> 5-byte JMP placeholder
;	DX:AX -> target
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	patchJmp
	push	di
	mov	di,si
	call	emitJmp
	pop	di
	ret
ENDPROC	patchJmp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; patchHere
;
; Inputs:
;	DX:SI -> 5-byte JMP placeholder
;	ES:DI -> target (ie, the next unused location in the code block)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	patchHere
	push	es
	mov	ax,di
	mov	cx,es
	mov	es,dx			; ES:SI -> placeholder
	mov	dx,cx			; DX:AX -> target
	call	patchJmp
	pop	es
	ret
ENDPROC	patchHere

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genGosub
;
; Generate code for "GOSUB line", which looks like:
;
;	mov	ax,offset next
;	call	doGosub
;	jmp	line			; (see genGoto)
;    next:
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
DEFPROC	genGosub
	mov	al,OP_MOV_AX
	stosb
	push	di
	stosw				; (return offset, patched below)
	GENCALL	doGosub
	call	genGoto
	pop	si
	jc	gsb9
	mov	es:[si],di		; return offset
gsb9:	ret
ENDPROC	genGosub

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genOn
;
; Generate code for "ON expr GOTO line[,line]..." or "ON expr GOSUB ...",
; which looks like:
;
;	(push expr, converted to a long)
;	pop	ax
;	pop	dx
;	or	dx,dx
;	jz	$+5
;	jmp	next			; out of range
;	cmp	ax,1
;	jne	$+7 (or $+15)
;	(mov ax,offset next and call doGosub, if GOSUB)
;	jmp	line1
;	cmp	ax,2
;	...
;    next:
;
; Like MSBASIC, a value of zero, or a value greater than the number of lines,
; continues with the next statement.
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
DEFPROC	genOn
	mov	al,CLS_KEYWORD
	call	peekNextToken
	jbe	gonE
	cmp	al,TOK_ERROR		; ON ERROR?
	jne	gonE			; no
	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT	; consume ERROR
	mov	al,CLS_KEYWORD
	call	getNextToken
	jbe	gonX
	cmp	al,TOK_GOTO
	jne	gonX
;
; "ON ERROR GOTO 0" removes the handler; otherwise, generate a call to
; onError, followed by the JMP to the handler (which onError skips over).
;
	mov	al,CLS_DEC
	call	peekNextToken
	jbe	gonX
	DOSUTIL	ATOI32D			; DX:AX = line #
	or	ax,dx
	jnz	gonE1
	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT	; consume the zero
	GENCALL	offError
	clc
	ret
gonE1:	GENCALL	onError
	jmp	genGoto			; JMP line (always 5 bytes)

gonE:	call	genExpr
	ja	gon0
gonX:	stc
	ret
gon0:	push	ax
	mov	al,VAR_LONG
	call	genCvtType
	pop	ax
	jc	gonX
	cmp	ah,CLS_KEYWORD
	jne	gonX
	sub	cx,cx			; CL = 0 for GOTO
	cmp	al,TOK_GOTO
	je	gon1
	inc	cx			; CL = 1 for GOSUB
	cmp	al,TOK_GOSUB
	jne	gonX
gon1:	add	bx,size TOKLET		; consume GOTO or GOSUB
	mov	si,ds:[PSP_HEAP]
	mov	ax,[si].TOKLET_END
	sub	ax,bx			; AX = 4 * remaining tokens
	mov	dx,ax
	add	ax,ax
	add	ax,ax
	add	ax,dx			; AX = 20 * remaining tokens
	add	ax,CODE_ROOM
	call	ensureRoom		; make room for the entire statement
	jc	gonX
	mov	ax,OP_POP_DX_AX
	stosw
	mov	ax,OP_OR_DX_DX
	stosw
	mov	ax,OP_JZ_3
	stosw
	call	genJmp			; DX = offset following JMP to next
	push	dx
	push	cx			; CL = GOTO or GOSUB, CH = line #
	sub	ax,ax
	push	ax			; push list of return offsets to patch
gon2:	pop	si
	pop	cx
	inc	ch
	mov	al,OP_CMP_AX
	stosb
	mov	al,ch
	mov	ah,0
	stosw
	mov	ax,00575h		; JNE $+7 (around a 5-byte JMP)
	test	cl,cl
	jz	gon3
	mov	ax,00D75h		; JNE $+15 (around MOV, CALL, and JMP)
gon3:	stosw
	jz	gon4
	mov	al,OP_MOV_AX
	stosb
	mov	ax,si			; link this offset to the previous one
	mov	si,di
	stosw
	push	cx
	push	si
	GENCALL	doGosub
	pop	si
	pop	cx
gon4:	push	cx
	push	si
	call	genGoto			; JMP line (always 5 bytes)
	pop	si
	pop	cx
	jc	gon7
	push	cx
	push	si
	call	getNextSymbol		; another line?
	jc	gon6			; error
	jz	gon5			; no
	cmp	al,','
	je	gon2
gon6:	pop	si
	pop	cx
	jmp	short gon7
gon5:	pop	si
	pop	cx
gon5a:	test	si,si			; any more return offsets to patch?
	jz	gon5b			; no
	mov	ax,es:[si]
	mov	es:[si],di		; return offset
	xchg	si,ax
	jmp	gon5a
gon5b:	pop	si
	jmp	genPatch		; patch the JMP to next
gon7:	pop	si
	stc
	ret
ENDPROC	genOn

CODE	ENDS

	end
