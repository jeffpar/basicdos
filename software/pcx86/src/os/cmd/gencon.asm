;
; BASIC-DOS Code Generator: Console I/O
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these console I/O statements:
;
;	CLS				(genCLS)
;	COLOR				(genColor)
;	ECHO				(genEcho)
;	LOCATE				(genLocate)
;	PRINT				(genPrint)
;	SCREEN				(genScreen)
;	WIDTH				(genWidth)
;
; See gen.asm for an overview of all the gen*.asm files.  Like gen.asm, these
; functions are called while generating code, with DS:BX -> TOKLETs and ES:DI
; -> code block.
;
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,getNextToken,genCallCS,genPushImm,genPushImmByte>
	EXTNEAR	<genPushImmByteAL,genPushImmByteAH,genPushImmLong,genCvtType>
	EXTNEAR	<peekNextSymbol>
	EXTNEAR	<clearScreen,printArgs,printEcho,setColor,setFlags>
	EXTNEAR	<setPos,setScreen,setWidth>
	EXTABS	<TOK_OFF,TOK_ON>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

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
; Generate code for "COLOR [fgnd][,[bgnd][,border]]"
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
	mov	si,offset setColor
	jmp	short genArgs
ENDPROC	genColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genLocate
;
; Generate code for "LOCATE [row][,[col][,cursor]]"
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
DEFPROC	genLocate
	mov	si,offset setPos
	jmp	short genArgs
ENDPROC	genLocate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genScreen
;
; Generate code for "SCREEN [mode][,burst]"
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
DEFPROC	genScreen
	mov	si,offset setScreen
	jmp	short genArgs
ENDPROC	genScreen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genWidth
;
; Generate code for "WIDTH columns"
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
DEFPROC	genWidth
	mov	si,offset setWidth	; fall into genArgs
ENDPROC	genWidth

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genArgs
;
; Generate code to push a series of numeric arguments (as longs), followed by
; the number of arguments, and then a call to the function in SI, which must
; begin by calling getArgs.  An omitted argument (eg, the 1st argument in
; "LOCATE ,5") is pushed as -1.
;
; Inputs:
;	SI = offset of function (in our CODE segment)
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genArgs
	push	si			; save the function
	sub	cx,cx			; CX = # args
ga1:	call	peekNextSymbol
	jbe	ga2			; not a symbol
	cmp	al,','			; omitted argument?
	jne	ga2			; no
	mov	si,ds:[PSP_HEAP]
	mov	bx,[si].TOKLET_NEXT	; consume the comma
	push	cx
	GENPUSH	-1,-1
	pop	cx
	inc	cx
	jmp	ga1
ga2:	call	genExpr
	jb	ga9
	je	ga8
	push	ax
	push	cx
	mov	al,VAR_LONG
	call	genCvtType		; arguments must be longs
	pop	cx
	pop	ax
	jc	ga9
	inc	cx
	cmp	al,','			; was the last symbol a comma?
	je	ga1			; yes, go back for more
ga8:	GENPUSH	cx
	pop	cx
	GENCALL	cx
	ret
ga9:	pop	si			; discard the function
	ret
ENDPROC	genArgs

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
	mov	al,dl			; AL = VAR_LONG, VAR_STR, or VAR_DOUBLE
	GENPUSHB al
	pop	ax
	cmp	ah,CLS_KEYWORD		; did a keyword (eg, ELSE) end the
	je	gp8			; expression?
	cmp	ax,(CLS_SYM SHL 8) OR ':'; or a colon?
	je	gp8			; yes, so we're done
	mov	ah,VAR_COMMA		; comma (03h)
	cmp	al,','			; was the last symbol a comma?
	je	gp6			; yes
;
; Semi-colon is the other valid separator, but we no longer explicitly
; check for it, because historically PRINT presumes a semi-colon whenever
; a pair of values are separated only by whitespace (eg, if A = 2 and B = 3,
; "PRINT A B" behaves exactly like "PRINT A;B", displaying " 2  3").
;
; Unfortunately, in MSBASIC, that's only true for variables, not constants
; (eg, "PRINT 2 3" will print the number "23").  This is a parsing difference
; which we neither approve of nor emulate.
;
	mov	ah,VAR_SEMI		; presume semi-colon (02h) then
	test	al,al
	jz	gp8

gp6:	GENPUSHB ah			; "MOV AL,[VAR_SEMI or VAR_COMMA]"
	jmp	gp1			; continue processing arguments
gp8:	GENCALL	printArgs		; all done
gp9:	ret
ENDPROC	genPrint

CODE	ENDS

	end
