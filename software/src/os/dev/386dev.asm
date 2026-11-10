;
; BASIC-DOS 80286/80386 Processor (CPU$) Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This is the first built-in driver, and the first of two CPU$ drivers (see
; cpu.inc); it stores the processor type in CPU_HWTYPE and CPU_TYPE, and on
; an 80286 or later, if protected mode is requested (by a "CPU=80286" or
; "CPU=80386" line in CONFIG.SYS, or a P at the boot message, unless an R then
; overrides it), with at least 256K of conventional memory (after any
; "MEMSIZE=" line), it enables A20, builds its PMB table, GDT, IDT, LDT, and
; TSS in the system area (the last whole 64K of conventional memory), checks
; that it can switch to protected mode and back, and stays, managing all of
; memory with its PMB table (see PMB in cpu.inc) through DDINT_CPU.  On an
; 80386 or later, it uses the 80386's features (an 80386 TSS and selectors
; beyond 64K), unless there's a "CPU=80286" line, and then it acts as it does
; on an 80286; CPU_TYPE (and SV_TYPE) say which.  Otherwise, it makes CPU_TYPE
; CPUTYPE_8086, leaves A20 off, and unloads itself, and the 8086 driver
; (x86dev.asm) stays instead.  CPU_PMODE switches to protected mode for good,
; after which CPU$ reflects interrupts to the ROM BIOS, keeps the vectors
; that drivers install in its IDT (see pm_setvec), and stops the machine on
; any other exception (see cpu_fatal).  See docs/bdtech/mmu.
;
	BIOSAPI equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc
	include	386dev.inc
FL_RESULTS	equ	FL_CARRY OR FL_ZERO OR FL_SIGN OR FL_OVFL
;
; A bit for each function that can take long enough to need interrupts on (see
; cpu_entry): GETINFO, ALLOC, FREE, MAP, QUERY, ALIAS, REALLOC, SETBLK, and
; FREEALL.
;
CPU_LONG	equ	0D6Fh

DEV	group	CODE,DATA

CODE	segment para public 'CODE'
;
; Only ddcpu_req and the start of ddcpu_init (see 386init.asm) run on an 8086
; (and use only 8086 instructions); everything else runs on an 80286 or
; later, and 386v86.asm's code, which is linked between ours and the
; initialization's, only on an 80386.
;
	EXTERNS	<ddcpu_init>,far
	EXTNEAR	<v86_func>

	.286p

	public	CPU
CPU	DDH	<offset DEV:ddcpu_end+16,,DDATTR_CHAR,offset DEV:ddcpu_init,-1,2020202024555043h>
	even
	DEFLBL	CPU_FUNCS,word
	dw	ddcpu_getinfo, ddcpu_alloc, ddcpu_free, ddcpu_map
	dw	ddcpu_unmap, ddcpu_query, ddcpu_alias, ddcpu_pmode
	dw	ddcpu_realloc, ddcpu_move, ddcpu_setblk, ddcpu_freeall
	dw	ddcpu_setlim, ddcpu_seginfo, ddcpu_rwmem, ddcpu_sysregs
	dw	ddcpu_setfault, ddcpu_setstack, ddcpu_setldt, ddcpu_v86

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
; DS addressing SYSVARS (sys_seg in real mode, or SEL_SYS in protected mode).
;
; The functions that walk or change the PMB table and LDTs can take a while, so
; if the caller had interrupts on, they run with interrupts on, too, holding a
; session lock (DDINT_UTIL is a stub until DOS is ready) that keeps any other
; session from calling us; interrupt handlers don't call those functions, and
; a caller with interrupts off (eg, a debugger) keeps them off.  Only short
; pieces of them disable interrupts (see pmb_dup and ldt_grow).
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
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
	public	sys_seg
sys_seg	dw	0			; system area segment (see ddcpu_init)

DEFPROC	cpu_entry,far
	push	ds
	push	bp
	pushf
	cli
	push	0			; (nonzero if we lock; see ce3)
	push	bx
	push	si
	push	di
	mov	bp,cs:[sys_seg]
	push	ax
	smsw	ax
	test	al,1			; protected mode?
	pop	ax
	jz	ce1			; no
	mov	bp,SEL_SYS
ce1:	mov	ds,bp
	cmp	ah,CPU_MAXFUNC		; valid function?
	ja	ce8			; no
	mov	bl,ah
	mov	bh,0
	add	bx,bx
	mov	bp,cs:[CPU_FUNCS+bx]
	mov	si,CPU_LONG
	mov	di,cx
	mov	cl,ah
	shr	si,cl
	mov	cx,di
	shr	si,1			; one that needs interrupts on?
	jnc	ce3			; no
	mov	bx,sp
	test	byte ptr ss:[bx+9],FL_INTS SHR 8; did the caller have them on?
	jz	ce3			; no
	inc	word ptr ss:[bx+6]
	push	ax
	mov	ah,DDUTL_LOCK
	call	far ptr DDINT_UTIL
	pop	ax
	sti
ce3:	pop	di
	pop	si
	pop	bx
	push	bx
	push	si
	push	di
	call	bp
	jmp	short ce9
ce8:	mov	ax,ERR_INVALID
	stc
ce9:	pop	di
	pop	si
	pop	bx
	pop	bp			; (DEC leaves carry alone, too)
	dec	bp			; did we lock?
	jnz	ce9a			; no
	pushf
	push	ax
	mov	ah,DDUTL_UNLOCK
	call	far ptr DDINT_UTIL
	pop	ax
	popf
ce9a:	mov	bp,sp
	rcr	word ptr [bp],1		; replace the caller's carry flag
	rol	word ptr [bp],1		; with ours, and restore its flags
	popf
	pop	bp
	pop	ds
	ret
ENDPROC	cpu_entry

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_getinfo (CPU_GETINFO)
;
; Outputs:
;	AL = CPU type, AH = CPUF_* flags (including CPUF_HWTYPE), DX:CX =
;	length of largest free block
;
DEFPROC	ddcpu_getinfo
	mov	ds:[SYS_VARS].SV_ARG,0	; (anywhere; see pmb_largest)
	call	pmb_largest
	mov	ax,word ptr ds:[SYS_VARS].SV_TYPE
	clc
	ret
ENDPROC	ddcpu_getinfo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_alloc (CPU_ALLOC)
;
; Allocates a block (see pmb_fit), rounding its length up to a multiple of
; 16, so that every block starts on a paragraph boundary.  In protected mode,
; it gets selectors (see map_block), unless MEMF_NONE is set; in real mode, AX
; is its segment (or zero, above 1Mb).
;
; Inputs:
;	AL = MEMF_* flags, BX = owner, SI:DI = length
;	DX:CX = address (if MEMF_AT is set)
;
; Outputs:
;	Carry clear if successful: AX = selector (or segment), DX:CX = address
;	Carry set if error: AX = error code (if ERR_NOMEMORY, DX:CX = length
;	of largest free block)
;
DEFPROC	ddcpu_alloc
	call	len_round		; is the length zero?
	jz	ca9			; yes
	mov	ds:[SYS_VARS].SV_ARG,al
	mov	ds:[SYS_VARS].SV_OWNER,bx
	call	pmb_fit			; BX -> free PMB, DX:CX = address
	jc	ca8
;
; alloc_at allocates SV_LEN bytes at DX:CX, in the free block at BX, for
; SV_OWNER, with SV_ARG's selectors (386v86.asm uses it for blocks that start
; on a page).
;
	DEFLBL	alloc_at,near
	mov	bp,ds:[SYS_VARS].SV_NPMBS
	shl	bp,5
	add	bp,SYS_PMBS + 2 * (size PMB)
	cmp	bp,ds:[SYS_VARS+SV_LDTLOW]
	ja	ca8			; no room to split a free block twice
	call	pmb_cut			; BX -> PMB at DX:CX
	call	pmb_split		; BX -> PMB of length SV_LEN
	mov	ds:[bx].PMB_TYPE,PMBTYPE_USED
	mov	ax,ds:[SYS_VARS].SV_OWNER
	call	enc_owner		; AX = its owner ID
	mov	ds:[bx].PMB_OWNER,ax
	call	blk_sel			; AX = selector (or segment)
	jnc	ca1
	call	pmb_free		; no descriptors, so free it again
	jmp	short ca8
ca1:	mov	cx,ds:[bx].PMB_ADDR.LOW
	mov	dx,ds:[bx].PMB_ADDR.HIW
	ret				; (carry is clear)
ca8:	call	pmb_largest
	mov	ax,ERR_NOMEMORY
	stc
	ret
ca9:	jmp	cpu_inval
ENDPROC	ddcpu_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_free (CPU_FREE)
;
; Frees a block allocated by CPU_ALLOC, along with its selectors.
;
; Inputs:
;	DX:CX = block
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_BADADDR)
;
DEFPROC	ddcpu_free
	call	pmb_used		; BX -> PMB
	jc	cf9
	DEFLBL	pmb_free,near		; BX -> PMB to free
	mov	ds:[bx].PMB_TYPE,PMBTYPE_FREE
	sub	ax,ax
	mov	ds:[bx].PMB_OWNER,ax
	xchg	ax,ds:[bx].PMB_CODE	; does it have a code alias?
	test	ax,ax
	jz	cf0			; no
	mov	cx,1
	call	desc_free		; yes, so free it, too
	sub	ax,ax
cf0:	push	es
	push	ds
	pop	es
	lea	di,[bx].PMB_MCBTYPE
	mov	cx,(size PMB - PMB_MCBTYPE) SHR 1
	rep	stosw			; zero the type and name
	pop	es
	xchg	ax,ds:[bx].PMB_SEL
	xchg	cx,ds:[bx].PMB_NSEL
	jcxz	cf1			; no selectors
	call	desc_free
cf1:	call	pmb_merge		; merge with the next block if free
	cmp	bx,SYS_PMBS
	je	cf8
	sub	bx,size PMB
	call	pmb_merge		; and the previous block if free
cf8:	clc
cf9:	ret
ENDPROC	ddcpu_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_freeall (CPU_FREEALL)
;
; Frees every block that BX owns (by its owner ID; see enc_owner); since
; freeing a block can merge PMBs, we start over after each one.
;
; Inputs:
;	BX = owner
;
; Outputs:
;	Carry clear
;
DEFPROC	ddcpu_freeall
	xchg	ax,bx
	call	enc_owner
	xchg	dx,ax			; DX = owner ID
fa1:	mov	bx,SYS_PMBS
	mov	si,ds:[SYS_VARS].SV_NPMBS
fa2:	cmp	ds:[bx].PMB_TYPE,PMBTYPE_USED
	jne	fa3
	cmp	ds:[bx].PMB_OWNER,dx	; does DX own this block?
	jne	fa3			; no
	push	dx
	call	pmb_free
	pop	dx
	jmp	fa1
fa3:	add	bx,size PMB
	dec	si
	jnz	fa2
	clc
	ret
cr8:	jmp	cpu_inval		; (for ddcpu_realloc)
ENDPROC	ddcpu_freeall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_realloc (CPU_REALLOC)
;
; Changes the length of a block allocated by CPU_ALLOC (rounding it up to a
; multiple of 16): a shorter block frees its end, and a longer one takes what
; it needs from the block after it, which must be free and long enough.  Its
; first selector and code alias, if any, stay the same, but they and any other
; selectors change to fit its new length (see blk_fit); a block that needs
; more selectors must have enough free descriptors after its last one.
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
	call	len_round		; is the length zero?
	jz	cr8			; yes
	call	pmb_used		; BX -> PMB
	jc	cr9
	mov	ax,ds:[SYS_VARS].SV_LEN.LOW
	mov	dx,ds:[SYS_VARS].SV_LEN.HIW
	sub	ax,ds:[bx].PMB_LEN.LOW
	sbb	dx,ds:[bx].PMB_LEN.HIW	; DX:AX = new length - old length
	jb	cr4			; shorter
	mov	cx,ax
	or	cx,dx			; the same?
	jz	cr9			; yes (and carry is clear)
	cmp	ds:[bx].PMB_SIG,PMBSIG_LAST
	je	cr7
	cmp	ds:[bx+size PMB].PMB_TYPE,PMBTYPE_FREE
	jne	cr7			; the next block isn't free
	cmp	ds:[bx+size PMB].PMB_LEN.HIW,dx
	ja	cr2
	jb	cr7
	cmp	ds:[bx+size PMB].PMB_LEN.LOW,ax
	jae	cr2			; it's long enough
