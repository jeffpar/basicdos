;
; BASIC-DOS Code Generator: Expressions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for expressions (genExpr, including operators and function
; calls), along with the code generation helpers that push values and call
; functions, all of which were split from gencmd.asm to keep GENCMD.ASM within
; MASM's limits.
;
; See gencmd.asm for an overview of all the gen*.asm files.
;
	include	cmd.inc
	include	8086.inc
	include	fpu.inc

CODE    SEGMENT


	EXTNEAR	<allocCode,ensureRoom,keepCode>
	EXTNEAR	<addLabel>
	EXTNEAR	<allocVars>
	EXTNEAR	<addVar,getVar,setVarLong,setVarDouble>
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
	EXTNEAR	<genPushVarLong,genPushVarPtr,getNextSymbol,getNextToken>
	EXTNEAR	<peekNextSymbol,validateOp>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

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
ge0y:	lea	sp,[bp-_LOCBYTES-4]	; out of room (see ensureRoom), so
	stc				; discard the operator stack
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


CODE	ENDS

	end
