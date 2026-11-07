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

	EXTWORD	<dos_data>
	EXTNEAR	<get_psp,scb_release>

	EXTBYTE	<scb_locked,load_user,prog_user>

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
;
; With ring 3 programs, a block is DPL 3 (MEMF_USER) for a program that's
; being loaded for ring 3 (load_user is MEMF_USER, or 1 for ring 0; see
; psp_exec and scb_load), or otherwise, for a caller at ring 3.
;
	cmp	[prog_user],0		; ring 3 programs?
	je	ma1a			; no
	mov	al,[load_user]
	test	al,al			; loading a program?
	jnz	ma1b			; yes
	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	ma1a			; no
	mov	al,MEMF_USER		; yes, so DPL 3
ma1b:	and	al,MEMF_USER
	jz	ma1a			; not a ring 3 program block
	or	al,MEMF_LDT		; its memory goes in the session's LDT
ma1a:	test	dl,MCBTYPE_HIGH
	jz	ma2
	or	al,MEMF_HIGH
ma2:	mov	dh,al			; DH = MEMF_* flags
	push	dx
	call	far ptr DDINT_CPU	; AX = segment, DX:CX = address
	pop	si			; SI = type (and flags)
	jc	ma8
	test	si,MEMF_USER SHL 8	; DPL 3?
	jz	ma3			; no
	or	al,3			; yes, so RPL 3 too (eg, for SS)
ma3:	mov	[bp].REG_AX,ax
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
; using CPU_QUERY.  A ring 3 program can't call CPU$, so DL = 4 is how it gets
; a block's whole PMB (eg, its address, for DEBUG's DM command).
;
; Inputs:
;	CX = memory block # (0-based)
;	DL = memory block type (0 for any, 1 for free, 2 for used, or 3 for
;	the blocks that the current PSP owns; eg, for FRE(-1)), or 4 to copy
;	the block's PMB to REG_ES:REG_DI, which is all that's returned
;
; Outputs:
;	On success, carry clear:
;		REG_BX = segment
;		REG_AX = owner ID (eg, PSP; see CPU_SETBLK)
;		REG_SI:REG_DX = size (in bytes)
;		REG_ES:REG_DI -> name of process or type, if any
;	On failure, carry set (ie, no more blocks of the requested type)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	mem_query,DOS
	ASSUME	DS:DOS
	cmp	dl,4			; the block's PMB?
	jne	q0a			; no
	mov	bx,cx			; BX = PMB #
	les	di,dword ptr [bp].REG_DI; ES:DI -> the caller's buffer
	jmp	mem_pmb
q0a:	LOCK_SCB
	push	ds
	pop	es
	mov	di,offset pmb_buf	; ES:DI -> PMB buffer
	sub	si,si			; SI = owner ID to match (none)
	cmp	dl,3			; the current PSP's blocks?
	jne	q0			; no
	push	cx
	call	get_psp			; AX = PSP
	call	psp_owner		; AX = its owner ID
	pop	cx
	jc	q9			; no such block (and carry is set)
	xchg	si,ax			; SI = owner ID to match
	mov	dl,0			; DL = 0 (any block that it owns)
q0:	sub	bx,bx			; BX = PMB #
q1:	call	mem_pmb			; get PMB # BX
	jc	q9			; no more (and carry is set)
	test	si,si			; only one owner's blocks?
	jz	q1a			; no
	cmp	[pmb_buf].PMB_OWNER,si	; one of them?
	jne	q4			; no
