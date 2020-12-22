;
; BASIC-DOS Memory Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<get_psp,scb_release>

	EXTBYTE	<scb_locked>
	EXTWORD	<mcb_head,scb_active>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_alloc (REG_AH = 48h)
;
; Inputs:
;	REG_BX = paragraphs requested
;
; Outputs:
;	On success, REG_AX = new segment
;	On failure, REG_AX = error, REG_BX = max paras available
;
DEFPROC	mem_alloc,DOS
	mov	bx,[bp].REG_BX		; BX = # paras requested
	call	mcb_alloc
	jnc	ma9
	mov	[bp].REG_BX,bx
ma9:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
	ret
ENDPROC	mem_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_free (REG_AH = 49h)
;
; Inputs:
;	REG_ES = segment to free
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = ERR_BADMCB or ERR_BADADDR
;
DEFPROC	mem_free,DOS
	mov	ax,[bp].REG_ES		; AX = segment to free
	call	mcb_free
	jnc	mf9
	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY set
mf9:	ret
ENDPROC	mem_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_realloc (REG_AH = 4Ah)
;
; Inputs:
;	REG_ES = segment to realloc
;	REG_BX = new size (in paragraphs)
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error, REG_BX = max paras available
;
; TODO:
;	In some versions of DOS (2.1 and 3.x), this reportedly reallocates the
;	block to the largest available size, even though an error is reported.
;	Do we care to do the same?  I think not.
;
DEFPROC	mem_realloc,DOS
	mov	dx,[bp].REG_ES		; DX = segment to realloc
	mov	bx,[bp].REG_BX		; BX = # new paras requested
	call	mcb_realloc
	jnc	mr9
	mov	[bp].REG_BX,bx
	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY set
mr9:	ret
ENDPROC	mem_realloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_query
;
; This utility function simplifies implementation of the MEM /D command.
;
; TODO: While this is a useful function during development, consider dropping
; it (and the MEM /D command) in the final release.
;
; Inputs:
;	CX = memory block # (0-based)
;	DL = memory block type (0 for any, 1 for free, 2 for used)
;
; Outputs:
;	On success, carry clear:
;		REG_BX = segment
;		REG_AX = owner ID (eg, PSP)
;		REG_DX = size (in paragraphs)
;		REG_DI:REG_SI -> process name, if any
;	On failure, carry set (ie, no more blocks of the requested type)
;
; Modifies:
;	AX, BX, CX, DS, ES
;
DEFPROC	mem_query,DOS
	LOCK_SCB
	mov	bx,[mcb_head]		; BX tracks ES
	mov	es,bx
	ASSUME	ES:NOTHING
q1:	mov	ax,es:[MCB_OWNER]
	test	dl,dl			; report any block?
	jz	q3			; yes
	test	ax,ax			; free block?
	jnz	q2			; no
	cmp	dl,1			; yes, interested?
	je	q3			; yes
	jmp	short q4		; no
q2:	cmp	dl,2			; interested in used blocks?
	jne	q4			; no

q3:	jcxz	q7
	dec	cx
q4:	cmp	es:[MCB_SIG],MCBSIG_LAST
	stc
	je	q9
	add	bx,es:[MCB_PARAS]
	inc	bx
	mov	es,bx
	jmp	q1

q7:	mov	dx,es:[MCB_PARAS]
	cmp	ax,MCBOWNER_SYSTEM
	jbe	q8
	mov	[bp].REG_DI,es
	mov	[bp].REG_SI,MCB_NAME	; DI:SI -> process name (or nulls)

q8:	inc	bx
	mov	[bp].REG_BX,bx
	mov	[bp].REG_AX,ax
	mov	[bp].REG_DX,dx
	clc
q9:	UNLOCK_SCB
	ret
ENDPROC	mem_query

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_init
;
; Inputs:
;	ES:0 -> MCB
;	AL = SIG (ie, MCBSIG_NEXT or MCBSIG_LAST)
;	DX = OWNER (ie, MCBOWNER_NONE, MCBOWNER_SYSTEM, or a PSP segment)
;	CX = PARAS
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	mcb_init,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	sub	di,di
	stosb				; mov es:[MCB_SIG],al
	xchg	ax,dx
	stosw				; mov es:[MCB_OWNER],dx
	xchg	ax,cx
	stosw				; mov es:[MCB_PARAS],cx
	mov	cl,size MCB_RESERVED + size MCB_NAME
	mov	al,0
	rep	stosb
	ret
ENDPROC	mcb_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_setname
;
; Inputs:
;	ES = segment
;
; Outputs:
;	None
;
; Modifies:
;	BX, CX, SI, DI
;
DEFPROC	mcb_setname,DOS
	ASSUME	DS:DOS, ES:NOTHING
	push	es
	mov	di,es
	dec	di
	mov	es,di
	mov	bx,[scb_active]
	lea	si,[bx].SCB_FILENAME + 1
	mov	cx,size MCB_NAME
	mov	di,offset MCB_NAME
	rep	movsb
	pop	es
	ret
