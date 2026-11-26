;
; BASIC-DOS 80386 Processor (CPU$) Driver: V86 and Flat Machines
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The code for V86 machines (CPU_V86; see v86.inc), which is linked after
; 386dev.asm and before 386init.asm, so that CPU$ keeps it only when it uses
; the 80386's features (see cpu_len), the only time CPU_V86 can call it (see
; ddcpu_v86).
;
; Each machine has a page directory and a page table, in a block of their
; own, whose PMB has its page number (PMB_V86) and the machine's LDT
; selectors, so that they're freed with it: the ones for its memory (see
; v86_tiles), and the two that its exits update (VR_DSSEL and VR_ESSEL).  The
; page directory has the system's PDEs (see LIN_HI) and the PDE for the page
; table, which maps the machine's first 1Mb (plus the 64K that wraps), and
; the rest of its page is free, so the machine's context (V86CTX) is there,
; too.
;
; The machine's memory gets its pages as they're touched (see pg_get), a
; chunk at a time (PG_NCHUNK pages, in a block of its owner's), so a machine
; costs only the memory that it uses, and more machines can be created than
; there's memory for.  Its page table is also the system's for one of the
; windows (see WIN_SLOTS), which is where everything outside the machine
; finds its memory (and what its selectors' bases are), so a page that isn't
; there yet faults either way: in the machine (see v86_pf), which exits
; (V86X_NOMEM) when there's no memory for it, so that its host can wait for
; some, or in its window (see v86_syspf), where nothing can wait, so those
; pages can use the last chunk's worth of free memory, which the others
; leave alone.  A machine that has
; a console's video memory (see v86_vsel) gets the selector's memory in its
; page table each time it resumes (see v86_vid), or while the selector isn't
; present, no pages there, so that touching them waits (see v86_pf); and
; while that memory is the EGA or VGA's graphics memory, it has the video
; ports, too (see SYS_IOMAP), along with any ports that a driver has lent it
; (see v86_ports).
;
; While the machine runs, its context's V86REGS is the TSS's ring 0 stack
; (through SEL_V86STK, the first of SV_V86SEL's selectors), so every
; interrupt from the machine stores its registers there, and the machine's
; IDT (see v86_setup), whose gates are 80386 interrupt gates (as an interrupt
; from V86 mode needs), sends each one to a stub (see v86_stubs).  For a
; general protection fault, the stub does what the instruction would have
; done in real mode (v86_gp), still on the context's stack, and runs the
; machine again (v86_cont); for anything else (or a fault that exits), it
; loads the system's IDT, and goes back to the kernel's stack (v86_leave),
; where it ends the call (v86_exit), or runs the system's handler for a
; hardware interrupt and then runs the machine again (v86_resume), with its
; own IDT, and its own page directory.  The machine's IOPL is 0, so CLI,
; STI, PUSHF, POPF, INT, and IRET all fault, and so do I/O instructions,
; since the TSS's I/O permission bitmap allows only the ports that the
; machine has (see v86_ports), and the video ports while it has the graphics
; memory.
;
; A flat machine (see fl_create) runs 32-bit protected-mode code at ring 3
; the same way: with a page directory and context of its own, the machines'
; IDT while it runs, and an exit to its host for every interrupt, but with
; none of the monitor's work, since anything its code can't do is a fault.
;
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc
	include	v86.inc
	include	386dev.inc

DEV	group	CODE

CODE	segment para public 'CODE'

	EXTNEAR	<alloc_at,ddcpu_alloc,pmb_fit,pmb_used,pmb_free,desc_alloc>
	EXTNEAR	<sel_desc,pm_ptr,cpu_inval,ddcpu_seginfo,id_desc,desc_addr>
	EXTNEAR	<enc_owner,pg_entry,pmb_largest>

	.286p
;
; A machine's context, in its page directory's page (at V86_CTX); its frame
; (from VR_VEC through VR_GS) is where interrupts from the machine store its
; registers, so VR_DSSEL is the top of its ring 0 stack.
;
V86CTX		struc
VC_REGS		db	(size V86REGS) dup (?)
VC_KSP		dw	?	; the kernel's stack (SS:SP) to exit to
VC_KSS		dw	?
VC_SP0		dw	?	; the TSS's ring 0 stack (SS0:SP0) to restore
VC_SS0		dw	?
VC_MEM		dd	?	; the machine's memory (its window's address)
VC_LEN		dd	?	; and its length
VC_VIF		db	?	; the machine's IF (FL_INTS SHR 8, or 0)
VC_DBG		db	?	; nonzero if a debugger gets traps (v86_refl)
VC_VID		dw	?	; its video memory's selector ID (or zero)
VC_VPG		db	?	; and that memory's first page
VC_VCNT		db	?	; and # of pages
VC_VOK		db	?	; nonzero if the memory is there (see v86_vid)
VC_VIO		db	?	; FFh if it has the video ports, too (or 0)
VC_VDESC	db	(size DESC) dup (?)	; the selector's descriptor
VC_IOSET	db	?	; nonzero if a driver has lent it ports
VC_SUSP		db	?	; nonzero if it's suspended (see v86_susp)
VC_NOTE		dd	?	; the lending driver's function (see v86_ports)
VC_IOMAP	db	(IOMAP_LEN - 1) dup (?)	; its bitmap (see v86_ports)
VC_FLAT		db	?	; nonzero for a flat machine (see fl_create)
VC_PEND		db	?	; flat: nonzero for a pending fault (fl_event)
VC_FSEL		dw	?	; flat: its first selector (the machine)
VC_TOP		dd	?	; flat: the end of its memory (linear address)
VC_OWNER	dw	?	; its owner ID (see enc_owner)
VC_NEXT		dd	?	; the next page of its chunk (see pg_get)
VC_NFREE	db	?	; and how many pages the chunk has left
V86CTX		ends

V86_CTX		equ	0800h	; context's offset (PDEs for 80000000h and up)
V86_PT		equ	PG_SIZE	; page table's offset (in the next page)
V86_MAXLEN	equ	0Ah	; most memory a machine can have (640K), in 64K
V86_NSTUBS	equ	12h	; exception stubs (00h-11h), before the IRQs'
PG_NCHUNK	equ	16	; pages in a chunk of a machine's memory (64K)
FL_V86		equ	0DD5h	; flags that the machine can change
TSS_ESP0	equ	SYS_TSS + 4	; the 80386 TSS's ring 0 stack
TSS_SS0		equ	SYS_TSS + 8
;
; A flat machine (see fl_create) runs 32-bit code at ring 3, in protected
; mode, with memory that starts at FL_BASE in a linear address space of its
; own.  Its context has a page to itself, followed by its first page table
; (at V86_PT, as in a V86 machine) and then its page directory (at FL_PD), so
; that all of the directory's PDEs below the system's are its own, and the
; context's stack (which grows down from V86_CTX) isn't in any of them.
;
FL_BASE		equ	0001h	; its memory's linear address (bits 31-16)
FL_PD		equ	2 * PG_SIZE	; its page directory's offset
FL_NSEL		equ	5	; its selectors (see fl_create)
FL_CODE		equ	3 * (size DESC)	; its code selector (data is the next)
EXT_FLAT	equ	0CBh	; DESC_EXT: 4K granularity, 32-bit, limit 19-16

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

	DEFLBL	v86_begin,near

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_func (CPU_V86)
;
; Inputs:
;	AL = 0 to create a machine (see v86_create), 1 to run one (see
;	v86_run), 2 or 3 to copy registers (see v86_regs), 4 or 5 to lend
;	ports or take them back (see v86_ports), 6 to 8 for a flat machine
;	(see fl_func), or 9 to give memory its pages (see v86_commit)
;
DEFPROC	v86_func
	cmp	al,1
	je	v86_run
	jb	vf1
	cmp	al,3			; copying registers?
	jbe	v86_regs		; yes
	cmp	al,5			; lending ports?
	ja	vf2			; no
	jmp	v86_ports		; yes
vf2:	cmp	al,8			; a flat machine's function?
	ja	vf3			; no
	jmp	fl_func			; yes
vf3:	cmp	al,9			; giving a machine's memory its pages?
	jne	vf8			; no
	jmp	v86_commit		; yes
vf8:	jmp	cpu_inval
vf1:	jmp	v86_create
ENDPROC	v86_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_regs
;
; Copies the registers of the machine that ran last from its context to the
; caller's V86REGS, as v86_exit does (with the machine's own IF), or from
; the caller's to its context, as v86_run does (so that only its FL_V86
; flags change), and with AL = 3, VR_VEC (which isn't a register) is whether
; the debugger gets the machine's single-step traps and INT 3s (see
; v86_refl).  They're the machine's current registers only while it's
; interrupted (eg, while a debugger has stopped the handler that v86_irq
; called; see CPU_SYSREGS).
;
; Inputs:
;	AL = 2 (copy from the context) or 3 (copy to it)
;	ES:DI -> V86REGS
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	v86_regs
	mov	bx,ds:[SYS_VARS].SV_V86SEL	; BX = SEL_V86STK
	test	bx,bx			; has a machine been created?
	jz	vk8			; no
	mov	cx,VR_DSSEL / 2
	mov	si,V86_CTX
	push	es
	cmp	al,2			; copying from the context?
	jne	vk1			; no
	mov	es,bx
	call	v86_flags		; AX = FLAGS, with the machine's IF
	pop	es
	push	ds
	mov	ds,bx
	push	di
	rep	movsw
	pop	di
	pop	ds
	mov	word ptr es:[di].VR_EFL,ax
	ret				; (carry is clear)
vk1:	push	ds
	push	es
	pop	ds
	xchg	si,di			; DS:SI -> V86REGS, DI -> context
	mov	es,bx
	push	word ptr es:[di].VR_EFL+2
	push	word ptr es:[di].VR_EFL
	mov	dx,word ptr [si].VR_EFL	; DX = the caller's FLAGS
	mov	bl,byte ptr [si].VR_VEC	; BL = the debugger's choice
	rep	movsw
	mov	es:[V86_CTX].VC_DBG,bl
	mov	es:[V86_CTX].VC_PEND,0	; (see fl_event)
	pop	word ptr es:[V86_CTX].VR_EFL
	pop	word ptr es:[V86_CTX].VR_EFL+2
	pop	ds
	xchg	ax,dx
	call	v86_setfl		; (carry is clear)
	pop	es
	ret
vk8:	jmp	cpu_inval
ENDPROC	v86_regs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_run
;
; Runs a machine until it exits (see v86_exit), with the registers from the
; caller's V86REGS, except that VR_EFL's IF is the machine's own (VC_VIF),
; and its IOPL is 0.
;
; Inputs:
;	BX = machine (see v86_find)
;	ES:DI -> V86REGS
;
; Outputs:
;	Carry clear: AL = V86X_* (see v86.inc), V86REGS updated
;	Carry set: AX = error code
;
DEFPROC	v86_run
	mov	bp,es			; BP:DI -> V86REGS
	call	v86_find		; ES = its context, DX:CX = its address
	jc	vr9
	push	bp
	push	di
	push	dx
	push	cx			; (see v86_resume)
	mov	bp,sp
	push	ds
	lds	si,dword ptr [bp+4]	; DS:SI -> V86REGS
	mov	di,V86_CTX
	mov	cx,VR_DSSEL / 2
	cld
	rep	movsw
	pop	ds
	mov	ax,word ptr es:[V86_CTX].VR_EFL
	mov	dl,ah
	and	dl,FL_INTS SHR 8
	mov	es:[V86_CTX].VC_VIF,dl
	and	ax,FL_V86
	or	ax,FL_DEFAULT		; (IF, and bit 1)
	mov	word ptr es:[V86_CTX].VR_EFL,ax
	mov	word ptr es:[V86_CTX].VR_EFL+2,2	; VM (V86 mode)
	cmp	es:[V86_CTX].VC_FLAT,0	; a flat machine?
	je	v86_resume		; no
;
; A flat machine runs in protected mode, and always with its own code and
; stack selectors, whatever the caller's V86REGS has, since any others could
; take it to ring 0.
;
	sub	ax,ax
	mov	word ptr es:[V86_CTX].VR_EFL+2,ax
	mov	word ptr es:[V86_CTX].VR_CS+2,ax
	mov	word ptr es:[V86_CTX].VR_SS+2,ax
	mov	ax,es:[V86_CTX].VC_FSEL
	add	ax,FL_CODE + 3		; (RPL 3)
	mov	word ptr es:[V86_CTX].VR_CS,ax
	add	ax,size DESC
	mov	word ptr es:[V86_CTX].VR_SS,ax
	jmp	short v86_resume
vr9:	ret
ENDPROC	v86_run

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_resume
;
; Runs the machine again, from its context, with the TSS's ring 0 stack at
; the top of the context's frame (saving the kernel's, which v86_common
; restores), its page directory, and its IDT.  SEL_V86STK may name another
; machine's context by now (eg, after a hardware interrupt that switched
; sessions), so it's set again, and its video memory may have changed (eg,
; during another session's DOS call), so its pages are, too (see v86_vid).
; A fault that never left the context (see v86_common) goes to v86_cont,
; since nothing else has run.
;
; Inputs:
;	SS:SP -> the machine's page directory's address, and the caller's
;	V86REGS (see v86_run)
;
DEFPROC	v86_resume
	cli
	mov	ax,SEL_SYS
	mov	ds,ax
	mov	bp,sp
	mov	cx,[bp]
	mov	dx,[bp+2]
	call	v86_stk			; BX = ES = SEL_V86STK
	call	v86_vid
;
; A machine with the video ports whose video memory isn't there (because its
; console is hidden) is suspended; once it's there again, it resumes.
;
	mov	ax,word ptr es:[V86_CTX].VC_VOK	; AL = VC_VOK, AH = VC_VIO
	test	ah,ah			; does it have the video ports?
	jz	vr0a			; no
	test	al,al			; and not its video memory?
	jnz	vr0a			; no
	jmp	v86_susp		; yes, so it's suspended
vr0a:	cmp	es:[V86_CTX].VC_SUSP,0	; was it suspended?
	je	vr0b			; no
	mov	es:[V86_CTX].VC_SUSP,0
	mov	al,1			; (it resumes)
	call	v86_note
vr0b:
;
; The bits in the I/O permission bitmap of the ports that the machine has are
; clear only while it runs (v86_common sets them again): the ports that a
; driver has lent it, and the video ports.
;
	cld
	cmp	es:[V86_CTX].VC_IOSET,0	; any ports lent to it?
	je	vr1			; no
	push	cx			; (DX:CX = its page directory)
	push	ds
	push	es
	push	es
	push	ds
	pop	es
	pop	ds			; DS = context, ES = SEL_SYS
	mov	si,V86_CTX + VC_IOMAP
	mov	di,SYS_IOMAP
	mov	cx,(IOMAP_LEN - 1) / 2
	rep	movsw
	pop	es
	pop	ds
	pop	cx
