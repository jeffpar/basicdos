;
; BASIC-DOS Code Generator
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<allocCode,shrinkCode,freeCode,freeAllCode>
	EXTNEAR	<allocVars,allocFunc,freeFunc>
	EXTNEAR	<allocTempVars,updateTempVars,freeTempVars>
	EXTNEAR	<addVar,findVar,getVar,removeVar,setVar,setVarLong>
	EXTNEAR	<memError>
	EXTNEAR	<clearScreen,callDOS,printArgs,printEcho,printLine>
	EXTNEAR	<setColor,setFlags>

	EXTWORD	<KEYWORD_TOKENS,KEYOP_TOKENS>
	EXTBYTE	<OPDEFS_LONG,OPDEFS_STR,RELOPS>
	EXTABS	<TOK_ELSE,TOK_OFF,TOK_ON,TOK_THEN>

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
	jz	gc9			; no (TODO: display a message?)
	mov	si,size TBLK
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

gc4:	call	getNextLine
	cmc
	jnc	gc6
	call	genCommands		; generate code
	jnc	gc4

gc6:	push	ss
	pop	ds
	ASSUME	DS:DATA
	jc	gc7
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
	popf
gc8:	jnc	gc9

	mov	bx,ds:[PSP_HEAP]
	PRINTF	<"Syntax error in line %d",13,10>,[bx].LINE_NUM
	stc
	jmp	short gc9

gce:	call	memError

gc9:	LEAVE
	ret
ENDPROC	genCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCommands
;
; Generate code for one or more commands.
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
	mov	al,CLS_KEYWORD
	call	getNextToken
	jb	gcs1
	je	gcs9			; out of tokens
	mov	cx,cs:[si].CTD_FUNC	;
	cmp	al,KEYWORD_BASIC	; BASIC keyword?
	jb	gcs2			; no
	jcxz	gcs9			; no command address
	jmp	short gcs3		; call generator function

gcs1:	sub	ax,ax			; call genDOS w/o an ID
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

gcs9:	ret
ENDPROC	genCommands

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCLS
;
; Generate code for "CLS"
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
DEFPROC	genCLS
	GENCALL	clearScreen
	ret
ENDPROC	genCLS

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
; genColor
;
; Generate code for "COLOR fgnd[,[bgnd[,[border]]"
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
DEFPROC	genColor
	sub	cx,cx
gco1:	call	genExpr
	jb	gco9
	je	gco8
	inc	cx
	cmp	al,','			; was the last symbol a comma?
	je	gco1			; yes, go back for more
gco8:	GENPUSH	cx
	GENCALL	setColor
gco9:	ret
ENDPROC	genColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDefFn
;
; Generate code for "DEF fn(parms)=expr".
;
; We rely on genExpr to generate the code for "expr", which requires us to
; create a temp var block containing all the variables in "parms", so that
; when genExpr calls findVar, it searches the temp var block first.
;
; Note that we do NOT require the function name to begin with "FN" like
; MSBASIC does.
;
; TODO: We shouldn't allow DEF to redefine a function that already exists,
; but since BAT files inherit existing var blocks, we permit it (see call to
; removeVar).  Unfortunately, all removeVar does is mark the existing var
; data as DEAD, and addVar doesn't currently reuse DEAD space, so memory will
; grow until you force the var blocks to be deleted.
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

	cmp	[fnBlock],0		; function expression?
	jne	gd3a			; no
	call	genExpr			; yes
	jnc	gd3c
gd3x:	jmp	short gd8

gd3a:	push	si
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
gd3c:	mov	cl,[fnParms]
	mov	ch,0
	add	cx,cx
	add	cx,cx
	add	cx,6
	call	genPopBPOffset
	inc	cx
	inc	cx
	call	genPopBPOffset
	mov	ax,OP_POP_BP OR (OP_RETF_N SHL 8)
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
gd9:	LEAVE	CLEANUP
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
; Process "DEFDBL".  In BASIC-DOS, floating-point will comes in only one
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
; genEcho
;
; Process "ECHO".  If "ECHO ON" or "ECHO OFF", generate call to setFlags.
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
DEFPROC	genEcho
	mov	al,CLS_KEYWORD
	call	getNextToken
	jb	gec9
	jnz	gec1
	GENCALL	printEcho
	ret
