;
; BASIC-DOS 8086 Processor (CPU$) Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This is the second of two CPU$ drivers (see cpu.inc), and it stays only if
; the first (cpudev.asm) didn't, ie, on an 8086 or 8088 (or an 80286 that
; can't, or with "CPU=8088", won't use protected mode).  It manages all of
; memory with a chain of MCBs (see MCB in dosapi.inc), as DOS always has: the
; first MCB is in the paragraph after our code (see cpu_mcb), and the chain
; covers the rest of conventional memory, so every block that's allocated
; after us (eg, the other drivers, the kernel, and programs) has an MCB in the
; paragraph before it.  Our functions are the same as the first driver's: a
; selector is a segment, there are no descriptors to map or unmap, and
; CPU_QUERY describes each MCB with a PMB.
;
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	CPU86
CPU86	DDH	<offset DEV:ddcpu_end+16,,DDATTR_CHAR,offset DEV:ddcpu_init,-1,2020202024555043h>

	even
	DEFWORD	mcb_first,0		; paragraph of the first MCB
mv_pkt	MOVEPKT	<0,0,0>			; CPU_MOVE's packet, as it goes

	DEFLBL	CPU_FUNCS,word
	dw	ddcpu_getinfo, ddcpu_alloc, ddcpu_free, ddcpu_map
	dw	ddcpu_unmap, ddcpu_query, ddcpu_alias, cpu_inval
	dw	ddcpu_realloc, ddcpu_move

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; The only requests we support are OPEN and CLOSE (which always succeed).
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;	DDP_STATUS updated
;
; Modifies:
;	AX, DX
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcpu_req,far
	mov	ax,DDSTAT_DONE
	mov	dl,es:[bx].DDP_CMD
	cmp	dl,DDC_OPEN
	je	dcr9
	cmp	dl,DDC_CLOSE
	je	dcr9
	mov	ax,DDSTAT_ERROR + DDERR_UNKCMD
dcr9:	mov	es:[bx].DDP_STATUS,ax
	ret
ENDPROC	ddcpu_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cpu_entry (DDINT_CPU)
;
; Calls the CPU$ function in AH (see cpu.inc) with interrupts disabled and
; DS addressing our data.
;
; Inputs:
;	AH = CPU$ function; other registers as required by the function
;
; Outputs:
;	Carry clear if successful, set if error (AX = error code)
;
; Modifies:
;	AX, CX, DX (unless returning values); all other flags are restored
;
DEFPROC	cpu_entry,far
	push	ds
	push	es
	push	bp
	pushf
	cli
	push	bx
	push	si
	push	di
	mov	ds,cs:[0].DDH_DATA
	mov	bp,offset cpu_inval
	cmp	ah,CPU_MAXFUNC		; valid function?
	ja	ce1			; no
	mov	bl,ah
	mov	bh,0
	add	bx,bx
	mov	bp,cs:[CPU_FUNCS+bx]
	pop	di
	pop	si
	pop	bx
	push	bx
	push	si
	push	di
ce1:	call	bp
	pop	di
	pop	si
	mov	bp,sp
	rcr	word ptr [bp+2],1	; replace the caller's carry flag
	rol	word ptr [bp+2],1	; with ours, and restore its flags
	pop	bx
	popf
	pop	bp
	pop	es
	pop	ds
	ret
ENDPROC	cpu_entry

        ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_getinfo (CPU_GETINFO)
;
; Outputs:
;	AL = CPU type, AH = CPUF_* flags (none), DX:CX = length of largest
;	free block
;
DEFPROC	ddcpu_getinfo
	call	mcb_largest		; DX:CX = length of largest free block
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	al,[CPU_TYPE]
	mov	ah,0
	ret				; (carry is clear)
	ASSUME	DS:CODE
ENDPROC	ddcpu_getinfo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_alloc (CPU_ALLOC)
;
; Allocates the first free block that's long enough, or with SELF_HIGH, the
; top of the last one, or with SELF_AT, the memory at DX:CX, whose MCB goes in
; the paragraph before it (which must be free too); SELF_LOW is implied.
;
; Inputs:
;	AL = SELF_* flags, BX = owner, SI:DI = length
;	DX:CX = address (SELF_AT only)
;
; Outputs:
;	Carry clear if successful: AX = segment (0 if SELF_NONE), DX:CX =
;	address
;	Carry set if error: AX = error code (if ERR_NOMEMORY, DX:CX = length
;	of the largest free block)
;
DEFPROC	ddcpu_alloc
	push	ax			; save SELF_* flags
	test	al,SELF_AT
	jz	da1
	call	addr_mcb		; BP = MCB for DX:CX
	jc	da7
