;
; BASIC-DOS Control Flow Support Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSFUNC equ 1
	include	cmd.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<ctrlc,restoreMode,firstBlock,nextBlock>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;
; Each FOR statement generates a FORSLOT inline in the code block (see
; genFor), which contains the loop variable's type and address (stored when
; the code is generated), and the limit and step (stored by forInit when the
; FOR statement runs).  The limit and step have the same type as the loop
; variable (VAR_LONG or VAR_DOUBLE).
;
FORSLOT		struc
FS_TYPE		db	?		; 00h: VAR_LONG or VAR_DOUBLE
FS_PAD		db	?		; 01h
FS_VAR		dd	?		; 02h: far pointer to loop variable
FS_LIMIT	db	8 dup (?)	; 06h: limit
FS_STEP		db	8 dup (?)	; 0Eh: step
FORSLOT		ends

;
; GOSUB pushes GOSUB_SIG and the return address, and RETURN verifies the
; signature.  The signature is not a valid segment (see compactBlock).
;
GOSUB_SIG	equ	0F00Dh
GOSUB_MIN	equ	512		; min stack space left after GOSUB

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; forInit
;
; Stores the limit and step in the FORSLOT and tests whether the loop body
; should be executed (like MSBASIC, if the initial value is already past the
; limit, it isn't).
;
; Inputs:
;	limit (long, or far pointer to double)
;	step (long, or far pointer to double)
;	far pointer to FORSLOT
;
; Outputs:
;	DX:AX = non-zero to execute the loop body, zero if not
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	forInit,FAR
	ARGVAR	forLimit,dword
	ARGVAR	forStep,dword
	ARGVAR	pForSlot,dword
	ENTER
	push	ds
	les	di,[pForSlot]
	cmp	es:[di].FS_TYPE,VAR_DOUBLE
	je	fi1
	mov	ax,[forLimit].LOW
	mov	word ptr es:[di].FS_LIMIT,ax
	mov	ax,[forLimit].HIW
	mov	word ptr es:[di].FS_LIMIT+2,ax
	mov	ax,[forStep].LOW
	mov	word ptr es:[di].FS_STEP,ax
	mov	ax,[forStep].HIW
	mov	word ptr es:[di].FS_STEP+2,ax
	jmp	short fi2
fi1:	add	di,FS_LIMIT
	lds	si,[forLimit]
	mov	cx,4
	rep	movsw			; copy the limit
	lds	si,[forStep]		; (FS_STEP follows FS_LIMIT)
	mov	cx,4
	rep	movsw			; copy the step
fi2:	les	di,[pForSlot]
	call	forTest
	pop	ds
	LEAVE
	RETURN
ENDPROC	forInit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; forNext
;
; Adds the step to the loop variable and tests whether the loop body should
; be executed again.
;
; Inputs:
;	far pointer to FORSLOT
;
; Outputs:
;	DX:AX = non-zero to execute the loop body again, zero if not
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	forNext,FAR
	ARGVAR	pNextSlot,dword
	ENTER
	push	ds
	les	di,[pNextSlot]
	lds	si,es:[di].FS_VAR	; DS:SI -> loop variable
	cmp	es:[di].FS_TYPE,VAR_DOUBLE
	je	fn1
	mov	ax,word ptr es:[di].FS_STEP
	add	[si].LOW,ax
	mov	ax,word ptr es:[di].FS_STEP+2
	adc	[si].HIW,ax
	jmp	short fn2
fn1:	mov	bx,FPU_ADD
	call	getFPUFunc		; DX:AX -> FPU_ADD
	push	bp
	mov	bp,sp
	push	dx
	push	ax			; [bp-4] -> FPU_ADD
	push	ds
	push	si			; push A (the loop variable)
	push	es
	add	di,FS_STEP
	push	di			; push B (the step)
	push	ds
	pop	es
	mov	di,si			; ES:DI -> loop variable (result)
	call	dword ptr [bp-4]
	mov	sp,bp
	pop	bp
fn2:	les	di,[pNextSlot]
	call	forTest
	pop	ds
	LEAVE
	RETURN
ENDPROC	forNext

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; forTest
;
; If the step is negative, the loop continues while the variable is >= the
; limit; otherwise, it continues while the variable is <= the limit.
;
; Inputs:
;	ES:DI -> FORSLOT
;
; Outputs:
;	DX:AX = non-zero to execute the loop body, zero if not
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	forTest
	push	ds
	lds	si,es:[di].FS_VAR	; DS:SI -> loop variable
	cmp	es:[di].FS_TYPE,VAR_DOUBLE
	je	ft5
	mov	ax,[si].LOW
	mov	dx,[si].HIW		; DX:AX = loop variable
	mov	bl,0			; BL = 0 if equal
	cmp	dx,word ptr es:[di].FS_LIMIT+2
	jne	ft1
	cmp	ax,word ptr es:[di].FS_LIMIT
	je	ft3
	jb	ft2a
	jmp	short ft2b
ft1:	jl	ft2a
ft2b:	inc	bx			; BL = 1 if greater
	jmp	short ft3
ft2a:	dec	bx			; BL = -1 if less
ft3:	test	byte ptr es:[di].FS_STEP+3,80h
	jz	ft4			; step is not negative
	neg	bl			; negative, so reverse the comparison
ft4:	sub	ax,ax			; assume we're done
	cmp	bl,0
	jg	ft9			; the variable is past the limit
	dec	ax			; we're not done
	jmp	short ft9
;
; For doubles, the variable is past the limit if it's > the limit (or < the
; limit, if the step is negative).
;
ft5:	mov	bx,FPU_GT
	test	byte ptr es:[di].FS_STEP+7,80h
	jz	ft6
	mov	bx,FPU_LT
