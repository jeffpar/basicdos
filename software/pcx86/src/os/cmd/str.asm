;
; BASIC-DOS String Support Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<allocStrSpace,freeBlock,rtError>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;
; A string value is a far pointer to a length byte (1-255) followed by the
; string's characters; an empty string is a null pointer.  String constants
; live in code blocks, and all other strings live in the string pool, which
; consists of zero or more string blocks (SBLKs).  Each string in the pool is
; an entry with a 5-byte header preceding the length byte:
;
;	tag (STR_FREE, STR_TEMP, STR_HELD, or STR_OWNED)
;	owner (far pointer to the variable that owns the string, if STR_OWNED)
;
; A tag of zero (STR_PAD) is a single byte of padding instead.  Entries are
; allocated from the end of a block (BLK_FREE), and when a string is freed, it
; becomes a STR_FREE entry, unless it's at the end of its block, in which case
; BLK_FREE simply moves back.
;
; A STR_TEMP string is the result of a string operation (eg, concatenation or
; LEFT$), and every function that consumes a string value calls releaseStr,
; which frees the string if it's a STR_TEMP.  Assigning a STR_TEMP string to
; a variable simply changes its tag to STR_OWNED and sets its owner; all other
; strings (eg, constants and strings owned by other variables) are copied.
; A STR_HELD string is a STR_TEMP string passed to a user-defined function,
; which must not be freed until the function returns, since the function may
; use its parameter more than once.
;
; When there's no room at the end of any block, compactStrs moves STR_OWNED
; strings down over any free space (updating their owners), frees any STR_TEMP
; or STR_HELD strings that are no longer referenced (eg, those passed to a
; user-defined function that has since returned), and frees any empty blocks.
;
; Moving a string while an expression is being evaluated would be a problem
; if a pointer to it was waiting on the stack.  However, all such pointers live
; on the stack, which is small, so compactBlock scans the stack for pointers
; into the block, and any string that is referenced is "pinned" (ie, not moved
; or freed).  That makes it safe to compact the pool at any time.
;
STR_PAD		equ	0
STR_FREE	equ	1
STR_TEMP	equ	2
STR_HELD	equ	3
STR_OWNED	equ	4
STR_HDR		equ	5		; # header bytes preceding length byte
STR_SLACK	equ	SBLKLEN / 4	; desired free space after compaction
MAX_PINS	equ	16		; max pinned strings per block

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocStr
;
; Allocates a STR_TEMP string with the given length.  We first look for room
; at the end of a block; failing that, we compact the pool, and if that doesn't
; leave STR_SLACK bytes of room to spare, we allocate a new block (or failing
; that, settle for any block with enough room).
;
; Inputs:
;	CX = length (1-255)
;
; Outputs:
;	ES:DI -> length byte of new string (if there's no room, an error is
;	reported and the program is aborted)
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	allocStr
	push	bx
	push	cx
	push	dx
	push	si
	mov	dx,cx
	add	dx,STR_HDR+1		; DX = size of entry
	mov	bl,0			; BL = pass #
al1:	mov	si,ss:[PSP_HEAP]
	mov	ax,ss:[si].SBLKDEF.BDEF_NEXT
	mov	cx,dx
	cmp	bl,1			; pass 1 requires extra room
	jne	al2
	add	cx,STR_SLACK
al2:	test	ax,ax			; end of chain?
	jz	al4			; yes
	mov	es,ax
	mov	ax,es:[BLK_SIZE]
	sub	ax,es:[BLK_FREE]	; AX = room at end of block
	cmp	ax,cx
	jae	al6
	mov	ax,es:[BLK_NEXT]
	jmp	al2
al4:	inc	bl
	cmp	bl,1			; pass 0 failed?
	jne	al5			; no
	call	compactStrs
	jmp	al1
al5:	cmp	bl,2			; pass 1 failed?
	jne	al8			; no, pass 2 failed, so give up
	push	ds
	push	ss
	pop	ds
	call	allocStrSpace		; ES:DI -> new block
	pop	ds
	jc	al1			; no new block, so try pass 2
