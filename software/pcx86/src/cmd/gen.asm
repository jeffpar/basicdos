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
	EXTERNS	<memError>,near
	EXTERNS	<clearScreen,doCmd,printArgs,printEcho,printLine>,near
	EXTERNS	<setColor,setFlags>,near

	EXTERNS	<KEYWORD_TOKENS,KEYOP_TOKENS>,word
	EXTERNS	<OPDEFS_LONG,OPDEFS_STR,RELOPS>,byte
	EXTERNS	<TOK_ELSE,TOK_OFF,TOK_ON,TOK_THEN>,abs

	IFDEF	LATER
	EXTERNS	<SYNTAX_TABLES,SCF_TABLE>,word
	ENDIF	; LATER

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCode
;
; Inputs:
;	AL = GEN flags (eg, GEN_BATCH)
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
	LOCVAR	pHeap,word
	LOCVAR	pDefVars,word		; used by genDef*
	LOCVAR	defToks,byte		; used by genExpr
	LOCVAR	defType,byte		; used by genDef* and genExpr
	LOCVAR	genFlags,byte
	LOCVAR	nArgs,word
	LOCVAR	nExpArgs,word
	LOCVAR	nExpVals,word
	LOCVAR	nExpParens,word
	LOCVAR	nExpPrevOp,word
	LOCVAR	errCode,word
	LOCVAR	pInput,word		; original input address
	LOCVAR	pCode,dword		; original start of generated code
	LOCVAR	pLine,dword		; address of the current line
	LOCVAR	cbLine,word		; length of the current line
	LOCVAR	pTokNext,word
	LOCVAR	pTokEnd,word
	LOCVAR	pSynToken,word
	LOCVAR	lineNumber,word
	ENTER

	mov	[pHeap],bx
	test	al,GEN_BATCH
	jz	gc0
	or	al,GEN_ECHO
gc0:	mov	[genFlags],al
	sub	ax,ax
	mov	[nArgs],ax
	mov	[errCode],ax
	mov	[pInput],si
	mov	[lineNumber],ax
	lea	ax,[bx].DEFVARS
	mov	[pDefVars],ax

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
; another field, ES:[CBLK_REFS], as the bottom of a LBLREF table, and that
; is the real limit that the code generator must be mindful of.
;
; Initialize the LBLREF table; it's empty when CBLK_REFS = CBLK_SIZE.
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
	jmp	gc9

gc1:	lea	si,[bx].TBLK_DEF
gc2:	mov	cx,[si].TBLK_NEXT
	clc
	jcxz	gc3b			; nothing left to parse
	mov	ds,cx
	ASSUME	DS:NOTHING
	mov	si,size TBLK_HDR

gc3:	cmp	si,ds:[TBLK_FREE]
	jae	gc2			; advance to next block in chain
	inc	[lineNumber]
	lodsw
	test	ax,ax			; is there a label #?
	jz	gc3a			; no
	call	addLabel		; yes, add it to the LBLREF table
gc3a:	xchg	dx,ax			; DX = label #, if any
	lodsb				; AL = length byte
	mov	ah,0
	xchg	cx,ax			; CX = length of line
	jcxz	gc3			; empty line, nothing to do
;
; As a preliminary matter, if we're processing a BAT file, then generate
; code to print the line, unless it starts with a '@', in which case, skip
; over the '@'.
;
	cmp	byte ptr [si],'@'
	jne	gc3c
	inc	si
	dec	cx
	jz	gc3
	jmp	short gc4
gc3b:	jmp	short gc6

gc3c:	test	[genFlags],GEN_ECHO
	jz	gc4
	push	cx
	lea	cx,[si-1]
	GENPUSH	ds,cx			; DX:CX -> string (at the length byte)
	GENCALL	printLine
	pop	cx

gc4:	mov	bx,[pHeap]
	mov	[cbLine],cx
	mov	[pLine].OFF,si
	mov	[pLine].SEG,ds		; save text pointer and length
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
	DOSUTIL	DOS_UTL_TOKIFY2
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

gc5:	lds	si,[pLine]		; restore text pointer and length
	mov	cx,[cbLine]
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
;
; TODO: Define the memory model for the generated code.  For now, the
; only requirement is that DS always point to the var block (which means
; that all variables must fit in a single var block).
;
	push	bp
	push	ds
	mov	si,[pHeap]
	mov	ax,[si].VBLK_DEF.BLK_NEXT
	mov	ds,ax
	ASSUME	DS:NOTHING
	call	[pCode]			; execute the code buffer
	pop	ds
	ASSUME	DS:DATA
	pop	bp
	clc