ft6:	call	getFPUFunc		; DX:AX -> FPU_GT or FPU_LT
	push	bp
	mov	bp,sp
	push	dx
	push	ax			; [bp-4] -> function
	push	ds
	push	si			; push A (the loop variable)
	push	es
	add	di,FS_LIMIT
	push	di			; push B (the limit)
	call	dword ptr [bp-4]
	pop	ax			; AX = -1 if past the limit
	not	ax			; AX = -1 if not
	mov	sp,bp
	pop	bp
ft9:	cwd				; DX:AX = result
	pop	ds
	ret
ENDPROC	forTest

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getFPUFunc
;
; Inputs:
;	BX = FPUTBL offset
;
; Outputs:
;	DX:AX -> FPUTBL function
;
; Modifies:
;	AX, DX
;
DEFPROC	getFPUFunc
	push	ds
	push	si
	lds	si,cs:[FPU_TABLE]
	mov	ax,[si+bx]
	mov	dx,ds
	pop	si
	pop	ds
	ret
ENDPROC	getFPUFunc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doGosub
;
; Called by the code for GOSUB, which then jumps to the target line.  We push
; GOSUB_SIG and the return address (in the caller's code block, since RETURN
; may be in another code block) onto the caller's stack (underneath our own
; return address).
;
; Inputs:
;	AX = return offset (in the caller's code block)
;
; Outputs:
;	GOSUB_SIG and the return address pushed onto the stack
;
; Modifies:
;	BX, CX, DX
;
DEFPROC	doGosub,FAR
	pop	cx			; CX = our return offset
	pop	dx			; DX = our return segment
	mov	bx,GOSUB_SIG
	push	bx
	push	dx			; push the GOSUB return address
	push	ax
	mov	bx,ss:[PSP_HEAP]
	lea	bx,[bx].STACK + GOSUB_MIN
	cmp	sp,bx			; is there still enough stack space?
	jb	dg9			; no
	push	dx
	push	cx
	ret
dg9:	mov	al,7			; "Out of memory"
	jmp	short rtError
ENDPROC	doGosub

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doReturn
;
; Called by the code for RETURN (outside of DEF), to return to the code
; following the most recent GOSUB.
;
; Inputs:
;	GOSUB_SIG and return address on stack (underneath our return address)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	doReturn,FAR
	pop	cx			; discard our return address
	pop	cx
	pop	ax			; DX:AX = GOSUB return address
	pop	dx
	pop	bx			; BX = GOSUB_SIG (hopefully)
	cmp	bx,GOSUB_SIG
	jne	dr9
	push	dx
	push	ax
	ret
dr9:	mov	al,3			; "RETURN without GOSUB"
	jmp	short rtError
ENDPROC	doReturn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; rtError
;
; Reports a runtime error, using MSBASIC's error numbers.  If an ON ERROR
; handler is set (and we're not already in it), we reset the stack to its
; state at the start of the statement with the error (see findStmtSP), push
; the return address of the failed call from that statement's code (0:0 if
; there isn't one), for RESUME (see endErr), reset BP and DS to their state
; at the start of the program (see genCode), and jump to the handler;
; otherwise, we display the error message and abort the program, by way of
; our CTRLC handler (which also frees any blocks saved by callers; see
; restoreChains).
;
; Inputs:
;	AL = error number (eg, 5 for "Illegal function call")
;
; Outputs:
;	None (does not return)
;
DEFPROC	rtError
	push	ax
	call	findErl			; AX = line # of the error (for ERL)
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].ERR_LINE,ax
	pop	ax
	mov	ah,1
	xchg	ss:[bx].ERR_NUM,ax	; set the error # and active flag
	test	ah,ah			; were we already handling an error?
	jnz	re1			; yes
	cmp	ss:[bx].ERR_ADDR.SEG,0	; is there a handler?
	je	re1			; no
	mov	si,sp
	mov	ah,SIG_CBLK
	call	findRet			; DX:DI -> return address
	jnc	re0
	sub	dx,dx
	mov	di,dx
re0:	call	findStmtSP		; SI = SP of the statement
	mov	sp,si
	push	dx
	push	di
	mov	bp,ss:[bx].ERR_SP
	mov	ds,ss:[bx].VBLKDEF.BLK_NEXT
	jmp	dword ptr ss:[bx].ERR_ADDR

re1:	call	restoreMode		; (so that the message is visible)
	mov	dl,byte ptr ss:[bx].ERR_NUM
	IFDEF	DEBUG
	mov	dh,0			; DX = error number (for EPRINTF)
	ENDIF
	call	findMsg			; CS:SI -> message
	jc	re5			; unknown error
	EPRINTF	<"%ls">,<13,10>,dx,si,cs
	jmp	ctrlc
;
; An error without a message of its own (eg, "ERROR 200") is displayed with
; its error number, in every build.
;
re5:	PRINTF	<"%ls (%bu)",13,10>,si,cs,dx
	jmp	ctrlc
ENDPROC	rtError

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findMsg
;
; Finds the message for an error number, for runtime errors (see rtError)
; and compile-time errors (see compError).
;
; Inputs:
;	DL = error number
;
; Outputs:
;	CS:SI -> message (carry set if unknown, with "Unknown error")
;
; Modifies:
;	AL, SI
;
DEFPROC	findMsg
	mov	si,offset ERR_MSGS
fm1:	lods	byte ptr cs:[si]
	test	al,al			; end of the table?
	stc
	jz	fm9			; yes ("Unknown error")
	cmp	al,dl
	je	fm9			; (carry is clear)
fm2:	lods	byte ptr cs:[si]
	test	al,al
	jnz	fm2
	jmp	fm1
fm9:	ret
ENDPROC	findMsg

ERR_MSGS label byte
	db	1,"NEXT without FOR",0
	db	2,"Syntax error",0
	db	3,"RETURN without GOSUB",0
	db	4,"Out of DATA",0
	db	5,"Illegal function call",0
	db	7,"Out of memory",0
	db	8,"Undefined line number",0
	db	9,"Subscript out of range",0
	db	10,"Duplicate definition",0
	db	13,"Type mismatch",0
	db	14,"Out of string space",0
	db	15,"String too long",0
	db	20,"RESUME without error",0
	db	24,"Device timeout",0
	db	25,"Device fault",0
	db	26,"FOR without NEXT",0
	db	27,"Out of paper",0
	db	29,"WHILE without WEND",0
	db	30,"WEND without WHILE",0
	db	50,"FIELD overflow",0
	db	52,"Bad file number",0
	db	53,"File not found",0
	db	54,"Bad file mode",0
	db	55,"File already open",0
	db	57,"Device I/O error",0
	db	61,"Disk full",0
	db	62,"Input past end",0
	db	63,"Bad record number",0
	db	68,"Device unavailable",0
	db	70,"Permission denied",0
	db	71,"Disk not ready",0
	db	72,"Disk media error",0
	db	75,"Path/File access error",0
	db	0,"Unknown error",0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; onError
;
; Used by "ON ERROR GOTO line", whose code is a call to onError followed by
; a 5-byte JMP to the line (see genOnError); we record the address of the JMP
; as the ON ERROR handler, and then return past it.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	onError,FAR
	pop	ax
	pop	dx			; DX:AX -> JMP
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].ERR_ADDR.OFF,ax
	mov	ss:[bx].ERR_ADDR.SEG,dx
	add	ax,5
	push	dx
	push	ax
	ret
