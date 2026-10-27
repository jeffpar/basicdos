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
; A "CPU=8088" line in CONFIG.SYS makes CPU$ act as it does on an 8088, and
; "CPU=PROBE" runs an experimental probe of the ROM BIOS in protected mode
; (see pm_probe).
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

;
; The protected-mode probe (see pm_probe) uses the system area beyond the
; tables: SYS_LOG for PROBELOG and its events (PROBEEVT), SYS_TSS for a TSS,
; SYS_PIDT for an IDT, and the rest, up to SYS_STK0, for its ring 0 stack.
; Its GDT is the 64K at SEL_TMP (110000h), and its ring 3 data segment is the
; scratch buffer at DDPI_BUFPTR.
;
SYS_LOG		equ	SYS_END
SYS_TSS		equ	SYS_LOG + 400h
SYS_PIDT	equ	SYS_TSS + 100h
SYS_STK0	equ	SYS_PIDT + IDT_MAX * 8 + 1000h
PB_SIZE		equ	800h	; size of the ring 3 data segment

PROBELOG	struc
PL_STATUS	dw	?	; PLS_*
PL_VEC		dw	?	; the exception that ended the probe, if any
PL_ERR		dw	?	; its error code (or AX, if none)
PL_FIP		dw	?	; its IP
PL_FCS		dw	?	; and its CS
PL_NINTS	dw	?	; software interrupts reflected
PL_NIRQS	dw	?	; hardware interrupts reflected
PL_NFIX		dw	?	; null selectors replaced with SEL_LOW
PL_NEVENTS	dw	?	; events logged
PL_TARGET	dd	?	; handler being called (see reflect_prep)
PL_ES13		dw	?	; caller's ES and BX, while an INT 13h
PL_BX13		dw	?	; buffer uses an identity selector
PL_R0SP		dw	?	; pm_call's SP (restored by probe_exit)
PL_PICMASK	db	?	; master PIC mask
		db	?
PL_GDTR		dw	3 dup (?) ; probe GDT limit and base (for LGDT)
PL_IDTR		dw	3 dup (?) ; probe IDT limit and base (for LIDT)
PL_BUF		dd	?	; linear address of the ring 3 data segment
PL_R3		dw	8 dup (?) ; ring 3 registers (PUSHA order)
		dw	?
PROBELOG	ends

PLS_RUN		equ	1	; running
PLS_DONE	equ	2	; ring 3 finished (see PL_R3)
PLS_FAULT	equ	3	; an exception ended it (see PL_VEC)
PLS_RESET	equ	4	; a reset (eg, a triple fault) ended it

PROBEEVT	struc
PE_KIND		db	?	; event kind (see log_event)
PE_VEC		db	?	; vector
PE_VAL		dw	?	; caller's AX (or the error code)
PE_IP		dw	?	; caller's IP
PE_CS		dw	?	; caller's CS
PROBEEVT	ends
PL_MAXEV	equ	(SYS_TSS - SYS_LOG - size PROBELOG) / (size PROBEEVT)

