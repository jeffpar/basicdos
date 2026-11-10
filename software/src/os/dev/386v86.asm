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
; free, so the machine's context (V86CTX) is there, too.
;
; While the machine runs, its context's V86REGS is the TSS's ring 0 stack
; (through SEL_V86STK, the first of SV_V86SEL's selectors), so every
; interrupt from the machine stores its registers there, and the machine's
; IDT (see v86_setup), whose gates are 80386 interrupt gates (as an interrupt
; from V86 mode needs), sends each one to a stub (see v86_stubs), which loads
; the system's IDT, and goes back to the kernel's stack, where it ends the
; call (v86_exit), runs the system's handler for a hardware interrupt, or
; for a general protection fault, does what the instruction would have done
; in real mode (v86_gp); then it runs the machine again (v86_resume), with
; its own IDT, and its own page directory.  The machine's IOPL is 0, so CLI,
; STI, PUSHF, POPF, INT, and IRET all fault, and so do I/O instructions,
; since the TSS has no I/O permission bitmap.
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
	EXTNEAR	<sel_desc,pm_ptr,cpu_inval>

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
;	AL = 0 to create a machine (see v86_create), or 1 to run one (see
;	v86_run)
;
DEFPROC	v86_func
	cmp	al,1
	je	v86_run
	jb	vf1
	jmp	cpu_inval
vf1:	jmp	v86_create
ENDPROC	v86_func

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
; sessions), so it's set again.
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
	lidt	qword ptr ds:[SYS_VARS].SV_V86IDTR
	mov	ss,bx
	mov	sp,V86_CTX
	db	66h,61h			; POPAD
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
; upper half of VR_ERR goes, so it's moved to VR_VEC.
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
	db	66h
	lidt	qword ptr ds:[SYS_VARS].SV_PIDTR
	mov	cx,ss:[V86_CTX].VC_SP0
	mov	ds:[TSS_ESP0],cx
	mov	cx,ss:[V86_CTX].VC_SS0
	mov	ds:[TSS_SS0],cx
	mov	bx,ss
	mov	es,bx			; ES = context
	mov	cx,es:[V86_CTX].VC_KSP
	mov	ss,es:[V86_CTX].VC_KSS
	mov	sp,cx
	cmp	al,IRQ_SLAVE		; a hardware interrupt?
	jae	v86_irq			; yes
	cmp	al,INT_NMI		; or an NMI?
	je	v86_irq			; yes
	cmp	al,INT_GP		; a general protection fault?
	je	v86_gp			; yes
;
; The exceptions that real mode delivers through the vectors (the same ones
; that it returns from at the same address) go to the machine's own.
;
	mov	si,word ptr es:[V86_CTX].VR_EIP
	cmp	al,INT_DB
	jbe	vc2			; 00h and 01h
	cmp	al,INT_BR
	jb	vc8			; (INT 03h and 04h fault as 0Dh)
	cmp	al,INT_NM
	ja	vc8
vc2:	jmp	v86_refl		; 05h-07h
vc8:	mov	al,V86X_FAULT
	jmp	v86_exit
ENDPROC	v86_noerr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_irq
;
; Runs the system's handler for a hardware interrupt (or an NMI) from the
; machine, as if it had interrupted us, and then runs the machine again, or
; after a timer tick, exits.
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
	push	offset DEV:vi9
	push	ds:[SYS_PIDT+bx].DESC_BASE	; the handler's selector
	push	ds:[SYS_PIDT+bx].DESC_LIMIT	; and offset
	db	OP_RETF			; "return" to it
vi9:	pop	ax
	cmp	al,IRQ_MASTER		; a timer tick (IRQ 0)?
	je	vi10			; yes
	jmp	v86_resume
vi10:	mov	al,V86X_TICK
	jmp	v86_exit
