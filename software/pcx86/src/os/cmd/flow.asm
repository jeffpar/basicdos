;
; BASIC-DOS Control Flow Support Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<ctrlc>
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
dg9:	PRINTF	<"Out of memory",13,10>
	jmp	ctrlc
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
dr9:	PRINTF	<"RETURN without GOSUB",13,10>
	jmp	ctrlc
ENDPROC	doReturn

CODE	ENDS

	end
