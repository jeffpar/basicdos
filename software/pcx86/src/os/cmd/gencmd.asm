;
; BASIC-DOS Code Generator
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This is the core of the code generator: genCode generates (and runs) the
; code for a line or program, and genCommands dispatches each command to its
; generator.  It also contains the token helpers that all the gen*.asm files
; share (eg, getNextToken); expressions (genExpr) and the code-emitting
; helpers (eg, GENCALL's genCallCS and GENPUSH's genPushImm) are in
; genexp.asm, and the label helpers (addLabel, findLabel) are in genflo.asm.
;
; Generates code for these commands:
;
;	DEFDBL/DEFINT/DEFSNG/DEFSTR	(genDefDbl, genDefInt, genDefStr)
;	LET				(genLet)
;	All DOS commands		(genDOS, generates call to callDOS)
;
; The other gen*.asm files include:
;
;	gencon.asm			console I/O (CLS, COLOR, ECHO, PRINT)
;	gendef.asm			definitions (DATA, DEF, DIM, ERASE,
;					OPTION BASE, READ, RESTORE) and array
;					element references
;	genflo.asm			control (END, FOR/NEXT, GOSUB, GOTO,
;					IF/THEN/ELSE, ON, RETURN, WHILE/WEND)
;	genfpu.asm			floating-point support
;	gengfx.asm			graphics (DRAW, GET, LINE, PAINT,
;					PRESET, PSET, PUT)
;	genexp.asm			expressions (genExpr) and the code
;					generation helpers (genPush*, genCall*)
;	gensys.asm			system (CHAIN, DEF SEG, ERROR, KEY,
;					PLAY, POKE, SOUND)
;
	include	cmd.inc
	include	8086.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<allocCode,ensureRoom,keepCode,genRedir,genRedirEnd>
	EXTNEAR	<addLabel>
	EXTNEAR	<allocVars>
	EXTNEAR	<addVar,getVar,setVarLong,setVarDouble>
	EXTNEAR	<setStr,holdStr,swapArgs,compactStrs,genArrayRef,checkCtl>
	EXTNEAR	<memError>
	EXTNEAR	<callDOS,printLine>
	EXTNEAR	<genCallFar,genPushImmByte,genPushImmByteAH,genPushImmByteAL>
	EXTNEAR	<genPushImmLong,genExpr,genCallCS>

	EXTWORD	<KEYWORD_TOKENS,KEYOP_TOKENS>
	EXTBYTE	<OPDEFS,RELOPS>
	EXTWORD	<EVAL_LONG,EVAL_STR>
	EXTLONG	<FPU_TABLE>
	EXTNEAR	<genCallFPU,genCallFPUDst,genCallFPUDst2>
	EXTNEAR	<genConstDouble,genCvtType,genFnCall,genPushSlot>
	EXTABS	<TOK_ABS,TOK_TAN>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCode
;
; Inputs:
;	AL = GEN flags (eg, GEN_BATCH)
;	DS:BX -> heap
;	DS:SI -> INPUTBUF (for single line) or null (for TBLKs)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	genCode
	LOCVAR	codeSeg,word		; code segment
	LOCVAR	defVarSeg,word		; default VBLK segment
	LOCVAR	defType,byte		; used by genDefInt, etc.
	LOCVAR	pCode,dword		; original start of generated code
	ENTER

	mov	[codeSeg],cs
	test	al,GEN_BATCH
	jz	gc1
	or	al,GEN_ECHO
gc1:	mov	[bx].GEN_FLAGS,al

	sub	cx,cx
	mov	[bx].ERR_CODE,cl
	mov	[bx].LINE_NUM,cx
	mov	[bx].LINE_LBL,cx
	mov	byte ptr [bx].GFX_DATA+6,cl	; see gfxInit
	mov	dx,ds
	test	si,si
	jnz	gc2
	mov	dx,[bx].TBLKDEF.BLK_NEXT
	test	dx,dx			; anything to run?
	jnz	gc1a			; yes
	jmp	gc9			; no (TODO: display a message?)
gc1a:	mov	si,size TBLK
	mov	[bx].DATA_STATE[2],cx	; start READ at the first DATA item