da1:	call	len_paras		; AX = paragraphs
	jz	da7			; (none)
	xchg	cx,ax			; CX = paragraphs
	pop	dx			; DL = SELF_* flags
	push	dx
	sub	di,di			; DI = a free MCB that fits (none yet)
	mov	ax,[mcb_first]
da2:	mov	es,ax
	cmp	es:[MCB_OWNER],0	; free?
	jne	da5			; no
	test	dl,SELF_AT
	jnz	da3
	cmp	es:[MCB_PARAS],cx	; long enough?
	jb	da5			; no
	mov	di,ax
	test	dl,SELF_HIGH		; looking for the last one?
	jz	da6			; no
	jmp	short da5
da3:	cmp	bp,ax			; is the MCB we want in this block?
	jb	da5			; no
	mov	si,ax
	add	si,es:[MCB_PARAS]
	sub	si,bp			; SI = paragraphs after it
	jb	da5			; (it's past this block)
	cmp	si,cx			; enough?
	jb	da5			; no
	mov	di,ax
	jmp	short da6
da5:	add	ax,es:[MCB_PARAS]
	inc	ax
	cmp	es:[MCB_SIG],MCBSIG_LAST
	jne	da2
	test	di,di			; did a block fit?
	jz	da8			; no
da6:	mov	es,di			; ES:0 -> the free block
	test	dl,SELF_AT
	jnz	da6a
	mov	bp,di			; BP = MCB at its start
	test	dl,SELF_HIGH
	jz	da6a
	add	bp,es:[MCB_PARAS]
	sub	bp,cx			; or at its top
da6a:	call	mcb_carve
	pop	dx			; DL = SELF_* flags
	mov	cx,bp
	inc	cx
	mov	ax,cx			; AX = segment
	test	dl,SELF_NONE
	jz	da6b
	sub	ax,ax
da6b:	jmp	para_len		; DX:CX = address
da7:	pop	ax
	jmp	cpu_inval
da8:	pop	ax
	call	mcb_largest		; DX:CX = length of largest free block
	mov	ax,ERR_NOMEMORY
	stc
	ret
ENDPROC	ddcpu_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_free (CPU_FREE)
;
; Frees a block, merging it with any free blocks before and after it.
;
; Inputs:
;	DX:CX = address of block
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_BADADDR)
;
DEFPROC	ddcpu_free
	call	mcb_find		; ES = MCB, DX = free MCB before it
	jc	df9
	sub	ax,ax
	mov	es:[MCB_OWNER],ax
	mov	es:[MCB_NAME],al
	call	mcb_merge		; merge the next block if it's free
	test	dx,dx			; is the block before it free?
	jz	df9			; no (and carry is clear)
	mov	es,dx
	call	mcb_merge		; yes, so merge this block into it
	clc
df9:	ret
ENDPROC	ddcpu_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_realloc (CPU_REALLOC)
;
; Changes the length of a block (rounding it up to a multiple of 16): a
; shorter block frees its end, and a longer one takes what it needs from the
; block after it, which must be free and long enough.
;
; Inputs:
;	DX:CX = address of block, SI:DI = new length
;
; Outputs:
;	Carry clear if successful; carry set if error: AX = error code (if
;	ERR_NOMEMORY, the block wasn't changed, and DX:CX = the longest it
;	could be)
;
DEFPROC	ddcpu_realloc
	call	mcb_find		; ES = MCB
	jc	dr9
	call	len_paras		; AX = new paragraphs
	jz	dr7			; (none)
	xchg	bx,ax			; BX = new paragraphs
	mov	cx,es:[MCB_PARAS]	; CX = paragraphs now
	cmp	bx,cx			; any change?
	je	dr9			; no (and carry is clear)
	mov	dl,es:[MCB_SIG]		; DL = signature for any free remainder
	cmp	dl,MCBSIG_LAST		; is this the last block?
	je	dr2			; yes
	mov	ax,es
	add	ax,cx
	inc	ax
	push	ds
	mov	ds,ax
	ASSUME	DS:NOTHING		; DS:0 -> next MCB
	mov	dl,MCBSIG_NEXT
	cmp	ds:[MCB_OWNER],0	; is the next block free?
	jne	dr1			; no
	add	cx,ds:[MCB_PARAS]
	inc	cx			; CX = the most paragraphs available
	mov	dl,ds:[MCB_SIG]