vr1:	mov	al,es:[V86_CTX].VC_VIO
	not	al
	cbw
	db	66h,98h			; CWDE
	db	66h			; (MOV [...],EAX)
	mov	ds:[SYS_IOMAP+IOMAP_VIDEO],ax
	mov	ax,ds:[TSS_ESP0]
	mov	es:[V86_CTX].VC_SP0,ax
	mov	word ptr ds:[TSS_ESP0],V86_CTX + VR_DSSEL
	mov	ax,ds:[TSS_SS0]
	mov	es:[V86_CTX].VC_SS0,ax
	mov	ds:[TSS_SS0],bx
	mov	es:[V86_CTX].VC_KSP,sp
	mov	es:[V86_CTX].VC_KSS,ss
;
; An interrupt from a flat machine pushes no segment registers, so its ring 0
; stack is that much lower (v86_common stores them), and its page directory
; follows its context and first page table (see FL_PD).
;
	cmp	es:[V86_CTX].VC_FLAT,0	; a flat machine?
	je	vr1a			; no
	mov	word ptr ds:[TSS_ESP0],V86_CTX + VR_ES
	add	cx,FL_PD
	adc	dx,0			; DX:CX = its page directory
vr1a:	push	dx
	push	cx
	db	66h,58h			; POP EAX
	db	0Fh,22h,0D8h		; MOV CR3,EAX
	db	66h
	DTREG	lidt,<ds:[SYS_VARS].SV_V86IDTR>
	mov	ss,bx
	cmp	ss:[V86_CTX].VC_FLAT,0	; a flat machine?
	jne	fl_go			; yes
	DEFLBL	v86_cont,near
	mov	sp,V86_CTX
vr_ret:	db	66h,61h			; POPAD
	add	sp,VR_EIP - VR_VEC	; (past VR_VEC and VR_ERR)
	db	66h,0CFh		; IRETD (to V86 mode, or ring 3)
;
; A flat machine's data segment registers come from its context, too, each
; one only if ring 3 could load it (see fl_seg), since loading it here mustn't
; fault; the stack is the context's, whose page has nothing else below
; V86_CTX.
;
fl_go:	mov	sp,V86_CTX
	mov	bp,sp
	mov	ax,word ptr [bp].VR_GS
	call	fl_seg
	db	8Eh,0E8h		; MOV GS,AX
	mov	ax,word ptr [bp].VR_FS
	call	fl_seg
	db	8Eh,0E0h		; MOV FS,AX
	mov	ax,word ptr [bp].VR_ES
	call	fl_seg
	mov	es,ax
	mov	ax,word ptr [bp].VR_DS
	call	fl_seg
	mov	ds,ax
	jmp	vr_ret
ENDPROC	v86_resume

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_stubs
;
; The machine's IDT sends each vector to its stub, which calls v86_noerr (or
; for an exception with an error code, v86_err), so that its return address
; says which stub it was: one for each exception (00h-11h) and then one for
; each IRQ (70h-7Fh).
;
	DEFLBL	v86_stubs,near
	REPT	8
	call	v86_noerr		; 00h-07h
	ENDM
	call	v86_err			; 08h
	call	v86_noerr		; 09h
	REPT	5
	call	v86_err			; 0Ah-0Eh
	ENDM
	call	v86_noerr		; 0Fh
	call	v86_noerr		; 10h
	call	v86_err			; 11h
	REPT	16
	call	v86_noerr		; 70h-7Fh
	ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_common
