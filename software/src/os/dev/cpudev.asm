;
; BASIC-DOS Processor (CPU$) Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; CPU$ is the first built-in driver.  It stores the processor type in
; CPU_TYPE, and on an 80286 or later with at least 64K of extended memory,
; it enables A20, builds a physical memory arena (see PMB in cpu.inc) and the
; GDT, IDT, and LDT in the system area (the first 64K of extended memory),
; checks that it can switch to protected mode and back, and stays loaded to
; provide the functions listed in cpu.inc through DDINT_CPU; otherwise, it
; unloads itself.  For now, the processor always returns to real mode; see
; docs/bdtech/mmu for the design and the plans for the rest of BASIC-DOS.
;
	BIOSAPI equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc

	.286p
;
; The system area is the first 64K of extended memory (aka the HMA), which is
; addressable in real mode as segment SYS_SEG (once A20 is enabled) and in
; protected mode with selector SEL_SYS (whose base is SYS_SEG * 16), so the
; same offsets work in both modes.  Offsets below 10h are the last 16 bytes
; of the ROM BIOS, and FFFF:00D0h is where a PSP's CALL 5 (F01D:FEF0h) goes
; when A20 is enabled, so we put a far jump to the INT_DOSCALL5 vector there.
;
SYS_SEG		equ	0FFFFh
SYS_CALL5	equ	00D0h
SYS_VARS	equ	0100h
SYS_PMBS	equ	0200h
PMB_MAX		equ	128
SYS_IDT		equ	SYS_PMBS + PMB_MAX * (size PMB)
IDT_MAX		equ	256
SYS_GDT		equ	SYS_IDT + IDT_MAX * 8
GDT_MAX		equ	256
SYS_LDT		equ	SYS_GDT + GDT_MAX * 8
LDT_MAX		equ	1024
SYS_END		equ	SYS_LDT + LDT_MAX * 8
;
; The linear address of any system area offset (other than the first 16
; bytes) is 10xxxxh, where xxxx is the offset minus 10h.
;
SYS_BASE16	equ	10h

SYSVARS		struc
SV_SIG		dw	?	; SIG_SYSVARS (if A20 is enabled)
SV_TYPE		db	?	; CPU type
SV_FLAGS	db	?	; CPUF_* flags
SV_NPMBS	dw	?	; number of PMBs
SV_RMSP		dw	?	; real-mode SP (while in protected mode)
SV_RMSS		dw	?	; real-mode SS (while in protected mode)
SV_RMCS		dw	?	; real-mode CS (ie, the CPU$ segment)
SV_GDTR		dw	3 dup (?) ; GDT limit and base (for LGDT)
SV_IDTR		dw	3 dup (?) ; IDT limit and base (for LIDT)
SV_RMIDTR	dw	3 dup (?) ; real-mode IDT limit and base
SV_ARG		db	?	; CPU_ALLOC: SELF_* flags
		db	?
SV_OWNER	dw	?	; CPU_ALLOC: owner
SV_LEN		dd	?	; CPU_ALLOC: length
SYSVARS		ends
SIG_SYSVARS	equ	'PC'

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
ACC_LDT		equ	82h	; present, LDT
ACC_CALLGATE	equ	84h	; present, DPL 0, 80286 call gate
ACC_INTGATE	equ	86h	; present, DPL 0, 80286 interrupt gate

SEL_TI		equ	04h	; table indicator (set for LDT selectors)
;
; Fixed GDT selectors
;
SEL_SYS		equ	08h	; data: system area
SEL_LDTD	equ	10h	; LDT
SEL_CPUCODE	equ	18h	; code: CPU$ driver
SEL_LOW		equ	20h	; data: first 64K of memory
SEL_STACK	equ	28h	; data: caller's stack (see pm_call)
SEL_TMP		equ	30h	; data: scratch (initially 110000h)
SEL_CPU		equ	38h	; call gate: cpu_entry
GDT_FIXED	equ	8	; number of fixed GDT entries

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	CPU
CPU	DDH	<offset DEV:ddcpu_end+16,,DDATTR_CHAR,offset DEV:ddcpu_init,-1,2020202024555043h>

	DEFLBL	CPU_FUNCS,word
	dw	ddcpu_getinfo, ddcpu_alloc, ddcpu_free, ddcpu_map
	dw	ddcpu_unmap, ddcpu_query

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
; DS addressing the system area (SYS_SEG in real mode, SEL_SYS in protected
; mode).  If DS doesn't address the system area (eg, a BIOS block move turned
; A20 off), we turn A20 back on.
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
DEFPROC	cpu_entry,far
	push	ds
	push	bp
	pushf
	cli
	push	bx
	push	si
	push	di
	push	ax
	smsw	ax
	test	al,1			; protected mode?
	mov	ax,SYS_SEG
	jz	ce1			; no
	mov	ax,SEL_SYS
