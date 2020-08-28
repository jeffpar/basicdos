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
	EXTERNS	<appendStr,setStr,memError>,near
	EXTERNS	<clearScreen,printArgs,setColor>,near

	EXTERNS	<KEYWORD_TOKENS,KEYOP_TOKENS>,word
	EXTERNS	<OPDEFS,RELOPS>,byte
	EXTERNS	<TOK_ELSE,TOK_THEN>,abs

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCode
;
; Inputs:
;	DS:BX -> heap
;	DS:SI -> BUF_INPUT (or null to parse preloaded text)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	genCode
	LOCVAR	nArgs,word
	LOCVAR	nExpArgs,word
	LOCVAR	nExpVals,word
	LOCVAR	nExpParens,word
	LOCVAR	nExpPrevOp,word
	LOCVAR	errCode,word
	LOCVAR	pInput,word
	LOCVAR	pCode,dword
	LOCVAR	pTokNext,word
	LOCVAR	pTokEnd,word
	LOCVAR	lineNumber,word
	ENTER

	sub	ax,ax
	mov	[nArgs],ax
	mov	[errCode],ax
	mov	[pInput],si
	mov	[lineNumber],ax

	call	allocVars
	jc	gce
	call	allocCode
	jc	gce
	ASSUME	ES:NOTHING		; ES:DI -> code block
	mov	[pCode].OFF,di
	mov	[pCode].SEG,es
	mov	ax,OP_MOV_BP_SP		; make it easy for endProgram
	stosw				; to reset the stack and return
;
; ES:[CBLK_SIZE] is the absolute limit for pCode, but we also maintain
; another field, ES:[CBLK_REFS], as the top of a LBLREF stack, and that
; is the real limit that the code generator must be mindful of.
;
; Initialize the LBLREF stack; it's empty when CBLK_REFS = CBLK_SIZE.
;
	mov	es:[CBLK_REFS],cx

	mov	si,[pInput]
	test	si,si
	jz	gc1
	mov	cl,[si].INP_CNT
	mov	ch,0
	lea	si,[si].INP_BUF
	jmp	short gc4

gce:	call	memError
gcx:	jmp	gc9

gc1:	lea	si,[bx].TEXT_BLK
gc2:	mov	cx,[si].TBLK_NEXT
	clc
	jcxz	gc6			; nothing left to parse
	mov	ds,cx
	ASSUME	DS:NOTHING
	mov	si,size TBLK_HDR

gc3:	cmp	si,ds:[TBLK_FREE]
	jae	gc2			; advance to next block in chain
	inc	[lineNumber]
	lodsw
	call	addLabel		; add label AX to the LBLREF stack
	xchg	dx,ax			; DX = label #, if any
	lodsb
	mov	ah,0
	xchg	cx,ax			; CX = length of next line
	jcxz	gc3

gc4:	push	bx			; save heap offset
	push	cx
	push	ds
	push	si			; save text pointer + length
	push	es
	push	di			; save code gen pointer

	push	ss
	pop	es
;
; Copy the line (at DS:SI with length CX) to LINEBUF, so that we
; can use a single segment (DS) to address both LINEBUF and TOKENBUF
; once ES has been restored to the code gen segment.
;
	push	cx
	push	es
	lea	di,[bx].LINEBUF
	push	di
	rep	movsb
	xchg	ax,cx			; AL = 0
	stosb				; null-terminate for good measure
	pop	si
	pop	ds
	pop	cx			; DS:SI -> LINEBUF (with length CX)

	lea	di,[bx].TOKENBUF	; ES:DI -> TOKENBUF
	mov	ax,DOS_UTL_TOKIFY2
	int	21h
	mov	bx,di
	push	es
	pop	ds
	add	bx,offset TOK_BUF	; DS:BX -> TOKLET array
	pop	di
	pop	es			; restore code gen pointer
	jc	gc5

	add	ax,ax
	add	ax,ax
	add	ax,bx
	mov	[pTokEnd],ax

	call	genCommands		; generate code

gc5:	pop	si
	pop	ds
	pop	cx			; restore text pointer + length
	pop	bx			; restore heap offset
	jc	gc6			; error

	cmp	[pInput],0		; more text to parse?
	jne	gc6			; no (just a single line)

	add	si,cx			; advance past previous line of text
	jmp	gc3			; and check for more

gc6:	push	ss
	pop	ds
	ASSUME	DS:DATA
	jc	gc7
	mov	al,OP_RETF		; terminate the code in the buffer
	stosb

	push	bp
	push	ds
	push	es
	mov	si,ds:[PSP_HEAP]
	mov	ax,[si].VARS_BLK.BLK_NEXT
	mov	ds,ax
	mov	es,ax
	ASSUME	DS:NOTHING
	call	[pCode]			; execute the code buffer
	pop	es
	pop	ds
	ASSUME	DS:DATA
	pop	bp
	clc

gc7:	pushf
	call	freeCode
	popf
gc8:	jnc	gc9

	PRINTF	<'Syntax error in line %d',13,10>,lineNumber
	stc

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
	cmc
	jnc	gcs9
	lea	dx,[KEYWORD_TOKENS]	; CS:DX -> TOKTBL
	mov	ax,DOS_UTL_TOKID	; identify the token
	int	21h			; at DS:SI (with length CX)
	jc	gcs9			; can't identify
	cmp	ax,20			; supported keyword?
	jb	gcs9			; no
	test	dx,dx			; generator function?
	jz	gcs9			; no
	call	dx			; call the generator
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
; genDefInt
;
; Process "DEFINT" (TODO)
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
	clc
	ret