SEL_TSS		equ	SEL_STACK	; probe GDT: TSS (instead of SEL_STACK)
SEL_R3CODE	equ	00h+SEL_TI+3	; probe LDT: CPU$'s code, DPL 3
SEL_R3DATA	equ	08h+SEL_TI+3	; probe LDT: ring 3 data and stack
SEL_R3EXIT	equ	10h+SEL_TI+3	; probe LDT: call gate to probe_exit
ACC_TSS		equ	81h	; present, DPL 0, available 80286 TSS
ACC_DPL3	equ	60h	; DPL 3 (added to another ACC_* value)
FL_RESULTS	equ	FL_CARRY OR FL_ZERO OR FL_SIGN OR FL_OVFL

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
	rcr	word ptr [bp+2],1	; replace the caller's carry flag
	rol	word ptr [bp+2],1	; with ours, and restore its flags
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
	mov	di,offset DEV:cfg_8088
	call	find_cfg		; is there a "CPU=8088" line?
	mov	ax,0			; (AL = CPUTYPE_8086)
	mov	ds,ax
	ASSUME	DS:BIOS
	je	di2			; yes, so act as if this is an 8088
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
	mov	bp,sp
	les	bx,dword ptr [bp]	; ES:BX -> DDPI
	call	probe_init		; run the probe, if requested
	sub	ax,ax
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

	DEFLBL	cfg_8088,byte
	db	8,"CPU=8088"

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Protected-mode probe
;
; If CONFIG.SYS has a "CPU=PROBE" line, ddcpu_init calls pm_probe (through
; pm_call) to see how far the ROM BIOS gets when it runs in protected mode,
; at ring 0, on behalf of code at ring 3.  pm_probe builds:
;
;   - a GDT (in the 64K at SEL_TMP) whose entries after the fixed ones are
;     "identity" descriptors, whose bases are their selectors times 16, so
;     real-mode segment values that are multiples of 8 (eg, 40h, B800h, and
;     F000h) work unchanged at ring 0, as does arithmetic on such values (eg,
;     the diskette DMA address, ES * 16 + BX); RAM below C000h gets data
;     descriptors, and the adapter and system ROMs get code descriptors;
;   - a TSS, for its ring 0 stack in the system area;
;   - LDT entries for ring 3: CPU$'s code, a data segment (the scratch buffer
;     at DDPI_BUFPTR), and a call gate to probe_exit;
;   - an IDT whose software interrupt gates (DPL 3, so ring 3 can use them)
;     go to sw_int, whose hardware interrupt gates (the master PIC moves to
;     78h, next to the slave's 70h) go to irq_stubs, and whose exception gates
;     go to exc_stubs.
;
; sw_int and irq_common "reflect" each interrupt to the real-mode vector's
; handler, which must have an identity code selector (eg, F000h); exc_common
; replaces a null DS or ES at ring 0 with SEL_LOW (the BIOS often loads DS
; with zero) and ends the probe on any other exception.  Every one of these
; events is logged in PROBELOG (until it's full), which a debugger can dump
; at 1039F0h, and probe_report prints a summary.
;
; pm_probe "returns" to probe3 at ring 3, which makes a series of BIOS calls,
; including a diskette read, and waits for the timer to tick before calling
; probe_exit, which restores the GDT, IDT, and PIC and returns to pm_call.
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
;
; Hardware interrupt stubs for vectors 70h-7Fh; each one loads AL with its
; IRQ's real-mode vector.
;
	DEFLBL	irq_stubs,near
	IRP	v,<70h,71h,72h,73h,74h,75h,76h,77h,8,9,0Ah,0Bh,0Ch,0Dh,0Eh,0Fh>
	pusha
	mov	al,v
	jmp	short irq_common
	ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; irq_common
;
; Reflects a hardware interrupt to its real-mode handler; if there's no
; handler we can call, we simply end the interrupt.
;
; Inputs:
;	AL = real-mode vector
;	PUSHA frame on the stack
;
DEFPROC	irq_common
	mov	bp,sp
	push	ds
	mov	ah,al
	mov	al,'I'
	call	reflect_prep
	jc	ic8
	inc	ss:[SYS_LOG].PL_NIRQS
	pop	ds
	popa
	pushf
	call	dword ptr ss:[SYS_LOG].PL_TARGET
	iret
ic8:	mov	al,20h			; EOI both PICs
	out	0A0h,al
	out	20h,al
	pop	ds
	popa
	iret
ENDPROC	irq_common
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
; These vectors are also real-mode interrupts, so if the frame (without an
; error code) returns to an INT for this vector, we reflect it instead (eg,
; a BIOS's IRQ 9 handler does INT 0Ah).  If a general protection fault with
; a zero error code occurred at ring 0 while DS (or ES) held a null selector,
; we load SEL_LOW (whose base is zero) and retry the instruction; any other
; exception ends the probe.
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
	jnz	ex0			; no
	lsl	dx,cx			; DX = its limit
	mov	si,[bp+16]		; SI = IP (if there's no error code)
	cmp	si,2
	jb	ex0
	dec	si
	cmp	si,dx			; is SI within the limit?
	ja	ex0			; no
	push	ds
	mov	ds,cx
	mov	al,OP_INT
	cmp	[si-1],ax		; is there an INT for this vector?
	pop	ds
	jne	ex0			; no
	jmp	sw_int1			; yes
ex0:	lea	si,[bp+14]		; SS:SI -> AX, IP, and CS
	mov	cl,ah
	mov	dx,1
	shl	dx,cl
	test	dx,3D00h		; error code? (08h and 0Ah-0Dh)
	jz	ex8
	inc	si
	inc	si			; SS:SI -> error code, IP, and CS
	cmp	ah,0Dh			; general protection fault?
	jne	ex8			; no
	cmp	word ptr ss:[si],0	; with a zero error code?
	jne	ex8			; no
	test	byte ptr ss:[si+4],3	; at ring 0?
	jnz	ex8			; no
	mov	al,'F'
	mov	cx,SEL_LOW
	mov	dx,ds
	cmp	dx,4			; is DS a null selector?
	jae	ex1			; no
	mov	ds,cx
	jmp	short ex2
ex1:	mov	dx,es
	cmp	dx,4			; is ES a null selector?
	jae	ex8			; no
	mov	es,cx
ex2:	call	log_event
	inc	ss:[SYS_LOG].PL_NFIX
	popa
	add	sp,2			; discard the error code
	iret
ex8:	mov	al,'X'
	call	log_event
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	byte ptr ds:[SYS_LOG].PL_VEC,ah
	mov	di,SYS_LOG + PL_ERR
	mov	cx,3
	rep	movsw			; copy error code (or AX), IP, CS
	mov	ds:[SYS_LOG].PL_STATUS,PLS_FAULT
	jmp	probe_end
ENDPROC	exc_common

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sw_int
;
; Reflects a software interrupt to its real-mode handler, getting the vector
; from the caller's INT instruction, and returns the handler's result flags
; (CF, ZF, SF, and OF) to the caller; if there's no handler we can call, the
; caller gets carry set.  For INT 13h functions with a buffer at ES:BX, ES:BX
; becomes an identity selector and offset for the same address while the
; handler runs, so that the BIOS calculates the right DMA address.
;
DEFPROC	sw_int
	pusha
	DEFLBL	sw_int1,near		; exc_common goes here for an INT
	mov	bp,sp
	push	ds
	lds	si,dword ptr [bp+16]	; DS:SI -> caller's next instruction
	mov	ax,[si-2]
	cmp	al,OP_INT		; INT n?
	je	si1			; yes (AH = n)
	mov	ah,INT_BP
	cmp	byte ptr [si-1],OP_INT03; INT3?
	je	si1			; yes
	mov	ax,(0FFh SHL 8) OR 'N'	; no, so log an unknown vector
	lea	si,[bp+14]
	call	log_event
si8:	or	byte ptr [bp+20],FL_CARRY
	pop	ds
	popa
	iret
si1:	mov	al,'S'
	call	reflect_prep
	jc	si8
	inc	ss:[SYS_LOG].PL_NINTS
	cmp	ah,INT_FDC
	jne	si3
	mov	al,[bp+15]		; AL = caller's AH
	sub	al,FDC_READ
	cmp	al,FDC_FORMAT - FDC_READ + 1
	jae	si3			; no buffer at ES:BX
	mov	ax,es
	call	sel_base
	add	ax,[bp+8]
	adc	dx,0			; DX:AX = address of ES:BX
	cmp	dx,10h			; below 1Mb?
	jae	si8			; no
	mov	cx,ax
	and	cx,7Fh			; CX = offset from an identity selector
	shr	ax,4
	shl	dx,12
	or	ax,dx
	and	al,0F8h			; AX = identity selector
	mov	ss:[SYS_LOG].PL_ES13,es
	push	word ptr [bp+8]
	pop	ss:[SYS_LOG].PL_BX13
	mov	es,ax
	mov	[bp+8],cx
si3:	pop	ds
	popa
	pushf
	call	dword ptr ss:[SYS_LOG].PL_TARGET
	push	bp
	mov	bp,sp
	pushf
	push	ax
	cmp	ss:[SYS_LOG].PL_ES13,0	; did we replace ES:BX?
	je	si4			; no
	mov	es,ss:[SYS_LOG].PL_ES13
	mov	bx,ss:[SYS_LOG].PL_BX13
	mov	ss:[SYS_LOG].PL_ES13,0
si4:	mov	ax,[bp-2]		; AX = handler's flags
	and	ax,FL_RESULTS
	and	word ptr [bp+6],NOT FL_RESULTS
	or	[bp+6],ax		; update the caller's flags
	pop	ax
	add	sp,2
	pop	bp
	iret
ENDPROC	sw_int

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; reflect_prep
;
; Sets PL_TARGET to the real-mode vector's handler and logs the event.
;
; Inputs:
;	AL = event kind, AH = real-mode vector
;	BP -> PUSHA frame (followed by the caller's IP and CS)
;
; Outputs:
;	Carry clear if the handler can be called (it has an identity code
;	selector), set if not (and the event is logged as 'N')
;
; Modifies:
;	BX, CX, SI, DS
;
DEFPROC	reflect_prep
	push	ax
	mov	bx,SEL_LOW
	mov	ds,bx
	mov	bl,ah
	mov	bh,0
	shl	bx,2			; DS:BX -> real-mode vector
	mov	cx,[bx]
	mov	bx,[bx+2]
	mov	ss:[SYS_LOG].PL_TARGET.OFF,cx
	mov	ss:[SYS_LOG].PL_TARGET.SEG,bx
	test	bl,7			; is the segment an identity selector
	jnz	rp8
	cmp	bx,0C000h		; with a code descriptor?
	jae	rp9			; yes (and carry is clear)
rp8:	mov	al,'N'
	stc
rp9:	lea	si,[bp+14]		; SS:SI -> caller's AX, IP, and CS
	pushf
	call	log_event
	popf
	pop	ax
	ret
ENDPROC	reflect_prep

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; log_event
;
; Adds an event to PROBELOG, unless it's full or the event repeats the last
; one (eg, in a polling loop).  The kinds are 'S' (software interrupt
; reflected), 'I' (hardware interrupt reflected), 'N' (interrupt not
; reflected), 'F' (null selector replaced), and 'X' (exception that ended the
; probe).
;
; Inputs:
;	AL = kind, AH = vector
;	SS:SI -> caller's AX (or the error code), IP, and CS
;
; Modifies:
;	Flags only
;
DEFPROC	log_event
	push	bx
	mov	bx,ss:[SYS_LOG].PL_NEVENTS
	cmp	bx,PL_MAXEV
	jae	le9
	shl	bx,3
	add	bx,SYS_LOG + size PROBELOG
	cmp	word ptr ss:[bx-(size PROBEEVT)].PE_KIND,ax
	jne	le1
	push	ax
	mov	ax,ss:[si+2]
	cmp	ss:[bx-(size PROBEEVT)].PE_IP,ax
	jne	le0
	mov	ax,ss:[si+4]
	cmp	ss:[bx-(size PROBEEVT)].PE_CS,ax
le0:	pop	ax
	je	le9			; same as the last event
le1:	inc	ss:[SYS_LOG].PL_NEVENTS
	mov	word ptr ss:[bx].PE_KIND,ax
	push	word ptr ss:[si]
	pop	ss:[bx].PE_VAL
	push	word ptr ss:[si+2]
	pop	ss:[bx].PE_IP
	push	word ptr ss:[si+4]
	pop	ss:[bx].PE_CS
le9:	pop	bx
	ret
ENDPROC	log_event

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sel_base
;
; Inputs:
;	AX = selector (in the probe GDT or the LDT)
;
; Outputs:
;	DX:AX = its base address
;
; Modifies:
;	AX, BX, DX, DS
;
DEFPROC	sel_base
	mov	bx,ax
	and	bx,NOT 7
	mov	dx,SEL_TMP		; the probe GDT
	test	al,SEL_TI
	jz	sb1
	add	bx,SYS_LDT
	mov	dx,SEL_SYS
sb1:	mov	ds,dx
	mov	ax,[bx].DESC_BASE
	mov	dl,[bx].DESC_BASE16
	mov	dh,0
	ret
ENDPROC	sel_base

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pic_init
;
; Initializes the master PIC with a new vector base and the PL_PICMASK mask.
;
; Inputs:
;	AH = vector base
;	DS = system area (SYS_SEG or SEL_SYS)
;
; Modifies:
;	AL
;
DEFPROC	pic_init
	mov	al,11h			; ICW1: edge-triggered, cascade, ICW4
	out	20h,al
	mov	al,ah
	out	21h,al			; ICW2: vector base
	mov	al,04h
	out	21h,al			; ICW3: slave on IRQ 2
	mov	al,01h
	out	21h,al			; ICW4: 8086 mode
	mov	al,ds:[SYS_LOG].PL_PICMASK
	out	21h,al
	ret
ENDPROC	pic_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; stodesc
;
; Inputs:
;	AX = limit (or gate offset), CX = base (or gate selector)
;	DL = base bits 23-16 (or zero), DH = access byte
;	ES:DI -> descriptor
;
; Outputs:
;	ES:DI -> next descriptor
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	stodesc
	stosw
	xchg	ax,cx
	stosw
	xchg	ax,dx
	stosw
	sub	ax,ax
	stosw
	ret
ENDPROC	stodesc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; probe_exit (ring 3 calls it through SEL_R3EXIT)
;
; Saves ring 3's registers in PL_R3; then, at probe_end (where exc_common
; also goes), restores the PIC, GDT, IDT, and pm_call's stack, and returns
; to pm_call.
;
DEFPROC	probe_exit
	cli
	pusha
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	si,sp
	mov	di,SYS_LOG + PL_R3
	mov	cx,8
	rep	movsw
	mov	ds:[SYS_LOG].PL_STATUS,PLS_DONE
	DEFLBL	probe_end,near		; DS = ES = SEL_SYS
	mov	di,SYS_LDT
	mov	cx,3 * (size DESC) SHR 1
	sub	ax,ax
	rep	stosw			; free the ring 3 LDT entries
	mov	ah,08h
	call	pic_init		; move the master PIC back to 08h
	mov	al,20h			; and EOI both PICs, in case an
	out	0A0h,al			; exception interrupted a handler
	out	20h,al
	lgdt	qword ptr ds:[SYS_VARS].SV_GDTR
	lidt	qword ptr ds:[SYS_VARS].SV_IDTR
	mov	ax,SEL_STACK
	mov	ss,ax
	mov	sp,ds:[SYS_LOG].PL_R0SP
	ret
ENDPROC	probe_exit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; probe3 (runs at ring 3, with SS = SEL_R3DATA)
;
; Makes some BIOS calls and waits for a second of timer ticks, and then calls
; probe_exit with these results:
;
;	AX = INT 13h result (reading drive A's first sector into DS:0)
;	BX = that sector's signature (AA55h if it was read)
;	CX = timer ticks counted (18 or more if IRQ 0 works)
;	DX = INT 12h result (Kb of conventional memory)
;	SI = INT 15h CAS_GETEXTMEM result (Kb of extended memory)
;	DI = INT 11h result (equipment flags)
;
DEFPROC	probe3
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	si,offset DEV:probe_msg
p3a:	lods	byte ptr cs:[si]
	test	al,al
	jz	p3b
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	jmp	p3a
p3b:	int	INT_EQUIP
	push	ax
	int	INT_MEMORY
	push	ax
	mov	ah,CAS_GETEXTMEM
	int	INT_CASSETTE
	push	ax
	mov	ah,KBD_CHECK
	int	INT_KBD
	mov	ah,FDC_RESET
	sub	dx,dx			; DL = drive 0
	int	INT_FDC
	mov	ax,(FDC_READ SHL 8) OR 1
	mov	cx,0001h		; cylinder 0, sector 1
	sub	dx,dx			; head 0, drive 0
	sub	bx,bx			; ES:BX -> start of our data segment
	int	INT_FDC
	push	ax
	mov	ah,TIME_GETTICKS
	int	INT_TIME
	mov	si,dx
	sub	di,di
p3c:	mov	ah,TIME_GETTICKS
	int	INT_TIME
	sub	dx,si			; DX = ticks so far
	cmp	dx,18			; one second?
	jae	p3d			; yes
	dec	di
	jnz	p3c			; keep waiting (for a while)
p3d:	mov	cx,dx
	pop	ax
	mov	bx,ds:[510]
	pop	si
	pop	dx
	pop	di
	db	OP_CALLF		; call probe_exit
	dw	0,SEL_R3EXIT
ENDPROC	probe3

	DEFLBL	probe_msg,byte
	db	"CPU$ ring 3",13,10,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_probe (called in protected mode by pm_call)
;
; Builds the probe's GDT, TSS, LDT entries, and IDT, moves the master PIC,
; and "returns" to probe3 at ring 3.
;
; Inputs:
;	DS = ES = SEL_SYS
;
DEFPROC	pm_probe
	mov	ds:[SYS_LOG].PL_R0SP,sp
	mov	ds:[SYS_LOG].PL_STATUS,PLS_RUN
	mov	ax,SEL_LOW
	mov	es,ax
	ASSUME	ES:BIOS
	mov	[EDGE_CNT],offset DEV:probe_resume ; where an 80286 resets to
	mov	ax,SEL_TMP
	mov	es,ax
	ASSUME	ES:NOTHING
	sub	di,di
	mov	si,SYS_GDT
	mov	cx,GDT_FIXED * (size DESC) SHR 1
	rep	movsw			; copy the fixed GDT entries
	mov	bx,GDT_FIXED		; BX = index of the next entry
pp1:	mov	cx,bx
	shl	cx,7			; CX = base bits 15-0 (index * 128)
	mov	dx,bx
	shr	dx,9			; DL = base bits 23-16
	mov	dh,ACC_DATA
	cmp	bh,0C000h SHR 11	; selector C000h or higher?
	jb	pp2			; no
	mov	dh,ACC_CODE
pp2:	mov	ax,0FFFFh
	call	stodesc
	inc	bx
	cmp	bh,20h			; all 8192 entries (64K) done?
	jb	pp1			; no
	mov	di,SEL_TSS
	mov	ax,2Bh			; TSS limit (44 bytes)
	mov	cx,SYS_TSS - 10h
	mov	dx,(ACC_TSS SHL 8) OR SYS_BASE16
	call	stodesc
	push	ds
	pop	es
	mov	word ptr ds:[SYS_TSS+2],SYS_STK0	; TSS SP0
	mov	word ptr ds:[SYS_TSS+4],SEL_SYS		; TSS SS0
	mov	di,SYS_LDT
	mov	ax,0FFFFh
	mov	cx,ds:[SYS_GDT+SEL_CPUCODE].DESC_BASE
	mov	dl,ds:[SYS_GDT+SEL_CPUCODE].DESC_BASE16
	mov	dh,ACC_CODE + ACC_DPL3
	call	stodesc			; SEL_R3CODE
	mov	ax,PB_SIZE - 1
	mov	cx,ds:[SYS_LOG].PL_BUF.LOW
	mov	dl,byte ptr ds:[SYS_LOG].PL_BUF.HIW
	mov	dh,ACC_DATA + ACC_DPL3
	call	stodesc			; SEL_R3DATA
	mov	ax,offset DEV:probe_exit
	mov	cx,SEL_CPUCODE
	mov	dx,(ACC_CALLGATE + ACC_DPL3) SHL 8
	call	stodesc			; SEL_R3EXIT

	mov	di,SYS_PIDT
	sub	bx,bx			; BX = vector
pp3:	mov	ax,bx
	mov	dh,ACC_INTGATE		; DPL 0, for exceptions and IRQs
	sub	al,70h
	cmp	al,10h			; 70h-7Fh?
	jae	pp4			; no
	mov	cx,offset DEV:irq_stubs
	jmp	short pp5
pp4:	mov	ax,bx
	cmp	al,10h			; 00h-0Fh?
	jae	pp6			; no
	cmp	al,INT_BP
	jb	pp4a
	cmp	al,INT_UD		; 03h-05h are software interrupts
	jb	pp6
pp4a:	mov	cx,offset DEV:exc_stubs
pp5:	mov	ah,5			; each stub is 5 bytes
	mul	ah
	add	ax,cx
	jmp	short pp7
pp6:	mov	ax,offset DEV:sw_int
	mov	dh,ACC_INTGATE + ACC_DPL3
pp7:	mov	cx,SEL_CPUCODE
	mov	dl,0
	call	stodesc
	inc	bl
	jnz	pp3

	mov	ds:[SYS_LOG].PL_GDTR,0FFFFh
	mov	byte ptr ds:[SYS_LOG].PL_GDTR+4,11h
	mov	ds:[SYS_LOG].PL_IDTR,IDT_MAX * (size DESC) - 1
	mov	ds:[SYS_LOG].PL_IDTR+2,SYS_PIDT - 10h
	mov	byte ptr ds:[SYS_LOG].PL_IDTR+4,SYS_BASE16
	lgdt	qword ptr ds:[SYS_LOG].PL_GDTR
	lidt	qword ptr ds:[SYS_LOG].PL_IDTR
	mov	ax,SEL_TSS
	ltr	ax
	in	al,21h
	mov	ds:[SYS_LOG].PL_PICMASK,al
	mov	ah,78h
	call	pic_init		; move the master PIC to 78h
	mov	ax,SEL_SYS
	mov	ss,ax
	mov	sp,SYS_STK0
	push	SEL_R3DATA		; ring 3 SS:SP
	push	PB_SIZE
	push	FL_INTS			; ring 3 flags (interrupts on, IOPL 0)
	push	SEL_R3CODE
	push	offset DEV:probe3
	iret				; "return" to ring 3
ENDPROC	pm_probe

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; probe_resume
;
; An 80286 resets to here (instead of pm_resume) while the probe is set up;
; if the probe was still running (eg, a triple fault), we move the master
; PIC back before going on to pm_resume.
;
DEFPROC	probe_resume,far
	mov	ax,SYS_SEG
	mov	ds,ax
	cmp	ds:[SYS_LOG].PL_STATUS,PLS_RUN
	jne	rs9
	mov	ds:[SYS_LOG].PL_STATUS,PLS_RESET
	mov	ss,ds:[SYS_VARS].SV_RMSS
	mov	sp,ds:[SYS_VARS].SV_RMSP
	mov	ah,08h
	call	pic_init
rs9:	jmp	pm_resume
ENDPROC	probe_resume
;
; probe_report prints each label below, followed by the PROBELOG word
; at the offset after it.
;
	DEFLBL	probe_fields,byte
	db	"CPU$ probe: status ",0,PL_STATUS
	db	", ints ",0,PL_NINTS
	db	", irqs ",0,PL_NIRQS
	db	", fixes ",0,PL_NFIX
	db	", events ",0,PL_NEVENTS
	db	13,10,"fault ",0,PL_VEC
	db	", error ",0,PL_ERR
	db	" at ",0,PL_FCS
	db	":",0,PL_FIP
	db	13,10,"disk ",0,PL_R3+14
	db	", sig ",0,PL_R3+8
	db	", ticks ",0,PL_R3+12
	db	", mem ",0,PL_R3+10
	db	", ext ",0,PL_R3+2
	db	", equip ",0,PL_R3
	db	13,10,0,-1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; probe_report
;
; Prints the probe's results (see probe_fields) with the BIOS.
;
; Modifies:
;	AX, BX, CX, SI, DI, DS
;
DEFPROC	probe_report
	mov	ax,SYS_SEG
	mov	ds,ax
	mov	si,offset DEV:probe_fields
pr1:	lods	byte ptr cs:[si]
	test	al,al			; end of label?
	jz	pr2			; yes
	call	pr8
	jmp	pr1
pr2:	lods	byte ptr cs:[si]	; AL = PROBELOG offset
	cmp	al,-1			; end of fields?
	je	pr9			; yes
	cbw
	xchg	di,ax
	mov	ax,ds:[SYS_LOG+di]
	mov	cx,4
pr3:	rol	ax,4
	push	ax
	and	al,0Fh
	add	al,90h			; convert the low nibble to hex
	daa
	adc	al,40h
	daa
	call	pr8
	pop	ax
	loop	pr3
	jmp	pr1
pr8:	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
pr9:	ret
ENDPROC	probe_report

	DEFLBL	probe_cfg,byte
	db	9,"CPU=PROBE"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; probe_init
;
; Runs the protected-mode probe if CONFIG.SYS has a "CPU=PROBE" line.
;
; Inputs:
;	ES:BX -> DDPI
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	probe_init
	mov	di,offset DEV:probe_cfg
	call	find_cfg		; is there a "CPU=PROBE" line?
	jne	pi9			; no
	les	di,es:[bx].DDPI_BUFPTR	; ES:DI -> scratch buffer
	mov	ax,es
	mov	dx,ax
	shl	ax,4
	shr	dx,12
	add	ax,di
	adc	dx,0			; DX:AX = its address
	push	dx
	push	ax
	mov	ax,SYS_SEG
	mov	ds,ax
	mov	es,ax
	mov	di,SYS_LOG
	mov	cx,(SYS_STK0 - SYS_LOG) SHR 1
	sub	ax,ax
	rep	stosw			; clear the probe's system area
	pop	ds:[SYS_LOG].PL_BUF.LOW
	pop	ds:[SYS_LOG].PL_BUF.HIW
	mov	bx,offset DEV:pm_probe
	call	pm_call
	jmp	probe_report
pi9:	ret
ENDPROC	probe_init

	ASSERT	<offset irq_common - offset irq_stubs>,EQ,<16 * 5>
	ASSERT	<offset exc_common - offset exc_stubs>,EQ,<16 * 5>

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