ENDPROC	onError

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; offError
;
; Used by "ON ERROR GOTO 0", which removes the ON ERROR handler.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	BX
;
DEFPROC	offError,FAR
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].ERR_ADDR.SEG,0
	ret
ENDPROC	offError

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resumeErr
;
; Used by "RESUME line" (before the JMP to the line), to end error handling
; and restore the stack to the start of the statement with the error (see
; endErr), so that, as in MSBASIC, any GOSUBs it was in are still active.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AL, BX, CX, DX, SI
;
DEFPROC	resumeErr,FAR
	call	endErr			; SI = SP of the statement
	pop	cx
	pop	dx			; DX:CX = return address
	mov	sp,si
	push	dx
	push	cx
	ret
ENDPROC	resumeErr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; endErr
;
; Ends the handling of an error, for RESUME, and returns the SP at the start
; of the statement with the error, below which rtError saved the return
; address of the failed call (see resumeStmt).  It's a "RESUME without error"
; error if no error is being handled.
;
; Inputs:
;	None
;
; Outputs:
;	SS:BX -> heap, SI = SP (see findStmtSP)
;
; Modifies:
;	AL, BX, SI
;
DEFPROC	endErr
	mov	bx,ss:[PSP_HEAP]
	mov	al,20			; "RESUME without error"
	cmp	byte ptr ss:[bx].ERR_NUM.HIB,0
	je	ee9			; no error is being handled
	mov	byte ptr ss:[bx].ERR_NUM.HIB,0
	jmp	short findStmtSP
