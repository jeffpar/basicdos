;
; BASIC-DOS Memory Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; CPU$ manages all memory (see cpu.inc), so these functions just call it,
; passing it the segment (or selector) of each block, and keeping each
; block's owner, type, and name with CPU$ (see CPU_SETBLK).
;
	DOSPSP equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dos.inc
	include	dosapi.inc
	include	cpu.inc

DOS	segment word public 'CODE'

	EXTWORD	<dos_data,scb_active>
	EXTNEAR	<get_psp,scb_release>

	EXTBYTE	<scb_locked>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_alloc (REG_AH = 48h)
;
; The block can be anywhere in memory (including extended memory, in protected
; mode).  If MCBTYPE_HIGH is set in AL, it's allocated from the top of the
; last free block that's big enough, instead of the bottom of the first, so
; that long-lived blocks don't fragment the memory below them (eg, the memory
; that COMMAND.COM frees when it discards its transient portion).  The block
; is owned by the current PSP (or the system, if there's no PSP yet).
;
; Inputs:
;	REG_AL = MCBTYPE (optionally with MCBTYPE_HIGH)
;	REG_BX = paragraphs requested
;
; Outputs:
;	On success, REG_AX = new segment
;	On failure, REG_AX = error, REG_BX = max paras available
;
DEFPROC	mem_alloc,DOS
	mov	dl,al			; DL = type (and MCBTYPE_HIGH)
	call	get_psp			; AX = PSP (ZF set if none)
	jnz	ma1
	mov	ax,MCBOWNER_SYSTEM
ma1:	xchg	bx,ax			; BX = owner
	mov	ax,[bp].REG_BX
	call	para_len		; SI:DI = length
	mov	ax,CPU_ALLOC SHL 8
	test	dl,MCBTYPE_HIGH
	jz	ma2
	or	al,MEMF_HIGH
ma2:	push	dx
	call	far ptr DDINT_CPU	; AX = segment, DX:CX = address
	pop	si			; SI = type
	jc	ma8
	mov	[bp].REG_AX,ax
	xchg	ax,si
	and	al,NOT MCBTYPE_HIGH	; AL = type
	sub	si,si			; SI = 0 (no name)
	mov	ah,CPU_SETBLK
	call	far ptr DDINT_CPU	; BX = owner still
	ret
ma8:	mov	[bp].REG_AX,ax		; update REG_AX
	jmp	short mem_fail		; and REG_BX, and return CARRY set
ENDPROC	mem_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_free (REG_AH = 49h)
;
; Inputs:
;	REG_ES = segment to free
;
; Outputs:
;	On success, carry clear, REG_ES = 0 (and REG_DS, if it was the same)
;	On failure, carry set, REG_AX = ERR_BADADDR
;
DEFPROC	mem_free,DOS
	mov	cx,[bp].REG_ES		; CX = segment to free
	mov	dx,-1			; (DX = -1 means CX is a segment)
	mov	ah,CPU_FREE
	call	far ptr DDINT_CPU
	jnc	mf9
	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY set
	ret
;
; In protected mode, the block's selector is gone, and reloading it into the
; caller's ES (or DS, if it addressed the block, too) would fault, so (in
; either mode) the caller gets 0 instead.
;
mf9:	mov	ax,[bp].REG_ES		; AX = the freed segment (or selector)
	sub	dx,dx
	mov	[bp].REG_ES,dx
	cmp	[bp].REG_DS,ax		; did DS address the block, too?
	jne	mf9a			; no
	mov	[bp].REG_DS,dx
mf9a:	clc
	ret
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
	mov	ax,[bp].REG_BX
	call	para_len		; SI:DI = length
	mov	cx,[bp].REG_ES		; CX = segment to realloc
	mov	dx,-1			; (DX = -1 means CX is a segment)
	mov	ah,CPU_REALLOC
	call	far ptr DDINT_CPU
	jnc	mr9
	mov	[bp].REG_AX,ax		; update REG_AX
;
; mem_fail sets REG_BX to the paragraphs in DX:CX (at most FFFFh), the
; length that CPU$ says is available, and returns carry set.
;
	DEFLBL	mem_fail,near
	mov	bx,-1
	cmp	dx,10h			; 1Mb or more?
	jae	mr8			; yes
	mov	bx,cx
	mov	cl,4
	shr	bx,cl
	mov	cl,12
	shl	dx,cl
	or	bx,dx			; BX = paragraphs
