;
; BASIC-DOS V86 Utility: Memory Blocks, Programs, and FPU$
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The machine's memory blocks (MCBs, as DOS has them), loading its programs
; (COM and EXE files) and their PSPs, and copying FPU$'s functions into it.
;
	include	v86host.inc
	include	fpu.inc

CODE    SEGMENT word public 'CODE'

	EXTBYTE	<VARS>
	EXTWORD	<cur_psp,mach_paras>
	EXTLONG	<dta>
	EXTNEAR	<seg_ptr,v86_get,v86_put,get_word,put_word>

	.286p

        ASSUME  CS:CODE, DS:CODE, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_init
;
; Makes all of the machine's memory after ARENA_SEG one free block.
;
; Modifies:
;	AX, CX, DI, ES
;
DEFPROC	mem_init
	mov	ax,ARENA_SEG
	sub	di,di
	call	seg_ptr
	mov	es:[di].MCB_SIG,MCBSIG_LAST
	mov	cx,[mach_paras]
	sub	cx,ARENA_SEG + 1
	mov	es:[di].MCB_PARAS,cx
	sub	ax,ax
	mov	es:[di].MCB_OWNER,ax
	inc	di
	inc	di
	inc	di
	inc	di
	inc	di			; ES:DI -> MCB_TYPE
	mov	cx,11
	rep	stosb			; MCB_TYPE through MCB_NAME
	ret
ENDPROC	mem_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_alloc
;
; Allocates a block: the first one that's big enough, or with MCBTYPE_HIGH,
; the top of the last one; free blocks that follow each other are combined
; along the way.
;
; Inputs:
;	BX = paragraphs, AL = MCBTYPE_* (and MCBTYPE_HIGH), DX = owner
;
; Outputs:
;	Carry clear: AX = segment
;	Carry set: AX = error code (and BX = most paragraphs available)
;
; Modifies:
;	AX, BX, CX, SI, DI, ES
;
DEFPROC	mem_alloc
	push	bp
	push	dx
	push	ax
	mov	bp,sp			; [BP] = type, [BP+2] = owner
	sub	si,si			; SI = the block that fits, if any
	sub	dx,dx			; DX = most paragraphs seen
	mov	ax,ARENA_SEG
ma1:	call	mcb_ptr			; ES:DI -> MCB
	jc	ma9			; (AX = error code)
	cmp	es:[di].MCB_OWNER,0	; free?
	jne	ma4			; no
	call	mcb_join		; join any free blocks after it
	mov	cx,es:[di].MCB_PARAS
	cmp	cx,dx
	jbe	ma2
	mov	dx,cx
ma2:	cmp	cx,bx			; big enough?
	jb	ma4			; no
	mov	si,ax			; yes
	test	byte ptr [bp],MCBTYPE_HIGH	; is the last one we want?
	jz	ma5			; no, the first
ma4:	cmp	es:[di].MCB_SIG,MCBSIG_LAST
	je	ma4a
	add	ax,es:[di].MCB_PARAS
	inc	ax			; AX = next MCB
	jmp	ma1
ma4a:	test	si,si			; did one fit?
	jnz	ma5			; yes
	mov	bx,dx
	mov	ax,ERR_NOMEMORY
	stc
	jmp	short ma9
ma5:	mov	ax,si
	call	mcb_ptr			; ES:DI -> the block's MCB
	mov	cx,es:[di].MCB_PARAS
	sub	cx,bx			; CX = paragraphs left over
	jz	ma7			; none
	test	byte ptr [bp],MCBTYPE_HIGH	; take the top?
	jnz	ma6			; yes
	call	mcb_split		; no, the bottom
	jmp	short ma7
ma6:	push	bx
	mov	bx,cx
	dec	bx			; the bottom (less an MCB) stays free
	call	mcb_split
	pop	bx
	add	ax,cx			; AX = the top part's MCB
	call	mcb_ptr
ma7:	mov	dx,[bp+2]
	mov	es:[di].MCB_OWNER,dx
	mov	cl,[bp]
	and	cl,NOT MCBTYPE_HIGH
	mov	es:[di].MCB_TYPE,cl
	push	ax
	sub	ax,ax
	add	di,MCB_NAME
	stosw
	stosw
	stosw
	stosw
	pop	ax
	inc	ax			; AX = the block's segment
	clc
ma9:	pop	cx
	pop	dx
	pop	bp
	ret
