;
; BASIC-DOS Array Support Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<allocBlockSize,freeBlock,freeStr,rtError,getVarLen>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;
; An array is a VAR_ARRAY variable whose name is the array name followed by
; a type character ('%', '#', or '$'), so that A, A(), and A$() are all
; different variables.  The variable's data is a far pointer to the array's
; block (ABLK), which is zero until the array is dimensioned (by DIM, or
; automatically, with an upper bound of 10, when an element is first used).
;
; Each array has its own ABLK in the ABLKDEF chain, which contains this
; header, followed by the number of elements in each dimension (a word per
; dimension), followed by the elements themselves (4 bytes for VAR_LONG and
; VAR_STR, and 8 bytes for VAR_DOUBLE), all of which are initially zero.
;
; The elements of a string array own their strings (see str.asm), so the
; string pool updates them whenever it moves their strings.
;
ABLK		struc
ABLK_HDR	db size	BLKHDR dup (?)	; 00h
ABLK_TYPE	db	?		; 08h: element type (VAR_*)
ABLK_DIMS	db	?		; 09h: # of dimensions
ABLK_BASE	dw	?		; 0Ah: lower bound (OPTION BASE)
ABLK_SIZE	dw	?		; 0Ch: element size
ABLK_DATA	dw	?		; 0Eh: offset of first element
ABLK		ends

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; listDims
;
; Display array bounds without expanding or changing its elements.
;
; Inputs:
;	ES:DI -> array variable's far pointer
;
; Outputs:
;	Parenthesized lower and upper bounds written to STDOUT
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	listDims
	mov	ax,es:[di].SEG
	test	ax,ax
	jnz	ld0
	PRINTF	<"() = undimensioned",13,10>
	ret
ld0:	les	di,es:[di]
	mov	cl,es:[ABLK_DIMS]
	mov	ch,0
	mov	dx,es:[ABLK_BASE]
	mov	di,size ABLK
	PRINTF	<"(">
ld1:	mov	ax,es:[di]
	add	ax,dx
	dec	ax			; upper bound = base + count - 1
	PRINTF	<"%u TO %u">,dx,ax
	add	di,2
	loop	ld2
	PRINTF	<")",13,10>
	ret
ld2:	PRINTF	<", ">
	jmp	ld1
ENDPROC	listDims

AUTO_BOUND	equ	10		; upper bound of undimensioned arrays

;
; The array functions called by generated code take a variable number of
; arguments, so they can't simply use RET N.  The generated code pushes:
;
;	far pointer to the array variable
;	N 32-bit subscripts (or upper bounds, for DIM)
;	16-bit value with N in the low byte and the element type in the high
;
; and on return, all those values have been removed, and for getElemPtr and
; getElemVal, replaced with a single 32-bit result.  After setting up BP,
; these frame offsets apply:
;
ARR_INFO	equ	6		; [bp+6]: element type and N
ARR_SUBS	equ	8		; [bp+8]: last subscript

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dimArray (DIM)
;
; Inputs:
;	See above (the subscripts are the upper bound of each dimension)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	dimArray,FAR
	push	bp
	mov	bp,sp
	call	getArrayVar		; ES:DI -> array variable
	mov	ax,es:[di].SEG
	test	ax,ax			; already dimensioned?
	jz	dm1			; no
	jmp	arrDup
dm1:	mov	bl,0			; BL = 0 (use the upper bounds)
	call	allocArray
	mov	cl,0			; CL = 0 (no result)
	jmp	arrReturn
ENDPROC	dimArray

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getElemPtr
;
; Inputs:
;	See above
;
; Outputs:
;	Far pointer to the element on the stack
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	getElemPtr,FAR
	push	bp
	mov	bp,sp
	call	findElem		; ES:DI -> element
	mov	ax,di
	mov	dx,es			; DX:AX = result
	jmp	short getElem9
