;
; BASIC-DOS Memory Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<MCB_HEAD,PSP_ACTIVE>,word

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_alloc (REG_AH = 48h)
;
; Inputs:
;	REG_BX = paragraphs requested
;
; Outputs:
;	On success, REG_AX = new segment
;	On failure, REG_AX = ERR_NOMEM, REG_BX = max paras available
;
DEFPROC	mcb_alloc,DOS
	mov	bx,[bp].REG_BX		; BX = # paras requested
	call	alloc
	jnc	mca9
	mov	[bp].REG_BX,bx
mca9:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
	ret
ENDPROC	mcb_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_free (REG_AH = 49h)
;
; Inputs:
;	REG_ES = segment to free
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = ERR_BADMCD or ERR_BADADDR
;
DEFPROC	mcb_free,DOS
	mov	ax,[bp].REG_ES		; AX = segment to free
	call	free
	jnc	mcf9
	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY set
mcf9:	ret
ENDPROC	mcb_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; initmcb
;
; Inputs:
;	ES:0 -> MCB
;	AL = SIG (eg, MCB_NORMAL)
;	DX = OWNER (eg, 0 or PSP_ACTIVE)
;	CX = PARAS
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	initmcb,DOS
	sub	di,di
	stosb				; mov es:[MCB_SIG],al
	xchg	ax,dx
	stosw				; mov es:[MCB_OWNER],dx
	xchg	ax,cx
	stosw				; mov es:[MCB_PARAS],cx
	mov	cl,size MCB_RESERVED
	mov	al,0
	rep	stosb
	ret
ENDPROC	initmcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; alloc
;
; Inputs:
;	BX = paragraphs requested (from REG_BX if via INT 21h)
;
; Outputs:
;	On success, AX = new segment, carry clear
;	On failure, BX = max paras available, carry set
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC alloc,DOS
	mov	es,[MCB_HEAD]

ma1:	mov	ax,es:[MCB_PARAS]	; AX = # paras this block
	cmp	es:[MCB_OWNER],0	; free block?
	jne	ma5			; no
	cmp	ax,bx			; big enough?
	je	ma4			; just big enough, use as-is
	jb	ma5			; no
;
; Split the current block; the new MCB at the split point will
; be marked free, and it will have the same MCB_SIG as the found block.
;
	xchg	cx,ax			; CX = # paras in found block
	mov	al,es:[MCB_SIG]		; AL = signature for new block
	push	es
	mov	dx,es
	add	dx,bx
	inc	dx
	mov	es,dx			; ES:0 -> new MCB
	sub	cx,bx			; reduce by # paras requested
	dec	cx			; reduce by 1 for new MCB
	sub	dx,dx			; no owner
	call	initmcb
	pop	es			; ES:0 -> back to found block
	mov	es:[MCB_SIG],MCB_NORMAL
	mov	es:[MCB_PARAS],bx
ma4:	mov	ax,[PSP_ACTIVE]
	mov	es:[MCB_OWNER],ax
	mov	ax,es
	inc	ax			; return ES+1 in AX, with CARRY clear
	clc
	jmp	short ma9

ma5:	cmp	es:[MCB_SIG],MCB_LAST	; last block?
	je	ma8			; yes, return error

	mov	dx,es			; advance to the next block
	add	dx,ax
	inc	dx
	mov	es,dx
	jmp	ma1

ma8:	mov	ax,ERR_NOMEM
	stc
ma9:	ret
ENDPROC	alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; free
;
; Inputs:
;	AX = segment to free (from REG_ES if via INT 21h)
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = ERR_BADMCB or ERR_BADADDR
;
; Modifies:
;	AX, BX, DX, ES
;
DEFPROC	free,DOS
;
; Freeing a block requires that we merge it with any free block that
; immediately precedes or follows it (well, "require" is a strong word; it's
; only required if we want alloc to work better).  And since the MCBs are
; singly-linked (and there again, "linked" is a rather strong word), we must
; walk the chain from the head until we find the candidate block.
;
	dec	ax			; AX = candidate MCB
	sub	dx,dx			; DX = previous MCB (0 if not free)
	mov	bx,[MCB_HEAD]		; BX tracks ES

mf1:	mov	es,bx
	cmp	bx,ax			; does current MCB match candidate?
	jne	mf6			; no
;
; If the previous block is free, add this block's paras (+1 for its MCB)
; to the previous block's paras.
;
	test	dx,dx			; is the previous block free?
	jz	mf3			; no

mf2:	mov	al,es:[MCB_SIG]
	mov	cx,es:[MCB_PARAS]	; yes, merge current with previous
	inc	cx
	mov	es,dx			; ES:0 -> previous block
	add	es:[MCB_PARAS],cx	; update its number of paras
	mov	es:[MCB_SIG],al		; propagate the signature as well
	mov	bx,dx
	sub	dx,dx
;
; Mark the candidate block free, and if the next block is NOT free, we're done.
;
mf3:	mov	es:[MCB_OWNER],dx	; happily, DX is zero
	cmp	es:[MCB_SIG],MCB_LAST	; is there a next block?
	je	mf9			; no (and carry is clear)
	mov	dx,bx			; yes, save this block as new previous
	add	bx,es:[MCB_PARAS]
	inc	bx
	mov	es,bx			; ES:0 -> next block
	cmp	es:[MCB_OWNER],0	; also free?
	jne	mf9			; no, we're done (and carry is clear)
;
; Otherwise, use the same merge logic as before; the only difference now
; is that the candidate block has become the previous block.
;
	jmp	mf2

mf6:	cmp	es:[MCB_SIG],MCB_LAST	; continuing search: last block?
	je	mf8			; yes, return error
	sub	dx,dx			; assume block is not free
	cmp	es:[MCB_OWNER],dx	; is it free?
	jne	mf7			; no
	mov	dx,bx			; DX = new previous (and free) MCB
mf7:	add	bx,es:[MCB_PARAS]
	inc	bx
	jmp	mf1			; check the next block

mf8:	mov	ax,ERR_BADADDR
	stc
mf9:	ret
ENDPROC	free

DOS	ends

	end