al6:	mov	di,es:[BLK_FREE]
	add	es:[BLK_FREE],dx
	mov	al,STR_TEMP
	stosb
	sub	ax,ax
	stosw				; zero the owner
	stosw
	xchg	ax,dx
	sub	al,STR_HDR+1
	mov	es:[di],al		; set the length
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
al8:	jmp	strNoSpace
ENDPROC	allocStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; compactStrs
;
; Compacts every string block (see compactBlock), freeing any that end up
; empty.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	compactStrs
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	push	ss
	pop	ds			; DS -> heap
	mov	si,ds:[PSP_HEAP]
	lea	si,[si].SBLKDEF		; DS:SI -> head of SBLK chain
	mov	ax,[si].BDEF_NEXT
cs1:	test	ax,ax
	jz	cs9
	mov	es,ax
	push	es:[BLK_NEXT]
	call	compactBlock
	cmp	es:[BLK_FREE],size SBLK	; is the block empty now?
	jne	cs2			; no
	push	si
	call	freeBlock		; free block ES in chain at DS:SI
	pop	si
cs2:	pop	ax
	jmp	cs1
cs9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	compactStrs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; compactBlock
;
; First, we collect the offsets of any pointers into this block from the
; stack; those strings are pinned.  Then we walk the block, moving unpinned
; STR_OWNED strings down and updating their owners, skipping STR_FREE entries,
; padding, and unpinned STR_TEMP and STR_HELD strings (ie, freeing them), and
; padding any gap that precedes a pinned string.
;
; Inputs:
;	DS = SS (heap)
;	ES = block segment
;
; Outputs:
;	BLK_FREE updated
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	compactBlock
	push	si
	push	bp
	sub	sp,MAX_PINS * 2
	mov	bp,sp			; SS:BP -> array of pinned offsets
	mov	bx,ds:[PSP_HEAP]
	lea	bx,[bx].STACK + size STACK - 4
	lea	si,[bp + MAX_PINS * 2]	; scan from above the array
	sub	dx,dx			; DX = # pins
	mov	ax,es
cb1:	cmp	si,bx			; done scanning the stack?
	ja	cb4			; yes
	cmp	[si+2],ax		; pointer into this block?
	jne	cb3			; no
	cmp	dx,MAX_PINS		; room for another pin?
	jb	cb2			; yes
	mov	dx,-1			; no, so pin everything
	jmp	short cb4
cb2:	mov	di,dx
	add	di,di
	mov	cx,[si]
	mov	[bp+di],cx		; record the offset
	inc	dx
cb3:	inc	si
	inc	si
	jmp	cb1

cb4:	mov	si,size SBLK		; SI = source
	mov	di,si			; DI = destination
cb5:	cmp	si,es:[BLK_FREE]
	jae	cb9
	mov	cl,es:[si]		; CL = tag
	test	cl,cl			; padding?
	jnz	cb6			; no
	inc	si
	jmp	cb5
cb6:	mov	bl,es:[si+STR_HDR]
	mov	bh,0
	add	bx,STR_HDR+1		; BX = size of entry
	cmp	cl,STR_FREE
	je	cb8			; skip free entries
	lea	ax,[si+STR_HDR]		; AX = offset of length byte
	call	isPinned
	je	cb7			; pinned
	cmp	cl,STR_OWNED
	jne	cb8			; unreferenced STR_TEMP or STR_HELD
	cmp	si,di			; does it need to move?
	je	cb7a			; no
	push	ds
	push	es
	pop	ds
	mov	cx,bx
	rep	movsb			; move it (SI and DI advance by BX)
	sub	di,bx			; ES:DI -> moved entry
	push	si
	lea	ax,[di+STR_HDR]
	lds	si,es:[di+1]		; DS:SI -> owner
	mov	[si].OFF,ax		; update the owner
	mov	[si].SEG,es
	pop	si
	pop	ds
	add	di,bx
	jmp	cb5