gc2:	mov	[bx].LINE_PTR.OFF,si
	mov	[bx].LINE_PTR.SEG,dx
	mov	[bx].LINE_LEN,cx	; CX = previous length (0)

	call	allocVars
	jc	gce
	mov	ax,[bx].VBLKDEF.BLK_NEXT
	mov	[defVarSeg],ax		; save the first (default) VBLK segment
	call	allocCode
	jc	gce
	ASSUME	ES:NOTHING		; ES:DI -> code block
	mov	[pCode].OFF,di
	mov	[pCode].SEG,es

	mov	ax,OP_MOV_BP_SP		; make it easy for endProgram
	stosw				; to reset the stack and return
	jmp	short gc4

gc4x:
	IFDEF	DEBUG
	mov	al,0
	call	genSpin			; erase the spinner
	ENDIF
	call	memError		; no room for code, so skip execution
	jmp	gc7

gce:	call	memError
	jmp	gc9

gc4:	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a line
	jc	gc4x
	call	getNextLine
	cmc
	jnc	gc6
	IFDEF	DEBUG
	mov	ax,ss:[PSP_HEAP]
	xchg	ax,bx
	mov	bx,ss:[bx].LINE_NUM
	and	bx,3
	mov	bl,cs:SPIN_CHARS[bx]	; BL = next spinner char
	xchg	ax,bx
	call	genSpin			; display the spinner
	ENDIF
	call	genRedir		; any ":>" redirection?
	jc	gc6			; yes, but it's invalid
	push	ax
	push	dx
	push	cx
	call	genCommands		; generate code
	pop	cx
	pop	dx
	pop	ax
	jc	gc6
	test	ax,ax			; was the line redirected?
	jz	gc4			; no
	mov	si,ds:[PSP_HEAP]
	mov	[si].LINE_LEN,ax	; restore the line's length
	call	genRedirEnd		; and end the redirection
	jnc	gc4

gc6:	push	ss
	pop	ds
	ASSUME	DS:DATA
	IFDEF	DEBUG
	pushf
	mov	al,0
	call	genSpin			; erase the spinner
	popf
	ENDIF
	jc	gc7
	call	checkCtl		; any FOR without NEXT (etc)?
	jc	gc7			; yes
	mov	al,OP_RETF		; terminate the code in the buffer
	stosb
;
; The memory model for the generated code is simple: CS is the current
; code block, SS is the heap, DS is the first var block, and ES is scratch.
;
; Since a BAS file can run another BAS file, we save the caller's ON ERROR
; state (see rtError), and then record the SP that the code will start with.
;
	mov	si,ds:[PSP_HEAP]
	push	[si].ERR_SP
	push	[si].ERR_NUM
	push	[si].ERR_ADDR.OFF
	push	[si].ERR_ADDR.SEG
	sub	ax,ax
	mov	[si].ERR_NUM,ax
	mov	[si].ERR_ADDR.SEG,ax
	push	bp
	push	ds
	mov	ax,sp
	sub	ax,4			; (the CALL below pushes 4 bytes)
	mov	[si].ERR_SP,ax
	mov	ds,[defVarSeg]
	ASSUME	DS:NOTHING
	call	[pCode]			; execute the code buffer
	pop	ds
	ASSUME	DS:DATA
	pop	bp
	mov	si,ds:[PSP_HEAP]
	pop	[si].ERR_ADDR.SEG
	pop	[si].ERR_ADDR.OFF
	pop	[si].ERR_NUM
	pop	[si].ERR_SP
	clc

gc7:	pushf
	call	keepCode		; free (or keep) the code
	call	compactStrs		; free any leftover temp strings
	popf
gc8:	jnc	gc9

	mov	bx,ds:[PSP_HEAP]
	cmp	[bx].ERR_CODE,0		; was an error already reported?
	stc
	jne	gc9			; yes (see memError)
	mov	ax,[bx].LINE_LBL	; report the line's label #, if any
	test	ax,ax
	jnz	gc8a
	mov	ax,[bx].LINE_NUM	; otherwise, its position in the file
gc8a:	PRINTF	<"Syntax error in line %d",13,10>,ax
	stc

gc9:	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].ERR_CODE,0	; (preserves carry)
	LEAVE
	ret