ee9:	jmp	rtError
ENDPROC	endErr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findStmtSP
;
; Returns the SP at the start of the statement with the error: the program's
; SP (see ERR_SP in genCode), less any GOSUBs that were active (see doGosub),
; since nothing else remains on the stack from one statement to the next.
;
; Inputs:
;	SS:BX -> heap
;
; Outputs:
;	SI = SP
;
; Modifies:
;	SI
;
DEFPROC	findStmtSP
	mov	si,ss:[bx].ERR_SP
fss1:	cmp	word ptr ss:[si-2],GOSUB_SIG
	jne	fss9			; no (more) GOSUBs
	sub	si,6			; skip GOSUB_SIG and its return address
	jmp	fss1
fss9:	ret
ENDPROC	findStmtSP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; raiseError
;
; Used by "ERROR n", which simulates error n (1-255).
;
; Inputs:
;	1 32-bit arg on stack
;
; Outputs:
;	None (does not return)
;
DEFPROC	raiseError,FAR
	mov	bx,sp			; (our return address stays on the
	mov	ax,ss:[bx+4]		; stack for findErl)
	mov	dx,ss:[bx+6]		; DX:AX = error #
	test	dx,dx
	jnz	rse9
	dec	ax
	cmp	ax,255
	inc	ax
	jb	rse8