dr1:	pop	ds
	ASSUME	DS:CODE
dr2:	cmp	bx,cx			; are there enough?
	ja	dr8			; no
	je	dr3			; exactly
	push	es
	mov	ax,es
	add	ax,bx
	inc	ax
	mov	es,ax			; ES:0 -> new MCB for the remainder
	sub	cx,bx
	dec	cx			; CX = its paragraphs
	push	bx
	sub	bx,bx			; BX = owner (none)
	mov	al,dl
	call	mcb_set
	pop	bx
	pop	es
	mov	dl,MCBSIG_NEXT
dr3:	mov	es:[MCB_SIG],dl
	mov	es:[MCB_PARAS],bx
	clc
	ret
dr7:	jmp	cpu_inval
dr8:	call	para_len		; DX:CX = the longest it could be
	mov	ax,ERR_NOMEMORY
	stc
dr9:	ret
ENDPROC	ddcpu_realloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_map (CPU_MAP)
;
; There are no selectors to create, so the memory must be below 1Mb, at a
; paragraph boundary, and AX is its segment.
;
; Inputs:
;	AL = SELF_* flags, DX:CX = address, SI:DI = length
;
; Outputs:
;	Carry clear if successful: AX = segment, CX = 1
;	Carry set if error: AX = ERR_INVALID
;
DEFPROC	ddcpu_map
	mov	bx,si
	or	bx,di			; is the length zero?
	jz	dm8			; yes
	call	addr_mcb		; BP = segment - 1
	jc	dm8
	lea	ax,[bp+1]		; AX = segment
	mov	cx,1
	ret				; (carry is clear)
dm8:	jmp	cpu_inval
ENDPROC	ddcpu_map

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_unmap (CPU_UNMAP)
;
; There's nothing to do.
;
DEFPROC	ddcpu_unmap
	clc
	ret
ENDPROC	ddcpu_unmap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_alias (CPU_ALIAS)
;
; A segment is its own alias.
;
; Inputs:
;	AL = SELF_* flags, BX = segment
;
; Outputs:
;	Carry clear: AX = segment, DX:CX = its address
;
DEFPROC	ddcpu_alias
	mov	ax,bx
	mov	cx,bx
	jmp	para_len
ENDPROC	ddcpu_alias

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_query (CPU_QUERY)
;
; Describes an MCB with a PMB (PMB_SEL and PMB_NSEL are zero).
;
; Inputs:
;	BX = PMB # (0 for the first MCB)
;	ES:DI -> buffer for PMB
;
; Outputs:
;	Carry clear if successful (PMB copied to ES:DI)
;	Carry set if no such MCB (AX = ERR_INVALID)
;
DEFPROC	ddcpu_query
	mov	ax,[mcb_first]
dq1:	mov	ds,ax
	ASSUME	DS:NOTHING		; DS:0 -> MCB
	dec	bx			; is this the one?
	js	dq2			; yes
	cmp	ds:[MCB_SIG],MCBSIG_LAST
	je	cpu_inval
	add	ax,ds:[MCB_PARAS]
	inc	ax
	jmp	dq1
dq2:	mov	al,ds:[MCB_SIG]
	stosb				; PMB_SIG
	mov	ax,ds:[MCB_OWNER]
	cmp	ax,1			; carry set if free
	mov	al,PMBTYPE_USED
	sbb	al,0
	stosb				; PMB_TYPE
	mov	ax,ds:[MCB_OWNER]
	stosw				; PMB_OWNER
	mov	cx,ds
	inc	cx
	call	para_len
	xchg	ax,cx
	stosw
	xchg	ax,dx
	stosw				; PMB_ADDR
	mov	cx,ds:[MCB_PARAS]
	call	para_len
	xchg	ax,cx
	stosw
	xchg	ax,dx
	stosw				; PMB_LEN
	sub	ax,ax
	stosw				; PMB_SEL
	stosw				; PMB_NSEL
	mov	al,ds:[MCB_TYPE]
	stosb				; PMB_MCBTYPE
	mov	al,ah
	mov	cx,PMB_NAME - PMB_MCBTYPE - 1
	rep	stosb
	mov	si,MCB_NAME
	mov	cx,size MCB_NAME
	rep	movsb			; PMB_NAME
	ret				; (carry is clear)
	DEFLBL	cpu_inval,near
	mov	ax,ERR_INVALID
	stc
	ret
	ASSUME	DS:CODE