ENDPROC	genCode

	IFDEF	DEBUG
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genSpin
;
; Displays the progress "spinner" char in AL on STDERR while a BAS or BAT file
; is being compiled (in DEBUG builds only).  BASIC-DOS backspaces are destructive, so after the first
; line, each char is preceded by a backspace (to erase the previous char), and
; when AL is zero, only a backspace is displayed (to erase the spinner).
;
; Inputs:
;	AL = char (or zero to erase)
;
; Outputs:
;	None (all registers preserved, but not flags)
;
DEFPROC	genSpin
	push	ax
	push	bx
	push	cx
	push	dx
	push	ds
	mov	bx,ss
	mov	ds,bx
	mov	bx,ds:[PSP_HEAP]
	test	[bx].GEN_FLAGS,GEN_BASIC OR GEN_BATCH
	jz	gs9			; not compiling a file
	mov	cx,[bx].LINE_NUM
	jcxz	gs9			; nothing displayed yet
	mov	ah,al
	mov	al,CHR_BACKSPACE
	push	ax
	mov	dx,sp			; DS:DX -> backspace and char
	test	ah,ah			; erasing?
	jz	gs1			; yes, so display only the backspace
	dec	cx			; first line?
	mov	cx,2
	jnz	gs2			; no
	inc	dx			; yes, so display only the char
gs1:	mov	cx,1
gs2:	mov	bx,STDERR
	mov	ah,DOS_HDL_WRITE
	int	21h
	pop	ax
gs9:	pop	ds
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	genSpin

SPIN_CHARS	db	"-\|/"			; (the first line uses '\')
	ENDIF	; DEBUG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genCommands
;
; Generate code for one or more commands.
;
; As in MSBASIC, a command that begins with a variable (or array element)
; followed by '=' is an implicit LET.  This applies only to commands processed
; here (eg, in BAS/BAT files, after THEN or ELSE, or after a colon); a command
; line must still use LET, because parseCmd sends any non-keyword command to
; parseDOS.
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
	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a command
	jc	gcs9
	mov	dx,bx			; DX -> TOKLETs (for implicit LET)
	mov	al,CLS_KEYWORD
	call	getNextToken
	jb	gcs0
	je	gcs9			; out of tokens
	mov	cx,cs:[si].CTD_FUNC	;
	cmp	al,KEYWORD_BASIC	; BASIC keyword?
	jb	gcs2			; no
	jcxz	gcs8			; no command address
;
; If the keyword is alone (eg, "CIRCLE") and its generator fails, then it's
; presumably the name of a program to run (eg, CIRCLE.BAS), so we discard any
; code the generator produced and treat it as a DOS command instead.
;
	push	cx
	mov	al,CLS_ANY
	call	peekNextToken		; any tokens after the keyword?
	pop	cx
	jnz	gcs3			; yes
	push	bx
	push	di
	call	cx			; call the generator function
	pop	si
	pop	dx
	jnc	gcs4
	mov	di,si			; it failed, so discard its code
	mov	bx,dx
	jmp	short gcs1b		; and treat the keyword as a command
;
; If the next token is a colon that a previous command didn't consume (eg,
; "CLS:PRINT"), skip it; otherwise, it must be a DOS command.
;
gcs0:	cmp	ah,CLS_SYM
	jne	gcs1
	mov	si,[bx].TOKLET_OFF
	cmp	byte ptr [si],':'
	jne	gcs1
	add	bx,size TOKLET
	jmp	genCommands

gcs1:	test	ah,CLS_VAR		; variable (ie, implicit LET)?
	jz	gcs1b			; no
	push	bx
	mov	bx,dx
	mov	al,CLS_VAR
	call	getNextToken
	jbe	gcs1a
	call	getNextSymbol
	jbe	gcs1a
	cmp	al,'='			; assignment?
	je	gcs1L			; yes
	cmp	al,'('			; array element assignment?
	jne	gcs1a			; no
gcs1L:	pop	ax			; discard saved BX
	mov	bx,dx			; rewind to the variable
	mov	cx,offset genLet
	jmp	short gcs3