ce1:	mov	ds,ax
	pop	ax
	cmp	ds:[SYS_VARS].SV_SIG,SIG_SYSVARS
	je	ce2
	push	ax
	call	a20_on
	pop	ax
	cmp	ds:[SYS_VARS].SV_SIG,SIG_SYSVARS
	jne	ce8
ce2:	cmp	ah,CPU_MAXFUNC		; valid function?
	ja	ce8			; no
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
	call	bp
	jmp	short ce9
ce8:	mov	ax,ERR_INVALID
	stc
ce9:	pop	di
	pop	si
	mov	bp,sp
	rcr	word ptr [bp+2],1	; replace the carry in the caller's flags
	rol	word ptr [bp+2],1	; with ours, and restore them
	pop	bx
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
;	AL = CPU type, AH = CPUF_* flags, DX:CX = length of largest free block
;
DEFPROC	ddcpu_getinfo
	call	pmb_largest
	mov	ax,word ptr ds:[SYS_VARS].SV_TYPE
	clc
	ret
ENDPROC	ddcpu_getinfo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_alloc (CPU_ALLOC)
;
; Allocates the first free block that's big enough, rounding the length up
; to a multiple of 16 (so every block starts on a paragraph boundary), and
; maps it with selectors unless SELF_NONE is set.
;
; Inputs:
;	AL = SELF_* flags, BX = owner, SI:DI = length
;
; Outputs:
;	Carry clear if successful: AX = selector, DX:CX = address
;	Carry set if error: AX = error code (if ERR_NOMEMORY, DX:CX = length
;	of largest free block)
;
DEFPROC	ddcpu_alloc
	add	di,15
	adc	si,0
	and	di,0FFF0h
	mov	cx,si
	or	cx,di			; is the length zero?
	jz	ca9			; yes
	mov	ds:[SYS_VARS].SV_ARG,al
	mov	ds:[SYS_VARS].SV_OWNER,bx
	mov	ds:[SYS_VARS].SV_LEN.LOW,di
	mov	ds:[SYS_VARS].SV_LEN.HIW,si
	mov	bx,SYS_PMBS
	mov	cx,ds:[SYS_VARS].SV_NPMBS
ca1:	cmp	ds:[bx].PMB_TYPE,PMBTYPE_FREE
	jne	ca2
	cmp	ds:[bx].PMB_LEN.HIW,si
	ja	ca3
	jb	ca2
	cmp	ds:[bx].PMB_LEN.LOW,di
	jae	ca3
ca2:	add	bx,size PMB
	loop	ca1
ca8:	call	pmb_largest
	mov	ax,ERR_NOMEMORY
	stc
	ret
ca9:	mov	ax,ERR_INVALID
	stc
	ret
ca3:	call	pmb_split		; BX -> PMB of the requested length
	jc	ca8
	sub	ax,ax			; AX = selector (none yet)
	sub	cx,cx			; CX = number of selectors
	test	ds:[SYS_VARS].SV_ARG,SELF_NONE
	jnz	ca4			; (carry is clear)
	push	bx
	mov	al,ds:[SYS_VARS].SV_ARG
	mov	cx,ds:[bx].PMB_ADDR.LOW
	mov	dx,ds:[bx].PMB_ADDR.HIW
	mov	di,ds:[bx].PMB_LEN.LOW
	mov	si,ds:[bx].PMB_LEN.HIW
	call	map_block		; AX = selector, CX = # of selectors
	pop	bx
	jnc	ca4
	call	pmb_merge		; return the block to the free memory
	jmp	ca8
ca4:	mov	ds:[bx].PMB_TYPE,PMBTYPE_USED
	mov	dx,ds:[SYS_VARS].SV_OWNER
	mov	ds:[bx].PMB_OWNER,dx
	mov	ds:[bx].PMB_SEL,ax
	mov	ds:[bx].PMB_NSEL,cx
	mov	cx,ds:[bx].PMB_ADDR.LOW
	mov	dx,ds:[bx].PMB_ADDR.HIW
	ret				; (carry is still clear)
