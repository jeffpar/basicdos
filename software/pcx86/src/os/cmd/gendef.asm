;
; BASIC-DOS Code Generator: Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these commands:
;
;	DIM				(genDim: dimension arrays)
;	ERASE				(genErase: erase arrays, or delete
;					files, like DEL, if the first name is
;					not an array)
;	OPTION BASE			(genOption: set the lower bound of
;					subsequently dimensioned arrays)
;
; and for array element references (genArrayRef), which genExpr and genLet
; use.  See arr.asm for the array functions that the generated code calls.
;
; See gen.asm for an overview of all the gen*.asm files.  Like gen.asm, these
; functions are called while generating code, with DS:BX -> TOKLETs and ES:DI
; -> code block.
;
; NOTE: Unlike genExpr, these functions must NOT use ENTER, because they
; call functions (eg, genPushVarPtr) that access genCode's local variables.
;
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<addVar,findVar,genExpr,genCvtType,genCallCS,genPushImm>
	EXTNEAR	<genPushVarPtr,getNextToken,getNextSymbol,peekNextSymbol>
	EXTNEAR	<genDOS,cmdDel>
	EXTNEAR	<dimArray,getElemPtr,getElemVal,eraseArray,setOptBase>
	EXTABS	<TOK_BASE,TOK_DEL>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

ARRAY_VAL	equ	0		; push element value (or double ptr)
ARRAY_PTR	equ	1		; push element address (eg, for LET)
ARRAY_DIM	equ	2		; dimension the array (for DIM)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genArrayRef
;
; If the variable is followed by a parenthesis and isn't a function, it's
; an array reference, so we generate code to push the array variable, the
; subscripts (converted to longs), and the element type and # of subscripts,
; followed by a call to the appropriate array function.
;
; Inputs:
;	AL = ARRAY_VAL, ARRAY_PTR, or ARRAY_DIM
;	AH = element type (VAR_LONG, VAR_DOUBLE, or VAR_STR)
;	CX = length of name
;	DS:SI -> name
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry set if error; otherwise:
;	ZF set if not an array reference (AH, CX, and SI are preserved)
;	ZF clear if code was generated (AH = element type)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	genArrayRef
	push	si
	push	cx
	push	ax			; AL = mode, AH = element type
	cmp	al,ARRAY_DIM		; DIM?
	je	gar2			; yes, so it must be an array
	call	peekNextSymbol		; next symbol a parenthesis?
	jbe	gar1			; no
	cmp	al,'('
	jne	gar1			; no
	pop	ax
	push	ax
	call	findVar			; is the variable a function?
	jc	gar2			; it doesn't exist, so it's not
	cmp	ah,VAR_FUNC
	jne	gar2			; no
gar1:	pop	ax
	pop	cx
	pop	si
	cmp	al,al			; ZF set (not an array), CF clear
	ret

gar2:	pop	ax
	pop	cx
	pop	si
	push	ax
	mov	al,1
	call	findArray		; DX:SI -> array variable
	jc	gar8
	call	genPushVarPtr
	call	getNextSymbol		; consume the parenthesis
	jbe	gar8
	cmp	al,'('
	jne	gar8
	sub	cx,cx			; CX = # of subscripts
gar3:	push	cx
	call	genExpr			; DL = subscript type
	pop	cx
	jbe	gar8			; no subscript
	push	ax			; AX = last token
	push	cx
	mov	al,VAR_LONG
	call	genCvtType		; convert subscript to a long
	pop	cx
	pop	ax
	jc	gar8
	inc	cx
	cmp	ah,CLS_SYM		; was the last token a symbol?
	jne	gar8			; no
	cmp	al,','			; another subscript?
	je	gar3			; yes
	cmp	al,')'			; end of subscripts?
	jne	gar8			; no
	pop	ax
	push	ax
	mov	dl,cl
	mov	dh,ah			; DX = element type and # subscripts
	GENPUSH	dx
	pop	ax
	push	ax
	mov	cx,offset dimArray
	cmp	al,ARRAY_DIM
	je	gar4
	mov	cx,offset getElemPtr
	cmp	al,ARRAY_PTR
	je	gar4
	cmp	ah,VAR_DOUBLE		; doubles are passed by reference
	je	gar4
	mov	cx,offset getElemVal