mr8:	mov	[bp].REG_BX,bx
	stc
mr9:	ret
ENDPROC	mem_realloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; para_len
;
; Converts AX paragraphs to a length for CPU$; DOS allows a block with no
; paragraphs, but CPU$ doesn't, so it gets one.
;
; Inputs:
;	AX = paragraphs
;
; Outputs:
;	SI:DI = length in bytes
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	para_len
	cmp	ax,1
	adc	ax,0			; (0 becomes 1)
	mov	cl,4
	mov	di,ax
	shl	di,cl
	mov	si,ax
	mov	cl,12
	shr	si,cl
	ret
ENDPROC	para_len

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_query
;
; This utility function simplifies implementation of the MEM command.  It
; describes the memory blocks (all of memory, conventional and extended),
; using CPU_QUERY.
;
; Inputs:
;	CX = memory block # (0-based)
;	DL = memory block type (0 for any, 1 for free, 2 for used)
;
; Outputs:
;	On success, carry clear:
;		REG_BX = segment
;		REG_AX = owner ID (eg, PSP)
;		REG_SI:REG_DX = size (in bytes)
;		REG_ES:REG_DI -> name of process or type, if any
;	On failure, carry set (ie, no more blocks of the requested type)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	mem_query,DOS
	ASSUME	DS:DOS
	LOCK_SCB
	push	ds
	pop	es
	mov	di,offset pmb_buf	; ES:DI -> PMB buffer
	sub	bx,bx			; BX = PMB #
q1:	call	mem_pmb			; get PMB # BX
	jc	q9			; no more (and carry is set)
	test	dl,dl			; any block?
	jz	q3			; yes
	mov	al,1			; AL = 1 (free)
	cmp	[pmb_buf].PMB_TYPE,PMBTYPE_FREE
	je	q2
	inc	ax			; AL = 2 (used)
q2:	cmp	dl,al			; the type requested?
	jne	q4			; no
q3:	jcxz	q7			; and the block # requested?
	dec	cx
q4:	inc	bx
	jmp	q1
q7:	mov	ax,[pmb_buf].PMB_OWNER
	cmp	[pmb_buf].PMB_TYPE,PMBTYPE_FREE
	je	q7a			; (AX is zero)
	test	ax,ax			; does the used block have an owner?
	jnz	q7a			; yes
	mov	al,MCBOWNER_SYSTEM	; no (eg, a reserved block)
q7a:	mov	[bp].REG_AX,ax
	mov	cx,[pmb_buf].PMB_LEN.LOW
	mov	[bp].REG_DX,cx
	mov	cx,[pmb_buf].PMB_LEN.HIW
	mov	[bp].REG_SI,cx		; REG_SI:REG_DX = size
	mov	bx,[pmb_buf].PMB_SEL
	mov	[bp].REG_BX,bx
	cmp	ax,MCBOWNER_SYSTEM	; owned by a process (or driver)?
	jbe	q8			; no
	mov	di,offset pmb_buf + PMB_NAME
	cmp	byte ptr [di],0
	jne	q7b
	mov	di,offset pmb_buf + PMB_MCBTYPE
q7b:	mov	[bp].REG_DI,di
	mov	[bp].REG_ES,ds		; REG_ES:REG_DI -> string
q8:	clc
q9:	UNLOCK_SCB_RET
ENDPROC	mem_query

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_pmb
;
; Inputs:
;	BX = PMB #, or -1 for the block whose segment is CX
;	ES:DI -> PMB buffer
;
; Outputs:
;	Carry clear if successful (PMB copied to ES:DI)
;
; Modifies:
;	None
;
DEFPROC	mem_pmb
	push	ax
	push	cx
	push	dx
	mov	ah,CPU_QUERY
	call	far ptr DDINT_CPU
	pop	dx
	pop	cx
	pop	ax
	ret
