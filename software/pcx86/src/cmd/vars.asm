;
; BASIC-DOS Variable Management
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTERNS	<segVars>,word

        ASSUME  CS:CODE, DS:CODE, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; allocVars
;
; Allocates segVars if not already allocated.
;
; Inputs:
;	None
;
; Outputs:
;	If carry clear, segVars allocated; otherwise, carry set
;
; Modifies:
;	AX
;
DEFPROC	allocVars
	mov	ax,[segVars]
	test	ax,ax
	jnz	al9
	push	bx
	mov	bx,VBLKLEN SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	21h
	pop	bx
	jc	al9
	push	di
	push	es
	mov	[segVars],ax
	mov	es,ax
	sub	di,di
	sub	ax,ax
	stosw				; set VAR_NEXT
	mov	ax,VBLKLEN
	stosw				; set VAR_SIZE
	mov	ax,size VBLK_HDR
	stosw				; set VAR_FREE
	mov	ax,VAR_LONG SHL 8
	IFDEF DEBUG
	mov	al,VARSIG 
	ENDIF
	stosw				; initialize VAR_RESERVED/VAR_ZERO
	sub	ax,ax
	stosw
	stosw
	stosb				; set end-of-vars byte (zero)
	pop	es
	pop	di
al9:	ret
ENDPROC	allocVars

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addVar
;
; Variables start with a byte length (the length of the name), followed by
; the name of the variable, followed by the variable data.  The name length
; is limited to MAX_VARNAME.
;
; Note that, except for numbers (integers and floating point values), the
; variable data is generally a far pointer to the actual data; for example, a
; string variable is just a far pointer to a location inside a string pool.
;
; Inputs:
;	AL = VAR_*
;	CX = length of name
;	DS:SI -> variable name
;
; Outputs:
;	If carry clear, AH = var type, DX -> var data
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	addVar
	call	findVar
	jnc	av10
	push	di
	push	es
	mov	es,[segVars]
	ASSERT	STRUCT,es:[0],VAR
	mov	di,es:[VAR_FREE]
	push	ax

	cmp	cx,MAX_VARNAME
	jbe	av0
	mov	cx,MAX_VARNAME
av0:	push	di
	add	di,cx
	mov	dl,2			; minimum associated data size
	cmp	al,VAR_INT
	jbe	av1
	mov	dl,4
	cmp	al,VAR_DOUBLE
	jb	av1
	mov	dl,8
av1:	mov	dh,0
	add	di,dx
	inc	di			; one for the length byte
	cmp	es:[VAR_SIZE],di	; enough room?
	pop	di
	jb	av9			; no (carry set)
;
; Build the new variable at ES:DI, with combined length and type in the
; first byte, the variable name in the following bytes, and zero-initialized
; data in the remaining bytes.
;
	mov	ah,al			; AH = var type
	or	al,cl
	stosb
av2:	lodsb				; rep movsb would be nice here
	cmp	al,'a'			; but we upper-case the var name now
	jb	av3
	sub	al,20h
av3:	stosb
	loop	av2
	mov	cl,dl
	mov	al,0
	mov	dx,di			; DX = offset of variable's data
	rep	stosb
	mov	es:[VAR_FREE],di
	cmp	es:[VAR_SIZE],di
	ASSERT	AE
	je	av8
	stosb				; ensure there's always a zero after
av8:	jmp	retVar

av9:	pop	ax
	pop	es
	pop	di
av10:	ret
ENDPROC	addVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findVar
;
; Inputs:
;	CX = length of name
;	DS:SI -> variable name
;
; Outputs:
;	If carry clear, AH = var type, DX -> var data
;	If carry set, AH = VAR_LONG, DX -> zero constant
;
; Modifies:
;	AH, DX
;
DEFPROC	findVar
	push	di
	push	es
	mov	es,[segVars]
	ASSERT	STRUCT,es:[0],VAR
	mov	di,size VBLK_HDR	; ES:DI -> first var in block
	push	ax

fv1:	mov	al,es:[di]
	inc	di
	test	al,al			; end of variables in the block?
	jnz	fv2			; no
	stc
	mov	ah,VAR_LONG
	mov	dx,offset VAR_ZERO + 1
	jmp	short retVar		; yes

fv2:	mov	ah,al
	and	al,MAX_VARNAME
	cmp	al,cl			; do the name lengths match?
	jne	fv6			; no

	push	ax
	push	cx
	push	si
	push	di
fv3:	lodsb				; rep cmpsb would be nice here
	cmp	al,'a'			; especially since it doesn't use AL
	jb	fv4			; but tokens are not upper-cased first
	sub	al,20h
fv4:	scasb
	jne	fv5
	loop	fv3
	mov	dx,di			; DX -> variable data
fv5:	pop	di
	pop	si
	pop	cx
	pop	ax
	je	retVar			; match!

fv6:	add	al,2			; add at least 2 bytes for data
	cmp	ah,VAR_INT		; just an INT?
	jbe	fv7			; yes, good enough
	add	al,2			; add 2 more data bytes
	cmp	ah,VAR_DOUBLE		; good enough?
	jb	fv7			; yes
	add	al,4			; no, add 4 more (for a total of 8)
fv7:	cbw
	add	di,ax			; bump to next variable
	jmp	fv1			; keep looking

	DEFLBL	retVar,near
	mov	di,dx
	pop	dx
	mov	al,dl			; AH = var type (AL unchanged)
	mov	dx,di			; DX -> var data

fv9:	pop	es
	pop	di
	ret
ENDPROC	findVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setVarLong
;
; Stack on input:
;	pointer to var data
;	32-bit value
;
; Stack on output:
;	None
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	setVarLong,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	pop	ax
	pop	bx			; BX:AX = 32-bit value
	pop	di
	pop	es			; ES:DI -> var data
	stosw
	xchg	ax,bx
	stosw
	push	dx			; ie, "JMP DX:CX"
	push	cx
	ret
ENDPROC	setVarLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; appendVarStr
;
; This is the first function that must consider how the string pool will work.
;
; The pool will consist of zero or more blocks, each block will contain zero
; or more strings, and each string will consist of:
;
;	length byte (1-255)
;	# of bytes
;
; We can reserve length zero by saying that all empty strings must have a null
; pointer.  This means that length bytes of zero can be used to indicate
; unused pool space; the next byte must be the number of unused bytes.
;
; This simplistic model makes it easy to append to a string if it's followed
; by enough unused bytes.
;
; Inputs:
;	2 pointers to strings pushed on stack (target followed by source)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	appendVarStr,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	pop	si
	pop	ax
	pop	di
	pop	es
	push	es
	push	di
	push	dx
	push	cx

	push	ds
	mov	ds,ax			; DS:SI -> string to append
	push	di
	push	es
;
; If the target string doesn't exist, it can simply "inherit" the source.
;
	les	di,es:[di]		; ES:DI -> target string
	test	di,di
	jnz	avs1
	pop	es
	pop	di
	mov	es:[di].OFF,si
	mov	es:[di].SEG,ds
	jmp	avs9
;
; Get length of target string at ES:DI into CL, and verify that the new
; string will still be within limits.
;
avs1:	mov	cl,es:[di]
	mov	al,[si]
	add	cl,al
	jc	avs8			; resulting string would be too big
;
; Check the target string to see if there's any (and enough) space after it.
;
	mov	ah,0
	inc	ax
	add	si,ax
	;...

avs8:	pop	es			; recover address of target string ptr
	pop	di

avs9:	pop	ds
	ret
ENDPROC	appendVarStr

CODE	ENDS

	end