gec1:	cmp	al,TOK_ON
	jne	gec2
	mov	ah,NOT CMD_NOECHO
	jmp	short gec8
gec2:	cmp	al,TOK_OFF
	stc
	jne	gec9
	mov	ah,CMD_NOECHO
gec8:	mov	al,OP_MOV_AL
	stosw				; "MOV AL,xx" where XX is value in AH
	GENCALL	setFlags
gec9:	ret
ENDPROC	genEcho

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genExpr
;
; Generate code for an expression.  To help catch errors up front, maintain
; a count of values queued, compare that to the number of arguments expected
; by all the operators, and also maintain an open parentheses count.
;
; Inputs:
;	DS:BX -> next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	AX = last result from getNextToken
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
	LOCVAR	exprType,byte
	LOCVAR	exprParms,byte
	LOCVAR	exprArgs,word
	LOCVAR	exprVals,word
	LOCVAR	exprParens,word
	LOCVAR	exprPrevOp,word
	ENTER
	push	cx
	push	si
	mov	si,ds:[PSP_HEAP]
	mov	al,[si].DEF_PARMS
	mov	[exprParms],al		; parm count (only from genDefFn)
	sub	dx,dx
	mov	word ptr [exprType],dx	; exprType = VAR_NONE, exprToks = 0
	mov	[exprArgs],1		; count of expected arguments
	mov	[exprVals],dx		; count of values queued
	mov	[exprParens],dx		; count of open parentheses
	mov	[exprPrevOp],dx		; previous operator (none)
	push	dx			; push end-of-operators marker (zero)

ge1:	mov	al,CLS_ANY		; CLS_NUM, CLS_SYM, CLS_VAR, CLS_STR
	call	getNextToken
	jbe	ge2x
	inc	[exprToks]
	cmp	ah,CLS_SYM		; 20h?
	je	ge1b			; process CLS_SYM below
;
; Non-operator (non-symbol) cases: keywords, variables, strings, and numbers.
;
	mov	byte ptr [exprPrevOp],-1; invalidate prevOp (intervening token)
	cmp	ah,CLS_KEYWORD		; 30h?
	je	ge2x			; keywords not allowed in expressions
	cmp	ah,CLS_VAR		; 10h? (variable with type?)
	ASSERT	NE			; (type should be fully qualified now)
	ja	ge2			; yes
;
; Must be CLS_STR or CLS_NUM.  Handle CLS_STR here and CLS_NUM below.
;
	test	ah,CLS_STR		; string?
	jz	ge3			; no, must be number
	mov	al,VAR_STR		; AL = VAR_STR
	call	setExprType		; update expression type
	jnz	ge2x
	sub	cx,2			; CX = string length
	ASSERT	NC
	jcxz	ge1a			; empty string
	inc	si			; DS:SI -> string contents
	call	genPushStr
	jmp	short ge2e

ge1a:	DBGBRK
	sub	cx,cx			; for empty strings, push null ptr
	sub	dx,dx
	call	genPushImmLong
	jmp	short ge2e
ge1b:	jmp	short ge4
;
; Process CLS_VAR.  We don't care if findVar succeeds or not, because
; even if it fails, it returns var type (AH) VAR_LONG with var data (DX:SI)
; set to a zero constant.  However, var type (AH) must still be consistent
; with the expression type.
;
ge2:	call	findVar
	cmp	ah,VAR_PARM		; 20h?
	jne	ge2a			; no
;
; VAR_PARM variables are present only in temp var blocks created by genDefFn,
; so genDefFn must have called us with a parameter count.
;
	mov	cl,[exprParms]
	call	genFuncParm
	jmp	short ge2b

ge2a:	cmp	ah,VAR_FUNC		; C0h?
	jne	ge2c
	call	genFuncExpr		; process the function expression
ge2b:	jnc	ge2d			; AH = return type
	jmp	short ge3x

ge2c:	call	genPushVarLong

ge2d:	mov	al,ah			; AL = var type
	call	setExprType		; update expression type
	jnz	ge3x			; error
ge2e:	inc	[exprVals]		; count another queued value
	jmp	ge1