gc7:	pushf
	call	freeCode
	popf
gc8:	jnc	gc9

	PRINTF	<"Syntax error in line %d",13,10>,lineNumber
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
	jbe	gcs9			; out of tokens
	mov	dx,cs:[si].CTD_FUNC	;
	cmp	al,KEYWORD_GENCODE	; keyword support generated code?
	jb	gcs9			; no
	cmp	al,KEYWORD_LANGUAGE	; is keyword part of the language?
	jb	gcs2			; no
gcs1:	test	dx,dx			; command address?
	jz	gcs9			; no

	IFDEF	LATER
	cmp	dx,offset SYNTAX_TABLES	; syntax table address?
	jb	gcs6			; no, dedicated generator function
	call	synCheck		; yes, process syntax table
	jmp	short gcs8
	ELSE
	jmp	short gcs6		; call generator function
	ENDIF	; LATER
;
; For keywords that are BASIC-DOS extensions, we need to generate a call
; to doCmd with a pointer to the full command-line and the keyword handler.
; doCmd will then perform the traditional parse-and-execute logic.
;
gcs2:	xchg	ax,dx			; AX = handler address
	mov	dx,offset genCmd
	mov	[pTokEnd],bx		; mark the tokens fully processed

gcs6:	call	dx			; call dedicated generator function

gcs7:	mov	es:[CBLK_FREE],di

gcs8:	jnc	genCommands

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
	clc
	ret
ENDPROC	genCLS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCmd
;
; Generate code for generic commands.
;
; Inputs:
;	AX = handler
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genCmd
	xchg	dx,ax
	GENPUSH	dx
	mov	cx,[pLine].OFF
	mov	dx,[pLine].SEG
	GENPUSH	dx,cx
	mov	dx,[cbLine]
	GENPUSH	dx
	GENCALL	doCmd
	clc
	ret
ENDPROC	genCmd

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
	mov	word ptr [nArgs],0
gco1:	call	genExpr
	jb	gco9
	je	gco8
	cmp	al,','			; was the last symbol a comma?
	je	gco1			; yes, go back for more
gco8:	GENPUSH	nArgs
	GENCALL	setColor
	clc
gco9:	ret
ENDPROC	genColor

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

	mov	al,CLS_SYM		; check for hyphen
	call	getNextToken
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
; For every letter from DL through DH, set pDefVars[DL] to defType.
;
gdi3:	push	bx
	mov	cl,dh
	sub	cl,dl
	mov	ch,0
	inc	cx			; CX = # of letters to set
	mov	al,[defType]		; AL = new default for each letter
	mov	bx,[pDefVars]
	sub	dl,'A'
	add	bl,dl
	adc	bh,ch			; BX -> 1st letter
gdi3a:	mov	[bx],al
	inc	bx
	loop	gdi3a
	pop	bx

	mov	al,CLS_SYM		; check for comma
	call	getNextToken
	jbe	gdi9
	cmp	al,','
	je	genDefVar

gdi8:	stc
gdi9:	ret

	DEFLBL	getCharToken,near
	mov	al,CLS_VAR		; token must be CLS_VAR
	push	dx
	call	getNextToken
	pop	dx
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
	mov	ah,CMD_ECHO
	jmp	short gec8
gec2:	cmp	al,TOK_OFF
	stc
	jne	gec9
	mov	ah,NOT CMD_ECHO
gec8:	mov	al,OP_MOV_AL
	stosw				; "MOV AL,xx" where XX is value in AH
	GENCALL	setFlags
	clc
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
;	BX = offset of next TOKLET
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
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	genExpr
	sub	dx,dx
	mov	word ptr [defType],dx	; defType = VAR_NONE, defToks = 0
	mov	[nExpArgs],1		; count of expected arguments
	mov	[nExpVals],dx		; count of values queued
	mov	[nExpParens],dx		; count of open parentheses
	mov	[nExpPrevOp],dx		; previous operator (none)
	push	dx			; push end-of-operators marker (zero)

gn1:	mov	al,CLS_ANY		; CLS_NUM, CLS_SYM, CLS_VAR, CLS_STR
	call	getNextToken
	jbe	gn2x
	inc	[defToks]
	cmp	ah,CLS_SYM
	je	gn4			; process CLS_SYM below
