;
; BASIC-DOS Code Generator
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTERNS	<allocCode,freeCode,allocVars>,near
	EXTERNS	<addVar,findVar,setVarLong>,near
	EXTERNS	<appendStr,setStr>,near
	EXTERNS	<clearScreen,printArgs,setColor>,near

	EXTERNS	<segVars>,word
	EXTERNS	<KEYWORD_TOKENS,KEYOP_TOKENS>,word
	EXTERNS	<OPDEFS,RELOPS>,byte
	EXTERNS	<TOK_ELSE,TOK_THEN>,abs

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genImmediate
;
; Generate code for a single line, by creating a temporary code block, and
; then calling the specified "gen" handler(s) to generate code in the block.
;
; Inputs:
;	DI -> TOKENBUF with all tokens
;	DX = TOKDEF_DATA for first token (ie, the "gen" handler)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	genImmediate
	LOCVAR	nArgs,word
	LOCVAR	nExpArgs,word
	LOCVAR	nExpVals,word
	LOCVAR	nExpParens,word
	LOCVAR	nExpPrevOp,word
	LOCVAR	errCode,word
	LOCVAR	pCode,dword
	LOCVAR	pTokletNext,word
	LOCVAR	pTokletEnd,word
	ENTER
	sub	ax,ax
	mov	[nArgs],ax
	mov	[errCode],ax
	mov	bx,di			; BX -> TOKENBUF
	mov	al,[bx].TOK_CNT		; AX = token count
	add	bx,offset TOK_BUF	; BX -> TOKLET array
	add	ax,ax
	add	ax,ax
	add	ax,bx
	mov	[pTokletEnd],ax
	add	bx,size TOKLET		; skip 1st token (already parsed)

	call	allocVars
	jc	gie
	call	allocCode
	jc	gie
	ASSUME	ES:NOTHING		; ES:DI -> usable code block space
	mov	[pCode].OFF,di
	mov	[pCode].SEG,es

gi1:	call	genCommand		; generate code
	jnc	gi6
	jmp	short gi7		; error

gie:	PRINTF	<'Not enough memory (%#06x)',13,10>,ax
	jmp	short gi9

gi6:	mov	al,OP_RETF		; terminate code
	stosb
	push	bp
	push	ds
	push	es
	mov	ax,[segVars]
	mov	ds,ax
	mov	es,ax
	ASSUME	DS:NOTHING
	call	[pCode]			; execute code
	pop	es
	pop	ds
	ASSUME	DS:CODE
	pop	bp
	clc

gi7:	pushf
	call	freeCode
	popf
gi8:	jnc	gi9

	PRINTF	<'Syntax error',13,10>

gi9:	LEAVE
	ret
ENDPROC	genImmediate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCommands
;
; Generate code for one or more commands.
;
; Inputs:
;	BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genCommands
gc1:	call	getNextToken
	cmc
	jnc	gc9
	lea	dx,[KEYWORD_TOKENS]
	mov	ax,DOS_UTL_TOKID
	int	21h			; identify the token
	jc	gc9			; can't identify
	DEFLBL	genCommand,near
	call	dx
	jnc	gc1
gc9:	ret
ENDPROC	genCommands

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCLS
;
; Generate code for "CLS"
;
; Inputs:
;	BX -> TOKLETs
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
; genColor
;
; Generate code for "COLOR fgnd[,[bgnd[,[border]]"
;
; Inputs:
;	BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genColor
	call	genExprNum
	jb	gco9
	je	gco8
	cmp	al,','			; was the last symbol a comma?
	je	genColor		; yes, go back for more
gco8:	GENPUSH	nArgs
	GENCALL	setColor
gco9:	ret
ENDPROC	genColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genExprNum
;
; Generate code for a numeric expression.  To help catch errors up front,
; maintains a count of values queued, compares that to the number of arguments
; expected by all the operators, and also maintains an open parentheses count.
;
; Inputs:
;	BX = offset of next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	AX = last result from getNextToken
;	CF clear if successful, set if error
;	ZF clear if expression existed, set if not
;	ES:DI -> next unused location in code block
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	genExprNum
	sub	dx,dx
	mov	[nExpArgs],1		; count of expected arguments
	mov	[nExpVals],dx		; count of values queued
	mov	[nExpParens],dx		; count of open parentheses
	mov	[nExpPrevOp],dx		; previous operator (none)
	push	dx			; push end-of-operators marker (zero)