ENDPROC	mem_pmb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_setname
;
; Makes the PSP at DX the owner of its block, and gives the block a name.
;
; Inputs:
;	DX = PSP segment
;	DS:SI -> name (8 characters), or SI = 0 for none
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	mcb_setname,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	push	ax
	push	bx
	push	cx
	push	dx
	push	es
	push	ds
	pop	es			; ES:SI -> name
	mov	bx,dx			; BX = owner
	mov	cx,dx
	mov	dx,-1			; DX:CX = block
	mov	ax,(CPU_SETBLK SHL 8) OR MCBTYPE_NONE
	call	far ptr DDINT_CPU
	pop	es
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	mcb_setname

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_alias
;
; Returns the code alias of a memory block: in protected mode, a code
; selector for the same memory as the block's selector, which CPU$ creates
; only once and frees with the block (see CPU_ALIAS); in real mode, the
; block's own segment.  load_program uses it for a COM program's CS, and
; programs get it with DOS_UTL_ALIAS (see utl_alias).
;
; Inputs:
;	AX = block's segment (or selector)
;
; Outputs:
;	Carry clear if successful: AX = code segment (or selector)
;	Carry set if error: AX = error code
;
; Modifies:
;	AX
;
DEFPROC	mem_alias,DOS
	push	bx
	push	cx
	push	dx
	xchg	bx,ax
	mov	ax,(CPU_ALIAS SHL 8) OR MEMF_CODE
	call	far ptr DDINT_CPU
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	mem_alias

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mem_pmode
;
; Returns carry set in protected mode, where segment arithmetic doesn't work
; (eg, an EXE file's relocations, so load_program can't load one; see
; docs/bdtech/mmu).
;
; Modifies:
;	CX, DX
;
DEFPROC	mem_pmode,DOS
	push	ax
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; AH = CPUF_* flags
	shr	ah,1			; carry = CPUF_PM (01h)
	pop	ax
	ret
ENDPROC	mem_pmode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_alias (AH = 27h)
;
; Returns the code alias of a memory block (see mem_alias), which a program
; needs to execute code that it writes into the block (eg, COMMAND.COM's code
; blocks).
;
; Inputs:
;	REG_BX = block's segment (or selector)
;
; Outputs:
;	Carry clear if successful: REG_AX = code segment (or selector)
;	Carry set if error: REG_AX = error code
;
DEFPROC	utl_alias,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ax,[bp].REG_BX
	call	mem_alias
	mov	[bp].REG_AX,ax		; (carry is unchanged)
	ret