ge2x:	jmp	short ge3x
;
; Process CLS_NUM.  Number is a constant and CX is its exact length.
;
; TODO: If the preceding character is a '-' and the top of the operator stack
; is 'N' (unary minus), consider decrementing SI and removing the operator.
; Why? Because it's better for ATOI32 to know up front that we're dealing with
; a negative number, because then it can do precise overflow checks.
;
ge3:	mov	al,VAR_LONG		; AL = VAR_LONG
	call	setExprType		; update expression type
	jnz	ge3x			; error
	push	bx
	mov	bl,10			; BL = 10 (default base)
	test	ah,CLS_OCT OR CLS_HEX	; octal or hex value?
	jz	ge3a			; no
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
	jmp	ge2e			; go count another queued value
ge3x:	jmp	short ge8
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
	dec	cx
	add	[exprArgs],cx
	mov	si,dx			; SI = current evaluator
;
; Operator is valid, so peek at the operator stack and pop if the top
; operator precedence >= current operator precedence.
;
ge5a:	pop	dx			; "peek"
	cmp	dh,ah			; top precedence > current?
	jb	ge6			; no
	ja	ge5b			; yes
	test	dh,1			; unary operator?
	jnz	ge6			; yes, hold off
ge5b:	pop	cx			; pop the evaluator as well
	jcxz	ge6c			; no evaluator (eg, left paren)

	IFDEF MAXDEBUG
	DPRINTF	'o',<"op %c, func @%08lx\r\n">,dx,cx,cs
	ENDIF

	GENCALL	cx			; and generate call
	jmp	ge5a

ge6:	push	dx			; "unpeek"
ge6a:	push	si			; push current evaluator
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
ge7b:	mov	ah,CLS_SYM
;
; We have reached the (presumed) end of the expression, so start popping
; the operator stack.
;
ge8:	pop	cx
	jcxz	ge9			; all done

	IFDEF MAXDEBUG
	pop	ax
	DPRINTF	'o',<"op %c, func @%08lx...\r\n">,cx,ax,cs
	xchg	cx,ax
	ELSE
	pop	cx			; CX = evaluator
	ENDIF

	jcxz	ge8
	GENCALL	cx
	jmp	ge8
;
; Verify the number of values queued matches the number of expected arguments.
;
ge9:	mov	cx,[exprVals]
	cmp	cx,[exprArgs]
	stc
	jne	ge10
	cmp	[exprParens],0
	stc
	jg	ge10
	test	cx,cx			; return ZF set if no values
ge10:	mov	dx,word ptr [exprType]	; DL = expression type, DH = # tokens
	pop	si
	pop	cx
	LEAVE
	RETURN

	DEFLBL	setExprType,near
	cmp	[exprType],al
	je	set9
	cmp	[exprType],0
	jne	set9
	mov	[exprType],al
set9:	ret				; return ZF set if type is OK

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
;
gfe0:	ASSERT	Z,<cmp [nFuncType],VAR_LONG>
	call	genPushLong

gfe1:	dec	[nFuncParms]		; more parameters?
	jl	gfe6			; no
	jcxz	gfe3			; yes, but no (more) have been supplied

	call	genExpr			; process parameter expression
	jbe	gfe3			; no value supplied

	push	ax			; save last symbol from genExpr
	call	loadFuncData		; AL = parameter type
	cmp	al,dl			; does it match expression type?
	pop	ax			; restore last symbol
	jne	gfe9			; no, error

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
	cmp	al,VAR_LONG		; TODO: currently supports default
	stc				; parameter values for VAR_LONG only
	jne	gfe9
	mov	al,ah			; AL = default value
	test	al,al			; negative? (eg, PARM_REQUIRED)
	jl	gfe9			; yes, parameter is NOT optional
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
	mov	al,CLS_NUM
	call	getNextToken
	jbe	gg9
	DOSUTIL	ATOI32D			; DS:SI -> decimal string
	call	findLabel
;
; If carry is clear, then we found the specified label # (ie, it must have
; been a backward reference), so we can generate the correct code immediately;
; AX contains the LBL_IP to use.
;
; If carry is set, then the label # must be a forward reference.  findLabel
; automatically calls addLabel with LBL_RESOLVE set, so when the definition is
; finally found, this (and any other LBL_RESOLVE references) can be resolved.
;
; In the interim, we generate a 3-byte program termination sequence (reset
; the stack pointer and return); once the label definition is encountered, that
; 3-byte sequence will be overwritten with a 3-byte JMP (see addLabel).
;
	jc	gg7
	xchg	dx,ax
	sub	dx,di
	sub	dx,3			; DX = 16-bit displacement
	mov	al,OP_JMP
	stosb
	xchg	ax,dx
	stosw
	jmp	short gg8