ENDPROC	ddcpu_alloc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_free (CPU_FREE)
;
; Frees a block allocated by CPU_ALLOC, along with its selectors.
;
; Inputs:
;	DX:CX = address of block
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_BADADDR)
;
DEFPROC	ddcpu_free
	mov	bx,SYS_PMBS
	mov	si,ds:[SYS_VARS].SV_NPMBS
cf1:	cmp	ds:[bx].PMB_ADDR.LOW,cx
	jne	cf2
	cmp	ds:[bx].PMB_ADDR.HIW,dx
	jne	cf2
	cmp	ds:[bx].PMB_TYPE,PMBTYPE_USED	; only CPU_ALLOC blocks
	je	cf3				; can be freed
cf2:	add	bx,size PMB
	dec	si
	jnz	cf1
	mov	ax,ERR_BADADDR
	stc
	ret
cf3:	mov	ds:[bx].PMB_TYPE,PMBTYPE_FREE
	sub	ax,ax
	mov	ds:[bx].PMB_OWNER,ax
	sub	cx,cx
	xchg	ax,ds:[bx].PMB_SEL
	xchg	cx,ds:[bx].PMB_NSEL
	call	desc_free
	call	pmb_merge		; merge with the next block if free
	cmp	bx,SYS_PMBS
	je	cf9
	sub	bx,size PMB
	call	pmb_merge		; and the previous block if free
cf9:	clc
	ret
ENDPROC	ddcpu_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_map (CPU_MAP)
;
; Maps any physical memory (eg, a DOS memory block or video memory) with
; one or more selectors; the arena isn't checked or changed.
;
; Inputs:
;	AL = SELF_* flags, DX:CX = address, SI:DI = length
;
; Outputs:
;	Carry clear if successful: AX = selector, CX = # of selectors
;	Carry set if error: AX = error code
;
DEFPROC	ddcpu_map
	mov	bx,si
	or	bx,di			; is the length zero?
	jz	cm9			; yes
	call	map_block
	jnc	cm10
	mov	ax,ERR_NOMEMORY
	ret
cm9:	mov	ax,ERR_INVALID
	stc
cm10:	ret
ENDPROC	ddcpu_map

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_unmap (CPU_UNMAP)
;
; Frees selectors returned by CPU_MAP.
;
; Inputs:
;	BX = first selector, CX = # of selectors (0 = 1)
;
; Outputs:
;	Carry clear if successful, set if error (AX = ERR_INVALID)
;
DEFPROC	ddcpu_unmap
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
cu2:	cmp	dx,LDT_MAX		; or beyond the LDT
cu3:	ja	cu8
	call	desc_free
	clc
	ret
cu8:	mov	ax,ERR_INVALID
	stc
	ret
ENDPROC	ddcpu_unmap

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcpu_query (CPU_QUERY)
;
; Inputs:
;	BX = PMB # (0 for the first)
;	ES:DI -> buffer for PMB
;
; Outputs:
;	Carry clear if successful (PMB copied to ES:DI)
;	Carry set if no such PMB (AX = ERR_INVALID)
;
DEFPROC	ddcpu_query
	cmp	bx,ds:[SYS_VARS].SV_NPMBS	; is the PMB # valid?
	jae	cq9				; no
	shl	bx,4
	lea	si,[bx+SYS_PMBS]
	mov	cx,(size PMB) SHR 1
	rep	movsw
	clc
	ret
cq9:	mov	ax,ERR_INVALID
	stc
	ret
ENDPROC	ddcpu_query

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_largest
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
	mov	ax,ds:[bx].PMB_LEN.HIW
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
; pmb_split
;
; If the free block at BX is longer than SV_LEN, splits it in two by
; duplicating its PMB (moving it and all the PMBs after it up one entry), and
; then reduces the first to SV_LEN and the second to whatever remains.
;
; Inputs:
;	BX -> free PMB, at least SV_LEN long
;
; Outputs:
;	Carry clear if successful (BX -> PMB of length SV_LEN)
;	Carry set if the PMB table is full
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	pmb_split
	mov	ax,ds:[SYS_VARS].SV_LEN.LOW
	mov	dx,ds:[SYS_VARS].SV_LEN.HIW
	cmp	ds:[bx].PMB_LEN.LOW,ax
	jne	ps1
	cmp	ds:[bx].PMB_LEN.HIW,dx
	je	ps9			; exact fit (and carry is clear)
