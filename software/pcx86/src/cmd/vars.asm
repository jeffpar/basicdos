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
	xchg	di,ax
	sub	ax,ax
	stosb				; initialize VAR_ZERO
	stosw
	stosw
	stosb				; set end-of-vars byte
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
;	If carry clear, AL = var type, DX:SI -> var data
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	addVar
	call	findVar
	jnc	av10
	push	di
	push	es
	mov	es,[segVars]
	mov	di,es:[VAR_FREE]
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

av9:	pop	es
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
;	If carry clear, AL = var type, DX:SI -> var data
;	If carry set, AL = VAR_LONG, DX:SI -> zero constant
;
; Modifies:
;	DX, SI
;
DEFPROC	findVar
	push	di
	push	es
	mov	es,[segVars]
	mov	di,size VBLK_HDR

fv1:	mov	al,es:[di]
	inc	di
	test	al,al			; end of variables in the block?
	jnz	fv2			; no
	mov	dx,offset VAR_ZERO
	stc
	jmp	short fv9		; yes

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
	mov	si,dx
	mov	dx,es			; DX:SI -> var data
	mov	al,[si]
	and	al,VAR_TYPE

fv9:	pop	es
	pop	di
	ret
ENDPROC	findVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; letVar32
;
; Inputs:
;	ES:DI -> var data
;	1 pointer to 32-bit value pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	letVar32,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	pop	ax
	stosw
	pop	ax
	stosw
	push	dx			; ie, "JMP DX:CX"
	push	cx
	ret
ENDPROC	letVar32

CODE	ENDS

	end
