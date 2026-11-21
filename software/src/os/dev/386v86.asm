;
; BASIC-DOS 80386 Processor (CPU$) Driver: V86 Machines
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
; own, whose PMB has the two LDT selectors that the machine's exits update
; (VR_DSSEL and VR_ESSEL), so that they're freed with it; the machine's
; memory's PMB has its page number (PMB_V86).  The page directory has the
; system's PDEs (see LIN_HI) and the PDE for the page table, which maps the
; machine's first 1Mb (plus the 64K that wraps), and the rest of its page is
; free, so the machine's context (V86CTX) is there, too.  A machine that has
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
	EXTNEAR	<enc_owner>

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
VC_MEM		dd	?	; the machine's memory (physical address)
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
V86CTX		ends

V86_CTX		equ	0800h	; context's offset (PDEs for 80000000h and up)
V86_PT		equ	PG_SIZE	; page table's offset (in the next page)
V86_MAXLEN	equ	0Ah	; most memory a machine can have (640K), in 64K
V86_NSTUBS	equ	12h	; exception stubs (00h-11h), before the IRQs'
FL_V86		equ	0DD5h	; flags that the machine can change
TSS_ESP0	equ	SYS_TSS + 4	; the 80386 TSS's ring 0 stack
TSS_SS0		equ	SYS_TSS + 8

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

	DEFLBL	v86_begin,near

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_func (CPU_V86)
;
; Inputs:
;	AL = 0 to create a machine (see v86_create), 1 to run one (see
;	v86_run), 2 or 3 to copy registers (see v86_regs), or 4 or 5 to lend
;	ports or take them back (see v86_ports)
;
DEFPROC	v86_func
	cmp	al,1
	je	v86_run
	jb	vf1
	cmp	al,3			; copying registers?
	jbe	v86_regs		; yes
	cmp	al,5			; lending ports?
	ja	vf8			; no
	jmp	v86_ports		; yes
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
;	BX = machine (its memory's first selector)
;	ES:DI -> V86REGS
;
; Outputs:
;	Carry clear: AL = V86X_* (see v86.inc), V86REGS updated
;	Carry set: AX = error code
;
DEFPROC	v86_run
	mov	cx,bx
	mov	dx,-1
	call	pmb_used		; BX -> PMB
	jc	vr9
	mov	ax,ds:[bx].PMB_V86
	test	ax,ax			; is the block a machine's memory?
	jz	vr8			; no
	mov	dx,ax
	shr	dx,4
	shl	ax,12			; DX:AX = its page directory
	push	es
	push	di
	push	dx
	push	ax			; (see v86_resume)
	xchg	cx,ax			; DX:CX = page directory
	call	v86_stk			; ES = its context's selector
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
	jmp	short v86_resume
vr8:	jmp	cpu_inval
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
	push	dx
	push	cx
	db	66h,58h			; POP EAX
	db	0Fh,22h,0D8h		; MOV CR3,EAX
	db	66h
	DTREG	lidt,<ds:[SYS_VARS].SV_V86IDTR>
	mov	ss,bx
	DEFLBL	v86_cont,near
	mov	sp,V86_CTX
vr_ret:	db	66h,61h			; POPAD
	add	sp,VR_EIP - VR_VEC	; (past VR_VEC and VR_ERR)
	db	66h,0CFh		; IRETD (to V86 mode)
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
	jz	vc9			; no
	cld
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
; v86_leave goes back to the kernel's stack, with the system's IDT and the
; kernel's ring 0 stack in the TSS, and every port's bit set again (see
; io_close), and then on to DX, with AX unchanged, DS = SEL_SYS, and ES =
; context.
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
	jmp	dx
vc3:	jmp	v86_refl
vc8:	mov	al,V86X_FAULT
	jmp	v86_out
;
; Only a debugger's trace (after the LIDT in v86_resume) or an NMI (eg,
; while a fault is handled above) can get here from the kernel, before the
; machine runs, so the trace ends (as if it were a G) and the code goes on.
;
vc9:	and	byte ptr [bp+VR_EFL+1],NOT (FL_TRAP SHR 8)
	jmp	vr_ret
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
; the caller's V86REGS (with its own IF, and VR_DSSEL and VR_ESSEL updated),
; and loading the system's page directory again (the machine's can be freed).
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
	mov	ax,word ptr es:[V86_CTX].VR_DS
	mov	bx,es:[V86_CTX].VR_DSSEL
	call	v86_alias
	mov	ax,word ptr es:[V86_CTX].VR_ES
	mov	bx,es:[V86_CTX].VR_ESSEL
	call	v86_alias
	push	ds
	push	es
	pop	ds
	mov	si,V86_CTX
	les	di,dword ptr [bp+4]	; ES:DI -> V86REGS
	mov	cx,(size V86REGS) / 2
	rep	movsw
	pop	ds
	push	ds:[SYS_VARS].SV_PDIR.HW
	push	ds:[SYS_VARS].SV_PDIR.LW
	db	66h,58h			; POP EAX
	db	0Fh,22h,0D8h		; MOV CR3,EAX
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
; debugger gets; see v86_refl), runs the machine again.
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
	jmp	v86_resume