gn1:	mov	al,CLS_NUM OR CLS_SYM OR CLS_VAR
	call	getNextToken
	jbe	gn3x
	cmp	ah,CLS_SYM
	je	gn4
;
; Non-operator cases: distinguish between variables and numbers.
;
gn2:	mov	byte ptr [nExpPrevOp],-1; invalidate prevOp (intervening token)
	test	ah,CLS_VAR		; variable?
	jz	gn3			; no
;
; Some tokens initially classified as VAR are really keyword operators
; (eg, 'NOT', 'AND', 'XOR'), so check for those first.
;
	mov	dx,offset KEYOP_TOKENS	; see if token is a KEYOP
	mov	ax,DOS_UTL_TOKID
	int	21h
	jnc	gn5			; jump to operator validation

	mov	dx,offset KEYWORD_TOKENS; see if token is a KEYWORD
	mov	ax,DOS_UTL_TOKID
	int	21h
	jc	gn2a
	mov	ah,CLS_KEYWORD
	jmp	short gn3x		; jump to expression termination

gn2a:	call	findVar			; no, check vars next
;
; We don't care if findVar succeeds or not, because even if it fails,
; it returns var type (AH) VAR_LONG with var data (DX) preset to zero.
;
; TODO: Check AH for the var type and act accordingly.
;
	call	genPushVarLong

gn2b:	inc	[nExpVals]		; count another queued value
	jmp	gn1
;
; Number must be a constant, and although CX contains its exact length,
; DOS_UTL_ATOI32 doesn't actually care; it simply converts characters until
; it reaches a non-digit.
;
; TODO: If the preceding character is a '-' and the top of the operator stack
; is 'N' (unary minus), consider decrementing SI and removing the operator.
; Why? Because it's better for ATOI32 to know up front that we're dealing with
; a negative number, because then it can do precise overflow checks.
;
gn3:	push	bx
	mov	bl,10			; BL = 10 (default base)
	test	ah,CLS_OCT OR CLS_HEX	; octal or hex value?
	jz	gn3a			; no
	inc	si			; yes, skip leading ampersand
	shl	ah,1
	shl	ah,1
	shl	ah,1
	mov	bl,ah			; BL = 8 or 16 (new base)
	cmp	byte ptr [si],'9'	; is next character a digit?
	jbe	gn3a			; yes
	inc	si			; no, skip it (must be 'O' or 'H')
gn3a:	mov	ax,DOS_UTL_ATOI32	; DS:SI -> numeric string
	int	21h
	xchg	cx,ax			; save result in DX:CX
	pop	bx

	GENPUSH	dx,cx
	jmp	gn2b			; go count another queued value
gn3x:	jmp	short gn8
;
; Before we try to validate the operator, we need to remap binary minus to
; unary minus.  So, if we have a minus, and the previous token is undefined,
; or another operator, or a left paren, it's unary.  Ditto for unary plus.
; The internal identifiers for unary '-' and '+' are 'N' and 'P'.
;
gn4:	mov	ah,'N'
	cmp	al,'-'
	je	gn4a
	mov	ah,'P'
	cmp	al,'+'
	jne	gn5
gn4a:	mov	cx,[nExpPrevOp]
	jcxz	gn4b
	cmp	cl,')'			; do NOT remap if preceded by ')'
	je	gn5
	cmp	cl,-1			; another operator (including '(')?
	je	gn5			; no
gn4b:	mov	al,ah			; remap the operator
;
; Verify that the symbol is a valid operator.
;
gn5:	call	validateOp		; AL = operator to validate
	jc	gn8			; error
	mov	[nExpPrevOp],ax
	sub	si,si
	jcxz	gn7			; handle no-arg operators below
	dec	cx
	add	[nExpArgs],cx
	mov	si,dx			; SI = current evaluator
;
; Operator is valid, so peek at the operator stack and pop if the top
; operator precedence >= current operator precedence.
;
gn6:	pop	dx			; "peek"
	cmp	dh,ah			; top precedence > current?
	jb	gn6b			; no
	ja	gn6a
	jcxz	gn6b			; don't pop unary operator yet