ENDPROC	genDefInt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genExprNum
;
; Generate code for a numeric expression.  To help catch errors up front,
; maintain a count of values queued, compare that to the number of arguments
; expected by all the operators, and also maintain an open parentheses count.
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
	mov	ax,DOS_UTL_TOKID	; CS:DX -> TOKTBL
	int	21h
	jnc	gn5			; jump to operator validation

	mov	dx,offset KEYWORD_TOKENS; see if token is a KEYWORD
	mov	ax,DOS_UTL_TOKID	; CS:DX -> TOKTBL
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
; Number must be a constant and CX must contain its exact length.
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
gn3a:	mov	ax,DOS_UTL_ATOI32	; DS:SI -> numeric string (length CX)
	int	21h
	xchg	cx,ax			; save result in DX:CX
	pop	bx
	GENPUSH	dx,cx
	jmp	gn2b			; go count another queued value
gn3x:	jmp	gn8
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
	jc	gn3x			; error
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
gn5a:	pop	dx			; "peek"
	cmp	dh,ah			; top precedence > current?
	jb	gn6			; no
	ja	gn5b			; yes
	test	dh,1			; unary operator?
	jnz	gn6			; yes, hold off
gn5b:	pop	cx			; pop the evaluator as well
	jcxz	gn6c			; no evaluator (eg, left paren)

	IFDEF MAXDEBUG
	DPRINTF	<"op %c, func @%08lx",13,10>,dx,cx,cs
	ENDIF

	GENCALL	cx			; and generate call
	jmp	gn5a

gn6:	push	dx			; "unpeek"
gn6a:	push	si			; push current evaluator
	push	ax			; push current operator/precedence
gn6b:	jmp	gn1			; next token
;
; We just popped an operator with no evaluator; if it's a left paren,
; we're done; otherwise, ignore it (eg, unary '+').
;
gn6c:	cmp	dl,'('
	je	gn6b
	jmp	gn5a
;
; When special (eg, no-arg) operators are encountered in the expression,
; they are handled here.
;
gn7:	cmp	al,'('
	jne	gn7a
	inc	[nExpParens]
	jmp	gn6a
gn7a:	ASSERT	Z,<cmp al,')'>
	dec	[nExpParens]
	jmp	gn5a
;
; We have reached the (presumed) end of the expression, so start popping
; the operator stack.
;
gn8:	pop	cx
	jcxz	gn9			; all done

	IFDEF MAXDEBUG
	pop	ax
	DPRINTF	<"op %c, func @%08lx...",13,10>,cx,ax,cs
	xchg	cx,ax
	ELSE
	pop	cx			; CX = evaluator
	ENDIF

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
	mov	ax,DOS_UTL_ATOI32D	; DS:SI -> decimal string
	int	21h
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
; addLabel
;
; Inputs:
;	AX = label #, if any
;	ES -> current code block
;
; Outputs:
;	Carry clear if successful, set if error (eg, duplicate label)
;
; Modifies:
;	CX, DX
;
DEFPROC	addLabel
	test	ax,ax			; is there a label?
	jz	al9			; no, nothing to do
	mov	dx,di			; DX = current code gen offset
	test	dx,LBL_RESOLVE		; is this a label reference?
	jnz	al8			; yes, just add it
;
; For label definitions, we scan the LBLREF stack to ensure this
; definition is unique.  We must also scan the stack for any unresolved
; references and fix them up.
;
	mov	cx,es:[CBLK_SIZE]
	mov	di,es:[CBLK_REFS]
	sub	cx,di
	jcxz	al8			; stack is empty
	shr	cx,1			; CX = # of words on LBLREF stack
al1:	repne	scasw			; scan all words for label #
	jne	al8			; nothing found
	test	di,(size LBLREF)-1	; did we match the first LBLREF word?
	jz	al1			; no (must have match LBL_IP instead)
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
	mov	cx,es:[CBLK_SIZE]
	mov	di,es:[CBLK_REFS]
	sub	cx,di
	jcxz	fl8			; stack is empty
	shr	cx,1			; CX = # of words on LBLREF stack
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
; genCallFar
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
DEFPROC	genCallFar
	push	ax
	mov	al,OP_CALLF
	stosb
	xchg	ax,cx
	stosw
	mov	ax,cs
	stosw
	pop	ax
	ret
ENDPROC	genCallFar

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
; if we determine that DX (yyyy) is a sign-extension of CX (xxxx),
; we can generate this 6-byte sequence instead:
;
;	MOV	AX,xxxx
;	CWD
;	PUSH	DX
;	PUSX	AX
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
	DPRINTF	<"num %ld",13,10>,cx,dx
	ENDIF
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
; Generates code to push 4-byte variable data onto stack (eg, a VAR_LONG
; integer or a VAR_STR pointer).
;
; DX must contain the var block offset of the variable, which the generated
; code will load using SI, so that it can use a pair of LODSW instructions to
; load the variable's data and push onto the stack.
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
; getNextToken
;
; Return the next token if it matches the criteria in AL; by default,
; we ignore whitespace tokens.
;
; Inputs:
;	AL = CLS bits
;	DS:BX -> TOKLETs
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
	cmp	bx,[pTokEnd]
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
	mov	[pTokNext],bx
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
	mov	bx,[pTokNext]
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
	lods	word ptr cs:[si]	; AX = evaluator
	xchg	dx,ax			; DX = evaluator, AX = op/prec
vo9:	xchg	al,ah			; AL = operator, AH = precedence
	pop	si
	ret
ENDPROC	validateOp

CODE	ENDS

	end