ENDPROC	ddcpu_query

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_move (CPU_MOVE)
;
; Copies a block of memory, up to 32K at a time, from the end if the
; destination is above the source, so that overlapping blocks are copied
; correctly.
;
; Inputs:
;	ES:BX -> MOVEPKT
;
; Outputs:
;	Carry clear
;
DEFPROC	ddcpu_move
	push	ds
	push	es
	pop	ds
	ASSUME	DS:NOTHING		; DS:SI -> caller's MOVEPKT
	pop	es
	ASSUME	ES:CODE			; ES:DI -> ours
	mov	si,bx
	mov	di,offset mv_pkt
	mov	cx,(size MOVEPKT) SHR 1
	rep	movsw
	push	es
	pop	ds
	ASSUME	DS:CODE, ES:NOTHING
	sub	bp,bp			; BP = 0 to copy forward
	mov	ax,[mv_pkt].MV_SRC.LOW
	mov	dx,[mv_pkt].MV_SRC.HIW
	cmp	dx,[mv_pkt].MV_DST.HIW
	ja	dv1
	jb	dv0
	cmp	ax,[mv_pkt].MV_DST.LOW
	jae	dv1
dv0:	inc	bp			; BP = 1 to copy backward
dv1:	mov	cx,8000h		; CX = up to 32K
	cmp	[mv_pkt].MV_LEN.HIW,0
	jne	dv2
	cmp	cx,[mv_pkt].MV_LEN.LOW
	jbe	dv2
	mov	cx,[mv_pkt].MV_LEN.LOW
	jcxz	dv9			; nothing left (and carry is clear)
dv2:	sub	[mv_pkt].MV_LEN.LOW,cx
	sbb	[mv_pkt].MV_LEN.HIW,0
	mov	si,offset mv_pkt + MV_SRC
	call	mv_ptr			; BX:SI -> source
	push	bx
	push	si
	mov	si,offset mv_pkt + MV_DST
	call	mv_ptr			; BX:SI -> destination
	mov	di,si
	mov	es,bx
	pop	si
	pop	ds
	ASSUME	DS:NOTHING
	test	bp,bp			; backward?
	jz	dv3			; no
	add	si,cx
	dec	si
	add	di,cx
	dec	di
	std
dv3:	rep	movsb
	cld
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	jmp	dv1
dv9:	ret
ENDPROC	ddcpu_move

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mv_ptr
;
; Returns a far pointer to the next CX bytes to copy from (or to) the address
; at DS:SI (MV_SRC or MV_DST), which is advanced past them if copying forward
; (BP = 0); if copying backward, they're the last CX bytes of the block left
; to copy (MV_LEN has already been reduced by CX).
;
; Inputs:
;	DS:SI -> address, CX = # of bytes, BP = direction (0 = forward)
;
; Outputs:
;	BX:SI -> those bytes
;
; Modifies:
;	AX, BX, DX, SI
;
DEFPROC	mv_ptr
	mov	ax,[si].LOW
	mov	dx,[si].HIW		; DX:AX = address
	test	bp,bp
	jnz	mp1
	add	[si].LOW,cx
	adc	[si].HIW,0
	jmp	short mp2
mp1:	add	ax,[mv_pkt].MV_LEN.LOW
	adc	dx,[mv_pkt].MV_LEN.HIW
mp2:	mov	bx,ax
	and	ax,0Fh			; AX = offset
	push	cx
	mov	cl,4
	shr	bx,cl
	mov	cl,12
	shl	dx,cl
	or	bx,dx			; BX = segment
	pop	cx
	xchg	si,ax			; SI = offset
	ret
