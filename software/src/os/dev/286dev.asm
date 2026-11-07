;
; BASIC-DOS 80286 Processor (CPU$) Device Driver
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
; that it can switch to protected mode and back,
; and stays, managing all of memory with its PMB table (see PMB in cpu.inc)
; through DDINT_CPU.  Otherwise, it makes CPU_TYPE CPUTYPE_8086, leaves A20
; off, and unloads itself, and the 8086 driver
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
;
; The system area is the last whole 64K of conventional memory, which is
; addressable in real mode with segment sys_seg and in protected mode with
; selector SEL_SYS (whose base is sys_seg * 16), so the same offsets work in
; both modes.
;
; The GDT starts after that, with GDT_MAX entries that CPU$ allocates from,
; but its limit extends to the "identity" selectors (A000h to F800h, every
; 800h), whose bases are their values times 16, so the ROM BIOS can use its
; own segments (eg, F000h and B800h) in protected mode; everything else in
; the system area fits between the first part of the GDT and A000h.
;
SYS_VARS	equ	0020h
SYS_GDT		equ	00E0h
GDT_MAX		equ	256
SYS_PIDT	equ	SYS_GDT + GDT_MAX * 8
IDT_MAX		equ	256
;
; The TSS (80286 format) is only for its ring 0 stack (SS0:SP0; see
; CPU_SETSTACK), which the processor switches to when an interrupt takes ring
; 3 code to ring 0; we never switch tasks, so the rest of it stays zero.
;
SYS_TSS		equ	SYS_PIDT + IDT_MAX * 8
TSS_SP0		equ	2	; ring 0 SP (followed by SS)
TSS_LEN		equ	44
SEL_VIDEO	equ	0A000h	; first identity selector (data)
;
; The rest is a pool for the PMB table and the LDTs: the table grows up from
; the bottom as blocks are added (see pmb_dup), and with programs at ring 3,
; each session has its own LDT (see CPU_SETLDT), so that its programs'
; selectors (MEMF_LDT) can't name another session's memory.  The LDTs are
; packed down from the top, with session 0's first; each one starts empty, and
; grows as needed (see ldt_grow), up to LDT_LIMIT descriptors, which is all
; that fits in an owner ID (see enc_owner).  SV_LDTS has each LDT's offset, so
; each one ends at the offset of the session before it; the active session's
; offset is also in SV_LDT, and its limit is in the LDTR's descriptor
; (SEL_LDTD).
;
; Since the GDT's limit covers everything up to the identity selectors, the
; processor can also read the pool as descriptors, through selectors below
; A000h, each of whose access bytes is at an offset of 5 mod 8.  So the PMBs
; and LDTs must start at an offset of 6 mod 8 (and everything in them moves by
; multiples of 8), which puts those access bytes on byte 7 of every 8 bytes of
; a table, none of which ever has its present bit set: the top of a
; descriptor's base; and in a PMB, the top of PMB_ADDR, the high byte of
; PMB_NSEL, a reserved byte, and the last byte of PMB_NAME (see ddcpu_setblk).
; Otherwise, a ring 3 program could load another session's descriptors, or a
; PMB, as its own.
;
SYS_PMBS	equ	SYS_TSS + TSS_LEN + 2
SYS_LDTTOP	equ	SYS_GDT + SEL_VIDEO - 2
LDT_SESSIONS	equ	32
LDT_STEP	equ	32	; descriptors to add at a time
LDT_LIMIT	equ	256	; descriptors per session
	ASSERT	<(SYS_PMBS AND 7)>,EQ,6
	ASSERT	<(SYS_LDTTOP AND 7)>,EQ,6
	ASSERT	<(PMB_NSEL AND 7)>,EQ,6
	ASSERT	<((PMB_NAME + size PMB_NAME) AND 7)>,EQ,0
SEL_ROM		equ	0C000h	; first identity code selector
SEL_IDSTEP	equ	0800h	; identity selectors are every 800h
GDT_LIMIT	equ	0F807h	; (through the last identity selector)

;
; SYSVARS is at SYS_VARS in the system area, and the PMB table at SYS_PMBS.
;
SYSVARS		struc
SV_TYPE		db	?	; CPU type
SV_FLAGS	db	?	; CPUF_* flags
SV_NPMBS	dw	?	; number of PMBs
SV_ARG		db	?	; CPU_ALLOC: MEMF_* flags
SV_SESS		db	?	; active session # (see CPU_SETLDT)
SV_OWNER	dw	?	; CPU_ALLOC: owner
SV_LEN		dd	?	; CPU_ALLOC, CPU_REALLOC, CPU_MOVE: length
SV_SRC		dd	?	; CPU_MOVE: source
SV_DST		dd	?	; CPU_MOVE: destination
SV_RMSP		dw	?	; real-mode SP (while in protected mode)
SV_RMSS		dw	?	; real-mode SS (while in protected mode)
SV_RMCS		dw	?	; real-mode CS (ie, the CPU$ segment)
SV_GDTR		dw	3 dup (?) ; GDT limit and base (for LGDT)
SV_PIDTR	dw	3 dup (?) ; protected mode's IDT limit and base
SV_RMIDTR	dw	3 dup (?) ; real-mode IDT limit and base
SV_FAULT	dd	?	; fault handler (see CPU_SETFAULT and to_fault)
SV_LDT		dw	?	; active session's LDT offset (see CPU_SETLDT)
SV_LDTTOP	dw	?	; the end of session 0's LDT (see ldt_grow)
SV_LDTS		dw	LDT_SESSIONS dup (?) ; each session's LDT offset
SYSVARS		ends
SV_LDTLOW	equ	SV_LDTS + (LDT_SESSIONS - 1) * 2 ; (the lowest LDT)
	ASSERT	<SYS_VARS + size SYSVARS>,LE,SYS_GDT