q1a:	test	dl,dl			; any block?
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
; get_pname
;
; Copies the 8-byte name of the program whose PSP is in AX to the caller's
; buffer at ES:DI (filled with zeros if there's no program, or no block for
; it), so that a caller (eg, KILL, via scb_query) needn't treat PSP-1 as
; an MCB segment, which isn't a valid selector in protected mode.
;
; Inputs:
;	AX = PSP (zero if none)
;	ES:DI -> 8-byte buffer
;	DS = DOS
;
; Outputs:
;	ES:DI buffer filled; ES:DI advanced by 8
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	get_pname,DOS
	test	ax,ax			; is there a program?
	jz	gpn8			; no
	push	es
	push	di			; save the caller's buffer
	mov	cx,ax
	mov	dx,-1			; DX:CX = the PSP's block
	mov	bx,-1			; BX = -1 (query the block at DX:CX)
	push	ds
	pop	es
	mov	di,offset pmb_buf	; ES:DI -> our PMB buffer
	call	mem_pmb
	pop	di
	pop	es			; ES:DI -> the caller's buffer again
	jc	gpn8			; no such block, so no name
	mov	si,offset pmb_buf + PMB_NAME
	mov	cx,4
	rep	movsw			; DS:SI (our PMB) -> ES:DI (caller)
	ret
gpn8:	sub	ax,ax
	mov	cx,4
	rep	stosw			; no name, so zero the 8 bytes
	ret
ENDPROC	get_pname

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_owner
;
; Returns the owner ID of the PSP in AX, which is the owner of its own block
; (as CPU$ stores it; see CPU_SETBLK), for comparing with other blocks' owners
; (eg, from CPU_QUERY), since in protected mode a ring 3 program's PSP is an
; LDT selector, which isn't its ID.
;
; Inputs:
;	AX = PSP
;	ES:DI -> PMB buffer
;
; Outputs:
;	Carry clear if successful: AX = owner ID (and ES:DI -> the PSP's PMB)
;	Carry set if there's no such block (AX = error code)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	psp_owner,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	push	bx
	xchg	cx,ax
	mov	bx,-1
	mov	dx,bx			; DX:CX = the PSP's block (BX = -1)
	mov	ah,CPU_QUERY
	call	far ptr DDINT_CPU	; its PMB (or carry set, AX = error)
	pop	bx
	jc	po9
	mov	ax,es:[di].PMB_OWNER	; AX = its owner ID
po9:	ret
ENDPROC	psp_owner

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
; programs get it with DOS_UTL_ALIAS (see utl_alias).  When programs run at
; ring 3 (see prog_user), the alias has RPL 3 while psp_exec loads a ring 3
; program (see load_user), or for a ring 3 caller, which is how psp_exec
; knows to start the program at ring 3 (see r3_start); it also keeps the
; PCjs emulator, which takes a gate's new CPL from its selector's RPL, from
; trying to enter a ring 3 program's interrupt handler at ring 0.
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
	jc	mas9
	cmp	cs:[prog_user],0	; ring 3 programs?
	je	mas9			; no
	mov	cl,cs:[load_user]
	test	cl,cl			; loading a program (see mem_alloc)?
	jnz	mas8			; yes
	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	mas9			; no
	mov	cl,MEMF_USER
mas8:	test	cl,MEMF_USER		; for ring 3?
	jz	mas9			; no
	or	al,3			; yes, so RPL 3
mas9:	pop	dx
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
; utl_segself (AH = 27h and 28h)
;
; In real mode, a segment is its own code alias and its own selector, so
; DOS_UTL_ALIAS and DOS_UTL_MAPSEG both return the segment they're given; in
; protected mode, set_fault replaces this function with utl_alias and
; utl_mapseg (see utilpm.asm), which real mode doesn't keep.
;
; Inputs:
;	REG_BX = segment
;
; Outputs:
;	Carry clear: REG_AX = segment
;
DEFPROC	utl_segself,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ax,[bp].REG_BX
	mov	[bp].REG_AX,ax
	ret
ENDPROC	utl_segself

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
; A ring 3 program's block doesn't match, since its owner ID isn't its selector
; (see enc_owner), so programs at ring 3 don't share code; they can't, because
; an LDT selector means something else in another session's LDT, and COMMAND's
; shared code has variables (eg, CMD_REFS) that every copy must write.
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

	public	pmb_buf
pmb_buf	PMB	<>			; for CPU_QUERY

DOS	ends

	end