;
; The entry is pinned, so pad any gap preceding it and resume after it.
;
cb7:	mov	cx,si
	sub	cx,di
	mov	al,STR_PAD
	rep	stosb
cb7a:	add	si,bx
	mov	di,si
	jmp	cb5
cb8:	add	si,bx
	jmp	cb5

cb9:	mov	es:[BLK_FREE],di
	add	sp,MAX_PINS * 2
	pop	bp
	pop	si
	ret
;
; isPinned returns ZF set if the offset in AX is one of the DX offsets at
; SS:BP (or if DX is -1).
;
isPinned:
	cmp	dx,-1
	je	ip9
	push	cx
	push	di
	mov	cx,dx
	mov	di,bp
	jcxz	ip8
ip1:	cmp	[di],ax
	je	ip7
	inc	di
	inc	di
	loop	ip1
ip8:	inc	cx			; clear ZF
ip7:	pop	di
	pop	cx
ip9:	ret
ENDPROC	compactBlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; freeStr
;
; Inputs:
;	ES:DI -> length byte of string in the pool
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	freeStr
	push	ax
	push	di
	mov	byte ptr es:[di-STR_HDR],STR_FREE
	mov	al,es:[di]
	mov	ah,0
	inc	ax
	add	di,ax			; DI -> end of entry
	cmp	di,es:[BLK_FREE]	; at the end of the block?
	jne	fs9			; no
	sub	di,ax
	sub	di,STR_HDR		; DI -> start of entry
	mov	es:[BLK_FREE],di	; so just move BLK_FREE back
fs9:	pop	di
	pop	ax
	ret
ENDPROC	freeStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; releaseStr
;
; Frees the string if it's a STR_TEMP string; every function that consumes
; a string value should call this when it's done with the value.
;
; Inputs:
;	ES:DI = string value
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	releaseStr
	call	isTempStr
	jne	rs9
	call	freeStr
rs9:	ret
ENDPROC	releaseStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; isTempStr
;
; Inputs:
;	ES:DI = string value
;
; Outputs:
;	ZF set if the string is a STR_TEMP string in the pool
;
; Modifies:
;	None
;
DEFPROC	isTempStr
	test	di,di			; empty string?
	jz	its8			; yes
	cmp	es:[BLK_SIG],SIG_SBLK	; in the pool?
	jne	its9			; no
	cmp	byte ptr es:[di-STR_HDR],STR_TEMP
	ret
its8:	cmp	di,1			; clear ZF
its9:	ret
ENDPROC	isTempStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; holdStr
;
; Changes the string on top of the caller's stack from STR_TEMP to STR_HELD
; (see the description of the pool above), leaving it on the stack.
;
; Inputs:
;	string value on stack (NOT popped)
;
; Outputs:
;	None
;
; Modifies:
;	DI, ES
;
DEFPROC	holdStr,FAR
	push	bp
	mov	bp,sp
	les	di,[bp+6]
	call	isTempStr
	jne	hs9
	mov	byte ptr es:[di-STR_HDR],STR_HELD
hs9:	pop	bp
	ret