ENDPROC	getElemPtr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getElemVal
;
; Used for VAR_LONG and VAR_STR elements; VAR_DOUBLE elements, like all
; doubles, are passed by reference instead (see getElemPtr).
;
; Inputs:
;	See above
;
; Outputs:
;	32-bit element value on the stack
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	getElemVal,FAR
	push	bp
	mov	bp,sp
	call	findElem		; ES:DI -> element
	mov	ax,es:[di].LOW
	mov	dx,es:[di].HIW		; DX:AX = result
	DEFLBL	getElem9,near
	mov	cl,1			; CL = 1 (result in DX:AX)
	jmp	short arrReturn
ENDPROC	getElemVal

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; arrReturn
;
; Removes the arguments (see above), pushes the result (if any), and returns
; to the generated code.
;
; Inputs:
;	BP -> frame
;	CL = 1 if DX:AX contains a result, 0 if not
;
; Outputs:
;	None
;
DEFPROC	arrReturn,FAR
	mov	si,[bp+ARR_INFO]
	and	si,0FFh
	add	si,si
	add	si,si
	lea	bx,[bp+si+ARR_SUBS+4]	; SS:BX -> top of the arguments
	push	[bp+4]
	push	[bp+2]			; save the return address
	mov	si,[bp]			; and the caller's BP
	pop	ss:[bx-8]		; move the return address up
	pop	ss:[bx-6]		; (with room for DX:AX above it)
	cmp	cl,1			; is there a result?
	jne	ar8			; no
	mov	ss:[bx-4],ax
	mov	ss:[bx-2],dx
	lea	sp,[bx-8]
	jmp	short ar9
ar8:	mov	ax,ss:[bx-8]
	mov	dx,ss:[bx-6]
	mov	ss:[bx-4],ax		; move the return address up further
	mov	ss:[bx-2],dx
	lea	sp,[bx-4]
ar9:	mov	bp,si
	ret
ENDPROC	arrReturn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; eraseArray (ERASE)
;
; Frees the array's block (and if it's a string array, all its strings)
; and resets the array variable, so that the array can be dimensioned again.
;
; Input stack:
;	far pointer to the array variable
;
; Output stack:
;	None
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	eraseArray,FAR
	ARGVAR	pArrayVar,dword
	ENTER
	push	ds
	lds	si,[pArrayVar]
	call	freeArray
	pop	ds
	LEAVE
	RETURN
ENDPROC	eraseArray

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeArray
;
; Frees an array's block (and the strings of a string array), and zeroes the
; array variable, so that the array can be dimensioned again.
;
; Inputs:
;	DS:SI -> array variable
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	freeArray
	push	si
	push	ds
	sub	ax,ax
	mov	[si].OFF,ax
	xchg	ax,[si].SEG		; AX = array block (and zero it)
	test	ax,ax			; was it dimensioned?
	jz	ea9			; no
	mov	ds,ax
	cmp	ds:[ABLK_TYPE],VAR_STR	; string array?
	jne	ea8			; no
	mov	si,ds:[ABLK_DATA]
ea1:	cmp	si,ds:[BLK_FREE]	; end of the elements?
	jae	ea8			; yes
	les	di,[si]			; ES:DI = element
	call	freeVarStr		; free the element's string
	add	si,4
	jmp	ea1
ea8:	push	ds
	pop	es			; ES = array block
	push	ss
	pop	ds
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].ABLKDEF
	call	freeBlock
ea9:	pop	ds
	pop	si
	ret
ENDPROC	freeArray

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeVarStr
;
; Frees a string (if any) that a string variable or element points to; a
; string that isn't in a string block (eg, a constant in a code block) is
; left alone.
;
; Inputs:
;	ES:DI -> string (or null)
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	freeVarStr
	test	di,di
	jz	fvs9
	cmp	es:[BLK_SIG],SIG_SBLK
	jne	fvs9
	call	freeStr
fvs9:	ret
ENDPROC	freeVarStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clearVars
;
; Used by "CLEAR", which resets every numeric variable to zero and every
; string variable to the empty string, and erases every array.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	clearVars,FAR
	push	ds
	cld
	mov	si,ss:[PSP_HEAP]
	mov	ax,ss:[si].VBLKDEF.BLK_NEXT
cv1:	test	ax,ax			; any more var blocks?
	jz	cv9			; no
	mov	ds,ax
	mov	si,size VBLK		; DS:SI -> first var in the block