vi9:	mov	al,V86X_TICK
	jmp	v86_exit
ENDPROC	v86_irq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_pf
;
; A page fault in the machine's video memory (see v86_vid) means that its
; selector wasn't present when the machine resumed, so unless it's present
; now, the machine waits until it is, as a program that loads it does (see
; SELID_WAIT), and then runs again, at the same instruction; if the wait ends
; early (eg, for a CTRLC), it exits as after a timer tick, so that DOS can act
; on it.  Any other page fault exits (V86X_FAULT), as one does after its
; selector is freed.
;
; Inputs:
;	DS = SEL_SYS, ES = context
;
DEFPROC	v86_pf
	db	0Fh,20h,0D0h		; MOV EAX,CR2
	db	66h,0C1h,0E8h,12	; SHR EAX,12 (AX = its page)
	mov	cx,word ptr es:[V86_CTX].VC_VPG	; CL = first page, CH = count
;
; Video memory is below 1Mb, so the page's high byte must be zero, and then
; its offset from the first page (which wraps if it's below it) must be less
; than the count (which is zero if there's no video memory).
;
	test	ah,ah
	jnz	pf8
	sub	al,cl
	cmp	al,ch			; in the machine's video memory?
	jae	pf8			; no
	call	v86_vid			; ZF clear if it's there now
	jc	pf8			; (it's gone)
	jnz	pf1			; it is
	mov	dx,SELID_WAIT
	mov	di,es:[V86_CTX].VC_VID	; DX:DI = its wait ID
	mov	ah,DDUTL_WAIT
	call	far ptr DDINT_UTIL
	jc	vi9			; the wait ended early
pf1:	jmp	v86_resume
pf8:	mov	al,V86X_FAULT
	jmp	v86_exit
ENDPROC	v86_pf

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
; segment) are in pages that the machine has, so that touching them can't
; fault.
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
	stc
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
; that memory as its base, since another LDT can have a selector at the same
; index), and returns where a segment is in it, and how many of the bytes
; there are mapped (by v86_init) in the same order: the rest of its memory,
; or of the ROMs.
;
; Inputs:
;	BX = segment
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
	push	bx
	push	di
	push	bp
	mov	di,SYS_PMBS
	mov	bp,ds:[SYS_VARS].SV_NPMBS
vq1:	cmp	ds:[di].PMB_V86,0	; a machine's memory?
	je	vq2			; no
	push	bx
	mov	bx,ds:[di].PMB_SEL
	mov	al,ADDR_SEL
	call	ddcpu_seginfo		; DX:CX = its first selector's base
	pop	bx
	jc	vq2			; (it isn't in the active LDT)
	cmp	cx,ds:[di].PMB_ADDR.LW
	jne	vq2
	cmp	dx,ds:[di].PMB_ADDR.HW
	je	vq3			; it's this machine
vq2:	add	di,size PMB
	dec	bp
	jnz	vq1
vq8:	pop	bp
	pop	di
	pop	bx
	jmp	cpu_inval
vq3:	mov	ax,16
	mul	bx			; DX:AX = linear address
	mov	cx,ds:[di].PMB_LEN.LW
	mov	si,ds:[di].PMB_LEN.HW
	stc
	sbb	cx,ax
	sbb	si,dx			; SI:CX = bytes after it in memory
	jb	vq4			; it's beyond the memory
	add	ax,ds:[di].PMB_ADDR.LW
	adc	dx,ds:[di].PMB_ADDR.HW	; DX:AX = its physical address
	jmp	short vq5
vq4:	cmp	dx,0Ch			; is it in the ROMs?
	jb	vq8			; no (it isn't mapped)
	mov	cx,0FFFFh
	sub	cx,ax
	mov	si,0Fh
	sbb	si,dx			; SI:CX = bytes after it in the ROMs
vq5:	test	si,si			; more than 64K?
	jz	vq6			; no (and carry is clear)
	mov	cx,0FFFFh
vq6:	xchg	ax,cx			; DX:CX = address, AX = limit
	pop	bp
	pop	di
	pop	bx
	ret
ENDPROC	v86_info

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_create
;
; Creates a machine, owned by BX, with SI:DI bytes of memory (rounded up to a
; multiple of 4K, at most 640K), allocated from the top of memory (which is
; likely to be extended memory), so that it doesn't take conventional memory
; that DOS could use, and with a console's video memory, if DX is its
; selector (see v86_vsel).
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
	jc	vcr0
	add	di,PG_SIZE - 1
	adc	si,0
	and	di,NOT (PG_SIZE - 1)	; SI:DI = length, in pages
	mov	ax,di
	or	ax,si			; is it zero?
	jz	vcr8			; yes
	cmp	si,V86_MAXLEN		; more than 640K?
	jb	vcr1			; no
	ja	vcr8			; yes
	test	di,di
	jz	vcr1			; no
vcr8:	jmp	cpu_inval
vcr5:	pop	cx
	pop	cx			; (the video memory's ID and pages)
vcr0:	ret
vcr1:	call	v86_vsel		; DX = video ID, CX = its pages
	jc	vcr0
	push	cx
	push	dx
	push	si
	push	di
	push	bx
	mov	al,MEMF_NONE OR MEMF_HIGH
	call	alloc_64k		; DX:CX = address (see v86_tiles)
	pop	bx			; BX = owner
	pop	di
	pop	si
	jc	vcr5
	push	si
	push	di
	push	dx
	push	cx
	push	ax
	mov	bp,sp			; BP -> selector, address, length,
					; and video memory's ID and pages
	push	bx
	push	bp
	mov	al,MEMF_NONE OR MEMF_HIGH
	sub	si,si
	mov	di,2 * PG_SIZE
	call	alloc_page		; DX:CX = page directory (and table)
	pop	bp			; (alloc_at uses BP)
	pop	bx
	jc	vcr7
	push	dx
	push	cx
	mov	al,MEMF_LDT OR MEMF_USER
	mov	cx,2
	call	desc_alloc		; AX = VR_DSSEL and VR_ESSEL
	jc	vcr6
	push	ax			; [BP-6] = them
	mov	cx,[bp-4]
	mov	dx,[bp-2]
	call	pmb_used		; BX -> page directory's PMB
	pop	ax
	mov	ds:[bx].PMB_SEL,ax
	mov	ds:[bx].PMB_NSEL,2	; (so they're freed with it)
	push	ax
	mov	cx,[bp+2]
	mov	dx,[bp+4]
	call	pmb_used		; BX -> memory's PMB
	push	bx
	mov	si,[bp+8]
	mov	di,[bp+6]		; SI:DI = length
	mov	dx,[bp+4]
	push	bp
	mov	bp,[bp+2]		; DX:BP = address
	call	v86_tiles		; AX = first selector, CX = count
	pop	bp
	pop	bx
	jc	vcr6
	mov	[bp],ax			; (the memory's selector)
	mov	ds:[bx].PMB_SEL,ax
	mov	ds:[bx].PMB_NSEL,cx	; (so they're freed with it)
	mov	ax,[bp-4]
	mov	dx,[bp-2]
	shr	ax,12
	shl	dx,4
	or	ax,dx			; AX = page directory's page #
	mov	ds:[bx].PMB_V86,ax
	call	v86_init
	add	sp,6
	pop	ax			; AX = memory's selector
	add	sp,10			; (its address, length, and video ID)
	pop	dx			; DL = video memory's first page (or 0)
	mov	dh,dl
	mov	dl,0			; DX = its segment (or 0)
	clc
	ret
vcr6:	mov	cx,[bp-4]
	mov	dx,[bp-2]
	call	vcr_free		; free the page directory's block
vcr7:	mov	cx,[bp+2]
	mov	dx,[bp+4]
	call	vcr_free		; and the memory's block
	mov	sp,bp
	add	sp,14
	mov	ax,ERR_NOMEMORY
	stc
	ret
vcr_free:
	call	pmb_used
	jc	vcf9
	call	pmb_free
vcf9:	ret
ENDPROC	v86_create

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_init
;
; Fills in a new machine's page directory, page table, and context: its
; memory, the ROMs (C0000h-FFFFFh, read-only), and the wrap of its first 64K
; at 1Mb, and its video memory's selector ID and pages, if any, which get
; their PTEs as it runs (see v86_vid).
;
; Inputs:
;	SS:BP -> memory's selector, address, and length, and video memory's
;	ID and pages (see v86_create)
;	SS:BP-4 -> page directory's address, and [BP-6] = VR_DSSEL
;	DS = SEL_SYS
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	v86_init
	mov	ax,[bp-4]
	mov	dx,[bp-2]
	mov	bx,SEL_TMP
	call	pm_ptr			; BX = SEL_TMP, AX = 0
	mov	es,bx
	sub	di,di
	mov	cx,PG_SIZE		; (8K, in words)
	cld
	rep	stosw
	mov	ax,[bp-4]
	mov	dx,[bp-2]
	add	ax,PG_SIZE + PG_USER
	adc	dx,0
	mov	es:[0],ax
	mov	es:[2],dx		; PDE 0 -> the page table
	push	ds
	mov	ax,ds:[SYS_VARS].SV_PDIR.LW
	mov	dx,ds:[SYS_VARS].SV_PDIR.HW
	mov	cl,ds:[SYS_VARS].SV_NPT
	mov	ch,0
	shl	cx,1			; CX = words of the system's PDEs
	mov	bx,SEL_TMP2
	call	pm_ptr
	mov	ds,bx
	mov	si,PDE_KERNEL
	mov	di,si
	rep	movsw			; the system's PDEs
	pop	ds
	mov	di,V86_PT
	mov	ax,[bp+2]
	mov	dx,[bp+4]
	or	al,PG_USER		; DX:AX = its memory's first PTE
	mov	cx,[bp+6]
	mov	bx,[bp+8]
	shr	cx,12
	shl	bx,4
	or	cx,bx			; CX = # of its pages
	push	cx
	call	vi_ptes
	mov	di,V86_PT + 0C0h * 4
	mov	ax,PG_ROM
	mov	dx,000Ch		; DX:AX = PTE for C0000h
	mov	cx,40h
	call	vi_ptes
	pop	cx
	cmp	cx,10h			; more than 64K of memory?
	jbe	vi1			; no
	mov	cx,10h
vi1:	shl	cx,1
	mov	si,V86_PT
	mov	di,V86_PT + 100h * 4
	push	ds
	push	es
	pop	ds
	rep	movsw			; the 64K at 1Mb wraps to the first
	pop	ds
	mov	ax,[bp+2]
	mov	word ptr es:[V86_CTX].VC_MEM,ax
	mov	ax,[bp+4]
	mov	word ptr es:[V86_CTX].VC_MEM+2,ax
	mov	ax,[bp+6]
	mov	word ptr es:[V86_CTX].VC_LEN,ax
	mov	ax,[bp+8]
	mov	word ptr es:[V86_CTX].VC_LEN+2,ax
	mov	ax,[bp+10]
	mov	es:[V86_CTX].VC_VID,ax
	mov	ax,[bp+12]
	mov	word ptr es:[V86_CTX].VC_VPG,ax
	mov	di,V86_CTX + VC_IOMAP
	mov	cx,(IOMAP_LEN - 1) / 2
	mov	ax,-1
	rep	stosw			; no ports lent to it yet
	mov	bx,[bp-6]
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
; the host can reach anything smaller than 32K through a single selector.
;
; Inputs:
;	DX:BP = address, SI:DI = length (non-zero)
;
; Outputs:
;	Carry clear: AX = first selector, CX = # of selectors
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
;	AL = 4 or 5, BX = machine (its memory's first selector)
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
	mov	cx,bx
	mov	dx,-1
	call	pmb_used		; BX -> PMB
	pop	si			; SI = # of ports
	pop	di			; DI = first port
	pop	ax
	jc	vp8
	mov	cx,ds:[bx].PMB_V86
	jcxz	vp8			; it isn't a machine's memory
	mov	dx,cx
	shr	dx,4
	shl	cx,12			; DX:CX = its page directory
	push	ax
	call	v86_stk			; ES = its context
	pop	ax
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
	mov	ds:[bx].DESC_LIMIT,2 * PG_SIZE - 1
	mov	ds:[bx+size DESC].DESC_LIMIT,0FFFFh
	mov	ds:[SYS_VARS].SV_V86SEL,ax
	clc
vs9:	ret
ENDPROC	v86_setup

CODE	ends

	end