;
; Non-operator (non-symbol) cases: keywords, variables, strings, and numbers.
;
	mov	byte ptr [nExpPrevOp],-1; invalidate prevOp (intervening token)
	cmp	ah,CLS_KEYWORD
	je	gn2x			; keywords not allowed in expressions
	cmp	ah,CLS_VAR		; variable with type?
	ASSERT	NE			; (type should be fully qualified now)
	ja	gn2			; yes
;
; Must be CLS_STR or CLS_NUM.  Handle CLS_STR here and CLS_NUM below.
;
	test	ah,CLS_STR		; string?
	jz	gn3			; no, must be number
	mov	al,VAR_STR		; AL = VAR_STR
	call	setExprType		; update expression type
	jnz	gn2x
	sub	cx,2			; CX = string length
	ASSERT	NC
	jcxz	gn1a			; empty string
	inc	si			; DS:SI -> string contents
	call	genPushStr
	jmp	short gn2a

gn1a:	DBGBRK
	sub	cx,cx			; for empty strings, push null ptr
	sub	dx,dx
	call	genPushImmLong
	jmp	short gn2a
;
; Process CLS_VAR.  We don't care if findVar succeeds or not, because
; even if it fails, it returns var type (AH) VAR_LONG with var data (DX)
; preset to zero.
;
; We do, however, care about the var type (AH), which must be consistent
; with the expression type (currently, VAR_LONG or VAR_STR).
;
gn2:	call	findVar			; no, check vars next
	mov	al,ah			; AL = var type
	call	setExprType		; update expression type
	jnz	gn2x			; error
	call	genPushVarLong

gn2a:	inc	[nExpVals]		; count another queued value
	jmp	gn1
gn2x:	jmp	short gn3x
;
; Process CLS_NUM.  Number is a constant and CX is its exact length.
;
; TODO: If the preceding character is a '-' and the top of the operator stack
; is 'N' (unary minus), consider decrementing SI and removing the operator.
; Why? Because it's better for ATOI32 to know up front that we're dealing with
; a negative number, because then it can do precise overflow checks.
;
gn3:	mov	al,VAR_LONG		; AL = VAR_LONG
	call	setExprType		; update expression type
	jnz	gn3x			; error
	push	bx
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
gn3a:	DOSUTIL	DOS_UTL_ATOI32		; DS:SI -> numeric string (length CX)
	xchg	cx,ax			; save result in DX:CX
	pop	bx
	GENPUSH	dx,cx
	jmp	gn2a			; go count another queued value

gn3s:	mov	ah,CLS_SYM
gn3x:	jmp	short gn8
;
; Process CLS_SYM.  Before we try to validate the operator, we need to remap
; binary minus to unary minus.  So, if we have a minus, and the previous token
; is undefined, or another operator, or a left paren, it's unary.  Ditto for
; unary plus.  The internal identifiers for unary '-' and '+' are 'N' and 'P'.
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
	jc	gn3s			; error (reset AH to CLS_SYM)
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
	DPRINTF	'o',<"op %c, func @%08lx",13,10>,dx,cx,cs
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
; When special (eg, zero arg) operators are encountered in the expression,
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
	DPRINTF	'o',<"op %c, func @%08lx...",13,10>,cx,ax,cs
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
gn10:	mov	dx,word ptr [defType]	; DL = expression type, DH = # tokens
	ret

	DEFLBL	setExprType,near
	cmp	[defType],al
	je	set9
	cmp	[defType],0
	jne	set9
	mov	[defType],al
set9:	ret				; return ZF set if type is OK

ENDPROC	genExpr

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
	DOSUTIL	DOS_UTL_ATOI32D		; DS:SI -> decimal string
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
gife:	stc
	ret
ENDPROC	genIf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLet
;
; Generate code to "let" a variable equal some expression.  We'll start with
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

	mov	al,ah			; AL = CLS
gl1:	call	addVar			; DX -> var data
	jc	gl9

	push	ax
	call	genPushDSDX
	mov	al,CLS_SYM
	call	getNextToken
	pop	dx
	jbe	gl9

	cmp	al,'='
	stc
	jne	gl9

	call	genExpr
	jc	gl9
	GENCALL	setVarLong		; TODO: check expression type in DL

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

gp1:	call	genExpr
	jnc	gp2
	test	dh,dh			; if there were no tokens
	stc				; then ignore the error
	jnz	gp9			; (PRINT without args is allowed)