;
; Descriptors (gates use DESC_LIMIT for the offset, DESC_BASE for the
; selector, and DESC_BASE16 for the parameter count)
;
DESC		struc
DESC_LIMIT	dw	?	; limit (bits 15-0)
DESC_BASE	dw	?	; base (bits 15-0)
DESC_BASE16	db	?	; base (bits 23-16)
DESC_ACC	db	?	; access rights (ACC_*), or zero if free
DESC_EXT	dw	?	; 80386: limit (19-16), flags, base (31-24)
DESC		ends

ACC_DATA	equ	92h	; present, DPL 0, read/write data
ACC_CODE	equ	9Ah	; present, DPL 0, execute/read code
ACC_RW		equ	02h	; writable data (or readable code)
ACC_CONFORM	equ	04h	; conforming code (added to ACC_CODE)
ACC_PRESENT	equ	80h	; present (in every ACC_* value but ACC_DPL3)
ACC_DPL3	equ	60h	; DPL 3 (added to another ACC_* value)
ACC_LDT		equ	82h	; present, LDT
ACC_CALLGATE	equ	84h	; present, DPL 0, 80286 call gate
ACC_INTGATE	equ	86h	; present, DPL 0, 80286 interrupt gate
ACC_TSS		equ	81h	; present, DPL 0, available 80286 TSS

SEL_TI		equ	04h	; table indicator (set for LDT selectors)
;
; Fixed GDT selectors; SEL_BIOS and SEL_DDINT are the same values as the
; BIOS and DDINT segments, so code that uses those works in either mode.
;
SEL_SYS		equ	08h	; data: system area
SEL_LDTD	equ	10h	; LDT
SEL_CPUCODE	equ	18h	; code: CPU$ driver
SEL_LOW		equ	20h	; data: first 64K of memory
SEL_STACK	equ	28h	; data: caller's stack (see pm_call)
SEL_TMP		equ	30h	; data: scratch
SEL_CPU		equ	38h	; call gate: cpu_entry
SEL_BIOS	equ	40h	; data: segment 40h (BIOS)
SEL_TMP2	equ	48h	; data: scratch (see pm_ptr)
SEL_DDINT	equ	50h	; code: segment 50h (DDINT)
SEL_C5CODE	equ	58h	; code: the CALL 5 jump (0:00C0h)
;		equ	60h	; SEL_CALL5 (in cpu.inc): call gate to it
SEL_TSS		equ	68h	; TSS (see CPU_SETSTACK)
GDT_FIXED	equ	0Eh	; number of fixed GDT entries
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
; Only ddcpu_req and the start of ddcpu_init run on an 8086 (and use only
; 8086 instructions); everything else runs on an 80286 or later.
;
	.286p

	public	CPU
CPU	DDH	<offset DEV:ddcpu_end+16,,DDATTR_CHAR,offset DEV:ddcpu_init,-1,2020202024555043h>
	even
	DEFLBL	CPU_FUNCS,word
	dw	ddcpu_getinfo, ddcpu_alloc, ddcpu_free, ddcpu_map
	dw	ddcpu_unmap, ddcpu_query, ddcpu_alias, ddcpu_pmode
	dw	ddcpu_realloc, ddcpu_move, ddcpu_setblk, ddcpu_freeall
	dw	ddcpu_setlim, ddcpu_seginfo, ddcpu_rwmem, ddcpu_sysregs
	dw	ddcpu_setfault, ddcpu_setstack, ddcpu_setldt

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
	mov	bp,ds:[SYS_VARS].SV_NPMBS
	shl	bp,5
	add	bp,SYS_PMBS + 2 * (size PMB)
	cmp	bp,ds:[SYS_VARS+SV_LDTLOW]
	ja	ca8			; no room to split a free block twice
	call	pmb_fit			; BX -> free PMB, DX:CX = address
	jc	ca8
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
; segment.
;
; Inputs:
;	AL = MEMF_* flags, DX:CX = address, SI:DI = length
;
; Outputs:
;	Carry clear if successful: AX = selector, CX = # of selectors
;	Carry set if error: AX = error code
;
DEFPROC	ddcpu_map
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
;	BX = selector, SI:DI = new length (1 to 64K)
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_INVALID)
;
DEFPROC	ddcpu_setlim
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PM
	jz	sl9			; (carry is clear)
	mov	ax,di
	sub	ax,1			; AX = new limit
	sbb	si,0			; is SI:DI from 1 to 64K?
	jnz	sl8			; no
	test	bl,SEL_TI		; an LDT selector?
	jnz	sl1			; yes
	cmp	bx,GDT_FIXED * 8	; a fixed GDT selector?
	jb	sl8			; yes