ENDPROC	mem_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_free
;
; Inputs:
;	AX = segment
;
; Outputs:
;	Carry clear if successful, set if not (AX = error code)
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	mem_free
	dec	ax
	call	mcb_ptr
	jc	mf9
	mov	es:[di].MCB_OWNER,0
mf9:	ret
ENDPROC	mem_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_realloc
;
; Inputs:
;	AX = segment, BX = paragraphs
;
; Outputs:
;	Carry clear if successful
;	Carry set: AX = error code (and BX = most paragraphs it could have)
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	mem_realloc
	dec	ax
	call	mcb_ptr			; ES:DI -> MCB
	jc	mr9
	mov	cx,es:[di].MCB_PARAS	; CX = paragraphs now
	cmp	bx,cx			; growing?
	jbe	mr2			; no
	call	mcb_join		; maybe, if free blocks follow
	cmp	bx,es:[di].MCB_PARAS
	jbe	mr2			; yes
	push	es:[di].MCB_PARAS	; no, so save the most it could have
	mov	bx,cx
	call	mr2			; and put it back the way it was
	pop	bx
	mov	ax,ERR_NOMEMORY
	stc
mr9:	ret
mr2:	cmp	es:[di].MCB_PARAS,bx	; any to give up?
	je	mr8			; no
	call	mcb_split
mr8:	clc
	ret
ENDPROC	mem_realloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_split
;
; Makes the paragraphs of a block after the first BX a free block of their
; own (which needs at least one more paragraph, for its MCB).
;
; Inputs:
;	AX = MCB segment, ES:DI -> MCB, BX = paragraphs to keep
;
; Outputs:
;	ES:DI -> MCB
;
; Modifies:
;	DI, ES
;
DEFPROC	mcb_split
	push	ax
	push	cx
	push	dx
	mov	cx,es:[di].MCB_PARAS
	sub	cx,bx
	dec	cx			; CX = the new block's paragraphs
	mov	dl,MCBSIG_NEXT
	xchg	dl,es:[di].MCB_SIG	; DL = the block's signature
	mov	es:[di].MCB_PARAS,bx
	add	ax,bx
	inc	ax			; AX = the new MCB
	sub	di,di
	call	seg_ptr
	mov	es:[di].MCB_SIG,dl
	mov	es:[di].MCB_PARAS,cx
	sub	cx,cx
	mov	es:[di].MCB_OWNER,cx
	mov	es:[di].MCB_TYPE,cl
	pop	dx
	pop	cx
	pop	ax
	sub	di,di
	jmp	seg_ptr			; ES:DI -> the block's MCB again
ENDPROC	mcb_split

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_freeall
;
; Frees every block that an owner has.
;
; Inputs:
;	DX = owner
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	mem_freeall
	mov	ax,ARENA_SEG
mfa1:	call	mcb_ptr
	jc	mfa9
	cmp	es:[di].MCB_OWNER,dx
	jne	mfa2
	mov	es:[di].MCB_OWNER,0
mfa2:	cmp	es:[di].MCB_SIG,MCBSIG_LAST
	je	mfa9
	add	ax,es:[di].MCB_PARAS
	inc	ax
	jmp	mfa1
mfa9:	ret
ENDPROC	mem_freeall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_query
;
; Finds a block, for DOSUTIL QRYMEM.
;
; Inputs:
;	CX = block # (from 0), DL = 0 for any block, 1 for a free one, 2 for a
;	used one, or 3 for one of the current PSP's
;
; Outputs:
;	Carry clear: AX = MCB segment, ES:DI -> MCB
;	Carry set if there's no such block
;
; Modifies:
;	AX, CX, DI, ES
;
DEFPROC	mem_query
	mov	ax,ARENA_SEG
mq1:	call	mcb_ptr
	jc	mq9
	cmp	dl,3
	ja	mq8
	je	mq3
	cmp	dl,1
	jb	mq5			; any block
	je	mq2
	cmp	es:[di].MCB_OWNER,0	; used?
	jne	mq5			; yes
	jmp	short mq6
mq2:	cmp	es:[di].MCB_OWNER,0	; free?
	je	mq5			; yes
	jmp	short mq6
mq3:	push	bx
	mov	bx,[cur_psp]
	cmp	es:[di].MCB_OWNER,bx	; ours?
	pop	bx
	jne	mq6			; no
mq5:	jcxz	mq9			; this is the one (carry is clear)
	dec	cx
mq6:	cmp	es:[di].MCB_SIG,MCBSIG_LAST
	je	mq8
	add	ax,es:[di].MCB_PARAS
	inc	ax
	jmp	mq1
