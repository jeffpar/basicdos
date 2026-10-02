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
;	GOTO				(genGoto)
;	IF ... THEN ... [ELSE ...]	(genIf, including implied GOTOs; see
;					also: genBlock, genJmp, and genPatch)
;	RETURN				(genReturn, which ends a DEF block)
;
; See gen.asm for an overview of all the gen*.asm files.  Like gen.asm, these
; functions are called while generating code, with DS:BX -> TOKLETs and ES:DI
; -> code block.
;
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT

	EXTNEAR	<genExpr,genCommands,getNextToken,findLabel>
	EXTABS	<TOK_ELSE,TOK_THEN>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

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
;	jnz	thenBlock
;	jmp	elseBlock
;    thenBlock:
;	; Generate code for "THEN" block
;	; ...
;	jmp	nextBlock (only needed if there's an "ELSE" block)
;    elseBlock:
;	; Generate code for "ELSE" block
;	; ...
;    nextBlock:
;
; We use near jumps, so there's no limit on the size of the blocks, and each
; jump is patched once the block it skips has been generated.
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
	add	bx,size TOKLET		; consume THEN
	mov	ax,OP_POP_DX_AX
	stosw
	mov	ax,OP_OR_AX_DX
	stosw
	mov	ax,OP_JNZ_3
	stosw
	call	genJmp			; DX -> JMP offset (to the ELSE block)
	push	dx
	call	genBlock		; generate the THEN block
	pop	si
	jc	gif9
	cmp	ah,CLS_KEYWORD
	jne	gif8
	cmp	al,TOK_ELSE
	jne	gif8			; no ELSE block
	add	bx,size TOKLET		; consume ELSE
	call	genJmp			; DX -> JMP offset (to the next block)
	call	genPatch		; ELSE block starts here
	push	dx
	call	genBlock		; generate the ELSE block
	pop	si
	jc	gif9
gif8:	jmp	genPatch		; next block starts here
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

CODE	ENDS

	end