ENDPROC	v86_irq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_gp
;
; A general protection fault in the machine: CLI, STI, PUSHF, POPF, INT,
; INT3, INTO, and IRET (with an operand-size prefix, too) do what they would
; in real mode, using the machine's IF; anything else (eg, I/O or HLT) exits.
;
; Inputs:
;	DS = SEL_SYS, ES = context
;
DEFPROC	v86_gp
	mov	ax,word ptr es:[V86_CTX].VR_CS
	mov	si,word ptr es:[V86_CTX].VR_EIP
	mov	cx,2			; (no more than 3 bytes)
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
	jne	vg8
	test	byte ptr es:[V86_CTX].VR_EFL+1,FL_OVFL SHR 8
	jz	vg9			; no overflow, so there's no INT 04h
	mov	ah,INT_OF
vg7:	mov	al,ah
	jmp	v86_refl
vg2:	mov	es:[V86_CTX].VC_VIF,0
	jmp	short vg9
vg3:	mov	es:[V86_CTX].VC_VIF,FL_INTS SHR 8
	jmp	short vg9
vg4:	call	v86_flags		; AX = the machine's FLAGS
	call	v86_pushv
	jc	vg8
	jmp	short vg9
vg5:	call	v86_popv		; AX = new FLAGS
	jc	vg8
	call	v86_setfl
	jmp	short vg9
vg6:	call	v86_popv		; AX = IP
	jc	vg8
	xchg	si,ax			; SI = IP
	call	v86_popv		; AX = CS
	jc	vg8
	mov	word ptr es:[V86_CTX].VR_CS,ax
	call	v86_popv		; AX = FLAGS
	jc	vg8
	call	v86_setfl
vg9:	mov	word ptr es:[V86_CTX].VR_EIP,si
	mov	word ptr es:[V86_CTX].VR_EIP+2,0
	jmp	v86_resume
vg8:	mov	al,V86X_FAULT
	jmp	v86_exit
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
	sub	dx,dx			; DL = 0 (16-bit pushes)
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
	jmp	short v86_exit
rf2:	call	v86_flags		; AX = the machine's FLAGS
	call	v86_pushv
	jc	rf8
	mov	ax,word ptr es:[V86_CTX].VR_CS
	call	v86_pushv
	pop	ax			; AX = IP to return to
	jc	rf7
	call	v86_pushv
	jc	rf7
	pop	ax
	mov	es:[V86_CTX].VC_VIF,0
	and	byte ptr es:[V86_CTX].VR_EFL+1,NOT (FL_TRAP SHR 8)
	mov	word ptr es:[V86_CTX].VR_EIP,cx
	mov	word ptr es:[V86_CTX].VR_EIP+2,0
	mov	word ptr es:[V86_CTX].VR_CS,di
	jmp	v86_resume
rf8:	pop	ax
rf7:	pop	ax
	mov	al,V86X_FAULT
ENDPROC	v86_refl			; fall into v86_exit

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
	cmp	al,V86X_TICK
	jne	vx1
	mov	es:[V86_CTX].VR_VEC,INT_HW_TMR
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
	push	ds:[SYS_VARS].SV_PDIR.HIW
	push	ds:[SYS_VARS].SV_PDIR.LOW
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
; machine's stack, or pop one (ignoring the upper half).
;
; Inputs:
;	AX = word (v86_pushv), DL = 0 (or OP_OPSIZE)
;	DS = SEL_SYS, ES = context
;
; Outputs:
;	AX = word (v86_popv); carry set if the stack isn't there
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
	jnc	v86_pushw
	ret
ENDPROC	v86_pushv

DEFPROC	v86_popv
	call	v86_popw
	jc	pv9
	test	dl,dl			; a dword?
	jz	pv9			; no
	push	ax
	call	v86_popw		; (its upper half)
	pop	ax
pv9:	ret
ENDPROC	v86_popv

DEFPROC	v86_pushw
	push	si
	mov	si,word ptr es:[V86_CTX].VR_ESP
	dec	si
	dec	si
	call	v86_stkchk		; GS:SI -> the new top
	jc	pw9
	db	65h			; (GS:)
	mov	[si],ax
	mov	word ptr es:[V86_CTX].VR_ESP,si
pw9:	pop	si
	ret
ENDPROC	v86_pushw

DEFPROC	v86_popw
	push	si
	mov	si,word ptr es:[V86_CTX].VR_ESP
	call	v86_stkchk		; GS:SI -> the top
	jc	po9
	db	65h			; (GS:)
	lodsw
	mov	word ptr es:[V86_CTX].VR_ESP,si