mq8:	stc
mq9:	ret
ENDPROC	mem_query

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_ptr
;
; Inputs:
;	AX = MCB segment
;
; Outputs:
;	Carry clear: ES:DI -> MCB
;	Carry set: AX = ERR_BADMCB
;
; Modifies:
;	DI, ES (and AX on error)
;
DEFPROC	mcb_ptr
	cmp	ax,ARENA_SEG		; in the machine's arena?
	jb	mp8			; no
	cmp	ax,[mach_paras]
	jae	mp8			; no
	sub	di,di
	call	seg_ptr
	cmp	es:[di].MCB_SIG,MCBSIG_NEXT
	je	mp9			; (carry is clear)
	cmp	es:[di].MCB_SIG,MCBSIG_LAST
	je	mp9
mp8:	mov	ax,ERR_BADMCB
	stc
mp9:	ret
ENDPROC	mcb_ptr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_join
;
; Combines a block with any free blocks after it.
;
; Inputs:
;	AX = MCB segment
;
; Outputs:
;	ES:DI -> MCB
;
; Modifies:
;	DI, ES
;
DEFPROC	mcb_join
	push	bx
	push	cx
	push	dx
mj1:	call	mcb_ptr
	cmp	es:[di].MCB_SIG,MCBSIG_LAST
	je	mj9
	mov	cx,es:[di].MCB_PARAS
	push	ax
	add	ax,cx
	inc	ax
	call	mcb_ptr			; ES:DI -> the next MCB
	jc	mj8
	cmp	es:[di].MCB_OWNER,0	; free?
	jne	mj8			; no
	mov	dl,es:[di].MCB_SIG
	mov	bx,es:[di].MCB_PARAS
	pop	ax
	call	mcb_ptr
	mov	es:[di].MCB_SIG,dl
	add	cx,bx
	inc	cx
	mov	es:[di].MCB_PARAS,cx
	jmp	mj1
mj8:	pop	ax
	call	mcb_ptr