gn6a:	pop	cx			; yes, pop the evaluator as well
	jcxz	gn6			; no evaluator (eg, left paren)
	GENCALL	cx			; and generate call
	jmp	gn6
gn6b:	push	dx			; "unpeek"
gn6c:	push	si			; push current evaluator
	push	ax			; push current operator/precedence
gn6d:	jmp	gn1			; next token
;
; Special operators handled here.
;
gn7:	cmp	al,'('
	jne	gn7a
	inc	[nExpParens]
	jmp	gn6c
gn7a:	ASSERT	Z,<cmp al,')'>
	dec	[nExpParens]
	jmp	gn6
;
; Time to start popping the operator stack.
;
gn8:	pop	cx
	jcxz	gn9			; all done
	pop	cx			; CX = evaluator
	jcxz	gn8
	GENCALL	cx
	jmp	gn8
;
; Verify the number of values queued matches the number of expected arguments.
;
gn9:	mov	cx,[nExpVals]
	cmp	cx,[nExpArgs]
	stc
	jne	gn10
	cmp	[nExpParens],0
	stc
	jne	gn10
	inc	[nArgs]
	test	cx,cx			; return ZF set if no values
gn10:	ret
ENDPROC	genExprNum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genExprStr
;
; Generate code for a string expression.  It begins by creating an empty
; string (ie, null pointer) on the stack and beginning string operations
; (ie, concatenations, if any).
;
; The common case is a string constant, which is stored in the code block.
; The generated code will call appendStr to append the string referenced in
; the code block to the string pointer on the stack.
;
; Inputs:;
;	BX = offset of next TOKLET
;	ES:DI -> next unused location in code block
;
; Outputs:
;	CF clear if successful, set if error
;	ZF clear if expression existed, set if not
;	ES:DI -> next unused location in code block
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	genExprStr
	int 3
	call	genPushZeroLong

gs1:	mov	al,CLS_VAR OR CLS_STR
	call	getNextToken
	jbe	gs5

	cmp	ah,CLS_STR
	jne	gs2
;
; Handle string constant here.
;
	sub	cx,2			; CX = string length
	ASSERT	NC
	jcxz	gs4			; empty string, skip it
	inc	si			; DS:SI -> string contents
	PUSHSTR
	jmp	short gs3
;
; Handle string variable here.
;
gs2:	cmp	ah,VAR_STR
	ASSERT	Z
	stc
	jne	gs8
	call	findVar			; find the variable
	jc	gs8
	cmp	ah,VAR_STR		; correct type?
	stc
	jne	gs8			; no
	call	genPushVarLong
gs3:	GENCALL	appendStr
;
; Check for concatenation (the only supported string operator).
;
gs4:	mov	al,CLS_SYM
	call	getNextToken
	jbe	gs5
	cmp	al,'+'
	je	gs1
	stc

gs5:

gs8:	ret
ENDPROC	genExprStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genGoto
;
; Generate code for "GOTO [line]"
;
; Inputs:
;	BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genGoto
	stc
	ret
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
; if the amount of generated code is larger than 127 bytes, we'll have to use
; "jnz $+5; jmp elseBlock" instead.
;
; Inputs:
;	BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genIf
	call	genExprNum
	jbe	gife
	cmp	ah,CLS_KEYWORD
	jne	gife
	cmp	al,TOK_THEN
	jne	gife
	mov	ax,OP_POP_DX_AX
	stosw
	mov	ax,OP_OR_AX_DX
	stosw
	mov	ax,OP_JZ_SELF
	stosw
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
gife:	stc
	ret
ENDPROC	genIf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLet
;
; Generate code to "let" a variable equal some expression.  We start with
; 32-bit integer ("long") variables.  We'll also start with the assumption
; that it's OK to alloc the variable at "gen" time, so that the only code we
; have to generate (and execute later) is code that sets the variable,
; using its preallocated location.
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
;
; If the variable has a specific type, then AL should be >= VAR_INT.
; Otherwise, we default to VAR_LONG.
;
	mov	al,ah
	cmp	al,VAR_INT
	jae	gl1
	mov	al,VAR_LONG