ENDPROC	mcb_setname

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_split
;
; Inputs:
;	ES:0 -> MCB
;	AL = SIG for new block
;	BX = new (smaller) size for block
;	CX = original (larger) size of block
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	mcb_split,DOS
	ASSUME	DS:NOTHING
	cmp	bx,cx			; are the sizes identical?
	jne	sp1			; no
	mov	es:[MCB_SIG],al		; yes, no actual split required
	jmp	short sp9
sp1:	push	es
	mov	dx,es
	add	dx,bx
	inc	dx
	mov	es,dx			; ES:0 -> new MCB
	sub	cx,bx			; reduce by # paras requested
	dec	cx			; reduce by 1 for new MCB
	sub	dx,dx			; DX = owner (none)
	call	mcb_init
	pop	es			; ES:0 -> back to found block
	mov	es:[MCB_SIG],MCBSIG_NEXT
sp9:	mov	es:[MCB_PARAS],bx
	ret
ENDPROC	mcb_split

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_alloc
;
; Inputs:
;	BX = paragraphs requested (from REG_BX if via INT 21h)
;
; Outputs:
;	On success, carry clear, AX = new segment
;	On failure, carry set, BX = max paras available
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC mcb_alloc,DOS
	ASSUME	ES:NOTHING
	LOCK_SCB
	mov	es,[mcb_head]
	sub	dx,dx			; DX = largest free block so far
a1:	mov	al,es:[MCB_SIG]
	cmp	al,MCBSIG_NEXT
	je	a2
	cmp	al,MCBSIG_LAST
	jne	a7
a2:	mov	cx,es:[MCB_PARAS]	; CX = # paras this block
	cmp	es:[MCB_OWNER],0	; free block?
	jne	a6			; no
	cmp	cx,bx			; big enough?
	je	a4			; just big enough, use as-is
	ja	a3			; yes
	cmp	dx,cx			; is this largest free block so far?
	jae	a6			; no
	mov	dx,cx			; yes
	jmp	short a6
;
; Split the current block; the new MCB at the split point will
; be marked free, and it will have the same MCB_SIG as the found block.
;
a3:	mov	al,es:[MCB_SIG]		; AL = signature for new block
	call	mcb_split

a4:	call	get_psp
	jnz	a5
	mov	ax,MCBOWNER_SYSTEM	; no active PSP yet, so use this
a5:	mov	es:[MCB_OWNER],ax
	mov	ax,es
	inc	ax			; return ES+1 in AX, with CARRY clear
	clc
	jmp	short a9

a6:	cmp	es:[MCB_SIG],MCBSIG_LAST; last block?
	je	a8			; yes, return error
	mov	ax,es			; advance to the next block
	add	ax,cx
	inc	ax
	mov	es,ax
	jmp	a1

a7:	mov	ax,ERR_BADMCB
	jmp	short a8a

a8:	mov	ax,ERR_NOMEMORY
	mov	bx,dx			; BX = max # paras available
a8a:	stc

a9:	UNLOCK_SCB
	ret
ENDPROC	mcb_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_realloc
;
; Inputs:
;	DX = segment to realloc (from REG_ES if via INT 21h)
;	BX = new size (in paragraphs)
;
; Outputs:
;	On success, carry clear, AX = new segment
;	On failure, carry set, BX = max paras available for segment
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC mcb_realloc,DOS
	ASSUME	ES:NOTHING
	LOCK_SCB
	dec	dx
	mov	es,dx			; ES:0 -> MCB
	mov	cx,es:[MCB_PARAS]	; CX = # paras in block
	cmp	bx,cx			; any change in size?
	je	r9			; no, that's easy

	mov	al,es:[MCB_SIG]
	cmp	al,MCBSIG_LAST		; is this the last block?
	je	r2			; yes
	add	dx,cx
	inc	dx
	mov	ds,dx			; DS:0 -> next MCB
	ASSUME	DS:NOTHING
	mov	al,ds:[MCB_SIG]
	cmp	ds:[MCB_OWNER],0	; is the next MCB free?
	jne	r2			; no
	add	cx,ds:[MCB_PARAS]	; yes, include it
	inc	cx			; CX = maximum # of paras

r2:	cmp	bx,cx			; is requested <= avail?
	ja	r8			; no
	call	mcb_split		; yes, split block into used and free
	jmp	short r9		; return success

r7:	mov	ax,ERR_BADMCB
	jmp	short r8a

r8:	mov	bx,cx			; BX = maximum # of paras available
	mov	ax,ERR_NOMEMORY
r8a:	stc

r9:	UNLOCK_SCB
	ret
ENDPROC	mcb_realloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_free
;
; When freeing a block, it's important to merge it with any free block that
; immediately precedes or follows it.  And since the MCBs are singly-linked,
; we must walk the chain from the head until we find the candidate block.
;
; Inputs:
;	AX = segment to free (from REG_ES if via INT 21h)
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = ERR_BADMCB or ERR_BADADDR
;
; Modifies:
;	AX, BX, CX, DX, ES
;
DEFPROC	mcb_free,DOS
	ASSUME	ES:NOTHING
	LOCK_SCB

	mov	bx,[mcb_head]		; BX tracks ES
	dec	ax			; AX = candidate MCB
	sub	dx,dx			; DX = previous MCB (0 if not free)

