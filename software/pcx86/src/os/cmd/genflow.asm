;
; BASIC-DOS Code Generator: Control Flow
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Generates code for these control flow statements:
;
;	END and STOP			(genEnd)
;	FOR ... TO ... [STEP ...]	(genFor and genNext; see FORSLOT and
;	NEXT [var[,var]...]		the forInit and forNext functions in
;					flow.asm)
;	GOSUB				(genGosub; see doGosub in flow.asm)
;	GOTO				(genGoto)
;	IF ... THEN ... [ELSE ...]	(genIf, including implied GOTOs; see
;					also: genBlock, genJmp, and genPatch)
;	ON ... GOTO/GOSUB ...		(genOn)
;	RETURN				(genReturn, which ends a DEF block,
;					or returns from a GOSUB)
;	WHILE ... WEND			(genWhile and genWend)
;
; Every statement is compiled statically, so FOR, WHILE, and their matching
; NEXT and WEND statements are paired up as the code is generated: FOR and
; WHILE push a CTL_FOR or CTL_WHILE entry onto the code block's LBLREF table
; (see pushCtl), whose LBL_IP is the offset following the JMP that skips the
; loop, and NEXT and WEND mark the innermost one CTL_DONE (see findCtl).  Until
; that 5-byte JMP is patched, it holds the address of the FORSLOT (for FOR) or
; the top of the loop (for WHILE).
;
; Code for a program may span several code blocks (see ensureRoom), so every
; JMP that may go to another code block (eg, GOTO, IF, and the JMPs for loops)
; is either a near JMP (if the target is in the same block) or a far JMP, and
; any JMP that's patched later occupies 5 bytes.
;
; See gen.asm for an overview of all the gen*.asm files.  Like gen.asm, these
; functions are called while generating code, with DS:BX -> TOKLETs and ES:DI
; -> code block.
;
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,genCommands,getNextToken>
	EXTNEAR	<genCvtType,genTestDouble,genCallCS,genPushVarPtr>
	EXTNEAR	<genPushImm,genPushImmLong,addVar,getNextSymbol>
	EXTNEAR	<setVarLong,setVarDouble,forInit,forNext,doGosub,doReturn>
	EXTNEAR	<ensureRoom>
	EXTABS	<TOK_ELSE,TOK_THEN,TOK_TO,TOK_STEP,TOK_GOTO,TOK_GOSUB>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

FS_SIZE		equ	22		; size of FORSLOT (see flow.asm)
OP_JZ_3		equ	00374h		; JZ  $+5 (eg, around a near JMP)
OP_JZ_5		equ	00574h		; JZ  $+7 (eg, around a far JMP)
OP_JNZ_5	equ	00575h		; JNZ $+7 (eg, around a far JMP)
OP_OR_DX_DX	equ	0D20Bh		; OR  DX,DX
OP_CMP_AX	equ	03Dh		; CMP AX,imm16

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
	mov	al,CLS_DEC
	call	getNextToken
	jbe	gg9
	DOSUTIL	ATOI32D			; DS:SI -> decimal string
	call	findLabel		; DX:AX -> label (if carry clear)
;
; If carry is clear, then we found the specified label # (ie, it must have
; been a backward reference), so we can generate the correct JMP immediately.
;
; If carry is set, then the label # must be a forward reference.  findLabel
; automatically calls addLabel with LBL_RESOLVE set, so when the definition is
; finally found, this (and any other LBL_RESOLVE references) can be resolved.
;
; In the interim, we generate a program termination sequence (reset the stack
; pointer and return); once the label definition is encountered, it will be
; overwritten with a JMP (see addLabel).
;
; Since the label may be in another code block, every GOTO occupies 5 bytes,
; which is enough for a far JMP (a near JMP is padded with NOPs).
;
	jc	gg7
	push	di
	call	emitJmp
	pop	ax
	sub	ax,di
	cmp	ax,-3			; did we generate a near JMP?
	jne	gg8			; no
	jmp	short gg7a		; yes, so pad it
gg7:	mov	ax,OP_MOV_SP_BP		; placeholder for endProgram
	stosw
	mov	al,OP_RETF
	stosb
