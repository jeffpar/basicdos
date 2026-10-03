;
; BASIC-DOS Code Generator
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This is the core of the code generator: genCode generates (and runs) the
; code for a line or program, genCommands dispatches each command to its
; generator, and genExpr generates expressions (including operators and type
; conversions).  It also contains the token and code-emitting helpers that
; all the gen*.asm files share (eg, getNextToken, GENCALL's genCallCS, and
; GENPUSH's genPushImm); the label helpers (addLabel, findLabel) are in
; genflow.asm.
;
; Generates code for these commands:
;
;	DEF				(genDefFn: user-defined functions)
;	DEFDBL/DEFINT/DEFSNG/DEFSTR	(genDefDbl, genDefInt, genDefStr)
;	LET				(genLet)
;	All DOS commands		(genDOS, generates call to callDOS)
;
; The other gen*.asm files include:
;
;	gencon.asm			console I/O (CLS, COLOR, ECHO, PRINT)
;	gendef.asm			definitions (DIM, ERASE, OPTION BASE)
;					and array element references
;	genflow.asm			control (END, FOR/NEXT, GOSUB, GOTO,
;					IF/THEN/ELSE, ON, RETURN, WHILE/WEND)
;	genfpu.asm			floating-point support
;
	include	cmd.inc
	include	8086.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<allocCode,ensureRoom,shrinkCode,freeCode,freeAllCode>
	EXTNEAR	<addLabel>
	EXTNEAR	<allocVars,allocFunc,freeFunc>
	EXTNEAR	<allocTempVars,updateTempVars,freeTempVars>
	EXTNEAR	<addVar,getVar,removeVar,setVar,setVarLong,setVarDouble>
	EXTNEAR	<setStr,holdStr,swapArgs,compactStrs,genArrayRef,checkCtl>
	EXTNEAR	<memError>
	EXTNEAR	<callDOS,printLine>

	EXTWORD	<KEYWORD_TOKENS,KEYOP_TOKENS>
	EXTBYTE	<OPDEFS,RELOPS>
	EXTWORD	<EVAL_LONG,EVAL_STR>
	EXTLONG	<FPU_TABLE>
	EXTNEAR	<genCallFPU,genCallFPUDst,genCallFPUDst2>
	EXTNEAR	<genConstDouble,genCvtType,genFnCall,genPushSlot>
	EXTABS	<TOK_ABS,TOK_TAN>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCode
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
	LOCVAR	codeSeg,word		; code segment
	LOCVAR	defVarSeg,word		; default VBLK segment
	LOCVAR	defType,byte		; used by genDefInt, etc.
	LOCVAR	pCode,dword		; original start of generated code
	ENTER

	mov	[codeSeg],cs
	test	al,GEN_BATCH
	jz	gc1
	or	al,GEN_ECHO
gc1:	mov	[bx].GEN_FLAGS,al

	sub	cx,cx
	mov	[bx].ERR_CODE,cl
	mov	[bx].LINE_NUM,cx
	mov	dx,ds
	test	si,si
	jnz	gc2
	mov	dx,[bx].TBLKDEF.BLK_NEXT
	test	dx,dx			; anything to run?
	jnz	gc1a			; yes
	jmp	gc9			; no (TODO: display a message?)
gc1a:	mov	si,size TBLK
gc2:	mov	[bx].LINE_PTR.OFF,si
	mov	[bx].LINE_PTR.SEG,dx
	mov	[bx].LINE_LEN,cx	; CX = previous length (0)

	call	allocVars
	jc	gce
	mov	ax,[bx].VBLKDEF.BLK_NEXT
	mov	[defVarSeg],ax		; save the first (default) VBLK segment
	call	allocCode
	jc	gce
	ASSUME	ES:NOTHING		; ES:DI -> code block
	mov	[pCode].OFF,di
	mov	[pCode].SEG,es

	mov	ax,OP_MOV_BP_SP		; make it easy for endProgram
	stosw				; to reset the stack and return

gc4:	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a line
	jc	gc4x
	call	getNextLine
	cmc
	jnc	gc6
	call	genCommands		; generate code
	jnc	gc4

gc6:	push	ss
	pop	ds
	ASSUME	DS:DATA
	jc	gc7
	call	checkCtl		; any FOR without NEXT (etc)?
	jc	gc7			; yes
	mov	al,OP_RETF		; terminate the code in the buffer
	stosb
;
; The memory model for the generated code is simple: CS is the current
; code block, SS is the heap, DS is the first var block, and ES is scratch.
;
	push	bp
	push	ds
	mov	ds,[defVarSeg]
	ASSUME	DS:NOTHING
	call	[pCode]			; execute the code buffer
	pop	ds
	ASSUME	DS:DATA
	pop	bp
	clc

gc7:	pushf
	call	freeAllCode
	call	compactStrs		; free any leftover temp strings
	popf
gc8:	jnc	gc9

	mov	bx,ds:[PSP_HEAP]
	PRINTF	<"Syntax error in line %d",13,10>,[bx].LINE_NUM
	stc
	jmp	short gc9

gce:	call	memError

gc9:	LEAVE
	ret

gc4x:	call	memError		; no room for code, so skip execution
	clc
	jmp	gc7
ENDPROC	genCode

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
	jc	gcs9
	mov	dx,bx			; DX -> TOKLETs (for implicit LET)
	mov	al,CLS_KEYWORD
	call	getNextToken
	jb	gcs0
	je	gcs9			; out of tokens
	mov	cx,cs:[si].CTD_FUNC	;
	cmp	al,KEYWORD_BASIC	; BASIC keyword?
	jb	gcs2			; no
	jcxz	gcs8			; no command address
	jmp	short gcs3		; call generator function
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
gcs1b:	sub	ax,ax			; call genDOS w/o an ID
;
; For non-BASIC keywords, generate callDOS code with a pointer to the
; full command-line and the keyword handler.  callDOS will then perform
; the traditional parse-and-execute logic.
;
gcs2:	cbw				; AX = keyword ID
	mov	dx,cx			; DX = handler address
	mov	cx,offset genDOS

gcs3:	call	cx			; call dedicated generator function
	mov	es:[BLK_FREE],di
	jnc	genCommands
	ret
;
; A keyword with no generator (eg, ELSE) ends the commands, and we leave it
; for the caller (eg, genIf), returning AX = CLS_KEYWORD and the keyword ID.
;
gcs8:	sub	bx,size TOKLET		; (this clears carry, too)
gcs9:	ret
ENDPROC	genCommands

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
	mov	cx,[si].LINE_LEN
	sub	cx,ax
	push	ax
	GENPUSH	cx			; push length of command line
	mov	cx,[si].LINE_PTR.OFF
	pop	ax
	add	cx,ax
	mov	dx,[si].LINE_PTR.SEG	; DX:CX -> command line
	GENPUSH	dx,cx			; push pointer to command line
	GENCALL	callDOS
	mov	[si].TOKLET_END,bx	; mark the tokens fully processed
	ret
ENDPROC	genDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDefFn
;
; Generate code for "DEF fn(parms)=expr".
;
; We rely on genExpr to generate the code for "expr", which requires us to
; create a temp var block containing all the variables in "parms", so when
; genExpr calls findVar (via addVar), it searches the temp var block first.
;
; Note that we do NOT require the function name to begin with "FN" like
; MSBASIC does.
;
; TODO: We must allow DEF to redefine a function that already exists, hence
; the call to removeVar.  However, all removeVar does is mark the existing var
; data as DEAD, and addVar doesn't currently reuse DEAD space, so memory usage
; could grow without limit until we've implemented some cleanup code.
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
DEFPROC	genDefFn
	LOCVAR	segVars,word
	LOCVAR	fnParms,byte
	LOCVAR	fnType,byte
	LOCVAR	fnBlock,byte
	LOCVAR	fnNameLen,word
	LOCVAR	fnNameOff,word
	LOCVAR	fnParmOff,word
;
; Unlike other "gen" functions, if this function generates anything, it
; goes into a new code block, not the current code block, so we save and
; restore ES:DI before the ENTER and after LEAVE (since we depend on LEAVE
; to "CLEANUP" any data left on the stack in the event of an error).
;
	mov	es:[BLK_FREE],di
	push	es
	push	di
	ENTER

	mov	si,ds:[PSP_HEAP]
	test	[si].GEN_FLAGS,GEN_DEF
	jnz	gd1x			; nested DEF fn not allowed
	or	[si].GEN_FLAGS,GEN_DEF

	mov	al,CLS_VAR
	call	getNextToken
	jbe	gd1x
	and	ah,VAR_TYPE		; convert CLS_VAR_* to VAR_*
;
; We're going to save the VAR_FUNC var info on the stack until we have a
; complete description for addVar; we already have the return type (AH), but
; we also need the parameter count and the generated code for the expression.
;
	sub	dx,dx
	mov	[segVars],dx
	mov	[fnType],ah
	mov	[fnBlock],1
	mov	[fnParms],dl
	mov	[fnNameLen],cx
;
; Copy the function name onto the stack, because if this is a function block,
; the buffer containing the name will be overwritten before we can call addVar.
;
	inc	cx
	and	cl,NOT 1		; increase length to next EVEN value
	sub	sp,cx
	mov	di,sp			; ES:DI is available for reuse
	mov	[fnNameOff],di
	push	ss			; since we saved them on entry above
	pop	es
	rep	movsb
;
; The parameter list is next, and it's optional.
;
	call	getNextSymbol
	jbe	gd3			; assume it's a block
	dec	[fnBlock]		; switch assumption to non-block
	cmp	al,'='
	je	gd3			; no parameters
	cmp	al,'('
	jne	gd1x			; command appears to be invalid
;
; Allocate a temp var block and then work through all the parameters.
;
	call	allocTempVars		; returns original var block in DX
	mov	[segVars],dx

	sub	dx,dx			; DX = parm offset
	mov	[fnParmOff],sp		; top of parm info on stack
gd1:	mov	al,CLS_VAR
	call	getNextToken
	jz	gd1x			; ran out of parameters
	jb	gd2
	mov	dl,ah
	and	dl,VAR_TYPE		; DL = parm type
	mov	ah,VAR_PARM
	inc	dh
	jz	gd1x			; too many parameters
	push	dx
	call	addVar
	pop	ax
	push	ax
	jc	gd1x			; unable to add the parameter
;
; AX contains the parm info that was in DX prior to calling addVar
; (AL = parm type, AH = parm offset).  Store AX in the var data (DX:SI).
;
	inc	[fnParms]
	call	setVar
	xchg	dx,ax			; restore DX (done with the var data)
	call	getNextSymbol
	jbe	gd1x
	cmp	al,','
	je	gd1
	cmp	al,')'
	je	gd2
gd1x:	jmp	short gd3x

gd2:	inc	[fnBlock]		; revert to block assumption
	call	getNextSymbol
	jbe	gd2a			; no symbols, assumption is good
	dec	[fnBlock]		; more symbols, so revert to non-block
	cmp	al,'='			; expression to follow?
	jne	gd3x			; no
;
; Time to add the original var block(s) back to the chain, so that genExpr
; has access to both the parameter variables we just added and all globals.
;
gd2a:	mov	dx,[segVars]
	call	updateTempVars
;
; Similar to what we did with allocTempVars (if there was a parameter list),
; we call allocFunc to create a fresh code buffer for genExpr.
;
gd3:	call	allocFunc
	jc	gd3x
	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a line
	jc	gd3x

	push	di
	IFDEF	MAXDEBUG
	mov	ax,OP_INT06
	stosw
	mov	al,OP_INT03
	stosb
	ENDIF
	mov	al,OP_PUSH_BP
	stosb
	mov	ax,OP_MOV_BP_SP
	stosw
;
; At this point, if we're defining a "function expression", then all we
; do is call genExpr.  Otherwise, if we're defining a "function block", then
; we must call genCommands and getNextLine in a loop until we encounter a
; RETURN command.
;
	mov	si,ds:[PSP_HEAP]
	mov	al,[fnParms]		; set DEF_PARMS in case
	mov	[si].DEF_PARMS,al	; genExpr encounters any VAR_PARMs
	mov	al,[fnType]		; and DEF_TYPE for genReturn
	mov	[si].DEF_TYPE,al

	cmp	[fnBlock],0		; function expression?
	jne	gd3a			; no
	call	genExpr			; yes
	jc	gd3x
	mov	al,[fnType]
	call	genCvtType		; convert to the function's type
	jnc	gd3c
gd3x:	jmp	gd8

gd3a:	push	si
	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a line
	jc	gd3b
	call	getNextLine		; function block
	jc	gd3b			; ran out of lines before RETURN
	call	genCommands		; generate some code
gd3b:	pop	si
	jc	gd3x
	test	[si].GEN_FLAGS,GEN_DEF	; did a RETURN clear GEN_DEF?
	jnz	gd3a			; not yet
;
; genExpr generates code that leaves the result on the stack, so to wrap up
; this function call, we must generate code that pops that result into the
; return variable on the stack (which genFuncExpr allocated prior to the call).
;
; Since doubles are always passed by reference, the return variable of a
; VAR_DOUBLE function is a pointer to a slot in the caller's code block, so
; we generate code that copies the result to the slot (with setVarDouble).
;
gd3c:	mov	cl,[fnParms]
	mov	ch,0
	add	cx,cx
	add	cx,cx
	add	cx,6			; CX = offset of the return variable
	cmp	[fnType],VAR_DOUBLE
	jne	gd3e
	mov	ax,OP_POP_DX_AX		; DX:AX -> result
	stosw
	inc	cx
	inc	cx
	call	genPushBPOffset		; push the return variable (a pointer
	dec	cx			; to the caller's slot)
	dec	cx
	call	genPushBPOffset
	mov	ax,OP_PUSH_DX OR (OP_PUSH_AX SHL 8)
	stosw				; push the pointer to the result
	push	cx
	GENCALL	setVarDouble
	pop	cx
	inc	cx
	inc	cx
	jmp	short gd3f
gd3e:	call	genPopBPOffset
	inc	cx
	inc	cx
	call	genPopBPOffset
gd3f:	mov	ax,OP_POP_BP OR (OP_RETF_N SHL 8)
	stosw
	sub	cx,8
	xchg	ax,cx
	stosw
	call	shrinkCode
;
; ES contains the generated code, so we're ready to add the VAR_FUNC now.
; But first, call freeTempVars and restore var block to its original state,
; if we allocated a temp block for parameters.
;
	cmp	[segVars],0
	je	gd3d
	call	freeTempVars
gd3d:	mov	cx,[fnNameLen]
	mov	si,[fnNameOff]		; DS:SI -> function name on stack
	mov	ah,VAR_FUNC
	call	removeVar		; remove any existing function var
	jc	gd7			; error (predefined)
	mov	ah,VAR_FUNC
	mov	al,[fnParms]
	call	addVar			; add new function var
	jc	gd7			; error (eg, out of memory)
;
; DX:SI -> VAR_FUNC var data.  Set the function return type and # parameters,
; followed by each of the parameters types and offsets.
;
	mov	di,[fnParmOff]		; DI = top of parm info on stack
	mov	ax,word ptr [fnType]
gd4:	call	setVar
	dec	[fnParms]
	jl	gd5
	dec	di
	dec	di
	mov	ax,[di]			; AH = parm offset
	mov	ah,PARM_REQUIRED	; which we replace with parm flags
	jmp	gd4

gd5:	pop	di			; ES:DI -> generated code
	mov	ax,di
	call	setVar
	mov	ax,es
	call	setVar			; function address updated
	clc
	jmp	short gd9

gd7:	call	freeFunc		; on error, free the code block in ES
;
; Error paths converge here.  Even if parameter info is still pushed on the
; stack, the LEAVE macro automatically cleans up the stack.
;
gd8:	stc
gd9:	pushf
	mov	si,ds:[PSP_HEAP]	; the DEF is no longer in progress
	and	[si].GEN_FLAGS,NOT GEN_DEF
	popf
	LEAVE	CLEANUP
	pop	di
	pop	es
	RETURN
ENDPROC	genDefFn

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
	mov	[defType],VAR_LONG

	DEFLBL	genDefVar,near
	call	getCharToken		; check for char
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
; For every letter from DL through DH, set DEFVARS[DL] to defType.
;
gdi3:	push	bx
	mov	cl,dh
	sub	cl,dl
	mov	ch,0
	inc	cx			; CX = # of letters to set
	mov	al,[defType]		; AL = new default for each letter
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
	jbe	gdi9
	cmp	al,','
	je	genDefVar

gdi8:	stc
gdi9:	ret

	DEFLBL	getCharToken,near
	mov	al,CLS_VAR		; token must be CLS_VAR
	call	getNextToken
	jbe	gdi8
	dec	cx
	jnz	gdi8			; and it must have a length of 1
	inc	cx
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
	mov	[defType],VAR_DOUBLE
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
	mov	[defType],VAR_STR
	jmp	genDefVar
ENDPROC	genDefStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genExpression (aka genExpr)
;
; Generate code for an expression.
;
; The code block at ES:DI serves as the operand queue, the stack at SP serves
; as the operator stack, and with VAR_LONG operands being joined by VAR_DOUBLE
; and VAR_STR operands, we must now maintain a type stack (typeStack) as well.
;
; Unlike the stack at SP, the type stack grows upward; the top of the stack
; (typeTop) starts at zero and is incremented as type values are "pushed"
; (as operands are queued) and decremented as type values are "popped" (as
; operators are processed).
;
; At the end, the type stack must have a single value, representing the type
; of the entire expression, and the open parentheses count (exprParens) must be
; zero.
;
; Expression generation stops when we run out of tokens or detect consecutive
; non-operator symbols.
;
; Inputs:
;	DS:BX -> next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	AX = last result from getNextToken (a keyword that ends the expression,
;	such as THEN or ELSE, is NOT consumed, so the caller can process it)
;	DL = expression type, DH = # tokens
;	CF clear if successful, set if error
;	ZF clear if expression existed, set if not
;	ES:DI -> next unused location in code block
;
; Modifies:
;	AX, BX, DX, DI
;
DEFPROC	genExpr
	LOCVAR	exprToks,byte
	LOCVAR	exprParms,byte
	LOCVAR	exprParens,word
	LOCVAR	exprPrevOp,word
	LOCVAR	typeTop,word		; top (offset) of types in typeStack
	LOCVAR	typeStack,byte,32	; arbitrarily limited to 32
	ENTER
	push	cx
	push	si
	mov	si,ds:[PSP_HEAP]
	mov	al,[si].DEF_PARMS
	mov	[exprParms],al		; parm count (only from genDefFn)
	sub	dx,dx
	mov	[exprToks],dl		; zero total tokens
	mov	[exprParens],dx		; zero open parentheses
	mov	[exprPrevOp],dx		; zero previous operator (none)
	mov	[typeTop],dx		; type stack initially empty
	push	dx			; push end-of-operators marker (zero)
	jmp	short ge1
ge0x:	jmp	ge8
ge0y:	stc				; out of room (see ensureRoom)
	jmp	ge9a

ge1:	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a token
	jc	ge0y
	mov	al,CLS_ANY		; CLS_NUM, CLS_SYM, CLS_VAR, CLS_STR
	call	getNextToken
	jbe	ge0x
	inc	[exprToks]
	cmp	ah,CLS_SYM		; symbol? (20h)
	je	ge1b			; process CLS_SYM below
;
; Non-operator (non-symbol) cases: keywords, variables, strings, and numbers.
;
	cmp	ah,CLS_KEYWORD		; keyword? (30h)
	jne	ge1c			; no
	jmp	ge1k			; yes (see if it's a function)
ge1c:
	cmp	byte ptr [exprPrevOp],-1
	je	ge1x
	mov	byte ptr [exprPrevOp],-1; invalidate prevOp (intervening token)
	cmp	ah,CLS_VAR		; variable with type? (10h)
	ASSERT	NE			; (type should be fully qualified now)
	ja	ge2			; yes
;
; Must be CLS_STR or CLS_NUM.  Handle CLS_STR here and CLS_NUM below.
;
	test	ah,CLS_STR		; string? (08h)
	jz	ge3			; no, must be number
	mov	dl,VAR_STR		; DL = VAR_STR (60h)
	call	pushType		; push operand type
	sub	cx,2			; CX = string length
	ASSERT	NC
	jcxz	ge1a			; empty string
	mov	ax,cx
	add	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for the string
	jc	ge0y
	inc	si			; DS:SI -> string contents
	call	genPushStr
	jmp	ge1

ge1a:	sub	cx,cx			; for empty strings, push null ptr
	sub	dx,dx
	call	genPushImmLong
	jmp	ge1
ge1b:	jmp	ge4

ge1x:	dec	[exprToks]		; rewind to unexpected symbol
	sub	bx,size TOKLET
	jmp	short ge2x
;
; Process CLS_VAR_*.  Instead of calling findVar, we now call addVar,
; because variables can be referenced before they're defined, so missing
; variables must be created on first reference; addVar still gives findVar
; first crack at locating the variable.
;
; Note that var type (AH) must also be consistent with expression type.
;
ge2:	and	ah,NOT CLS_VAR		; convert AH from CLS_VAR_* to VAR_*
	mov	al,0			; ARRAY_VAL
	call	genArrayRef		; array element?
	jc	ge2x			; error
	jnz	ge2d			; yes (AH = element type)
	call	addVar
	cmp	ah,VAR_PARM		; parameter? (20h)
	jne	ge2a			; no
;
; VAR_PARM variables are present only in temp var blocks created by genDefFn,
; so genDefFn must have called us with a parameter count.
;
	mov	cl,[exprParms]
	call	genFuncParm
	jmp	short ge2b

ge2a:	cmp	ah,VAR_FUNC		; function? (C0h)
	jne	ge2c
	call	genFuncExpr		; process the function expression
ge2b:	jnc	ge2d			; AH = return type
ge2x:	jmp	short ge3x

ge2c:	cmp	ah,VAR_DOUBLE		; doubles are always pushed
	jne	ge2e			; by reference
	push	ax
	call	genPushVarPtr
	pop	ax
	jmp	short ge2d
ge2e:	call	genPushVarLong

ge2d:	mov	dl,ah			; DL = var type
	call	pushType		; update expression type
	jmp	ge1
;
; Process CLS_NUM.  Number is a constant and CX is its exact length.
;
; TODO: If the preceding character is a '-' and the top of the operator stack
; is 'N' (unary minus), consider decrementing SI and removing the operator.
; Why? Because it's better for ATOI32 to know up front that we're dealing with
; a negative number, because then it can do precise overflow checks.
;
ge3:	cmp	ah,CLS_FLOAT		; floating-point constant?
	je	ge3f			; yes
	mov	dl,VAR_LONG		; DL = VAR_LONG
	call	pushType		; update expression type
	push	bx
	mov	bl,10			; BL = 10 (default base)
	cmp	ah,CLS_OCT OR CLS_HEX	; octal or hex value?
	ja	ge3a			; no
	inc	si			; yes, skip leading ampersand
	shl	ah,1
	shl	ah,1
	shl	ah,1
	mov	bl,ah			; BL = 8 or 16 (new base)
	cmp	byte ptr [si],'9'	; is next character a digit?
	jbe	ge3a			; yes
	inc	si			; no, skip it (must be 'O' or 'H')
ge3a:	DOSUTIL	ATOI32			; DS:SI -> numeric string (length CX)
	xchg	cx,ax			; save result in DX:CX
	pop	bx
	GENPUSH	dx,cx
	jmp	ge1			; go count another queued value
ge3x:	jmp	ge8
;
; Process CLS_FLOAT (see genConstDouble).
;
ge3f:	call	genConstDouble		; DS:SI -> numeric string
	jc	ge3x			; conversion error
	mov	dl,VAR_DOUBLE
	call	pushType		; update expression type
	jmp	ge1
;
; Process numeric function keywords (TOK_ABS through TOK_TAN), which take
; one parenthesized argument and call the corresponding FPU$ function, so the
; argument is converted to a double if necessary, and so is the result.  Any
; other keyword ends the expression (eg, THEN).
;
ge1k:	cmp	al,TOK_ABS
	jb	ge1kx
	cmp	al,TOK_TAN
	ja	ge1kx
	cmp	byte ptr [exprPrevOp],-1; preceded by an operand?
	je	ge1kx			; yes, so the expression is over
	mov	byte ptr [exprPrevOp],-1
	call	genFnCall		; generate the function call
	jc	ge3x
	mov	dl,VAR_DOUBLE
	call	pushType		; update expression type
	jmp	ge1
ge1kx:	jmp	ge1x
;
; Process CLS_SYM.  Before we try to validate the operator, we need to remap
; binary minus to unary minus.  So, if we have a minus, and the previous token
; is undefined, or another operator, or a left paren, it's unary.  Ditto for
; unary plus.  The internal identifiers for unary '-' and '+' are 'N' and 'P'.
;
ge4:	mov	ah,'N'
	cmp	al,'-'
	je	ge4a
	mov	ah,'P'
	cmp	al,'+'
	jne	ge5
ge4a:	mov	cx,[exprPrevOp]
	jcxz	ge4b
	cmp	cl,')'			; do NOT remap if preceded by ')'
	je	ge5
	cmp	cl,-1			; another operator (including '(')?
	je	ge5			; no
ge4b:	mov	al,ah			; remap the operator
;
; Verify that the symbol is a valid operator.
;
ge5:	call	validateOp		; AL = operator to validate
	jc	ge7b			; error (reset AH to CLS_SYM)
	mov	[exprPrevOp],ax
	sub	si,si
	jcxz	ge7			; handle no-arg operators below
	mov	si,dx			; SI = current operator index
;
; Operator is valid, so peek at the operator stack and pop if the top
; operator precedence >= current operator precedence.  However, unary
; operators (odd precedence) are prefixes, so they can't apply to anything
; already on the stack (eg, in "2^-2", the unary minus must not pop the '^').
;
	test	ah,1			; unary operator?
	jnz	ge6a			; yes, so just push it
ge5a:	pop	dx			; "peek"
	cmp	dh,ah			; top precedence > current?
	jb	ge6			; no
	ja	ge5b			; yes
	test	dh,1			; unary operator?
	jnz	ge6			; yes, hold off
ge5b:	pop	cx			; pop the operator index as well
	jcxz	ge6c			; no operator index (eg, left paren)
	call	genOp
	jmp	ge5a

ge6:	push	dx			; "unpeek"
ge6a:	push	si			; push current operator index
	push	ax			; push current operator/precedence
ge6b:	jmp	ge1			; next token
;
; We just popped an operator with no evaluator; if it's a left paren,
; we're done; otherwise, ignore it (eg, unary '+').
;
ge6c:	cmp	dl,'('
	je	ge6b
	jmp	ge5a
;
; When special (eg, zero arg) operators are encountered in the expression,
; they are handled here.
;
ge7:	cmp	al,'('
	jne	ge7a
	inc	[exprParens]
	jmp	ge6a
;
; When parsing one in a series of comma-delimited expressions, all of which
; may be parenthesized, we must treat the closing parenthesis no differently
; than the commas.
;
ge7a:	ASSERT	Z,<cmp al,')'>
	dec	[exprParens]
	jge	ge5a
	mov	[exprParens],0		; don't treat this as an error
ge7b:	mov	ah,CLS_SYM
;
; We have reached the (presumed) end of the expression, so start popping
; the operator stack.
;
ge8:	pop	cx
	jcxz	ge9			; all done
	mov	dx,cx
	pop	cx			; CX = operator index
	call	genOp
	jmp	ge8
;
; Verify that a single type remains on typeStack, and no open parentheses.
;
ge9:	cmp	[typeTop],1
	stc
	jne	ge9a
	add	[exprParens],-1		; if exprParens is NOT zero
	jc	ge9a			; then adding -1 will force carry set
	call	popType			; DL = expression type
ge9a:	mov	dh,[exprToks]		; DH = # tokens
	pop	si
	pop	cx
	LEAVE
	RETURN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pushType (genExpr internal function)
;
; Inputs:
;	DL = VAR_*
;
; Outputs:
;	typeTop incremented
;
; Modifies:
;	flags
;
	DEFLBL	pushType,near
	push	si
	mov	si,[typeTop]
	ASSERT	B,<cmp si,32>		; TODO: deal with possible overflow
	mov	[typeStack][si],dl
	inc	si
	mov	[typeTop],si
	pop	si
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; popType (genExpr internal function)
;
; Inputs:
;	None
;
; Outputs:
;	ZF clear and DL = VAR_* (ZF set if no type exists)
;
; Modifies:
;	DL, flags
;
	DEFLBL	popType,near
	push	si
	mov	si,[typeTop]
	test	si,si
	jz	pt9			; return ZF set if stack empty
	lea	si,[si-1]		; decrement without altering flags
	mov	dl,[typeStack][si]
	mov	[typeTop],si
pt9:	pop	si
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genOp (genExpr internal function)
;
; Pop N types (where N is 2 if the operator precedence is even and 1 if odd)
; from the type stack, push the operator's new type, and generate code for the
; operator's evaluator.
;
; Some type mismatches are automatic errors (eg, whenever one type is VAR_STR,
; as strings can only operate with other strings).  All other mismatches are
; necessarily between VAR_LONG and VAR_DOUBLE, and whether the int should be
; converted to a float or vice versa depends on the operator.
;
; For example, all arithmetic and relational operators must "promote" ints
; to floats, with the exception of '\' (integer division) and MOD, which must
; "demote" floats to ints.  Ditto for logical operators (and shift operators).
; Demotion means rounding to the nearest 32-bit integer (eg, 7.5 becomes 8,
; -7.4 becomes -7).
;
; Some type matches are also automatic errors (eg, when the types are VAR_STR
; and the operator is neither "+" nor relational).  However, there's no special
; logic for that; the error is indicated by a zero evaluator (see EVAL_STR).
;
; Inputs:
;	CX = operator index (OPEVAL_*)
;	DL = operator symbol (from OPDEFS)
;	DH = operator precedence (from OPDEFS)
;
; Outputs:
;	Carry clear if successful, set if error (ie, type mismatch)
;
; Modifies:
;	CX, DX, DI
;
	DEFLBL	genOp,near
	IFDEF MAXDEBUG
	DPRINTF	'o',<"op %c, func @%08lx\r\n">,dx,cx,cs
	ENDIF
	jcxz	go2x			; jump if no operator index

	push	si
	push	ax
	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for an op
	pop	ax
	jnc	go0
	jmp	go8x
go0:	call	popType
	jz	go3x			; exit if error
	test	dh,1
	mov	dh,dl			; DH = type of 2nd arg pushed
	jnz	go1
	call	popType			; DL = type of 1st arg pushed
	jz	go3x			; exit if error

go1:	cmp	dl,dh			; type mismatch?
	jne	go3			; yes, handle below
	cmp	dl,VAR_STR
	jne	go2
	cmp	cl,OPEVAL_ADD		; adding two strings produces string
	je	go8a
	jmp	short go8		; all other string ops return integers
;
; The types match, so if they're both integer, there's nothing else to do.
; If they're both float, operators NOT and above require demotion to integer.
;
go2:	cmp	dh,VAR_LONG
	jne	go2a
;
; Like MSBASIC, "/" and "^" always produce floating-point results, so both
; integers must be promoted ("\" is integer division), unless there's no FPU$
; driver, in which case they're integer operations.
;
	cmp	word ptr cs:[FPU_TABLE].SEG,0
	je	go8a
	cmp	cl,OPEVAL_DIV
	je	go2b
	cmp	cl,OPEVAL_EXP
	jne	go8a
go2b:	push	cx
	mov	cx,FPU_CVT2LD
	call	genCallFPUDst2
	jmp	short go3d
go2a:	cmp	cl,OPEVAL_NOT
	jb	go8a
	push	cx
	mov	cx,FPU_CVT1DL
	je	go3c
	mov	cx,FPU_CVT2DL
	jmp	short go3c
go2x:	jmp	short go9
;
; Deal with type mismatches here.
;
go3:	cmp	dl,VAR_STR		; if the 1st arg...
	je	go8x
	cmp	dh,VAR_STR		; or the 2nd arg are strings
go3x:	je	go8x			; then it's a guaranteed type mismatch
;
; A float and an int walk into a bar.  If the bar is "NOT" or above,
; the float must be demoted to int.  Otherwise, the int must be promoted.
;
	push	cx
	cmp	cl,OPEVAL_NOT
	jae	go3b
	cmp	dl,VAR_LONG
	mov	cx,FPU_CVTL1D
	jne	go3a
	mov	cx,FPU_CVTL2D
go3a:	call	genCallFPUDst
go3d:	pop	cx
	jc	go8x
	mov	dx,VAR_DOUBLE OR (VAR_DOUBLE SHL 8)
	jmp	short go8a

go3b:	cmp	dl,VAR_DOUBLE
	mov	cx,FPU_CVTD1L
	jne	go3c
	mov	cx,FPU_CVTD2L
go3c:	call	genCallFPU
	pop	cx
	jc	go8x
	mov	dx,VAR_LONG OR (VAR_LONG SHL 8)
	jmp	short go8a

go8:	mov	dl,VAR_LONG
;
; At this point, DL is the result type and DH is the (possibly promoted)
; input(s) type.  The latter indicates which table the evaluator comes from.
;
go8a:	cmp	dh,VAR_DOUBLE		; relational operators (OPEVAL_EQ and
	jne	go8f			; above) on doubles produce longs
	cmp	cl,OPEVAL_EQ
	jb	go8f
	mov	dl,VAR_LONG
go8f:	call	pushType		; DL = type to push
	jcxz	go8x			; no evaluator implies an error
	dec	cx
	add	cx,cx			; CX = evaluator table offset
	mov	si,offset EVAL_LONG
	cmp	dh,VAR_LONG
	je	go8b
	cmp	dh,VAR_DOUBLE
	je	go8d
	mov	si,offset EVAL_STR
go8b:	add	si,cx
	mov	cx,cs:[si]
	GENCALL	cx			; generate call to operator evaluator
	jmp	short go8c		; (GENCALL also clears carry)
;
; Since FPUTBL begins with entries for OPEVAL_NEG through OPEVAL_GE, CX is
; also the FPUTBL offset of the evaluator.  And since operators above
; OPEVAL_GE always demote doubles to longs, CX will never be any larger.
; Operators below OPEVAL_EQ produce doubles, so they require a result slot.
;
go8d:	cmp	cx,FPU_EQ		; does the operator produce a double?
	jae	go8e			; no
	call	genCallFPUDst
	jmp	short go8c
go8e:	call	genCallFPU
	jmp	short go8c
go8x:	stc
go8c:	pop	si
go9:	ret

ENDPROC	genExpr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genFuncExpr
;
; Generate code for "func(parm1,parm2,...)".  The func variable has already
; been parsed and DX:SI has been set to the corresponding function data.
;
; NOTE: Function data for predefined functions is actually at CS:SI, but
; since we must also support user-defined functions, we can't assume that.
; This is why we must use the loadFuncData helper function, instead of simple
; LODSW CS: instructions.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;	DX:SI -> function data
;
; Outputs:
;	Carry clear if successful, AH = return type
;
; Modifies:
;	Any
;
DEFPROC	genFuncExpr
	LOCVAR	nFuncParms,byte
	LOCVAR	nFuncType,byte
	LOCVAR	pFuncData,dword
	ENTER
	sub	cx,cx			; CX = 0 if no parms supplied
	mov	[pFuncData].OFF,si
	mov	[pFuncData].SEG,dx
	call	loadFuncData
	mov	word ptr [nFuncType],ax	; nFuncType = AL, nFuncParms = AH
;
; NOTE: peekNextSymbol can "fail" for any number of reasons, including
; the fact that not all operators that may follow an unparenthesized function
; reference are symbols (eg, "MOD").  So we must be very forgiving here.
;
	call	peekNextSymbol		; check for parenthesis
	jbe	gfe0
	cmp	al,'('
	jne	gfe0
	inc	cx			; CX = 1 if one or more parms supplied
	call	getNextSymbol		; consume the parenthesis
;
; For VAR_LONG functions, the generated stack frame needs to begin with room
; for a VAR_LONG return value; we use genPushLong instead of genPushZeroLong
; because it generates less code AND it doesn't matter what value gets pushed.
; For VAR_DOUBLE functions, the return value is a pointer to a slot in our
; code block, where the function will store its result.
;
gfe0:	cmp	[nFuncType],VAR_DOUBLE
	jne	gfe0a
	push	cx
	call	genPushSlot
	pop	cx
	jmp	short gfe1
gfe0a:	call	genPushLong

gfe1:	dec	[nFuncParms]		; more parameters?
	jl	gfe6			; no
	jcxz	gfe3			; yes, but no (more) have been supplied

	call	genExpr			; process parameter expression
	jbe	gfe3			; no value supplied

	push	ax			; save last symbol from genExpr
	call	loadFuncData		; AL = parameter type
	cmp	al,VAR_LSKIP		; optional VAR_LONG we can skip?
	jne	gfe1b			; no
	mov	al,VAR_LONG
	cmp	dl,VAR_STR		; was a string supplied instead?
	jne	gfe1b			; no
	push	cx
	push	dx
	mov	al,ah
	cbw
	cwd
	xchg	cx,ax			; DX:CX = default value
	call	genPushImmLong		; push the default value
	GENCALL	swapArgs		; and move it below the string
	pop	dx
	pop	cx
	dec	[nFuncParms]		; the string is the next parameter
	call	loadFuncData		; AL = its type
;
; A string passed to a user-defined function must be held (see holdStr),
; since the function may use its parameter more than once.
;
gfe1b:	cmp	al,VAR_STR		; string parameter?
	jne	gfe1c			; no
	mov	si,cs
	cmp	[pFuncData].SEG,si	; for a user-defined function?
	je	gfe1c			; no
	push	cx
	push	dx
	GENCALL	holdStr
	pop	dx
	pop	cx
gfe1c:	push	cx
	call	genCvtType		; convert to the parameter type
	pop	cx
	pop	ax			; restore last symbol
	jc	gfe9			; error

	cmp	ah,CLS_SYM		; was last token a symbol?
	jne	gfe9			; no, error
	cmp	al,')'			; yes, closing parenthesis?
	jne	gfe2			; no
	sub	cx,cx			; zero number of remaining parms
	jmp	gfe1

gfe2:	cmp	al,','			; comma?
	jne	gfe9			; no, error
	test	cl,cl			; are more parameters allowed?
	jz	gfe9			; no
	jmp	gfe1
;
; No parameter value was supplied, so if the parameter isn't optional,
; that's an error.
;
gfe3:	call	loadFuncData
	and	al,0FCh			; VAR_CHAR, VAR_LSKIP -> VAR_LONG
	cmp	al,VAR_LONG		; TODO: currently supports default
	stc				; parameter values for VAR_LONG only
	jne	gfe9
	mov	al,ah			; AL = default value
	cmp	al,PARM_REQUIRED	; is the parameter optional?
	stc
	je	gfe9			; no
	cbw
	cwd				; DX:AX = default value
	xchg	cx,ax			; DX:CX
	call	genPushImmLong		; push it
	sub	cx,cx
	jmp	gfe1			; continue processing parameters

gfe6:	jcxz	gfe7
	cmp	al,')'
	jne	gfe9			; something is malformed
gfe7:	call	loadFuncData		; AX = function address offset
	xchg	cx,ax
	call	loadFuncData		; AX = function address segment
	xchg	dx,ax
	test	dx,dx
	jnz	gfe8
	mov	dx,cs
gfe8:	GENCALL	dx,cx			; generate call to function DX:CX
	mov	ah,[nFuncType]		; AH = return type
	jmp	short gfe10		; GENCALL should have cleared carry
gfe9:	stc
gfe10:	LEAVE
	ret

	DEFLBL	loadFuncData,near
	push	ds
	lds	si,[pFuncData]
	lodsw
	mov	[pFuncData].OFF,si
	pop	ds
	ret
ENDPROC	genFuncExpr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genFuncParm
;
; Generate code for accessing parameter N (of CL parameters).
;
; For example, if CL is 3 and the parameter # is 2, calculate the
; parameter offset ((count - parm #) * 4 + 6) and generate the code:
;
;	push	[bp+(offset+2)]
;	push	[bp+(offset+0)]
;
; Inputs:
;	CL = parm count
;	DX:SI -> parm data
;	ES:DI -> code block
;
; Outputs:
;	If carry clear, AH = parm type (from parm data)
;
; Modifies:
;	AX, DI
;
DEFPROC	genFuncParm
	call	getVar			; AL = parm type, AH = parm #
	sub	cl,ah
	jc	gfp9			; parm # inconsistency
	mov	ah,al
	push	ax
	mov	ch,0
	add	cx,cx
	add	cx,cx
	add	cx,8			; adjust CX for high word first
	call	genPushBPOffset
	dec	cx
	dec	cx			; then back down to the low word
	call	genPushBPOffset
	pop	ax
	clc
gfp9:	ret
ENDPROC	genFuncParm

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
	je	gl9			; TODO: Generate a better error message
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
ENDPROC	genLet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCallCS
;
; Inputs:
;	CS:CX -> function to call (or DX:CX if using genCallFar)
;
; Outputs:
;	Carry clear
;
; Modifies:
;	CX, DX, DI
;
DEFPROC	genCallCS
	mov	dx,cs
	DEFLBL	genCallFar,near
	push	ax
	mov	al,OP_CALLF
	stosb
	xchg	ax,cx
	stosw
	xchg	ax,dx
	stosw
	pop	ax
	clc
	ret
ENDPROC	genCallCS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPopBPOffset
;
; Inputs:
;	CX = offset
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI
;
DEFPROC	genPopBPOffset
	cmp	cx,7Fh
	ja	gpo1
	mov	ax,OP_POP_BP8
	stosw
	mov	al,cl
	stosb
	ret
gpo1:	mov	ax,OP_POP_BP16
	stosw
	mov	ax,cx
	stosw
	ret
ENDPROC	genPopBPOffset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushBPOffset
;
; Inputs:
;	CX = offset
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI
;
DEFPROC	genPushBPOffset
	cmp	cx,7Fh
	ja	gpu1
	mov	ax,OP_PUSH_BP8
	stosw
	mov	al,cl
	stosb
	ret
gpu1:	mov	ax,OP_PUSH_BP16
	stosw
	mov	ax,cx
	stosw
	ret
ENDPROC	genPushBPOffset

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
	cmp	dx,[defVarSeg]
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
; genPushImmByte
;
; Inputs:
;	AL = OP_MOV_AL
;	AH = value to push
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI
;
DEFPROC	genPushImmByteAL
	mov	ah,al
	DEFLBL	genPushImmByteAH,near
	mov	al,OP_MOV_AL
	DEFLBL	genPushImmByte,near
	stosw
	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushImmByteAL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushImmLong
;
; While the general case looks like this 8-byte sequence:
;
;	MOV	AX,yyyy
;	PUSH	AX
;	MOV	AX,xxxx
;	PUSH	AX
;
; if we determine that DX (yyyy) is a sign-extension of CX (xxxx),
; we can generate this 6-byte sequence instead:
;
;	MOV	AX,xxxx
;	CWD
;	PUSH	DX
;	PUSH	AX
;
; and if CX (xxxx) is zero, it can be simplified to a 4-byte sequence
; (ie, genPushZeroLong):
;
;	XOR	AX,AX
;	PUSH	AX
;	PUSH	AX
;
; Inputs:
;	DX:CX = value to push
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	genPushImmLong
	IFDEF MAXDEBUG
	DPRINTF	'o',<"num %ld\r\n">,cx,dx
	ENDIF
	xchg	ax,dx			; AX has original DX
	xchg	ax,cx			; AX contains CX, CX has original DX
	cwd				; DX is 0 or FFFFh
	cmp	dx,cx			; same as original DX?
	xchg	cx,ax			; AX contains original DX, CX restored
	xchg	dx,ax			; DX restored
	jne	gpi7			; no, DX is not the same
	jcxz	genPushZeroLong		; jump if we can zero AX as well
	mov	al,OP_MOV_AX
	stosb
	xchg	ax,cx
	stosw
	mov	ax,OP_CWD OR (OP_PUSH_DX SHL 8)
	stosw
	jmp	short gpi8
gpi7:	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	ax,OP_PUSH_AX OR (OP_MOV_AX SHL 8)
	stosw
	xchg	ax,cx
	stosw
gpi8:	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushImmLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushStr
;
; Copies the string at DS:SI with length CX into the code segment,
; pushing the far address of that string and then "leaping" over the string.
;
; Inputs:
;	DS:SI -> string (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX DI
;
DEFPROC	genPushStr
	mov	ax,OP_PUSH_CS OR (OP_CALL SHL 8)
	stosw
	mov	ax,cx
	inc	ax			; +1 for length byte
	stosw
	mov	al,cl
	stosb				; store the length byte
	rep	movsb			; followed by all the characters
	ret
ENDPROC	genPushStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushZeroLong
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI
;
DEFPROC	genPushZeroLong
	mov	ax,OP_ZERO_AX
	stosw
	DEFLBL	genPushLong,near
	mov	ax,OP_PUSH_AX OR (OP_PUSH_AX SHL 8)
	stosw
	ret
ENDPROC	genPushZeroLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushVarLong
;
; Generates code to push 4-byte variable data onto stack (eg, a VAR_LONG
; integer or a VAR_STR pointer).
;
; DX:SI points to the variable data, and if DX == defVarSeg, then the
; generated code can assume DS:SI; otherwise, we must generate code to load
; the segment as well.
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
	cmp	dx,[defVarSeg]
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
; getNextLine
;
; Inputs:
;	DS = heap segment
;
; Outputs:
;	If carry clear, DS:BX -> TOKLET array (TOKLET_END set to end)
;
; Modifies:
;	Any
;
DEFPROC	getNextLine
	mov	bx,ds:[PSP_HEAP]	; DS:BX -> heap
	mov	cx,[bx].LINE_LEN
	lds	si,[bx].LINE_PTR
	ASSUME	DS:NOTHING

	mov	dx,ds
	mov	ax,ss
	cmp	ax,dx			; is LINE_PTR in the heap?
	jne	gnl0			; no
	test	cx,cx			; yes, we must be using INPUTBUF
	stc				; have we already processed it?
	jnz	gnl4x			; yes
	mov	cl,[si].INP_CNT		; CX = length
	lea	si,[si].INP_DATA	; DS:SI -> line
	jmp	short gnl4

gnl0:	add	si,cx			; advance to the next line
gnl1:	cmp	si,ds:[BLK_FREE]	; still working the same TBLK?
	jb	gnl2			; yes
	mov	dx,ds:[BLK_NEXT]	; no, advance to next TBLK in chain
	cmp	dx,1			; is there another segment?
	jb	gnl4x			; no
	mov	ds,dx
	mov	si,size TBLK		; DS:SI -> next line
gnl2:	inc	ss:[bx].LINE_NUM
	lodsw
	test	ax,ax			; is there a label #?
	jz	gnl3			; no
	call	addLabel		; yes, add it to the LBLREF table
gnl3:	lodsb				; AL = length byte
	mov	ah,0
	xchg	cx,ax			; CX = length of line
	jcxz	gnl1
;
; As a preliminary matter, if we're processing a BAT file, then generate
; code to print the line, unless it starts with a '@', in which case, skip
; over the '@'.
;
gnl4:	DPRINTF	'b',<"%.*ls\r\n">,cx,si,ds
	cmp	byte ptr [si],'@'
	jne	gnl5
	inc	si
	dec	cx
	jz	gnl1
	jmp	short gnl6
gnl4x:	jmp	short gnl9
;
; One of the annoying things about the ECHO state is that, since we can't
; be sure what the state of ECHO will be at runtime, we must inject printLine
; before every line.
;
gnl5:	test	ss:[bx].GEN_FLAGS,GEN_ECHO
	jz	gnl6
	push	cx
	lea	cx,[si-1]
	GENPUSH	ds,cx			; DS:CX -> string (at the length byte)
	GENCALL	printLine
	pop	cx
;
; Ready to process the line of code at DS:SI with length CX.
;
gnl6:	mov	ss:[bx].LINE_PTR.OFF,si
	mov	ss:[bx].LINE_PTR.SEG,ds
	mov	ss:[bx].LINE_LEN,cx

	push	es
	push	di			; save code gen pointer
	push	ss
	pop	es			; ES = heap
;
; Copy the line (at DS:SI with length CX) to LINEBUF, so that we can use a
; single segment (DS) to address both LINEBUF and TOKENBUF once ES has been
; restored to the code gen segment.
;
	push	cx
	push	es
	lea	di,[bx].LINEBUF		; ES:DI -> LINEBUF
	push	di
	rep	movsb
	xchg	ax,cx			; AL = 0
	stosb				; null-terminate for good measure
	pop	si
	pop	ds
	pop	cx			; DS:SI -> LINEBUF (with length CX)

	lea	di,[bx].TOKENBUF	; ES:DI -> TOKENBUF
	DOSUTIL	TOKEN2
	mov	bx,di
	add	bx,offset TOK_DATA	; DS:BX -> TOKLET array
	pop	di
	pop	es			; restore code gen pointer
	jc	gnl9

	add	ax,ax
	add	ax,ax
	add	ax,bx
	mov	si,ds:[PSP_HEAP]
	mov	[si].TOKLET_END,ax
gnl9:	ret
ENDPROC	getNextLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextSymbol
;
; Call getNextToken with AL = CLS_SYM, updating BX and preserving CX, DX, SI.
;
DEFPROC	getNextSymbol
	push	cx
	push	si
	mov	al,CLS_SYM
	call	getNextToken
	pop	si
	pop	cx
	ret
ENDPROC	getNextSymbol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextToken
;
; Return the next token if it matches the criteria in AL (ignores whitespace).
;
; Inputs:
;	AL = CLS bits
;	DS:BX -> TOKLETs
;
; Outputs if next token matches:
;	AH = CLS of token
;	AL = 1st character of token (upper-cased)
;	CX = length of token
;	SI = offset of token (or offset of TOKDEF if CLS_KEYWORD)
;	BX = offset of next TOKLET
;	ZF and CF clear
;
; Outputs if NO matching next token:
;	ZF set if no more tokens (AX is zero)
;	CF set if no matching token (AH is CLS)
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	getNextToken
	push	dx
	push	di
gnt0:	mov	di,ds:[PSP_HEAP]
	cmp	bx,[di].TOKLET_END
	jb	gnt0a
	sub	ax,ax
	jmp	gnt9			; no more tokens (ZF set, CF clear)

gnt0a:	mov	ah,[bx].TOKLET_CLS
	test	ah,al
	jnz	gnt1
	cmp	ah,CLS_WHITE		; whitespace token?
gnt0b:	stc
	jne	gnt0c			; no (CF set)
	add	bx,size TOKLET		; yes, so ignore it
	jmp	gnt0
gnt0c:	jmp	gnt9

gnt1:	cmp	al,CLS_KEYWORD		; looking for keyword?
	jne	gnt1a			; no
	cmp	ah,CLS_VAR		; yes, undecorated CLS_VAR?
	jne	gnt0b			; no, can't be a keyword then

gnt1a:	mov	si,[bx].TOKLET_OFF
	mov	cl,[bx].TOKLET_LEN
	mov	ch,0
	add	bx,size TOKLET
	mov	dl,al			; DL = requested CLS
	mov	al,[si]			; AL = 1st character of token
	cmp	al,'a'			; ensure 1st character is upper-case
	jb	gnt2
	sub	al,20h
;
; Any CLS_VAR with additional bits specifying the variable type (eg,
; CLS_VAR_LONG, CLS_VAR_STR) is done, once we remove the type suffix from
; its length (the type is part of a variable's identity, not its name).
; Any vanilla CLS_VAR, however, must be further identified.  We now check for
; keyword operators (like NOT) and all other keywords.  Failing that, we
; assume it's a variable, so we look up the variable's implicit type and
; update the CLS bits accordingly.
;
gnt2:	cmp	ah,CLS_VAR
	je	gnt2v
	test	ah,CLS_VAR		; decorated CLS_VAR (eg, CLS_VAR_LONG)?
	jz	gnt7			; no
	dec	cx			; yes, so drop the type suffix
	jmp	short gnt8
gnt2v:

	push	ax
	push	dx
	mov	dx,offset KEYOP_TOKENS	; see if token is a KEYOP
	DOSUTIL	TOKID			; CS:DX -> TOKTBL
	jc	gnt2a
	mov	ah,CLS_SYM		; AL = TOKDEF_ID, SI -> TOKDEF
	jnc	gnt2b
gnt2a:	mov	dx,offset KEYWORD_TOKENS; see if token is a KEYWORD
	DOSUTIL	TOKID			; CS:DX -> TOKTBL
	jc	gnt2c
	mov	ah,CLS_KEYWORD		; AL = TOKDEF_ID, SI -> TOKDEF
gnt2b:	pop	dx
	pop	dx
	jmp	short gnt8
gnt2c:	pop	dx			; neither KEYOP nor KEYWORD
	pop	ax
	cmp	dl,CLS_KEYWORD		; and did we request a KEYWORD?
	stc
	je	gnt9			; yes, return error

	push	bx
	push	ax
	lea	bx,[di].DEFVARS
	sub	al,'A'			; convert 1st letter to DEFVARS index
	xlat				; look up the default VAR type
	test	al,al			; has a default been set?
	jnz	gnt4			; yes
	mov	al,VAR_LONG		; no, default to VAR_LONG
	cmp	word ptr cs:[FPU_TABLE].SEG,0
	je	gnt4			; if there's no FPU$ driver
	mov	al,VAR_DOUBLE		; otherwise, VAR_DOUBLE
gnt4:	mov	ah,al
	or	ah,CLS_VAR
	pop	bx			; we're really popping AX
	mov	al,bl			; and restoring AL
	pop	bx
	jmp	short gnt8
;
; If we're about to return a CLS_SYM that happens to be a colon, then return
; ZF set (but not carry) to end the caller's token scan.
;
gnt7:	cmp	ah,CLS_SYM
	jne	gnt8

	cmp	al,':'
	je	gnt9

gnt8:	or	ah,0			; return both ZF and CF clear
gnt9:	pop	di
	pop	dx
	ret
ENDPROC	getNextToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekNextSymbol
;
; Peek and return the next symbol, if any.
;
; Inputs and outputs are the same as getNextSymbol, but we also save the
; offset of the next TOKLET, in case the caller wants to consume the token.
;
; Modifies:
;	AX
;
DEFPROC	peekNextSymbol
	push	bx
	call	getNextSymbol
	jmp	short peekReturn
ENDPROC	peekNextSymbol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekNextToken
;
; Peek and return the next token, if it matches the criteria in AL.
;
; Inputs and outputs are the same as getNextToken, but we also save the
; offset of the next TOKLET, in case the caller wants to consume the token.
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	peekNextToken
	push	bx
	call	getNextToken
	DEFLBL	peekReturn,near
	push	bx
	mov	bx,ds:[PSP_HEAP]
	pop	ds:[bx].TOKLET_NEXT	; save BX in TOKLET_NEXT in case the
	pop	bx			; caller wants to advance after peeking
	ret
ENDPROC	peekNextToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; validateOp
;
; This must also check for operators that are multi-character.  It must remap
; "<>" and "><" to 'U', "<=" and "=<" to 'L', and ">=" and "=>" to 'G'.
;
; See RELOPS for the complete list of multi-character operators we remap.
;
; Inputs:
;	AL = operator
;
; Outputs:
;	If carry clear:
;		AL = operator
;		AH = precedence
;		CX = # args
;		DX = operator index
;
; Modifies:
;	AH, CX, DX
;
DEFPROC	validateOp
	push	si
	xchg	dx,ax			; DL = operator to validate
	mov	al,CLS_SYM
	call	peekNextToken
	jbe	vo2

	mov	dh,al			; DX = potential 2-character operator
	mov	si,offset RELOPS
vo1:	lods	word ptr cs:[si]
	test	al,al
	jz	vo2
	cmp	ax,dx			; match?
	lods	byte ptr cs:[si]
	jne	vo1
	mov	bx,ds:[PSP_HEAP]
	mov	bx,[bx].TOKLET_NEXT	; load TOKLET saved by peekNextToken
	xchg	dx,ax			; DL = (new) operator to validate

vo2:	mov	ah,dl			; AH = operator to validate
	mov	si,offset OPDEFS
vo3:	lods	byte ptr cs:[si]
	test	al,al
	stc
	jz	vo9			; not valid
	cmp	al,ah			; match?
	je	vo7			; yes
	add	si,size OPDEF - 1
	jmp	vo3

vo7:	lods	byte ptr cs:[si]	; AL = precedence, AH = operator
	sub	cx,cx			; default to 0 args
	cmp	al,2			; precedence <= 2?
	jbe	vo8			; yes
	inc	cx			; no, so op requires at least 1 arg
	test	al,1			; odd precedence?
	jnz	vo8			; yes, just 1 arg
	inc	cx			; no, op requires 2 args
vo8:	xchg	dx,ax
	lods	byte ptr cs:[si]	; AL = operator index
	cbw
	xchg	dx,ax			; DX = operator index, AX = op/prec
vo9:	xchg	al,ah			; AL = operator, AH = precedence
	pop	si
	ret
ENDPROC	validateOp

CODE	ENDS

	end