gp2:	jz	gp8
	push	ax
	mov	al,VAR_LONG		; AL = default type
	cmp	dl,al			; does that match the expression type?
	je	gp3			; yes
	mov	al,VAR_STR		; must be VAR_STR then
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
	jmp	gp1			; contine processing arguments

gp8:	GENCALL	printArgs
	clc

gp9:	ret
ENDPROC	genPrint

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
	DPRINTF	'l',<"%#010P: line %d: adding label %d...",13,10>,lineNumber,ax

	mov	dx,di			; DX = current code gen offset
	test	dx,LBL_RESOLVE		; is this a label reference?
	jnz	al8			; yes, just add it
;
; For label definitions, we scan the LBLREF table to ensure this
; definition is unique.  We must also scan the table for any unresolved
; references and fix them up.
;
	mov	cx,es:[CBLK_SIZE]
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
	DPRINTF	'l',<"%#010P: line %d: finding label %d...",13,10>,lineNumber,ax

	push	di
	mov	cx,es:[CBLK_SIZE]
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
; genPushDSDX
;
; Inputs:
;	DS:DX = value to push
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	genPushDSDX
	mov	al,OP_PUSH_DS
	stosb
	DEFLBL	genPushImm,near
	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushDSDX

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
	DPRINTF	'o',<"num %ld",13,10>,cx,dx
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
;	AX, BX, CX, DX, SI
;
DEFPROC	getNextToken
	cmp	bx,[pTokEnd]
	jb	gt0
	sub	ax,ax
	jmp	gt9			; no more tokens (ZF set, CF clear)

gt0:	mov	ah,[bx].TOKLET_CLS
	test	ah,al
	jnz	gt1
	cmp	ah,CLS_WHITE		; whitespace token?
gt0a:	stc
	jne	gt9			; no (CF set)
	add	bx,size TOKLET		; yes, so ignore it
	jmp	getNextToken

gt1:	cmp	al,CLS_KEYWORD		; looking for keyword?
	jne	gt1a			; no
	cmp	ah,CLS_VAR		; yes, undecorated CLS_VAR?
	jne	gt0a			; no, can't be a keyword then

gt1a:	mov	si,[bx].TOKLET_OFF
	mov	cl,[bx].TOKLET_LEN
	mov	ch,0
	add	bx,size TOKLET
	mov	dl,al			; DL = requested CLS
	mov	al,[si]			; AL = 1st character of token
	cmp	al,'a'			; ensure 1st character is upper-case
	jb	gt2
	sub	al,20h
;
; Any CLS_VAR with additional bits specifying the variable type (eg,
; CLS_VAR_LONG, CLS_VAR_STR) is done.  Any vanilla CLS_VAR, however, must
; be further identified.  We now check for keyword operators (like NOT) and
; all other keywords.  Failing that, we assume it's a variable, so we look
; up the variable's implicit type and update the CLS bits accordingly.
;
gt2:	cmp	ah,CLS_VAR
	jne	gt7

	push	ax
	push	dx
	mov	dx,offset KEYOP_TOKENS	; see if token is a KEYOP
	DOSUTIL	DOS_UTL_TOKID		; CS:DX -> TOKTBL
	jc	gt2a
	mov	ah,CLS_SYM		; AL = TOKDEF_ID, SI -> TOKDEF
	jnc	gt2b
gt2a:	mov	dx,offset KEYWORD_TOKENS; see if token is a KEYWORD
	DOSUTIL	DOS_UTL_TOKID		; CS:DX -> TOKTBL
	jc	gt2c
	mov	ah,CLS_KEYWORD		; AL = TOKDEF_ID, SI -> TOKDEF
gt2b:	pop	dx
	pop	dx
	jmp	short gt8
gt2c:	pop	dx			; neither KEYOP nor KEYWORD
	pop	ax
	cmp	dl,CLS_KEYWORD		; and did we request a KEYWORD?
	stc
	je	gt9			; yes, return error

	push	bx
	push	ax
	mov	bx,[pDefVars]
	sub	al,'A'			; convert 1st letter to DEFVARS index
	xlat				; look up the default VAR type
	test	al,al			; has a default been set?
	jnz	gt4			; yes
	mov	al,VAR_LONG		; no, default to VAR_LONG
gt4:	mov	ah,al
	or	ah,CLS_VAR
	pop	bx			; we're really popping AX
	mov	al,bl			; and restoring AL
	pop	bx
	jmp	short gt8