ENDPROC	holdStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swapArgs
;
; Swaps the two 32-bit values on top of the caller's stack (eg, to insert a
; default parameter before a parameter that has already been pushed).
;
; Inputs:
;	2 32-bit values on stack (NOT popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	swapArgs,FAR
	push	bp
	mov	bp,sp
	mov	ax,[bp+6]
	xchg	ax,[bp+10]
	mov	[bp+6],ax
	mov	ax,[bp+8]
	xchg	ax,[bp+12]
	mov	[bp+8],ax
	pop	bp
	ret
ENDPROC	swapArgs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setStr
;
; Sets a string variable.  The variable's current string (if any) is freed,
; and then the variable either adopts the new string (if it's STR_TEMP) or
; gets a copy of it.
;
; Input stack:
;	pointer to target string variable
;	source string value
;
; Output stack:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	setStr,FAR
	ARGVAR	pTargetVar,dword
	ARGVAR	pSource,dword
	ENTER
	push	ds
	lds	si,[pTargetVar]		; DS:SI -> variable
	les	di,[si]			; ES:DI = current value
	mov	ax,es
	cmp	di,[pSource].OFF	; is the variable being set to itself?
	jne	ss1			; no
	cmp	ax,[pSource].SEG
	je	ss9			; yes, nothing to do
ss1:	sub	ax,ax
	mov	[si].OFF,ax		; set the variable to empty
	mov	[si].SEG,ax
	test	di,di			; did it have a value?
	jz	ss2			; no
	cmp	es:[BLK_SIG],SIG_SBLK
	jne	ss2
	call	freeStr			; free the variable's string
ss2:	les	di,[pSource]
	test	di,di			; empty string?
	jz	ss9			; yes, so we're done
	call	isTempStr		; STR_TEMP string?
	je	ss3			; yes, so adopt it
	mov	cl,es:[di]
	mov	ch,0
	call	allocStr		; ES:DI -> new string
	push	di
	lds	si,[pSource]
	movsb				; copy the length byte
	mov	cl,es:[di-1]
	rep	movsb			; and the characters
	pop	di
ss3:	mov	byte ptr es:[di-STR_HDR],STR_OWNED
	mov	ax,[pTargetVar].OFF
	mov	es:[di-STR_HDR+1],ax
	mov	ax,[pTargetVar].SEG
	mov	es:[di-STR_HDR+3],ax
	lds	si,[pTargetVar]
	mov	[si].OFF,di
	mov	[si].SEG,es
ss9:	pop	ds
	LEAVE
	RETURN
ENDPROC	setStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalAddStr
;
; Concatenates two strings.  If A is a STR_TEMP string at the end of its
; block, and there's enough room after it, then B is simply appended to A;
; otherwise, a new string is allocated.
;
; Input stack:
;	string value A
;	string value B
;
; Output stack:
;	string value A + B
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	evalAddStr,FAR
	ARGVAR	pA,dword
	ARGVAR	pB,dword
	ENTER
	push	ds
	les	di,[pA]
	lds	si,[pB]
	test	si,si			; is B empty?
	jz	ea0			; yes, so the result is A
	test	di,di			; is A empty?
	jnz	ea1			; no
	mov	[pA].OFF,si		; yes, so the result is B
	mov	[pA].SEG,ds
ea0:	jmp	ea9
ea1:	mov	al,es:[di]
	mov	ah,0
	mov	cl,[si]
	mov	ch,0			; CX = length of B
	add	ax,cx			; AX = length of A + B
	cmp	ax,255
	ja	ea10
	call	isTempStr		; is A a STR_TEMP string?
	jne	ea3			; no
	cmp	di,si			; is B the same string?
	jne	ea2			; no
	mov	dx,ds
	mov	bx,es
	cmp	dx,bx
	je	ea3			; yes
ea2:	mov	bl,es:[di]
	mov	bh,0			; BX = length of A
	lea	dx,[bx+di+1]		; DX -> end of A
	cmp	dx,es:[BLK_FREE]	; is A at the end of its block?
	jne	ea3			; no
	mov	dx,es:[BLK_SIZE]
	sub	dx,es:[BLK_FREE]
	cmp	dx,cx			; enough room for B?
	jb	ea3			; no
	add	es:[BLK_FREE],cx
	mov	es:[di],al		; update the length of A
	add	di,bx
	inc	di			; ES:DI -> end of A
	inc	si			; DS:SI -> chars of B
	rep	movsb			; append B
	jmp	short ea8

ea3:	xchg	cx,ax			; CX = length of A + B
	call	allocStr		; ES:DI -> new string
	push	di
	inc	di
	lds	si,[pA]
	lodsb
	mov	cl,al
	rep	movsb			; copy A
	lds	si,[pB]
	lodsb
	mov	cl,al
	rep	movsb			; copy B
	pop	di
	push	es
	push	di
	les	di,[pA]
	call	releaseStr
	pop	[pA].OFF		; the result is the new string
	pop	[pA].SEG
ea8:	les	di,[pB]
	call	releaseStr
ea9:	pop	ds
	LEAVE
	ret	4			; clean off the B value
ea10:	jmp	strTooLong
ENDPROC	evalAddStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; evalEQStr
;
; Comparing strings requires comparing corresponding bytes until the bytes
; are unequal or until the end of both strings is reached.  The result of the
; final byte comparison determines the return value.
;
; Null pointers indicate empty strings and can be detected by checking either
; the segment OR the offset for zero; both will be zero, but it's sufficient to
; check only one, since non-null pointers never have a zero segment OR offset.
;
; Inputs:
;	2 32-bit args on stack (popped)
;
; Outputs:
;	1 32-bit result on stack (pushed)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	evalEQStr,FAR
	mov	bx,offset evalEQ
	DEFLBL	evalRelStr,near
	ARGVAR	pStrA,dword
	ARGVAR	pStrB,dword
	ENTER
	push	ds
	sub	cx,cx			; CL = len of strA, CH = len of strB
	lds	si,[pStrA]
	les	di,[pStrB]
	test	si,si
	jz	es1
	lodsb
	mov	cl,al
es1:	test	di,di
	jz	es2
	mov	ch,es:[di]
	inc	di
;
; We're ready to start comparing corresponding bytes; the lengths in CL and CH
; determine whether we can really fetch another byte from DS:[SI] and ES:[DI],
; respectively; otherwise, the zeros we preload in AL and AH are used instead.
;
es2:	sub	ax,ax
	jcxz	es5			; end of both strings has been reached
	test	cl,cl
	jz	es3
	lodsb				; AL = next byte from strA
	dec	cx			; CL = CL - 1
es3:	test	ch,ch
	jz	es4
	mov	ah,es:[di]		; AH = next byte from strB
	inc	di			;
	dec	ch			; CH = CH - 1
es4:	cmp	al,ah
	je	es2
es5:	jmp	bx

evalEQ:	je	evalT
	jmp	short evalF
evalNE:	jne	evalT
	jmp	short evalF
evalLT:	jb	evalT
	jmp	short evalF
evalGT:	ja	evalT
	jmp	short evalF
evalLE:	jbe	evalT
	jmp	short evalF
evalGE:	jb	evalF

evalT:	mov	ax,-1
	jmp	short evalX

evalF:	sub	ax,ax
evalX:	les	di,[pStrA]
	call	releaseStr
	les	di,[pStrB]
	call	releaseStr
	cwd
	mov	[pStrA].LOW,ax
	mov	[pStrA].HIW,dx
	pop	ds
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
;	AX, BX, CX, DX, SI, DI, ES
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
;	AX, BX, CX, DX, SI, DI, ES
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
;	AX, BX, CX, DX, SI, DI, ES
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
;	AX, BX, CX, DX, SI, DI, ES
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
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	evalGEStr,FAR
	mov	bx,offset evalGE
	jmp	evalRelStr
ENDPROC	evalGEStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Runtime errors
;
; These report the error (see rtError), using MSBASIC's error numbers.
;
strNoSpace:
	mov	al,14			; "Out of string space"
	jmp	short strError
strTooLong:
	mov	al,15			; "String too long"
	jmp	short strError
	DEFLBL	strIllegal,near
	mov	al,5			; "Illegal function call"
strError:
	jmp	rtError

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getByteArg
;
; Inputs:
;	DX:AX = 32-bit value
;
; Outputs:
;	AX = value (if it's not 0-255, an Illegal function call error occurs)
;
; Modifies:
;	AX
;
DEFPROC	getByteArg
	test	dx,dx
	jnz	strIllegal
	cmp	ax,255
	ja	strIllegal
	ret
ENDPROC	getByteArg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getStrLen
;
; Inputs:
;	SS:SI -> string value
;
; Outputs:
;	CX = length of string
;
; Modifies:
;	CX, DI, ES
;
DEFPROC	getStrLen
	les	di,ss:[si]
	sub	cx,cx
	test	di,di
	jz	gsl9
	mov	cl,es:[di]
gsl9:	ret
ENDPROC	getStrLen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getSubStr
;
; Returns the substring of the string value at SS:SI with the given offset
; and length (which must be within the string), releasing the string value
; unless the substring is the entire string.
;
; Inputs:
;	SS:SI -> string value
;	AX = offset of substring (0-based)
;	CX = length of substring
;
; Outputs:
;	DX:AX = substring value
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	getSubStr
	jcxz	gss8			; empty substring
	les	di,ss:[si]
	test	ax,ax			; does it start at the beginning?
	jnz	gss2			; no
	cmp	cl,es:[di]		; and is it the entire string?
	jne	gss2			; no
	xchg	ax,di			; yes, the result is the string itself
	mov	dx,es
	ret
gss2:	push	ax
	call	allocStr		; ES:DI -> new string
	pop	ax
	push	ds
	push	si
	lds	si,ss:[si]		; DS:SI -> string value
	add	si,ax
	inc	si			; DS:SI -> 1st char of substring
	push	di
	mov	cl,es:[di]
	mov	ch,0
	inc	di
	rep	movsb
	pop	di
	pop	si
	pop	ds
	push	es
	push	di
	les	di,ss:[si]
	call	releaseStr
	pop	ax
	pop	dx
	ret
gss8:	les	di,ss:[si]
	call	releaseStr
	sub	ax,ax
	cwd
	ret
ENDPROC	getSubStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; newStr
;
; Allocates a string and copies the characters at SS:SI to it.
;
; Inputs:
;	SS:SI -> characters
;	CX = # of characters (zero for an empty string)
;
; Outputs:
;	DX:AX = string value
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	newStr
	sub	ax,ax
	cwd
	jcxz	ns9
	call	allocStr		; ES:DI -> new string
	push	ds
	push	ss
	pop	ds
	push	di
	inc	di
	rep	movsb
	pop	ax
	mov	dx,es
	pop	ds
ns9:	ret
ENDPROC	newStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; swapVars
;
; Used by "SWAP var1,var2", which exchanges the values of two variables (or
; array elements) of the same type.  A string in the pool records its owner,
; so after swapping strings, we update their owners.
;
; Inputs:
;	far pointer to 1st variable (popped)
;	far pointer to 2nd variable (popped)
;	16-bit type (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	swapVars,FAR
	ARGVAR	pSwapA,dword
	ARGVAR	pSwapB,dword
	ARGVAR	wSwapType,word
	ENTER
	push	ds
	lds	si,[pSwapA]
	les	di,[pSwapB]
	mov	ax,[wSwapType]
	mov	cx,2			; CX = # words for a long or string
	cmp	al,VAR_DOUBLE
	jne	sw1
	add	cx,cx			; or 4 for a double
sw1:	mov	ax,[si]
	xchg	ax,es:[di]
	mov	[si],ax
	inc	si
	inc	si
	inc	di
	inc	di
	loop	sw1
	mov	ax,[wSwapType]
	cmp	al,VAR_STR		; strings?
	jne	sw9			; no
	lds	si,[pSwapA]
	call	swapOwner
	lds	si,[pSwapB]
	call	swapOwner
sw9:	pop	ds
	LEAVE
	RETURN
ENDPROC	swapVars

;
; swapOwner: makes the variable at DS:SI the owner of its pool string, if any.
;
DEFPROC	swapOwner
	les	di,[si]			; ES:DI = string value
	test	di,di			; empty?
	jz	so9			; yes
	cmp	es:[BLK_SIG],SIG_SBLK	; in the pool?
	jne	so9			; no
	cmp	byte ptr es:[di-STR_HDR],STR_OWNED
	jne	so9
	mov	es:[di-STR_HDR+1],si
	mov	es:[di-STR_HDR+3],ds
so9:	ret
ENDPROC	swapOwner

CODE	ENDS

	end