gl1:	call	addVar			; DX -> var data
	jc	gl9

	push	ax
	PUSH_DS_DX
	mov	al,CLS_SYM
	call	getNextToken
	pop	dx
	jbe	gl9

	cmp	al,'='
	stc
	jne	gl9

	cmp	dl,VAR_STR		; check the new variable's type
	jne	gl2			; presumably numeric

	call	genExprStr
	jc	gl9
	GENCALL	setStr
	jmp	short gl9

gl2:	call	genExprNum
	jc	gl9
	GENCALL	setVarLong

gl9:	ret
ENDPROC	genLet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPrint
;
; Generate code to print.
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
	GENPUSHB VAR_NONE		; push end-of-args marker (VAR_NONE)

gp1:	mov	al,CLS_VAR or CLS_STR
	call	peekNextToken
	jc	gp8
	jz	gp3
	cmp	ah,CLS_STR
	je	gp2
	cmp	ah,VAR_STR
	jne	gp3
;
; Handle string arguments here.
;
gp2:	push	ax
	call	genExprStr
	pop	ax
	jc	gp9
	jz	gp8

	push	ax
	GENPUSHB ah
	pop	ax
	jmp	short gp5
;
; Handle numeric arguments here.
;
gp3:	call	genExprNum
	jc	gp9
	jz	gp8

gp4:	push	ax
	GENPUSHB VAR_LONG
	pop	ax
;
; Argument paths rejoin here to determine spacing requirements.
;
gp5:	mov	ah,VAR_SEMI
	cmp	al,';'			; was the last symbol a semi-colon?
	je	gp6			; yes
	mov	ah,VAR_COMMA
	cmp	al,','			; how about a comma?
	jne	gp8			; no

gp6:	GENPUSHB ah			; "MOV AL,[VAR_SEMI or VAR_COMMA]"
	jmp	gp1			; contine processing arguments
;
; Arguments exhausted, generate the print call.
;
gp8:	GENCALL	printArgs
	clc

gp9:	ret
ENDPROC	genPrint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCallCX
;
; Inputs:
;	CS:CX -> function to call
;
; Outputs:
;	None
;
; Modifies:
;	CX, DI
;
DEFPROC	genCallCX
	push	ax
	mov	al,OP_CALLF
	stosb
	xchg	ax,cx
	stosw
	mov	ax,cs
	stosw
	pop	ax
	ret
ENDPROC	genCallCX

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushImm
;
; Inputs:
;	DX = value to push
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	genPushImm
	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushImm

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
DEFPROC	genPushImmByte
	stosw
	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushImmByte

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
; if we determine that DX (yyyy) is a sign-extension of AX, we can
; generate this 6-byte sequence instead:
;
;	MOV	AX,xxxx
;	CWD
;	PUSH	DX
;	PUSX	AX
;
; and if AX (xxxx) is zero, it can be simplified to a 4-byte sequence
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
	xchg	ax,dx			; AX has original DX
	xchg	ax,cx			; AX contains CX, CX has original DX
	cwd				; DX is 0 or FFFFh
	cmp	dx,cx			; same as original DX?
	xchg	cx,ax			; AX contains original DX, CX restored
	xchg	dx,ax			; DX restored
	jne	gpil7			; no, DX is not the same
	jcxz	genPushZeroLong		; jump if we can zero AX as well
	mov	al,OP_MOV_AX
	stosb
	xchg	ax,cx
	stosw
	mov	ax,OP_CWD OR (OP_PUSH_DX SHL 8)
	stosw
	jmp	short gpil8
gpil7:	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	ax,OP_PUSH_AX OR (OP_MOV_AX SHL 8)
	stosw
	xchg	ax,cx
	stosw
gpil8:	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushImmLong

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
	mov	ax,OP_PUSH_AX OR (OP_PUSH_AX SHL 8)
	stosw
	ret
ENDPROC	genPushZeroLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushVarLong
;
; Generates code to push 4-byte variable data onto stack (eg, a VAR_LONG or
; a VAR_STR pointer).
;
; Inputs:
;	DS:DX -> var data
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	genPushVarLong
	mov	al,OP_MOV_SI		; "MOV SI,offset var data"
	stosb
	xchg	ax,dx
	stosw
	mov	ax,OP_LODSW OR (OP_XCHG_DX SHL 8)
	stosw
	mov	ax,OP_LODSW OR (OP_PUSH_AX SHL 8)
	stosw
	mov	al,OP_PUSH_DX
	stosb
	ret