ENDPROC	mv_ptr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_find
;
; Finds the allocated block at DX:CX.
;
; Outputs:
;	Carry clear if successful: ES:0 -> its MCB, DX = the MCB before it
;	if that block is free (otherwise zero)
;	Carry set if error: AX = ERR_BADADDR
;
; Modifies:
;	AX, DX, BP, ES
;
DEFPROC	mcb_find
	call	addr_mcb		; BP = MCB
	jc	mf8
	mov	ax,[mcb_first]
	sub	dx,dx
mf1:	mov	es,ax
	cmp	ax,bp			; is this the one?
	je	mf3			; yes
	cmp	es:[MCB_SIG],MCBSIG_LAST
	je	mf8
	sub	dx,dx
	cmp	es:[MCB_OWNER],dx	; is this block free?
	jne	mf2			; no
	mov	dx,ax
mf2:	add	ax,es:[MCB_PARAS]
	inc	ax
	jmp	mf1
mf3:	cmp	es:[MCB_OWNER],0	; is it allocated?
	jne	mf9			; yes (and carry is clear)
mf8:	mov	ax,ERR_BADADDR
	stc
mf9:	ret
ENDPROC	mcb_find

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_carve
;
; Allocates CX paragraphs at the MCB in BP, which is inside the free block at
; ES (at its start, or far enough after it for that MCB to fit), leaving free
; blocks for any memory before and after it.
;
; Inputs:
;	ES:0 -> free MCB, BP = new MCB, BX = owner, CX = paragraphs
;
; Modifies:
;	AX, DX, SI, DI, ES
;
DEFPROC	mcb_carve
	mov	dl,es:[MCB_SIG]		; DL = signature of the last block
	mov	si,es
	add	si,es:[MCB_PARAS]
	inc	si			; SI = paragraph after the free block
	mov	ax,bp
	mov	di,es
	sub	ax,di			; is the new MCB after the free one?
	jz	mc1			; no
	dec	ax
	mov	es:[MCB_PARAS],ax	; yes, so the free block ends before it
	mov	es:[MCB_SIG],MCBSIG_NEXT
mc1:	mov	ax,bp
	add	ax,cx
	inc	ax			; AX = paragraph after the new block
	sub	si,ax			; anything left after it?
	jz	mc2			; no
	mov	es,ax			; yes, so it's free
	push	bx
	push	cx
	mov	cx,si
	dec	cx			; CX = its paragraphs
	sub	bx,bx			; BX = owner (none)
	mov	al,dl
	call	mcb_set
	pop	cx
	pop	bx
	mov	dl,MCBSIG_NEXT
mc2:	mov	es,bp
	mov	al,dl			; (and fall into mcb_set)
ENDPROC	mcb_carve

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_set
;
; Inputs:
;	ES:0 -> MCB, AL = signature, BX = owner, CX = paragraphs
;
; Modifies:
;	AX
;
DEFPROC	mcb_set
	mov	es:[MCB_SIG],al
	mov	es:[MCB_OWNER],bx
	mov	es:[MCB_PARAS],cx
	push	cx
	push	di
	mov	di,MCB_TYPE
	mov	cx,(size MCB - MCB_TYPE) SHR 1
	sub	ax,ax
	rep	stosw			; zero the type and name
	pop	di
	pop	cx
	ret
ENDPROC	mcb_set

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_merge
;
; If the block after the free block at ES is free too, merges it.
;
; Inputs:
;	ES:0 -> free MCB
;
; Modifies:
;	AX
;
DEFPROC	mcb_merge
	cmp	es:[MCB_SIG],MCBSIG_LAST
	je	mm9
	mov	ax,es
	add	ax,es:[MCB_PARAS]
	inc	ax
	push	ds
	mov	ds,ax
	ASSUME	DS:NOTHING		; DS:0 -> next MCB
	cmp	ds:[MCB_OWNER],0	; is it free?
	jne	mm8			; no
	mov	ax,ds:[MCB_PARAS]
	inc	ax
	add	es:[MCB_PARAS],ax
	mov	al,ds:[MCB_SIG]
	mov	es:[MCB_SIG],al
mm8:	pop	ds
	ASSUME	DS:CODE
mm9:	ret
ENDPROC	mcb_merge

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_largest
;
; Outputs:
;	DX:CX = length of the largest free block (zero if none), carry clear
;
; Modifies:
;	AX, CX, DX, ES
;
DEFPROC	mcb_largest
	sub	cx,cx			; CX = most free paragraphs so far
	mov	ax,[mcb_first]