gcs1a:	pop	bx
gcs1b:	sub	ax,ax			; call genDOS w/o an ID
;
; For non-BASIC keywords, generate callDOS code with a pointer to the
; full command-line and the keyword handler.  callDOS will then perform
; the traditional parse-and-execute logic.
;
gcs2:	cbw				; AX = keyword ID
	mov	dx,cx			; DX = handler address
	mov	cx,offset genDOS

gcs3:	call	cx			; call dedicated generator function
gcs4:	mov	es:[BLK_FREE],di
	jnc	genCommands
	ret
;
; A keyword with no generator (eg, ELSE) ends the commands, and we leave it
; for the caller (eg, genIf), returning AX = CLS_KEYWORD and the keyword ID.
;
gcs8:	sub	bx,size TOKLET		; (this clears carry, too)
gcs9:	ret
ENDPROC	genCommands

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genDOS
;
; Generate code for DOS commands.
;
; Inputs:
;	AL = keyword ID
;	DX = handler offset
;	DS:BX -> TOKLETs
;	ES:DI -> code block
;
; Outputs:
;	Carry clear if successful, set if error
;
; Modifies:
;	Any
;
DEFPROC	genDOS
	push	ax
	GENPUSH	dx			; push handler offset
	pop	dx
	GENPUSH	dx			; push keyword ID
	mov	si,ds:[PSP_HEAP]
	mov	ax,[bx - size TOKLET].TOKLET_OFF
	lea	cx,[si].LINEBUF
	sub	ax,cx			; AX = # bytes preceding command
	mov	cx,[si].LINE_LEN
	sub	cx,ax
	push	ax
	GENPUSH	cx			; push length of command line
	mov	cx,[si].LINE_PTR.OFF
	pop	ax
	add	cx,ax
	mov	dx,[si].LINE_PTR.SEG	; DX:CX -> command line
	GENPUSH	dx,cx			; push pointer to command line
	GENCALL	callDOS
	mov	[si].TOKLET_END,bx	; mark the tokens fully processed
	ret
ENDPROC	genDOS

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

	call	getNextSymbol		; check for hyphen
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
; For every letter from DL through DH, set DEFVARS[DL] to defType.
;
gdi3:	push	bx
	mov	cl,dh
	sub	cl,dl
	mov	ch,0
	inc	cx			; CX = # of letters to set
	mov	al,[defType]		; AL = new default for each letter
	mov	bx,ds:[PSP_HEAP]
	lea	bx,[bx].DEFVARS
	sub	dl,'A'
	add	bl,dl
	adc	bh,ch			; BX -> 1st letter
gdi3a:	mov	[bx],al
	inc	bx
	loop	gdi3a
	pop	bx

	call	getNextSymbol		; check for comma
	jbe	gdi7			; no more tokens (or a ':' or keyword)
	cmp	al,','
	je	genDefVar
	sub	bx,size TOKLET		; leave any other symbol for the caller
gdi7:	clc
	ret

gdi8:	stc
gdi9:	ret

	DEFLBL	getCharToken,near
	mov	al,CLS_VAR		; token must be CLS_VAR
	call	getNextToken
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
; Process "DEFDBL".  In BASIC-DOS, floating-point will come in only one
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
; genLet
;
; Generate code to "LET" a variable equal some expression.  We'll start with
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

	and	ah,VAR_TYPE		; convert CLS_VAR_* to VAR_*
	mov	al,1			; ARRAY_PTR
	call	genArrayRef		; array element?
	jc	gl9			; error
	jnz	gl1			; yes (AH = element type)
	call	addVar			; DX:SI -> var data
	jc	gl9

	mov	cx,cs
	cmp	dx,cx			; constants (in CS) cannot be "let"
	je	gl9			; TODO: Generate a better error message
	push	ax			; AH is still var type (from addVar)
	call	genPushVarPtr
	pop	ax
gl1:	push	ax
	call	getNextSymbol
	pop	cx			; CH is now the var type
	jbe	gl9

	cmp	al,'='
	jne	gl9

	call	genExpr
	jc	gl9
;
; Like MSBASIC, assigning a long to a double variable (or vice versa) converts
; the value to the variable's type; all other mismatches are errors.
;
	push	cx
	mov	al,ch
	call	genCvtType		; TODO: generate "type mismatch" error
	pop	cx
	jc	gl9
	mov	dx,offset setVarDouble
	cmp	ch,VAR_DOUBLE		; doubles are copied by reference
	je	gl8
	mov	dx,offset setStr
	cmp	ch,VAR_STR		; strings are adopted or copied
	je	gl8
	mov	dx,offset setVarLong