sl1:	push	ax
	call	sel_desc		; SI -> its descriptor
	pop	ax
	jc	sl9
	mov	ds:[si].DESC_LIMIT,ax
	ret				; (carry is clear)
sl8:	mov	ax,ERR_INVALID
	stc
sl9:	ret
ENDPROC	ddcpu_setlim

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
;	Carry clear if successful: DX:CX = base address, AX = limit (or with
;	ADDR_RIGHTS, the access rights in AL and the extended byte in AH)
;	Carry set if the selector isn't present (AX = ERR_INVALID)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	ddcpu_seginfo
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
	add	si,ds:[SYS_VARS].SV_LDT	; the active session's LDT
	jmp	short sg3
sg2:	cmp	si,GDT_LIMIT		; is it within the GDT?
	ja	sg8			; no
	add	si,SYS_GDT
sg3:	test	ds:[si].DESC_ACC,ACC_PRESENT
	jz	sg8
	mov	cx,ds:[si].DESC_BASE
	mov	dl,ds:[si].DESC_BASE16
	mov	dh,byte ptr ds:[si].DESC_EXT+1
	test	al,ADDR_RIGHTS		; (carry is clear)
	mov	ax,ds:[si].DESC_LIMIT
	jz	sg9
	mov	ax,word ptr ds:[si].DESC_ACC
sg9:	ret
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
	jmp	short sf1
	DEFLBL	ddcpu_setstack,near
	mov	bx,SYS_TSS + TSS_SP0
sf1:	xchg	cx,ds:[bx].OFF
	xchg	dx,ds:[bx].SEG
	clc
	ret
ENDPROC	ddcpu_setfault

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_setldt (CPU_SETLDT)
;
; Makes the LDT of the session in AL the active one, so that its programs'
; selectors (MEMF_LDT) are the ones the descriptor helpers allocate and
; resolve (see SV_LDT), and the LDTR's descriptor (SEL_LDTD) is repointed at
; it.  In real mode there are no LDTs, so there's nothing to do.
;
; Inputs:
;	AL = session #
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
	mov	ds:[SYS_VARS].SV_SESS,al	; (see enc_owner)
	mov	bl,al
	mov	bh,0
	add	bx,bx			; BX = session # * 2
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
	mov	cx,ds:[si].DESC_BASE
	mov	dl,ds:[si].DESC_BASE16
	mov	dh,0			; DX:CX = its base address
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
; its session # (see CPU_SETLDT) in AH and its LDT index in AL, so that it's
; unique even though another session's program can have the same selector,
; and so that it's above MCBOWNER_SYSTEM, like a PSP segment (see MEM and
; DEBUG's DM).  Any other owner (a segment, a GDT selector, or the system) is
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
	mov	ah,ds:[SYS_VARS].SV_SESS
	or	ah,80h			; AH = 80h + its session #
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
;	Carry clear if successful: AX = selector, CX = # of selectors
;	Carry set if error: AX = ERR_NOMEMORY
;
DEFPROC	pm_map
	call	map_block
	jnc	pmp9
	mov	ax,ERR_NOMEMORY
pmp9:	ret
ENDPROC	pm_map

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_unmap (CPU_UNMAP in protected mode)
;
; Inputs:
;	BX = first selector, CX = # of selectors (0 = 1)
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_INVALID)
;
DEFPROC	pm_unmap
	mov	ax,bx
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
	ret
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
	mov	ds:[bx].DESC_BASE,cx	; DX:CX = base (and carry is clear)
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
	add	si,ds:[SYS_VARS].SV_LDT	; the active session's LDT
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
; ldt_num
;
; Outputs:
;	DX = # of descriptors in the active session's LDT
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
; Adds room for CX more descriptors to the active session's LDT (LDT_STEP at a
; time, up to LDT_LIMIT, as long as the PMB table has room for two more PMBs).
; Selectors are indexes, so moving an LDT doesn't change them.  The processor
; doesn't use the other sessions' LDTs, and other sessions can't run (see
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
	mov	bl,ds:[SYS_VARS].SV_SESS
	mov	bh,0
	add	bx,bx			; BX = session # * 2
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
lg3:	xchg	bx,ax			; BX = session # * 2
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
	mov	bx,ds:[SYS_VARS].SV_LDT	; the active session's LDT
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
	add	di,ds:[SYS_VARS].SV_LDT	; the active session's LDT
df1:	push	es
	push	ds
	pop	es
	shl	cx,2			; 4 words per descriptor
	sub	ax,ax
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
	lgdt	qword ptr ds:[SYS_VARS].SV_GDTR
	lidt	qword ptr ds:[SYS_VARS].SV_PIDTR
	smsw	ax
	or	al,1			; set PE
	lmsw	ax
	db	OP_JMPF			; flush the prefetch queue and load CS
	dw	offset DEV:dp2,SEL_CPUCODE