;
; Entered from a stub with interrupts off, SS:SP -> the stub's return
; address, the error code (if any), and the machine's frame, in its context;
; it stores the registers there, too (with the vector in VR_VEC), loads the
; system's IDT and the kernel's ring 0 stack in the TSS, and goes back to the
; kernel's stack.  Without an error code, the return address is where the
; upper half of VR_ERR goes, so it's moved to VR_VEC.  The machine's DF (eg,
; after its STD) is still set, so it's cleared for our string instructions
; (and the machine's own is in its FLAGS, for the return).
;
DEFPROC	v86_noerr
	sub	sp,4			; (room for VR_VEC and half of VR_ERR)
	db	66h,60h			; PUSHAD
	mov	bp,sp
	mov	ax,word ptr [bp+VR_ERR+2]
	mov	[bp+VR_VEC],ax		; the stub's return address
	jmp	short v86_common
	DEFLBL	v86_err,near
	db	66h,60h			; PUSHAD
	mov	bp,sp
	DEFLBL	v86_common,near
	test	byte ptr [bp+VR_EFL+2],2	; from V86 mode?
	jnz	vc0			; yes
;
; An interrupt from a flat machine (at ring 3) pushed no segment registers,
; so we store them where one from V86 mode would have.
;
	test	byte ptr [bp+VR_CS],3	; from a flat machine?
	jnz	vc0b			; yes
	jmp	v86_kern		; no (from the kernel)
vc0b:	mov	word ptr [bp+VR_ES],es
	mov	word ptr [bp+VR_DS],ds
	db	8Ch,66h,VR_FS		; MOV [BP+VR_FS],FS
	db	8Ch,6Eh,VR_GS		; MOV [BP+VR_GS],GS
vc0:	cld
	mov	ax,[bp+VR_VEC]
	sub	ax,offset DEV:v86_stubs + 3
	mov	cl,3
	div	cl			; AL = stub #
	cmp	al,V86_NSTUBS		; an exception?
	jb	vc1			; yes
	add	al,IRQ_SLAVE - V86_NSTUBS
vc1:	mov	ah,0
	mov	[bp+VR_VEC],ax		; AL = vector
	mov	bx,SEL_SYS
	mov	ds,bx
	mov	bx,ss
	mov	es,bx			; ES = context
	cmp	es:[V86_CTX].VC_FLAT,0	; a flat machine?
	je	vc0a			; no
	jmp	fl_event		; yes
vc0a:
;
; A general protection fault (eg, a CLI or an IRET), and the exceptions that
; real mode delivers through the vectors (the same ones that it returns from
; at the same address), which go to the machine's own, are handled right
; here, on the context's stack, with the machine's IDT, page directory, and
; ports still in place, and leave the context (see v86_leave) only to exit
; (see v86_out); anything else leaves it first.
;
	cmp	al,INT_GP		; a general protection fault?
	je	v86_gp			; yes
	mov	si,word ptr es:[V86_CTX].VR_EIP
	cmp	al,INT_DB
	jbe	vc3			; 00h and 01h
	cmp	al,INT_NMI		; an NMI?
	je	vc2			; yes
	cmp	al,INT_BR
	jb	vc8			; (INT 03h and 04h fault as 0Dh)
	cmp	al,INT_NM
	jbe	vc3			; 05h-07h
	mov	dx,offset DEV:v86_pf
	cmp	al,INT_PF		; a page fault?
	je	v86_leave		; yes
	cmp	al,IRQ_SLAVE		; a hardware interrupt?
	jb	vc8			; no
vc2:	mov	dx,offset DEV:v86_irq
;
; v86_leave goes back to the kernel's stack, with the system's IDT and page
; directory (the only one with the machines' windows; the machine's own is
; in SV_MCR3 until it exits, for a debugger that asks about its linear
; addresses; see seg_lin), the kernel's ring 0 stack in the TSS, and every
; port's bit set again (see io_close), and then on to DX, with AX unchanged,
; DS = SEL_SYS, and ES = context.
;
	DEFLBL	v86_leave,near
	call	io_close
	db	66h
	DTREG	lidt,<ds:[SYS_VARS].SV_PIDTR>
	mov	cx,ss:[V86_CTX].VC_SP0
	mov	ds:[TSS_ESP0],cx
	mov	cx,ss:[V86_CTX].VC_SS0
	mov	ds:[TSS_SS0],cx
	mov	bx,ss
	mov	es,bx			; ES = context (again)
	mov	cx,es:[V86_CTX].VC_KSP
	mov	ss,es:[V86_CTX].VC_KSS
	mov	sp,cx
	push	ax
	db	0Fh,20h,0D8h		; MOV EAX,CR3
	db	66h			; (MOV [...],EAX)
	mov	ds:[SYS_VARS].SV_MCR3.LW,ax
	push	ds:[SYS_VARS].SV_PDIR.HW
	push	ds:[SYS_VARS].SV_PDIR.LW
	db	66h,58h			; POP EAX
	db	0Fh,22h,0D8h		; MOV CR3,EAX
	pop	ax
	jmp	dx
vc3:	jmp	v86_refl
vc8:	mov	al,V86X_FAULT
	jmp	v86_out
ENDPROC	v86_noerr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_gp
;
; A general protection fault in the machine: CLI, STI, PUSHF, POPF, INT,
; INT3, INTO, and IRET (with an operand-size prefix, too) do what they would
; in real mode, using the machine's IF; an IN or OUT of a byte or a word exits
; (V86X_IO), so that the host can do it, except at the interrupt controller's
; ports (20h and 21h) and the game port (201h), without an exit: the machine
; gets no hardware interrupts of its own, so an OUT to the controller (eg, an
; end of interrupt) does nothing, and an IN reads zero, and no driver owns a
; game adapter, so the port reads FFh (the buttons, bits 4-7, are up, and
; programs that time the position bits, 0-3, which an OUT would clear, give
; up at once, eg, BASIC's STICK is 0), and an OUT does nothing; anything
; else (eg, HLT) exits as a fault.
;
; Inputs:
;	DS = SEL_SYS, ES = context
;
DEFPROC	v86_gp
	mov	ax,word ptr es:[V86_CTX].VR_CS
	mov	si,word ptr es:[V86_CTX].VR_EIP
;
; The processor read the instruction before it faulted, so the bytes read
; here (no more than 3) are there, unless the fault was reading past the end
; of the segment.
;
	cmp	si,-2			; could it reach the end?
	jb	vg0			; no
	mov	cx,2
	call	v86_chk			; can we read it?
	jnc	vg0			; yes
	jmp	vg8
vg0:	call	v86_seg			; GS = CS
	sub	dx,dx			; DL = 0 (no operand-size prefix)
	db	65h			; (GS:)
	lodsb
	cmp	al,OP_OPSIZE
	jne	vg1
	mov	dl,al			; DL = operand-size prefix
	db	65h			; (GS:)
	lodsb
vg1:	cmp	al,OP_CLI
	je	vg2
	cmp	al,OP_STI
	je	vg3
	cmp	al,OP_PUSHF
	je	vg4
	cmp	al,OP_POPF
	je	vg5
	cmp	al,OP_IRET
	je	vg6
	mov	ah,INT_BP
	cmp	al,OP_INT03
	je	vg7
	cmp	al,OP_INT
	jne	vg1a
	db	65h			; (GS:)
	lodsb
	mov	ah,al			; AH = vector
	jmp	short vg7
vg1a:	cmp	al,OP_INTO
	jne	vg10
	test	byte ptr es:[V86_CTX].VR_EFL+1,FL_OVFL SHR 8
	jz	vg9			; no overflow, so there's no INT 04h
	mov	ah,INT_OF
vg7:	mov	al,ah
	jmp	v86_refl
vg2:	mov	es:[V86_CTX].VC_VIF,0
	jmp	short vg9
vg3:	mov	es:[V86_CTX].VC_VIF,FL_INTS SHR 8
	jmp	short vg9
vg4:	mov	cx,-1
	call	v86_stkchk		; is there room for its FLAGS?
	jc	vg8			; no
	call	v86_flags		; AX = the machine's FLAGS
	call	v86_pushv
	jmp	short vg9
vg5:	mov	cx,1
	call	v86_stkchk		; are its new FLAGS there?
	jc	vg8			; no
	call	v86_popv		; AX = new FLAGS
	jmp	short vg6a
vg6:	mov	cx,3
	call	v86_stkchk		; are its IP, CS, and FLAGS there?
	jc	vg8			; no
	call	v86_popv		; AX = IP
	xchg	si,ax			; SI = IP
	call	v86_popv		; AX = CS
	mov	word ptr es:[V86_CTX].VR_CS,ax
	call	v86_popv		; AX = FLAGS
vg6a:	call	v86_setfl
vg9:	mov	word ptr es:[V86_CTX].VR_EIP,si
	mov	word ptr es:[V86_CTX].VR_EIP+2,0
	jmp	v86_cont
vg8:	mov	al,V86X_FAULT
	jmp	v86_out
;
; IN and OUT are E4h-E7h (with the port in the next byte) and ECh-EFh (with
; the port in DX); bit 0 is set for a word, and bit 1 for OUT.
;
vg10:	mov	ah,al
	and	ah,0F4h
	cmp	ah,0E4h			; IN or OUT?
	jne	vg8			; no
	test	dl,dl			; of a dword?
	jnz	vg8			; yes
	mov	bl,al
	mov	bh,0			; BX = opcode
	mov	cx,word ptr es:[V86_CTX].VR_EDX
	test	al,08h			; is the port in DX?
	jnz	vg11			; yes
	db	65h			; (GS:)
	lodsb
	mov	ah,0
	xchg	cx,ax			; CX = port
vg11:	mov	al,0FFh			; AL = what the game port reads
	cmp	cx,201h			; the game port?
	je	vg11a			; yes
	inc	ax			; AL = what the controller's read
	cmp	cx,21h			; the interrupt controller's port?
	ja	vg12			; no
	cmp	cl,20h
	jb	vg12			; no
vg11a:	test	bl,2			; OUT?
	jnz	vg9			; yes, so it does nothing
	mov	byte ptr es:[V86_CTX].VR_EAX,al
	test	bl,1			; a word?
	jz	vg9			; no
	mov	byte ptr es:[V86_CTX].VR_EAX+1,al
	jmp	vg9
vg12:	mov	es:[V86_CTX].VR_ERR.LW,cx
	mov	es:[V86_CTX].VR_ERR.HW,bx
	mov	word ptr es:[V86_CTX].VR_EIP,si
	mov	al,V86X_IO
	jmp	v86_out
ENDPROC	v86_gp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_refl
;
; Sends an interrupt to the machine's vector, as real mode would (pushing its
; FLAGS, CS, and IP, and clearing IF and TF), unless the vector's handler
; starts with a HLT, in which case the machine exits (V86X_INT) instead.
;
; Inputs:
;	AL = vector, SI = IP to return to
;	DS = SEL_SYS, ES = context
;
DEFPROC	v86_refl
;
; A single-step trap or an INT 3 goes to the system's handler instead (eg, a
; debugger's, which has set VC_DBG; see v86_regs), as a hardware interrupt
; does (see v86_irq), with the machine's IP past it.
;
	cmp	es:[V86_CTX].VC_DBG,0	; does a debugger get them?
	je	rf1			; no
	cmp	al,INT_DB		; a single-step trap?
	je	rf0			; yes
	cmp	al,INT_BP		; an INT 3?
	jne	rf1			; no
rf0:	mov	word ptr es:[V86_CTX].VR_EIP,si
	mov	dx,offset DEV:v86_irq
	jmp	v86_leave
rf1:	sub	dx,dx			; DL = 0 (16-bit pushes)
	mov	bl,al
	mov	bh,0
	shl	bx,2			; BX -> the vector
	push	ax
	sub	ax,ax
	call	v86_seg			; GS = 0 (that page is always there)
	db	65h			; (GS:)
	mov	cx,[bx]			; CX = handler's offset
	db	65h			; (GS:)
	mov	di,[bx+2]		; DI = handler's segment
	push	si
	mov	ax,di
	mov	si,cx
	push	cx
	sub	cx,cx
	call	v86_chk			; can we read its first byte?
	pop	cx
	jc	rf2			; no (so it isn't a HLT)
	call	v86_seg			; GS = handler's segment
	db	65h			; (GS:)
	cmp	byte ptr [si],OP_HLT	; a default handler?
	jne	rf2			; no
	pop	si			; SI = IP to return to
	pop	ax			; AL = vector
	mov	word ptr es:[V86_CTX].VR_EIP,si
	mov	word ptr es:[V86_CTX].VR_EIP+2,0
	mov	ah,0
	mov	es:[V86_CTX].VR_VEC,ax
	mov	al,V86X_INT
	jmp	short v86_out
rf2:	push	cx
	mov	cx,-3
	call	v86_stkchk		; is there room for the frame?
	pop	cx			; CX = handler's offset
	jc	rf8			; no
	call	v86_flags		; AX = the machine's FLAGS
	call	v86_pushv
	mov	ax,word ptr es:[V86_CTX].VR_CS
	call	v86_pushv
	pop	ax			; AX = IP to return to
	call	v86_pushv
	pop	ax
	mov	es:[V86_CTX].VC_VIF,0
	and	byte ptr es:[V86_CTX].VR_EFL+1,NOT (FL_TRAP SHR 8)
	mov	word ptr es:[V86_CTX].VR_EIP,cx
	mov	word ptr es:[V86_CTX].VR_EIP+2,0
	mov	word ptr es:[V86_CTX].VR_CS,di
	jmp	v86_cont
rf8:	pop	ax
	pop	ax
	mov	al,V86X_FAULT
ENDPROC	v86_refl			; fall into v86_out

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_out
;
; Leaves the machine's context (see v86_leave) to exit.
;
; Inputs:
;	AL = V86X_*
;	DS = SEL_SYS, ES = SS = context
;
DEFPROC	v86_out
	mov	dx,offset DEV:v86_exit
	jmp	v86_leave
ENDPROC	v86_out

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_exit
;
; Ends the call that ran the machine (see v86_run), storing its registers in
; the caller's V86REGS (with its own IF, and VR_DSSEL and VR_ESSEL updated);
; no machine is interrupted now (see SV_MCR3), and this one can be freed.
;
; Inputs:
;	AL = V86X_*
;	DS = SEL_SYS, SS:SP -> the machine's page directory's address, and the
;	caller's V86REGS (see v86_run)
;
DEFPROC	v86_exit
	mov	bp,sp
	push	ax
	mov	cx,[bp]
	mov	dx,[bp+2]
	call	v86_stk			; ES = context (again, after a tick)
	pop	ax
;
; A hardware interrupt's vector becomes the one that real mode uses for it
; (IRQs 0-7 are at IRQ_MASTER in protected mode, and at 08h in real mode).
;
	cmp	al,V86X_TICK
	jne	vx1
	cmp	es:[V86_CTX].VR_VEC,IRQ_MASTER
	jb	vx1
	sub	es:[V86_CTX].VR_VEC,IRQ_MASTER - INT_HW_TMR
vx1:	push	ax
	call	v86_flags
	mov	word ptr es:[V86_CTX].VR_EFL,ax
	cmp	es:[V86_CTX].VC_FLAT,0	; a flat machine?
	jne	vx2			; yes (see fl_lin for its selectors)
	mov	ax,word ptr es:[V86_CTX].VR_DS
	mov	bx,es:[V86_CTX].VR_DSSEL
	call	v86_alias
	mov	ax,word ptr es:[V86_CTX].VR_ES
	mov	bx,es:[V86_CTX].VR_ESSEL
	call	v86_alias
vx2:	push	ds
	push	es
	pop	ds
	mov	si,V86_CTX
	les	di,dword ptr [bp+4]	; ES:DI -> V86REGS
	mov	cx,(size V86REGS) / 2
	rep	movsw
	pop	ds
	sub	ax,ax
	mov	ds:[SYS_VARS].SV_MCR3.LW,ax
	mov	ds:[SYS_VARS].SV_MCR3.HW,ax
	mov	es,[bp+6]		; (the caller's ES)
	pop	ax			; AL = V86X_*
	add	sp,8
	clc
	ret
ENDPROC	v86_exit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_irq
;
; Runs the system's handler for a hardware interrupt (or an NMI) from the
; machine, as if it had interrupted us, and then exits (V86X_TICK), so that
; the host can act on it (eg, give the machine a tick, or an interrupt that a
; driver counted for it; see SND_IRQS), or after an NMI (or a trap that a
; debugger gets; see v86_refl), runs the machine again, unless it's a flat
; machine with a fault pending (see fl_event), which exits (V86X_FAULT).
;
; Inputs:
;	AL = vector, DS = SEL_SYS
;
DEFPROC	v86_irq
	push	ax
	mov	bl,al
	mov	bh,0
	shl	bx,3			; BX = its gate's offset in the IDT
	pushf
	push	cs
	push	offset DEV:v86_irqret
	push	ds:[SYS_PIDT+bx].DESC_BASE	; the handler's selector
	push	ds:[SYS_PIDT+bx].DESC_LIMIT	; and offset
	db	OP_RETF			; "return" to it
	DEFLBL	v86_irqret,near		; (see CPU_SYSREGS)
	pop	ax
	cmp	al,IRQ_SLAVE		; a hardware interrupt?
	jae	vi9			; yes
;
; A flat machine's fault that no debugger took (see fl_event) exits now.
;
	mov	ax,V86X_FAULT		; (AH = 0)
	xchg	ah,es:[V86_CTX].VC_PEND
	test	ah,ah			; was one pending?
	jnz	vi9a			; yes
	jmp	v86_resume
vi9:	mov	al,V86X_TICK
vi9a:	jmp	v86_exit
ENDPROC	v86_irq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_pf
;
; A page fault in the machine's memory means that the page hasn't been
; touched before, so it gets its memory now (see pg_get), and the machine
; runs again, at the same instruction; if there's none to give it, the
; machine exits (V86X_NOMEM, with the page's address in VR_ERR), so that its
; host can wait until there is (see v86_commit).
;
; One in its video memory (see v86_vid) means that its selector wasn't
; present when the machine resumed, so unless it's present now, the machine
; waits until it is, as a program that loads it does (see SELID_WAIT), and
; then runs again; if the wait ends early (eg, for a CTRLC), it exits as
; after a timer tick, so that DOS can act on it.  Any other page fault exits
; (V86X_FAULT), as one does after its selector is freed.
;
; Inputs:
;	DS = SEL_SYS, ES = context
;
DEFPROC	v86_pf
	db	0Fh,20h,0D0h		; MOV EAX,CR2
	db	66h,0C1h,0E8h,12	; SHR EAX,12 (AX = its page)
	db	66h,3Dh			; CMP EAX,110h
	dw	0110h,0
	jae	pf8			; (beyond the machine's addresses)
	mov	si,ax			; SI = the page
	mov	cx,word ptr es:[V86_CTX].VC_VPG	; CL = first page, CH = count
;
; Video memory is below 1Mb, so the page's high byte must be zero, and then
; its offset from the first page (which wraps if it's below it) must be less
; than the count (which is zero if there's no video memory).
;
	test	ah,ah
	jnz	pf2
	sub	al,cl
	cmp	al,ch			; in the machine's video memory?
	jae	pf2			; no
	call	v86_vid			; ZF clear if it's there now
	jc	pf8			; (it's gone)
	jnz	pf1			; it is
	mov	dx,SELID_WAIT
	mov	di,es:[V86_CTX].VC_VID	; DX:DI = its wait ID
	mov	ah,DDUTL_WAIT
	call	far ptr DDINT_UTIL
	jc	pf7			; the wait ended early
pf1:	jmp	v86_resume
pf2:	mov	ax,si
	cwd				; (DL = 0: not from the reserve)
	call	pg_get
	jnc	pf1
	cmp	al,ERR_NOMEMORY
	jne	pf8			; (it's not the machine's memory)
	mov	ax,si
	shl	ax,12
	shr	si,4			; SI:AX = the page's address
	mov	es:[V86_CTX].VR_ERR.LW,ax
	mov	es:[V86_CTX].VR_ERR.HW,si
	mov	al,V86X_NOMEM
	jmp	short pf9
pf7:	mov	al,V86X_TICK
	jmp	short pf9
pf8:	mov	al,V86X_FAULT
pf9:	jmp	v86_exit
ENDPROC	v86_pf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_kern
;
; An interrupt from the kernel, on the context's stack (see v86_common).
;
; Inputs:
;	SS:BP -> its PUSHAD frame, in the context
;
DEFPROC	v86_kern
;
; A page fault from the kernel is ours, touching a page of the machine's
; memory that isn't there yet (eg, v86_refl pushing a frame on its stack),
; so the page gets its memory (from the reserve, if need be; see pg_get) and
; the instruction runs again; if it can't, the machine exits with a fault.
;
	cmp	word ptr [bp+VR_VEC],offset DEV:v86_stubs + (INT_PF + 1) * 3
	jne	vkn2			; not a page fault
	push	ds
	push	es
	mov	ax,SEL_SYS
	mov	ds,ax
	mov	ax,ss
	mov	es,ax			; ES = context
	db	0Fh,20h,0D0h		; MOV EAX,CR2
	db	66h,0C1h,0E8h,12	; SHR EAX,12 (AX = its page)
	db	66h,3Dh			; CMP EAX,110h
	dw	0110h,0
	jae	vkn1			; (beyond the machine's addresses)
	mov	dl,1
	call	pg_get
	jc	vkn1
	pop	es
	pop	ds
	jmp	vr_ret
vkn1:	mov	al,V86X_FAULT
	jmp	v86_out
;
; Otherwise, only a debugger's trace (after the LIDT in v86_resume) or an
; NMI (eg, while a fault is handled above) can get here from the kernel,
; before the machine runs, so the trace ends (as if it were a G) and the code
; goes on.
;
vkn2:	and	byte ptr [bp+VR_EFL+1],NOT (FL_TRAP SHR 8)
	jmp	vr_ret
ENDPROC	v86_kern

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_alias
;
; Points an exit's selector (VR_DSSEL or VR_ESSEL) at a segment of the
; machine, with a limit that stops at the end of its memory (or at its first
; byte, with a limit of zero, if the segment starts beyond it).
;
; Inputs:
;	AX = segment, BX = selector
;	DS = SEL_SYS, ES = context
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	v86_alias
	push	ax
	call	sel_desc		; SI -> its descriptor
	pop	ax
	jc	va9
	mov	dx,ax
	shl	ax,4
	shr	dx,12			; DX:AX = the segment's address
	mov	cx,word ptr es:[V86_CTX].VC_LEN
	mov	di,word ptr es:[V86_CTX].VC_LEN+2
	sub	cx,ax
	sbb	di,dx			; DI:CX = how much memory follows it
	jc	va1			; none
	jnz	va2			; 64K or more
	jcxz	va1			; none
	dec	cx			; CX = limit
	jmp	short va3
va1:	sub	ax,ax
	cwd				; DX:AX = the start of its memory
	sub	cx,cx
	jmp	short va3
va2:	mov	cx,0FFFFh
va3:	add	ax,word ptr es:[V86_CTX].VC_MEM
	adc	dx,word ptr es:[V86_CTX].VC_MEM+2
	mov	ds:[si].DESC_LIMIT,cx
	mov	ds:[si].DESC_BASE,ax
	mov	ds:[si].DESC_BASE16,dl
	add	dh,LIN_HI
	mov	byte ptr ds:[si].DESC_EXT,0
	mov	byte ptr ds:[si].DESC_EXT+1,dh
va9:	ret
ENDPROC	v86_alias

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_flags and v86_setfl
;
; v86_flags returns the machine's FLAGS (with its own IF), and v86_setfl
; changes them (as POPF would in real mode), along with its IF.
;
; Inputs:
;	AX = new FLAGS (v86_setfl)
;	ES = context
;
; Outputs:
;	AX = FLAGS (v86_flags)
;
; Modifies:
;	AX, CX (v86_setfl)
;
DEFPROC	v86_flags
	mov	ax,word ptr es:[V86_CTX].VR_EFL
	and	ah,NOT (FL_INTS SHR 8)
	or	ah,es:[V86_CTX].VC_VIF
	ret
ENDPROC	v86_flags

DEFPROC	v86_setfl
	mov	cl,ah
	and	cl,FL_INTS SHR 8
	mov	es:[V86_CTX].VC_VIF,cl
	and	ax,FL_V86
	mov	cx,word ptr es:[V86_CTX].VR_EFL
	and	cx,NOT FL_V86
	or	ax,cx
	mov	word ptr es:[V86_CTX].VR_EFL,ax
	ret
ENDPROC	v86_setfl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_pushv and v86_popv
;
; Push a word (or with DL set, a dword whose upper half is zero) on the
; machine's stack, or pop one (ignoring the upper half), after v86_stkchk.
;
; Inputs:
;	AX = word (v86_pushv), DL = 0 (or OP_OPSIZE)
;	ES = context, GS = the machine's SS (see v86_stkchk)
;
; Outputs:
;	AX = word (v86_popv)
;
; Modifies:
;	AX
;
DEFPROC	v86_pushv
	test	dl,dl			; a dword?
	jz	v86_pushw		; no
	push	ax
	sub	ax,ax
	call	v86_pushw		; (its upper half)
	pop	ax
ENDPROC	v86_pushv			; fall into v86_pushw

DEFPROC	v86_pushw
	push	si
	mov	si,word ptr es:[V86_CTX].VR_ESP
	dec	si
	dec	si
	db	65h			; (GS:)
	mov	[si],ax
	mov	word ptr es:[V86_CTX].VR_ESP,si
	pop	si
	ret
ENDPROC	v86_pushw

DEFPROC	v86_popv
	call	v86_popw
	test	dl,dl			; a dword?
	jz	pv9			; no
	push	ax
	call	v86_popw		; (its upper half)
	pop	ax
pv9:	ret
ENDPROC	v86_popv

DEFPROC	v86_popw
	push	si
	mov	si,word ptr es:[V86_CTX].VR_ESP
	db	65h			; (GS:)
	lodsw
	mov	word ptr es:[V86_CTX].VR_ESP,si
	pop	si
	ret
ENDPROC	v86_popw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_stkchk
;
; Checks that the values about to be popped from the machine's stack (or the
; room for those about to be pushed) are in pages that the machine has, with
; no word split by the end of its segment, and points GS at its SS.
;
; Inputs:
;	CX = # of values to pop (or if negative, to push)
;	DL = 0 for words (or OP_OPSIZE for dwords)
;	DS = SEL_SYS, ES = context
;
; Outputs:
;	Carry clear if successful (GS = the machine's SS)
;
; Modifies:
;	CX
;
DEFPROC	v86_stkchk
	push	ax
	push	si
	shl	cx,1
	test	dl,dl			; dwords?
	jz	sk1			; no
	shl	cx,1			; CX = # of bytes (negative to push)
sk1:	mov	si,word ptr es:[V86_CTX].VR_ESP
	test	cx,cx			; a push?
	jns	sk2			; no
	add	si,cx			; SI = the new top
	neg	cx
sk2:	dec	cx			; CX = # of bytes after the first
;
; When the first is at an odd offset, a word is split if the last byte wraps
; to the start of the segment.
;
	test	si,1			; an odd offset?
	jz	sk3			; no
	mov	ax,si
	add	ax,cx			; does the last byte wrap?
	jc	sk9			; yes (and carry is set)
sk3:	mov	ax,word ptr es:[V86_CTX].VR_SS
	call	v86_chk
	jc	sk9
	call	v86_seg
sk9:	pop	si
	pop	ax
	ret
ENDPROC	v86_stkchk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_chk
;
; Checks that the first and last bytes at the machine's AX:SI (within the
; segment) are in pages that the machine has, or pages of its memory that
; aren't there yet, which get their memory when we touch them (see vc9).
;
; Inputs:
;	AX = segment, SI = offset, CX = # of bytes after the first
;	ES = context
;
; Outputs:
;	Carry clear if they're there
;
DEFPROC	v86_chk
	push	bx
	push	si
	call	ck1			; the first byte
	jc	ck9
	add	si,cx			; and the last
	call	ck1
ck9:	pop	si
	pop	bx
	ret
ck1:	push	ax
	push	dx
	mov	dx,ax
	shl	ax,4
	shr	dx,12
	add	ax,si
	adc	dx,0			; DX:AX = linear address
	shr	ax,12
	shl	dx,4
	or	ax,dx			; AX = its page #
	shl	ax,2
	xchg	bx,ax
	pop	dx
	pop	ax
	test	byte ptr es:[V86_PT+bx],1	; is its PTE present?
	jnz	ck2			; yes (and carry is clear)
	push	ax
	mov	ax,bx
	shr	ax,2
	call	pg_mine			; carry set unless it's memory's
	pop	ax
ck2:	ret
ENDPROC	v86_chk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_seg and v86_stk
;
; v86_seg points GS at a segment of the machine (through SEL_V86MEM, whose
; base is a linear address that the machine's page directory maps), and
; v86_stk points ES at a machine's context (through SEL_V86STK).
;
; Inputs:
;	AX = segment (v86_seg), or DX:CX = page directory (v86_stk)
;	DS = SEL_SYS
;
; Outputs:
;	BX = ES = SEL_V86STK (v86_stk)
;
; Modifies:
;	AL, BX (v86_stk)
;
DEFPROC	v86_seg
	push	ax
	push	bx
	push	dx
	mov	dx,ax
	shl	ax,4
	shr	dx,12			; DX:AX = linear address
	mov	bx,ds:[SYS_VARS].SV_V86SEL
	add	bx,size DESC		; BX = SEL_V86MEM
	mov	ds:[SYS_GDT+bx].DESC_BASE,ax
	mov	ds:[SYS_GDT+bx].DESC_BASE16,dl
	db	8Eh,0EBh		; MOV GS,BX
	pop	dx
	pop	bx
	pop	ax
	ret
ENDPROC	v86_seg

DEFPROC	v86_stk
	mov	bx,ds:[SYS_VARS].SV_V86SEL
	mov	ds:[SYS_GDT+bx].DESC_BASE,cx
	mov	ds:[SYS_GDT+bx].DESC_BASE16,dl
	mov	al,dh
	add	al,LIN_HI
	mov	byte ptr ds:[SYS_GDT+bx].DESC_EXT+1,al
	mov	es,bx
	ret
ENDPROC	v86_stk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_info (CPU_SEGINFO with ADDR_V86)
;
; Finds the machine whose memory's first selector is in the active LDT (with
; the machine's window as its base, since another LDT can have a selector at
; the same index), and returns where a segment is in that window, and how
; many of the bytes there are in consecutive pages that are present: its
; memory's (the ones that have been touched), its video memory's, or the
; ROMs'.  With ADDR_PHYS as well, the address is the segment's physical one,
; and the bytes are only those in physically consecutive pages of the same
; 64K (eg, for a DMA transfer, which the pages of a chunk allow; see pg_get).
;
; Inputs:
;	AL = ADDR_* flags, BX = segment
;
; Outputs:
;	Carry clear if successful: DX:CX = address, AX = limit (FFFFh if the
;	bytes go beyond 64K)
;	Carry set if no machine, or the segment isn't mapped (AX = ERR_INVALID)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	v86_info
	push	bx			; [BP+10] = segment
	push	di
	push	es
	push	bp
	push	ax			; [BP+2] = ADDR_* flags
	push	ax			; [BP] = a physical page (bits 31-16)
	mov	bp,sp
	sub	di,di			; DI = slot
vq1:	mov	ax,di
	call	win_ctx			; ES = the slot's machine's context
	jc	vq2			; (it has none)
	mov	bx,es:[V86_CTX].VC_FSEL
	call	sel_desc		; SI -> its first selector's descriptor
	jc	vq2
	call	desc_addr		; DX:CX = its base
	jcxz	vq3
vq2:	inc	di
	cmp	di,WIN_SLOTS
	jb	vq1
vq8:	pop	ax
	pop	ax
	pop	bp
	pop	es
	pop	di
	pop	bx
	jmp	cpu_inval
vq3:	cmp	dx,word ptr es:[V86_CTX].VC_MEM+2
	jne	vq2			; (another LDT's)
	mov	ax,16
	mul	word ptr [bp+10]	; DX:AX = linear address
	mov	si,ax
	shr	si,12
	mov	di,dx
	shl	di,4
	or	si,di
	shl	si,2			; SI = offset of its page's PTE
	sub	cx,cx			; CX = # of pages that are present
vq4:	mov	bx,es:[V86_PT+si]
	test	bl,PG_PRESENT
	jz	vq5
	test	byte ptr [bp+2],ADDR_PHYS
	jz	vq4c
	and	bx,NOT (PG_SIZE - 1)
	jcxz	vq4a			; (the first page)
	cmp	bx,di			; the next physical page?
	jne	vq5			; no
	push	ax
	mov	ax,es:[V86_PT+si+2]
	cmp	ax,[bp]			; of the same 64K?
	pop	ax
	jne	vq5			; no
	jmp	short vq4b
vq4a:	mov	di,es:[V86_PT+si+2]
	mov	[bp],di
vq4b:	lea	di,[bx+PG_SIZE]		; DI = the page that would follow it
vq4c:	add	si,4
	inc	cx
	cmp	cl,17			; more than 64K yet?
	jb	vq4			; no
vq5:	jcxz	vq8			; it isn't mapped
	test	byte ptr [bp+2],ADDR_PHYS
	jnz	vq5a
	add	dx,word ptr es:[V86_CTX].VC_MEM+2
	mov	di,ax			; DX:DI = its address (in the window)
	jmp	short vq5b
vq5a:	mov	bx,cx
	shl	bx,12
	sub	di,bx			; DI = the first page (bits 15-0)
	mov	bx,ax
	and	bx,PG_SIZE - 1
	or	di,bx
	mov	dx,[bp]			; DX:DI = its physical address
vq5b:	mov	si,0FFFFh
	cmp	cl,17
	jae	vq6
	mov	ch,cl
	shl	ch,4
	mov	cl,0			; CX = the pages' length (0 if 64K)
	and	ax,PG_SIZE - 1
	sub	cx,ax
	dec	cx
	mov	si,cx			; SI = limit
vq6:	mov	cx,di			; DX:CX = address
	xchg	ax,si			; AX = limit
	pop	bx
	pop	bx
	pop	bp
	pop	es
	pop	di
	pop	bx
	clc
	ret
ENDPROC	v86_info

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_create
;
; Creates a machine, owned by BX, with SI:DI bytes of memory (rounded up to a
; multiple of 4K, at most 640K), none of which it has yet (see pg_get) except
; its first page, and with a console's video memory, if DX is its selector
; (see v86_vsel).  Its context and page table are in a block from the top of
; memory (which is likely to be extended memory), as its memory's chunks will
; be, so that it doesn't take conventional memory that DOS could use, and it
; gets a window (see WIN_SLOTS), where its selectors find its memory.
;
; Inputs:
;	BX = owner, SI:DI = length, DX = video memory's selector (or zero)
;
; Outputs:
;	Carry clear: AX = first selector of its memory, DX = video memory's
;	segment in the machine (or zero)
;	Carry set: AX = error code
;
DEFPROC	v86_create
	push	bx
	push	si
	push	di
	push	dx
	call	v86_setup		; the machines' IDT and selectors
	pop	dx
	pop	di
	pop	si
	pop	bx
	jc	vcr0a
	add	di,PG_SIZE - 1
	adc	si,0
	and	di,NOT (PG_SIZE - 1)	; SI:DI = length, in pages
	mov	ax,di
	or	ax,si			; is it zero?
	jz	vcr0			; yes
	cmp	si,V86_MAXLEN		; more than 640K?
	jb	vcr1			; no
	ja	vcr0			; yes
	test	di,di
	jz	vcr1			; no
vcr0:	jmp	cpu_inval
vcr0a:	ret
vcr1:	call	v86_vsel		; DX = video ID, CX = its pages
	jc	vcr0a
	push	cx			; [BP+10] = the video memory's pages
	push	dx			; [BP+8] = and its ID
	push	si
	push	di			; [BP+6]:[BP+4] = length
	mov	al,MEMF_NONE OR MEMF_HIGH
	sub	si,si
	mov	di,2 * PG_SIZE
	call	alloc_page		; DX:CX = its context, BX -> PMB
	jc	vcr8
	push	dx
	push	cx			; [BP+2]:[BP] = its context
	mov	bp,sp
	push	ds:[bx].PMB_OWNER	; [BP-2] = its owner ID
	call	win_slot		; AX = a free window's slot
	jc	vcr7
	push	ax			; [BP-4] = its slot
	shl	ax,6
	add	ax,WIN_ADDR
	push	ax			; [BP-6] = its window (bits 31-16)
	xchg	dx,ax
	mov	si,[bp+6]
	mov	di,[bp+4]		; SI:DI = length
	push	bp
	sub	bp,bp			; DX:BP = the window's address
	call	v86_tiles		; AX = first selector, CX = count
	pop	bp
	jc	vcr7
	push	ax			; [BP-8] = the machine
	push	cx
	mov	cx,[bp]
	mov	dx,[bp+2]
	call	pmb_used		; BX -> its context's PMB
	pop	cx
	mov	ax,[bp-8]
	mov	ds:[bx].PMB_SEL,ax
	mov	ds:[bx].PMB_NSEL,cx	; (so they're freed with it)
	dec	cx
	dec	cx
	shl	cx,3
	add	cx,ax
	push	cx			; [BP-10] = VR_DSSEL (see v86_tiles)
	mov	ax,[bp]
	mov	dx,[bp+2]
	shr	ax,12
	shl	dx,4
	or	ax,dx			; AX = its context's page #
	mov	ds:[bx].PMB_V86,ax
	call	v86_init		; ES = its context
;
; The machine's first page (its vectors) is always there (see v86_refl), so
; a machine that has it has at least a chunk of its memory, too.
;
	sub	ax,ax
	cwd				; (DL = 0: not from the reserve)
	call	pg_get
	jc	vcr7
	mov	ax,[bp-8]		; AX = the machine
	mov	dh,[bp+10]
	mov	dl,0			; DX = video memory's segment (or 0)
	lea	sp,[bp+12]
	clc
	ret
vcr7:	mov	cx,[bp]
	mov	dx,[bp+2]
	call	pmb_used
	jc	vcr7a
	call	pmb_free		; (and its selectors and window)
vcr7a:	lea	sp,[bp+4]
vcr8:	add	sp,8
	mov	ax,ERR_NOMEMORY
	stc
vcr9:	ret
ENDPROC	v86_create

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_init
;
; Fills in a new machine's page directory, page table, and context: the ROMs
; (C0000h-FFFFFh, read-only), its window in the system's page directory (the
; same page table), its length (its memory's pages come later; see pg_get),
; and its video memory's selector ID and pages, if any, which get their PTEs
; as it runs (see v86_vid).
;
; Inputs:
;	SS:BP -> context's address and memory's length, and video memory's ID
;	and pages (see v86_create)
;	[BP-2] = owner ID, [BP-4] = window's slot, [BP-6] = window's address
;	(bits 31-16), [BP-8] = the machine, [BP-10] = VR_DSSEL
;	DS = SEL_SYS
;
; Outputs:
;	ES = context
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	v86_init
	mov	cx,[bp]
	mov	dx,[bp+2]
	call	v86_stk			; ES = context
	sub	di,di
	sub	ax,ax
	mov	cx,PG_SIZE		; (8K, in words)
	cld
	rep	stosw
	mov	ax,[bp]
	mov	dx,[bp+2]
	sub	di,di
	call	v86_pdes
	mov	di,V86_PT + 0C0h * 4
	mov	ax,PG_ROM
	mov	dx,000Ch		; DX:AX = PTE for C0000h
	mov	cx,40h
	call	vi_ptes
	mov	ax,[bp-6]
	mov	word ptr es:[V86_CTX].VC_MEM+2,ax
	mov	ax,[bp+4]
	mov	word ptr es:[V86_CTX].VC_LEN,ax
	mov	ax,[bp+6]
	mov	word ptr es:[V86_CTX].VC_LEN+2,ax
	mov	ax,[bp+8]
	mov	es:[V86_CTX].VC_VID,ax
	mov	ax,[bp+10]
	mov	word ptr es:[V86_CTX].VC_VPG,ax
	mov	ax,[bp-2]
	mov	es:[V86_CTX].VC_OWNER,ax
	mov	ax,[bp-8]
	mov	es:[V86_CTX].VC_FSEL,ax
	mov	di,V86_CTX + VC_IOMAP
	mov	cx,(IOMAP_LEN - 1) / 2
	mov	ax,-1
	rep	stosw			; no ports lent to it yet
	push	es
	call	pd_master		; ES:0 -> the system's page directory
	mov	bx,[bp-4]
	shl	bx,2
	mov	ax,[bp]
	mov	dx,[bp+2]
	add	ax,V86_PT + PG_USER
	adc	dx,0			; DX:AX = PDE for its page table
	mov	es:[bx+WIN_PDE*4],ax
	mov	es:[bx+WIN_PDE*4+2],dx	; (its window)
	pop	es
	mov	bx,[bp-10]
	or	bl,3			; (RPL 3, for the ring 3 caller)
	mov	es:[V86_CTX].VR_DSSEL,bx
	sub	ax,ax
	call	v86_alias
	mov	bx,es:[V86_CTX].VR_DSSEL
	add	bx,size DESC
	mov	es:[V86_CTX].VR_ESSEL,bx
	sub	ax,ax
	jmp	v86_alias
;
; vi_ptes stores CX PTEs at ES:DI, starting with DX:AX, for consecutive pages.
;
vi_ptes:
	stosw
	xchg	ax,dx
	stosw
	xchg	ax,dx
	add	ax,PG_SIZE
	adc	dx,0
	loop	vi_ptes
	ret
ENDPROC	v86_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_pdes
;
; Fills in a machine's page directory (already zeroed): PDE 0, for its first
; page table, and the system's PDEs (see LIN_HI).
;
; Inputs:
;	ES:DI -> page directory
;	DX:AX = address of the page before that page table
;	DS = SEL_SYS
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	v86_pdes
	add	ax,PG_SIZE + PG_USER
	adc	dx,0
	mov	es:[di],ax
	mov	es:[di+2],dx		; PDE 0 -> the page table
	push	ds
	push	di
	mov	ax,ds:[SYS_VARS].SV_PDIR.LW
	mov	dx,ds:[SYS_VARS].SV_PDIR.HW
	mov	cl,ds:[SYS_VARS].SV_NPT
	mov	ch,0
	shl	cx,1			; CX = words of the system's PDEs
	mov	bx,SEL_TMP2
	call	pm_ptr
	mov	ds,bx
	mov	si,PDE_KERNEL
	add	di,si
	rep	movsw			; the system's PDEs
	pop	di
	pop	ds
	ret
ENDPROC	v86_pdes

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_vsel
;
; Checks a new machine's video memory selector, if any: a console's (eg, from
; VKD$'s IOCTL_GETMODE), so an LDT selector, for whole pages from A0000h to
; C0000h, which the machine gets at the start of their frame (see v86_vid).
;
; Inputs:
;	DX = selector (or zero)
;	DS = SEL_SYS
;
; Outputs:
;	Carry clear: DX = its ID, CL = its first page, CH = # of pages (all
;	zero if none)
;	Carry set: AX = ERR_INVALID
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	v86_vsel
	sub	cx,cx
	test	dx,dx			; a selector?
	jz	vl9			; no (and carry is clear)
	push	bx
	push	si
	mov	bx,dx
	call	sel_desc		; SI -> its descriptor
	jc	vl8
	test	bl,SEL_TI		; an LDT selector (not a driver's)?
	jz	vl7			; no
	push	ds:[si].DESC_LIMIT
	call	desc_addr		; DX:CX = its address
	pop	ax			; AX = its limit (less than 64K)
	sub	dx,0Ah			; DX:CX = its offset from A0000h
	cmp	dx,1			; is it in A0000h-BFFFFh?
	ja	vl7			; no
	test	cx,PG_SIZE - 1		; does it start a page?
	jnz	vl7			; no
	shr	cx,12
	shl	dl,4
	or	cl,dl			; CL = its page in A0000h-BFFFFh
	shr	ah,4
	inc	ah
	mov	ch,ah			; CH = # of pages
	add	ah,cl
	cmp	ah,20h			; does it end by C0000h?
	ja	vl7			; no
	add	cl,0A0h			; CL = its first page
	cmp	cl,0B0h			; in a text frame (B0000h or B8000h)?
	jb	vl1			; no
	and	cl,0F8h			; CL = the frame's first page
vl1:	xchg	ax,bx
	call	enc_owner		; AX = its ID (and carry is clear)
	xchg	dx,ax
	jmp	short vl8
vl7:	mov	ax,ERR_INVALID
	stc
vl8:	pop	si
	pop	bx
vl9:	ret
ENDPROC	v86_vsel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_vid
;
; Gives the machine's video memory (see v86_vsel) PTEs for its selector's
; memory, if the selector is present and that memory starts on a page (which
; a buffer that holds a copy of it may not), or else PTEs that aren't
; present, so that the machine faults if it touches them (see v86_pf); a
; selector that's been freed takes the video memory away for good.
;
; The selector's memory can change (eg, when the console's mode does), so while
; it's the adapter's own (A0000h-BFFFFh), the machine has it at the start of
; its frame (A0000h, B0000h, or B8000h; eg, a console's text page at B8000h, as
; page 0 would be), and as much of it; a copy of it somewhere else stays where
; the adapter's was.  And while it's the EGA or VGA's graphics memory (below
; B0000h), which only a console that has the screen to itself gets, the machine
; has the video ports, too (VC_VIO; see v86_resume).  Most of the time, nothing
; has changed, so VC_VDESC is the descriptor as it was the last time.
;
; Inputs:
;	DS = SEL_SYS, ES = context
;
; Outputs:
;	ZF clear if the video memory is there, or carry set if it's gone now
;
DEFPROC	v86_vid
	cmp	es:[V86_CTX].VC_VID,0	; does it have video memory?
	jne	vv1			; yes
	ret
vv1:	pusha
	cld
	mov	bx,es:[V86_CTX].VC_VID
	call	id_desc			; BX -> its selector's descriptor
	jnc	vv1a
	jmp	vv7			; (it's been freed)
vv1a:	mov	si,bx
	mov	di,V86_CTX + VC_VDESC
	mov	cx,(size DESC) / 2
	repe	cmpsw			; has it changed?
	je	vv6			; no
	mov	si,bx
	mov	di,V86_CTX + VC_VDESC
	mov	cx,(size DESC) / 2
	rep	movsw
	mov	si,bx
	sub	bp,bp			; BP = 0 (not there, and no ports)
	sub	ax,ax
	cwd				; DX:AX = 0 (PTEs that aren't present)
	test	ds:[si].DESC_ACC,ACC_PRESENT
	jnz	vv2
;
; While the selector isn't present, a machine that had the video ports keeps
; them (VC_VIO), which means that it's suspended (see v86_susp), since its
; console's state is saved somewhere else (eg, see VKD$'s hide_vga).
;
	mov	bp,word ptr es:[V86_CTX].VC_VOK
	and	bp,0FF00h		; (not there, but the same ports)
	jmp	short vv5
vv2:	test	ds:[si].DESC_BASE,PG_SIZE - 1	; does it start on a page?
	jnz	vv5			; no
	inc	bp			; (it's there)
	call	desc_addr		; DX:CX = its address
	xchg	ax,cx			; DX:AX = its address
	mov	bx,dx
	sub	bx,0Ah
	cmp	bx,1			; the adapter's memory (A0000h-BFFFFh)?
	ja	vv4			; no (a copy of it)
	shl	bl,4
	mov	cl,ah
	shr	cl,4
	or	bl,cl
	add	bl,0A0h			; BL = its first page
	cmp	bl,0B0h			; in a text frame (B0000h or B8000h)?
	jb	vv2a			; no
	and	bl,0F8h			; BL = the frame's first page
vv2a:	mov	bh,byte ptr ds:[si].DESC_LIMIT+1
	shr	bh,4
	inc	bh			; BH = # of pages
	cmp	bx,word ptr es:[V86_CTX].VC_VPG	; is that where it was?
	je	vv3			; yes
	push	ax
	push	dx
	sub	ax,ax
	cwd
	call	vv_ptes			; no, so the old pages are gone
	pop	dx
	pop	ax
	mov	word ptr es:[V86_CTX].VC_VPG,bx
vv3:	cmp	bl,0B0h			; the graphics memory?
	jae	vv4			; no
	or	bp,0FF00h		; yes, so it has the ports, too
vv4:	or	al,PG_USER		; DX:AX = its first PTE
vv5:	call	vv_ptes
	mov	word ptr es:[V86_CTX].VC_VOK,bp	; (and VC_VIO)
vv6:	cmp	es:[V86_CTX].VC_VOK,0	; (carry is clear)
	popa
	ret
vv7:	sub	ax,ax
	cwd
	call	vv_ptes
	sub	ax,ax
	mov	es:[V86_CTX].VC_VID,ax
	mov	word ptr es:[V86_CTX].VC_VPG,ax	; (and VC_VCNT)
	mov	word ptr es:[V86_CTX].VC_VOK,ax	; (and VC_VIO)
	stc
	popa
	ret
;
; vv_ptes stores the video memory's PTEs, starting with DX:AX.
;
vv_ptes:
	mov	cx,word ptr es:[V86_CTX].VC_VPG	; CL = first page, CH = count
	mov	di,cx
	and	di,0FFh
	shl	di,2
	add	di,V86_PT		; ES:DI -> the first page's PTE
	mov	cl,ch
	mov	ch,0
	jmp	vi_ptes
ENDPROC	v86_vid

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_tiles
;
; Gives a machine's memory its selectors (in the active LDT, at DPL 3): one
; for every 32K, each covering the next 64K (or whatever remains), so that
; the host can reach anything smaller than 32K through a single selector;
; two more follow them, for the machine's exits (VR_DSSEL and VR_ESSEL; see
; v86_alias).
;
; Inputs:
;	DX:BP = address (in its window), SI:DI = length (non-zero)
;
; Outputs:
;	Carry clear: AX = first selector, CX = # of selectors (with the two)
;	Carry set: AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP
;
DEFPROC	v86_tiles
	push	dx
	push	si
	push	di
	mov	ax,di
	mov	cx,si
	add	ax,7FFFh
	adc	cx,0
	shl	ax,1
	rcl	cx,1			; CX = # of 32K parts
	push	cx
	inc	cx
	inc	cx			; (and the exits' two)
	mov	al,MEMF_LDT OR MEMF_USER
	call	desc_alloc		; AX = first selector, BX -> its DESC
	pop	cx
	pop	di
	pop	si
	pop	dx
	jc	vt8
	push	cx
	add	dh,ds:[SYS_VARS].SV_LINHI	; (see LIN_HI)
vt1:	mov	ds:[bx].DESC_BASE,bp
	mov	ds:[bx].DESC_BASE16,dl
	mov	byte ptr ds:[bx].DESC_EXT,0
	mov	byte ptr ds:[bx].DESC_EXT+1,dh
	push	ax
	mov	ax,di
	test	si,si			; 64K or more remaining?
	jz	vt2			; no
	sub	ax,ax			; yes, so the limit is FFFFh
vt2:	dec	ax
	mov	ds:[bx].DESC_LIMIT,ax
	pop	ax
	add	bp,8000h
	adc	dx,0			; the next 32K
	sub	di,8000h
	sbb	si,0
	add	bx,size DESC
	loop	vt1
	pop	cx
	inc	cx
	inc	cx			; (carry is still clear)
	ret
vt8:	mov	ax,ERR_NOMEMORY
	ret
ENDPROC	v86_tiles

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; alloc_page and alloc_64k
;
; Allocate a block that starts on a page (as CPU_ALLOC would allocate one
; that's PG_SIZE - 16 bytes longer, and then the page in it), since the
; processor maps memory a page at a time, or for a machine's memory, on a 64K
; boundary (from a block 64K - 16 bytes longer), so that its 64K boundaries
; are where its programs think they are, as a DMA controller's are.
;
; Inputs:
;	AL = MEMF_* flags, BX = owner, SI:DI = length (a multiple of PG_SIZE)
;
; Outputs:
;	As for CPU_ALLOC
;
DEFPROC	alloc_64k
	mov	ah,1
	jmp	short ap0
ENDPROC	alloc_64k

DEFPROC	alloc_page
	mov	ah,0
ap0:	mov	ds:[SYS_VARS].SV_ARG,al
	mov	ds:[SYS_VARS].SV_OWNER,bx
	push	si
	push	di
	mov	cx,PG_SIZE - 16
	test	ah,ah			; on a 64K boundary?
	jz	ap1			; no
	mov	cx,0FFF0h		; (64K - 16)
ap1:	add	di,cx
	adc	si,0
	mov	ds:[SYS_VARS].SV_LEN.LW,di
	mov	ds:[SYS_VARS].SV_LEN.HW,si
	push	ax
	call	pmb_fit			; BX -> free PMB, DX:CX = address
	pop	ax
	pop	di
	pop	si
	jc	ap8
	mov	ds:[SYS_VARS].SV_LEN.LW,di
	mov	ds:[SYS_VARS].SV_LEN.HW,si
	add	cx,PG_SIZE - 1
	adc	dx,0
	and	cx,NOT (PG_SIZE - 1)	; DX:CX = the page
	test	ah,ah			; on a 64K boundary?
	jz	ap2			; no
	add	cx,0FFFFh
	adc	dx,0
	sub	cx,cx			; DX:CX = the next 64K boundary
ap2:	jmp	alloc_at
ap8:	mov	ax,ERR_NOMEMORY
	ret
ENDPROC	alloc_page

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pg_get, pg_set, pg_mine, pg_chunk, and pg_fit
;
; pg_get gives a page of a machine's memory its physical memory, if it has
; none yet.  The first page touched in each 64K of the machine gets a chunk
; for all of that 64K (PG_NCHUNK pages, on a 64K boundary, from the top of
; memory, in a block of its owner's, so that it's freed when the owner ends),
; and all of its pages are mapped at once, so the 64K is contiguous, and its
; physical addresses have the machine's low 16 bits, as a DMA transfer needs
; (see v86_info).  When no free block has room for that, the page gets the
; next page (pg_set) of a chunk wherever one fits, of as many pages as fit
; (half as many each time, down to one; see pg_chunk).
;
; The last free block with room for a whole chunk is a reserve, for the pages
; that code outside the machine touches (DL nonzero), which can't wait for
; memory, as the machine can (see V86X_NOMEM); a chunk for any other page
; leaves such a block free, or isn't allocated.  A page in the machine's first
; 64K is also the same page of the 64K at 1Mb, which wraps, as an 8086's does.
; pg_mine checks that a page is one of its memory's (and unwraps it).
;
; Inputs:
;	AX = page # (in the machine's page table)
;	DL = nonzero if it can use the reserve (pg_get)
;	DS = SEL_SYS, ES = context
;
; Outputs:
;	Carry clear if the page is there (pg_get), or is memory's (pg_mine,
;	with AX = its page # in memory)
;	Carry set if not: AX = ERR_INVALID (it isn't memory's) or ERR_NOMEMORY
;	(pg_get)
;
; Modifies:
;	AX
;
DEFPROC	pg_get
	push	bx
	push	cx
	push	dx
	push	si
	call	pg_mine			; AX = the page of its memory
	jc	pgg8
	mov	bx,ax
	shl	bx,2			; BX = offset of its PTE
	test	byte ptr es:[V86_PT+bx],PG_PRESENT
	jnz	pgg9			; it's there (and carry is clear)
	cmp	es:[V86_CTX].VC_NFREE,0	; any pages left in a chunk?
	jne	pgg6			; yes
	mov	si,bx
	and	si,NOT (PG_NCHUNK * 4 - 1)
	push	si			; SI = offset of its 64K's first PTE
	mov	cx,PG_NCHUNK
pgg1:	test	byte ptr es:[V86_PT+si],PG_PRESENT
	jnz	pgg2			; the 64K has a page already
	add	si,4
	loop	pgg1
pgg2:	pop	si
	jcxz	pgg3
	jmp	short pgg5
pgg3:	mov	dh,1
	call	pg_chunk		; a chunk for the 64K
	jc	pgg5			; there's no room for one
	mov	bx,si
	mov	cx,PG_NCHUNK
pgg4:	mov	ax,bx
	shr	ax,2
	call	pg_mine			; is this page in its memory?
	jc	pgg4a			; no (it ends before the 64K does)
	call	pg_set
pgg4a:	add	bx,4
	loop	pgg4
	mov	es:[V86_CTX].VC_NFREE,0
	clc
	jmp	short pgg9
pgg5:	mov	dh,0
	call	pg_chunk		; a chunk wherever one fits
	jc	pgg9
pgg6:	call	pg_set
	clc
	jmp	short pgg9
pgg8:	mov	ax,ERR_INVALID		; (carry is still set)
pgg9:	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	pg_get
;
; pg_set gives the PTE at BX the chunk's next page.
;
DEFPROC	pg_set
	push	dx
	dec	es:[V86_CTX].VC_NFREE
	mov	ax,word ptr es:[V86_CTX].VC_NEXT
	mov	dx,word ptr es:[V86_CTX].VC_NEXT+2
	add	word ptr es:[V86_CTX].VC_NEXT,PG_SIZE
	adc	word ptr es:[V86_CTX].VC_NEXT+2,0
	or	al,PG_USER		; DX:AX = its PTE
	mov	es:[V86_PT+bx],ax
	mov	es:[V86_PT+bx+2],dx
	cmp	bx,10h * 4		; in the first 64K?
	jae	pgs9			; no
	mov	es:[V86_PT+bx+100h*4],ax
	mov	es:[V86_PT+bx+100h*4+2],dx
pgs9:	pop	dx
	ret
ENDPROC	pg_set

DEFPROC	pg_mine
	cmp	ax,100h			; in the 64K at 1Mb?
	jb	pgm1			; no
	sub	ax,100h
	cmp	ax,10h
	cmc
	jc	pgm9			; no, beyond it
pgm1:	push	dx
	mov	dx,word ptr es:[V86_CTX].VC_LEN+1
	shr	dx,4			; DX = # of pages in its memory
	cmp	ax,dx
	pop	dx
	cmc				; carry set if it's beyond them
pgm9:	ret
ENDPROC	pg_mine
;
; pg_chunk gets the machine a chunk (VC_NEXT, with VC_NFREE pages): PG_NCHUNK
; pages on a 64K boundary (see pg_fit), or unless DH is nonzero, as many as
; fit anywhere (half as many each time, down to one).  The chunk's block is
; allocated as the system's and then given to the machine's owner (as fl_grow
; does), since the owner's LDT may not be the active one (see enc_owner), and
; SV_LEN, SV_OWNER, and SV_ARG are saved, since a page fault can interrupt the
; CPU$ function that's using them.
;
; Inputs:
;	DL = nonzero if it can use the reserve, DH = nonzero for a whole
;	chunk (or none)
;
; Outputs:
;	Carry set if there's no memory for it (AX = ERR_NOMEMORY)
;
DEFPROC	pg_chunk
	pusha
	push	es
	push	ds:[SYS_VARS].SV_LEN.HW
	push	ds:[SYS_VARS].SV_LEN.LW
	push	ds:[SYS_VARS].SV_OWNER
	push	word ptr ds:[SYS_VARS].SV_ARG
	mov	ah,PG_NCHUNK		; AH = # of pages to try for
	mov	al,dl			; AL = nonzero if the reserve will do
pgc1:	push	ax
	cmp	ah,PG_NCHUNK		; a whole chunk?
	jne	pgc1a			; no
	call	pg_fit			; BX -> free PMB, DX:CX = address
	jc	pgc1b
	mov	ds:[SYS_VARS].SV_ARG,MEMF_NONE OR MEMF_HIGH
	mov	ds:[SYS_VARS].SV_OWNER,MCBOWNER_SYSTEM
	mov	ds:[SYS_VARS].SV_LEN.LW,0
	mov	ds:[SYS_VARS].SV_LEN.HW,PG_NCHUNK / 16
	call	alloc_at		; BX -> its PMB
	jmp	short pgc1b
pgc1a:	mov	al,ah
	mov	ah,0
	mov	si,ax
	shr	si,4
	shl	ax,12
	xchg	di,ax			; SI:DI = the chunk's length
	mov	al,MEMF_NONE OR MEMF_HIGH
	mov	bx,MCBOWNER_SYSTEM
	call	alloc_page		; DX:CX = address, BX -> its PMB
pgc1b:	pop	ax
	mov	si,sp
	jc	pgc2
	mov	es,ss:[si+8]		; ES = context (again)
	mov	di,es:[V86_CTX].VC_OWNER
	mov	ds:[bx].PMB_OWNER,di	; (the machine's owner's)
	test	al,al			; can it use the reserve?
	jnz	pgc3			; yes
	push	ax
	push	cx
	push	dx
	mov	ds:[SYS_VARS].SV_ARG,0	; (anywhere; see pmb_largest)
	call	pmb_largest		; DX:CX = the largest free block now
	sub	cx,PG_SIZE
	sbb	dx,PG_NCHUNK / 16	; room for a whole chunk (on a page)?
	pop	dx
	pop	cx
	pop	ax
	jnc	pgc3			; yes
	push	ax
	call	pmb_used		; no, so this one was the reserve's
	call	pmb_free
	pop	ax
	mov	si,sp
pgc2:	cmp	byte ptr ss:[si+21],0	; a whole chunk (the caller's DH)?
	jne	pgc2a			; yes, so nothing less will do
	shr	ah,1			; try for half as many
	jnz	pgc1
pgc2a:	stc
	jmp	short pgc9
pgc3:	mov	word ptr es:[V86_CTX].VC_NEXT,cx
	mov	word ptr es:[V86_CTX].VC_NEXT+2,dx
	mov	es:[V86_CTX].VC_NFREE,ah
	clc
pgc9:	pop	word ptr ds:[SYS_VARS].SV_ARG
	pop	ds:[SYS_VARS].SV_OWNER
	pop	ds:[SYS_VARS].SV_LEN.LW
	pop	ds:[SYS_VARS].SV_LEN.HW
	pop	es
	popa
	mov	ax,ERR_NOMEMORY		; (if carry is set)
	ret
ENDPROC	pg_chunk
;
; pg_fit finds the highest free block that has room for a chunk on a 64K
; boundary, and returns the highest one in it.
;
; Outputs:
;	Carry clear: BX -> free PMB, DX:CX = the chunk's address
;	Carry set if there's none
;
; Modifies:
;	BX, CX, DX
;
DEFPROC	pg_fit
	mov	bx,ds:[SYS_VARS].SV_NPMBS
	shl	bx,5
	add	bx,SYS_PMBS		; BX -> the end of the PMBs
pgf1:	sub	bx,size PMB
	cmp	bx,SYS_PMBS		; any more blocks?
	jb	pgf9			; no (and carry is set)
	cmp	ds:[bx].PMB_TYPE,PMBTYPE_FREE
	jne	pgf1
	mov	cx,ds:[bx].PMB_ADDR.LW
	mov	dx,ds:[bx].PMB_ADDR.HW
	add	cx,ds:[bx].PMB_LEN.LW
	adc	dx,ds:[bx].PMB_LEN.HW	; DX = the 64K where it ends
	sub	dx,PG_NCHUNK / 16	; DX:0 = the last whole 64K before that
	jb	pgf1
	cmp	dx,ds:[bx].PMB_ADDR.HW	; is that in the block?
	jb	pgf1			; no
	ja	pgf2			; yes
	cmp	ds:[bx].PMB_ADDR.LW,0
	jne	pgf1			; no
pgf2:	sub	cx,cx			; DX:CX = the chunk's address
pgf9:	ret
ENDPROC	pg_fit


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_syspf
;
; A page fault outside the machines (see exc_common): if it's in a machine's
; window, at a page of its memory that isn't there yet (eg, its host, or DOS,
; storing something where its program hasn't touched), the page gets its
; memory, from the reserve if need be (see pg_get), since nothing here can
; wait, and the instruction runs again.  SEL_V86STK, which finds the machine's
; context, is restored, in case we interrupted something that was using it.
;
; Outputs:
;	Carry clear if the page is there now, set if the fault isn't ours (or
;	there's no memory for it)
;
; Modifies:
;	None
;
DEFPROC	v86_syspf
	pusha
	push	ds
	push	es
	mov	ax,SEL_SYS
	mov	ds,ax
	mov	bx,ds:[SYS_VARS].SV_V86SEL
	test	bx,bx			; has a machine been created?
	stc
	jz	vsp9			; no
	db	0Fh,20h,0D0h		; MOV EAX,CR2
	db	66h,0C1h,0E8h,12	; SHR EAX,12
	db	66h,50h			; PUSH EAX
	pop	si			; SI = address bits 27-12
	pop	ax			; AX = address bits 31-28
	mov	di,si
	and	di,03FFh		; DI = its page # in its page table
	shr	si,10
	shl	ax,6
	or	ax,si			; AX = its PDE #
	sub	ax,WIN_PDE
	cmp	ax,WIN_SLOTS		; in one of the windows?
	cmc
	jc	vsp9			; no
	push	ds:[SYS_GDT+bx].DESC_BASE
	push	word ptr ds:[SYS_GDT+bx].DESC_BASE16
	push	ds:[SYS_GDT+bx].DESC_EXT
	call	win_ctx			; ES = its machine's context
	jc	vsp1			; (it has none)
	xchg	ax,di			; AX = page #
	mov	dl,1			; (the reserve is for these)
	call	pg_get
vsp1:	mov	bx,ds:[SYS_VARS].SV_V86SEL
	pop	ds:[SYS_GDT+bx].DESC_EXT
	pop	word ptr ds:[SYS_GDT+bx].DESC_BASE16
	pop	ds:[SYS_GDT+bx].DESC_BASE
vsp9:	pop	es
	pop	ds
	popa
	ret
ENDPROC	v86_syspf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_commit (CPU_V86 with AL = 9)
;
; Gives the pages of SI:DI bytes of a machine's memory their memory now (see
; pg_get), without using the reserve, so that its host knows they're there
; before it has DOS store something in them (eg, a program it's loading), or
; can wait until they can be (see V86X_NOMEM); any that aren't its memory's
; (eg, its video memory's) are skipped.
;
; Inputs:
;	BX = machine, DX:CX = address in the machine, SI:DI = # of bytes
;
; Outputs:
;	Carry clear if successful, set if not (AX = ERR_NOMEMORY, or
;	ERR_INVALID if it's not a V86 machine or its addresses)
;
DEFPROC	v86_commit
	push	es
	push	cx
	push	dx
	push	si
	call	v86_find		; ES = its context
	pop	si
	pop	dx
	pop	cx
	jc	vcm9
	cmp	es:[V86_CTX].VC_FLAT,0	; a flat machine?
	jne	vcm8			; yes
	mov	ax,si
	or	ax,di			; any bytes?
	jz	vcm9			; no (and carry is clear)
	add	di,cx
	adc	si,dx
	sub	di,1
	sbb	si,0			; SI:DI = the last byte's address
	cmp	si,10h			; beyond the 64K at 1Mb (or wrapped)?
	ja	vcm8			; yes
	shr	cx,12
	shl	dx,4
	or	cx,dx			; CX = the first page
	shr	di,12
	shl	si,4
	or	di,si			; DI = the last
	cmp	di,cx
	jb	vcm8
	sub	dx,dx			; (DL = 0: not from the reserve)
vcm1:	mov	ax,cx
	call	pg_get
	jnc	vcm2
	cmp	al,ERR_NOMEMORY
	stc
	je	vcm9
vcm2:	inc	cx
	cmp	cx,di
	jbe	vcm1
	clc
	jmp	short vcm9
vcm8:	mov	ax,ERR_INVALID
	stc
vcm9:	pop	es
	ret
ENDPROC	v86_commit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_find, win_ctx, win_slot, and pd_master
;
; v86_find finds a machine's context: a V86 machine is the first selector of
; its memory, whose base is its window's, and the window's PDE is its page
; table, which follows its context (win_ctx does that for a window's slot);
; a flat machine is its context's selector (see fl_create).  win_slot finds
; a window that no machine has, and pd_master points ES at the system's page
; directory.
;
; Inputs:
;	BX = machine (v86_find), or AX = slot (win_ctx)
;	DS = SEL_SYS
;
; Outputs:
;	Carry clear: ES = SEL_V86STK (its context) and DX:CX = its address
;	(v86_find and win_ctx), or AX = slot (win_slot)
;	Carry set if there's none (AX = ERR_INVALID)
;
; Modifies:
;	AX, BX, CX, DX, SI (v86_find); AX, BX, CX, DX (win_ctx and pd_master);
;	AX, BX, DX, ES (win_slot)
;
DEFPROC	v86_find
	push	bx
	call	sel_desc		; SI -> its descriptor
	pop	cx			; CX = the machine
	jc	wc8
	cmp	ds:[si].DESC_BASE,0
	jne	vfd1
	mov	al,ds:[si].DESC_BASE16
	mov	ah,byte ptr ds:[si].DESC_EXT+1
	sub	ax,(LIN_HI SHL 8) + WIN_ADDR
	test	al,3Fh			; a window's base?
	jnz	vfd1			; no
	shr	ax,6			; AX = slot
	cmp	ax,WIN_SLOTS
	jb	win_ctx
vfd1:	mov	dx,-1
	call	pmb_used		; BX -> PMB
	jc	wc8
	mov	cx,ds:[bx].PMB_V86
	jcxz	wc8			; it isn't a flat machine's context
	mov	dx,cx
	shr	dx,4
	shl	cx,12			; DX:CX = its context
	jmp	short wc1
	DEFLBL	win_ctx,near
	add	ax,WIN_PDE
	xchg	cx,ax			; CX = its PDE #
	mov	ax,ds:[SYS_VARS].SV_PDIR.LW
	mov	dx,ds:[SYS_VARS].SV_PDIR.HW
	call	pg_entry		; DX:AX = its page table
	jc	wc8			; (no machine has it)
	sub	ax,V86_PT
	sbb	dx,0
	xchg	cx,ax			; DX:CX = its context
wc1:	call	v86_stk
	clc
	ret
wc8:	jmp	cpu_inval
ENDPROC	v86_find

DEFPROC	win_slot
	call	pd_master
	mov	bx,WIN_PDE * 4
	sub	ax,ax
ws1:	test	byte ptr es:[bx],PG_PRESENT
	jz	ws9			; it's free (and carry is clear)
	add	bx,4
	inc	ax
	cmp	ax,WIN_SLOTS
	jb	ws1
	stc
ws9:	ret
ENDPROC	win_slot

DEFPROC	pd_master
	mov	ax,ds:[SYS_VARS].SV_PDIR.LW
	mov	dx,ds:[SYS_VARS].SV_PDIR.HW
	mov	bx,SEL_TMP2
	call	pm_ptr			; BX = selector, AX = offset (zero)
	mov	es,bx
	ret
ENDPROC	pd_master

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_free
;
; When a V86 machine's context is freed (see pmb_free), its window's PDE
; goes, and the TLB's entries for it, so that another machine can have the
; window; its memory's chunks are its owner's, and are freed with the owner.
;
; Inputs:
;	BX -> PMB (with PMB_V86), DS = SEL_SYS
;
; Modifies:
;	None
;
DEFPROC	v86_free
	cmp	ds:[bx].PMB_FLAT,0	; a flat machine's context?
	jne	vfr9			; yes (it has no window)
	pusha
	push	es
	mov	si,ds:[bx].PMB_ADDR.LW
	mov	di,ds:[bx].PMB_ADDR.HW
	add	si,V86_PT
	adc	di,0			; DI:SI = its page table
	call	pd_master		; ES:0 -> the system's page directory
	mov	bx,WIN_PDE * 4
	mov	cx,WIN_SLOTS
vfr1:	mov	ax,es:[bx]
	test	al,PG_PRESENT
	jz	vfr2
	and	ax,NOT (PG_SIZE - 1)
	cmp	ax,si
	jne	vfr2
	cmp	es:[bx+2],di		; is this its window?
	jne	vfr2			; no
	sub	ax,ax
	mov	es:[bx],ax
	mov	es:[bx+2],ax
	db	0Fh,20h,0D8h		; MOV EAX,CR3
	db	0Fh,22h,0D8h		; MOV CR3,EAX (flush the TLB)
	jmp	short vfr8
vfr2:	add	bx,4
	loop	vfr1
vfr8:	pop	es
	popa
vfr9:	ret
ENDPROC	v86_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; io_close
;
; Sets the bits of a machine's ports in the TSS's I/O permission bitmap
; again (see v86_resume) when it stops: all of them, if a driver lent it
; any, or else just the video ports'.
;
; Inputs:
;	DS = SEL_SYS, SS = context
;
; Modifies:
;	CX, DI, ES
;
DEFPROC	io_close
	push	ax
	push	ds
	pop	es
	mov	di,SYS_IOMAP
	mov	cx,(IOMAP_LEN - 1) / 2
	cmp	ss:[V86_CTX].VC_IOSET,0	; were any ports lent to it?
	jne	ioc1			; yes
	mov	di,SYS_IOMAP + IOMAP_VIDEO
	mov	cx,2			; no, so just the video ports'
ioc1:	mov	ax,-1
	rep	stosw
	pop	ax
	ret
ENDPROC	io_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_ports
;
; Lends ports to a machine (AL = 4), or takes them back (AL = 5), for a
; driver that owns a device (eg, SND$): the ports' bits in the machine's I/O
; permission bitmap (VC_IOMAP), which v86_resume copies into the TSS's while
; the machine runs, are cleared (or set again).  The bitmap ends below the
; video ports, which only the machine's video memory gives it (see v86_vid),
; and it has a byte for every 8 ports, so the ports must be whole bytes.
;
; Inputs:
;	AL = 4 or 5, BX = machine (see v86_find)
;	CX = first port, DX = # of ports (multiples of 8)
;	ES:DI -> the driver's function to call when the machine is suspended
;	or resumes (see v86_susp), or 0:0 (AL = 4 only)
;
; Outputs:
;	Carry clear if successful, set if not (AX = ERR_INVALID)
;
DEFPROC	v86_ports
	push	es
	push	di			; (the driver's function, if any)
	mov	si,cx
	or	si,dx
	test	si,7			; whole bytes of the bitmap?
	jnz	vp8			; no
	mov	si,cx
	add	si,dx
	jc	vp8
	cmp	si,IOMAP_VIDEO * 8	; below the video ports?
	ja	vp8			; no
	push	ax
	push	cx
	push	dx
	call	v86_find		; ES = its context
	pop	si			; SI = # of ports
	pop	di			; DI = first port
	pop	ax
	jc	vp8
	pop	word ptr es:[V86_CTX].VC_NOTE
	pop	word ptr es:[V86_CTX].VC_NOTE+2
	sub	al,5			; AL = 0 to take them back, else FFh
	jnz	vp1
	mov	word ptr es:[V86_CTX].VC_NOTE+2,0	; (and no more calls)
vp1:	not	al			; AL = byte for the bitmap
	mov	es:[V86_CTX].VC_IOSET,1
	mov	cx,si
	shr	cx,3			; CX = # of bytes
	shr	di,3
	add	di,V86_CTX + VC_IOMAP	; ES:DI -> the first port's byte
	cld
	rep	stosb			; (and carry is clear)
	ret
vp8:	pop	di
	pop	es
	jmp	cpu_inval
ENDPROC	v86_ports

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_susp and v86_note
;
; v86_susp suspends a machine whose console's state is somewhere else (see
; v86_resume): it waits for its video memory selector (as a page fault in
; that memory does; see v86_pf), and then resumes, or if the wait ends early
; (eg, for a CTRLC or KILL), exits as after an interrupt (VR_VEC = 0Eh), so
; that DOS can act on it.  The first time, the driver that lent it ports (if
; it asked; see v86_ports) is told, and told again when it resumes, so that
; the device can stop and start, too (eg, SND$ pauses a sound card's DMA).
;
; v86_note calls that driver's function with AL = 0 (suspended) or 1
; (resumed), with interrupts off; it can change any register but DS and ES.
;
; Inputs:
;	DS = SEL_SYS, ES = context, SS:SP as for v86_resume
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	v86_susp
	cmp	es:[V86_CTX].VC_SUSP,0	; suspended already?
	jne	vu1			; yes
	mov	es:[V86_CTX].VC_SUSP,1
	mov	al,0			; (it's suspended)
	call	v86_note
vu1:	mov	dx,SELID_WAIT
	mov	di,es:[V86_CTX].VC_VID	; DX:DI = its wait ID
	mov	ah,DDUTL_WAIT
	call	far ptr DDINT_UTIL
	jc	vu9			; the wait ended early
	jmp	v86_resume
vu9:	mov	es:[V86_CTX].VR_VEC,INT_PF
	mov	al,V86X_TICK
	jmp	v86_exit
ENDPROC	v86_susp

DEFPROC	v86_note
	cmp	word ptr es:[V86_CTX].VC_NOTE+2,0	; a function to call?
	je	vn9			; no
	pusha
	push	ds
	push	es
	call	dword ptr es:[V86_CTX].VC_NOTE
	pop	es
	pop	ds
	popa
vn9:	ret
ENDPROC	v86_note

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_setup
;
; The first time a machine is created, builds the machines' IDT (in a block of
; the system's), whose present gates go to v86_stubs: the exceptions
; (00h-11h) and the IRQs (70h-7Fh); and allocates SV_V86SEL's two GDT
; selectors: SEL_V86STK (for a context and its page directory; see v86_stk)
; and SEL_V86MEM (see v86_seg).
;
; Inputs:
;	DS = SEL_SYS
;
; Outputs:
;	Carry clear if successful, set if not (AX = error code)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	v86_setup
	cmp	ds:[SYS_VARS].SV_V86SEL,0
	jne	vs9			; already done (and carry is clear)
	mov	al,MEMF_NONE OR MEMF_HIGH
	mov	bx,MCBOWNER_SYSTEM
	sub	si,si
	mov	di,80h * (size DESC)
	call	ddcpu_alloc		; DX:CX = address
	jc	vs9
	mov	ds:[SYS_VARS].SV_V86IDTR,80h * (size DESC) - 1
	mov	ds:[SYS_VARS].SV_V86IDTR+2,cx
	mov	byte ptr ds:[SYS_VARS].SV_V86IDTR+4,dl
	mov	al,dh
	add	al,LIN_HI
	mov	byte ptr ds:[SYS_VARS].SV_V86IDTR+5,al
	xchg	ax,cx			; DX:AX = address
	mov	bx,SEL_TMP
	call	pm_ptr
	mov	es,bx
	sub	di,di
	sub	bx,bx			; BL = vector
vs1:	mov	al,bl
	cmp	al,V86_NSTUBS		; an exception with a stub?
	jb	vs2			; yes
	cmp	al,IRQ_SLAVE		; an IRQ?
	jb	vs3			; no
	sub	al,IRQ_SLAVE - V86_NSTUBS
vs2:	mov	ah,3
	mul	ah
	add	ax,offset DEV:v86_stubs
	stosw				; offset
	mov	ax,SEL_CPUCODE
	stosw				; selector
	mov	ax,ACC_INTG386 SHL 8
	jmp	short vs4
vs3:	sub	ax,ax			; (not present)
	stosw
	stosw
vs4:	stosw
	sub	ax,ax
	stosw
	inc	bl
	cmp	bl,80h
	jb	vs1
	sub	ax,ax			; AL = 0 (GDT data, DPL 0)
	mov	cx,2
	call	desc_alloc		; AX = selector, BX -> descriptor
	jc	vs9
	mov	ds:[bx].DESC_LIMIT,3 * PG_SIZE - 1	; (see FL_PD)
	mov	ds:[bx+size DESC].DESC_LIMIT,0FFFFh
	mov	ds:[SYS_VARS].SV_V86SEL,ax
	clc
vs9:	ret
ENDPROC	v86_setup

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fl_func (CPU_V86 with AL = 6, 7, or 8)
;
; A flat machine's functions (see v86.inc): AL = 6 creates one (fl_create),
; 7 points one of its two selectors at a linear address (fl_lin), and 8 adds
; memory to it (fl_grow).  The caller's ES is preserved.
;
DEFPROC	fl_func
	push	es
	call	ff1
	pop	es
	ret
ff1:	cmp	al,7
	je	fl_lin
	ja	ff2
	jmp	fl_create
ff2:	jmp	fl_grow
ENDPROC	fl_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fl_lin
;
; Points one of a flat machine's two selectors (VR_DSSEL or VR_ESSEL) at a
; linear address in the machine, so that its host can pass a pointer there to
; DOS; the selector covers as many of the bytes that follow as are in
; consecutive physical pages (at most 64K), since DOS and the drivers use it
; with the system's page directory.
;
; Inputs:
;	BX = machine, DX:CX = linear address, SI = 0 (VR_DSSEL) or 1 (VR_ESSEL)
;
; Outputs:
;	Carry clear: AX = selector, CX = its limit
;	Carry set: AX = ERR_INVALID (eg, the address has no memory)
;
DEFPROC	fl_lin
	cmp	si,1
	jbe	fn0b
fn0:	jmp	cpu_inval
fn0a:	pop	si
	jmp	fn0
fn0b:	push	si
	push	cx
	push	dx
	call	fl_find			; ES = its context
	pop	dx
	pop	ax			; DX:AX = linear address
	pop	si
	jc	fn0
	shl	si,3
	add	si,es:[V86_CTX].VR_DSSEL
	push	si			; the selector
	mov	bp,ax
	and	bp,PG_SIZE - 1		; BP = the address's offset in its page
	sub	cx,cx			; CH = 0 (no new page tables)
	call	fl_pte			; ES:BX -> the first page's PTE
	jc	fn0a
	mov	si,es:[bx]
	mov	di,es:[bx+2]		; DI:SI = PTE
	test	si,PG_PRESENT
	jz	fn0a
	and	si,NOT (PG_SIZE - 1)	; DI:SI = the page's address
	push	di
	push	si
	inc	cx			; CL = # of consecutive pages so far
fn1:	add	ax,PG_SIZE
	adc	dx,0
	add	si,PG_SIZE
	adc	di,0			; DI:SI = the next page, if it follows
	mov	es,ds:[SYS_VARS].SV_V86SEL
	call	fl_pte
	jc	fn2
	push	ax
	mov	ax,es:[bx]
	test	al,PG_PRESENT
	jz	fn1a
	and	ax,NOT (PG_SIZE - 1)
	cmp	ax,si
	jne	fn1a
	mov	ax,es:[bx+2]
	cmp	ax,di			; is it the next physical page?
	jne	fn1a			; no
	pop	ax
	inc	cx
	cmp	cl,17			; more than 64K yet?
	jb	fn1			; no
	jmp	short fn2
fn1a:	pop	ax
fn2:	pop	si
	pop	di			; DI:SI = the first page's address
	mov	ax,0FFFFh
	cmp	cl,17			; 64K or more from the address?
	jae	fn3			; yes
	mov	ah,cl
	shl	ah,4
	mov	al,0			; AX = the pages' length (0 if 64K)
	sub	ax,bp
	dec	ax			; AX = limit
fn3:	add	si,bp			; DI:SI = its physical address
	pop	bx			; BX = selector
	push	ax
	push	si
	call	sel_desc		; SI -> its descriptor
	pop	cx
	pop	dx			; DX = limit
	jc	fn9
	mov	ds:[si].DESC_LIMIT,dx
	mov	ds:[si].DESC_BASE,cx
	mov	ax,di
	mov	ds:[si].DESC_BASE16,al
	add	ah,LIN_HI
	mov	al,0
	mov	ds:[si].DESC_EXT,ax
	xchg	ax,bx			; AX = selector
	mov	cx,dx			; CX = limit (and carry is clear)
fn9:	ret
ENDPROC	fl_lin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fl_create
;
; Creates a flat machine, owned by BX, with SI:DI bytes of memory (rounded up
; to a multiple of 4K) at linear address FL_BASE, in a block from the top of
; memory.  Its context, first page table, and page directory are in a block
; of their own (see FL_PD), whose PMB has PMB_FLAT set, the context's page
; number (PMB_V86), and the machine's FL_NSEL LDT selectors, so that they're
; freed with it: one for the context itself (DPL 0), which names the machine,
; two for its host to point at its memory (VR_DSSEL and VR_ESSEL; see
; fl_lin), and its code and data selectors (base 0, for every linear address
; below the system's).  Every block is the owner's, so they're all freed
; when it ends.
;
; Inputs:
;	BX = owner, SI:DI = length
;
; Outputs:
;	Carry clear: AX = machine, DX:CX = its memory's linear address
;	Carry set: AX = error code
;
DEFPROC	fl_create
	push	bx
	push	si
	push	di
	call	v86_setup		; the machines' IDT and selectors
	pop	di
	pop	si
	pop	bx
	jnc	fc0a
fc0:	ret
fc0a:	call	fl_round		; SI:DI = length, in pages
	jnz	fc0b
	jmp	cpu_inval		; (it's zero)
fc0b:	push	bx
	push	si
	push	di
	mov	al,MEMF_NONE OR MEMF_HIGH
	call	alloc_page		; DX:CX = its memory
	pop	di
	pop	si
	pop	bx
	jc	fc0
	push	si
	push	di			; [BP+6]:[BP+4] = length
	push	dx
	push	cx			; [BP+2]:[BP] = memory
	mov	bp,sp
	push	bp
	mov	al,MEMF_NONE OR MEMF_HIGH
	sub	si,si
	mov	di,3 * PG_SIZE
	call	alloc_page		; DX:CX = context, BX -> its PMB
	pop	bp
	jnc	fc0c
	jmp	fc7
fc0c:
	push	dx
	push	cx			; [BP-2]:[BP-4] = context
	push	ds:[bx].PMB_OWNER	; [BP-6] = owner ID
	mov	al,MEMF_LDT
	mov	cx,FL_NSEL
	call	desc_alloc		; AX = first selector, BX -> its DESC
	jnc	fc0d
	jmp	fc6
fc0d:	push	ax			; [BP-8] = the machine
	mov	cx,[bp-4]
	mov	dx,[bp-2]
	call	fc_desc			; the machine (DPL 0): its context
	mov	cx,[bp]
	mov	dx,[bp+2]
	call	fc_desc			; VR_DSSEL: one byte of memory, for now
	or	ds:[bx - size DESC].DESC_ACC,ACC_DPL3
	call	fc_desc			; VR_ESSEL: the same
	or	ds:[bx - size DESC].DESC_ACC,ACC_DPL3
	mov	al,ACC_CODE OR ACC_DPL3
	call	fc_flat			; code: all below the system's
	mov	al,ACC_DATA OR ACC_DPL3
	call	fc_flat			; and data
	mov	cx,[bp-4]
	mov	dx,[bp-2]
	call	pmb_used		; BX -> the context's PMB
	mov	ax,[bp-8]
	mov	ds:[bx].PMB_SEL,ax
	mov	ds:[bx].PMB_NSEL,FL_NSEL
	mov	ds:[bx].PMB_FLAT,1
	mov	ax,[bp-4]
	mov	dx,[bp-2]
	shr	ax,12
	shl	dx,4
	or	ax,dx			; AX = the context's page #
	mov	ds:[bx].PMB_V86,ax
	mov	cx,[bp-4]
	mov	dx,[bp-2]
	call	v86_stk			; ES = context
	sub	di,di
	mov	cx,3 * PG_SIZE / 2
	sub	ax,ax
	cld
	rep	stosw
	mov	ax,[bp-4]
	mov	dx,[bp-2]
	mov	di,FL_PD
	call	v86_pdes
	mov	di,V86_CTX + VC_IOMAP
	mov	cx,(IOMAP_LEN - 1) / 2
	mov	ax,-1
	rep	stosw			; no ports
	inc	es:[V86_CTX].VC_FLAT
	mov	ax,[bp-6]
	mov	es:[V86_CTX].VC_OWNER,ax
	mov	ax,[bp-8]
	mov	es:[V86_CTX].VC_FSEL,ax
	add	ax,size DESC + 3	; (RPL 3, for the ring 3 host)
	mov	es:[V86_CTX].VR_DSSEL,ax
	add	ax,size DESC
	mov	es:[V86_CTX].VR_ESSEL,ax
	mov	word ptr es:[V86_CTX].VC_TOP+2,FL_BASE
	mov	cx,[bp]
	mov	dx,[bp+2]
	mov	di,[bp+4]
	mov	si,[bp+6]
	call	fl_add			; give it its memory
	jc	fc6
	mov	ax,[bp-8]		; AX = the machine
	mov	sp,bp
	add	sp,8
	sub	cx,cx
	mov	dx,FL_BASE		; DX:CX = its memory's linear address
	ret				; (carry is clear)
fc6:	mov	cx,[bp-4]
	mov	dx,[bp-2]
	call	fc_free			; free the context's block
fc7:	mov	cx,[bp]
	mov	dx,[bp+2]
	call	fc_free			; and the memory's
	mov	sp,bp
	add	sp,8
	mov	ax,ERR_NOMEMORY
	stc
fc9:	ret
fc_free:
	call	pmb_used
	jc	fc9
	jmp	pmb_free
;
; fc_desc fills in the descriptor at BX for the byte at DX:CX, and fc_flat
; for the whole address space, with access rights AL; both advance BX.
;
fc_desc:
	mov	ds:[bx].DESC_LIMIT,0
	mov	ds:[bx].DESC_BASE,cx
	mov	ds:[bx].DESC_BASE16,dl
	mov	ah,dh
	add	ah,LIN_HI
	mov	al,0
	mov	ds:[bx].DESC_EXT,ax
	jmp	short fc_next
fc_flat:
	mov	ds:[bx].DESC_LIMIT,0FFFFh
	mov	ds:[bx].DESC_BASE,0
	mov	ds:[bx].DESC_BASE16,0
	mov	ds:[bx].DESC_ACC,al
	mov	ds:[bx].DESC_EXT,EXT_FLAT
fc_next:
	add	bx,size DESC
	ret
ENDPROC	fl_create

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fl_grow
;
; Adds SI:DI bytes of memory (rounded up to a multiple of 4K) to a flat
; machine, in a block of its owner's, at the end of the memory it has.
;
; Inputs:
;	BX = machine, SI:DI = length
;
; Outputs:
;	Carry clear: DX:CX = the new memory's linear address
;	Carry set: AX = error code
;
DEFPROC	fl_grow
	push	si
	push	di
	call	fl_find			; ES = its context
	pop	di
	pop	si
	jc	fg8
	call	fl_round		; SI:DI = length, in pages
	jz	fg8			; (it's zero)
	push	si
	push	di
	mov	al,MEMF_NONE OR MEMF_HIGH
	mov	bx,MCBOWNER_SYSTEM
	call	alloc_page		; DX:CX = address, BX -> its PMB
	pop	di
	pop	si
	jc	fg9
	mov	es,ds:[SYS_VARS].SV_V86SEL
	mov	ax,es:[V86_CTX].VC_OWNER
	mov	ds:[bx].PMB_OWNER,ax	; (the machine's owner's)
	push	word ptr es:[V86_CTX].VC_TOP+2
	push	word ptr es:[V86_CTX].VC_TOP
	call	fl_add
	pop	cx
	pop	dx			; DX:CX = its linear address
	jnc	fg9
	mov	ax,ERR_NOMEMORY
fg9:	ret
fg8:	jmp	cpu_inval
ENDPROC	fl_grow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fl_add
;
; Maps a block at the end of a flat machine's memory (VC_TOP).
;
; Inputs:
;	DX:CX = block's address, SI:DI = its length (a multiple of PG_SIZE)
;	DS = SEL_SYS, ES = context
;
; Outputs:
;	Carry set if there's no memory for a page table
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	fl_add
	shr	di,12
	shl	si,4
	or	di,si			; DI = # of pages
	or	cl,PG_USER		; DX:CX = the first page's PTE
fa1:	push	cx
	push	dx
	mov	ax,word ptr es:[V86_CTX].VC_TOP
	mov	dx,word ptr es:[V86_CTX].VC_TOP+2
	mov	ch,1			; (with a new page table, if need be)
	call	fl_pte			; ES:BX -> the page's PTE
	pop	dx
	pop	cx
	jc	fa9
	mov	es:[bx],cx
	mov	es:[bx+2],dx
	mov	es,ds:[SYS_VARS].SV_V86SEL
	add	word ptr es:[V86_CTX].VC_TOP,PG_SIZE
	adc	word ptr es:[V86_CTX].VC_TOP+2,0
	add	cx,PG_SIZE
	adc	dx,0
	dec	di
	jnz	fa1
	clc
fa9:	ret
ENDPROC	fl_add

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fl_pte
;
; Finds the PTE of a linear address in a flat machine: in its first page
; table (after its context), or in one that its page directory points to,
; which is created if CH is set (in a block of the machine's owner's).
;
; Inputs:
;	DX:AX = linear address, CH = nonzero to create its page table
;	DS = SEL_SYS, ES = context
;
; Outputs:
;	Carry clear: ES:BX -> PTE (ES is the context's selector or SEL_TMP)
;	Carry set if there's none
;
; Modifies:
;	BX, ES
;
DEFPROC	fl_pte
	push	ax
	push	dx
	push	si
	mov	bx,dx
	shr	bx,6			; BX = its PDE's index
	cmp	bx,LIN_HI * 4		; one of the system's addresses?
	jae	fp8			; yes
	shl	bx,2
	shl	dx,4
	shr	ax,12
	or	ax,dx
	and	ax,03FFh
	shl	ax,2
	xchg	si,ax			; SI = its PTE's offset in its table
	test	bx,bx			; in the first page table?
	jnz	fp1			; no
	lea	bx,[si+V86_PT]		; ES:BX -> PTE (and carry is clear)
	jmp	short fp9
fp1:	test	byte ptr es:[bx+FL_PD],PG_PRESENT
	jnz	fp2
	test	ch,ch			; create its page table?
	jz	fp8			; no
	call	fl_newpt
	jc	fp9
fp2:	mov	ax,es:[bx+FL_PD]
	mov	dx,es:[bx+FL_PD+2]
	and	ax,NOT (PG_SIZE - 1)	; DX:AX = the page table
	mov	bx,SEL_TMP
	call	pm_ptr
	mov	es,bx
	mov	bx,si			; ES:BX -> PTE
	clc
	jmp	short fp9
fp8:	stc
fp9:	pop	si
	pop	dx
	pop	ax
	ret
ENDPROC	fl_pte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fl_newpt
;
; Gives a flat machine another page table, in a block of its owner's.
;
; Inputs:
;	BX = offset of its PDE in the page directory
;	DS = SEL_SYS, ES = context
;
; Outputs:
;	Carry set if there's no memory for it
;
DEFPROC	fl_newpt
	pusha
	push	bx
	mov	al,MEMF_NONE OR MEMF_HIGH
	mov	bx,MCBOWNER_SYSTEM
	sub	si,si
	mov	di,PG_SIZE
	call	alloc_page		; DX:CX = address, BX -> its PMB
	pop	di			; DI = the PDE's offset
	jc	fw9
	mov	es,ds:[SYS_VARS].SV_V86SEL
	mov	ax,es:[V86_CTX].VC_OWNER
	mov	ds:[bx].PMB_OWNER,ax	; (the machine's owner's)
	mov	ax,cx
	or	al,PG_USER
	mov	es:[di+FL_PD],ax
	mov	es:[di+FL_PD+2],dx
	xchg	ax,cx			; DX:AX = the page table
	mov	bx,SEL_TMP
	call	pm_ptr			; (AX = 0)
	mov	es,bx
	sub	di,di
	mov	cx,PG_SIZE / 2
	cld
	rep	stosw
	mov	es,ds:[SYS_VARS].SV_V86SEL
	clc
fw9:	popa
	ret
ENDPROC	fl_newpt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fl_find, fl_round, and fl_seg
;
; fl_find points ES at a flat machine's context, fl_round rounds a length up
; to a multiple of PG_SIZE, and fl_seg checks a selector for one of a flat
; machine's data segment registers: unless ring 3 could load it (readable,
; with DPL 3, and present), it becomes zero.
;
; Inputs:
;	BX = machine (fl_find), SI:DI = length (fl_round), AX = selector
;	(fl_seg)
;
; Outputs:
;	Carry clear, ES = SEL_V86STK, or carry set if it's not one (fl_find)
;	SI:DI = length, ZF set if it's zero (fl_round)
;	AX = selector, or zero (fl_seg)
;
; Modifies:
;	AX, BX, CX, DX (fl_find); AX (fl_round); CX (fl_seg)
;
DEFPROC	fl_find
	mov	cx,bx
	mov	dx,-1
	call	pmb_used		; BX -> PMB
	jc	ff9
	cmp	ds:[bx].PMB_FLAT,1	; a flat machine's context?
	jb	ff9			; no (and carry is set)
	mov	cx,ds:[bx].PMB_V86
	mov	dx,cx
	shr	dx,4
	shl	cx,12			; DX:CX = the context
	call	v86_stk			; (carry is clear)
ff9:	ret
ENDPROC	fl_find

DEFPROC	fl_round
	add	di,PG_SIZE - 1
	adc	si,0
	and	di,NOT (PG_SIZE - 1)
	mov	ax,di
	or	ax,si
	ret
ENDPROC	fl_round

DEFPROC	fl_seg
	or	al,3			; (as ring 3 would load it)
	verr	ax			; readable at ring 3?
	jnz	fs8			; no
	lar	cx,ax
	jnz	fs8
	test	ch,ACC_PRESENT		; and present?
	jnz	fs9			; yes
fs8:	sub	ax,ax
fs9:	ret
ENDPROC	fl_seg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fl_event
;
; An interrupt or exception from a flat machine (see v86_common): a hardware
; interrupt goes to the system's handler, as a V86 machine's does (see
; v86_irq), and an INT exits to the host (V86X_INT), with VR_EIP past it;
; the machine's IDT has no gates that ring 3 can use, so an INT is a general
; protection fault whose error code names the vector's gate.  An INT 3 goes
; to the system's handler instead (as a 16-bit program's does: a debugger's,
; or else DOS's, which ignores it), with VR_VEC = 03h and VR_EIP past it,
; and so does a single-step trap that a debugger wants (see v86_regs), and
; then the machine runs again.
;
; Anything else is a fault (including INTO), which exits (V86X_FAULT), but
; first, the system's INT 03h handler is called for it, too, with the fault
; pending (VC_PEND), so that a debugger there can see it (VR_VEC is its
; vector, and VR_ERR its error code): if the debugger changes the machine's
; registers (see v86_regs), the fault is no longer pending, and the machine
; runs again when the handler returns (see v86_irq).  An INT 3 that follows
; a NOP (a failed assertion; see ASSERT) is pending, too, so without a
; debugger, it exits as a fault with vector 03h.
;
; Inputs:
;	AL = vector, DS = SEL_SYS, ES = SS = context
;
DEFPROC	fl_event
	mov	dx,offset DEV:v86_irq
	cmp	al,IRQ_SLAVE		; a hardware interrupt?
	jae	fe0			; yes
	cmp	al,INT_NMI		; an NMI?
	jne	fe0a			; no
fe0:	jmp	v86_leave
fe0a:	cmp	al,INT_DB		; a single-step trap?
	jne	fe1			; no
	cmp	es:[V86_CTX].VC_DBG,0	; does a debugger get them?
	jne	fe0			; yes
fe1:	cmp	al,INT_GP		; a general protection fault?
	jne	fe7			; no
	mov	bx,word ptr es:[V86_CTX].VR_ERR
	test	bl,1			; from an external event?
	jnz	fe7			; yes
	shr	bx,3			; BX = vector, if it was an INT
;
; The fault is an INT if its instruction is one, for the vector that the
; error code names (an INTO is just a fault), so we read it, through
; SEL_V86MEM (see v86_seg), whose base V86 machines keep below 16Mb, along
; with the byte before it, unless that's in another page (which may not be
; there), in which case the instruction's first byte stands in for it.
;
	mov	si,ds:[SYS_VARS].SV_V86SEL
	add	si,size DESC		; SI = SEL_V86MEM
	mov	ax,word ptr es:[V86_CTX].VR_EIP
	sub	di,di			; DI = the instruction's offset
	test	ax,PG_SIZE - 1		; at the start of a page?
	jz	fe1a			; yes
	inc	di
	dec	ax			; (which can't borrow)
fe1a:	mov	ds:[SYS_GDT+si].DESC_BASE,ax
	mov	ax,word ptr es:[V86_CTX].VR_EIP+2
	mov	ds:[SYS_GDT+si].DESC_BASE16,al
	mov	byte ptr ds:[SYS_GDT+si].DESC_EXT+1,ah
	db	8Eh,0EEh		; MOV GS,SI
	db	65h			; (GS:)
	mov	ax,ds:[di]		; AL = opcode, AH = its vector
	db	65h			; (GS:)
	mov	ch,ds:[0]		; CH = the byte before it
	mov	byte ptr ds:[SYS_GDT+si].DESC_EXT+1,0
	mov	si,1			; SI = the instruction's length
	cmp	al,OP_INT03		; the one-byte INT 3?
	je	fe2			; yes
	cmp	al,OP_INT
	jne	fe7
	cmp	ah,bl
	jne	fe7
	inc	si
fe2:	add	word ptr es:[V86_CTX].VR_EIP,si
	adc	word ptr es:[V86_CTX].VR_EIP+2,0
	mov	es:[V86_CTX].VR_VEC,bx
	mov	al,INT_BP
	cmp	bl,al			; an INT 3 (of either length)?
	jne	fe6			; no
	cmp	ch,OP_NOP		; after a NOP?
	jne	fe8			; no
	jmp	short fe7
fe6:	mov	al,V86X_INT
	jmp	v86_out
fe7:	inc	es:[V86_CTX].VC_PEND
	mov	al,INT_BP
fe8:	jmp	v86_leave
ENDPROC	fl_event

CODE	ends

	end