po9:	pop	si
	ret
ENDPROC	v86_popw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_stkchk
;
; Checks that the word at the machine's SS:SI is there (and not split by the
; end of the segment), and points GS at SS.
;
; Inputs:
;	SI = offset
;	DS = SEL_SYS, ES = context
;
; Outputs:
;	Carry clear if successful (GS = the machine's SS)
;
DEFPROC	v86_stkchk
	cmp	si,0FFFFh		; split by the end of the segment?
	stc
	je	sc9			; yes
	push	ax
	push	cx
	mov	ax,word ptr es:[V86_CTX].VR_SS
	mov	cx,1
	call	v86_chk
	jc	sc8
	call	v86_seg
sc8:	pop	cx
	pop	ax
sc9:	ret
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
; v86_create
;
; Creates a machine, owned by BX, with SI:DI bytes of memory (rounded up to a
; multiple of 4K, at most 640K), allocated from the top of memory (which is
; likely to be extended memory), so that it doesn't take conventional memory
; that DOS could use.
;
; Inputs:
;	BX = owner, SI:DI = length
;
; Outputs:
;	Carry clear: AX = first selector of its memory, DX:CX = address
;	Carry set: AX = error code
;
DEFPROC	v86_create
	push	bx
	call	v86_setup		; the machines' IDT and selectors
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
vcr0:	ret
vcr1:	push	si
	push	di
	push	bx
	mov	al,MEMF_LDT OR MEMF_USER OR MEMF_HIGH
	call	alloc_page		; AX = selector, DX:CX = address
	pop	bx			; BX = owner
	pop	di
	pop	si
	jc	vcr0
	push	si
	push	di
	push	dx
	push	cx
	push	ax
	mov	bp,sp			; BP -> selector, address, and length
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
	mov	ax,[bp-4]
	mov	dx,[bp-2]
	shr	ax,12
	shl	dx,4
	or	ax,dx			; AX = page directory's page #
	mov	ds:[bx].PMB_V86,ax
	call	v86_init
	add	sp,6
	pop	ax			; AX = memory's selector
	pop	cx
	pop	dx			; DX:CX = its address
	add	sp,4
	clc
	ret
vcr6:	mov	cx,[bp-4]
	mov	dx,[bp-2]
	call	vcr_free		; free the page directory's block
vcr7:	mov	cx,[bp+2]
	mov	dx,[bp+4]
	call	vcr_free		; and the memory's block
	mov	sp,bp
	add	sp,10
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
; at 1Mb; nothing else (eg, video memory) is mapped.
;
; Inputs:
;	SS:BP -> memory's selector, address, and length (see v86_create)
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
	mov	ax,ds:[SYS_VARS].SV_PDIR.LOW
	mov	dx,ds:[SYS_VARS].SV_PDIR.HIW
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
; alloc_page
;
; Allocates a block that starts on a page (as CPU_ALLOC would allocate one
; that's PG_SIZE - 16 bytes longer, and then the page in it), since the
; processor maps memory a page at a time.
;
; Inputs:
;	AL = MEMF_* flags, BX = owner, SI:DI = length (a multiple of PG_SIZE)
;
; Outputs:
;	As for CPU_ALLOC
;
DEFPROC	alloc_page
	mov	ds:[SYS_VARS].SV_ARG,al
	mov	ds:[SYS_VARS].SV_OWNER,bx
	push	si
	push	di
	add	di,PG_SIZE - 16
	adc	si,0
	mov	ds:[SYS_VARS].SV_LEN.LOW,di
	mov	ds:[SYS_VARS].SV_LEN.HIW,si
	call	pmb_fit			; BX -> free PMB, DX:CX = address
	pop	di
	pop	si
	jc	ap8
	mov	ds:[SYS_VARS].SV_LEN.LOW,di
	mov	ds:[SYS_VARS].SV_LEN.HIW,si
	add	cx,PG_SIZE - 1
	adc	dx,0
	and	cx,NOT (PG_SIZE - 1)	; DX:CX = the page
	jmp	alloc_at
ap8:	mov	ax,ERR_NOMEMORY
	ret
ENDPROC	alloc_page

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