cv2:	lodsb
	cmp	al,VAR_DEAD		; dead byte?
	je	cv2			; yes
	jb	cv8			; no, end of the block
	mov	ah,al
	and	ah,VAR_TYPE		; AH = var type
	and	al,VAR_NAMELEN
	mov	cl,al
	mov	ch,0
	add	si,cx			; DS:SI -> var data
	push	ds
	pop	es
	mov	di,si
	push	ax
	call	getVarLen		; AX = length of var data
	xchg	cx,ax			; CX = length
	pop	ax			; AH = var type
	cmp	ah,VAR_STR
	jne	cv3
	les	di,[si]
	call	freeVarStr		; free the string (if any)
	jmp	short cv5		; and then zero the var
cv3:	cmp	ah,VAR_ARRAY
	jne	cv4
	push	cx
	call	freeArray		; erase the array (and zero the var)
	pop	cx
	jmp	short cv6
cv4:	cmp	ah,VAR_LONG
	je	cv5
	cmp	ah,VAR_DOUBLE		; anything else (eg, a function)
	jne	cv6			; is left alone
cv5:	push	ds
	pop	es
	mov	di,si
	push	cx
	mov	al,0
	rep	stosb			; zero the var
	pop	cx
cv6:	add	si,cx
	jmp	cv2
cv8:	mov	ax,ds:[BLK_NEXT]
	jmp	cv1
cv9:	pop	ds
	ret
ENDPROC	clearVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setOptBase (OPTION BASE)
;
; Inputs:
;	AL = 0 or 1
;
; Outputs:
;	None
;
; Modifies:
;	BX
;
DEFPROC	setOptBase,FAR
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].OPT_BASE,al
	ret
ENDPROC	setOptBase

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findElem
;
; Inputs:
;	BP -> frame (see above)
;
; Outputs:
;	ES:DI -> element (an error is reported if a subscript is out of range)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	findElem
	call	getArrayVar		; ES:DI -> array variable
	mov	ax,es:[di].SEG
	test	ax,ax			; dimensioned?
	jnz	fe1			; yes
	mov	bl,1			; no, so dimension it automatically
	call	allocArray		; AX = array block
fe1:	mov	es,ax
	mov	cl,[bp+ARR_INFO]	; CL = # of subscripts
	cmp	cl,es:[ABLK_DIMS]	; does it match the # of dimensions?
	jne	fe9			; no
	mov	ch,0
	mov	si,cx
	add	si,si
	add	si,si
	lea	si,[bp+si+ARR_SUBS-4]	; SS:SI -> first subscript
	mov	bx,ABLK_DATA+2		; ES:BX -> first dimension
	sub	di,di			; DI = element index
fe2:	mov	ax,ss:[si].LOW
	mov	dx,ss:[si].HIW
	sub	ax,es:[ABLK_BASE]
	sbb	dx,0			; DX:AX = subscript - base
	jnz	fe9			; out of range (negative or too large)
	cmp	ax,es:[bx]
	jae	fe9			; out of range
	xchg	ax,di			; AX = index so far, DI = subscript
	mul	word ptr es:[bx]
	add	di,ax			; DI = new index
	add	bx,2
	sub	si,4
	loop	fe2
	mov	ax,di
	mul	word ptr es:[ABLK_SIZE]
	add	ax,es:[ABLK_DATA]
	xchg	di,ax			; ES:DI -> element
	ret
fe9:	jmp	arrRange
ENDPROC	findElem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocArray
;
; Inputs:
;	BP -> frame (see above)
;	BL = 0 to use the subscripts as upper bounds, 1 to use AUTO_BOUND
;	ES:DI -> array variable
;
; Outputs:
;	AX = array block (and array variable updated)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	allocArray
	push	es
	push	di
	mov	bh,bl			; BH = 1 if automatic
	mov	cl,[bp+ARR_INFO]	; CX = # of dimensions
	mov	ch,0
	mov	si,cx
	add	si,si
	add	si,si
	lea	si,[bp+si+ARR_SUBS-4]	; SS:SI -> first upper bound
	mov	di,ss:[PSP_HEAP]
	mov	al,ss:[di].OPT_BASE
	cbw
	xchg	di,ax			; DI = lower bound
	mov	ax,1			; AX = total # of elements
