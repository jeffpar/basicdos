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
;	DEF				(genDefFn: user-defined functions,
;					via genDef in gensys.asm)
;	DIM				(genDim: dimension arrays)
;	ERASE				(genErase: erase arrays, or delete
;					files, like DEL, if the first name is
;					not an array)
;	OPTION BASE			(genOption: set the lower bound of
;					subsequently dimensioned arrays)
;
; and for array element references (genArrayRef), which genExpr and genLet
; use, and entire integer arrays (genArrayVar), which GET and PUT use.  See arr.asm for the array functions that the generated code calls.
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
	EXTNEAR	<setVar,removeVar,allocTempVars,updateTempVars,freeTempVars>
	EXTNEAR	<allocFunc,freeFunc,ensureRoom,shrinkCode,getNextLine>
	EXTNEAR	<genCommands,genPushBPOffset,genPopBPOffset,setVarDouble>
	EXTNEAR	<dimArray,getElemPtr,getElemVal,eraseArray,setOptBase>
	EXTABS	<TOK_BASE,TOK_DEL>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

ARRAY_VAL	equ	0		; push element value (or double ptr)
ARRAY_PTR	equ	1		; push element address (eg, for LET)
ARRAY_DIM	equ	2		; dimension the array (for DIM)

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
; genArrayVar
;
; Generate code to push a far pointer to an integer array variable (eg, the
; CAR% in "PUT (X,Y),CAR%"), for statements that use an entire array.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	genArrayVar
	mov	al,CLS_VAR
	call	getNextToken
	jbe	gav9
	and	ah,VAR_TYPE		; convert CLS_VAR_* to VAR_*
	cmp	ah,VAR_LONG
	jne	gav9
	mov	al,1
	call	findArray		; DX:SI -> array variable
	jc	gav9
	call	genPushVarPtr
	clc
	ret
gav9:	stc
	ret
ENDPROC	genArrayVar

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