gar4:	GENCALL	cx
	pop	ax			; AH = element type
	or	al,1			; ZF clear, CF clear
	ret
gar8:	pop	ax
	stc
	ret
ENDPROC	genArrayRef

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findArray
;
; Array variables are named with the array's name followed by a character
; indicating the element type ('%' for VAR_LONG, '#' for VAR_DOUBLE, and '$'
; for VAR_STR), so that (for example) A, A(), and A$() are all different.
;
; Inputs:
;	AL = 0 to find the array variable, 1 to add it (if it doesn't exist)
;	AH = element type
;	CX = length of name
;	DS:SI -> name
;
; Outputs:
;	If carry clear, DX:SI -> array variable
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	findArray
	push	di
	push	es
	sub	sp,32
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> name buffer on stack
	cmp	cx,30
	jbe	fa1
	mov	cx,30
fa1:	push	di
	rep	movsb			; copy the name
	xchg	dx,ax			; DL = mode, DH = element type
	mov	al,'%'
	cmp	dh,VAR_LONG
	je	fa2
	mov	al,'$'
	cmp	dh,VAR_STR
	je	fa2
	mov	al,'#'
fa2:	stosb				; followed by the type character
	pop	si			; DS:SI -> name buffer (DS = SS)
	mov	cx,di
	sub	cx,si			; CX = length of array variable name
	mov	ah,VAR_ARRAY
	test	dl,dl
	jz	fa3
	call	addVar
	jmp	short fa4
fa3:	call	findVar
fa4:	jc	fa8
	add	sp,32
	pop	es
	pop	di
	ret
fa8:	add	sp,32
	pop	es
	pop	di
	stc
	ret
ENDPROC	findArray

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDim
;
; Generate code for "DIM array(bounds)[,array(bounds)]...".
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
DEFPROC	genDim
gdm1:	mov	al,CLS_VAR
	call	getNextToken
	jbe	gdm8
	and	ah,VAR_TYPE		; AH = element type
	mov	al,ARRAY_DIM
	call	genArrayRef
	jc	gdm9
	call	getNextSymbol		; another array?
	jbe	gdm9			; no
	cmp	al,','
	je	gdm1
gdm8:	stc
gdm9:	ret
ENDPROC	genDim

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genErase
;
; Generate code for "ERASE array[,array]...".  Since ERASE is also the same
; as DEL in BASIC-DOS, if the first name isn't an existing array, then we
; generate code for the DOS command instead.
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
DEFPROC	genErase
	push	bx			; save the token and code positions
	push	di			; (in case this is a DOS command)
ger1:	mov	al,CLS_VAR
	call	getNextToken
	jbe	ger7
	and	ah,VAR_TYPE		; AH = element type
	mov	al,0
	call	findArray		; DX:SI -> array variable
	jc	ger7
	call	genPushVarPtr
	GENCALL	eraseArray
	call	getNextSymbol		; another array?
	jbe	ger8			; no
	cmp	al,','
	je	ger1
	stc				; not a comma, so it's an error
	jmp	short ger8
;
; If the first name isn't an array (ie, no code has been generated yet), then
; it's a DOS command after all.
;
ger7:	mov	si,sp
	cmp	di,ss:[si]		; any code generated?
	stc
	jne	ger8			; yes, so it's an error
	pop	di
	pop	bx			; rewind
	mov	ax,TOK_DEL		; and generate the DEL command
	mov	dx,offset cmdDel
	jmp	genDOS
ger8:	pop	si			; discard the saved positions
	pop	si			; (POP doesn't modify flags)
	ret
ENDPROC	genErase

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genOption
;
; Generate code for "OPTION BASE 0" or "OPTION BASE 1".
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
DEFPROC	genOption
	mov	al,CLS_KEYWORD
	call	getNextToken
	jbe	gop8
	cmp	al,TOK_BASE
	jne	gop8
	mov	al,CLS_NUM
	call	getNextToken
	jbe	gop8
	cmp	cx,1			; must be a single digit
	jne	gop8
	mov	ah,[si]
	sub	ah,'0'
	cmp	ah,1			; 0 or 1
	ja	gop8
	mov	al,OP_MOV_AL
	stosw				; "MOV AL,xx" where XX is value in AH
	GENCALL	setOptBase
	ret
gop8:	stc
	ret
ENDPROC	genOption

CODE	ENDS

	end
