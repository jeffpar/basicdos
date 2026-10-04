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
	include	fpu.inc

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
; callFPUFunc
;
; Calls the FPU$ driver's function at the specified FPUTBL offset, passing
; all other registers through (unlike callFPU, which uses CX).
;
; Inputs:
;	BX = FPUTBL offset (eg, FPU_DTOA)
;	Other registers as required by the function
;
; Outputs:
;	As returned by the function, or carry set if there's no FPUTBL
;
; Modifies:
;	BX, plus whatever the function modifies
;
DEFPROC	callFPUFunc
	cmp	word ptr cs:[FPU_TABLE+2],0
	stc
	je	cff9			; no FPUTBL
	push	ds
	push	si
	lds	si,cs:[FPU_TABLE]
	push	ds
	push	word ptr [si+bx]	; push the FPUTBL function address
	mov	bx,sp
	lds	si,ss:[bx+4]		; restore SI and DS
	call	dword ptr ss:[bx]
	pop	bx			; (POPs don't modify flags)
	pop	bx
	pop	si
	pop	ds
cff9:	ret
ENDPROC	callFPUFunc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strToChar
;
; Converts a string value on the stack to the code of its first character
; (zero if empty), for functions that accept either (eg, STRING$).
;
; Input stack:
;	string value
;
; Output stack:
;	32-bit character code
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	strToChar,FAR
	RETVAR	pStrChr,dword
	ENTER
	les	di,[pStrChr]
	sub	ax,ax
	test	di,di
	jz	stc8
	mov	al,es:[di+1]
	call	releaseStr
stc8:	mov	[pStrChr].LOW,ax
	mov	[pStrChr].HIW,0
	LEAVE
	RETURN
ENDPROC	strToChar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strLen (LEN)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	strLen,FAR
	RETVAR	retLen,dword
	ARGVAR	pLenStr,dword
	ENTER
	lea	si,[pLenStr]
	call	getStrLen
	les	di,[pLenStr]
	call	releaseStr
	mov	[retLen].LOW,cx
	mov	[retLen].HIW,0
	LEAVE
	RETURN
ENDPROC	strLen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strAsc (ASC)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	strAsc,FAR
	RETVAR	retAsc,dword
	ARGVAR	pAscStr,dword
	ENTER
	les	di,[pAscStr]
	test	di,di
	jz	sa9
	mov	al,es:[di+1]
	mov	ah,0
	call	releaseStr
	mov	[retAsc].LOW,ax
	mov	[retAsc].HIW,0
	LEAVE
	RETURN
sa9:	jmp	strIllegal
ENDPROC	strAsc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strChr (CHR$)
;
; Inputs:
;	32-bit return value
;	32-bit character code (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	strChr,FAR
	RETVAR	retChr,dword
	ARGVAR	chrCode,dword
	ENTER
	mov	ax,[chrCode].LOW
	mov	dx,[chrCode].HIW
	call	getByteArg
	xchg	dx,ax			; DL = character code
	mov	cx,1
	call	allocStr
	mov	es:[di+1],dl
	mov	[retChr].OFF,di
	mov	[retChr].SEG,es
	LEAVE
	RETURN
ENDPROC	strChr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strLeft (LEFT$)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;	32-bit length (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strLeft,FAR
	RETVAR	retLeft,dword
	ARGVAR	pLeftStr,dword
	ARGVAR	leftLen,dword
	ENTER
	mov	ax,[leftLen].LOW
	mov	dx,[leftLen].HIW
	call	getByteArg		; AX = requested length
	lea	si,[pLeftStr]
	call	getStrLen		; CX = string length
	cmp	cx,ax
	jb	sl1
	xchg	cx,ax			; CX = substring length
sl1:	sub	ax,ax			; AX = substring offset
	call	getSubStr
	mov	[retLeft].OFF,ax
	mov	[retLeft].SEG,dx
	LEAVE
	RETURN
ENDPROC	strLeft

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strRight (RIGHT$)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;	32-bit length (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strRight,FAR
	RETVAR	retRight,dword
	ARGVAR	pRightStr,dword
	ARGVAR	rightLen,dword
	ENTER
	mov	ax,[rightLen].LOW
	mov	dx,[rightLen].HIW
	call	getByteArg		; AX = requested length
	lea	si,[pRightStr]
	call	getStrLen		; CX = string length
	cmp	ax,cx
	jb	sr1
	mov	ax,cx
sr1:	sub	cx,ax			; CX = substring offset
	xchg	cx,ax			; AX = offset, CX = length
	call	getSubStr
	mov	[retRight].OFF,ax
	mov	[retRight].SEG,dx
	LEAVE
	RETURN
ENDPROC	strRight

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strMid (MID$)
;
; The length is optional; PARM_OPT_REST (ie, -2) means the rest of the string.
;
; Inputs:
;	32-bit return value
;	string value (popped)
;	32-bit position (1-based, popped)
;	32-bit length (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strMid,FAR
	RETVAR	retMid,dword
	ARGVAR	pMidStr,dword
	ARGVAR	midPos,dword
	ARGVAR	midLen,dword
	ENTER
	mov	ax,[midPos].LOW
	mov	dx,[midPos].HIW
	call	getByteArg
	dec	ax			; AX = offset
	jl	sm9			; position must be 1 or more
	xchg	bx,ax			; BX = offset
	mov	ax,[midLen].LOW
	mov	dx,[midLen].HIW
	cmp	ax,-2			; PARM_OPT_REST (sign-extended)?
	jne	sm1
	cmp	dx,-1
	jne	sm1
	mov	ax,255			; use the rest of the string
	sub	dx,dx
sm1:	call	getByteArg		; AX = requested length
	lea	si,[pMidStr]
	call	getStrLen		; CX = string length
	sub	cx,bx			; CX = # chars from offset to end
	ja	sm2
	sub	cx,cx			; offset is past the end
sm2:	cmp	cx,ax
	jb	sm3
	xchg	cx,ax			; CX = substring length
sm3:	xchg	ax,bx			; AX = offset
	call	getSubStr
	mov	[retMid].OFF,ax
	mov	[retMid].SEG,dx
	LEAVE
	RETURN
sm9:	jmp	strIllegal
ENDPROC	strMid

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strInstr (INSTR)
;
; Returns the position (1-based) of string B in string A, starting at the
; given position, or zero if not found.  Like MSBASIC, if B is empty, the
; result is the starting position (unless A is empty or the starting position
; is past the end of A).
;
; Inputs:
;	32-bit return value
;	32-bit starting position (popped)
;	string value A (popped)
;	string value B (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strInstr,FAR
	RETVAR	retInstr,dword
	ARGVAR	instrPos,dword
	ARGVAR	pInstrA,dword
	ARGVAR	pInstrB,dword
	ENTER
	push	ds
	mov	ax,[instrPos].LOW
	mov	dx,[instrPos].HIW
	call	getByteArg
	dec	ax			; AX = offset
	jl	si10			; position must be 1 or more
	xchg	bx,ax			; BX = offset
	lea	si,[pInstrB]
	call	getStrLen
	mov	dx,cx			; DX = length of B
	lea	si,[pInstrA]
	call	getStrLen		; CX = length of A
	sub	ax,ax			; AX = result (zero)
	cmp	bx,cx			; offset within A?
	jae	si8			; no
	inc	bx			; BX = position
	test	dx,dx			; is B empty?
	jz	si7			; yes, result is the position
	dec	bx			; BX = offset
	sub	cx,bx			; CX = # chars from offset to end
	sub	cx,dx			; CX = # positions to try - 1
	jb	si8			; B is longer than the rest of A
	inc	cx
	lds	si,[pInstrA]
	lea	si,[si+bx+1]		; DS:SI -> 1st char to try
	les	di,[pInstrB]
	inc	di			; ES:DI -> 1st char of B
si1:	push	cx
	push	si
	push	di
	mov	cx,dx
	repe	cmpsb
	pop	di
	pop	si
	pop	cx
	je	si6			; match
	inc	si
	inc	bx
	loop	si1
	jmp	short si8		; no match
si6:	inc	bx			; BX = position
si7:	xchg	ax,bx			; AX = result
si8:	push	ax
	les	di,[pInstrA]
	call	releaseStr
	les	di,[pInstrB]
	call	releaseStr
	pop	ax
	mov	[retInstr].LOW,ax
	mov	[retInstr].HIW,0
	pop	ds
	LEAVE
	RETURN
si10:	jmp	strIllegal
ENDPROC	strInstr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strStr (STR$)
;
; Inputs:
;	32-bit return value
;	pointer to double (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strStr,FAR
	RETVAR	retStr,dword
	ARGVAR	pStrNum,dword
	LOCVAR	strBuf,byte,32
	ENTER
	push	ds
	push	ss
	pop	es
;
; If the double is an integer that fits in 32 bits (eg, STR$(I)), we format
; it with ITOA, which is much faster than FPU_DTOA.  Such a double is zero or
; has an exponent from 0 to 30, and no fraction bits are shifted out when its
; mantissa is shifted right by 52-exponent.
;
	lds	si,[pStrNum]		; DS:SI -> double
	mov	dx,[si+6]
	mov	ax,dx
	add	ax,ax			; AX = double without its sign
	or	ax,[si+4]
	or	ax,[si+2]
	or	ax,[si]
	mov	bx,ax			; BX:AX = zero if the double is zero
	jz	sst4
	mov	ax,dx
	and	ax,7FF0h
	mov	cl,4
	shr	ax,cl			; AX = biased exponent
	neg	ax
	add	ax,1075			; AX = # bits to shift (52-exponent)
	cmp	ax,22
	jb	sst8			; too large
	cmp	ax,52
	ja	sst8			; too small
	xchg	di,ax
	mov	ax,[si]
	mov	bx,[si+2]
	mov	cx,[si+4]
	and	dx,000Fh
	or	dl,10h			; DX:CX:BX:AX = mantissa
	sub	si,si			; SI = fraction bits
sst2:	shr	dx,1
	rcr	cx,1
	rcr	bx,1
	rcr	ax,1
	adc	si,0
	dec	di
	jnz	sst2
	test	si,si			; any fraction bits?
	jnz	sst8			; yes
	lds	si,[pStrNum]
	test	byte ptr [si+7],80h
	jz	sst4
	neg	bx
	neg	ax
	sbb	bx,0			; BX:AX = negative value
sst4:	xchg	si,ax
	mov	dx,bx			; DX:SI = value
	lea	di,[strBuf]		; ES:DI -> buffer
	mov	bx,((PF_LONG OR PF_SIGN OR PF_HASH) SHL 8) OR 10
	sub	cx,cx
	DOSUTIL	ITOA			; AX = # of characters
	xchg	cx,ax
	jmp	short sst9

sst8:	lds	si,[pStrNum]		; DS:SI -> double
	lea	di,[strBuf]		; ES:DI -> buffer
	mov	cx,32			; CX = size of buffer
	sub	dx,dx			; DX = width (none)
	mov	ax,(PF_HASH SHL 8) OR 0FFh
	mov	bx,FPU_DTOA		; AL = precision (none)
	call	callFPUFunc		; AH = flags (PF_HASH)
	lea	cx,[strBuf]
	sub	di,cx			; DI = # chars
	xchg	cx,di
sst9:	lea	si,[strBuf]
	call	newStr
	mov	[retStr].OFF,ax
	mov	[retStr].SEG,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	strStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strVal (VAL)
;
; Like MSBASIC, blanks (spaces, tabs, and linefeeds) are ignored, and if the
; string doesn't begin with a number, the result is zero.
;
; Inputs:
;	pointer to double result (in a slot)
;	string value (popped)
;
; Outputs:
;	double result updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strVal,FAR
	RETVAR	pValNum,dword
	ARGVAR	pValStr,dword
	LOCVAR	valBuf,byte,256
	ENTER
	push	ds
	push	ss
	pop	es
	lea	di,[valBuf]		; ES:DI -> buffer
	lds	si,[pValStr]
	sub	cx,cx
	test	si,si
	jz	sv3
	lodsb
	mov	cl,al
sv1:	lodsb
	cmp	al,' '
	je	sv2
	cmp	al,CHR_TAB
	je	sv2
	cmp	al,CHR_LINEFEED
	je	sv2
	stosb
sv2:	loop	sv1
sv3:	mov	al,0
	stosb				; null-terminate the buffer
	les	di,[pValStr]
	call	releaseStr
	push	ss
	pop	ds
	lea	si,[valBuf]		; DS:SI -> buffer
	les	di,[pValNum]		; ES:DI -> result
	mov	bx,FPU_ATOD
	call	callFPUFunc
	jnc	sv9
	les	di,[pValNum]		; no number, so the result is zero
	sub	ax,ax
	mov	cx,4
	rep	stosw
sv9:	pop	ds
	LEAVE
	RETURN
ENDPROC	strVal

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strSpace (SPACE$)
;
; Inputs:
;	32-bit return value
;	32-bit length (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	strSpace,FAR
	RETVAR	retSpace,dword
	ARGVAR	spaceLen,dword
	ENTER
	mov	bl,' '
	mov	ax,[spaceLen].LOW
	mov	dx,[spaceLen].HIW
	call	fillStr
	mov	[retSpace].OFF,ax
	mov	[retSpace].SEG,dx
	LEAVE
	RETURN
ENDPROC	strSpace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strString (STRING$)
;
; Inputs:
;	32-bit return value
;	32-bit length (popped)
;	32-bit character code (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	strString,FAR
	RETVAR	retString,dword
	ARGVAR	stringLen,dword
	ARGVAR	stringChr,dword
	ENTER
	mov	ax,[stringChr].LOW
	mov	dx,[stringChr].HIW
	call	getByteArg
	xchg	bx,ax			; BL = character code
	mov	ax,[stringLen].LOW
	mov	dx,[stringLen].HIW
	call	fillStr
	mov	[retString].OFF,ax
	mov	[retString].SEG,dx
	LEAVE
	RETURN
ENDPROC	strString

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fillStr
;
; Inputs:
;	DX:AX = length
;	BL = character
;
; Outputs:
;	DX:AX = new string value, filled with the character
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	fillStr
	call	getByteArg
	xchg	cx,ax			; CX = length
	sub	ax,ax
	cwd
	jcxz	fl9
	call	allocStr		; ES:DI -> new string
	push	di
	inc	di
	mov	al,bl
	rep	stosb
	pop	ax
	mov	dx,es
fl9:	ret
ENDPROC	fillStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strHex (HEX$) and strOct (OCT$)
;
; Negative values are treated as unsigned 32-bit values (eg, HEX$(-1) is
; "FFFFFFFF").
;
; Inputs:
;	32-bit return value
;	32-bit value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strHex,FAR
	mov	bl,16
	DEFLBL	strBase,near
	RETVAR	retBase,dword
	ARGVAR	baseNum,dword
	LOCVAR	baseBuf,byte,12
	ENTER
	mov	si,[baseNum].LOW
	mov	dx,[baseNum].HIW	; DX:SI = value
	mov	bh,PF_LONG
	sub	cx,cx
	push	ss
	pop	es
	lea	di,[baseBuf]
	push	di
	DOSUTIL	ITOA			; AL = # of digits
	pop	si
	mov	cl,al
	mov	ch,0
	call	newStr
	mov	[retBase].OFF,ax
	mov	[retBase].SEG,dx
	LEAVE
	RETURN
ENDPROC	strHex

DEFPROC	strOct,FAR
	mov	bl,8
	jmp	strBase
ENDPROC	strOct

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strUCase (UCASE$) and strLCase (LCASE$)
;
; Inputs:
;	32-bit return value
;	string value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strUCase,FAR
	mov	bx,('z' SHL 8) OR 'a'	; BL = 'a', BH = 'z'
	DEFLBL	strCase,near
	RETVAR	retCase,dword
	ARGVAR	pCaseStr,dword
	ENTER
	push	ds
	lea	si,[pCaseStr]
	call	getStrLen		; CX = length, ES:DI = string
	jcxz	sc9
	call	isTempStr		; can we modify the string in place?
	je	sc1			; yes
	push	bx
	call	allocStr		; ES:DI -> new string
	pop	bx
	lds	si,[pCaseStr]
	push	di
	movsb
	mov	cl,es:[di-1]
	rep	movsb			; copy the string
	pop	di
	mov	[pCaseStr].OFF,di	; and use the copy instead
	mov	[pCaseStr].SEG,es
sc1:	push	di
	mov	cl,es:[di]
	inc	di
sc2:	mov	al,es:[di]
	cmp	al,bl
	jb	sc3
	cmp	al,bh
	ja	sc3
	xor	al,20h			; flip the case
	mov	es:[di],al
sc3:	inc	di
	loop	sc2
	pop	di
sc9:	mov	ax,[pCaseStr].OFF
	mov	[retCase].OFF,ax
	mov	ax,[pCaseStr].SEG
	mov	[retCase].SEG,ax
	pop	ds
	LEAVE
	RETURN
ENDPROC	strUCase

DEFPROC	strLCase,FAR
	mov	bx,('Z' SHL 8) OR 'A'	; BL = 'A', BH = 'Z'
	jmp	strCase
ENDPROC	strLCase

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strInkey (INKEY$)
;
; Returns the next key (if any) without waiting; extended keys (eg, cursor
; keys) are returned as two characters: a null and the scan code.
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	strInkey,FAR
	RETVAR	retInkey,dword
	LOCVAR	keyBuf,word
	ENTER
	sub	cx,cx
	mov	dl,0FFh
	mov	ah,DOS_TTY_IO
	int	21h			; ZF set if no key
	jz	sk8
	inc	cx
	mov	byte ptr [keyBuf],al
	test	al,al			; extended key?
	jnz	sk8			; no
	mov	ah,DOS_TTY_IO
	int	21h
	mov	byte ptr [keyBuf+1],al	; scan code
	inc	cx
sk8:	lea	si,[keyBuf]
	call	newStr
	mov	[retInkey].OFF,ax
	mov	[retInkey].SEG,dx
	LEAVE
	RETURN
ENDPROC	strInkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strDate (DATE$) and strTime (TIME$)
;
; Returns the date as "MM-DD-YYYY" or the time as "HH:MM:SS".
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strDate,FAR
	RETVAR	retDate,dword
	LOCVAR	dateBuf,byte,10
	ENTER
	push	ss
	pop	es
	lea	di,[dateBuf]
	mov	ah,DOS_MSC_GETDATE
	int	21h			; CX = year, DH = month, DL = day
	mov	bx,'--'
	mov	al,dh
	call	putDigits		; "MM-"
	mov	al,dl
	call	putDigits		; "DD-"
	xchg	ax,cx
	mov	cl,100
	div	cl			; AL = century, AH = year
	push	ax
	call	put2Digits		; "YY"
	pop	ax
	mov	al,ah
	call	put2Digits		; "YY"
	mov	cx,10
	jmp	short strDT
ENDPROC	strDate

DEFPROC	strTime,FAR
	RETVAR	retTime,dword
	LOCVAR	timeBuf,byte,10
	ENTER
	push	ss
	pop	es
	lea	di,[timeBuf]
	mov	ah,DOS_MSC_GETTIME
	int	21h			; CH = hour, CL = min, DH = sec
	mov	bx,'::'
	mov	al,ch
	call	putDigits		; "HH:"
	mov	al,cl
	call	putDigits		; "MM:"
	mov	al,dh
	call	put2Digits		; "SS"
	mov	cx,8
	DEFLBL	strDT,near
	lea	si,[timeBuf]
	call	newStr
	mov	[retTime].OFF,ax
	mov	[retTime].SEG,dx
	LEAVE
	RETURN
ENDPROC	strTime

;
; putDigits stores AL as two decimal digits at ES:DI, followed by BL.
;
DEFPROC	putDigits
	call	put2Digits
	mov	al,bl
	stosb
	ret
ENDPROC	putDigits

DEFPROC	put2Digits
	aam				; AH = tens, AL = ones
	xchg	al,ah
	add	ax,'00'
	stosw
	ret
ENDPROC	put2Digits

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strFre (FRE)
;
; Compacts the string pool and then returns the amount of free memory, in
; bytes.  The argument is ignored.
;
; Inputs:
;	32-bit return value
;	32-bit value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strFre,FAR
	RETVAR	retFre,dword
	ARGVAR	freArg,dword
	ENTER
	push	ds
	call	compactStrs
	sub	cx,cx			; CX = memory block #
	sub	si,si			; SI = free paragraphs
fr1:	mov	dl,1			; DL = 1 (free blocks only)
	DOSUTIL	QRYMEM
	jc	fr8
	add	si,dx
	inc	cx
	jmp	fr1
fr8:	xchg	ax,si
	mov	cx,16
	mul	cx			; DX:AX = free bytes
	mov	[retFre].LOW,ax
	mov	[retFre].HIW,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	strFre

CODE	ENDS

	end
