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
; calls); the code-emitting helpers that push values and call functions (eg,
; genPushImmLong and genCallCS) are in genemit.asm.
;
; See gencmd.asm for an overview of all the gen*.asm files.
;
	DOSFUNC equ 1
	include	cmd.inc
	include	gen.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<ensureRoom>
	EXTNEAR	<addVar>
	EXTNEAR	<genArrayRef>

	EXTBYTE	<OPDEFS>
	EXTWORD	<EVAL_LONG,EVAL_STR>
	EXTLONG	<FPU_TABLE>
	EXTNEAR	<genCallFPU,genCallFPUDst,genCallFPUDst2>
	EXTNEAR	<genConstDouble,genFnCall>
	EXTABS	<TOK_ABS,TOK_TAN,TOK_MOUSE,TOK_SCREEN,TOK_IOCTL>
	EXTNEAR	<genPushVarLong,genPushVarPtr,getNextToken>
	EXTNEAR	<validateOp>
	EXTNEAR	<genCallCS,genCallFar,genPushImmLong>
	EXTNEAR	<genPushStr>

        
	EXTNEAR	<genFuncExpr,genFuncParm>

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

ge1:	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a token
	jc	ge1z
	mov	al,CLS_ANY		; CLS_NUM, CLS_SYM, CLS_VAR, CLS_STR
	call	getNextToken
	jbe	ge1y
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
	jc	ge1z
	inc	si			; DS:SI -> string contents
	call	genPushStr
	jmp	ge1
ge1y:	jmp	ge8
ge1z:	jmp	ge8x			; (see ge8x below)

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
; other keyword ends the expression (eg, THEN), except MOUSE, SCREEN, and
; IOCTL, which are also predefined functions (eg, MOUSE(0), SCREEN(1,1), or
; IOCTL(1,&HF3)), so they're processed like variables.
;
ge1k:	cmp	al,TOK_MOUSE
	je	ge1k1
	cmp	al,TOK_IOCTL
	je	ge1k1
	cmp	al,TOK_SCREEN
	jne	ge1l
ge1k1:	mov	si,[si].CTD_OFF		; DS:SI -> "MOUSE" or "SCREEN"
	mov	ah,CLS_VAR_LONG
	jmp	ge1c
ge1l:	cmp	al,TOK_ABS
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
; We ran out of code or type-stack room, or genOp found an error (eg, a type
; mismatch), so discard the operator stack and any helper frames, and return
; with carry set.
;
ge8x:	lea	sp,[bp-_LOCBYTES-4]
	stc
	jmp	short ge9a
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
;	If full, abort genExpr through its normal error cleanup.
;
; Modifies:
;	flags
;
	DEFLBL	pushType,near
	push	si
	mov	si,[typeTop]
	cmp	si,32			; reject a push past the type stack's end
	jae	ge8x
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
;	None (an error, such as a type mismatch, aborts genExpr; see ge8x)
;
; Modifies:
;	CX, DX, DI
;
	DEFLBL	genOp,near
	jcxz	go2x			; jump if no operator index

	push	si
	push	ax
	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for an op
	pop	ax
	jc	ge8x			; no room (see ge8x)
	IFDEF MAXDEBUG
	DPRINTF	'o',<"op %c, func @%08lx\r\n">,dx,cx,cs
	ENDIF
	call	popType
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
go2x:	ret
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
	jcxz	go8x			; no evaluator implies an error
	pop	si
	jmp	genCallCS		; generate call to operator evaluator
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
go8c:	jc	go8x			; no FPU$ driver
	pop	si
	ret
go8x:	jmp	ge8x

ENDPROC	genExpr



CODE	ENDS

	end