ps1:	mov	cx,ds:[SYS_VARS].SV_NPMBS
	cmp	cx,PMB_MAX		; is the PMB table full?
	cmc				; carry set if so
	jc	ps9
	inc	ds:[SYS_VARS].SV_NPMBS
	push	es
	push	ds
	pop	es
	shl	cx,4
	add	cx,SYS_PMBS		; CX = end of the PMB table
	mov	si,cx
	dec	si
	dec	si			; SI -> last word of the table
	lea	di,[si+size PMB]
	sub	cx,bx
	shr	cx,1			; CX = # of words to move
	std
	rep	movsw
	cld
	pop	es
	mov	ds:[bx].PMB_SIG,PMBSIG_NEXT
	mov	ds:[bx].PMB_LEN.LOW,ax
	mov	ds:[bx].PMB_LEN.HIW,dx
	add	ds:[bx+size PMB].PMB_ADDR.LOW,ax
	adc	ds:[bx+size PMB].PMB_ADDR.HIW,dx
	sub	ds:[bx+size PMB].PMB_LEN.LOW,ax
	sbb	ds:[bx+size PMB].PMB_LEN.HIW,dx
ps9:	ret
ENDPROC	pmb_split

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
	mov	al,ds:[bx+size PMB].PMB_SIG
	mov	ds:[bx].PMB_SIG,al
	push	es
	push	ds
	pop	es
	lea	di,[bx+size PMB]
	lea	si,[di+size PMB]
	mov	cx,ds:[SYS_VARS].SV_NPMBS
	dec	ds:[SYS_VARS].SV_NPMBS
	shl	cx,4
	add	cx,SYS_PMBS		; CX = end of the PMB table
	sub	cx,si
	shr	cx,1			; CX = # of words to move
	rep	movsw
	pop	es