cr7:	mov	cx,ds:[bx].PMB_LEN.LOW
	mov	dx,ds:[bx].PMB_LEN.HIW
	cmp	ds:[bx].PMB_SIG,PMBSIG_LAST
	je	cr7a
	cmp	ds:[bx+size PMB].PMB_TYPE,PMBTYPE_FREE
	jne	cr7a
	add	cx,ds:[bx+size PMB].PMB_LEN.LOW
	adc	dx,ds:[bx+size PMB].PMB_LEN.HIW
cr7a:	mov	ax,ERR_NOMEMORY
	stc
cr9:	ret
cr2:	mov	ds:[SYS_VARS].SV_LEN.LOW,ax
	mov	ds:[SYS_VARS].SV_LEN.HIW,dx
	call	blk_room		; are there selectors for that length?
	jc	cr9			; no
	add	bx,size PMB
	call	pmb_split		; BX -> the part of it we need
	lea	bx,[bx-size PMB]	; (LEA leaves carry alone)
	jc	cr7
	mov	ax,ds:[SYS_VARS].SV_LEN.LOW
	add	ds:[bx].PMB_LEN.LOW,ax
	mov	ax,ds:[SYS_VARS].SV_LEN.HIW
	adc	ds:[bx].PMB_LEN.HIW,ax
	call	blk_fit
	jmp	pmb_drop		; remove the PMB after BX
cr4:	call	pmb_split		; BX -> PMB of the new length
	jc	cr7
	call	blk_fit
	add	bx,size PMB
	sub	ax,ax			; (the selectors and code alias stay
	mov	ds:[bx].PMB_NSEL,ax	; with the block)
	mov	ds:[bx].PMB_CODE,ax
	jmp	pmb_free		; free the rest
ENDPROC	ddcpu_realloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_map (CPU_MAP)
;
; Maps any memory (eg, a DOS memory block or video memory) with one or more
; selectors (see pm_map); the arena isn't checked or changed.  In real mode,
; the memory must be below 1Mb, at a paragraph boundary, and AX is its
; segment.  With MEMF_REMAP (protected mode only), it changes the memory that
; a selector from CPU_MAP with MEMF_LDT maps, in any LDT (see pm_remap).
;
; Inputs:
;	AL = MEMF_* flags, DX:CX = address, SI:DI = length
;	BX = selector ID (with MEMF_REMAP)
;
; Outputs:
;	Carry clear if successful: AX = selector, CX = # of selectors, and with
;	MEMF_LDT in protected mode, DX = the selector's ID (see enc_owner)
;	Carry set if error: AX = error code
;
DEFPROC	ddcpu_map
	test	al,MEMF_REMAP		; change a selector instead?
	jnz	cm5			; yes
	mov	bx,si
	or	bx,di			; is the length zero?
	jz	cm9			; yes
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	cm1
	jmp	pm_map
cm1:	call	addr_seg		; AX = segment
	jc	cm9
	mov	cx,1
	ret
cm5:	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	cm9
	jmp	pm_remap
cm9:	jmp	cpu_inval
ENDPROC	ddcpu_map

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_unmap (CPU_UNMAP)
;
; Frees selectors returned by CPU_MAP or CPU_ALIAS (see pm_unmap); in real
; mode, there's nothing to do.
;
; Inputs:
;	BX = first selector, CX = # of selectors (0 = 1)
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_INVALID)
;
DEFPROC	ddcpu_unmap
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	cu9			; (carry is clear)
	jmp	pm_unmap
cu9:	ret
ENDPROC	ddcpu_unmap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_alias (CPU_ALIAS)
;
; Creates a selector for the same memory as an existing one, with the access
; rights that the MEMF_* flags select (see pm_alias); in real mode, a segment
; is its own alias.
;
; Inputs:
;	AL = MEMF_* flags, BX = selector (or segment) to alias
;
; Outputs:
;	Carry clear if successful: AX = selector, DX:CX = base address
;	Carry set if error: AX = error code
;
DEFPROC	ddcpu_alias
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	cl1
;
; A block's code alias (just MEMF_CODE, for the block's own selector) is
; created only once, and kept in its PMB (see pmb_free), with the same DPL
; as the block's selector (eg, DPL 3 for a ring 3 program's block).
;
	cmp	al,MEMF_CODE		; just a code alias?
	jne	cl0b			; no
	push	bx
	mov	cx,bx
	mov	dx,-1			; DX:CX = block with selector BX
	call	pmb_used		; BX -> its PMB, if any
	pop	ax			; AX = selector to alias
	jc	cl0a			; it isn't a block's
	and	al,NOT 3		; (with any RPL)
	cmp	ds:[bx].PMB_SEL,ax	; is it the block's own selector?
	jne	cl0a			; no
	cmp	ds:[bx].PMB_CODE,0	; does the block have its alias yet?
	jne	cl0			; yes
	push	bx
	xchg	bx,ax			; BX = selector to alias
	call	sel_desc		; SI -> its descriptor
	mov	al,MEMF_CODE
	test	ds:[si].DESC_ACC,ACC_DPL3	; a DPL 3 block (MEMF_USER)?
	jz	cl0c			; no
	or	al,MEMF_USER		; yes, so its alias is DPL 3 too
cl0c:	test	bl,SEL_TI		; an LDT block (a ring 3 program)?
	jz	cl0d			; no
	or	al,MEMF_LDT		; yes, so its alias is in the same LDT
cl0d:	call	pm_alias		; AX = new alias
	pop	bx
	jc	cl9
	mov	ds:[bx].PMB_CODE,ax
cl0:	mov	ax,ds:[bx].PMB_CODE
	mov	cx,ds:[bx].PMB_ADDR.LOW
	mov	dx,ds:[bx].PMB_ADDR.HIW	; DX:CX = base address
	clc
cl9:	ret
cl0a:	xchg	bx,ax			; BX = selector to alias again
	mov	al,MEMF_CODE
cl0b:	jmp	pm_alias
cl1:	mov	ax,bx
	mov	dx,bx
	mov	cl,4
	shl	bx,cl
	mov	cl,12
	shr	dx,cl
	mov	cx,bx			; DX:CX = segment * 16
	clc
	ret
ENDPROC	ddcpu_alias

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_setlim (CPU_SETLIM)
;
; Changes the length that a selector from CPU_ALLOC, CPU_MAP, or CPU_ALIAS
; covers (its limit), keeping the selector; fixed GDT selectors can't change.
; In real mode, there's nothing to do.
;
; Inputs:
;	BX = selector, SI:DI = new length (1 to 64K, or on an 80386, to
;	4G; see lim_desc)
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_INVALID)
;
DEFPROC	ddcpu_setlim
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	sl9			; (carry is clear)
	test	bl,SEL_TI		; an LDT selector?
	jnz	sl1			; yes
	cmp	bx,GDT_FIXED * 8	; a fixed GDT selector?
	jb	sl8			; yes
sl1:	push	si
	call	sel_desc		; SI -> its descriptor
	mov	bx,si
	pop	si
	jnc	lim_desc
	ret
sl8:	jmp	cpu_inval
sl9:	ret
ENDPROC	ddcpu_setlim

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; lim_desc
;
; Sets the limit of a descriptor from a length, from 1 to 64K, or on an
; 80386 (see SV_TYPE), any non-zero length, which above 1Mb uses 4K
; granularity, rounding the length down to a multiple of 4K, so that the
; descriptor never reaches beyond it; it keeps the descriptor's AVL and D/B
; bits.
;
; Inputs:
;	BX -> DESC, SI:DI = length
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_INVALID)
;
; Modifies:
;	AX (if error), CX, DX, SI, DI, BP
;
DEFPROC	lim_desc
	mov	bp,di
	mov	cx,si
	sub	bp,1
	sbb	cx,0			; CX:BP = new limit
	jc	ld8			; the length was zero
	jcxz	ld1			; the length is 64K or less
	cmp	ds:[SYS_VARS].SV_TYPE,CPUTYPE_80386
	jb	ld8			; only an 80386 can have more
	cmp	cx,10h			; is the length above 1Mb?
	jb	ld1			; no
	shr	di,12
	mov	bp,si
	shl	bp,4
	or	bp,di
	mov	cx,si
	shr	cx,12			; CX:BP = length / 4K
	sub	bp,1
	sbb	cx,0			; CX:BP = new limit, in 4K units
	or	cl,EXT_GRAN
ld1:	mov	dl,byte ptr ds:[bx].DESC_EXT
	and	dl,EXT_KEEP		; (always zero on an 80286)
	or	dl,cl
	mov	byte ptr ds:[bx].DESC_EXT,dl
	mov	ds:[bx].DESC_LIMIT,bp	; (and carry is clear)
	ret
ld8:	jmp	cpu_inval
ENDPROC	lim_desc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_seginfo (CPU_SEGINFO)
;
; A selector may be any present descriptor in the GDT (including the identity
; selectors) or the LDT, in either mode.
;
; Inputs:
;	AL = ADDR_* flags, BX = segment or selector
;
; Outputs:
;	Carry clear if successful: DX:CX = base address, AX = limit (FFFFh if
;	it's beyond 64K), or with ADDR_RIGHTS, the access rights in AL and the
;	extended byte (the 80386 limit bits 19-16 and flags) in AH
;	Carry set if the selector isn't present (AX = ERR_INVALID)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	ddcpu_seginfo
	test	al,ADDR_LDT		; an LDT # (see CPU_SETLDT)?
	jnz	sg4			; yes
	test	al,ADDR_SEL		; a selector?
	jnz	sg1			; yes
	push	ax
	test	al,ADDR_PHYS		; a physical address (BX:0000)?
	mov	dx,bx
	mov	cx,0			; DX:CX = BX:0000
	jnz	sg0			; yes
	mov	ax,16
	mul	bx			; DX:AX = the segment's address
	xchg	cx,ax
sg0:	pop	ax
	and	al,ADDR_RIGHTS
	cmp	al,1			; carry set if not ADDR_RIGHTS
	sbb	ax,ax			; AX = FFFFh (limit) or 0 (no rights)
	clc
	ret
sg1:	mov	si,bx
	and	si,NOT 7
	test	bl,SEL_TI		; an LDT selector?
	jz	sg2			; no
	cmp	si,ds:[SYS_GDT + SEL_LDTD].DESC_LIMIT	; within the LDT?
	jae	sg8			; no
	add	si,ds:[SYS_VARS].SV_LDT	; the active LDT
	jmp	short sg3
sg2:	cmp	si,GDT_LIMIT		; is it within the GDT?
	ja	sg8			; no
	add	si,SYS_GDT
sg3:	test	ds:[si].DESC_ACC,ACC_PRESENT
	jz	sg8
	call	desc_addr		; DX:CX = base address
	test	al,ADDR_RIGHTS		; (carry is clear)
	mov	ax,word ptr ds:[si].DESC_ACC
	jnz	sg9
	mov	ax,ds:[si].DESC_LIMIT
	test	byte ptr ds:[si].DESC_EXT,EXT_GRAN OR EXT_LIMIT
	jz	sg9			; the limit is 64K or less
	mov	ax,0FFFFh		; (and carry is clear)
sg9:	ret
sg4:	cmp	bx,LDT_SESSIONS		; a valid LDT #?
	jae	sg8			; no
	add	bx,bx			; BX = LDT # * 2
	mov	cx,ds:[SYS_VARS+SV_LDTS+bx]	; CX = the LDT's offset
	mov	ax,ds:[SYS_VARS+SV_LDTTOP+bx]	; AX = where it ends
	sub	ax,cx			; AX = its length (and carry is clear)
	dec	ax			; AX = its limit
	mov	dl,ds:[SYS_GDT + SEL_LDTD].DESC_BASE16
	mov	dh,0			; DX:CX = its base
	ret
sg8:	jmp	cpu_inval
ENDPROC	ddcpu_seginfo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_rwmem (CPU_RWMEM)
;
; In protected mode, we copy through SEL_TMP2 (see pm_ptr), and then restore
; its descriptor, in case we interrupted something that was using it (eg,
; CPU_MOVE).  In real mode, the bytes must start below 1Mb.
;
; Inputs:
;	AL = ADDR_* flags, BX:SI = address, CX = length
;	ES:DI -> buffer
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_INVALID)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	ddcpu_rwmem
	push	ax
	push	cx
	push	si
	call	ddcpu_seginfo		; DX:CX = base, AX = limit
	pop	si			; SI = offset
	pop	bp			; BP = length
	pop	bx			; BL = ADDR_* flags
	jc	rw9
	sub	ax,si			; AX = limit - offset
	jb	sg8			; the offset is beyond the limit
	test	bp,bp			; anything to copy?
	jz	rw9			; no (and carry is clear)
	dec	bp
	cmp	ax,bp			; is the last byte within the limit?
	jb	sg8			; no
	inc	bp
	add	cx,si
	adc	dx,0			; DX:CX = address of the bytes
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jnz	rw2
	cmp	dx,10h			; below 1Mb?
	jae	sg8			; no
	mov	si,cx
	and	si,0Fh			; SI = offset
	mov	ax,cx
	mov	cl,4
	shr	ax,cl
	mov	cl,12
	shl	dx,cl
	or	ax,dx			; AX = segment
	jmp	short rw4