gg7a:	mov	ax,(OP_NOP SHL 8) OR OP_NOP
	stosw
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
;	jnz	thenBlock
;	jmp	elseBlock		; (5 bytes, near or far)
;    thenBlock:
;	; Generate code for "THEN" block
;	; ...
;	jmp	nextBlock (only needed if there's an "ELSE" block)
;    elseBlock:
;	; Generate code for "ELSE" block
;	; ...
;    nextBlock:
;
; Since a block may continue in another code block (see ensureRoom), every
; JMP is a 5-byte placeholder (see genJmp5) that's patched with either a near
; or far JMP once the block it skips has been generated (see patchHere).
;
; A block that begins with a line number is an implied GOTO (eg, "THEN 10"
; instead of "THEN GOTO 10").
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
	call	genTestDouble		; (a double is true if it's non-zero)
	jc	gif9
	add	bx,size TOKLET		; consume THEN
	mov	ax,OP_POP_DX_AX
	stosw
	mov	ax,OP_OR_AX_DX
	stosw
	mov	ax,OP_JNZ_5
	stosw
	call	genJmp5			; JMP to the ELSE block (placeholder)
	push	es
	push	dx
	call	genBlock		; generate the THEN block
	pop	si
	pop	dx			; DX:SI -> after the JMP to ELSE
	jc	gif9
	cmp	ah,CLS_KEYWORD
	jne	gif8
	cmp	al,TOK_ELSE
	jne	gif8			; no ELSE block
	add	bx,size TOKLET		; consume ELSE
	push	dx
	push	si
	call	genJmp5			; JMP to the next block (placeholder)
	pop	si
	pop	ax
	push	es
	push	dx			; save JMP to the next block
	xchg	dx,ax
	sub	si,5
	call	patchHere		; ELSE block starts here
	call	genBlock		; generate the ELSE block
	pop	si
	pop	dx			; DX:SI -> after the JMP to next
	jc	gif9
gif8:	sub	si,5
	call	patchHere		; next block starts here
	clc
	ret
gif9:	stc
	ret
ENDPROC	genIf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genBlock
;
; Generates a block of commands for genIf; a block that begins with a line
; number is an implied GOTO.
;
; Inputs:
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;	AX = CLS_KEYWORD and keyword ID, if a keyword (eg, ELSE) ended
;	the block
;
; Modifies:
;	Any
;
DEFPROC	genBlock
	mov	al,CLS_DEC
	call	getNextToken
	jbe	gb1			; no line number
	sub	bx,size TOKLET		; let genGoto consume the line number
	call	genGoto
	jc	gb9
gb1:	jmp	genCommands
gb9:	ret
ENDPROC	genBlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genJmp, genPatch
;
; genJmp generates a near JMP whose target will be patched later, and genPatch
; patches a JMP to jump to the next unused location in the code block.
;
; Inputs:
;	ES:DI -> code block
;	SI = offset returned by genJmp (for genPatch)
;
; Outputs:
;	DX = offset of the byte following the JMP (from genJmp)
;	Carry clear (from genPatch)
;
; Modifies:
;	AX, DX (genJmp), or AX (genPatch)
;
DEFPROC	genJmp
	mov	al,OP_JMP
	stosb
	stosw				; (offset to be patched)
	mov	dx,di
	ret
ENDPROC	genJmp

DEFPROC	genPatch
	mov	ax,di
	sub	ax,si			; AX = distance from JMP to here
	mov	es:[si-2],ax
	clc
	ret
ENDPROC	genPatch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genReturn
;
; Generate code to "RETURN [optional value]" from a DEF block, or "RETURN"
; from a GOSUB.
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
	test	[si].GEN_FLAGS,GEN_DEF	; ending a DEF block?
	jnz	gr1			; yes
	GENCALL	doReturn		; no, returning from a GOSUB
	ret
gr1:	call	genExpr
	jc	gr9
	mov	al,[si].DEF_TYPE
	call	genCvtType		; convert to the function's type
	jc	gr9
	and	[si].GEN_FLAGS,NOT GEN_DEF
gr9:	ret
ENDPROC	genReturn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genEnd
;
; Generate code for "END" (and "STOP", which is currently the same).
;
; Inputs:
;	ES:DI -> code block
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, DI
;
DEFPROC	genEnd
	mov	ax,OP_MOV_SP_BP		; same as endProgram (see genCode)
	stosw
	mov	al,OP_RETF
	stosb
	clc
	ret
ENDPROC	genEnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genFor
;
; Generate code for "FOR var = start TO limit [STEP step]", which looks like:
;
;	jmp	short around the FORSLOT
;	(FORSLOT)
;	(set var to start)
;	(push limit and step, converted to the type of var)
;	push	segment FORSLOT		; (since the code may have continued
;	push	offset FORSLOT		; in another code block by now)
;	call	forInit
;	or	ax,dx
;	jnz	body
;	jmp	next			; patched by genNext (5 bytes)
;    body:
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
DEFPROC	genFor
	mov	al,CLS_VAR
	call	getNextToken		; loop variable
	ja	gfo0
gfoX:	stc
	ret
gfo0:	and	ah,VAR_TYPE
	call	addVar			; DX:SI -> loop variable
	jc	gfoX
	cmp	ah,VAR_LONG		; must be a long or a double
	je	gfo1
	cmp	ah,VAR_DOUBLE
	jne	gfoX
gfo1:	mov	cx,ax			; CH = type
	mov	ax,OP_JMPS OR (FS_SIZE SHL 8)
	stosw
	push	es			; push FORSLOT segment
	push	di			; push FORSLOT offset
	mov	al,ch
	mov	ah,0
	stosw				; FS_TYPE and FS_PAD
	mov	ax,si
	stosw				; FS_VAR offset
	mov	ax,dx
	stosw				; FS_VAR segment
	push	cx
	mov	cx,8
	sub	ax,ax
	rep	stosw			; zero FS_LIMIT and FS_STEP
	pop	cx			; CH = type
	push	cx			; [sp] = type, [sp+2] = FORSLOT offset
	call	genPushVarPtr
	call	getNextSymbol
	jbe	gfo7x
	cmp	al,'='
	je	gfo1a
gfo7x:	jmp	gfo7
gfo1a:	call	genExpr			; initial value
	jbe	gfo7x
	call	gfoCvt
	jc	gfo7
	pop	cx
	push	cx
	push	ax
	mov	dx,offset setVarLong
	cmp	ch,VAR_DOUBLE
	jne	gfo2
	mov	dx,offset setVarDouble
gfo2:	mov	cx,dx
	GENCALL	cx			; set the loop variable
	pop	ax
	cmp	ah,CLS_KEYWORD		; TO?
	jne	gfo7
	cmp	al,TOK_TO
	jne	gfo7
	add	bx,size TOKLET		; consume TO
	call	genExpr			; limit
	jbe	gfo7
	call	gfoCvt
	jc	gfo7
	cmp	ah,CLS_KEYWORD		; STEP?
	jne	gfo3
	cmp	al,TOK_STEP
	jne	gfo7
	add	bx,size TOKLET		; consume STEP
	call	genExpr			; step
	jbe	gfo7
	call	gfoCvt
	jc	gfo7
	jmp	short gfo4
gfo3:	sub	dx,dx
	mov	cx,1
	call	genPushImmLong		; the default step is 1
	mov	dl,VAR_LONG
	call	gfoCvt
	jc	gfo7
gfo4:	pop	cx
	pop	si			; SI = FORSLOT offset
	pop	dx			; DX = FORSLOT segment
	push	dx
	push	si
	call	genPushImm		; push FORSLOT segment
	pop	dx
	push	dx
	call	genPushImm		; push FORSLOT offset
	GENCALL	forInit
	mov	ax,OP_OR_AX_DX
	stosw
	mov	ax,OP_JNZ_5
	stosw
	call	genJmp5			; DX = offset of body
	pop	ax
	mov	es:[di-4],ax		; save FORSLOT address in JMP (for now)
	pop	ax
	mov	es:[di-2],ax
	mov	ax,CTL_FOR
	jmp	pushCtl
gfo7:	pop	cx
	pop	cx
	pop	cx
	stc
	ret
;
; gfoCvt converts the value (type DL) to the type of the loop variable (on
; the stack, underneath the return address), preserving AX.
;
gfoCvt:	push	ax
	push	bx
	mov	bx,sp
	mov	al,ss:[bx+7]		; AL = type (CH on the stack)
	pop	bx
	call	genCvtType
	pop	ax
	ret
ENDPROC	genFor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genNext
;
; Generate code for "NEXT [var[,var]...]", which looks like:
;
;	push	segment FORSLOT
;	push	offset FORSLOT
;	call	forNext
;	or	ax,dx
;	jz	next
;	jmp	body
;    next:
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
DEFPROC	genNext
gnx1:	call	findCtl			; DX:SI -> innermost FOR or WHILE
	jc	gnx0
	cmp	ax,CTL_FOR		; is it a FOR?
	je	gnx1a			; yes
	stc
gnx0:	ret
gnx1a:	push	dx			; [sp+6] = block containing the FOR
	push	si			; [sp+4] = LBLREF offset
	push	ds
	mov	ds,dx
	mov	si,[si].LBL_IP		; SI = offset of body
	mov	ax,[si-2]		; AX = FORSLOT segment
	mov	cx,[si-4]		; CX = FORSLOT offset
	pop	ds
	push	ax			; [sp+2] = FORSLOT segment
	push	cx			; [sp] = FORSLOT offset
	mov	al,CLS_VAR
	call	getNextToken		; is there a loop variable?
	jbe	gnx3			; no
	cmp	ah,CLS_KEYWORD		; a keyword (eg, ELSE) instead?
	jne	gnx2			; no
	sub	bx,size TOKLET		; yes, so leave it for the caller
	jmp	short gnx3
gnx2:	and	ah,VAR_TYPE
	call	addVar			; DX:SI -> loop variable
	jc	gnx7
	push	es
	push	bx
	mov	bx,sp
	mov	es,ss:[bx+6]		; ES = FORSLOT segment
	mov	bx,ss:[bx+4]		; ES:BX -> FORSLOT
	cmp	si,es:[bx+2]		; is it the loop variable?
	jne	gnx6			; no
	cmp	dx,es:[bx+4]
gnx6:	pop	bx
	pop	es
	jne	gnx7			; no
gnx3:	mov	si,sp
	mov	dx,ss:[si+2]
	call	genPushImm		; push FORSLOT segment
	mov	si,sp
	mov	dx,ss:[si]
	call	genPushImm		; push FORSLOT offset
	GENCALL	forNext
	mov	ax,OP_OR_AX_DX
	stosw
	pop	ax
	pop	ax
	pop	si			; SI = LBLREF offset
	pop	dx			; DX = block containing the FOR
	mov	ax,OP_JZ_3		; JZ around a near JMP
	mov	cx,es
	cmp	cx,dx			; is the FOR in this block?
	je	gnx4			; yes
	mov	ax,OP_JZ_5		; no, so JZ around a far JMP
gnx4:	stosw
	push	ds
	mov	ds,dx
	mov	[si].LBL_NUM,CTL_DONE
	mov	ax,[si].LBL_IP		; DX:AX -> body
	pop	ds
	push	ax
	call	emitJmp			; jump back to the body
	pop	si
	sub	si,5			; DX:SI -> the FOR's JMP
	call	patchHere		; patch it to jump here
	call	getNextSymbol		; another variable (eg, "NEXT I,J")?
	jc	gnx9
	jz	gnx9			; no (carry clear)
	cmp	al,','
	jne	gnx8
	jmp	gnx1
gnx8:	stc
	ret
gnx7:	pop	si
	pop	si
	pop	si
	pop	si
	stc
gnx9:	ret
ENDPROC	genNext

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genWhile
;
; Generate code for "WHILE expr", which looks like:
;
;    top:
;	(push expr)
;	pop	ax
;	pop	dx
;	or	ax,dx
;	jnz	body
;	jmp	wend			; patched by genWend (5 bytes)
;    body:
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
DEFPROC	genWhile
	push	es			; save address of top
	push	di
	call	genExpr
	jbe	gwh8
	call	genTestDouble		; (a double is true if it's non-zero)
	jc	gwh8
	mov	ax,OP_POP_DX_AX
	stosw
	mov	ax,OP_OR_AX_DX
	stosw
	mov	ax,OP_JNZ_5
	stosw
	call	genJmp5			; DX = offset of body
	pop	ax
	mov	es:[di-4],ax		; save address of top in JMP (for now)
	pop	ax
	mov	es:[di-2],ax
	mov	ax,CTL_WHILE
	jmp	pushCtl
gwh8:	pop	ax
	pop	ax
	stc
	ret
ENDPROC	genWhile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genWend
;
; Generate code for "WEND", which jumps back to the top of the WHILE.
;
; Inputs:
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genWend
	call	findCtl			; DX:SI -> innermost FOR or WHILE
	jc	gwe9
	cmp	ax,CTL_WHILE		; is it a WHILE?
	stc
	jne	gwe9			; no
	push	ds
	mov	ds,dx
	mov	[si].LBL_NUM,CTL_DONE
	mov	si,[si].LBL_IP		; SI = offset of body
	mov	ax,[si-4]
	mov	cx,[si-2]		; CX:AX -> top
	pop	ds
	push	dx
	push	si
	mov	dx,cx
	call	emitJmp			; jump back to the top
	pop	si
	pop	dx
	sub	si,5			; DX:SI -> the WHILE's JMP
	call	patchHere		; patch it to jump here
	clc
gwe9:	ret
ENDPROC	genWend

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genJmp5
;
; Generates a 5-byte placeholder for a JMP (near or far) whose target will be
; patched later (see patchHere).
;
; Inputs:
;	ES:DI -> code block
;
; Outputs:
;	DX = offset of the byte following the placeholder
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	genJmp5
	mov	al,OP_JMPF
	stosb
	stosw
	stosw
	mov	dx,di
	ret
ENDPROC	genJmp5

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; emitJmp
;
; Generates a near JMP if the target is in the same code block, otherwise a
; far JMP.
;
; Inputs:
;	DX:AX -> target
;	ES:DI -> code block
;
; Outputs:
;	ES:DI updated (3 bytes for a near JMP, 5 bytes for a far JMP)
;
; Modifies:
;	AX, DI
;
DEFPROC	emitJmp
	push	cx
	mov	cx,es
	cmp	cx,dx			; is the target in this block?
	jne	ej1			; no
	sub	ax,di
	sub	ax,3			; AX = 16-bit displacement
	xchg	cx,ax
	mov	al,OP_JMP
	stosb
	xchg	cx,ax
	stosw
	jmp	short ej9
ej1:	xchg	cx,ax
	mov	al,OP_JMPF
	stosb
	xchg	cx,ax
	stosw				; the offset of a far JMP
	xchg	ax,dx
	stosw				; and the segment
	xchg	ax,dx
ej9:	pop	cx
	ret
ENDPROC	emitJmp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; patchJmp
;
; Inputs:
;	ES:SI -> 5-byte JMP placeholder
;	DX:AX -> target
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	patchJmp
	push	di
	mov	di,si
	call	emitJmp
	pop	di
	ret
ENDPROC	patchJmp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; patchHere
;
; Inputs:
;	DX:SI -> 5-byte JMP placeholder
;	ES:DI -> target (ie, the next unused location in the code block)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	patchHere
	push	es
	mov	ax,di
	mov	cx,es
	mov	es,dx			; ES:SI -> placeholder
	mov	dx,cx			; DX:AX -> target
	call	patchJmp
	pop	es
	ret
ENDPROC	patchHere

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; firstBlock and nextBlock
;
; Labels (and open FORs and WHILEs) may be in any block of the code block
; chain, since each block has its own LBLREF table; a function block, however,
; is a chain of one.
;
; Inputs:
;	ES -> code (or function) block
;
; Outputs:
;	AX = first (or next) block, or zero if none
;
; Modifies:
;	AX
;
DEFPROC	firstBlock
	mov	ax,es
	cmp	es:[BLK_SIG],SIG_CBLK	; code block?
	jne	fb9			; no
	push	si
	mov	si,ss:[PSP_HEAP]
	mov	ax,ss:[si].CBLKDEF.BDEF_NEXT
	pop	si
fb9:	ret
ENDPROC	firstBlock

DEFPROC	nextBlock
	sub	ax,ax
	cmp	es:[BLK_SIG],SIG_CBLK	; code block?
	jne	nb9			; no
	mov	ax,es:[BLK_NEXT]
nb9:	ret
ENDPROC	nextBlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addLabel
;
; Adds a label definition or reference (if LBL_RESOLVE is set) to the current
; code block's LBLREF table.  For a definition, we first scan all the LBLREF
; tables to ensure the definition is unique, and to resolve any references
; (by replacing their placeholders with JMPs; see genGoto).
;
; Inputs:
;	AX = label #
;	DI = code gen offset (+ LBL_RESOLVE for a reference)
;	ES -> current code block
;
; Outputs:
;	Carry clear if successful, set if error (eg, duplicate label)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	addLabel
	push	si
	mov	dx,ax			; DX = label #
	mov	cx,es			; CX = current code block
	test	di,LBL_RESOLVE		; is this a reference?
	jnz	al8			; yes, just add it
	call	firstBlock		; AX = first block
al1:	mov	es,ax
	mov	si,es:[CBLK_REFS]
al2:	cmp	si,es:[BLK_SIZE]	; end of this LBLREF table?
	jae	al5			; yes
	cmp	es:[si].LBL_NUM,dx	; label # match?
	jne	al4			; no
	mov	ax,es:[si].LBL_IP
	test	ax,LBL_RESOLVE		; is this a reference?
	stc
	jz	al7			; no, it's a duplicate definition
	mov	es:[si].LBL_NUM,CTL_DONE; mark the reference resolved
	push	si
	push	dx
	and	ax,NOT LBL_RESOLVE
	xchg	si,ax			; ES:SI -> placeholder
	mov	dx,cx
	mov	ax,di			; DX:AX -> target
	call	patchJmp
	pop	dx
	pop	si
al4:	add	si,size LBLREF
	jmp	al2
al5:	call	nextBlock
	test	ax,ax
	jnz	al1
	mov	es,cx			; ES = current code block again
al8:	mov	si,es:[CBLK_REFS]
	sub	si,size LBLREF
	mov	es:[CBLK_REFS],si
	mov	es:[si].LBL_NUM,dx
	mov	es:[si].LBL_IP,di
	clc
al7:	mov	es,cx
	pop	si
	ret
ENDPROC	addLabel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findLabel
;
; Inputs:
;	AX = label #
;	ES:DI -> current code block
;
; Outputs:
;	Carry clear if found, DX:AX -> label; otherwise, a reference is added
;	(see addLabel)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	findLabel
	push	si
	push	es
	mov	dx,ax			; DX = label #
	call	firstBlock		; AX = first block
fl1:	mov	es,ax
	mov	si,es:[CBLK_REFS]
fl2:	cmp	si,es:[BLK_SIZE]	; end of this LBLREF table?
	jae	fl4			; yes
	cmp	es:[si].LBL_NUM,dx	; label # match?
	jne	fl3			; no
	mov	ax,es:[si].LBL_IP
	test	ax,LBL_RESOLVE		; is this a reference?
	jz	fl8			; no, it's the definition
fl3:	add	si,size LBLREF
	jmp	fl2
fl4:	call	nextBlock
	test	ax,ax
	jnz	fl1
	pop	es
	pop	si
	xchg	ax,dx			; AX = label #
	push	di
	or	di,LBL_RESOLVE
	call	addLabel		; add a reference
	pop	di
	stc
	ret
fl8:	mov	dx,es			; DX:AX -> label
	pop	es
	pop	si
	clc
	ret
ENDPROC	findLabel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pushCtl
;
; Pushes a CTL_FOR or CTL_WHILE entry onto the code block's LBLREF table.
;
; Inputs:
;	AX = CTL_FOR or CTL_WHILE
;	DX = offset (following the JMP that skips the loop)
;	ES:DI -> code block
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, DX
;
DEFPROC	pushCtl
	push	di
	mov	di,es:[CBLK_REFS]	; (FBLK_REFS is the same)
	sub	di,size LBLREF
	mov	es:[CBLK_REFS],di
	stosw				; LBL_NUM <- AX
	xchg	ax,dx
	stosw				; LBL_IP <- DX
	pop	di
	clc
	ret
ENDPROC	pushCtl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findCtl
;
; Finds the innermost (ie, most recent) open FOR or WHILE.
;
; Inputs:
;	ES -> code block
;
; Outputs:
;	If carry clear, DX:SI -> LBLREF, AX = CTL_FOR or CTL_WHILE
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	findCtl
	push	es
	sub	dx,dx			; DX = 0 (none found yet)
	call	firstBlock		; AX = first block
fc1:	mov	es,ax
	mov	si,es:[CBLK_REFS]	; (the newest entries come first)
fc2:	cmp	si,es:[BLK_SIZE]	; end of this LBLREF table?
	jae	fc4			; yes
	cmp	es:[si].LBL_NUM,CTL_WHILE; CTL_WHILE or CTL_FOR?
	jae	fc3			; yes
	add	si,size LBLREF
	jmp	fc2
fc3:	mov	dx,es			; DX:CX -> newest one so far
	mov	cx,si
fc4:	call	nextBlock
	test	ax,ax
	jnz	fc1
	test	dx,dx			; did we find one?
	stc
	jz	fc9			; no
	mov	es,dx
	mov	si,cx			; DX:SI -> LBLREF
	mov	ax,es:[si].LBL_NUM
	clc
fc9:	pop	es
	ret
ENDPROC	findCtl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; checkCtl
;
; Called by genCode when it's done generating code, to make sure that every
; FOR and WHILE has a matching NEXT or WEND.
;
; Inputs:
;	ES -> code block
;
; Outputs:
;	Carry set if there's an open FOR or WHILE
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	checkCtl
	call	findCtl
	cmc
	ret
ENDPROC	checkCtl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genGosub
;
; Generate code for "GOSUB line", which looks like:
;
;	mov	ax,offset next
;	call	doGosub
;	jmp	line			; (see genGoto)
;    next:
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
DEFPROC	genGosub
	mov	al,OP_MOV_AX
	stosb
	push	di
	stosw				; (return offset, patched below)
	GENCALL	doGosub
	call	genGoto
	pop	si
	jc	gsb9
	mov	es:[si],di		; return offset
gsb9:	ret
ENDPROC	genGosub

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genOn
;
; Generate code for "ON expr GOTO line[,line]..." or "ON expr GOSUB ...",
; which looks like:
;
;	(push expr, converted to a long)
;	pop	ax
;	pop	dx
;	or	dx,dx
;	jz	$+5
;	jmp	next			; out of range
;	cmp	ax,1
;	jne	$+7 (or $+15)
;	(mov ax,offset next and call doGosub, if GOSUB)
;	jmp	line1
;	cmp	ax,2
;	...
;    next:
;
; Like MSBASIC, a value of zero, or a value greater than the number of lines,
; continues with the next statement.
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
DEFPROC	genOn
	call	genExpr
	ja	gon0
gonX:	stc
	ret
gon0:	push	ax
	mov	al,VAR_LONG
	call	genCvtType
	pop	ax
	jc	gonX
	cmp	ah,CLS_KEYWORD
	jne	gonX
	sub	cx,cx			; CL = 0 for GOTO
	cmp	al,TOK_GOTO
	je	gon1
	inc	cx			; CL = 1 for GOSUB
	cmp	al,TOK_GOSUB
	jne	gonX
gon1:	add	bx,size TOKLET		; consume GOTO or GOSUB
	mov	si,ds:[PSP_HEAP]
	mov	ax,[si].TOKLET_END
	sub	ax,bx			; AX = 4 * remaining tokens
	mov	dx,ax
	add	ax,ax
	add	ax,ax
	add	ax,dx			; AX = 20 * remaining tokens
	add	ax,CODE_ROOM
	call	ensureRoom		; make room for the entire statement
	jc	gonX
	mov	ax,OP_POP_DX_AX
	stosw
	mov	ax,OP_OR_DX_DX
	stosw
	mov	ax,OP_JZ_3
	stosw
	call	genJmp			; DX = offset following JMP to next
	push	dx
	push	cx			; CL = GOTO or GOSUB, CH = line #
	sub	ax,ax
	push	ax			; push list of return offsets to patch
gon2:	pop	si
	pop	cx
	inc	ch
	mov	al,OP_CMP_AX
	stosb
	mov	al,ch
	mov	ah,0
	stosw
	mov	ax,00575h		; JNE $+7 (around a 5-byte JMP)
	test	cl,cl
	jz	gon3
	mov	ax,00D75h		; JNE $+15 (around MOV, CALL, and JMP)
gon3:	stosw
	jz	gon4
	mov	al,OP_MOV_AX
	stosb
	mov	ax,si			; link this offset to the previous one
	mov	si,di
	stosw
	push	cx
	push	si
	GENCALL	doGosub
	pop	si
	pop	cx
gon4:	push	cx
	push	si
	call	genGoto			; JMP line (always 5 bytes)
	pop	si
	pop	cx
	jc	gon7
	push	cx
	push	si
	call	getNextSymbol		; another line?
	jc	gon6			; error
	jz	gon5			; no
	cmp	al,','
	je	gon2
gon6:	pop	si
	pop	cx
	jmp	short gon7
gon5:	pop	si
	pop	cx
gon5a:	test	si,si			; any more return offsets to patch?
	jz	gon5b			; no
	mov	ax,es:[si]
	mov	es:[si],di		; return offset
	xchg	si,ax
	jmp	gon5a
gon5b:	pop	si
	jmp	genPatch		; patch the JMP to next
gon7:	pop	si
	stc
	ret
ENDPROC	genOn

CODE	ENDS

	end
