;
; BASIC-DOS String Support Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<allocStrSpace>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalAddStr
;
; This is the first function to consider how the string pool will work.
;
; The pool will consist of zero or more blocks, each block will contain zero
; or more strings, and each string will consist of:
;
;	length byte (1-255)
;	characters (up to 255)
;
; Length zero is not used; empty strings have a null pointer.  Thus, a length
; of zero can be used to indicate unused pool space.
;
; This simplistic model makes it easy to append to a string if it's followed by
; enough unused bytes.
;
; Input stack:
;	pointer to target string data
;	pointer to source string data
;
; Output stack:
;	pointer to target string data
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	evalAddStr,FAR
	ARGVAR	pTarget,dword
	ARGVAR	pSource,dword
	DPRINTF	's',<"evalAddStr\r\n">
	ENTER
	push	ds
	lds	si,[pSource]
	les	di,[pTarget]
;
; If the source string pointer is null (ie, an empty string), that's
; the easiest case of all; there's nothing to do.  We'll assume that checking
; the offset is sufficient, since all our blocks begin with headers, so a
; non-zero offset should be impossible.
;
	test	si,si
	jz	as0
;
; If the target string pointer is null, it can simply "inherit" the source.
;
	test	di,di
	jnz	as1
	mov	[pTarget].OFF,si
	mov	[pTarget].SEG,ds
as0:	jmp	as9
;
; Get length of target string at ES:DI into CL, and verify that the new
; string will still be within limits.
;
as1:	mov	dl,es:[di]
	mov	dh,0
	mov	cl,dl
	mov	al,[si]
	add	dl,al
	jc	as8			; resulting string would be too big
;
; If the target string does NOT reside in a string pool block, then it must
; always be copied.
;
	cmp	es:[BLK_SIG],SIG_SBLK
	jne	as2			; target must be copied
;
; Check the target string to see if there's any (and enough) space after it.
;
	mov	ch,0
	mov	bx,di			; BX -> target also
	add	di,cx
	inc	di			; DI -> 1st byte after string
	mov	cx,es:[BLK_SIZE]
	sub	cx,di			; CX = max possible chars available
	mov	ah,0			; AX = length of source string
	cmp	cx,ax			; less than we need?
	jb	as2			; yes, target must be copied instead
	mov	cx,ax
	push	ax
	push	di
	mov	al,0
	rep	scasb			; zeros all the way?
	pop	di
	pop	ax
	jne	as2			; no, target must be copied instead
;
; Finally, an answer: we can simply copy the source to the end of the target.
;
	inc	si
	mov	cx,ax			; CX = length of source string
	rep	movsb			; copied
	add	es:[bx],al		; update length of target string
	ASSERT	NC
	jmp	short as9		; all done
;
; We must copy the target + source to a new location.  Combined length is DL.
; Use findStrSpace to find a sufficiently large space.
;
as2:	push	si			; push source
	push	ds
	push	di			; push target
	push	es
	call	findStrSpace		; DL = # bytes required
	pop	ds
	pop	si			; recover target in DS:SI
	jc	as4			; error
	mov	al,dl
	mov	bx,di
	mov	dx,es			; DX:BX = new string address
	stosb				; start with the new combined length
