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

	extrn	MCB_HEAD:word
	extrn	PSP_ACTIVE:word

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_alloc (REG_AH = 48h)
;
; Inputs:
;	REG_BX = paragraphs requested
;
; Outputs:
;	On success, REG_AX = new segment
;	On failure, REG_AX = ERR_MEMORY, REG_BX = max paras available
;
	ASSUME	CS:DOS, DS:DOS, ES:NOTHING, SS:NOTHING

	public	mem_alloc
mem_alloc proc	near
	int 3
	mov	bx,[bp].REG_BX		; BX = # paras requested
	call	malloc
	jnc	ma9
	mov	[bp].REG_BX,bx
ma9:	mov	[bp].REG_AX,ax		; return REG_AX plus whatever CARRY is
	ret
mem_alloc endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; initmcb
;
; Inputs:
;	ES:DI -> MCB_HDR
;	AL = SIG (eg, MCB_NORMAL)
;	DX = OWNER (eg, 0 or PSP_ACTIVE)
;	CX = PARAS
;
; Modifies:
;	AX, CX, DX, DI
;
	public	initmcb
initmcb	proc	near
	stosb				; mov es:[MCB_SIG],al
	xchg	ax,dx
	stosw				; mov es:[MCB_OWNER],dx
	xchg	ax,cx
	stosw				; mov es:[MCB_PARAS],cx
	mov	cl,size MCB_RESERVED
	mov	al,0
	rep	stosb
	ret
initmcb endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; malloc
;
; Inputs:
;	BX = paragraphs requested
;
; Outputs:
;	On success, AX = new segment, carry clear
;	On failure, BX = max paras available, carry set
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
	ASSUME	CS:DOS, DS:DOS, ES:NOTHING, SS:NOTHING

	public	malloc
malloc	proc	near
	int 3
	mov	es,[MCB_HEAD]

m1:	cmp	es:[MCB_OWNER],0	; free block?
	jne	m7			; no
	mov	ax,es:[MCB_PARAS]	; AX = # paras this block
	cmp	ax,bx			; big enough?
	jb	m7			; no
;
; Split the current block; the new MCB_HDR at the split point will
; be marked free, and it will have the same MCB_SIG as the found block.
;
	mov	al,es:[MCB_SIG]
	push	es
	mov	dx,es
	inc	dx
	add	dx,bx
	mov	es,dx			; ES:[0] is new MCB_HDR
	mov	cx,ax			; CX = # paras in found block
	sub	cx,bx			; reduce by # paras requested
	dec	cx			; reduce by 1 for new MCB_HDR
	sub	dx,dx
	call	initmcb
	pop	es			; ES:[0] back to found block
	mov	es:[MCB_SIG],MCB_NORMAL
	mov	ax,[PSP_ACTIVE]
	mov	es:[MCB_OWNER],ax
	mov	es:[MCB_PARAS],bx
	mov	ax,es
	inc	ax			; return ES+1 in AX, with CARRY clear
	clc
	jmp	short m9

m7:	cmp	es:[MCB_SIG],MCB_LAST	; last block?
	je	m8			; yes, return error

	mov	dx,es			; advanced to the next block
	add	dx,ax
	mov	es,dx
	jmp	m1

m8:	mov	ax,ERR_MEMORY
	stc
m9:	ret
malloc	endp

DOS	ends

	end