pm9:	ret
ENDPROC	pmb_merge

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; map_block
;
; Allocates and fills in one selector for every 64K of the block (the last
; one's limit covers whatever remains).
;
; Inputs:
;	AL = SELF_* flags, DX:CX = address, SI:DI = length (non-zero)
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
	mov	cx,si
	cmp	di,1
	cmc
	adc	cx,0			; CX = # of 64K pieces
	call	desc_alloc		; AX = selector, BX -> DESC
	pop	di
	pop	si
	pop	bp
	pop	dx			; DX:BP = address
	jc	mb9
	push	ax
	push	cx
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
	pop	cx
	pop	ax
	clc
mb9:	ret
ENDPROC	map_block

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; desc_alloc
;
; Finds CX consecutive free descriptors in the GDT (after the fixed entries)
; or the LDT, and claims them by storing the access byte in each.
;
; Inputs:
;	AL = SELF_* flags, CX = # of descriptors
;
; Outputs:
;	Carry clear if successful: AX = first selector, BX -> first DESC
;	Carry set if not found
;
; Modifies:
;	AX, BX, DX, SI, DI
;
DEFPROC	desc_alloc
	mov	bx,SYS_GDT + GDT_FIXED * (size DESC)
	mov	dx,GDT_MAX - GDT_FIXED
	test	al,SELF_LDT
	jz	da1
	mov	bx,SYS_LDT
	mov	dx,LDT_MAX
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
da8:	stc
	ret
da5:	mov	ah,ACC_DATA
	test	al,SELF_CODE
	jz	da6
	mov	ah,ACC_CODE
da6:	mov	bx,di
	push	cx
da7:	mov	ds:[di].DESC_ACC,ah
	add	di,size DESC
	loop	da7
	pop	cx
	test	al,SELF_LDT
	mov	ax,bx
	jnz	da9
	sub	ax,SYS_GDT		; GDT selector = offset within GDT
	ret
da9:	sub	ax,SYS_LDT - SEL_TI	; LDT selector = offset within LDT + TI
	ret
ENDPROC	desc_alloc

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
	add	di,SYS_LDT - SYS_GDT
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
; a20_on
;
; Enables A20 with the 8042 keyboard controller, as on a PC AT.
;
; Modifies:
;	AL
;
DEFPROC	a20_on
	call	kbc_wait
	mov	al,0D1h			; 8042 command: write output port
	out	64h,al
	call	kbc_wait
	mov	al,0DFh			; output port: A20 on, no reset
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
	mov	ax,SYS_SEG
	mov	ds,ax
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
	sub	ax,ax
	mov	es,ax
	ASSUME	ES:BIOS
	mov	[EDGE_CNT],offset pm_resume
	mov	[CRC_REG],cs
	lgdt	qword ptr ds:[SYS_VARS].SV_GDTR
	lidt	qword ptr ds:[SYS_VARS].SV_IDTR
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
	DEFLBL	pm_return,near
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
	mov	ax,SYS_SEG
	mov	ds,ax
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
; pm_fault
;
; Every IDT entry points here.  Since interrupts are disabled in protected
; mode, this can only be an exception, so we abandon the protected-mode
; function and return to real mode (pm_resume restores the caller's stack).
;
DEFPROC	pm_fault
	mov	ax,SEL_SYS
	mov	ds,ax
	jmp	pm_return
ENDPROC	pm_fault
;
; Everything from here on is discarded after initialization (see DDPI_END).
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Only 8086 instructions may be used until the CPU type is known.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated (left zero if we're not staying)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, DS
;
DEFPROC	ddcpu_init,far
	mov	cs:[0].DDH_REQUEST,offset DEV:ddcpu_req
	push	es
	push	bx
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
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
di2:	mov	[CPU_TYPE],al
	cmp	al,CPUTYPE_80286	; protected mode available?
	jb	di9			; no
;
; We need at least 64K of extended memory for the system area.
;
	mov	ah,CAS_GETEXTMEM
	int	INT_CASSETTE
	jc	di9
	cmp	ax,64			; enough extended memory?
	jb	di9			; no
	xchg	si,ax			; SI = Kb of extended memory
	call	a20_on
;
; Make sure A20 is enabled before writing anything to the system area: if
; it's not, then writing SYS_VARS changes its wrap-around alias in low memory.
;
	mov	ax,SYS_SEG
	mov	es,ax
	ASSUME	ES:NOTHING
	mov	bx,ds:[SYS_VARS-10h]	; BX = word at the low memory alias
	mov	ax,bx
	not	ax
	mov	es:[SYS_VARS].SV_SIG,ax
	cmp	ds:[SYS_VARS-10h],ax	; did the alias change?
	mov	ds:[SYS_VARS-10h],bx	; (restore it, in case it did)
	jne	di3			; no, so A20 is enabled
di9:	pop	bx
	pop	es
	ret
;
; Clear the system area, and then fill in SYSVARS, the PMBs, GDT, and IDT.
;
di3:	mov	di,10h
	mov	cx,(SYS_END - 10h) SHR 1
	sub	ax,ax
	rep	stosw
	mov	byte ptr es:[SYS_CALL5],OP_JMPF
	mov	word ptr es:[SYS_CALL5+1],INT_DOSCALL5 * 4

	mov	di,SYS_VARS
	mov	es:[di].SV_SIG,SIG_SYSVARS
	mov	al,[CPU_TYPE]
	mov	es:[di].SV_TYPE,al
	mov	es:[di].SV_RMCS,cs
	mov	es:[di].SV_GDTR,GDT_MAX * (size DESC) - 1
	mov	es:[di].SV_GDTR+2,SYS_GDT - 10h
	mov	byte ptr es:[di].SV_GDTR+4,SYS_BASE16
	mov	es:[di].SV_IDTR,IDT_MAX * (size DESC) - 1
	mov	es:[di].SV_IDTR+2,SYS_IDT - 10h
	mov	byte ptr es:[di].SV_IDTR+4,SYS_BASE16
	mov	es:[di].SV_RMIDTR,3FFh
;
; The arena describes conventional memory (DOS's), everything else below 1Mb
; (reserved), the system area, and the rest of extended memory (free).
;
	mov	ax,[MEMORY_SIZE]
	mov	dx,ax
	shl	ax,10
	shr	dx,6			; DX:AX = conventional memory size
	mov	di,SYS_PMBS
	mov	bl,PMBTYPE_DOS
	sub	cx,cx
	push	dx
	push	ax
	mov	bp,dx
	sub	dx,dx
	call	init_pmb		; PMB 0 = 0 to DX:AX
	pop	cx
	pop	dx			; DX:CX = end of conventional memory
	sub	ax,ax
	sub	ax,cx
	mov	bp,10h
	sbb	bp,dx			; BP:AX = 1Mb - DX:CX
	mov	bl,PMBTYPE_RSVD
	call	init_pmb		; PMB 1 = DX:CX to 1Mb
	sub	cx,cx
	mov	dx,10h
	sub	ax,ax
	mov	bp,1
	mov	bl,PMBTYPE_SYS
	call	init_pmb		; PMB 2 = 1Mb to 1Mb + 64K
	mov	ax,si
	mov	bp,ax
	shl	ax,10
	shr	bp,6
	dec	bp			; BP:AX = extended memory less 64K
	mov	dx,ax
	or	dx,bp			; any extended memory left?
	jz	di4			; no
	sub	cx,cx
	mov	dx,11h
	mov	bl,PMBTYPE_FREE
	call	init_pmb		; PMB 3 = 1Mb + 64K to the end
di4:	mov	byte ptr es:[di-(size PMB)].PMB_SIG,PMBSIG_LAST
	sub	di,SYS_PMBS
	shr	di,4
	mov	es:[SYS_VARS].SV_NPMBS,di

	push	cs
	pop	ds
	ASSUME	DS:NOTHING
	mov	si,offset DEV:gdt_init
	mov	di,SYS_GDT + (size DESC)
	mov	cx,offset DEV:gdt_init_end - offset DEV:gdt_init
	rep	movsb
	mov	ax,cs
	mov	dx,ax
	shl	ax,4
	shr	dx,12			; DX:AX = linear address of CS
	mov	es:[SYS_GDT+SEL_CPUCODE].DESC_BASE,ax
	mov	es:[SYS_GDT+SEL_CPUCODE].DESC_BASE16,dl

	mov	di,SYS_IDT
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
; Switch to protected mode and back; we stay only if the test succeeds.
;
	mov	bx,offset DEV:pm_test
	call	pm_call
	mov	ax,SYS_SEG
	mov	ds,ax
	ASSUME	DS:NOTHING
	sub	ax,ax			; AX = DDPI_END (zero if not staying)
	test	ds:[SYS_VARS].SV_FLAGS,CPUF_PMOK
	jz	di8
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	[DDINT_CPU],OP_JMPF
	mov	word ptr [DDINT_CPU+1],offset DEV:cpu_entry
	mov	word ptr [DDINT_CPU+3],cs
	mov	ax,offset DEV:ddcpu_init
di8:	pop	bx
	pop	es
	mov	es:[bx].DDPI_END.OFF,ax
	ret
ENDPROC	ddcpu_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_pmb
;
; Inputs:
;	ES:DI -> PMB
;	BL = PMBTYPE_*
;	DX:CX = address
;	BP:AX = length
;
; Outputs:
;	ES:DI -> next PMB
;
; Modifies:
;	DI
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	init_pmb
	mov	es:[di].PMB_SIG,PMBSIG_NEXT
	mov	es:[di].PMB_TYPE,bl
	mov	es:[di].PMB_ADDR.LOW,cx
	mov	es:[di].PMB_ADDR.HIW,dx
	mov	es:[di].PMB_LEN.LOW,ax
	mov	es:[di].PMB_LEN.HIW,bp
	add	di,size PMB
	ret
ENDPROC	init_pmb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_test (called in protected mode by pm_call)
;
; Writes and reads back a pattern at the start of free extended memory
; (which real mode can't reach), and if that works, sets CPUF_PMOK.
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pm_test
	smsw	ax
	test	al,1			; are we in protected mode?
	jz	pt9			; no
	mov	ax,SEL_TMP
	mov	es,ax
	mov	ax,5AA5h
	xchg	es:[0],ax
	cmp	word ptr es:[0],5AA5h
	mov	es:[0],ax
	jne	pt9
	or	ds:[SYS_VARS].SV_FLAGS,CPUF_PMOK
pt9:	ret
ENDPROC	pm_test

	DEFLBL	gdt_init,byte
	DESC	<0FFFFh,0FFF0h,0Fh,ACC_DATA,0>		; SEL_SYS (FFFF0h)
	DESC	<LDT_MAX*(size DESC)-1,SYS_LDT-10h,SYS_BASE16,ACC_LDT,0>
	DESC	<0FFFFh,0,0,ACC_CODE,0>			; SEL_CPUCODE
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_LOW
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_STACK
	DESC	<0FFFFh,0,11h,ACC_DATA,0>		; SEL_TMP
	DESC	<offset DEV:cpu_entry,SEL_CPUCODE,0,ACC_CALLGATE,0>
	DEFLBL	gdt_init_end,byte

CODE	ends

DATA	segment para public 'DATA'

ddcpu_end	db	16 dup(0)

DATA	ends

	end