ml1:	mov	es,ax
	cmp	es:[MCB_OWNER],0	; free?
	jne	ml2			; no
	cmp	es:[MCB_PARAS],cx
	jbe	ml2
	mov	cx,es:[MCB_PARAS]
ml2:	add	ax,es:[MCB_PARAS]
	inc	ax
	cmp	es:[MCB_SIG],MCBSIG_LAST
	jne	ml1			; (and fall into para_len)
ENDPROC	mcb_largest

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; para_len
;
; Inputs:
;	CX = paragraphs (or a segment)
;
; Outputs:
;	DX:CX = bytes (or the segment's address), carry clear
;
DEFPROC	para_len
	push	ax
	xchg	ax,cx
	mov	cx,16
	mul	cx
	xchg	cx,ax
	pop	ax
	clc
	ret
ENDPROC	para_len

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addr_mcb
;
; Inputs:
;	DX:CX = address
;
; Outputs:
;	Carry clear if it's below 1Mb and a multiple of 16: BP = its segment
;	minus 1 (ie, where its MCB would be)
;
; Modifies:
;	DX, BP
;
DEFPROC	addr_mcb
	test	cl,0Fh			; a multiple of 16?
	jnz	am8			; no
	cmp	dx,10h			; below 1Mb?
	jae	am8			; no
	mov	bp,cx
	push	cx
	mov	cl,4
	shr	bp,cl
	mov	cl,12
	shl	dx,cl
	pop	cx
	or	bp,dx			; BP = segment (and carry is clear)
	dec	bp			; (DEC leaves carry alone)
	ret
am8:	stc
	ret
ENDPROC	addr_mcb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; len_paras
;
; Inputs:
;	SI:DI = length
;
; Outputs:
;	AX = paragraphs (rounded up), zero flag set if none; a length of 1Mb
;	or more returns FFFFh (more than there can be)
;
; Modifies:
;	AX, DX
;
DEFPROC	len_paras
	mov	ax,di
	mov	dx,si
	add	ax,15
	adc	dx,0
	cmp	dx,10h			; 1Mb or more?
	jae	lp8			; yes
	push	cx
	mov	cl,4
	shr	ax,cl
	mov	cl,12
	shl	dx,cl
	pop	cx
	or	ax,dx			; AX = paragraphs
	ret
lp8:	or	ax,-1
	ret
ENDPROC	len_paras

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The first MCB goes in the first paragraph here, which ends our code.
;
	DEFLBL	cpu_mcb,byte
	db	31 dup (0)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If the 80286 driver stayed, we don't; otherwise, we put the first MCB in the
; paragraph at cpu_mcb, with all the conventional memory after it free (our
; INIT code, the other drivers, and DEVINIT, which claims what it's using as
; soon as we return; see chk_cpu).
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated (left zero if we're not staying)
;
; Modifies:
;	AX, BX, CX, DX, DS, ES
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcpu_init,far
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; is CPU$ loaded already?
	jnc	di9			; yes, so we're not staying
	mov	ax,offset DEV:cpu_mcb + 15
	mov	cl,4
	shr	ax,cl			; AX = first MCB's paragraph, from CS
	mov	dx,ax
	inc	dx
	shl	dx,cl
	mov	es:[bx].DDPI_END.OFF,dx	; (we end after it)
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	ds:[0].DDH_REQUEST,offset DEV:ddcpu_req
	mov	dx,ds
	add	ax,dx
	mov	[mcb_first],ax
	mov	es,ax			; ES:0 -> the first MCB
	mov	dx,BIOS
	mov	ds,dx
	ASSUME	DS:BIOS
	mov	dx,[MEMORY_SIZE]
	mov	cl,6
	shl	dx,cl			; DX = end of conventional memory
	sub	dx,ax
	dec	dx
	mov	cx,dx			; CX = paragraphs after the first MCB
	sub	bx,bx			; BX = owner (none)
	mov	al,MCBSIG_LAST
	call	mcb_set
	mov	byte ptr ds:[DDINT_CPU],OP_JMPF
	mov	word ptr ds:[DDINT_CPU+1],offset DEV:cpu_entry
	mov	word ptr ds:[DDINT_CPU+3],cs
di9:	ret
ENDPROC	ddcpu_init

CODE	ends

DATA	segment para public 'DATA'

ddcpu_end	db	16 dup(0)

DATA	ends

	end