rw2:	mov	si,SYS_GDT + SEL_TMP2
	push	ds:[si].DESC_LIMIT
	push	ds:[si].DESC_BASE
	push	word ptr ds:[si].DESC_BASE16
	push	ds:[si].DESC_EXT
	xchg	ax,cx			; DX:AX = address
	push	bx
	mov	bx,SEL_TMP2
	call	pm_ptr			; BX = selector, AX = offset (zero)
	xchg	si,ax			; SI = offset
	xchg	ax,bx			; AX = selector
	pop	bx
rw4:	mov	cx,bp			; CX = length
	push	ds
	push	es
	mov	ds,ax			; DS:SI -> the bytes
	test	bl,ADDR_WRITE		; writing them?
	jz	rw5			; no
	push	es
	push	ds
	pop	es
	pop	ds
	xchg	si,di			; DS:SI -> buffer, ES:DI -> the bytes
rw5:	cld
	rep	movsb
	pop	es
	pop	ds			; DS = SYSVARS again
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	rw9			; (carry is clear)
	mov	si,SYS_GDT + SEL_TMP2
	pop	ds:[si].DESC_EXT
	pop	word ptr ds:[si].DESC_BASE16
	pop	ds:[si].DESC_BASE
	pop	ds:[si].DESC_LIMIT	; (carry is still clear)