ENDPROC	utl_alias

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_mapseg (AH = 28h)
;
; Returns a selector for a real-mode segment's 64K, for programs that read
; and write memory by segment (eg, BASIC's DEF SEG, PEEK, and POKE).  In real
; mode, it's the segment itself.  In protected mode, it's a selector that the
; session keeps (a later call replaces it): writable for video memory (A000h
; through BFFFh), and read-only everywhere else, so that programs can read
; low memory (eg, the BIOS data area) and the ROMs, but not change them.
;
; Inputs:
;	REG_BX = real-mode segment
;
; Outputs:
;	Carry clear if successful: REG_AX = selector (or segment)
;	Carry set if error: REG_AX = error code
;
DEFPROC	utl_mapseg,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	bx,[bp].REG_BX		; BX = segment
	call	mem_pmode		; protected mode?
	jnc	ums9			; no (the segment is its own selector)
	mov	ax,bx
	mov	cl,4
	shl	ax,cl
	mov	dx,bx
	mov	cl,12
	shr	dx,cl
	xchg	cx,ax			; DX:CX = the segment's address
	mov	al,MEMF_RDONLY OR MEMF_USER
	cmp	bh,0A0h			; video memory (A000h-BFFFh)?
	jb	ums1			; no
	cmp	bh,0C0h
	jae	ums1			; no
	mov	al,MEMF_USER		; yes, so it's writable
ums1:	mov	si,1
	sub	di,di			; SI:DI = 64K
	mov	ah,CPU_MAP
	call	far ptr DDINT_CPU	; AX = new selector
	jc	ums8
	mov	bx,[scb_active]
	xchg	ax,[bx].SCB_MAPSEL	; AX = the session's previous one
	test	ax,ax			; is there one?
	jz	ums3			; no
;
; Free the previous selector, and like mem_free, make sure the caller doesn't
; get it back in ES or DS.
;
	push	bx
	xchg	bx,ax			; BX = previous selector
	cmp	[bp].REG_ES,bx
	jne	ums2
	mov	[bp].REG_ES,0
ums2:	cmp	[bp].REG_DS,bx
	jne	ums2a
	mov	[bp].REG_DS,0
ums2a:	sub	cx,cx			; CX = 0 (one selector)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU
	pop	bx
	clc
ums3:	mov	bx,[bx].SCB_MAPSEL
ums9:	mov	[bp].REG_AX,bx		; (carry is clear)
	ret
ums8:	mov	[bp].REG_AX,ax		; (carry is set)
	ret
ENDPROC	utl_mapseg

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
;	Carry clear
;
; Modifies:
;	AX, BX
;
DEFPROC	mcb_free_all,DOS
	xchg	bx,ax			; BX = owner
	mov	ah,CPU_FREEALL
	call	far ptr DDINT_CPU
	ret
ENDPROC	mcb_free_all

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_getsize
;
; Returns the size (in paras) of a segment IFF it's a valid memory block.
;
; Inputs:
;	DX = segment
;
; Outputs:
;	On success, carry clear:
;		AX = size of segment, in paragraphs
;		CX = owner
;	On failure, carry set (not a valid memory block)
;
; Modifies:
;	AX, CX
;
DEFPROC	mcb_getsize,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	push	bx
	push	dx
	push	di
	push	es
	mov	es,cs:[dos_data]
	ASSUME	ES:DOS
	inc	es:[scb_locked]		; LOCK_SCB (through ES, not CS)
	mov	di,offset pmb_buf	; ES:DI -> PMB buffer
	mov	cx,dx
	mov	bx,-1			; BX = -1 (the block at segment CX)
	mov	dx,bx
	call	mem_pmb
	jc	gs9
	mov	ax,es:[di].PMB_LEN.LOW
	mov	dx,es:[di].PMB_LEN.HIW
	mov	cl,4
gs1:	shr	dx,1
	rcr	ax,1
	dec	cl
	jnz	gs1			; AX = paragraphs (and carry is clear)
	mov	cx,es:[di].PMB_OWNER
gs9:	pop	es
	ASSUME	ES:NOTHING
	pop	di
	pop	dx
	pop	bx
	UNLOCK_SCB_RET
ENDPROC	mcb_getsize

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mcb_findpsp
;
; Finds a PSP block (one that owns itself) whose PSP_CODESIZE and PSP_CHECKSUM
; match, and which is still long enough to contain the code (eg, COMMAND
; discards the transient portion of its code while running a program; see
; runTransient).
;
; Inputs:
;	AX = code size, DX = checksum
;
; Outputs:
;	CX = code segment (PSP_START.SEG, which in protected mode is a code
;	alias of the block) of the matching PSP (zero if none)
;
; Modifies:
;	CX
;
DEFPROC	mcb_findpsp,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	push	bx
	push	di
	push	es
	mov	es,cs:[dos_data]
	mov	di,offset pmb_buf	; ES:DI -> PMB buffer
	sub	bx,bx			; BX = PMB #
fp1:	call	mem_pmb
	jc	fp8			; no more
	mov	cx,es:[di].PMB_SEL
	jcxz	fp3			; (no segment)
	cmp	es:[di].PMB_OWNER,cx	; does the block own itself?
	jne	fp3			; no
	cmp	es:[di].PMB_LEN.HIW,0
	jne	fp2
	cmp	es:[di].PMB_LEN.LOW,ax	; does it still contain the code?
	jb	fp3			; no
fp2:	push	ds
	mov	ds,cx
	cmp	ds:[PSP_CODESIZE],ax
	jne	fp2a
	cmp	ds:[PSP_CHECKSUM],dx
	jne	fp2a
	mov	cx,ds:[PSP_START].SEG	; CX = its code (and ZF is still set)
fp2a:	pop	ds
	je	fp9			; a match
fp3:	inc	bx
	jmp	fp1
fp8:	sub	cx,cx			; no match
fp9:	pop	es
	pop	di
	pop	bx
	ret
ENDPROC	mcb_findpsp

pmb_buf	PMB	<>			; for CPU_QUERY

DOS	ends

	end