;
; If we're about to return a CLS_SYM that happens to be a colon, then return
; ZF set (but not carry) to end the caller's token scan.
;
gt7:	cmp	ah,CLS_SYM
	jne	gt8

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
; Modifies:
;	AX, CX, SI
;
DEFPROC	peekNextToken
	push	bx
	push	dx
	call	getNextToken
	mov	[pTokNext],bx
	pop	dx
	pop	bx
	ret
ENDPROC	peekNextToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; synCheck
;
; Inputs:
;	CS:DX -> syntax table
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
	IFDEF	LATER
DEFPROC	synCheck
	mov	si,dx			; CS:SI -> syntax table
;
; Loop until we find an SC_PEKTK that matches the next token.
;
sc1:	lods	word ptr cs:[si]	; AL = next SC_* value
	test	al,al
	jl	sc8c
	cmp	al,SC_GENPB		; invoke GENPUSHB? (71h)
	jne	sc2			; no
	GENPUSHB ah
	jmp	sc1
sc2:	cmp	al,SC_PEKTK		; invoke peekNextToken? (73h)
	jne	sc1			; no
	mov	al,ah			; AL = mask for peekNextToken
	push	si
	mov	[pSynToken],si		; remember where the SC_PEKTK was
	call	peekNextToken
	pop	si
	jz	sc8			; nope, wrap it up
	jc	sc1			; look for next SC_PEKTK
;
; We found a token of the specified CLS, so look for a more specific match.
;
sc3:	xchg	dx,ax			; DH = token CLS, DL = token char
sc3a:	lods	word ptr cs:[si]	; AL = next SC_* value
	cmp	al,SC_MATCH		; (74h)
	je	sc3b
	cmp	al,SC_MASYM		; (75h)
	ja	sc8			; never found a match, wrap up
	jne	sc3a
	mov	al,ah
	mov	ah,CLS_SYM
	cmp	dx,ax
	jne	sc3a
	push	si
	call	getNextToken
	pop	si
	jmp	short sc4
sc3b:	cmp	dh,ah			; match?
	je	sc4			; yes
	cmp	ah,CLS_ANY		; any CLS OK? (3Fh)
	jne	sc3a			; no
;
; Perform operations < SC_PEKTK.  If an operation reports an error (CF set),
; the call is terminated; if it reports no valid data (ZF set), we wrap it up.
;
sc4:	lods	word ptr cs:[si]
	sub	dx,dx			; allow SC_NEXTK
	cmp	al,SC_CALFN		; call an SCF function? (72h)
	ja	sc8b			; done with match, wrap up
	jne	sc4b			; no
	mov	al,ah
	cbw				; AX = SCF #
	add	ax,ax			; convert to word offset
	push	si
	xchg	si,ax			; SI -> SCF function
	call	cs:SCF_TABLE[si]
	pop	si
	jc	sc9
	jz	sc8
	test	ax,ax			; was there a previous token?
	jz	sc4			; no
	sub	bx,size TOKLET		; yes, back up to the previous token
	jmp	sc4
sc4b:	cmp	al,SC_GENPB		; invoke GENPUSHB? (71h)
	jne	sc2			; no
	GENPUSHB ah
	jmp	sc4
;
; To wrap up, scan the syntax table for a final SC_GENFN and then exit,
; unless there's an SC_NEXTK entry, in which case we go back for more tokens.
;
sc8:	mov	dx,-1
sc8a:	lods	word ptr cs:[si]	; AL = next SC_* value
sc8b:	test	al,al			; end of table?
sc8c:	jl	sc9			; OK, just leave
	cmp	al,SC_NEXTK		; (76h)
	jne	sc8d
	inc	dx			; should we look for more tokens?
	jz	sc8			; no
	mov	si,[pSynToken]
	sub	si,2			; go peek for more tokens
	jmp	sc1
sc8d:	cmp	al,SC_GENFN		; have we found SC_GENFN yet? (77h)
	jne	sc8a			; no
	mov	al,ah
	cbw				; AX = SCF #
	add	ax,ax			; convert to word offset
	xchg	si,ax			; SI -> SCF function
	mov	cx,cs:SCF_TABLE[si]
	GENCALL cx
	clc
sc9:	ret
ENDPROC	synCheck
	ENDIF	; LATER

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
	mov	si,offset OPDEFS_LONG
	cmp	[defType],VAR_STR
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