ENDPROC	genPushVarLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextKeyword
;
; Like getNextToken but with AL preset to CLS_VAR, and if successful,
; the token is checked against the KEYWORDS table.
;
; Inputs:
;	BX -> TOKLETs
;
; Outputs:
;	CF clear if successful, AX = TOKDEF_ID (BX, CX, SI updated as well)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	getNextKeyword
	mov	al,CLS_VAR
	call	getNextToken
	jb	gk9
	stc
	je	gk9
	lea	dx,[KEYWORD_TOKENS]
	mov	ax,DOS_UTL_TOKID
	int	21h
gk9:	ret
ENDPROC	getNextKeyword

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextToken
;
; Return the next token if it matches the criteria in AL; by default,
; we ignore whitespace tokens.
;
; Inputs:
;	AL = CLS bits
;	BX -> TOKLETs
;
; Outputs if next token matches:
;	AH = CLS of token
;	AL = symbol if CLS_SYM
;	CX = length of token
;	SI = offset of token
;	BX = offset of next TOKLET
;	ZF and CF clear
;
; Outputs if NO matching next token:
;	ZF set if no matching token (AH is CLS), CF set if no more tokens
;	BX, CX, and SI unchanged
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	getNextToken
	cmp	bx,[pTokletEnd]
	cmc
	jb	gt9			; no more tokens
	mov	ah,[bx].TOKLET_CLS
	test	al,ah
	jnz	gt1
	test	ah,CLS_WHITE		; whitespace token?
	jz	gt9			; no (return ZF set)
	add	bx,size TOKLET		; yes, ignore it
	jmp	getNextToken

gt1:	mov	si,[bx].TOKLET_OFF
	mov	cl,[bx].TOKLET_LEN
	mov	ch,0
	lea	bx,[bx + size TOKLET]
;
; If we're about to return a CLS_SYM that happens to be a colon, then
; return ZF set (but not carry) to end the caller's token scan.
;
	cmp	ah,CLS_SYM
	jne	gt8
	mov	al,[si]
	cmp	al,':'
	je	gt9
gt8:	or	ah,0			; return both ZF and CF clear
gt9:	ret
ENDPROC	getNextToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekNextToken
;
; Return the next token if it matches the criteria in AL; by default,
; we ignore whitespace tokens.
;
; Inputs and outputs are the same as getNextToken, but we also save the
; offset of the next TOKLET, in case the caller wants to consume it.
;
DEFPROC	peekNextToken
	push	bx
	call	getNextToken
	mov	[pTokletNext],bx
	pop	bx
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
;	If carry clear, AL = op, AH = precedence, CX = args, DX = evaluator
;
; Modifies:
;	AH, CX, DX
;
DEFPROC	validateOp
	push	si
	xchg	dx,ax			; DL = operator to validate
	mov	al,CLS_SYM
	call	peekNextToken
	jbe	vo6
	mov	dh,al			; DX = potential 2-character operator
	mov	si,offset RELOPS
vo1:	lodsw
	test	al,al
	jz	vo6
	cmp	ax,dx			; match?
	lodsb
	jne	vo1
	mov	bx,[pTokletNext]
	xchg	dx,ax			; DL = (new) operator to validate
vo6:	mov	ah,dl			; AH = operator to validate
	mov	si,offset OPDEFS
vo7:	lodsb
	test	al,al
	stc
	jz	vo9			; not valid
	cmp	al,ah			; match?
	je	vo8			; yes
	add	si,size OPDEF - 1
	jmp	vo7
vo8:	lodsb				; AL = precedence, AH = operator
	xchg	dx,ax
	lodsb
	cbw
	xchg	cx,ax
	lodsw				; AX = evaluator
	xchg	dx,ax			; DX = evaluator, AX = op/prec
vo9:	xchg	al,ah			; AL = operator, AH = precedence
	pop	si
	ret
ENDPROC	validateOp

CODE	ENDS

	end
