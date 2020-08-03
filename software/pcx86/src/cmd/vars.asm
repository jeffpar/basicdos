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
	mov	es:[VAR_SIZE],VBLKLEN
	mov	di,size VBLK_HDR
	mov	es:[VAR_NEXT],di
	mov	al,0
	stosb
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
; is limited to MAX_VARLEN.
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
;	If carry clear, DX = offset of var data
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
	mov	di,es:[VAR_NEXT]
	cmp	cx,MAX_VARLEN
	jbe	av0
	mov	cx,MAX_VARLEN
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
av2:	rep	movsb
	mov	cl,dl
	mov	al,0
	mov	dx,di			; DX = offset of variable's data
	rep	stosb
	mov	es:[VAR_NEXT],di
	cmp	es:[VAR_SIZE],di
	ASSERT	AE
	je	av9
	stosb				; ensure there's always a zero after
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
;	If carry clear, DX = offset of var data
;
; Modifies:
;	DX
;
DEFPROC	findVar
	push	ax
	push	di
	push	es
	mov	es,[segVars]
	mov	di,size VBLK_HDR

fv1:	mov	al,es:[di]
	inc	di
	test	al,al			; end of variables in the block?
	stc
	jz	fv9			; yes
	mov	ah,al
	and	al,MAX_VARLEN
	cmp	al,cl			; do the name lengths match?
	jne	fv7			; no

	push	cx
	push	si
	push	di
	rep	cmpsb
	mov	dx,di			; DX -> variable data (potentially)
	pop	di
	pop	si
	pop	cx
	je	fv9			; match!

fv7:	add	al,2			; add at least 2 bytes for data
	cmp	ah,VAR_INT		; just an INT?
	jbe	fv8			; yes, good enough
	add	al,2			; add 2 more data bytes
	cmp	ah,VAR_DOUBLE		; good enough?
	jb	fv8			; yes
	add	al,4			; no, add 4 more (for a total of 8)
fv8:	cbw
	add	di,ax			; bump to next variable
	jmp	fv1			; keep looking

fv9:	pop	es
	pop	di
	pop	ax
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
;	AX, CX, DX, DI, ES
;
DEFPROC	letVar32,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	pop	si
	pop	ds			; DS:SI -> 32-bit value
	movsw
	movsw
	push	dx			; ie, "JMP DX:CX"
	push	cx
	ret
ENDPROC	letVar32

CODE	ENDS

	end