gg7:	mov	ax,OP_MOV_SP_BP		; placeholder for endProgram
	stosw
	mov	al,OP_RETF
	stosb
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
;	jz	elseBlock
;    thenBlock:
;	; Generate code for "THEN" block
;	; ...
;	jmp	nextBlock (optional; only needed if there's an "ELSE" block)
;     elseBlock:
;	; Generate code for "ELSE" block
;	; ...
;     nextBlock:
;
; So when genCommands for the "THEN" block returns, we must update the
; "jz elseBlock" with the address of the next available location.  Note that
; if the amount of generated code is larger than 127 bytes, we'll have to
; move the generated code to make room for "jnz $+5; jmp elseBlock" instead.
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
	mov	ax,OP_POP_DX_AX
	stosw
	mov	ax,OP_OR_AX_DX
	stosw
	mov	ax,OP_JZ_SELF
	stosw
;
; Before calling genCommands, we must peek at the next token and check for
; a line number, because there could be an implied GOTO (ie, "THEN 10" instead
; of "THEN GOTO 10").
;
	push	di			; ES:DI-1 -> JZ offset
	call	genCommands
gif8:	pop	ax			; AX = old DI
	mov	dx,di			; DX = new DI
	sub	dx,ax			; DX = # generated bytes for JZ to skip
	ASSERT	B,<cmp dx,128>
	sub	di,dx
	mov	es:[di-1],dl		; update the JZ offset
	add	di,dx
	ASSERT	NC
	ret
gif9:	stc
	ret
ENDPROC	genIf

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
	call	addVar			; DX:SI -> var data
	jc	gl9

	cmp	dx,[codeSeg]		; constants cannot be "let"
	je	gl9			; TODO: Generate a better error message
	push	ax
	call	genPushVarPtr
	call	getNextSymbol
	pop	dx
	jbe	gl9

	cmp	al,'='
	jne	gl9

	call	genExpr
	jc	gl9
	GENCALL	setVarLong		; TODO: check expression type in DL
	ret

gl9:	stc
	ret
ENDPROC	genLet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPrint
;
; Generate code to "PRINT" a series of values.
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
DEFPROC	genPrint
	GENPUSHB VAR_NONE		; push end-of-args marker
gp1:	call	genExpr
	jnc	gp2
	test	dh,dh			; if there were no tokens
	stc				; then ignore the error
	jnz	gp9			; (PRINT without args is allowed)
gp2:	jz	gp8
	push	ax
	mov	al,VAR_LONG		; AL = default type (40h)
	cmp	dl,al			; does that match the expression type?
	je	gp3			; yes
	mov	al,VAR_STR		; must be VAR_STR then (80h)
	ASSERT	Z,<cmp dl,al>		; verify our assumption
gp3:	GENPUSHB al
	pop	ax
	mov	ah,VAR_SEMI
	cmp	al,';'			; was the last symbol a semi-colon?
	je	gp6			; yes
	mov	ah,VAR_COMMA
	cmp	al,','			; how about a comma?
	jne	gp8			; no
gp6:	GENPUSHB ah			; "MOV AL,[VAR_SEMI or VAR_COMMA]"
	jmp	gp1			; continue processing arguments
gp8:	GENCALL	printArgs		; all done
gp9:	ret
ENDPROC	genPrint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genReturn
;
; Generate code to "RETURN [optional value]".
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
	test	[si].GEN_FLAGS,GEN_DEF
	jz	gr9
	call	genExpr
	jc	gr9
	and	[si].GEN_FLAGS,NOT GEN_DEF
gr9:	ret
ENDPROC	genReturn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addLabel
;
; Inputs:
;	AX = label #
;	ES -> current code block
;
; Outputs:
;	Carry clear if successful, set if error (eg, duplicate label)
;
; Modifies:
;	CX, DX
;
DEFPROC	addLabel
	mov	dx,di			; DX = current code gen offset
	mov	di,ss:[PSP_HEAP]
	DPRINTF	'l',<"%#010P: line %d: adding label %d...\r\n">,ss:[di].LINE_NUM,ax
	test	dx,LBL_RESOLVE		; is this a label reference?
	jnz	al8			; yes, just add it
;
; For label definitions, we scan the LBLREF table to ensure this
; definition is unique.  We must also scan the table for any unresolved
; references and fix them up.
;
	mov	cx,es:[BLK_SIZE]
	mov	di,es:[CBLK_REFS]
	sub	cx,di
	shr	cx,1			; CX = # of words on LBLREF table
al0:	jcxz	al8			; table is empty
al1:	repne	scasw			; scan all words for label #
	jne	al8			; nothing found
	test	di,(size LBLREF)-1	; did we match the first LBLREF word?
	jz	al0			; no (must have match LBL_IP instead)
	test	word ptr es:[di],LBL_RESOLVE
	stc
	jz	al9			; duplicate definition
;
; Generate code in the same fashion as genGoto, except that here, we're
; replacing a previously unresolved GOTO with a forward JMP (ie, positive
; displacement) to the location at DX.
;
	push	ax
	push	dx
	push	di
	mov	di,es:[di]
	and	di,NOT LBL_RESOLVE
	sub	dx,di
	sub	dx,3			; DX = 16-bit displacement
	mov	al,OP_JMP
	stosb
	xchg	ax,dx
	stosw
	pop	di
	pop	dx
	pop	ax
	jmp	al1			; keep looking for LBL_RESOLVE matches

al8:	mov	di,es:[CBLK_REFS]
	sub	di,size LBLREF
	mov	es:[CBLK_REFS],di
	stosw				; LBL_NUM <- AX
	xchg	ax,dx
	stosw				; LBL_IP <- DX
	xchg	ax,dx			; restore AX
	mov	di,dx			; restore DI
	clc
al9:	ret
ENDPROC	addLabel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findLabel
;
; Inputs:
;	AX = label #
;	ES -> current code block
;
; Outputs:
;	Carry clear if found, AX = code gen offset for label
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	findLabel
	push	di
	mov	di,ss:[PSP_HEAP]
	DPRINTF	'l',<"%#010P: line %d: finding label %d...\r\n">,ss:[di].LINE_NUM,ax
	mov	cx,es:[BLK_SIZE]
	mov	di,es:[CBLK_REFS]
	sub	cx,di
	jcxz	fl8			; table is empty
	shr	cx,1			; CX = # of words on LBLREF table
fl1:	repne	scasw			; scan all words for label #
	jne	fl8			; nothing found
	test	di,(size LBLREF)-1	; did we match the first LBLREF word?
	jz	fl1			; no (must have match LBL_IP instead)
	test	word ptr es:[di],LBL_RESOLVE
	jnz	fl1			; this is a ref, not a definition
	mov	ax,es:[di]		; AX = LBL_IP for label
	jmp	short fl9
fl8:	pop	di
	push	di
	add	di,LBL_RESOLVE
	call	addLabel
	stc
fl9:	pop	di
	ret
ENDPROC	findLabel

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
	jne	gnt9			; no (CF set)
	add	bx,size TOKLET		; yes, so ignore it
	jmp	gnt0

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
; CLS_VAR_LONG, CLS_VAR_STR) is done.  Any vanilla CLS_VAR, however, must
; be further identified.  We now check for keyword operators (like NOT) and
; all other keywords.  Failing that, we assume it's a variable, so we look
; up the variable's implicit type and update the CLS bits accordingly.
;
gnt2:	cmp	ah,CLS_VAR
	jne	gnt7

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
; Peek and return the next symbol, if any.  TODO: Remove if no callers.
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
;	If carry clear, AL = op, AH = precedence, CX = # args, DX = evaluator
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
	mov	si,offset OPDEFS_LONG
	cmp	[exprType],VAR_STR
	jne	vo3
	mov	si,offset OPDEFS_STR
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
	lods	word ptr cs:[si]	; AX = evaluator
	xchg	dx,ax			; DX = evaluator, AX = op/prec
vo9:	xchg	al,ah			; AL = operator, AH = precedence
	pop	si
	ret
ENDPROC	validateOp

CODE	ENDS

	end