rw9:	ret
ENDPROC	ddcpu_rwmem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_sysregs (CPU_SYSREGS)
;
; Inputs:
;	ES:DI -> 12-byte buffer
;
; Outputs:
;	Carry clear: GDTR and IDTR stored at ES:DI, AX = MSW, CX = LDTR, and
;	DX = TR (both zero in real mode, where they can't be read)
;
DEFPROC	ddcpu_sysregs
	sgdt	qword ptr es:[di]
	sidt	qword ptr es:[di+6]
	sub	cx,cx
	cwd				; (AH is our function number)
	smsw	ax
	test	al,1			; protected mode?
	jz	sr9			; no (and carry is clear)
	sldt	cx
	str	dx
sr9:	ret
ENDPROC	ddcpu_sysregs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_setfault (CPU_SETFAULT) and ddcpu_setstack (CPU_SETSTACK)
;
; Inputs:
;	DX:CX = fault handler (0:0 for none; see to_fault), or the ring 0
;	stack (SS:SP) for interrupts from ring 3 (see SYS_TSS)
;
; Outputs:
;	Carry clear: DX:CX = previous handler (or stack)
;
; Modifies:
;	BX (which cpu_entry restores), CX, DX
;
DEFPROC	ddcpu_setfault
	mov	bx,SYS_VARS + SV_FAULT
	mov	si,2			; SI = offset of the segment (.SEG)
	jmp	short sf1
	DEFLBL	ddcpu_setstack,near
	mov	si,ds:[SYS_VARS].SV_TSSSP0
	lea	bx,[si+SYS_TSS]		; (on an 80386, ESP0 bits 31-16 stay 0)
sf1:	xchg	cx,ds:[bx]
	xchg	dx,ds:[bx+si]
	clc
	ret
ENDPROC	ddcpu_setfault

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_setldt (CPU_SETLDT)
;
; Makes LDT # AL the active one, so that its selectors (MEMF_LDT) are the ones
; the descriptor helpers allocate and resolve (see SV_LDT), and the LDTR's
; descriptor (SEL_LDTD) is repointed at it.  DOS assigns each session an LDT
; (sessions can share one), and makes it active whenever the session runs.  In
; real mode there are no LDTs, so there's nothing to do.
;
; Inputs:
;	AL = LDT #
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, CX, DX (and BX, which cpu_entry restores)
;
DEFPROC	ddcpu_setldt
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM	; protected mode?
	jz	stl9			; no, so nothing to do
	mov	ds:[SYS_VARS].SV_LDTNUM,al	; (see enc_owner)
	mov	bl,al
	mov	bh,0
	add	bx,bx			; BX = LDT # * 2
	mov	ax,ds:[SYS_VARS+SV_LDTS+bx]	; AX = the LDT's offset
	mov	cx,ds:[SYS_VARS+SV_LDTTOP+bx]	; CX = where it ends
	call	ldt_load
stl9:	clc
	ret
ENDPROC	ddcpu_setldt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ldt_load
;
; Makes the LDT at AX the active one, and reloads the LDTR.
;
; Inputs:
;	AX = the LDT's offset, CX = where it ends
;
; Modifies:
;	AX, CX
;
DEFPROC	ldt_load
	mov	ds:[SYS_VARS].SV_LDT,ax
	sub	cx,ax			; CX = its length
	sub	cx,1
	adc	cx,0			; CX = its limit (0 if it's empty)
	mov	ds:[SYS_GDT + SEL_LDTD].DESC_LIMIT,cx
	mov	ds:[SYS_GDT + SEL_LDTD].DESC_BASE,ax
	mov	ax,SEL_LDTD
	lldt	ax			; reload LDTR from its new descriptor
	ret
ENDPROC	ldt_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_pmode (CPU_PMODE)
;
; Switches to protected mode (see pm_pmode), if this is an 80286 or later
; and we passed our self-test.
;
DEFPROC	ddcpu_pmode
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PMOK
	jz	cpu_inval
	jmp	pm_pmode
ENDPROC	ddcpu_pmode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_query (CPU_QUERY)
;
; Inputs:
;	BX = PMB # (0 for the first), or -1 for the block at DX:CX
;	ES:DI -> buffer for PMB
;
; Outputs:
;	Carry clear if successful (PMB copied to ES:DI)
;	Carry set if no such PMB (AX = ERR_INVALID, or ERR_BADADDR)
;
DEFPROC	ddcpu_query
	cmp	bx,-1				; the block at DX:CX?
	jne	cq1				; no
	call	pmb_used			; BX -> PMB
	jnc	cq2
	ret
cq1:	cmp	bx,ds:[SYS_VARS].SV_NPMBS	; is the PMB # valid?
	jae	cpu_inval			; no
	call	pmb_ptr				; BX -> PMB
cq2:	mov	si,bx
	mov	cx,(size PMB) SHR 1
	rep	movsw
	clc
	ret
	DEFLBL	cpu_inval,near
	mov	ax,ERR_INVALID
	stc
	ret
ENDPROC	ddcpu_query

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_v86 (CPU_V86)
;
; V86 machines (see v86.inc) need protected mode with the 80386's features,
; and only then is their code (see 386v86.asm) still loaded.
;
DEFPROC	ddcpu_v86
	cmp	ds:[SYS_VARS].SV_TYPE,CPUTYPE_80386	; 80386 features?
	jne	cpu_inval		; no
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM	; and protected mode?
	jz	cpu_inval		; no
	jmp	v86_func
ENDPROC	ddcpu_v86

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_setblk (CPU_SETBLK)
;
; Sets the owner (as its owner ID; see enc_owner), type, and name in a
; block's PMB.
;
; Inputs:
;	DX:CX = block, AL = MCBTYPE_*, BX = owner
;	ES:SI -> name (8 characters), or SI = 0 for none
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_BADADDR)
;
DEFPROC	ddcpu_setblk
	push	bx
	push	ax
	call	pmb_used		; BX -> PMB
	pop	cx			; CL = type
	pop	ax			; AX = owner
	jc	bk9
	call	enc_owner		; AX = its owner ID
	mov	ds:[bx].PMB_OWNER,ax
	mov	ds:[bx].PMB_MCBTYPE,cl
	lea	di,[bx].PMB_NAME
	mov	cx,size PMB_NAME
	push	es
	push	ds
	push	es
	pop	ds			; DS:SI -> name
	pop	es			; ES:DI -> PMB_NAME
	mov	al,0
	test	si,si			; is there a name?
	jz	bk1			; no
	rep	movsb
bk1:	rep	stosb			; (zero the rest, if any)
;
; A filename can have any byte in it, but this one must never look like a
; present descriptor's access byte (see SYS_GDT).
;
	and	byte ptr es:[bx].PMB_NAME+7,7Fh	; (and clears carry)
	pop	es
bk9:	ret
ENDPROC	ddcpu_setblk

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
	mov	ax,es:[bx].MV_SRC.LOW
	mov	ds:[SYS_VARS].SV_SRC.LOW,ax
	mov	ax,es:[bx].MV_SRC.HIW
	mov	ds:[SYS_VARS].SV_SRC.HIW,ax
	mov	ax,es:[bx].MV_DST.LOW
	mov	ds:[SYS_VARS].SV_DST.LOW,ax
	mov	ax,es:[bx].MV_DST.HIW
	mov	ds:[SYS_VARS].SV_DST.HIW,ax
	mov	ax,es:[bx].MV_LEN.LOW
	mov	ds:[SYS_VARS].SV_LEN.LOW,ax
	mov	ax,es:[bx].MV_LEN.HIW
	mov	ds:[SYS_VARS].SV_LEN.HIW,ax
	mov	ax,ds:[SYS_VARS].SV_SRC.LOW
	mov	dx,ds:[SYS_VARS].SV_SRC.HIW
	sub	bp,bp			; BP = 0 to copy forward
	cmp	dx,ds:[SYS_VARS].SV_DST.HIW
	ja	mv1
	jb	mv0b
	cmp	ax,ds:[SYS_VARS].SV_DST.LOW
	jae	mv1
mv0b:	inc	bp			; BP = 1 to copy backward
mv1:	mov	ax,ds			; AX = SYSVARS segment (or selector)
	mov	cx,8000h		; CX = up to 32K
	cmp	ds:[SYS_VARS].SV_LEN.HIW,0
	jne	mv2
	cmp	cx,ds:[SYS_VARS].SV_LEN.LOW
	jbe	mv2
	mov	cx,ds:[SYS_VARS].SV_LEN.LOW
	jcxz	mv9			; nothing left (and carry is clear)
mv2:	sub	ds:[SYS_VARS].SV_LEN.LOW,cx
	sbb	ds:[SYS_VARS].SV_LEN.HIW,0
	mov	si,SYS_VARS + SV_SRC
	call	mv_ptr			; SI = source offset, BX = its segment
	push	bx
	push	si
	mov	si,SYS_VARS + SV_DST
	call	mv_ptr			; SI = dest offset, BX = its segment
	mov	di,si
	pop	si
	mov	es,bx
	pop	ds
	test	bp,bp			; backward?
	jz	mv3			; no
	add	si,cx
	dec	si
	add	di,cx
	dec	di
	std
mv3:	rep	movsb
	cld
	mov	ds,ax			; DS = SYSVARS again
	jmp	mv1
mv9:	pop	es
	pop	ds
	ret				; (carry is clear)
ENDPROC	ddcpu_move

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mv_ptr
;
; Returns a far pointer to the next CX bytes to copy from (or to) the address
; at DS:SI (SV_SRC or SV_DST), which is advanced past them if copying forward
; (BP = 0); if copying backward, they're the last CX bytes of the block left
; to copy (SV_LEN has already been reduced by CX).
;
; Inputs:
;	DS:SI -> address, CX = # of bytes, BP = direction (0 = forward)
;
; Outputs:
;	BX:SI -> those bytes (BX = segment or selector)
;
; Modifies:
;	BX, DX, SI
;
DEFPROC	mv_ptr
	push	ax
	mov	ax,[si].LOW
	mov	dx,[si].HIW		; DX:AX = address
	test	bp,bp
	jnz	mp1
	add	[si].LOW,cx
	adc	[si].HIW,0
	jmp	short mp2
mp1:	add	ax,ds:[SYS_VARS].SV_LEN.LOW
	adc	dx,ds:[SYS_VARS].SV_LEN.HIW
mp2:	mov	bx,SEL_TMP
	cmp	si,SYS_VARS + SV_SRC
	jne	mp3
	mov	bx,SEL_TMP2
mp3:	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	mp4
	call	pm_ptr			; BX = selector, AX = offset
	jmp	short mp5
mp4:	mov	bx,ax
	and	ax,0Fh			; AX = offset
	push	cx
	mov	cl,4
	shr	bx,cl
	mov	cl,12
	shl	dx,cl
	or	bx,dx			; BX = segment
	pop	cx
mp5:	xchg	si,ax			; SI = offset
	pop	ax
	ret
ENDPROC	mv_ptr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; blk_sel
;
; Gives the block at BX a selector (in protected mode, unless MEMF_NONE is
; set in SV_ARG), or returns its segment (in real mode).
;
; Inputs:
;	BX -> PMB
;
; Outputs:
;	Carry clear if successful: AX = selector (or segment)
;	Carry set if there are no free descriptors
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	blk_sel
	mov	cx,ds:[bx].PMB_ADDR.LOW
	mov	dx,ds:[bx].PMB_ADDR.HIW
	sub	ax,ax
	test	ds:[SYS_VARS].SV_ARG,MEMF_NONE
	jnz	bs9			; (carry is clear)
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jnz	bs1
	call	addr_seg		; AX = segment
	jnc	bs9
	sub	ax,ax			; (none above 1Mb)
	ret
bs1:	push	bx
	push	bp
	mov	al,ds:[SYS_VARS].SV_ARG
	mov	di,ds:[bx].PMB_LEN.LOW
	mov	si,ds:[bx].PMB_LEN.HIW
	call	map_block		; AX = selector, CX = # of selectors
	pop	bp
	pop	bx
	jc	bs9
	mov	ds:[bx].PMB_SEL,ax
	mov	ds:[bx].PMB_NSEL,cx
bs9:	ret
ENDPROC	blk_sel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; blk_room
;
; Checks that the block at BX can have the selectors that a longer length
; needs (see map_block).  A block's selectors are consecutive, and the ones it
; has can't change, so any more must be the descriptors after its last one.
;
; Inputs:
;	BX -> PMB, SI:DI = new length
;
; Outputs:
;	Carry clear if successful
;	Carry set if not: AX = ERR_NOMEMORY, DX:CX = the longest it could be
;
; Modifies:
;	AX, CX, DX, SI, DI, BP
;
DEFPROC	blk_room
	mov	bp,ds:[bx].PMB_NSEL	; BP = # of selectors it has
	test	bp,bp			; (clears carry)
	jz	br9			; none, so it doesn't need any
	call	len_sels		; CX = # of selectors it needs
	mov	di,cx
	sub	di,bp			; DI = # more that it needs
	jbe	br8			; none
	push	bx
	mov	ax,bp
	shl	ax,3
	add	ax,ds:[bx].PMB_SEL
	xchg	bx,ax			; BX = the selector after its last one
br1:	call	sel_desc		; is it in use?
	jnc	br7			; yes
	cmp	cx,dx			; is it past the end of its table?
	jae	br6			; yes
	add	bx,size DESC
	inc	bp
	dec	di			; does it need any more?
	jnz	br1			; yes
	pop	bx
br8:	clc
br9:	ret
br6:	test	bl,SEL_TI		; in an LDT?
	jz	br7			; no
	mov	cx,di
	call	ldt_grow		; yes, so it can have more
	jnc	br1
br7:	pop	bx
	mov	dx,bp
	sub	cx,cx			; DX:CX = BP selectors' worth of memory
	mov	ax,ERR_NOMEMORY
	stc
	ret
ENDPROC	blk_room

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; blk_fit
;
; Makes the selectors of the block at BX fit its new length, so that they reach
; all of the block and none of what follows it: selectors it no longer needs
; are freed, new ones (see blk_room) get its first selector's access rights,
; and all of their limits are set, along with its code alias's, which covers
; the same memory as its first selector.
;
; Inputs:
;	BX -> PMB
;
; Modifies:
;	AX, CX, DX, SI, DI, BP
;
DEFPROC	blk_fit
	mov	bp,ds:[bx].PMB_NSEL	; BP = # of selectors it has
	test	bp,bp
	jz	bf9			; none
	push	bx
	mov	di,ds:[bx].PMB_LEN.LOW
	mov	si,ds:[bx].PMB_LEN.HIW	; SI:DI = its length
	call	len_sels		; CX = # of selectors it needs
	mov	ds:[bx].PMB_NSEL,cx
	sub	bp,cx			; BP = # that it no longer needs
	jbe	bf1			; none
	mov	ax,cx
	shl	ax,3
	add	ax,ds:[bx].PMB_SEL	; AX = the first of them
	mov	cx,bp
	call	desc_free
bf1:	mov	bx,ds:[bx].PMB_SEL
	call	sel_desc		; SI -> its first descriptor
	pop	bx
	push	bx
	push	si
	mov	al,ds:[si].DESC_ACC
	mov	cx,ds:[bx].PMB_NSEL
	push	cx
bf2:	mov	ds:[si].DESC_ACC,al
	add	si,size DESC
	loop	bf2
	pop	cx
	mov	bp,ds:[bx].PMB_ADDR.LOW
	mov	dx,ds:[bx].PMB_ADDR.HIW	; DX:BP = its address
	mov	di,ds:[bx].PMB_LEN.LOW
	mov	si,ds:[bx].PMB_LEN.HIW	; SI:DI = its length
	pop	bx
	push	bx
	call	desc_fill		; (BX -> its first descriptor)
	pop	si
	pop	bx
	push	bx
	mov	ax,ds:[si].DESC_LIMIT	; AX = its first selector's limit
	mov	bx,ds:[bx].PMB_CODE
	test	bx,bx			; does it have a code alias?
	jz	bf8			; no
	call	sel_desc		; SI -> its code alias's descriptor
	mov	ds:[si].DESC_LIMIT,ax
bf8:	pop	bx
bf9:	ret
ENDPROC	blk_fit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addr_seg
;
; Inputs:
;	DX:CX = address
;
; Outputs:
;	Carry clear if it's below 1Mb and a multiple of 16: AX = its segment
;
; Modifies:
;	AX
;
DEFPROC	addr_seg
	cmp	dx,10h
	cmc
	jc	as9			; it's not below 1Mb
	test	cl,0Fh
	stc
	jnz	as9			; it's not a multiple of 16
	push	cx
	push	dx
	mov	ax,cx
	mov	cl,4
	shr	ax,cl
	mov	cl,12
	shl	dx,cl
	or	ax,dx			; AX = segment (and carry is clear)
	pop	dx
	pop	cx
as9:	ret
ENDPROC	addr_seg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; len_round
;
; Rounds the length in SI:DI up to a multiple of 16, and stores it in SV_LEN.
;
; Outputs:
;	SI:DI = SV_LEN = length; zero flag set if it's zero
;
DEFPROC	len_round
	add	di,15
	adc	si,0
	and	di,0FFF0h
	mov	ds:[SYS_VARS].SV_LEN.LOW,di
	mov	ds:[SYS_VARS].SV_LEN.HIW,si
	push	si
	or	si,di
	pop	si
	ret
ENDPROC	len_round

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_fit
;
; Finds where to allocate a block of length SV_LEN: at DX:CX, with MEMF_AT
; (that memory must be free); otherwise, the first free block that's long
; enough, or with MEMF_HIGH, the top of the last one, anywhere in memory, or
; below 1Mb with MEMF_LOW.
;
; Inputs:
;	AL = MEMF_* flags, DX:CX = address (MEMF_AT only)
;
; Outputs:
;	Carry clear if successful: BX -> free PMB, DX:CX = address in it
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	pmb_fit
	test	al,MEMF_AT
	jz	pf1
	call	pmb_find		; BX -> PMB containing DX:CX
	jc	pf0
	cmp	ds:[bx].PMB_TYPE,PMBTYPE_FREE
	stc
	jne	pf0			; it isn't free
	mov	si,ds:[bx].PMB_ADDR.LOW
	mov	di,ds:[bx].PMB_ADDR.HIW
	add	si,ds:[bx].PMB_LEN.LOW
	adc	di,ds:[bx].PMB_LEN.HIW	; DI:SI = end of the free block
	sub	si,cx
	sbb	di,dx			; DI:SI = room after DX:CX
	sub	si,ds:[SYS_VARS].SV_LEN.LOW
	sbb	di,ds:[SYS_VARS].SV_LEN.HIW
pf0:	ret				; carry set if it doesn't fit
pf1:	mov	ah,al
	mov	bx,SYS_PMBS
	mov	si,ds:[SYS_VARS].SV_NPMBS
	sub	di,di			; DI -> PMB found (none yet)
pf2:	test	ah,MEMF_LOW		; must it be below 1Mb?
	jz	pf2a			; no
	cmp	ds:[bx].PMB_ADDR.HIW,10h; is this block below 1Mb?
	jae	pf5			; no (and neither are the rest)
pf2a:	cmp	ds:[bx].PMB_TYPE,PMBTYPE_FREE
	jne	pf4
	mov	cx,ds:[SYS_VARS].SV_LEN.HIW
	cmp	ds:[bx].PMB_LEN.HIW,cx
	ja	pf3
	jb	pf4
	mov	cx,ds:[SYS_VARS].SV_LEN.LOW
	cmp	ds:[bx].PMB_LEN.LOW,cx
	jb	pf4			; it's not long enough
pf3:	mov	di,bx
	test	ah,MEMF_HIGH		; look for the last one?
	jz	pf5			; no
pf4:	add	bx,size PMB
	dec	si
	jnz	pf2
pf5:	mov	bx,di
	test	bx,bx			; found one?
	jz	pf8			; no
	mov	cx,ds:[bx].PMB_ADDR.LOW
	mov	dx,ds:[bx].PMB_ADDR.HIW
	test	ah,MEMF_HIGH
	jz	pf9			; (carry is clear)
	add	cx,ds:[bx].PMB_LEN.LOW
	adc	dx,ds:[bx].PMB_LEN.HIW
	sub	cx,ds:[SYS_VARS].SV_LEN.LOW
	sbb	dx,ds:[SYS_VARS].SV_LEN.HIW
	ret				; (carry is clear)
pf8:	stc
pf9:	ret
ENDPROC	pmb_fit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_find
;
; Inputs:
;	DX:CX = address
;
; Outputs:
;	Carry clear if successful: BX -> PMB containing it
;
; Modifies:
;	AX, BX, SI, DI
;
DEFPROC	pmb_find
	mov	bx,SYS_PMBS
	mov	si,ds:[SYS_VARS].SV_NPMBS
fd1:	mov	ax,ds:[bx].PMB_ADDR.LOW
	mov	di,ds:[bx].PMB_ADDR.HIW
	add	ax,ds:[bx].PMB_LEN.LOW
	adc	di,ds:[bx].PMB_LEN.HIW	; DI:AX = end of this block
	cmp	dx,di
	jb	fd9
	ja	fd2
	cmp	cx,ax
	jb	fd9			; it's below the end
fd2:	add	bx,size PMB
	dec	si
	jnz	fd1
	stc
	ret
fd9:	clc
	ret
ENDPROC	pmb_find

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_used
;
; Finds the block that CPU_ALLOC returned at DX:CX (or with DX = -1, the block
; whose selector or segment is CX).
;
; Outputs:
;	Carry clear if successful: BX -> PMB
;	Carry set if error: AX = ERR_BADADDR
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	pmb_used
	push	si
	push	di
	cmp	dx,-1			; is CX a selector (or segment)?
	jne	pu1			; no
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	pu0
;
; A selector that isn't in use has no block, even though an empty descriptor
; (eg, the null selector's) has base address zero, where the first block is.
;
	mov	bx,cx
	call	sel_desc		; SI -> its descriptor
	jc	pu2			; it isn't in use
	call	desc_addr		; DX:CX = its base address
	jmp	short pu1
pu0:	mov	dx,cx
	shl	cx,4
	shr	dx,12			; DX:CX = the segment's address
pu1:	call	pmb_find		; BX -> PMB containing DX:CX
pu2:	pop	di
	pop	si
	jc	pu8
	cmp	ds:[bx].PMB_ADDR.LOW,cx
	jne	pu8
	cmp	ds:[bx].PMB_ADDR.HIW,dx
	jne	pu8			; DX:CX isn't the start of a block
	cmp	ds:[bx].PMB_TYPE,PMBTYPE_USED
	je	pu9			; (carry is clear)
pu8:	mov	ax,ERR_BADADDR
	stc
pu9:	ret
ENDPROC	pmb_used

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; enc_owner
;
; Returns the owner ID that a block's PMB_OWNER holds for an owner.  In
; protected mode, an LDT selector (a ring 3 program's PSP) becomes 80h plus
; the active LDT # (see CPU_SETLDT) in AH and its LDT index in AL, so that it's
; unique even though a program with another LDT can have the same selector,
; and so that it's above MCBOWNER_SYSTEM, like a PSP segment (see MEM and
; DEBUG's DM).  The same ID names a selector from CPU_MAP in any LDT.  Any
; other owner (a segment, a GDT selector, or the system) is
; its own ID.
;
; Inputs:
;	AX = owner
;
; Outputs:
;	AX = owner ID
;
DEFPROC	enc_owner
	test	al,SEL_TI		; an LDT selector?
	jz	eo9			; no
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	eo9			; no (a real-mode segment)
	shr	ax,3			; AL = its LDT index (and AH = 0)
	mov	ah,ds:[SYS_VARS].SV_LDTNUM
	or	ah,80h			; AH = 80h + its LDT #
eo9:	ret
ENDPROC	enc_owner

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_largest
;
; Only blocks below 1Mb count if MEMF_LOW is set in SV_ARG (ie, for a
; CPU_ALLOC that had to be there).
;
; Outputs:
;	DX:CX = length of the largest free block (zero if none)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	pmb_largest
	sub	cx,cx
	sub	dx,dx
	mov	bx,SYS_PMBS
	mov	si,ds:[SYS_VARS].SV_NPMBS
pl1:	cmp	ds:[bx].PMB_TYPE,PMBTYPE_FREE
	jne	pl3
	test	ds:[SYS_VARS].SV_ARG,MEMF_LOW
	jz	pl1a			; any block counts
	cmp	ds:[bx].PMB_ADDR.HIW,10h
	jae	pl3			; this one is above 1Mb
pl1a:	mov	ax,ds:[bx].PMB_LEN.HIW
	cmp	ax,dx
	jb	pl3
	ja	pl2
	cmp	ds:[bx].PMB_LEN.LOW,cx
	jbe	pl3
pl2:	mov	dx,ax
	mov	cx,ds:[bx].PMB_LEN.LOW
pl3:	add	bx,size PMB
	dec	si
	jnz	pl1
	ret
ENDPROC	pmb_largest

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_cut
;
; If DX:CX is after the start of the block at BX, splits it in two there.
;
; Inputs:
;	BX -> PMB, DX:CX = address in it
;
; Outputs:
;	BX -> PMB that starts at DX:CX
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	pmb_cut
	sub	cx,ds:[bx].PMB_ADDR.LOW
	sbb	dx,ds:[bx].PMB_ADDR.HIW	; DX:CX = length of the first part
	mov	ax,cx
	or	ax,dx			; is it zero?
	jz	pc9			; yes
	call	pmb_dup
	mov	ds:[bx].PMB_LEN.LOW,cx
	mov	ds:[bx].PMB_LEN.HIW,dx
	add	bx,size PMB
	jmp	short pmb_rest		; the second part is the rest
pc9:	ret
ENDPROC	pmb_cut

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_split
;
; If the block at BX is longer than SV_LEN, splits it in two, so that the
; first is SV_LEN long.
;
; Inputs:
;	BX -> PMB, at least SV_LEN long
;
; Outputs:
;	Carry clear if successful (BX -> PMB of length SV_LEN)
;	Carry set if the PMB table is full
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	pmb_split
	mov	cx,ds:[SYS_VARS].SV_LEN.LOW
	mov	dx,ds:[SYS_VARS].SV_LEN.HIW
	cmp	ds:[bx].PMB_LEN.LOW,cx
	jne	ps1
	cmp	ds:[bx].PMB_LEN.HIW,dx
	je	pc9			; exact fit (and carry is clear)
ps1:	call	pmb_dup
	jc	pc9
	mov	ds:[bx].PMB_LEN.LOW,cx
	mov	ds:[bx].PMB_LEN.HIW,dx
	push	bx
	add	bx,size PMB
	call	pmb_rest
	pop	bx
	ret
ENDPROC	pmb_split

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_rest
;
; Moves the start of the block at BX (a copy of the block before it) past the
; length of the block before it.
;
; Inputs:
;	BX -> PMB, DX:CX = length of the block before it
;
; Outputs:
;	Carry clear
;
DEFPROC	pmb_rest
	add	ds:[bx].PMB_ADDR.LOW,cx
	adc	ds:[bx].PMB_ADDR.HIW,dx
	sub	ds:[bx].PMB_LEN.LOW,cx
	sbb	ds:[bx].PMB_LEN.HIW,dx
	clc
	ret
ENDPROC	pmb_rest

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_dup
;
; Duplicates the PMB at BX, by moving it and all the PMBs after it up one
; entry, and makes the first copy PMBSIG_NEXT.
;
; Inputs:
;	BX -> PMB
;
; Outputs:
;	Carry clear if successful, set if the PMB table is full
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	pmb_dup
	call	pmb_end
	add	ax,size PMB
	cmp	ds:[SYS_VARS+SV_LDTLOW],ax
	jb	pd9			; (carry is set) the table is full
	push	cx
	push	es
	push	ds
	pop	es
	call	pmb_end			; AX -> end of the PMB table
	inc	ds:[SYS_VARS].SV_NPMBS
	mov	si,ax
	dec	si
	dec	si			; SI -> last word of the table
	lea	di,[si+size PMB]
	sub	ax,bx
	shr	ax,1			; AX = # of words to move
;
; Moving them takes the direction flag, which an interrupt handler mustn't see
; set, so interrupts are off (if they were on) for a short piece at a time.
;
pd1:	mov	cx,64			; (at about 4 clocks a word)
	cmp	ax,cx
	jae	pd2
	mov	cx,ax
pd2:	sub	ax,cx
	pushf
	cli
	std
	rep	movsw
	cld
	popf
	test	ax,ax
	jnz	pd1
	pop	es
	pop	cx
	mov	ds:[bx].PMB_SIG,PMBSIG_NEXT
pd9:	ret
ENDPROC	pmb_dup

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_merge
;
; If the block at BX and the block after it are both free, merges them by
; adding the second length to the first and removing the second PMB.
;
; Inputs:
;	BX -> PMB
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	pmb_merge
	cmp	ds:[bx].PMB_TYPE,PMBTYPE_FREE
	jne	pm9
	cmp	ds:[bx].PMB_SIG,PMBSIG_LAST
	je	pm9
	cmp	ds:[bx+size PMB].PMB_TYPE,PMBTYPE_FREE
	jne	pm9
	mov	ax,ds:[bx+size PMB].PMB_LEN.LOW
	add	ds:[bx].PMB_LEN.LOW,ax
	mov	ax,ds:[bx+size PMB].PMB_LEN.HIW
	adc	ds:[bx].PMB_LEN.HIW,ax
	DEFLBL	pmb_drop,near		; remove the PMB after BX
	mov	al,ds:[bx+size PMB].PMB_SIG
	mov	ds:[bx].PMB_SIG,al
	push	es
	push	ds
	pop	es
	call	pmb_end			; AX -> end of the PMB table
	dec	ds:[SYS_VARS].SV_NPMBS
	lea	di,[bx+size PMB]
	lea	si,[di+size PMB]
	mov	cx,ax
	sub	cx,si
	shr	cx,1			; CX = # of words to move
	rep	movsw
	pop	es
pm9:	clc
	ret
ENDPROC	pmb_merge

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_end and pmb_ptr
;
; Inputs:
;	BX = PMB # (pmb_ptr only)
;
; Outputs:
;	pmb_end: AX -> end of the PMB table (SV_NPMBS entries)
;	pmb_ptr: BX -> that PMB
;
DEFPROC	pmb_end
	push	bx
	mov	bx,ds:[SYS_VARS].SV_NPMBS
	call	pmb_ptr
	xchg	ax,bx
	pop	bx
	ret
ENDPROC	pmb_end

DEFPROC	pmb_ptr
	shl	bx,5
	ASSERT	<size PMB>,EQ,32
	add	bx,SYS_PMBS
	ret
ENDPROC	pmb_ptr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_map (CPU_MAP in protected mode)
;
; Inputs:
;	AL = MEMF_* flags, DX:CX = address, SI:DI = length (non-zero)
;
; Outputs:
;	Carry clear if successful: AX = selector, CX = # of selectors, and DX =
;	its ID, if it's an LDT selector (see enc_owner)
;	Carry set if error: AX = ERR_NOMEMORY
;
DEFPROC	pm_map
	call	map_block
	jc	pmp8
	push	ax
	call	enc_owner		; AX = its ID (with MEMF_LDT)
	xchg	dx,ax			; (and carry is clear)
	pop	ax
	ret
pmp8:	mov	ax,ERR_NOMEMORY
	ret
ENDPROC	pm_map

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_remap (CPU_MAP with MEMF_REMAP)
;
; Changes the memory that an LDT selector from CPU_MAP maps, in whichever LDT
; its ID names (eg, so that a driver can move a console's video memory, or
; take it away, while the console isn't the one on the screen); a length of
; zero makes it not present, and a program that loads it waits until it's
; present again (see SELID_WAIT).  A segment register that already holds the
; selector keeps what it had until the selector is loaded again.
;
; Inputs:
;	BX = selector ID, DX:CX = address, SI:DI = length (64K or less, or
;	on an 80386, any length; see lim_desc)
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_INVALID)
;
DEFPROC	pm_remap
	call	id_desc			; BX -> the selector's descriptor
	jc	pr9
	mov	al,ds:[bx].DESC_ACC
	and	al,NOT ACC_PRESENT
	mov	bp,si
	or	bp,di			; a length of zero?
	jz	pr2			; yes, so it's not present
	push	ax
	push	cx
	push	dx
	call	lim_desc		; is the length valid?
	pop	dx
	pop	cx
	pop	ax
	jc	pr8			; no
	mov	ds:[bx].DESC_BASE,cx
	mov	ds:[bx].DESC_BASE16,dl
	add	dh,ds:[SYS_VARS].SV_LINHI	; (see LIN_HI)
	mov	byte ptr ds:[bx].DESC_EXT+1,dh
	or	al,ACC_PRESENT
pr2:	mov	ds:[bx].DESC_ACC,al	; (and carry is clear)
pr9:	ret
pr8:	jmp	cpu_inval
ENDPROC	pm_remap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; id_desc
;
; Finds the descriptor of an LDT selector from its ID (see enc_owner), in any
; LDT.
;
; Inputs:
;	BX = selector ID
;
; Outputs:
;	Carry clear if it's in use: BX -> its descriptor
;	Carry set if not: AX = ERR_INVALID
;
; Modifies:
;	AX, BX
;
DEFPROC	id_desc
	mov	ax,bx
	sub	ah,80h			; AH = its LDT #
	cmp	ah,LDT_SESSIONS		; a valid LDT #?
	jae	id8			; no
	mov	bl,ah
	mov	bh,0
	add	bx,bx			; BX = LDT # * 2
	push	cx
	mov	cx,ds:[SYS_VARS+SV_LDTTOP+bx]	; CX = where the LDT ends
	mov	bx,ds:[SYS_VARS+SV_LDTS+bx]	; BX = the LDT's offset
	mov	ah,0
	shl	ax,3			; AX = the descriptor's offset in it
	add	bx,ax
	cmp	bx,cx			; is it in the LDT?
	pop	cx
	jae	id8			; no
	cmp	ds:[bx].DESC_ACC,0	; is it in use?
	jne	id9			; yes (and carry is clear)
id8:	mov	ax,ERR_INVALID
	stc
id9:	ret
ENDPROC	id_desc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_unmap (CPU_UNMAP in protected mode)
;
; A selector ID (see enc_owner) frees that one LDT selector, in any LDT (eg,
; a driver's, from CPU_MAP with MEMF_LDT).
;
; Inputs:
;	BX = first selector, CX = # of selectors (0 = 1), or BX = selector ID
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_INVALID)
;
DEFPROC	pm_unmap
	test	bh,80h			; a selector ID?
	jz	cu0			; no
	call	id_desc			; BX -> its descriptor
	jc	cu7
	mov	di,bx
	mov	cx,1
	jmp	desc_zero
cu0:	mov	ax,bx
	test	cx,cx
	jnz	cu1
	inc	cx
cu1:	mov	dx,bx
	shr	dx,3
	add	dx,cx			; DX = index after the last selector
	test	bl,SEL_TI
	jnz	cu2
	cmp	bx,GDT_FIXED * 8	; fixed GDT selectors can't be freed
	jb	cu8
	cmp	dx,GDT_MAX		; nor can selectors beyond the GDT
	jmp	short cu3
cu2:	mov	si,dx
	call	ldt_num			; DX = # of descriptors
	cmp	si,dx			; or beyond the LDT
cu3:	ja	cu8
	call	desc_free
	clc
	ret
cu8:	mov	ax,ERR_INVALID
	stc
cu7:	ret
ENDPROC	pm_unmap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_alias (CPU_ALIAS in protected mode)
;
; Inputs:
;	AL = MEMF_* flags, BX = selector to alias
;
; Outputs:
;	Carry clear if successful: AX = selector, DX:CX = base address
;	Carry set if error: AX = error code (ERR_INVALID if BX isn't in use,
;	or ERR_NOMEMORY if there's no free descriptor)
;
DEFPROC	pm_alias
	call	sel_desc		; is BX's descriptor in use?
	jc	ci9
	push	bx
	mov	cx,1
	call	desc_alloc		; AX = selector, BX -> DESC
	pop	si			; SI = BX
	jc	ci8
	xchg	bx,si			; (allocating can move an LDT)
	push	ax
	push	si
	call	sel_desc		; SI -> BX's descriptor
	pop	bx			; BX -> DESC
	pop	ax
	mov	cx,ds:[si].DESC_LIMIT
	mov	ds:[bx].DESC_LIMIT,cx
	mov	dx,ds:[si].DESC_EXT
	mov	ds:[bx].DESC_EXT,dx
	mov	dl,ds:[si].DESC_BASE16
	mov	ds:[bx].DESC_BASE16,dl
	mov	cx,ds:[si].DESC_BASE
	mov	ds:[bx].DESC_BASE,cx
	call	desc_addr		; DX:CX = base (and carry is clear)
	ret
ci8:	mov	ax,ERR_NOMEMORY
ci9:	ret
ENDPROC	pm_alias

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sel_desc
;
; Inputs:
;	BX = selector
;
; Outputs:
;	Carry clear if it's in use: SI -> its descriptor
;	Carry set if not: AX = ERR_INVALID
;
; Modifies:
;	CX, DX, SI (and AX, if carry is set)
;
DEFPROC	sel_desc
	mov	si,bx
	and	si,NOT 7
	mov	cx,si
	shr	cx,3			; CX = descriptor index
	add	si,SYS_GDT
	mov	dx,GDT_MAX
	test	bl,SEL_TI
	jz	sd1
	sub	si,SYS_GDT
	add	si,ds:[SYS_VARS].SV_LDT	; the active LDT
	call	ldt_num			; DX = # of descriptors
sd1:	cmp	cx,dx			; is the index within the table?
	jae	sd8			; no
	cmp	ds:[si].DESC_ACC,0	; is the descriptor in use?
	jne	sd9			; yes (and carry is clear)
sd8:	mov	ax,ERR_INVALID
	stc
sd9:	ret
ENDPROC	sel_desc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; desc_addr
;
; Returns the physical address that a descriptor's base maps: its base, less
; the linear map's address (see LIN_HI) if it's in that map, which only the
; bases that we create are (a gate's base, its selector, is never there).
;
; Inputs:
;	SI -> DESC
;
; Outputs:
;	DX:CX = address (carry is clear)
;
DEFPROC	desc_addr
	mov	cx,ds:[si].DESC_BASE
	mov	dl,ds:[si].DESC_BASE16
	mov	dh,byte ptr ds:[si].DESC_EXT+1
	cmp	dh,LIN_HI		; in the linear map of physical memory?
	jb	dad9			; no
	sub	dh,LIN_HI
dad9:	clc
	ret
ENDPROC	desc_addr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ldt_num
;
; Outputs:
;	DX = # of descriptors in the active LDT
;
DEFPROC	ldt_num
	mov	dx,ds:[SYS_GDT + SEL_LDTD].DESC_LIMIT
	inc	dx
	shr	dx,3
	ret
ENDPROC	ldt_num

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ldt_grow
;
; Adds room for CX more descriptors to the active LDT (LDT_STEP at a time, up
; to LDT_LIMIT, as long as the PMB table has room for two more PMBs).
; Selectors are indexes, so moving an LDT doesn't change them.  The processor
; doesn't use the other LDTs, and other sessions can't run (see
; cpu_entry), so they can move with interrupts on; but an interrupt handler
; could reload a segment register from the active LDT, so it moves with
; interrupts off, along with zeroing the new entries (which aren't in use until
; the LDTR is reloaded).  That's never more than LDT_LIMIT descriptors' worth
; of memory, since those two together are the new LDT.
;
; Inputs:
;	CX = # of descriptors
;
; Outputs:
;	Carry clear if successful, set if there's no room
;
; Modifies:
;	None
;
DEFPROC	ldt_grow
	pusha
	push	es
	push	ds
	pop	es
	mov	bl,ds:[SYS_VARS].SV_LDTNUM
	mov	bh,0
	add	bx,bx			; BX = LDT # * 2
	add	cx,LDT_STEP - 1
	and	cx,NOT (LDT_STEP - 1)
	shl	cx,3			; CX = # of bytes to add
	mov	dx,ds:[SYS_VARS+SV_LDTTOP+bx]	; DX = where this LDT ends
	mov	ax,dx
	sub	ax,ds:[SYS_VARS].SV_LDT
	add	ax,cx
	sub	ax,LDT_LIMIT * 8	; would it be too long?
	jbe	lg1			; no
	sub	cx,ax			; yes, so add only what it can have
	jbe	lg8			; none
lg1:	mov	si,ds:[SYS_VARS+SV_LDTLOW]	; SI -> the lowest LDT
	mov	di,si
	sub	di,cx			; DI -> where it's going
	call	pmb_end
	add	ax,2 * (size PMB)
	cmp	di,ax			; does the PMB table have room?
	jb	lg8			; no
	mov	bp,cx			; BP = # of bytes to add
	mov	cx,ds:[SYS_VARS].SV_LDT
	sub	cx,si
	shr	cx,1
	rep	movsw			; move the LDTs below this one
	mov	ax,bx
lg2:	inc	bx
	inc	bx
	cmp	bx,LDT_SESSIONS * 2
	jae	lg3
	sub	ds:[SYS_VARS+SV_LDTS+bx],bp
	jmp	lg2
lg3:	xchg	bx,ax			; BX = LDT # * 2
	pushf
	cli
	mov	cx,dx
	sub	cx,si
	shr	cx,1
	rep	movsw			; move this LDT
	mov	cx,bp
	shr	cx,1
	sub	ax,ax
	rep	stosw			; and clear what it gained
	sub	ds:[SYS_VARS+SV_LDTS+bx],bp
	mov	ax,ds:[SYS_VARS+SV_LDTS+bx]
	mov	cx,dx
	call	ldt_load
	popf
	clc
	jmp	short lg9
lg8:	stc
lg9:	pop	es
	popa
	ret
ENDPROC	ldt_grow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_ptr
;
; Points a scratch selector (SEL_TMP or SEL_TMP2) at an address, with a 64K
; limit (see mv_ptr).
;
; Inputs:
;	BX = scratch selector, DX:AX = address
;	DS = SEL_SYS
;
; Outputs:
;	BX = selector, AX = offset (zero)
;
DEFPROC	pm_ptr
	push	bx
	add	bx,SYS_GDT
	mov	ds:[bx].DESC_LIMIT,0FFFFh
	mov	ds:[bx].DESC_BASE,ax
	mov	ds:[bx].DESC_BASE16,dl
	mov	al,dh
	add	al,ds:[SYS_VARS].SV_LINHI	; (see LIN_HI)
	mov	byte ptr ds:[bx].DESC_EXT+1,al
	mov	ds:[bx].DESC_ACC,ACC_DATA
	pop	bx
	sub	ax,ax
	ret
ENDPROC	pm_ptr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; map_block
;
; Allocates and fills in one selector for every 64K of the block (the last
; one's limit covers whatever remains).
;
; Inputs:
;	AL = MEMF_* flags, DX:CX = address, SI:DI = length (non-zero)
;
; Outputs:
;	Carry clear if successful: AX = first selector, CX = # of selectors
;	Carry set if not enough free descriptors
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	map_block
	push	dx
	push	cx
	push	si
	push	di
	call	len_sels		; CX = # of 64K pieces
	call	desc_alloc		; AX = selector, BX -> DESC
	pop	di
	pop	si
	pop	bp
	pop	dx			; DX:BP = address
	jc	mb9
	push	ax
	push	cx
	call	desc_fill
	pop	cx
	pop	ax
	clc
mb9:	ret
ENDPROC	map_block

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; len_sels
;
; Inputs:
;	SI:DI = length (non-zero)
;
; Outputs:
;	CX = # of selectors that it needs (one for every 64K, or part of it)
;
DEFPROC	len_sels
	mov	cx,si
	cmp	di,1
	cmc
	adc	cx,0
	ret
ENDPROC	len_sels

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; desc_fill
;
; Fills in the base and limit of consecutive descriptors, each covering the
; next 64K of a block (the last one's limit covers whatever remains).
;
; Inputs:
;	BX -> first DESC, CX = # of descriptors
;	DX:BP = address, SI:DI = length (non-zero)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	desc_fill
	add	dh,ds:[SYS_VARS].SV_LINHI	; (see LIN_HI)
mb1:	mov	ds:[bx].DESC_BASE,bp
	mov	ds:[bx].DESC_BASE16,dl
	mov	byte ptr ds:[bx].DESC_EXT,0
	mov	byte ptr ds:[bx].DESC_EXT+1,dh
	mov	ax,di
	test	si,si			; 64K or more remaining?
	jz	mb2			; no
	sub	ax,ax			; yes, so the limit is FFFFh
mb2:	dec	ax
	mov	ds:[bx].DESC_LIMIT,ax
	inc	dx			; next 64K
	dec	si
	add	bx,size DESC
	loop	mb1
	ret
ENDPROC	desc_fill

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; desc_alloc
;
; Finds CX consecutive free descriptors in the GDT (after the fixed entries)
; or the LDT, and claims them by storing the access byte in each.
;
; Inputs:
;	AL = MEMF_* flags, CX = # of descriptors
;
; Outputs:
;	Carry clear if successful: AX = first selector, BX -> first DESC
;	Carry set if not found
;
; Modifies:
;	AX, BX, DX, SI, DI
;
DEFPROC	desc_alloc
da0:	mov	bx,SYS_GDT + GDT_FIXED * (size DESC)
	mov	dx,GDT_MAX - GDT_FIXED
	test	al,MEMF_LDT
	jz	da1
	mov	bx,ds:[SYS_VARS].SV_LDT	; the active LDT
	call	ldt_num			; DX = # of descriptors
da1:	sub	si,si			; SI = free entries found so far
da2:	dec	dx
	js	da8			; no more entries
	cmp	ds:[bx].DESC_ACC,0	; is this entry free?
	je	da3			; yes
	sub	si,si
	jmp	short da4
da3:	test	si,si
	jnz	da3a
	mov	di,bx			; DI -> first free entry of this run
da3a:	inc	si
	cmp	si,cx
	je	da5
da4:	add	bx,size DESC
	jmp	da2
da8:	test	al,MEMF_LDT		; can its table grow?
	jz	da8a			; no
	call	ldt_grow		; maybe
	jnc	da0			; yes, so look again
da8a:	stc
	ret
da5:	mov	ah,ACC_DATA
	test	al,MEMF_CODE
	jz	da6
	mov	ah,al
	and	ah,MEMF_CONFORM		; conforming code? (the same bit)
	or	ah,ACC_CODE
da6:	test	al,MEMF_RDONLY
	jz	da6a
	and	ah,NOT ACC_RW		; read-only data (or execute-only code)
da6a:	test	al,MEMF_USER
	jz	da6b
	or	ah,ACC_DPL3
da6b:	mov	bx,di
	push	cx
da7:	mov	ds:[di].DESC_ACC,ah
	add	di,size DESC
	loop	da7
	pop	cx
	test	al,MEMF_LDT
	mov	ax,bx
	jnz	da9
	sub	ax,SYS_GDT		; GDT selector = offset within GDT
	ret
da9:	sub	ax,ds:[SYS_VARS].SV_LDT	; LDT selector = offset within its LDT
	or	al,SEL_TI		; + TI (the offset is 8-aligned)
	ret
ENDPROC	desc_alloc
	ASSERT	MEMF_CONFORM,EQ,ACC_CONFORM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; desc_free
;
; Inputs:
;	AX = first selector, CX = # of selectors (may be zero)
;
; Modifies:
;	AX, CX, DI
;
DEFPROC	desc_free
	jcxz	df9
	mov	di,ax
	and	di,NOT 7
	add	di,SYS_GDT
	test	al,SEL_TI
	jz	df1
	sub	di,SYS_GDT
	add	di,ds:[SYS_VARS].SV_LDT	; the active LDT
	DEFLBL	desc_zero,near		; (DI -> first DESC, CX = # of them)
df1:	push	es
	push	ds
	pop	es
	shl	cx,2			; 4 words per descriptor
	sub	ax,ax			; (and carry is clear)
	rep	stosw
	pop	es
df9:	ret
ENDPROC	desc_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_pmode (CPU_PMODE)
;
; Switches to protected mode for good.  The caller's CS, DS, ES, and SS become
; selectors for the same memory (see seg_sel), interrupts go through the
; protected-mode IDT (see sw_int and irq_common), with the master PIC moved
; to 78h, DDINT_CPU, DDINT_GETVEC, and DDINT_SETVEC go to our protected-mode
; code, and our TSS (see SYS_TSS) is loaded, for ring 3 code (once there's a
; ring 0 stack; see CPU_SETSTACK).
;
; Inputs:
;	cpu_entry's frame on the stack (see below)
;
; Outputs:
;	Carry clear if successful: AX = a data selector for the caller's CS
;	Carry set if error (still in real mode): AX = error code
;
; Modifies:
;	AX, CX, DX, SI, DI, BP, ES
;
DEFPROC	pm_pmode
	mov	bp,sp			; BP -> cpu_entry's frame: return, DI,
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM	; SI, BX, lock flag, FLAGS,
	jz	dp1				; BP, DS, IP, CS
	mov	ax,ERR_INVALID		; already in protected mode
	stc
	ret
dp0:	mov	sp,bp
	mov	ax,ERR_NOMEMORY		; no free descriptor
	stc
	ret
dp1:	mov	ax,[bp+18]
	mov	dl,MEMF_CODE
	call	seg_sel			; caller's CS
	jc	dp0
	push	ax			; [bp-2]
	mov	ax,[bp+18]
	mov	dl,0
	call	seg_sel			; and a data selector for it
	jc	dp0
	push	ax			; [bp-4]
	mov	ax,[bp+14]
	call	seg_sel			; caller's DS
	jc	dp0
	push	ax			; [bp-6]
	mov	ax,es
	call	seg_sel			; caller's ES
	jc	dp0
	push	ax			; [bp-8]
	mov	ax,ss
	call	seg_sel			; caller's SS
	jc	dp0
	push	ax			; [bp-10]
	mov	ax,[bp-2]
	mov	[bp+18],ax		; replace the caller's CS
	mov	ax,[bp-6]
	mov	[bp+14],ax		; and DS
	mov	ax,BIOS
	mov	es,ax
	mov	di,offset DDINT_CPU + DDINT_BIAS
	mov	ax,offset DEV:cpu_entry
	call	set_ddint
	mov	ax,offset DEV:pm_getvec
	call	set_ddint		; (DDINT_GETVEC follows DDINT_CPU)
	mov	ax,offset DEV:pm_setvec
	call	set_ddint		; (and DDINT_SETVEC follows that)
	mov	ah,78h
	call	pic_init		; move the master PIC to 78h
	or	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
;
; Until SS and DS are reloaded in protected mode, they can't be used (eg,
; to get the new selectors from the stack), so get them now.
;
	pop	dx			; DX = selector for caller's SS
	pop	cx			; CX = selector for caller's ES
	pop	si
	pop	si			; SI = data selector for caller's CS
	pop	di
	cmp	ds:[SYS_VARS].SV_LINHI,0; paging too (see LIN_HI)?
	je	dp1b			; no
;
; The 32-bit operand forms of LGDT and LIDT load all of the bases (the 16-bit
; forms ignore bits 31-24), and the low linear addresses still map physical
; memory, so the code after MOV CR0 runs until the far jump reloads CS.
;
	db	66h
	lgdt	qword ptr ds:[SYS_VARS].SV_GDTR
	db	66h
	lidt	qword ptr ds:[SYS_VARS].SV_PIDTR
	push	ds:[SYS_VARS].SV_PDIR.HIW
	push	ds:[SYS_VARS].SV_PDIR.LOW
	db	66h,58h			; POP EAX
	db	0Fh,22h,0D8h		; MOV CR3,EAX
	db	0Fh,20h,0C0h		; MOV EAX,CR0
	db	66h,0Dh			; OR EAX,80000001h (set PG and PE)
	dw	0001h,8000h
	db	0Fh,22h,0C0h		; MOV CR0,EAX
	jmp	short dp1c
dp1b:	lgdt	qword ptr ds:[SYS_VARS].SV_GDTR
	lidt	qword ptr ds:[SYS_VARS].SV_PIDTR
	smsw	ax
	or	al,1			; set PE
	lmsw	ax
dp1c:	db	OP_JMPF			; flush the prefetch queue and load CS
	dw	offset DEV:dp2,SEL_CPUCODE
dp2:	mov	ss,dx
	mov	ax,SEL_SYS
	mov	ds,ax
	mov	ax,SEL_LDTD
	lldt	ax
	mov	al,SEL_TSS		; (AH is still zero)
	ltr	ax
;
; Now that every register uses the linear map, the low linear addresses map
; nothing, until we map something else there (and any code that still uses
; a physical address as a linear one faults).
;
	cmp	ds:[SYS_VARS].SV_LINHI,0
	je	dp3
	mov	ax,ds:[SYS_VARS].SV_PDIR.LOW
	mov	dx,ds:[SYS_VARS].SV_PDIR.HIW
	mov	bx,SEL_TMP
	call	pm_ptr			; BX = selector, AX = offset (zero)
	mov	es,bx
	xchg	di,ax
	push	cx
	mov	cx,PDE_KERNEL / 2
	cld
	rep	stosw			; zero every PDE below C0000000h
	pop	cx
	db	0Fh,20h,0D8h		; MOV EAX,CR3
	db	0Fh,22h,0D8h		; MOV CR3,EAX (flush the TLB)
dp3:	mov	es,cx
	xchg	ax,si			; AX = data selector for caller's CS
	clc
	ret
ENDPROC	pm_pmode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_ddint
;
; Stores a far jump to SEL_CPUCODE:AX at ES:DI (a DDINT slot), and advances
; DI to the next slot.
;
; Modifies:
;	AX, DI
;
DEFPROC	set_ddint
	push	ax
	mov	al,OP_JMPF
	stosb
	pop	ax
	stosw
	mov	ax,SEL_CPUCODE
	stosw
	ret
ENDPROC	set_ddint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; seg_sel
;
; Returns a GDT selector for the real-mode segment in AX, with a 64K limit:
; an existing selector with the same base, limit, and type, if any (eg,
; SEL_LOW for segment 0, or SEL_BIOS for segment 40h), or a new one.
;
; Inputs:
;	AX = segment, DL = MEMF_CODE for a code selector (otherwise 0)
;	DS = system area
;
; Outputs:
;	Carry clear if successful: AX = selector
;	Carry set if there's no free descriptor
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	seg_sel
	push	bx
	push	dx
	mov	cx,ax
	shl	cx,4			; CX = base bits 15-0
	shr	ax,12			; AL = base bits 23-16
	mov	ah,ACC_DATA
	test	dl,MEMF_CODE
	jz	ss1
	mov	ah,ACC_CODE
ss1:	mov	bx,SYS_GDT + (size DESC)
	mov	si,GDT_MAX - 1
ss2:	cmp	bx,SYS_GDT + SEL_STACK	; (pm_call changes SEL_STACK)
	je	ss3
	mov	dh,ds:[bx].DESC_ACC
	and	dh,NOT 1		; (ignoring the "accessed" bit)
	cmp	dh,ah
	jne	ss3
	cmp	ds:[bx].DESC_BASE,cx
	jne	ss3
	cmp	ds:[bx].DESC_BASE16,al
	jne	ss3
	mov	dh,byte ptr ds:[bx].DESC_EXT+1
	cmp	dh,ds:[SYS_VARS].SV_LINHI	; base bits 31-24 too (see LIN_HI)?
	jne	ss3
	cmp	ds:[bx].DESC_LIMIT,0FFFFh
	je	ss8			; found one (and carry is clear)
ss3:	add	bx,size DESC
	dec	si
	jnz	ss2
	push	ax
	push	cx
	mov	al,dl
	mov	cx,1
	call	desc_alloc		; AX = selector, BX -> DESC
	pop	cx
	pop	dx			; DL = base bits 23-16
	jc	ss9
	mov	ds:[bx].DESC_LIMIT,0FFFFh
	mov	ds:[bx].DESC_BASE,cx
	mov	ds:[bx].DESC_BASE16,dl
	mov	dh,ds:[SYS_VARS].SV_LINHI
	mov	byte ptr ds:[bx].DESC_EXT+1,dh
	jmp	short ss9		; (carry is still clear)
ss8:	lea	ax,[bx-SYS_GDT]		; AX = selector
ss9:	pop	dx
	pop	bx
	ret
ENDPROC	seg_sel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pic_init
;
; Initializes the master PIC with a new vector base, keeping its mask.
;
; Inputs:
;	AH = vector base
;
; Modifies:
;	AL
;
DEFPROC	pic_init
	in	al,21h
	push	ax			; save the mask (ICW1 clears it)
	mov	al,11h			; ICW1: edge-triggered, cascade, ICW4
	out	20h,al
	mov	al,ah
	out	21h,al			; ICW2: vector base
	mov	al,04h
	out	21h,al			; ICW3: slave on IRQ 2
	mov	al,01h
	out	21h,al			; ICW4: 8086 mode
	pop	ax
	out	21h,al			; restore the mask
	ret
ENDPROC	pic_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Protected-mode interrupts
;
; The IDT's default gates (see idt_default) send exceptions to exc_stubs,
; hardware interrupts (at 70h-7Fh, since the master PIC moves from 08h to 78h)
; to irq_stubs, and software interrupts to sw_int, which "reflect" each one to
; its real-mode vector's handler, if that's in the ROM, whose segments are
; identity code selectors (eg, F000h), at ring 0.  A driver's handler, which
; pm_setvec puts in the vector's gate, is called directly.
;
; Exception stubs for vectors 00h-0Fh (the IDT sends 03h-05h to sw_int
; instead); each one loads AL with its vector.
;
	DEFLBL	exc_stubs,near
	IRP	v,<0,1,2,3,4,5,6,7,8,9,0Ah,0Bh,0Ch,0Dh,0Eh,0Fh>
	pusha
	mov	al,v
	jmp	short exc_common
	ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; exc_common
;
; Vectors 08h-0Fh are also IRQ 0-7 vectors in real mode, so if the frame
; (taken as having no error code) returns just past an INT for this vector
; (eg, the BIOS's IRQ 9 handler does INT 0Ah), we treat it as a software
; interrupt (see sw_int).  A general protection fault with a zero error code
; in the ROM, while DS (or ES) holds a null selector, is retried with SEL_LOW
; (base 0), because the BIOS loads DS with 0 to address the vectors; any
; other exception is fatal.
;
; Inputs:
;	AL = vector
;	PUSHA frame on the stack, followed by the error code (if any)
;
DEFPROC	exc_common
	mov	bp,sp
	mov	ah,al			; AH = vector
	mov	cx,[bp+18]		; CX = CS (if there's no error code)
	verr	cx			; is it readable?
	jnz	ex1			; no
	lsl	dx,cx			; DX = its limit
	mov	si,[bp+16]		; SI = IP (if there's no error code)
	cmp	si,2
	jb	ex1
	dec	si
	cmp	si,dx			; is SI within the limit?
	ja	ex1			; no
	push	ds
	mov	ds,cx
	mov	al,OP_INT
	cmp	[si-1],ax		; is there an INT for this vector?
	pop	ds
	jne	ex1			; no
	popa
	jmp	sw_int			; yes
ex1:	lea	si,[bp+16]		; SS:SI -> IP and CS
	sub	bx,bx			; BX = error code (if none)
	mov	cl,ah
	mov	dx,1
	shl	dx,cl
	test	dx,3D00h		; error code? (08h and 0Ah-0Dh)
	jz	ex8			; no
	mov	bx,ss:[si]		; BX = error code
	inc	si
	inc	si			; SS:SI -> IP and CS
	cmp	ah,0Dh			; general protection fault
	jne	ex8
	test	bx,bx			; with a zero error code
	jnz	ex8
	cmp	word ptr ss:[si+2],SEL_ROM	; in the ROM?
	jb	ex8			; no
	mov	cx,SEL_LOW
	mov	dx,ds
	cmp	dx,4			; is DS a null selector?
	jae	ex2			; no
	mov	ds,cx
	jmp	short ex3
ex2:	mov	dx,es
	cmp	dx,4			; is ES a null selector?
	jae	ex8			; no
	mov	es,cx
ex3:	popa
	add	sp,2			; discard the error code
	iret
ex8:	mov	cx,bx			; CX = error code
	mov	al,0
	call	to_fault		; (unless there's a fault handler)
	jmp	cpu_fatal
ENDPROC	exc_common
;
; Hardware interrupt stubs for vectors 70h-7Fh; each one makes room for a far
; address and loads AL with its IRQ's real-mode vector.
;
	DEFLBL	irq_stubs,near
	IRP	v,<70h,71h,72h,73h,74h,75h,76h,77h,8,9,0Ah,0Bh,0Ch,0Dh,0Eh,0Fh>
	push	ax
	push	ax
	pusha
	mov	al,v
	jmp	short irq_common
	ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; irq_common
;
; Reflects a hardware interrupt (from a default gate) to its real-mode
; vector's handler, if that's in the ROM, by "returning" to it with the
; interrupt's own frame on the stack, so that it returns directly to the
; interrupted code; otherwise, we just end the interrupt.
;
; Inputs:
;	AL = real-mode vector
;	PUSHA frame on the stack, followed by room for a far address
;
DEFPROC	irq_common
	mov	bp,sp
	call	rm_vector		; DX:CX = handler (if in the ROM)
	jc	ic8
	mov	[bp+16],cx
	mov	[bp+18],dx
	popa
	db	OP_RETF			; "return" to the handler
ic8:	mov	al,20h			; EOI both PICs
	out	0A0h,al
	out	20h,al
	popa
	add	sp,4
	iret
ENDPROC	irq_common

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sw_int
;
; Reflects a software interrupt (from a default gate) to its handler (see
; get_vec), getting the vector from the caller's INT instruction.  The
; handler is entered with interrupts disabled and an interrupt frame that
; returns to si_ret, which copies its result flags (CF, ZF, SF, and OF) to the
; caller's.  Callers handle any BIOS quirks with selectors (eg, INT 13h's
; buffers; see pm_rw in the FDC driver).  An interrupt with no handler is
; fatal.
;
; The stack above the PUSHA frame holds the handler's address (BP+16), its
; frame (BP+20), and the caller's frame (BP+26).
;
DEFPROC	sw_int
	sub	sp,10
	pusha
	mov	bp,sp
	push	ds
	lds	si,dword ptr [bp+26]	; DS:SI -> caller's next instruction
	mov	ax,[si-2]
	mov	cl,[si-1]
	pop	ds
	mov	bx,2			; BX = length of the INT
	cmp	al,OP_INT		; INT n?
	je	si1			; yes (AH = n)
	mov	ah,INT_BP
	dec	bx
	cmp	cl,OP_INT03		; INT3?
	je	si1			; yes
	mov	ah,0FFh			; no, so the vector is unknown
	dec	bx
	jmp	short si8
si1:	mov	al,ah
	call	get_vec			; DX:CX = handler
	test	dx,dx			; is there one?
	jz	si8			; no
	mov	[bp+16],cx
	mov	[bp+18],dx
	mov	word ptr [bp+20],offset DEV:si_ret
	mov	word ptr [bp+22],SEL_CPUCODE
	mov	cx,[bp+30]
	mov	[bp+24],cx		; the caller's flags
	popa
	db	OP_RETF			; "return" to the handler
si8:	sub	[bp+26],bx		; back the caller's IP up to the INT
	mov	cx,[bp+14]		; CX = caller's AX
	lea	si,[bp+26]		; SS:SI -> caller's IP and CS
	mov	al,0
	call	to_fault		; (unless there's a fault handler)
	jmp	cpu_fatal
ENDPROC	sw_int

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; si_ret
;
; A software interrupt's handler returns here (see sw_int), with the caller's
; frame on the stack.
;
DEFPROC	si_ret
	push	bp
	mov	bp,sp
	pushf				; [bp-2] = handler's flags
	push	ax
	mov	ax,[bp-2]
	and	ax,FL_RESULTS
	and	word ptr [bp+6],NOT FL_RESULTS
	or	[bp+6],ax		; update the caller's flags
	pop	ax
	mov	sp,bp
	pop	bp
	iret
ENDPROC	si_ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_getvec and pm_setvec (DDINT_GETVEC and DDINT_SETVEC in protected mode)
;
; A vector is its IDT gate (for vectors 08h-0Fh, the gates for IRQs 0-7, at
; 78h-7Fh), unless the gate is one of our defaults, in which case it's the
; real-mode vector, if that's in the ROM, or 0:0 if not (see get_vec), and
; setting a vector replaces its gate's selector and offset, keeping its DPL
; (see idt_default): 3 for INT 0 and the software interrupts that ring 3 code
; may issue (eg, INT 21h), and 0 for everything else, which it may not.
;
; Inputs:
;	AL = vector #
;	DX:CX = new vector (pm_setvec)
;
; Outputs:
;	DX:CX = vector (the previous vector, for pm_setvec)
;
; Modifies:
;	CX, DX
;
DEFPROC	pm_getvec,far
	call	get_vec
	ret
ENDPROC	pm_getvec

DEFPROC	pm_setvec,far
	pushf
	cli
	push	bx
	push	ds
	push	dx
	push	cx
	call	get_vec			; DX:CX = previous vector
	call	idt_gate		; DS:BX -> gate
	pop	[bx].DESC_LIMIT		; new offset
	pop	[bx].DESC_BASE		; and selector
	pop	ds
	pop	bx
	popf
	ret
ENDPROC	pm_setvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_vec
;
; Inputs:
;	AL = vector #
;
; Outputs:
;	DX:CX = vector (see pm_getvec); carry set if 0:0
;
; Modifies:
;	CX, DX
;
DEFPROC	get_vec
	push	bx
	push	ds
	call	idt_gate		; DS:BX -> gate
	mov	cx,[bx].DESC_LIMIT	; CX = offset
	mov	dx,[bx].DESC_BASE	; DX = selector
	pop	ds
	pop	bx
	cmp	dx,SEL_CPUCODE		; is it one of our default gates?
	je	rm_vector		; yes
	clc
	ret
ENDPROC	get_vec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; rm_vector
;
; Inputs:
;	AL = vector #
;
; Outputs:
;	DX:CX = real-mode vector, if its segment is an identity code selector
;	(ie, the handler is in the ROM); otherwise, 0:0 and carry set
;
; Modifies:
;	CX, DX
;
DEFPROC	rm_vector
	push	ds
	push	bx
	mov	bx,SEL_LOW
	mov	ds,bx
	mov	bl,al
	mov	bh,0
	shl	bx,2
	mov	cx,[bx].OFF
	mov	dx,[bx].SEG
	pop	bx
	pop	ds
	cmp	dx,SEL_ROM		; is the handler in the ROM
	jb	rv8
	test	dx,SEL_IDSTEP - 1	; at an identity selector?
	jz	rv9			; yes (and carry is clear)
rv8:	sub	cx,cx
	sub	dx,dx
	stc
rv9:	ret
ENDPROC	rm_vector

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; idt_gate
;
; Inputs:
;	AL = vector #
;
; Outputs:
;	DS:BX -> the vector's gate in the protected-mode IDT
;
DEFPROC	idt_gate
	mov	bx,SEL_SYS
	mov	ds,bx
	mov	bl,al
	mov	bh,0
	cmp	bl,8			; vectors 08h-0Fh are IRQs 0-7,
	jb	ig1
	cmp	bl,10h			; whose gates are at 78h-7Fh
	jae	ig1
	add	bl,70h
ig1:	shl	bx,3
	add	bx,SYS_PIDT
	ret
ENDPROC	idt_gate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; to_fault
;
; Gives a fatal exception to the fault handler (see CPU_SETFAULT), if there
; is one, unless the exception occurred in CPU$ or in the handler's own code
; segment.  The stack below the faulting instruction's frame is rebuilt as the
; PUSHA frame, the handler's address, our return address (tf_ret, where a
; handler that declines the exception returns, or for cpu_fatal's offer of
; the halt, cpu_halt), the vector, and the error code, and then the
; registers are restored and we "return" to the handler.
;
; Inputs:
;	AH = vector, AL = 0 (or FAULT_HALTED, from cpu_fatal), CX = error code
;	SS:BP -> PUSHA frame (at or above SI-26)
;	SS:SI -> IP, CS, and FLAGS of the faulting instruction
;	DS and ES as they were
;
; Outputs:
;	Returns only if there's no handler (or it can't be used)
;
; Modifies:
;	BX, DX, DI
;
DEFPROC	to_fault
	push	ds
	mov	dx,SEL_SYS
	mov	ds,dx
	mov	dx,ds:[SYS_VARS].SV_FAULT.SEG
	pop	ds
	test	dx,dx			; is there a handler?
	jz	tf9			; no
	mov	bx,ss:[si+2]		; BX = faulting CS
	cmp	bx,dx			; is it the handler's?
	je	tf9			; yes
	cmp	bx,SEL_CPUCODE		; or ours?
	je	tf9			; yes
	lea	bx,[si-28]		; BX -> new PUSHA frame (< BP)
	sub	di,di
tf1:	mov	dx,[bp+di]
	mov	ss:[bx+di],dx
	inc	di
	inc	di
	cmp	di,16
	jb	tf1
	mov	sp,bx
	mov	ss:[si-2],cx		; error code
	xchg	al,ah
	mov	ss:[si-4],ax		; vector (and FAULT_HALTED, if set)
	mov	dx,offset DEV:tf_ret
	test	ah,ah			; is it cpu_fatal's offer?
	jz	tf2			; no
	mov	dx,offset DEV:cpu_halt
tf2:	mov	ss:[si-8],dx
	mov	ss:[si-6],cs		; our return address
	push	ds
	mov	dx,SEL_SYS
	mov	ds,dx
	mov	dx,ds:[SYS_VARS].SV_FAULT.OFF
	mov	ss:[si-12],dx
	mov	dx,ds:[SYS_VARS].SV_FAULT.SEG
	mov	ss:[si-10],dx
	pop	ds
	popa
	db	OP_RETF			; "return" to the handler
tf9:	ret
;
; A handler that declines the exception returns here, with the registers as
; they were, and SS:SP -> the vector, the error code, and the faulting
; instruction's frame.
;
	DEFLBL	tf_ret,near
	pusha				; (for cpu_fatal's offer)
	mov	bp,sp
	mov	ah,[bp+16]		; AH = vector
	mov	cx,[bp+18]		; CX = error code
	lea	si,[bp+20]		; SS:SI -> IP, CS, and FLAGS
ENDPROC	to_fault			; fall into cpu_fatal

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cpu_fatal
;
; Reports an exception (or an interrupt that has no handler) with the BIOS,
; as "CPU fault vv (EC=xxxx) at cccc:iiii", where EC is the error code,
; followed by "System halted", and then offers the halt to the fault handler
; (see to_fault), with FAULT_HALTED in the vector's high byte, so that a
; debugger can keep control; if the handler declines it (or there's none, or
; it can't be used), we stop the machine for good.
;
; Inputs:
;	AH = vector (0FFh for an unknown software interrupt)
;	CX = error code (or the caller's AX, for a software interrupt)
;	SS:BP -> PUSHA frame (see to_fault)
;	SS:SI -> IP, CS, and FLAGS
;	DS and ES as they were
;
DEFPROC	cpu_fatal
	push	si
	push	bp
	push	word ptr ss:[si]	; IP
	push	word ptr ss:[si+2]	; CS
	push	cx
	push	ax			; AH = vector
	mov	bp,sp			; BP -> vector, error code, CS, and IP
	mov	si,offset DEV:fatal_fields
	sub	di,di
cft1:	lods	byte ptr cs:[si]
	cmp	al,4			; a field's # of digits (or the end)?
	ja	cft2			; no, a character
	cbw
	xchg	cx,ax			; CX = # of digits
	jcxz	cft8			; the end
	mov	ax,[bp+di]
	call	pr_hex
	inc	di
	inc	di
	jmp	cft1
cft2:	call	pr_char
	jmp	cft1
cft8:	pop	ax			; AH = vector
	pop	cx			; CX = error code
	add	sp,4
	pop	bp
	pop	si
	mov	al,FAULT_HALTED
	call	to_fault		; (unless there's a fault handler)
	DEFLBL	cpu_halt,near
	HALT_FATAL
ENDPROC	cpu_fatal
;
; Each field is a # of digits (4, or 2 for the vector, in AH); 0 ends them.
;
	DEFLBL	fatal_fields,byte
	db	"CPU fault ",2," (EC=",4,") at ",4,":",4,13,10
	db	"System halted",13,10,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pr_hex and pr_char
;
; Print the high CX digits of AX (in hex) or the character in AL with the
; BIOS.
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	pr_hex
ph1:	rol	ax,4
	push	ax
	and	al,0Fh
	add	al,90h			; convert the low nibble to hex
	daa
	adc	al,40h
	daa
	call	pr_char
	pop	ax
	loop	ph1
	ret
	DEFLBL	pr_char,near
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	ret
ENDPROC	pr_hex

	ASSERT	<offset exc_common - offset exc_stubs>,EQ,<16 * 5>
	ASSERT	<offset irq_common - offset irq_stubs>,EQ,<16 * 7>
CODE	ends

DATA	segment para public 'DATA'

ddcpu_end	db	16 dup(0)

DATA	ends

	end