mj9:	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	mcb_join

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_prog
;
; Loads a program (a COM or EXE file) into a new block, with a new PSP, as
; DOS_PSP_EXEC1 would.  A COM file with COMDATA (see COMHEAP) gets the
; memory, heap, and stack that BASIC-DOS would give it; any other COM file
; keeps all the memory, and an EXE file gets what its header asks for.
;
; Inputs:
;	BX = handle (closed on return), AX = environment (0 for the parent's)
;	CX = parent PSP (0 for none, for the machine's first program)
;	V_PATH = its name, V_TAIL = its command tail, V_EPB = an EPB (for its
;	FCBs; EPB_FCB1 offset -1 to make them from the tail)
;
; Outputs:
;	Carry clear: AX = PSP, ld_cs:ld_ip and ld_ss:ld_sp = its registers
;	Carry set: AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	load_prog
	mov	[ld_hdl],bx
	mov	[ld_env],ax
	mov	[ld_par],cx
	mov	dx,offset VARS + V_HDR
	mov	cx,1Ch
	mov	ah,DOS_HDL_READ
	int	21h			; read what an EXE header would be
	jc	lpe1
	cmp	ax,1Ch
	jb	lp1			; too short for one
	mov	ax,word ptr [VARS + V_HDR]
	cmp	ax,'ZM'			; an EXE?
	je	lp2			; yes
	cmp	ax,'MZ'
	je	lp2
lp1:	jmp	lp_com
lpe1:	jmp	lp_err
;
; Load an EXE file.
;
lp2:	mov	ax,word ptr [VARS + V_HDR + 4]
	sub	dx,dx
	mov	cx,9
lp2a:	shl	ax,1
	rcl	dx,1
	loop	lp2a			; DX:AX = the pages, in bytes
	mov	cx,word ptr [VARS + V_HDR + 2]
	jcxz	lp2b			; the last page is full
	sub	cx,512
	add	ax,cx
	adc	dx,-1			; less what the last page doesn't use
lp2b:	mov	cx,word ptr [VARS + V_HDR + 8]
	shl	cx,4			; (a header has less than 4K paras)
	sub	ax,cx
	sbb	dx,0			; DX:AX = the image's length
	mov	[ld_size].LOW,ax
	mov	[ld_size].HIW,dx
	add	ax,15
	adc	dx,0
	mov	cx,4
lp2c:	shr	dx,1
	rcr	ax,1
	loop	lp2c			; AX = the image's paragraphs
	add	ax,10h			; and the PSP's
	jc	lp2e
	mov	[ld_base],ax
	add	ax,word ptr [VARS + V_HDR + 0Ah]	; plus its minimum
	jnc	lp2f
lp2e:	jmp	lp_big
lp2f:
	call	ld_alloc		; AX = PSP, BX = paragraphs
	jc	lpe1
	mov	ax,[ld_base]
	add	ax,word ptr [VARS + V_HDR + 0Ch]	; plus its maximum
	jnc	lp2d
	mov	ax,-1
lp2d:	cmp	ax,bx			; less than it got?
	jae	lp3			; no
	xchg	bx,ax
	mov	ax,[ld_psp]
	call	mem_realloc		; yes, so give it just that
	mov	[ld_paras],bx
;
; Read the image, after the PSP, and fix its relocations.
;
lp3:	mov	ax,[ld_psp]
	add	ax,10h
	mov	[ld_base],ax
	mov	dx,word ptr [VARS + V_HDR + 8]
	mov	cx,dx
	shl	dx,4
	shr	cx,12			; CX:DX = the image's offset
	mov	ax,DOS_HDL_SEEKBEG
	mov	bx,[ld_hdl]
	int	21h
	jc	lpe2
	mov	ax,[ld_base]
lp3a:	mov	cx,8000h
	cmp	[ld_size].HIW,0
	jne	lp3b
	cmp	[ld_size].LOW,cx
	jae	lp3b
	mov	cx,[ld_size].LOW
	jcxz	lp4			; all of it
lp3b:	sub	di,di
	call	ld_read
	jc	lpe2
	sub	[ld_size].LOW,cx
	sbb	[ld_size].HIW,0
	add	ax,800h			; (the next 32K)
	jmp	lp3a
lpe2:	jmp	lp_errf
lp4:	mov	dx,word ptr [VARS + V_HDR + 18h]
	sub	cx,cx			; CX:DX = the relocations' offset
	mov	ax,DOS_HDL_SEEKBEG
	mov	bx,[ld_hdl]
	int	21h
	jc	lpe2
	mov	si,word ptr [VARS + V_HDR + 6]	; SI = # of relocations
lp4a:	test	si,si
	jz	lp5
	mov	cx,si
	cmp	cx,BUF_LEN / 4
	jbe	lp4b
	mov	cx,BUF_LEN / 4
lp4b:	sub	si,cx
	push	si
	push	cx
	shl	cx,2
	mov	dx,offset VARS + V_BUF
	mov	ah,DOS_HDL_READ
	int	21h
	pop	cx
	pop	si
	jc	lpe2
	mov	bx,offset VARS + V_BUF
lp4c:	mov	di,[bx]			; (the offset)
	mov	ax,[bx+2]
	add	ax,[ld_base]		; (and the segment)
	push	ax
	push	di
	call	get_word
	add	ax,[ld_base]
	xchg	dx,ax
	pop	di
	pop	ax
	call	put_word		; add the base to the word there
	add	bx,4
	loop	lp4c
	mov	bx,[ld_hdl]
	jmp	lp4a
lp5:	mov	ax,[ld_base]
	mov	dx,ax
	add	ax,word ptr [VARS + V_HDR + 16h]
	mov	[ld_cs],ax
	mov	ax,word ptr [VARS + V_HDR + 14h]
	mov	[ld_ip],ax
	add	dx,word ptr [VARS + V_HDR + 0Eh]
	mov	[ld_ss],dx
	mov	ax,word ptr [VARS + V_HDR + 10h]
	mov	[ld_sp],ax
	jmp	lp_psp
lp_big:	mov	ax,ERR_NOMEMORY
	jmp	lp_err
;
; Load a COM file, which we read from the start.
;
lp_com:	mov	ax,DOS_HDL_SEEKEND
	sub	cx,cx
	sub	dx,dx
	mov	bx,[ld_hdl]
	int	21h			; DX:AX = its length
	jc	lpc8
	test	dx,dx
	jnz	lpc7
	cmp	ax,COM_MAX
	ja	lpc7
	mov	[ld_size].LOW,ax
	mov	ax,DOS_HDL_SEEKBEG
	sub	dx,dx
	int	21h
	jc	lpc8
	mov	ax,[ld_size].LOW
	add	ax,100h + MINHEAP + 15
	rcr	ax,1
	shr	ax,3			; AX = the paragraphs it needs
	call	ld_alloc		; AX = PSP, BX = paragraphs
	jc	lpc8
	mov	cx,[ld_size].LOW
	mov	di,100h
	jcxz	lc1
	cmp	cx,8000h
	jbe	lc0
	mov	cx,8000h
	call	ld_read
	jc	lpc9
	mov	cx,[ld_size].LOW
	sub	cx,8000h
	add	di,8000h
lc0:	call	ld_read
	jnc	lc1
lpc9:	jmp	lp_errf
lpc7:	jmp	lp_big
lpc8:	jmp	lp_err
;
; As BASIC-DOS does (see load_program), give it COMDATA's heap (at least
; MINHEAP) after its image, unless the heap is in the image.
;
lc1:	mov	si,[ld_size].LOW
	add	si,100h			; SI = the end of its image
	mov	dx,MINHEAP SHR 4	; DX = paragraphs for its heap
	mov	ax,[ld_psp]
	lea	di,[si-2]
	call	get_word
	cmp	ax,SIG_BASICDOS		; COMDATA?
	jne	lc4			; no
	mov	ax,[ld_psp]
	push	si
	sub	si,size COMDATA
	mov	di,offset VARS + V_BUF
	mov	cx,size COMDATA
	call	v86_get			; V_BUF = its COMDATA
	pop	si
	mov	bx,offset VARS + V_BUF
	mov	ax,[bx].CD_HEAPSIZE
	cmp	ax,dx
	jbe	lc2
	xchg	dx,ax
lc2:	mov	ax,[bx].CD_CODESIZE
	mov	[ld_code],ax
	mov	[ld_hsize],dx
	test	ax,ax			; does its heap follow its code?
	jnz	lc3			; yes
	mov	ax,si			; no, its image
lc3:	mov	[ld_heap],ax
	mov	ax,[bx].CD_HEAPOFF
	test	ax,ax			; is the heap in its image?
	jz	lc5			; no
	mov	[ld_heap],ax
	mov	cx,[bx].CD_HEAPSIZE
	mov	[ld_hsize],cx
	shl	cx,4
	add	ax,cx
	mov	[ld_sp],ax		; its stack is at the top of the heap
	sub	dx,dx			; and it needs no more
	jmp	short lc6
lc4:	mov	dx,[ld_paras]		; any other COM file keeps it all
	sub	bx,bx
	mov	[ld_heap],bx
	mov	[ld_hsize],bx
	mov	[ld_code],bx
	jmp	short lc7
lc5:	mov	[ld_sp],0
lc6:	mov	bx,si
	add	bx,15
	shr	bx,4
	add	dx,bx			; DX = paragraphs it needs
	cmp	dx,[ld_paras]
	ja	lp_big4
	mov	bx,dx
	mov	ax,[ld_psp]
	call	mem_realloc
	mov	[ld_paras],bx
	cmp	[ld_sp],0		; a stack at the top of the heap?
	jne	lc8			; yes
lc7:	mov	ax,dx
	cmp	ax,1000h
	jb	lc7a
	mov	ax,1000h
lc7a:	shl	ax,4			; (64K is 0)
	mov	[ld_sp],ax
;
; Zero the memory after its image (up to 64K, for a heap and stack).
;
lc8:	mov	cx,[ld_paras]
	cmp	cx,1000h
	jb	lc8a
	mov	cx,1000h
lc8a:	shl	cx,4
	dec	cx			; CX = its last offset
	sub	cx,si			; less the image's end
	inc	cx			; CX = bytes to zero
	jz	lc9
	mov	di,si
lc8b:	push	cx
	cmp	cx,8000h
	jbe	lc8c
	mov	cx,8000h
lc8c:	push	cx
	mov	ax,[ld_psp]
	call	seg_ptr
	sub	ax,ax
	rep	stosb
	pop	cx
	add	si,cx
	mov	di,si
	pop	ax
	sub	ax,cx
	xchg	cx,ax
	jnz	lc8b
lc9:	mov	ax,[ld_psp]
	mov	[ld_cs],ax
	mov	[ld_ss],ax
	mov	[ld_ip],100h
	sub	[ld_sp],2
	mov	di,[ld_sp]
	sub	dx,dx
	call	put_word		; for its RET (to the PSP's INT 20h)
	jmp	short lp_psp
lp_big4:mov	ax,ERR_NOMEMORY
	jmp	short lp_errf
;
; Make its PSP.
;
lp_psp:	call	psp_build
	mov	ax,[ld_psp]
	mov	di,PSP_CODESIZE
	mov	dx,[ld_code]
	call	put_word
	mov	di,PSP_HEAPSIZE
	mov	dx,[ld_hsize]
	call	put_word
	mov	di,PSP_HEAP
	mov	dx,[ld_heap]
	call	put_word
	call	lp_close
	mov	ax,[ld_psp]
	clc
	ret
lp_errf:push	ax
	mov	ax,[ld_psp]
	call	mem_free
	pop	ax
lp_err:	push	ax
	call	lp_close
	pop	ax
	stc
	ret
lp_close:
	mov	bx,[ld_hdl]
	mov	ah,DOS_HDL_CLOSE
	int	21h
	ret
ENDPROC	load_prog

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ld_alloc
;
; Allocates the largest block (as DOS does for a program), if it has at least
; the paragraphs that the program needs, and makes its PSP the owner.
;
; Inputs:
;	AX = paragraphs needed
;
; Outputs:
;	Carry clear: AX = ld_psp = PSP, BX = ld_paras = paragraphs
;	Carry set: AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	ld_alloc
	push	ax
	mov	bx,-1
	mov	dx,MCBOWNER_SYSTEM
	mov	al,0
	call	mem_alloc		; BX = most paragraphs available
	pop	ax
	cmp	bx,ax
	mov	ax,ERR_NOMEMORY
	jb	la9			; (carry is set)
	mov	al,0
	call	mem_alloc		; AX = segment
	jc	la9
	mov	[ld_psp],ax
	mov	[ld_paras],bx
	mov	dx,ax
	dec	ax
	mov	di,MCB_OWNER
	call	put_word		; the PSP owns it
	mov	ax,dx
	clc
la9:	ret
ENDPROC	ld_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ld_read
;
; Reads CX bytes (at most 32K) of the program into the machine at AX:DI.
;
; Outputs:
;	Carry set if error (AX = error code)
;
; Modifies:
;	BX, DX (and AX, on error)
;
DEFPROC	ld_read
	push	ax
	push	di
	push	es
	call	seg_ptr			; ES:DI -> where it goes
	mov	bx,[ld_hdl]
	mov	dx,di
	push	ds
	push	es
	pop	ds
	mov	ah,DOS_HDL_READ
	int	21h
	pop	ds
	pop	es
	pop	di
	jc	lr8
	pop	ax
	ret
lr8:	pop	dx			; (discard AX, return the error)
	ret
ENDPROC	ld_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_build
;
; Fills in a new PSP (at ld_psp, ld_paras long), as DOS_PSP_EXEC does:
; INT 20h, the top of its memory, the vectors (22h-24h) that its exit will
; restore, its parent, its handles (its parent's, or for the first program,
; ours), its environment, its FCBs and command tail, and its MCB's name.
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	psp_build
	mov	ax,[ld_psp]
	sub	di,di
	call	seg_ptr			; ES:DI -> PSP
	mov	cx,100h / 2
	sub	ax,ax
	rep	stosw
	sub	di,100h
	mov	es:[di].PSP_TERMCALL,OP_INT20
	mov	ax,[ld_psp]
	add	ax,[ld_paras]
	mov	es:[di].PSP_PARAS,ax
	mov	al,ds:[PSP_SCB]
	mov	es:[di].PSP_SCB,al
	mov	es:[di].PSP_MODE,PSPMODE_V86
	mov	word ptr es:[di].PSP_DOSCALL,21CDh	; INT 21h
	mov	es:[di].PSP_DOSCALL+2,0CBh		; RETF
	mov	es:[di].PSP_HDLFREE,PFT_LEN
	mov	es:[di].PSP_HDLPTR.OFF,PSP_PFT
	mov	ax,[ld_psp]
	mov	es:[di].PSP_HDLPTR.SEG,ax
	mov	ax,[dta].OFF
	mov	es:[di].PSP_DTAPREV.OFF,ax
	mov	ax,[dta].SEG
	mov	es:[di].PSP_DTAPREV.SEG,ax
	mov	ax,[ld_par]
	test	ax,ax			; is there a parent?
	jnz	pb1			; yes
	mov	ax,[ld_psp]		; no, so it's its own
pb1:	mov	es:[di].PSP_PARENT,ax
	mov	si,INT_DOSEXIT * 4
	mov	di,offset VARS + V_BUF
	mov	cx,12
	sub	ax,ax
	call	v86_get			; V_BUF = vectors 22h-24h
	mov	si,offset VARS + V_BUF
	mov	ax,[ld_psp]
	mov	di,PSP_EXIT
	mov	cx,12
	call	v86_put			; into PSP_EXIT, PSP_CTRLC, PSP_ERROR
;
; Its handles are its parent's (or for the first program, ours), each one
; another reference to its SFH (see sfh_ref).
;
	mov	si,PSP_PFT		; (ours)
	mov	ax,[ld_par]
	test	ax,ax
	jz	pb2
	mov	si,PSP_PFT
	mov	di,offset VARS + V_BUF
	mov	cx,PFT_LEN
	call	v86_get
	mov	si,offset VARS + V_BUF
pb2:	push	si
	mov	cx,PFT_LEN
pb3:	lodsb
	cmp	al,SFH_NONE
	je	pb4
	mov	bl,al
	mov	bh,0
	inc	byte ptr [VARS + V_REFS + bx]
pb4:	loop	pb3
	pop	si
	mov	ax,[ld_psp]
	mov	di,PSP_PFT
	mov	cx,PFT_LEN
	call	v86_put
;
; Its environment is the one given, or its parent's.
;
	mov	dx,[ld_env]
	test	dx,dx
	jnz	pb5
	mov	ax,[ld_par]
	mov	di,PSP_ENVSEG
	call	get_word
	xchg	dx,ax
pb5:	mov	ax,[ld_psp]
	mov	di,PSP_ENVSEG
	call	put_word
;
; Its FCBs are made from its command tail (or copied from the EPB's), and
; its command tail follows them.
;
	mov	si,offset VARS + V_TAIL + 1
	mov	dx,PSP_FCB1
	mov	bx,offset VARS + V_EPB + EPB_FCB1
	call	pb_fcb
	mov	dx,PSP_FCB2
	mov	bx,offset VARS + V_EPB + EPB_FCB2
	call	pb_fcb
	mov	si,offset VARS + V_TAIL
	mov	cl,[si]
	mov	ch,0
	inc	cx
	inc	cx			; (its length, chars, and CR)
	mov	ax,[ld_psp]
	mov	di,PSP_CMDTAIL
	call	v86_put
;
; Its MCB's name is its name (without any directory or extension).
;
	mov	si,offset VARS + V_PATH
	mov	bx,si
pb6:	lodsb
	cmp	al,':'
	je	pb6a
	cmp	al,'\'
	jne	pb6b
pb6a:	mov	bx,si			; BX -> after the last ':' or '\'
pb6b:	test	al,al
	jnz	pb6
	mov	si,bx
	mov	di,offset VARS + V_BUF
	push	di
	mov	cx,8
pb7:	lodsb
	cmp	al,'.'
	je	pb8
	test	al,al
	jz	pb8
	mov	[di],al
	inc	di
	loop	pb7
	jmp	short pb9
pb8:	mov	byte ptr [di],0
	inc	di
	loop	pb8
pb9:	pop	si
	mov	ax,[ld_psp]
	dec	ax
	mov	di,MCB_NAME
	mov	cx,8
	jmp	v86_put
;
; Make (or copy) the FCB at PSP offset DX, from SI (or the EPB's pointer at
; BX); SI is updated.
;
pb_fcb:	push	si
	push	ds
	pop	es
	mov	di,offset VARS + V_FCB
	push	di
	mov	cx,16
	mov	al,0
	rep	stosb
	pop	di
	pop	si
	cmp	word ptr [bx],-1	; make it?
	jne	pf1			; no
	mov	ax,(DOS_FCB_PARSE SHL 8) OR 1
	int	21h			; parse DS:SI into ES:DI (V_FCB)
	jmp	short pf2
pf1:	push	si
	mov	si,[bx]
	mov	ax,[bx+2]
	mov	cx,16
	call	v86_get			; copy the EPB's
	pop	si
pf2:	push	si
	mov	si,offset VARS + V_FCB
	mov	ax,[ld_psp]
	mov	di,dx
	mov	cx,16
	call	v86_put
	pop	si
	ret
ENDPROC	psp_build

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; start_prog
;
; Starts the program that load_prog loaded, as the current program: its
; registers are as DOS_PSP_EXEC sets them, and its DTA is in its PSP.
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	start_prog
	mov	ax,[ld_cs]
	mov	word ptr [VARS+VR_CS],ax
	mov	ax,[ld_ip]
	mov	word ptr [VARS+VR_EIP],ax
	mov	ax,[ld_ss]
	mov	word ptr [VARS+VR_SS],ax
	mov	ax,[ld_sp]
	mov	word ptr [VARS+VR_ESP],ax
	sub	ax,ax
	mov	word ptr [VARS+VR_EIP+2],ax
	mov	word ptr [VARS+VR_ESP+2],ax
	mov	word ptr [VARS+VR_EAX],ax
	mov	word ptr [VARS+VR_EFL],FL_DEFAULT
	mov	ax,[cur_psp]
	mov	word ptr [VARS+VR_DS],ax
	mov	word ptr [VARS+VR_ES],ax
	mov	[dta].SEG,ax
	mov	[dta].OFF,PSP_DTA
	DEFLBL	set_dta,near
;
; Point our DTA at the program's (the machine's [dta]).
;
	push	ds
	mov	ax,[dta].SEG
	mov	di,[dta].OFF
	call	seg_ptr
	push	es
	pop	ds
	mov	dx,di
	mov	ah,DOS_DSK_SETDTA
	int	21h
	pop	ds
	ret
ENDPROC	start_prog

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fpu_copy
;
; Copies FPU$'s functions into a block of the machine's (see fpu.inc): its
; shared code, followed by the FPUTBL and its functions, with the four far
; pointers between them changed to the copies' segments.
;
; Inputs:
;	AX = FPUTBL's selector (from IOCTL_GETFPU)
;
; Outputs:
;	Carry clear: AX = the copy's FPUTBL segment
;	Carry set: AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	fpu_copy
	mov	[fc_tsel],ax
	mov	es,ax
	mov	dx,word ptr es:[FPU_COMATOD + 2]
	mov	[fc_csel],dx		; the shared code's selector
	lsl	cx,ax
	inc	cx
	mov	[fc_tlen],cx		; the length of the FPUTBL's part
	lsl	bx,dx
	inc	bx
	mov	[fc_clen],bx		; and of the shared code
	add	bx,15
	shr	bx,4
	mov	[fc_paras],bx		; paragraphs for the shared code
	add	cx,15
	shr	cx,4
	add	bx,cx
	mov	al,MCBTYPE_HIGH
	mov	dx,MCBOWNER_SYSTEM
	call	mem_alloc		; AX = segment
	jc	fc9
	mov	si,[fc_csel]
	mov	cx,[fc_clen]
	call	fc_copy			; the shared code
	mov	dx,ax
	add	dx,[fc_paras]		; DX = the FPUTBL's segment
	push	ax
	xchg	ax,dx
	mov	si,[fc_tsel]
	mov	cx,[fc_tlen]
	call	fc_copy			; and the FPUTBL's part
	xchg	ax,dx
	mov	di,FPU_COMTODEC + 2
	call	put_word
	mov	di,FPU_COMFROMDEC + 2
	call	put_word
	pop	dx			; DX = the shared code's segment
	add	ax,[fc_paras]		; AX = the FPUTBL's
	mov	di,FPU_COMATOD + 2
	call	put_word
	mov	di,FPU_COMDTOA + 2
	call	put_word
	clc
fc9:	ret
;
; Copy CX bytes (less than 32K) from SI:0 to the machine's AX:0.
;
fc_copy:
	sub	di,di
	call	seg_ptr
	push	ds
	mov	ds,si
	sub	si,si
	rep	movsb
	pop	ds
	ret
ENDPROC	fpu_copy

	DEFWORD	ld_hdl,0		; the program's handle
	DEFWORD	ld_env,0		; its environment
	DEFWORD	ld_par,0		; its parent
	DEFWORD	ld_psp,0		; its PSP
	DEFWORD	ld_paras,0		; and the paragraphs it has
	DEFWORD	ld_base,0		; (for an EXE) its image's segment
	DEFLONG	ld_size,0		; its image's length
	DEFWORD	ld_code,0		; (for a COM) PSP_CODESIZE
	DEFWORD	ld_hsize,0		; PSP_HEAPSIZE
	DEFWORD	ld_heap,0		; PSP_HEAP
	DEFWORD	ld_cs,0			; its registers
	DEFWORD	ld_ip,0
	DEFWORD	ld_ss,0
	DEFWORD	ld_sp,0
	DEFWORD	fc_tsel,0		; (for fpu_copy) the FPUTBL's selector
	DEFWORD	fc_tlen,0		; and its part's length
	DEFWORD	fc_csel,0		; the shared code's selector
	DEFWORD	fc_clen,0		; and its length
	DEFWORD	fc_paras,0		; and paragraphs

CODE	ENDS

	end