;
; This code to copy-and-zero target can be used ONLY if the target is in the
; string pool (NOT if it's a string constant in a code block).
;
; 	sub	ax,ax
; 	xchg	al,[si]
; 	inc	si
; 	xchg	cx,ax
; as3:	mov	al,0
; 	xchg	al,[si]
; 	inc	si
; 	stosb
; 	loop	as3

	lodsb
	mov	ah,0
	xchg	cx,ax
	rep	movsb

as4:	pop	ds			; recover source in DS:SI
	pop	si
	jc	as8
	lodsb
	mov	cl,al
	rep	movsb			; copy all the source bytes, too

as8:	jc	as9
	mov	[pTarget].OFF,bx
	mov	[pTarget].SEG,dx

as9:	pop	ds
	LEAVE
	ret	4			; clean off the source string pointer
ENDPROC	evalAddStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalEQStr
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	evalEQStr,FAR
	mov	bx,offset evalEQ
	DEFLBL	evalRelStr,near
	ARGVAR	eqA,dword
	ARGVAR	eqB,dword
	ENTER
	mov	cx,[eqA].LOW
	mov	dx,[eqB].LOW
	mov	ax,[eqA].HIW
	cmp	ax,[eqB].HIW
	jmp	bx
evalEQ:	jne	evalF
	cmp	cx,dx
	jne	evalF
	jmp	short evalT
evalNE:	jne	evalT
	cmp	cx,dx
	jne	evalT
	jmp	short evalF
evalLT:	jl	evalT
	jg	evalF
	cmp	cx,dx
	jl	evalT
	jmp	short evalF
evalGT:	jg	evalT
	jl	evalF
	cmp	cx,dx
	jg	evalT
	jmp	short evalF
evalLE:	jl	evalT
	jg	evalF
	cmp	cx,dx
	jle	evalT
	jmp	short evalF
evalGE:	jg	evalT
	jl	evalF
	cmp	cx,dx
	jge	evalT
	jmp	short evalF
evalT:	mov	ax,-1
	jmp	short evalX
evalF:	sub	ax,ax
evalX:	cwd
	mov	[eqA].LOW,ax
	mov	[eqA].HIW,dx
	LEAVE
	ret	4
ENDPROC	evalEQStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalNEStr
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	evalNEStr,FAR
	mov	bx,offset evalNE
	jmp	evalRelStr
ENDPROC	evalNEStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalLTStr
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	evalLTStr,FAR
	mov	bx,offset evalLT
	jmp	evalRelStr
ENDPROC	evalLTStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalGTStr
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	evalGTStr,FAR
	mov	bx,offset evalGT
	jmp	evalRelStr
ENDPROC	evalGTStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalLEStr
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	evalLEStr,FAR
	mov	bx,offset evalLE
	jmp	evalRelStr
ENDPROC	evalLEStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalGEStr
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	evalGEStr,FAR
	mov	bx,offset evalGE
	jmp	evalRelStr
ENDPROC	evalGEStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeStr
;
; Zero all the bytes referenced by the target variable.
;
; Inputs:
;	ES:DI -> string to free
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DI
;
DEFPROC	freeStr
	DPRINTF	's',<"freeStr: @%#08lx\r\n">,di,es
	mov	cl,es:[di]		; CL = string length
	mov	ch,0			; CX = length
	inc	cx			; CX = length + length byte
	mov	al,0
	rep	stosb			; zero away
	ret
ENDPROC	freeStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setStr
;
; Input stack:
;	pointer to target string variable
;	pointer to source string data
;
; Output stack:
;	None
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	setStr,FAR
	ARGVAR	pTargetVar,dword
	ARGVAR	pSource,dword
	DPRINTF	's',<"setStr\r\n">
	ENTER
	les	di,[pTargetVar]
;
; The general case involves storing the source address in the target variable
; after first zeroing all the bytes referenced by the target variable.
;
; However, there are a number of simple yet critical cases to check for first.
; For example, is the target is null?  If so, no further checks required.
;
	les	di,es:[di]
	test	di,di
	jz	ss8
;
; The target has a valid pointer, but before we zero its bytes, see if source
; and target are identical; if so, nothing to do at all.
;
	cmp	di,si
	jne	ss1
	mov	ax,es
	cmp	ax,[pSource].SEG
	je	ss9

ss1:	call	freeStr
;
; Transfer the pointer from DS:SI to the target variable now.
;
ss8:	push	ds
	les	di,[pTargetVar]
	lds	si,[pSource]
	mov	es:[di].OFF,si
	mov	es:[di].SEG,ds
	pop	ds

ss9:	LEAVE
	ret	8			; clean the stack
ENDPROC	setStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findStrSpace
;
; Inputs:
;	DX = # bytes required (not counting length byte)
;
; Outputs:
;	If successful, carry clear, ES:DI -> available space
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	findStrSpace
	DPRINTF	's',<"findStrSpace: %d bytes\r\n">,dx
	push	si
	push	ds
	push	ss
	pop	ds
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].SBLKDEF
	mov	ah,0

fss1:	mov	cx,[si]
	jcxz	fss6			; end of chain

	mov	es,cx
	mov	di,size SBLK		; ES:DI -> next location to check
	mov	bx,es:[BLK_SIZE]	; BX = limit

fss2:	cmp	di,bx
	jae	fss4
fss2a:	mov	al,es:[di]
	test	al,al
	jz	fss3
	add	di,ax
	inc	di
	jmp	fss2

fss3:	add	di,dx
	cmp	di,bx
	ja	fss4			; not enough room, even if free
	sub	di,dx			; rewind DI
	mov	cx,dx			; CX = # bytes required
	rep	scasb
	je	fss5
	dec	di			; rewind DI to the non-matching byte
	jmp	fss2a			; and continue scanning

fss4:	push	es
	pop	ds
	sub	si,si			; DS:SI -> BLK_NEXT
	jmp	fss1

fss5:	sub	di,dx			; ES:DI -> available space
	jmp	short fss9

fss6:	call	allocStrSpace		; ES:DI -> new space (if carry clear)

fss9:	pop	ds
	pop	si
	ret
ENDPROC	findStrSpace

CODE	ENDS

	end