f1:	mov	es,bx
	cmp	bx,ax			; does current MCB match candidate?
	jne	f4			; no
;
; If the previous block is free, add this block's paras (+1 for its MCB)
; to the previous block's paras.
;
	test	dx,dx			; is the previous block free?
	jz	f3			; no

f2:	mov	al,es:[MCB_SIG]
	cmp	al,MCBSIG_NEXT
	je	f2a
	cmp	al,MCBSIG_LAST
	jne	f7

f2a:	mov	cx,es:[MCB_PARAS]	; yes, merge current with previous
	inc	cx
	mov	es,dx			; ES:0 -> previous block
	add	es:[MCB_PARAS],cx	; update its number of paras
	mov	es:[MCB_SIG],al		; propagate the signature as well
	mov	bx,dx
	sub	dx,dx
;
; Mark the candidate block free, and if the next block is NOT free, we're done.
;
f3:	mov	es:[MCB_OWNER],dx	; happily, DX is zero
	mov	es:[MCB_NAME],dl
	cmp	es:[MCB_SIG],MCBSIG_LAST; is there a next block?
	je	f9			; no (and carry is clear)
	mov	dx,bx			; yes, save this block as new previous
	add	bx,es:[MCB_PARAS]
	inc	bx
	mov	es,bx			; ES:0 -> next block
	cmp	es:[MCB_OWNER],0	; also free?
	jne	f9			; no, we're done (and carry is clear)
;
; Otherwise, use the same merge logic as before; the only difference now
; is that the candidate block has become the previous block.
;
	jmp	f2

f4:	cmp	es:[MCB_SIG],MCBSIG_LAST; continuing search: last block?
	je	f8			; yes, return error
	sub	dx,dx			; assume block is not free
	cmp	es:[MCB_OWNER],dx	; is it free?
	jne	f5			; no
	mov	dx,bx			; DX = new previous (and free) MCB
f5:	add	bx,es:[MCB_PARAS]
	inc	bx
	jmp	f1			; check the next block

f7:	mov	ax,ERR_BADMCB
	jmp	short f8a

f8:	mov	ax,ERR_BADADDR
f8a:	stc

f9:	UNLOCK_SCB
	ret
ENDPROC	mcb_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_free_all
;
; Used during process termination to free all blocks "owned" by a PSP.
;
; Inputs:
;	AX = owner (PSP)
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = ERR_BADMCB or ERR_BADADDR
;
; Modifies:
;	AX, BX, CX, DX, ES
;
DEFPROC	mcb_free_all,DOS
	ASSUME	ES:NOTHING
	LOCK_SCB
	mov	bx,[mcb_head]

fa1:	mov	es,bx
	cmp	es:[MCB_OWNER],ax	; MCB owned by PSP?
	jne	fa8			; no
	push	ax			; save owner
	mov	ax,es			; AX = MCB
	inc	ax			; AX = segment
	call	mcb_free		; free the segment
	pop	ax			; restore owner
	jc	fa9			; assuming free was successful
	mov	bx,es			; we can pick up where free left off
	jmp	fa1

fa8:	cmp	es:[MCB_SIG],MCBSIG_LAST
	je	fa9
	add	bx,es:[MCB_PARAS]
	inc	bx
	jmp	fa1

fa9:	UNLOCK_SCB
	ret
ENDPROC	mcb_free_all

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_getsize
;
; Returns the size (in paras) of a segment IFF it's a valid memory block.
;
; It's tempting to simply subtract one from the segment and check for an MCB
; signature; however, it's too easy to be spoofed by a bogus signature.  The
; only way to be sure it's valid is by walking the MCB chain.
;
; Inputs:
;	DX = segment
;
; Outputs:
;	On success, carry clear:
;		AX = size of segment, in paragraphs
;		CX = owner (zero if free)
;	On failure, carry set (not a valid memory block)
;
; Modifies:
;	AX, CX
;
DEFPROC	mcb_getsize,DOS
	ASSUME	ES:NOTHING
	LOCK_SCB
	push	bx
	push	es
	mov	bx,[mcb_head]		; BX tracks ES
	dec	dx			; DX = candidate MCB
gs1:	mov	es,bx
	cmp	bx,dx			; does current MCB match candidate?
	je	gs8			; yes
	cmp	es:[MCB_SIG],MCBSIG_LAST; continuing search: last block?
	stc
	je	gs9			; yes, return error
	add	bx,es:[MCB_PARAS]
	inc	bx
	jmp	gs1			; check the next block
gs8:	mov	ax,es:[MCB_PARAS]	; AX = size, in paragraphs
	mov	cx,es:[MCB_OWNER]	; CX = owner (zero if free)
gs9:	inc	dx			; restore DX
	pop	es
	pop	bx
	UNLOCK_SCB
	ret
ENDPROC	mcb_getsize

DOS	ends

	end