dp2:	mov	ss,dx
	mov	es,cx
	mov	ax,SEL_SYS
	mov	ds,ax
	mov	ax,SEL_LDTD
	lldt	ax
	mov	al,SEL_TSS		; (AH is still zero)
	ltr	ax
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
;
; Everything from here on is discarded after initialization (see DDPI_END),
; and until we know it's an 80286 (see di3), it must run on an 8086.
;
	.8086
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Only 8086 instructions may be used until the CPU type is known.
;
; We're always the first driver, so we also apply any "MEMSIZE=" line (see
; docs/bdman/cfg), by lowering MEMORY_SIZE, before either driver builds its
; arena.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated (left zero if we're not staying), and if
;	we're staying, CPU_ARENA (see cpu.inc)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, DS
;
DEFPROC	ddcpu_init,far
	mov	ds,cs:[0].DDH_DATA
	mov	ds:[0].DDH_REQUEST,offset DEV:ddcpu_req
	push	es
	push	bx
	mov	di,offset DEV:cfg_memsize
	call	find_cfg		; is there a "MEMSIZE=" line?
	jne	di0			; no
	add	si,8			; DS:SI -> its value
	sub	ax,ax
dm1:	mov	cl,[si]
	sub	cl,'0'
	cmp	cl,9			; another digit?
	ja	dm2			; no
	inc	si
	mov	dx,ax
	shl	ax,1
	shl	ax,1
	add	ax,dx
	shl	ax,1			; AX = AX * 10
	mov	ch,0
	add	ax,cx
	jmp	dm1
dm2:	mov	dx,BIOS
	mov	ds,dx
	ASSUME	DS:BIOS
	cmp	ax,16			; is the value at least 16 (Kb)?
	jb	di0			; no
	cmp	ax,[MEMORY_SIZE]	; and less than we have?
	jae	di0			; no
	mov	[MEMORY_SIZE],ax
di0:	mov	di,offset DEV:cfg_cpu
	call	find_cfg		; is there a "CPU=80" line?
	jne	di0a			; no
	mov	al,[si+6]
	and	al,0FEh
	cmp	al,'2'			; "CPU=802xx" or "CPU=803xx"?
di0a:	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	pushf				; (ZF set if so; see di2)
;
; Even then, we determine the processor type (for CPU_HWTYPE).
;
; An 8086 or 80186 decrements SP before PUSH SP stores it, whereas an 80286
; or later stores the original value.
;
	push	sp
	pop	ax
	cmp	ax,sp			; did PUSH SP store the original SP?
	je	di1			; yes
;
; An 80186 masks shift counts to 5 bits, so shifting 1 left 33 times leaves
; 2 (instead of 0 on an 8086).
;
	mov	ax,1
	mov	cl,33
	shl	ax,cl
	shr	ax,1			; AL = CPUTYPE_8086 or CPUTYPE_80186
	jmp	short di2
;
; In real mode, an 80286 always clears FLAGS bits 12-15, whereas an 80386
; lets us set bits 12-14 (IOPL and NT).
;
di1:	pushf
	mov	ax,7000h
	push	ax
	popf
	pushf
	pop	ax
	popf
	cmp	ah,1			; carry set if bits 12-14 are clear
	mov	al,CPUTYPE_80386
	sbb	al,0			; AL = CPUTYPE_80286 or CPUTYPE_80386
di2:	mov	[CPU_HWTYPE],al
;
; We act as if this is an 8088 unless protected mode is requested, by a CONFIG
; line or a P at the boot message, and an R then overrides a line.
;
	mov	ah,byte ptr [BOOT_KEY]
	or	ah,20h			; AH = boot key, in lower-case
	popf				; was there a "CPU=80x86" line?
	je	di2c			; yes
	cmp	ah,'p'			; was the boot key P?
	jne	di2b			; no
di2c:	cmp	ah,'r'			; was the boot key R?
	je	di2b			; yes
;
; Protected mode also needs at least 256K of conventional memory (after any
; "MEMSIZE=" line), so with less, we act as if this is an 8088, too.
;
	cmp	[MEMORY_SIZE],256	; enough conventional memory?
	jae	di2a			; yes
di2b:	mov	al,CPUTYPE_8086		; no, so act as if this is an 8088
di2a:	mov	[CPU_TYPE],al
	cmp	al,CPUTYPE_80286	; protected mode available?
	jb	di9			; no
;
; Extended memory is optional.  A20 isn't, because an 80286 returns to real
; mode through a reset (see pm_call), and the ROM's reset vector at FFFFF0h
; needs it.  If A20 isn't enabled, then writing FFFF:0010h changes its
; wrap-around alias in low memory (and if it is, the write has no effect there,
; whether or not there's any memory at that address).
;
	mov	ah,CAS_GETEXTMEM
	int	INT_CASSETTE
	jnc	di2d
	sub	ax,ax			; no extended memory
di2d:	xchg	si,ax			; SI = Kb of extended memory
	call	a20_on
	mov	ax,0FFFFh
	mov	es,ax
	ASSUME	ES:NOTHING
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:NOTHING
	mov	bx,ds:[0]		; BX = word at the low memory alias
	mov	ax,bx
	not	ax
	mov	es:[10h],ax
	cmp	ds:[0],ax		; did the alias change?
	mov	ds:[0],bx		; (restore it, in case it did)
	pop	ds
	ASSUME	DS:BIOS
	jne	di3			; no, so A20 is enabled
;
; On an 8086 (or without A20, or if the protected mode self-test fails), we
; unload ourselves (DDPI_END is still zero), and the 8086 driver stays instead,
; so CPU_TYPE must say we're acting as an 8088.
;
di9:	mov	[CPU_TYPE],CPUTYPE_8086
	pop	bx
	pop	es
	ret
;
; The system area is the last whole 64K of conventional memory.  Clear all of
; it (so that unused GDT entries, including the gaps between the identity
; selectors, aren't present), and then fill in SYSVARS, the PMBs, and the GDT.
;
	.286p
	ASSUME	DS:BIOS
di3:	mov	ax,[MEMORY_SIZE]
	and	ax,0FFC0h		; AX = Kb, in whole 64K units
	sub	ax,64
	shl	ax,6			; AX = segment of the last whole 64K
	mov	cs:[sys_seg],ax
	mov	es,ax
	sub	ax,ax
	mov	di,ax
	mov	cx,8000h		; (64K)
	rep	stosw

	mov	di,SYS_VARS
	mov	al,[CPU_TYPE]
	mov	ah,al			; (the same as CPU_HWTYPE here)
	ror	ah,1
	ror	ah,1			; AH = CPUF_HWTYPE
	mov	word ptr es:[di].SV_TYPE,ax	; (and SV_FLAGS)
	mov	es:[di].SV_RMCS,cs
	mov	es:[di].SV_GDTR,GDT_LIMIT
	mov	es:[di].SV_GDTR+2,SYS_GDT
	mov	es:[di].SV_PIDTR,IDT_MAX * (size DESC) - 1
	mov	es:[di].SV_PIDTR+2,SYS_PIDT
	mov	es:[di].SV_RMIDTR,3FFh
	mov	ax,SYS_LDTTOP
	mov	es:[di].SV_LDT,ax	; session 0's LDT (see CPU_SETLDT)
	push	di
	add	di,SV_LDTTOP
	mov	cx,LDT_SESSIONS + 1
	rep	stosw			; every session's LDT is empty
	pop	di
	mov	ax,offset DEV:ddcpu_init
	call	init_arena

	push	cs
	pop	ds
	ASSUME	DS:NOTHING
	mov	si,offset DEV:gdt_init
	mov	di,SYS_GDT + (size DESC)
	mov	cx,offset DEV:gdt_init_end - offset DEV:gdt_init
	rep	movsb
;
; Every system area address has the same upper base bits (and the lower bits
; are its offset, since the area starts on a 64K boundary).
;
	mov	ax,es
	mov	al,ah
	shr	al,4			; AL = base bits 23-16
	mov	byte ptr es:[SYS_VARS].SV_GDTR+4,al
	mov	byte ptr es:[SYS_VARS].SV_PIDTR+4,al
	mov	es:[SYS_GDT+SEL_SYS].DESC_BASE16,al
	mov	es:[SYS_GDT+SEL_LDTD].DESC_BASE16,al
	mov	es:[SYS_GDT+SEL_TSS].DESC_BASE16,al
	mov	ax,cs
	mov	dx,ax
	shl	ax,4
	shr	dx,12			; DX:AX = linear address of CS
	mov	es:[SYS_GDT+SEL_CPUCODE].DESC_BASE,ax
	mov	es:[SYS_GDT+SEL_CPUCODE].DESC_BASE16,dl
;
; The identity selectors: data for video memory (A000h-B800h) and code for
; the adapter and system ROMs (C000h-F800h).  Video memory is DPL 3, so that
; ring 3 programs can draw directly, too (eg, COMMAND.COM's graphics, with
; the selector from the CONSOLE driver's IOCTL_GETMODE).
;
	mov	bx,SEL_VIDEO
di4a:	lea	di,[bx+SYS_GDT]
	mov	ax,0FFFFh
	stosw				; limit
	mov	ax,bx
	shl	ax,4
	stosw				; base bits 15-0
	mov	ax,bx
	shr	ax,12			; AL = base bits 23-16
	mov	ah,ACC_DATA + ACC_DPL3
	cmp	bx,SEL_ROM
	jb	di4b
	mov	ah,ACC_CODE
di4b:	stosw
	add	bx,SEL_IDSTEP
	jnc	di4a			; through F800h

	mov	di,SYS_PIDT		; pm_call's gates, for the test
	mov	cx,IDT_MAX
di5:	mov	ax,offset DEV:pm_fault
	stosw
	mov	ax,SEL_CPUCODE
	stosw
	mov	ax,ACC_INTGATE SHL 8
	stosw
	sub	ax,ax
	stosw
	loop	di5
;
; Switch to protected mode and back; we keep all of this only if the test
; succeeds, and otherwise, act as we do on an 8086.
;
	mov	bx,offset DEV:pm_test
	call	pm_call
	mov	es,cs:[sys_seg]
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	test	es:[SYS_VARS].SV_FLAGS,CPUF_PMOK
	jnz	di7
	mov	ah,0DDh			; output port: A20 off, no reset
	call	a20_set
	jmp	di9
di7:	call	a20_on			; (in case the ROM turned it off)
	mov	di,SYS_PIDT		; now the protected-mode gates
	sub	bx,bx
di6:	call	idt_default		; AX = handler, DH = access rights
	stosw
	mov	ax,SEL_CPUCODE
	stosw
	mov	al,0
	mov	ah,dh
	stosw
	sub	ax,ax
	stosw
	inc	bl
	jnz	di6
	mov	[CPU_ARENA].OFF,SYS_PMBS
	mov	[CPU_ARENA].SEG,es	; CPU_ARENA -> the PMB table
	mov	ax,offset DEV:ddcpu_init
	mov	byte ptr ds:[DDINT_CPU],OP_JMPF
	mov	word ptr ds:[DDINT_CPU+1],offset DEV:cpu_entry
	mov	word ptr ds:[DDINT_CPU+3],cs
	pop	bx
	pop	es
	ASSUME	ES:NOTHING
	mov	es:[bx].DDPI_END.OFF,ax
	ret
ENDPROC	ddcpu_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_arena
;
; Builds the arena (the PMB table): everything below BIOS_END (the vectors,
; the BIOS data, and BASIC-DOS's low memory) and CPU$ are used (by the
; system), the rest of conventional memory is free, except for the system
; area, the rest of the first 1Mb is reserved, and any extended memory is free.
;
; Inputs:
;	AX = length of CPU$ (rounded up to a multiple of 16 here)
;	SI = Kb of extended memory (zero if none)
;	DS = BIOS
;	ES:SYS_VARS -> SYSVARS
;
; Modifies:
;	BX, CX, DX, DI
;
DEFPROC	init_arena
	push	ax
	add	ax,15
	and	al,0F0h
	mov	bp,ax			; BP = length of CPU$
	mov	di,SYS_PMBS
	sub	dx,dx
	mov	ax,offset BIOS_END + BIOS_DATA
	mov	bl,PMBTYPE_USED
	call	pmb_add			; 0 to BIOS_END
	add	ax,bp
	call	pmb_add			; CPU$
	mov	dx,es
	shr	dx,12			; DX:0000h = start of the system area
	sub	ax,ax
	mov	bl,PMBTYPE_FREE
	call	pmb_add			; conventional memory below it
	inc	dx
	mov	bl,PMBTYPE_SYS
	call	pmb_add			; the system area
	mov	bl,PMBTYPE_FREE
	test	byte ptr [MEMORY_SIZE],3Fh
	jz	ia1			; no memory above the system area
	mov	ax,[MEMORY_SIZE]
	call	kb_addr			; DX:AX = end of conventional memory
	call	pmb_add			; the rest of conventional memory
ia1:	mov	dx,10h
	sub	ax,ax
	mov	bl,PMBTYPE_RSVD
	call	pmb_add			; the rest of the first 1Mb
	test	si,si			; any extended memory?
	jz	ia9			; no
	mov	ax,si
	call	kb_addr
	add	dx,10h			; DX:AX = end of extended memory
	mov	bl,PMBTYPE_FREE
	call	pmb_add			; extended memory
ia9:	mov	es:[di-(size PMB)].PMB_SIG,PMBSIG_LAST
	sub	di,SYS_PMBS
	mov	cl,5
	shr	di,cl			; DI = number of PMBs
	mov	es:[SYS_VARS].SV_NPMBS,di
	pop	ax
	ret
ENDPROC	init_arena

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_add
;
; Adds a PMB from the end of the last one (or 0) to DX:AX (a USED block is
; owned by the system).
;
; Inputs:
;	ES:DI -> next PMB, BL = PMBTYPE_*, DX:AX = end address
;
; Outputs:
;	ES:DI -> next PMB
;
DEFPROC	pmb_add
	push	ax
	push	cx
	push	dx
	push	si
	sub	cx,cx
	sub	si,si			; SI:CX = start (0 if first)
	cmp	di,SYS_PMBS
	je	pa1
	mov	cx,es:[di-(size PMB)].PMB_ADDR.LOW
	mov	si,es:[di-(size PMB)].PMB_ADDR.HIW
	add	cx,es:[di-(size PMB)].PMB_LEN.LOW
	adc	si,es:[di-(size PMB)].PMB_LEN.HIW
pa1:	mov	es:[di].PMB_SIG,PMBSIG_NEXT
	mov	es:[di].PMB_TYPE,bl
	mov	es:[di].PMB_ADDR.LOW,cx
	mov	es:[di].PMB_ADDR.HIW,si
	sub	ax,cx
	sbb	dx,si			; DX:AX = length
	mov	es:[di].PMB_LEN.LOW,ax
	mov	es:[di].PMB_LEN.HIW,dx
	sub	ax,ax
	mov	es:[di].PMB_SEL,ax
	mov	es:[di].PMB_NSEL,ax
	cmp	bl,PMBTYPE_USED
	jne	pa2
	mov	ax,MCBOWNER_SYSTEM
pa2:	mov	es:[di].PMB_OWNER,ax
	add	di,size PMB
	pop	si
	pop	dx
	pop	cx
	pop	ax
	ret
ENDPROC	pmb_add

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; a20_on
;
; Enables A20 with the 8042 keyboard controller, as on a PC AT.  Enter at
; a20_set with AH = the 8042 output port value instead (0DDh turns A20 off).
;
; Modifies:
;	AX
;
DEFPROC	a20_on
	mov	ah,0DFh			; output port: A20 on, no reset
	DEFLBL	a20_set,near
	call	kbc_wait
	mov	al,0D1h			; 8042 command: write output port
	out	64h,al
	call	kbc_wait
	mov	al,ah
	out	60h,al
	DEFLBL	kbc_wait,near		; wait for the 8042 to accept input
	push	cx
	sub	cx,cx
kw1:	in	al,64h
	test	al,02h			; is the 8042 input buffer full?
	loopnz	kw1			; yes
	pop	cx
	ret
ENDPROC	a20_on

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; kb_addr
;
; Inputs:
;	AX = Kb
;
; Outputs:
;	DX:AX = bytes
;
; Modifies:
;	CL
;
DEFPROC	kb_addr
	mov	dx,ax
	mov	cl,10
	shl	ax,cl
	mov	cl,6
	shr	dx,cl
	ret
ENDPROC	kb_addr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_cfg
;
; Looks for a CONFIG.SYS line that begins with the given text, using only
; 8086 instructions (ddcpu_init calls this before checking the CPU type).
;
; Inputs:
;	ES:BX -> DDPI
;	CS:DI -> text, preceded by its length
;
; Outputs:
;	Zero flag set if found
;
; Modifies:
;	AX, CX, SI, DS
;
DEFPROC	find_cfg
	push	es
	lds	si,es:[bx].DDP_PTR	; DS:SI -> CONFIG.SYS text
	push	cs
	pop	es
fc1:	push	si
	push	di
	mov	cl,cs:[di]
	mov	ch,0
	inc	di
	repe	cmpsb			; does this line begin with the text?
	pop	di
	pop	si
	je	fc9			; yes
fc2:	lodsb
	cmp	al,CHR_LINEFEED		; end of the line?
	je	fc1			; yes
	test	al,al			; end of CONFIG.SYS?
	jnz	fc2			; no
	inc	ax			; clear the zero flag
fc9:	pop	es
	ret
ENDPROC	find_cfg

	DEFLBL	cfg_cpu,byte
	db	6,"CPU=80"
	DEFLBL	cfg_memsize,byte
	db	8,"MEMSIZE="

	.286p
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_call
;
; Calls the function at CS:BX in protected mode, with interrupts and NMI
; disabled, CS = SEL_CPUCODE, DS = ES = SEL_SYS, and SS = SEL_STACK (the
; caller's stack), and then returns to real mode.  An 80386 returns by
; clearing PE, but an 80286 must be reset, so before switching, we set the
; CMOS shutdown code to 0Ah (which makes the BIOS resume at the address in
; 40:67h, EDGE_CNT) and point 40:67h at pm_resume; that also catches any
; "triple fault".  Any other exception goes to pm_fault, which returns to
; real mode, too.
;
; Inputs:
;	BX = offset of protected-mode function
;
; Modifies:
;	AX, DX
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pm_call
	pushf
	cli
	push	ds
	push	es
	push	bp
	mov	ds,cs:[sys_seg]
	mov	ax,ss
	mov	dx,ax
	shl	ax,4
	shr	dx,12			; DX:AX = linear address of SS
	mov	ds:[SYS_GDT+SEL_STACK].DESC_BASE,ax
	mov	ds:[SYS_GDT+SEL_STACK].DESC_BASE16,dl
	mov	ds:[SYS_VARS].SV_RMSS,ss
	mov	ds:[SYS_VARS].SV_RMSP,sp
	mov	al,8Fh			; CMOS shutdown byte (NMI disabled)
	out	70h,al
	mov	al,0Ah			; shutdown code: JMP DWORD PTR 40:67h
	out	71h,al
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	mov	[EDGE_CNT],offset pm_resume
	mov	[CRC_REG],cs
	lgdt	qword ptr ds:[SYS_VARS].SV_GDTR
	lidt	qword ptr ds:[SYS_VARS].SV_PIDTR
	smsw	ax
	or	al,1			; set PE
	lmsw	ax
	db	OP_JMPF			; flush the prefetch queue and load CS
	dw	offset pm1,SEL_CPUCODE
pm1:	mov	ax,SEL_STACK
	mov	ss,ax
	mov	ax,SEL_SYS
	mov	ds,ax
	mov	es,ax
	ASSUME	ES:NOTHING
	mov	ax,SEL_LDTD
	lldt	ax
	call	bx
;
; For now, every IDT gate points here (see ddcpu_init).  Since interrupts are
; disabled, this can only be an exception, so we abandon the function and
; return to real mode (pm_resume restores the caller's stack).
;
	DEFLBL	pm_fault,near
	mov	ax,SEL_SYS
	mov	ds,ax
	cmp	ds:[SYS_VARS].SV_TYPE,CPUTYPE_80386
	jb	pm3
	db	0Fh,20h,0C0h		; MOV EAX,CR0
	and	al,0FEh			; clear PE
	db	0Fh,22h,0C0h		; MOV CR0,EAX
	push	ds:[SYS_VARS].SV_RMCS
	push	offset pm_resume
	db	OP_RETF
pm3:	call	kbc_wait
	mov	al,0FEh			; 8042 command: pulse reset
	out	64h,al
pm4:	hlt
	jmp	pm4
;
; Both kinds of returns, and resets after any fault that pm_fault can't
; handle, end up here, in real mode with interrupts and NMI disabled.
;
pm_resume:
	mov	ds,cs:[sys_seg]
	mov	ss,ds:[SYS_VARS].SV_RMSS
	mov	sp,ds:[SYS_VARS].SV_RMSP
	lidt	qword ptr ds:[SYS_VARS].SV_RMIDTR
	mov	al,8Fh			; clear the CMOS shutdown code
	out	70h,al
	mov	al,0
	out	71h,al
	mov	al,0Dh			; and enable NMI again
	out	70h,al
	pop	bp
	pop	es
	pop	ds
	popf
	ret
ENDPROC	pm_call

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_test (called in protected mode by pm_call)
;
; Writes and reads back a pattern through ES (SEL_SYS), at the start of the
; system area (which is otherwise unused), and if that works, sets CPUF_PMOK.
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pm_test
	smsw	ax
	test	al,1			; are we in protected mode?
	jz	pt9			; no
	mov	ax,5AA5h
	xchg	es:[0],ax
	cmp	word ptr es:[0],5AA5h
	mov	es:[0],ax
	jne	pt9
	or	ds:[SYS_VARS].SV_FLAGS,CPUF_PMOK
pt9:	ret
ENDPROC	pm_test

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; idt_default
;
; Returns the default gate for an entry in the protected-mode IDT: exceptions
; (00h-02h and 06h-0Fh) go to exc_stubs, hardware interrupts (70h-7Fh) to
; irq_stubs, and everything else (software interrupts, which ring 3 may use)
; to sw_int.  Ring 3 may also issue INT 0 (eg, FPU$ signals a divide error
; with it), since its frame is the same as a divide error's.
;
; Inputs:
;	BL = IDT entry
;
; Outputs:
;	AX = offset of handler, DH = access rights
;
DEFPROC	idt_default
	mov	dh,ACC_INTGATE		; DPL 0, for exceptions and IRQs
	mov	al,bl
	sub	al,70h
	cmp	al,10h			; 70h-7Fh?
	jae	idd1			; no
	mov	ah,7			; each IRQ stub is 7 bytes
	mul	ah
	add	ax,offset DEV:irq_stubs
	ret
idd1:	mov	al,bl
	cmp	al,10h			; 00h-0Fh?
	jae	idd2			; no
	cmp	al,INT_BP
	jb	idd1a
	cmp	al,INT_UD		; 03h-05h are software interrupts
	jb	idd2
idd1a:	test	al,al			; INT 0?
	jnz	idd1b			; no
	mov	dh,ACC_INTGATE + ACC_DPL3
idd1b:	mov	ah,5			; each exception stub is 5 bytes
	mul	ah
	add	ax,offset DEV:exc_stubs
	ret
;
; Ring 3 code may issue only the software interrupts that are meant for it:
; breakpoint and overflow, DOS's vectors, the mouse, and the user vectors.
; Ring 0 code can issue any of them, but a BIOS function run for a ring 3
; program would trust whatever it was given (eg, a disk function computes its
; DMA address from a segment value), and a fault in the ROM stops the system.
;
idd2:	cmp	al,INT_PRTSC
	je	idd4			; DPL 0
	cmp	al,10h			; INT 03h or 04h?
	jb	idd3			; yes
	cmp	al,INT_MOUSE
	je	idd3
	mov	ah,al
	and	ah,0F0h
	cmp	ah,INT_DOSTERM		; DOS's vectors (20h-2Fh)?
	je	idd3			; yes
	cmp	al,R3_USERINT		; below the user vectors?
	jb	idd4			; yes
	cmp	al,R3_USERMAX		; above them?
	ja	idd4			; yes
idd3:	mov	dh,ACC_INTGATE + ACC_DPL3
idd4:	mov	ax,offset DEV:sw_int
	ret
ENDPROC	idt_default

	DEFLBL	gdt_init,byte
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_SYS
	DESC	<0,SYS_LDTTOP,0,ACC_LDT,0>		; SEL_LDTD
	DESC	<0FFFFh,0,0,ACC_CODE,0>			; SEL_CPUCODE
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_LOW
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_STACK
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_TMP
	DESC	<offset DEV:cpu_entry,SEL_CPUCODE,0,ACC_CALLGATE,0>
	DESC	<0FFFFh,BIOS_DATA,0,ACC_DATA,0>		; SEL_BIOS
	DESC	<0,0,0,0,0>				; (unused)
	DESC	<0FFFFh,BIOS_DATA+100h,0,ACC_CODE,0>	; SEL_DDINT
	DESC	<INT_DOSCALL5*4+4,0,0,ACC_CODE,0>	; SEL_C5CODE
	DESC	<INT_DOSCALL5*4,SEL_C5CODE,0,ACC_CALLGATE+ACC_DPL3,0>
	DESC	<TSS_LEN-1,SYS_TSS,0,ACC_TSS,0>		; SEL_TSS
	DEFLBL	gdt_init_end,byte
	ASSERT	<offset gdt_init_end - offset gdt_init>,EQ,<(GDT_FIXED-1)*8>

CODE	ends

DATA	segment para public 'DATA'

ddcpu_end	db	16 dup(0)

DATA	ends

	end