aa1:	mov	dx,AUTO_BOUND + 1
	test	bh,bh			; automatic?
	jnz	aa2			; yes
	mov	dx,ss:[si].LOW
	cmp	ss:[si].HIW,0		; upper bound in range?
	jne	aa9		; no
	inc	dx			; DX = upper bound + 1
	jz	aa9
aa2:	sub	dx,di			; DX = # of elements in dimension
	jbe	aa9		; must be at least 1
	test	bh,bh			; automatic?
	jnz	aa2a			; yes, so preserve the subscript
	mov	ss:[si].LOW,dx		; no, so save # of elements for later
aa2a:	mul	dx			; DX:AX = new total
	jc	aa8		; too large
	sub	si,4
	loop	aa1
	jmp	short aa2b
aa8:	jmp	arrMemory
aa9:	jmp	arrIllegal
aa2b:
;
; AX is the total # of elements; multiply by the element size and add the
; header size and dimension sizes to get the block size.
;
	mov	cx,4			; CX = element size
	cmp	byte ptr [bp+ARR_INFO+1],VAR_DOUBLE
	jne	aa3
	add	cx,cx
aa3:	mul	cx
	jc	aa8
	mov	dl,[bp+ARR_INFO]
	mov	dh,0			; DX = # of dimensions
	add	dx,dx
	add	ax,dx
	jc	aa8
	add	ax,size ABLK
	jc	aa8
	cmp	ax,0FFF0h
	ja	aa8
	push	cx
	push	ds
	push	ss
	pop	ds
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].ABLKDEF
	xchg	cx,ax			; CX = size of block
	call	allocBlockSize		; ES:DI -> zeroed block
	pop	ds
	pop	ax			; AX = element size
	jc	aa8
	mov	es:[BLK_FREE],cx	; BLK_FREE = end of the elements
	mov	es:[ABLK_SIZE],ax
	mov	al,[bp+ARR_INFO+1]
	mov	es:[ABLK_TYPE],al
	mov	cl,[bp+ARR_INFO]
	mov	es:[ABLK_DIMS],cl
	mov	ch,0
	mov	si,ss:[PSP_HEAP]
	mov	al,ss:[si].OPT_BASE
	cbw
	mov	es:[ABLK_BASE],ax
	mov	dx,AUTO_BOUND + 1
	sub	dx,ax			; DX = # of elements if automatic
	mov	si,cx
	add	si,si
	add	si,si
	lea	si,[bp+si+ARR_SUBS-4]	; SS:SI -> # of elements in 1st dim
	mov	di,ABLK_DATA+2
aa4:	mov	ax,dx
	test	bh,bh			; automatic?
	jnz	aa5			; yes
	mov	ax,ss:[si].LOW
aa5:	stosw				; store # of elements in each dimension
	sub	si,4
	loop	aa4
	mov	es:[ABLK_DATA],di	; elements follow
	mov	ax,es
	pop	di
	pop	es			; ES:DI -> array variable
	mov	es:[di].OFF,0
	mov	es:[di].SEG,ax
	ret
ENDPROC	allocArray

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getArrayVar
;
; Inputs:
;	BP -> frame (see above)
;
; Outputs:
;	ES:DI -> array variable
;
; Modifies:
;	DI, ES
;
DEFPROC	getArrayVar
	mov	di,[bp+ARR_INFO]
	and	di,0FFh
	add	di,di
	add	di,di
	les	di,[bp+di+ARR_SUBS]
	ret
ENDPROC	getArrayVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Runtime errors
;
; These report the error (see rtError), using MSBASIC's error numbers.
;
arrRange:
	mov	al,9			; "Subscript out of range"
	jmp	short arrError
arrDup:
	mov	al,10			; "Duplicate definition"
	jmp	short arrError
arrIllegal:
	mov	al,5			; "Illegal function call"
	jmp	short arrError
arrMemory:
	mov	al,7			; "Out of memory"
arrError:
	jmp	rtError

CODE	ENDS

	end