rse9:	mov	al,5			; "Illegal function call"
rse8:	jmp	rtError
ENDPROC	raiseError

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getErr (ERR)
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated with the last error #
;
; Modifies:
;	AX, BX
;
DEFPROC	getErr,FAR
	RETVAR	retErr,dword
	ENTER
	mov	bx,ss:[PSP_HEAP]
	mov	al,byte ptr ss:[bx].ERR_NUM
	mov	ah,0
	mov	[retErr].LOW,ax
	mov	[retErr].HIW,0
	LEAVE
	RETURN
ENDPROC	getErr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findErl
;
; Finds the line # of a runtime error (for ERL): we look for the far return
; address of the call from the generated code to the runtime function that
; failed (see findRet), and then find the last line label in the code
; before that address (or if there isn't one in that block, the last line
; label in the preceding block, since a line can span blocks).  A program
; without line numbers has no line labels, so ERL is zero.
;
; Inputs:
;	None
;
; Outputs:
;	AX = line # (zero if unknown)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, ES
;
DEFPROC	findErl
	mov	si,sp
	mov	ah,SIG_FBLK
	call	findRet			; DX:DI -> error
	jnc	fe4
	sub	ax,ax
	ret
fe4:	call	firstBlock		; AX = first block
	sub	cx,cx			; CX = line # (none yet)
fe5:	mov	es,ax
	sub	bp,bp			; BP = offset of best label in block
	mov	si,es:[CBLK_REFS]
fe6:	cmp	si,es:[BLK_SIZE]	; end of this LBLREF table?
	jae	fe7			; yes
	mov	ax,es:[si].LBL_IP
	test	ax,LBL_RESOLVE		; reference?
	jnz	fe6a			; yes
	cmp	es:[si].LBL_NUM,CTL_STMT; FOR, WHILE, statement, or resolved?
	jae	fe6a			; yes
	mov	bx,es
	cmp	bx,dx			; the block with the error?
	jne	fe6b			; no
	cmp	ax,di			; label at or after the return address?
	jae	fe6a			; yes
fe6b:	cmp	ax,bp			; the best label so far?
	jb	fe6a			; no
	mov	bp,ax
	mov	cx,es:[si].LBL_NUM
fe6a:	add	si,size LBLREF
	jmp	fe6
fe7:	mov	ax,es
	cmp	ax,dx			; was that the block with the error?
	je	fe9			; yes
	call	nextBlock
	test	ax,ax
	jnz	fe5
fe9:	xchg	ax,cx			; AX = line #
	ret
ENDPROC	findErl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findRet
;
; Scans the stack, upward from SS:SI, for the far return address of a call
; from the generated code: a pointer into a code block (or, if AH is SIG_FBLK,
; a function block) that follows a far CALL.
;
; Inputs:
;	AH = SIG_FBLK to include function blocks (otherwise, SIG_CBLK)
;	SS:SI -> stack
;
; Outputs:
;	If carry clear, DX:DI -> return address
;
; Modifies:
;	AL, DX, SI, DI, BP, ES
;
DEFPROC	findRet
	mov	bp,ss:[PSP_HEAP]
	lea	bp,[bp].STACK + size STACK
fr1:	cmp	si,bp			; reached the top of the stack?
	jae	fr8			; yes
	les	di,ss:[si]		; ES:DI = possible return address
	inc	si
	inc	si
	mov	al,es:[BLK_SIG]
	cmp	al,SIG_CBLK
	je	fr2
	cmp	al,ah
	jne	fr1
fr2:	cmp	di,es:[BLK_FREE]
	ja	fr1
	cmp	di,size CBLK + 5
	jb	fr1
	cmp	byte ptr es:[di-5],9Ah	; (OP_CALLF)
	jne	fr1
	mov	dx,es			; (and carry is clear)
	ret
fr8:	stc
	ret
ENDPROC	findRet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getErl (ERL)
;
; Returns the line # of the last runtime error (see findErl).
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX
;
DEFPROC	getErl,FAR
	RETVAR	retErl,dword
	ENTER
	mov	bx,ss:[PSP_HEAP]
	mov	ax,ss:[bx].ERR_LINE
	mov	[retErl].LOW,ax
	mov	[retErl].HIW,0
	LEAVE
	RETURN
ENDPROC	getErl

CODE	ENDS

	end