gl8:	mov	cx,dx
	GENCALL	cx
	ret

gl9:	stc
	ret
ENDPROC	genLet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushVarPtr
;
; Inputs:
;	DX:SI = value to push
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	genPushVarPtr
	cmp	dx,[defVarSeg]
	je	gpv1
	call	genPushImm
	jmp	short gpv2
gpv1:	mov	al,OP_PUSH_DS
	stosb
gpv2:	mov	dx,si
	DEFLBL	genPushImm,near
	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	al,OP_PUSH_AX
	stosb
	ret
ENDPROC	genPushVarPtr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genPushVarLong
;
; Generates code to push 4-byte variable data onto stack (eg, a VAR_LONG
; integer or a VAR_STR pointer).
;
; DX:SI points to the variable data, and if DX == defVarSeg, then the
; generated code can assume DS:SI; otherwise, we must generate code to load
; the segment as well.
;
; The generated code will then use a pair of LODSW instructions to load the
; variable data into AX:DX and push it on the stack (yes, ordinarily we'd use
; DX:AX, but that's not the natural order a pair of LODSW provides).
;
; Inputs:
;	DX:SI -> var data
;
; Outputs:
;	None
;
; Modifies:
;	DX, SI, DI
;
DEFPROC	genPushVarLong
	push	ax
	cmp	dx,[defVarSeg]
	je	gpl1
	mov	al,OP_MOV_AX
	stosb
	xchg	ax,dx
	stosw
	mov	ax,OP_MOV_ES_AX
	stosw
gpl1:	mov	al,OP_MOV_SI		; "MOV SI,offset var data"
	stosb
	xchg	ax,si
	stosw
	je	gpl2
	mov	al,OP_SEG_ES
	stosb
gpl2:	mov	ax,OP_LODSW OR (OP_XCHG_DX SHL 8)
	stosw
	je	gpl3
	mov	al,OP_SEG_ES
	stosb
gpl3:	mov	ax,OP_LODSW OR (OP_PUSH_AX SHL 8)
	stosw
	mov	al,OP_PUSH_DX
	stosb
	pop	ax
	ret
ENDPROC	genPushVarLong


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextLine
;
; Inputs:
;	DS = heap segment
;
; Outputs:
;	If carry clear, DS:BX -> TOKLET array (TOKLET_END set to end)
;
; Modifies:
;	Any
;
DEFPROC	getNextLine
	mov	bx,ds:[PSP_HEAP]	; DS:BX -> heap
	mov	cx,[bx].LINE_LEN
	lds	si,[bx].LINE_PTR
	ASSUME	DS:NOTHING

	mov	dx,ds
	mov	ax,ss
	cmp	ax,dx			; is LINE_PTR in the heap?
	jne	gnl0			; no
	test	cx,cx			; yes, we must be using INPUTBUF
	stc				; have we already processed it?
	jnz	gnl4x			; yes
	mov	cl,[si].INP_CNT		; CX = length
	lea	si,[si].INP_DATA	; DS:SI -> line
	jmp	short gnl4

gnl0:	add	si,cx			; advance to the next line
gnl1:	cmp	si,ds:[BLK_FREE]	; still working the same TBLK?
	jb	gnl2			; yes
	mov	dx,ds:[BLK_NEXT]	; no, advance to next TBLK in chain
	cmp	dx,1			; is there another segment?
	jb	gnl4x			; no
	mov	ds,dx
	mov	si,size TBLK		; DS:SI -> next line
gnl2:	inc	ss:[bx].LINE_NUM
	lodsw
	mov	ss:[bx].LINE_LBL,ax
	test	ax,ax			; is there a label #?
	jz	gnl3			; no
	call	addLabel		; yes, add it to the LBLREF table
gnl3:	lodsb				; AL = length byte
	mov	ah,0
	xchg	cx,ax			; CX = length of line
	jcxz	gnl1
;
; As a preliminary matter, if we're processing a BAT file, then generate
; code to print the line, unless it starts with a '@', in which case, skip
; over the '@'.
;
gnl4:	DPRINTF	'b',<"%.*ls\r\n">,cx,si,ds
	cmp	byte ptr [si],'@'
	jne	gnl5
	inc	si
	dec	cx
	jz	gnl1
	jmp	short gnl6
gnl4x:	jmp	short gnl9
;
; One of the annoying things about the ECHO state is that, since we can't
; be sure what the state of ECHO will be at runtime, we must inject printLine
; before every line.
;
gnl5:	test	ss:[bx].GEN_FLAGS,GEN_ECHO
	jz	gnl6
	push	cx
	lea	cx,[si-1]
	GENPUSH	ds,cx			; DS:CX -> string (at the length byte)
	GENCALL	printLine
	pop	cx
;
; Ready to process the line of code at DS:SI with length CX.
;
gnl6:	mov	ss:[bx].LINE_PTR.OFF,si
	mov	ss:[bx].LINE_PTR.SEG,ds
	mov	ss:[bx].LINE_LEN,cx

	push	es
	push	di			; save code gen pointer
	push	ss
	pop	es			; ES = heap
;
; Copy the line (at DS:SI with length CX) to LINEBUF, so that we can use a
; single segment (DS) to address both LINEBUF and TOKENBUF once ES has been
; restored to the code gen segment.
;
	push	cx
	push	es
	lea	di,[bx].LINEBUF		; ES:DI -> LINEBUF
	push	di
	rep	movsb
	xchg	ax,cx			; AL = 0
	stosb				; null-terminate for good measure
	pop	si
	pop	ds
	pop	cx			; DS:SI -> LINEBUF (with length CX)

	lea	di,[bx].TOKENBUF	; ES:DI -> TOKENBUF
	DOSUTIL	TOKEN2
	mov	bx,di
	add	bx,offset TOK_DATA	; DS:BX -> TOKLET array
	pop	di
	pop	es			; restore code gen pointer
	jc	gnl9

	add	ax,ax
	add	ax,ax
	add	ax,bx
	mov	si,ds:[PSP_HEAP]
	mov	[si].TOKLET_END,ax
gnl9:	ret
ENDPROC	getNextLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextSymbol
;
; Call getNextToken with AL = CLS_SYM, updating BX and preserving CX, DX, SI.
;
DEFPROC	getNextSymbol
	push	cx
	push	si
	mov	al,CLS_SYM
	call	getNextToken
	pop	si
	pop	cx
	ret
ENDPROC	getNextSymbol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getNextToken
;
; Return the next token if it matches the criteria in AL (ignores whitespace).
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
;	AX, BX, CX, SI
;
DEFPROC	getNextToken
	push	dx
	push	di
gnt0:	mov	di,ds:[PSP_HEAP]
	cmp	bx,[di].TOKLET_END
	jb	gnt0a
	sub	ax,ax
	jmp	gnt9			; no more tokens (ZF set, CF clear)

gnt0a:	mov	ah,[bx].TOKLET_CLS
	test	ah,al
	jnz	gnt1
	cmp	ah,CLS_WHITE		; whitespace token?
gnt0b:	stc
	jne	gnt0c			; no (CF set)
	add	bx,size TOKLET		; yes, so ignore it
	jmp	gnt0
gnt0c:	jmp	gnt9

gnt1:	cmp	al,CLS_KEYWORD		; looking for keyword?
	jne	gnt1a			; no
	cmp	ah,CLS_VAR		; yes, undecorated CLS_VAR?
	jne	gnt0b			; no, can't be a keyword then

gnt1a:	mov	si,[bx].TOKLET_OFF
	mov	cl,[bx].TOKLET_LEN
	mov	ch,0
	add	bx,size TOKLET
	mov	dl,al			; DL = requested CLS
	mov	al,[si]			; AL = 1st character of token
	cmp	al,'a'			; ensure 1st character is upper-case
	jb	gnt2
	sub	al,20h
;
; Any CLS_VAR with additional bits specifying the variable type (eg,
; CLS_VAR_LONG, CLS_VAR_STR) is done, once we remove the type suffix from
; its length (the type is part of a variable's identity, not its name).
; Any vanilla CLS_VAR, however, must be further identified.  We now check for
; keyword operators (like NOT) and all other keywords.  Failing that, we
; assume it's a variable, so we look up the variable's implicit type and
; update the CLS bits accordingly.
;
gnt2:	cmp	ah,CLS_VAR
	je	gnt2v
	test	ah,CLS_VAR		; decorated CLS_VAR (eg, CLS_VAR_LONG)?
	jz	gnt7			; no
	dec	cx			; yes, so drop the type suffix
	jmp	short gnt8
gnt2v:

	push	ax
	push	dx
	cmp	cx,3			; KEYOPs are 2 or 3 characters
	ja	gnt2a			; so skip them if it's longer
	mov	dx,offset KEYOP_TOKENS	; see if token is a KEYOP
	DOSUTIL	TOKID			; CS:DX -> TOKTBL
	jc	gnt2a
	mov	ah,CLS_SYM		; AL = TOKDEF_ID, SI -> TOKDEF
	jnc	gnt2b
gnt2a:	mov	dx,offset KEYWORD_TOKENS; see if token is a KEYWORD
	DOSUTIL	TOKID			; CS:DX -> TOKTBL
	jc	gnt2c
	mov	ah,CLS_KEYWORD		; AL = TOKDEF_ID, SI -> TOKDEF
gnt2b:	pop	dx
	pop	dx
	jmp	short gnt8
gnt2c:	pop	dx			; neither KEYOP nor KEYWORD
	pop	ax
	cmp	dl,CLS_KEYWORD		; and did we request a KEYWORD?
	stc
	je	gnt9			; yes, return error

	push	bx
	push	ax
	lea	bx,[di].DEFVARS
	sub	al,'A'			; convert 1st letter to DEFVARS index
	xlat				; look up the default VAR type
	test	al,al			; has a default been set?
	jnz	gnt4			; yes
	mov	al,VAR_LONG		; no, default to VAR_LONG
	cmp	word ptr cs:[FPU_TABLE].SEG,0
	je	gnt4			; if there's no FPU$ driver
	mov	al,VAR_DOUBLE		; otherwise, VAR_DOUBLE
gnt4:	mov	ah,al
	or	ah,CLS_VAR
	pop	bx			; we're really popping AX
	mov	al,bl			; and restoring AL
	pop	bx
	jmp	short gnt8
;
; If we're about to return a CLS_SYM that happens to be a colon, then return
; ZF set (but not carry) to end the caller's token scan.
;
gnt7:	cmp	ah,CLS_SYM
	jne	gnt8

	cmp	al,':'
	je	gnt9

gnt8:	or	ah,0			; return both ZF and CF clear
gnt9:	pop	di
	pop	dx
	ret
ENDPROC	getNextToken

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekNextSymbol
;
; Peek and return the next symbol, if any.
;
; Inputs and outputs are the same as getNextSymbol, but we also save the
; offset of the next TOKLET, in case the caller wants to consume the token.
;
; Modifies:
;	AX
;
DEFPROC	peekNextSymbol
	push	bx
	call	getNextSymbol
	jmp	short peekReturn
ENDPROC	peekNextSymbol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekNextToken
;
; Peek and return the next token, if it matches the criteria in AL.
;
; Inputs and outputs are the same as getNextToken, but we also save the
; offset of the next TOKLET, in case the caller wants to consume the token.
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	peekNextToken
	push	bx
	call	getNextToken
	DEFLBL	peekReturn,near
	push	bx
	mov	bx,ds:[PSP_HEAP]
	pop	ds:[bx].TOKLET_NEXT	; save BX in TOKLET_NEXT in case the
	pop	bx			; caller wants to advance after peeking
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
;	If carry clear:
;		AL = operator
;		AH = precedence
;		CX = # args
;		DX = operator index
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
	mov	bx,ds:[PSP_HEAP]
	mov	bx,[bx].TOKLET_NEXT	; load TOKLET saved by peekNextToken
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
	lods	byte ptr cs:[si]	; AL = operator index
	cbw
	xchg	dx,ax			; DX = operator index, AX = op/prec
vo9:	xchg	al,ah			; AL = operator, AH = precedence
	pop	si
	ret
ENDPROC	validateOp

CODE	ENDS

	end
