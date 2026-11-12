;
; BASIC-DOS Ring 3 Program Support
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; In protected mode, unless a "RING=0" line in CONFIG.SYS keeps them at ring 0
; (see set_fault), every session's first program (eg, COMMAND.COM) and the
; programs that EXEC starts run at ring 3 (see r3_load, r3_start, and
; prog_user), with DPL 3 selectors (see mem_alloc).  This module, like
; dos_fault and the NE loader before it, is resident only in protected mode.
;
; A ring 3 program's ring 0 stack (CPU_SETSTACK) is its parent's stack, just
; below the parent's REG_FRAME (which the parent's PSP_STACK records), since
; the parent is waiting for it there; so every interrupt, DOS call, and fault
; from the program runs on that stack, and the kernel switches it whenever a
; different program becomes current (see r3_sp0).  A session's first program
; (eg, COMMAND.COM), which has no parent, uses the session's own ring 0 stack
; (see r3_top).
;
; A ring 3 program can write its own PSP (and its parent's, which is in the
; same LDT), so the kernel doesn't trust what's there: each program's parent
; and ring 0 stack are in an R3REC, on the ring 0 stack that it can't reach,
; which SCB_SP0 points to, and the kernel rewrites the PSP's fields from it
; when the program ends (see r3_chkterm).  A ring 0 selector that a program
; supplies in memory, rather than in a segment register (which the processor
; checks), gets RPL 3 (see r3_exec), so that the kernel can't be made to use
; it.
;
; A fault in the kernel while it's working for a program ends the program,
; rather than stopping the system (see r3_end), but it can leave a driver's
; state unknown, so before the kernel touches a ring 3 program's stack (see
; r3_chkstk), or returns to an address that the program supplied (see
; r3_chkcode), it makes sure that won't fault, and if it would, the program
; ends as if it had caused the fault itself (see r3_gp).
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc
	include	cpu.inc
;
; The IDT is shared by every session and by ring 0 code (the kernel, drivers,
; and the ROM), so a ring 3 program's interrupt handler can't go in a gate:
; ring 0 code can't call it, another session's LDT doesn't have its selector,
; and its jump to the previous handler (a ring 0 selector) would fault.  So
; when a ring 3 program sets a vector (other than INT 22h-24h, which each
; session has its own of) to its own handler, r3_setvec records the handler in
; an RVEC, whose RV_CALL becomes the gate: entered from ring 3, in the same
; session, r3_reflect passes the interrupt to the handler, at ring 3, on the
; caller's stack; from anywhere else (ring 0, or another session), it goes to
; the gate's previous handler (RV_ORIG), so a hook doesn't see those calls.
; When a ring 3 program gets a vector whose handler isn't its session's,
; r3_getvec returns the address of the RVEC's stub (an INT_DOSEXIT, in
; r3_stubs, through r3_vsel, a readable code selector, since the program gets
; it in ES:BX), which r3_cbret recognizes: jumping (or calling, after a PUSHF)
; to it enters the previous handler as if the interrupt had gone straight to
; it, and setting the vector to it again restores that handler.  A program's
; RVECs are freed when it ends (see r3_endvec).
;
RVEC		struc
RV_CALL		db	3 dup (?)	; CALL r3_reflect (the vector's gate)
RV_VEC		db	?		; vector #
RV_SESS		db	?		; session # of RV_OWNER
RV_OWNER	dw	?		; PSP that set (or got) it (0 if free)
RV_USER		dd	?		; ring 3 handler, or 0 if none yet
RV_ORIG		dd	?		; previous handler
RVEC		ends
;
; The bits of a descriptor's access rights that make it a code segment, which
; are what an IRET requires of a selector that it loads into CS (see ACC_CODE
; in 386dev.asm), and how far below a ring 3 caller's SP r3_sprintf requires
; its stack to reach, to run sprintf (and any interrupts) on it.
;
R3_CODESEG	equ	18h
R3_SPMIN	equ	512

DOS	segment word public 'CODE'

	EXTBYTE	<load_user,scb_locked,err_active,r3_cblock>
	EXTLONG	<err_stack>
	EXTWORD	<dos_data,r3_code,r3_cbsp,r3_stseg,r3_vsel>
	EXTWORD	<scb_active>
	EXTLONG	<r3_cbsp0>
	EXTNEAR	<dos_func,dos_abort,dos_fterm,dos_ctrlc,dos_error,sprintf>
	EXTNEAR	<get_psp,scb_load1>

	.286p

	ASSUME	CS:DOS, DS:DOS, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_setldt
;
; Makes a session's LDT the active one (CPU_SETLDT), when the session becomes
; current or is loaded into (see scb_switch, scb_load, and psp_term), so that
; its programs' selectors (MEMF_LDT) resolve in its LDT, which it may share
; with other sessions (see init_scb); it preserves every register.
;
; Inputs:
;	DS:BX -> SCB
;
DEFPROC	r3_setldt,DOS
	push	ax
	push	cx
	push	dx
	mov	al,[bx].SCB_LDT
	mov	ah,CPU_SETLDT
	call	far ptr DDINT_CPU
	pop	dx
	pop	cx
	pop	ax
	ret
ENDPROC	r3_setldt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_stage
;
; DOS_UTL_LOAD with REG_AL = 1 gives the new session an LDT of its own (see
; init_scb), which is active while its program loads, so the caller's SPB and
; command line (in the caller's LDT) are first copied to a block of the
; kernel's, which the load uses instead (see scb_load).
;
; Inputs:
;	REG_ES:REG_BX -> SPB
;
; Outputs:
;	As for scb_load
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	r3_stage,DOS
	push	[bp].REG_ES
	push	[bp].REG_BX
	mov	es,[bp].REG_ES
	mov	di,[bp].REG_BX		; ES:DI -> SPB
	push	es
	push	di
	les	di,es:[di].SPB_CMDLINE	; ES:DI -> command line
	mov	cx,-1
	mov	al,0
	repne	scasb
	not	cx			; CX = its length (with the null)
	mov	bx,cx
	lea	di,[bx + size SPB]
	sub	si,si			; SI:DI = length of the copy
	mov	bx,MCBOWNER_SYSTEM
	mov	ax,CPU_ALLOC SHL 8	; AL = 0 (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = its selector
	pop	si
	pop	ds			; DS:SI -> SPB
	ASSUME	DS:NOTHING
	jc	rst8
	mov	es,ax
	sub	di,di
	mov	cx,size SPB
	rep	movsb			; copy the SPB
	lds	si,ds:[si - size SPB].SPB_CMDLINE
	mov	es:[SPB_CMDLINE].OFF,di
	mov	es:[SPB_CMDLINE].SEG,es
rst1:	lodsb
	stosb
	test	al,al
	jnz	rst1			; copy the command line
	mov	ds,cs:[dos_data]
	ASSUME	DS:DOS
	mov	[bp].REG_ES,es
	mov	[bp].REG_BX,0		; REG_ES:REG_BX -> the copy
	push	es
	call	scb_load1
	pop	cx			; CX = the copy
	pushf
	mov	dx,-1			; DX = -1 means CX is a segment
	mov	ah,CPU_FREE
	call	far ptr DDINT_CPU	; free it
	popf
	jmp	short rst9
rst8:	mov	ds,cs:[dos_data]
	mov	[bp].REG_AX,ax		; return the error code (carry is set)
rst9:	pop	[bp].REG_BX
	pop	[bp].REG_ES
	ret
ENDPROC	r3_stage

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_chkstk
;
; Checks that the kernel can read and write CX bytes of a ring 3 program's
; memory (eg, its stack, whose SP could be anything, and whose segment may no
; longer exist), or with r3_chkrd, just read them.
;
; Inputs:
;	DX:DI -> first byte, CX = # of bytes (non-zero)
;
; Outputs:
;	Carry clear if so
;
; Modifies:
;	AX, CX
;
DEFPROC	r3_chkstk,DOS
	ASSUME	DS:NOTHING
	verw	dx			; is it still a writable segment?
	jmp	short ck1
	DEFLBL	r3_chkrd,near
	verr	dx			; is it still a readable segment?
ck1:	stc
	jnz	ck9			; no
	lsl	ax,dx			; AX = its limit
	sub	ax,di			; AX = # of bytes after the first
	jb	ck9			; the first is past the limit
	dec	cx
	cmp	ax,cx			; are there too few?
ck9:	ret
ENDPROC	r3_chkstk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_chkcode
;
; Checks that an IRET can enter a ring 3 program at AX:CX, an address that the
; program supplied, or may have freed or shrunk the memory of since.
;
; Inputs:
;	AX:CX = address
;
; Outputs:
;	Carry clear if so
;
; Modifies:
;	DX
;
DEFPROC	r3_chkcode,DOS
	ASSUME	DS:NOTHING
	mov	dl,al
	and	dl,3
	cmp	dl,3			; does it have RPL 3?
	jne	ce8			; no
	lar	dx,ax			; DH = its access rights
	jnz	ce8			; it isn't accessible at ring 3
	and	dh,R3_CODESEG
	cmp	dh,R3_CODESEG		; is it a code segment?
	jne	ce8			; no
	lsl	dx,ax			; DX = its limit
	cmp	dx,cx			; is the offset past the limit?
	ret				; (if so, carry is set)
ce8:	stc
	ret
ENDPROC	r3_chkcode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_gp
;
; Ends the current program as if it had caused a general protection fault,
; when DOS finds that continuing would cause one in the kernel.
;
; Inputs:
;	AX = error code
;	CX:DX = address of the program's instruction
;
; r3_end
;
; Ends the current program for a fault, in its own code, or in the kernel while
; working for it (see dos_fault).  What the kernel was doing is abandoned, so
; we reset what it could have left changed, go back to the top of the program's
; ring 0 stack, which is the only part of it that's still needed (and the fault
; could have happened on another stack, eg, the hard error stack, or an alias
; of the caller's; see r3_sprintf), and report it.  Then dos_abort ends the
; program (see r3_uterm).  SCSTAT_FAULT makes any fault before the program is
; gone fatal, rather than a loop.
;
; If the fault happened in a ring 3 ERROR handler, DOS is in the middle of a
; call that's waiting for its response, so that all stays as it is, and
; r3_uterm ends the handler instead.
;
; Inputs:
;	AX = vector, SI = error code
;	CX:DX = address of the instruction
;
DEFPROC	r3_gp,DOS
	ASSUME	DS:NOTHING
	xchg	si,ax			; SI = error code
	mov	ax,0Dh			; AX = vector
	DEFLBL	r3_end,near
	cli
	mov	ds,cs:[dos_data]
	ASSUME	DS:DOS
	cmp	[r3_cbsp],0		; in a ring 3 ERROR handler?
	jne	re1			; yes
	mov	bx,[scb_active]
	or	[bx].SCB_STATUS,SCSTAT_FAULT
	mov	[bx].SCB_INDOS,0
	mov	[scb_locked],-1
	mov	[err_active],0
	mov	[load_user],0
	mov	di,ss			; DI = the stack we were on
	mov	ss,[r3_stseg]
	mov	sp,[bx].SCB_SP0
	sub	sp,10			; (its IP, CS, FLAGS, SP, and SS)
	push	dx
	push	cx
	push	si
	push	ax
	sti
	cmp	di,[r3_stseg]		; was it an alias of the program's?
	je	re2			; no
	cmp	di,[dos_data]
	je	re2			; no
	mov	bx,di
	sub	cx,cx			; (one selector)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU	; yes, so free the alias
	jmp	short re2
re1:	push	dx
	push	cx
	push	si
	push	ax
	sti
re2:	jmp	dos_fterm		; (the vector, error code, CS, and IP)
ENDPROC	r3_gp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_call5
;
; dos_call5 comes here for a CALL 5 from ring 3, through the SEL_CALL5 call
; gate, which switched to our stack and left the caller's SS and SP after its
; CS and IP; the near CALL's return address is on the caller's stack.  We pop
; it from there and rebuild the frame as an interrupt from ring 3 (IP, CS,
; FLAGS, SP, and SS), so that dos_func's IRET returns to the caller.
;
; Inputs:
;	SS:BP -> the caller's BP, IP, CS, SP, and SS (see dos_call5)
;	CL = DOS function
;
DEFPROC	r3_call5,DOSFAR
	push	ds
	push	cx
	push	dx
	push	di
	mov	dx,[bp+8]
	mov	di,[bp+6]		; DX:DI -> the near return address
	mov	cx,2
	call	r3_chkstk		; can we read it?
	jc	r58			; no
	mov	ds,dx
	mov	cx,[di]			; CX = the near return address
	mov	ax,[bp+4]
	call	r3_chkcode		; can we return there?
	jc	r58			; no
	add	word ptr [bp+6],2	; (popped)
	xchg	ax,cx			; AX = the near return address
	pop	di
	pop	dx
	pop	cx
	pop	ds
	xchg	ax,[bp]			; IP, and AX = the caller's BP
	push	ax
	mov	ax,[bp+4]
	mov	[bp+2],ax		; CS
	pushf				; (interrupts on, as dos_call5 does)
	pop	[bp+4]			; FLAGS
	pop	ax
	xchg	ax,bp			; (SP -> the new frame)
	mov	ah,cl
	jmp	dos_func
r58:	pop	di
	pop	dx
	pop	cx
	pop	ds
	pop	bp
	pop	dx
	pop	cx			; CX:DX = the address of its CALL
	sub	ax,ax
	jmp	r3_gp
ENDPROC	r3_call5

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_error
;
; dev_error calls this, on the hard error stack, to call a session's ERROR
; handler at ring 3: it runs on the stack of the program that called DOS
; (whose SS and SP are at the top of its ring 0 stack), since a ring 3
; handler can't use ours, with BP:SI pointing to a copy of the device's
; header on that stack, since it can't read the driver's memory either.
; While it runs, the program's ring 0 stack is lowered to dev_error's
; caller's stack, so that the handler's own DOS calls (eg, to prompt for a
; response) don't disturb the DOS call in progress.  If the handler can't be
; entered, or its frame doesn't fit on that stack, the response is ABORT.  A
; handler that isn't at ring 3 can only be the default, since the session's
; handler could have come from a PSP_ERROR that a program changed.
;
; The handler returns with an IRET to r3_stub, which issues INT 22h, and
; r3_cbret then returns to dev_error for us, with the response in AL.
;
; Inputs:
;	AH = flags, AL = drive #, DI = error code, BP:SI -> DDH
;	DS:BX -> SCB
;
; Outputs:
;	AL = response (CRERR_*)
;
	ASSUME	CS:DOS, DS:DOS, ES:NOTHING, SS:NOTHING
DEFPROC	r3_error,DOS
	test	byte ptr [bx].SCB_ERROR.SEG,3	; a ring 3 handler?
	jnz	re3			; yes
	pushf
	push	cs
	call	dos_error		; no, so call the default
	ret
re3:	mov	[r3_cbsp],sp		; SP -> our return address
	mov	cl,[scb_locked]
	mov	[r3_cblock],cl		; (see r3_cbabort)
	push	ax
	push	di			; save the handler's AX and DI
	mov	di,[err_stack].OFF
	mov	cx,[di-4]
	mov	dx,[di-2]		; DX:CX = dev_error's caller's stack
	mov	ah,CPU_SETSTACK
	call	far ptr DDINT_CPU	; DX:CX = the program's ring 0 stack
	mov	[r3_cbsp0].OFF,cx
	mov	[r3_cbsp0].SEG,dx
	mov	es,dx
	xchg	di,cx			; ES:DI = the program's ring 0 stack
	mov	ax,[bx].SCB_ERROR.SEG
	mov	cx,[bx].SCB_ERROR.OFF
	call	r3_chkcode		; can we enter the handler?
	jc	re8			; no
	mov	dx,es:[di-2]
	mov	di,es:[di-4]		; DX:DI -> the program's stack
	sub	di,size DDH + 6
	mov	cx,size DDH + 6
	call	r3_chkstk		; does the handler's frame fit?
	jc	re8			; no
	mov	es,dx			; ES:DI -> the handler's frame
	push	es			; the handler's SS
	push	di			; and SP
	pushf
	pop	dx
	push	dx			; and FLAGS
	push	[bx].SCB_ERROR.SEG
	push	[bx].SCB_ERROR.OFF	; and address
	mov	ax,offset r3_stub
	stosw
	mov	ax,[r3_code]
	stosw
	xchg	ax,dx
	stosw				; its return address, and then
	push	ds
	mov	ds,bp
	mov	bp,es
	push	di
	mov	cx,(size DDH) SHR 1
	rep	movsw			; the copy of the DDH
	pop	si			; BP:SI -> the copy
	pop	ds
	mov	di,sp
	mov	ax,[di+12]
	mov	di,[di+10]		; restore AX and DI
	iret				; and call the handler
re8:	mov	al,CRERR_ABORT
	jmp	r3_cbabort
ENDPROC	r3_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_ctrlc
;
; msc_sigctrlc calls this when a session's CTRLC handler is at ring 3, once it
; has filled in the REG_WS frames that would RETF to the handler: since a RETF
; can't go to ring 3 that way, the RETF goes to r3_iret instead, which IRETs to
; the handler, on the stack of the program that called DOS, where we put the
; handler's return address (r3_stub, whose INT 22h takes it back to r3_cbret)
; and the DOS call's.  If it isn't a ring 3 caller's DOS call (whose SS and SP
; we need), or the handler can't be entered (which includes any handler not at
; ring 3, which could have come from a PSP_CTRLC that a program changed), or
; those don't fit on that stack, it gets the default handler instead.
;
; Inputs:
;	SS:BP -> REG_FRAME (REG_WS.JMP_CS:JMP_IP = the CTRLC handler)
;	DS:BX -> SCB
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	r3_ctrlc,DOS
	and	[bx].SCB_STATUS,NOT SCSTAT_FAULT
	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	rt8			; no
	mov	ax,[bp].REG_WS.JMP_CS
	mov	cx,[bp].REG_WS.JMP_IP
	call	r3_chkcode		; can we enter the handler?
	jc	rt8			; no
	mov	dx,[bp + size REG_FRAME + 2]
	mov	di,[bp + size REG_FRAME]
	sub	di,12			; DX:DI -> the caller's stack
	mov	cx,12
	call	r3_chkstk		; do the addresses fit?
	jc	rt8			; no
	mov	es,dx
	mov	[bp + size REG_FRAME],di; ES:DI -> the caller's stack
	mov	ax,offset r3_stub
	stosw
	mov	ax,[r3_code]
	stosw
	mov	ax,[bp].REG_FL
	stosw				; the handler's return address
	lea	si,[bp].REG_IP
	mov	cx,3
	rep	movs word ptr es:[di],word ptr ss:[si]
	mov	ax,[bp].REG_WS.JMP_IP	; and the DOS call's
	mov	[bp].REG_IP,ax
	mov	ax,[bp].REG_WS.JMP_CS
	mov	[bp].REG_CS,ax		; IRET to the handler
	mov	[bp].REG_WS.JMP_IP,offset r3_iret
	mov	[bp].REG_WS.JMP_CS,cs
	ret
rt8:	mov	[bp].REG_WS.JMP_IP,offset dos_ctrlc
	mov	[bp].REG_WS.JMP_CS,cs
	ret
ENDPROC	r3_ctrlc

DEFPROC	r3_iret,DOSFAR
	add	sp,size WS_TEMP - 4	; skip REG_WS's RET_IP, RET_CS, RET_FL
	iret
ENDPROC	r3_iret

;
; A ring 3 handler (see r3_error and r3_ctrlc) returns here, through r3_code
; (a DPL 3, execute-only alias of our code), which takes it back to ring 0.
;
	DEFLBL	r3_stub,near
	int	INT_DOSEXIT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_cbret
;
; dos_exit (INT 22h) comes here, when a ring 3 handler returns through
; r3_stub: if it's the session's ERROR handler (see r3_error), we restore the
; program's ring 0 stack, and return to dev_error, with the handler's
; response in AL.  Otherwise, it's the session's CTRLC handler (see r3_ctrlc),
; and with carry set, the program ends; otherwise, the DOS call restarts, with
; the handler's registers, and its own IP, CS, and FLAGS, from the caller's
; stack (see r3_popret).
;
; INT 22h is a gate that any ring 3 code can use, so if it wasn't issued by
; r3_stub, or a stub for this session's RVEC, the program ends, as if the gate
; were privileged (with the same error code as a fault on that gate).
;
; msc_sigctrlc comes to r3_cbabort when a CTRLC ends the ERROR handler, with
; AL = CRERR_ABORT.
;
DEFPROC	r3_cbret,DOS
	ASSUME	DS:NOTHING
;
; An RVEC's stub (see r3_getvec) also issues INT_DOSEXIT, when a ring 3
; handler chains to the handler it replaced, by jumping to the stub with the
; interrupt's IP, CS, and FLAGS on its stack (or calling it, after a PUSHF):
; we pop them into our frame, and enter that handler (RV_ORIG), as if the
; interrupt had gone straight to it.
;
	sub	sp,4			; (room for the handler's address)
	pusha
	mov	bp,sp			; BP+20 -> IP, CS, FLAGS, SP, SS
	mov	ax,cs:[r3_vsel]
	cmp	[bp+22],ax		; did one of our stubs issue it?
	jne	rc0			; no
	mov	cx,[bp+20]
	dec	cx
	dec	cx			; CX = the stub's offset
	call	r3_vecof		; SI -> its RVEC
	jc	rc7			; (not a stub)
	mov	bx,cs:[scb_active]
	mov	al,cs:[bx].SCB_NUM
	cmp	cs:[si].RV_SESS,al	; is it this session's?
	jne	rc7			; no
	cmp	cs:[si].RV_OWNER,0	; is it in use?
	je	rc7			; no
	mov	ax,cs:[si].RV_ORIG.SEG
	test	ax,ax			; is there a handler to enter?
	jz	rc7			; no
	mov	[bp+18],ax
	mov	ax,cs:[si].RV_ORIG.OFF
	mov	[bp+16],ax		; [BP+16] -> the handler
	call	r3_popret		; pop the interrupt's IP, CS, and FLAGS
	jc	rc7
	popa
	db	OP_RETF			; enter the handler
rc7:	mov	dx,[bp+20]
	mov	cx,[bp+22]		; CX:DX = the address after its INT
	mov	ax,(INT_DOSEXIT SHL 3) OR 2
	jmp	r3_gp
rc0:	cmp	cs:[r3_cbsp],0		; is the ERROR handler running?
	je	rc5			; no
	popa
	mov	ds,cs:[dos_data]
	ASSUME	DS:DOS
	DEFLBL	r3_cbabort,near
	push	ax
	mov	cx,[r3_cbsp0].OFF
	mov	dx,[r3_cbsp0].SEG
	mov	ah,CPU_SETSTACK
	call	far ptr DDINT_CPU	; restore the program's ring 0 stack
	pop	ax
	mov	cl,[r3_cblock]
	mov	[scb_locked],cl		; (the handler could have changed it)
	sub	cx,cx
	xchg	cx,[r3_cbsp]
	cli
	mov	ss,[dos_data]
	mov	sp,cx			; SS:SP -> r3_error's return address
	sti
	ret
	ASSUME	DS:NOTHING
rc5:	mov	ax,cs:[r3_code]
	cmp	[bp+22],ax		; through the handlers' selector?
	jne	rc7			; no
	cmp	word ptr [bp+20],offset r3_stub + 2
	jne	rc7			; it isn't r3_stub's INT
	test	byte ptr [bp+24],FL_CARRY; end the program?
	jz	rc6			; no
	mov	ah,EXTYPE_CTRLC
	jmp	dos_abort
rc6:	call	r3_popret		; pop the DOS call's IP, CS, and FLAGS
	jc	rc7
	popa
	add	sp,4
	jmp	dos_func
ENDPROC	r3_cbret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_popret
;
; Pops an IP, CS, and FLAGS from a ring 3 caller's stack, over the ones at
; BP+20, for r3_cbret: the caller could have put anything there, so the kernel
; mustn't fault reading them, or returning to them, and the CS must have RPL 3
; (and the FLAGS IOPL 0, and interrupts on).
;
; Inputs:
;	SS:BP -> PUSHA frame, room for a far address, IP, CS, FLAGS, SP, and SS
;
; Outputs:
;	Carry clear if successful
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	r3_popret,DOS
	mov	dx,[bp+28]
	mov	di,[bp+26]		; DX:DI -> the caller's stack
	mov	cx,6
	call	r3_chkstk		; can we read them?
	jc	rp9			; no
	push	ds
	mov	ds,dx
	mov	cx,[di]			; CX = IP
	mov	ax,[di+2]
	or	al,3			; AX = CS (ring 3 only)
	mov	dx,[di+4]		; DX = FLAGS
	pop	ds
	push	dx
	call	r3_chkcode		; can we return there?
	pop	dx
	jc	rp9			; no
	mov	[bp+20],cx
	mov	[bp+22],ax
	and	dh,(FL_OVFL+FL_DOWN+FL_INTS+FL_TRAP) SHR 8
	or	dh,FL_INTS SHR 8	; (no IOPL or NT, and interrupts on)
	mov	[bp+24],dx
	add	word ptr [bp+26],6	; (popped)
	clc
rp9:	ret
ENDPROC	r3_popret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_sprintf
;
; With ring 3 programs, set_fault points sprintf_hook here, so that utl_printf
; and friends can format a ring 3 caller's parameters: they're on its own
; stack (at the SS:SP that follows its REG_FRAME), not after its REG_FRAME,
; and there can be any number of them (eg, a PRINTF USING of many values, 3
; words each), so rather than copy them, we run sprintf on the caller's stack
; (as it runs in real mode), through a DPL 0 alias of the caller's SS (since
; SS must be DPL 0 at ring 0), with a copy of the REG_FRAME just below the
; parameters, and BP pointing at the copy.  If there's no descriptor for the
; alias, or the caller's stack doesn't have R3_SPMIN bytes below its SP (a
; stack fault here would stop the system), we copy the REG_FRAME and up to
; R3_PARAMS words of parameters (as many as the caller's stack segment's limit
; allows) below our stack instead.
;
; Inputs and outputs:
;	The same as sprintf's
;
R3_PARAMS	equ	32

DEFPROC	r3_sprintf,DOS
	ASSUME	DS:NOTHING
	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jnz	rs1			; yes
	jmp	sprintf
rs1:	push	bp
	push	ds
	push	es
	push	si
	push	di
	push	cx
	push	ax			; save sprintf's inputs
	push	bx
	mov	bx,[bp + size REG_FRAME + 2]	; BX = the caller's SS
	mov	di,[bp + size REG_FRAME]
	dec	di			; DI = the last byte below its SP
	lsl	ax,bx			; AX = its limit
	jnz	rs1a			; (it's not a valid segment)
	cmp	di,ax			; is SP within the segment?
	ja	rs1a			; no
	cmp	di,R3_SPMIN		; is there room below it?
	jb	rs1a			; no
	mov	ax,CPU_ALIAS SHL 8	; (AL = 0: a DPL 0 data selector)
	call	far ptr DDINT_CPU	; AX = an alias of the caller's SS
	jnc	rs1b
rs1a:	stc
rs1b:	pop	bx
	mov	dx,sp
	mov	cx,ss			; CX:DX -> sprintf's inputs
	jc	rs2			; no alias (copy the parameters)
	mov	di,[bp + size REG_FRAME]	; AX:DI -> its parameters
	mov	ss,ax
	mov	sp,di			; (MOV SS holds interrupts for MOV SP)
	jmp	short rs3
rs2:	sub	sp,R3_PARAMS * 2	; (room to copy the parameters)
rs3:	sub	sp,size REG_FRAME
	mov	di,sp
	push	cx			; save our SS
	push	dx			; and SP (at sprintf's inputs)
	push	ss
	pop	es			; ES:DI -> the copy
	mov	ds,cx
	mov	si,bp			; DS:SI -> REG_FRAME
	mov	bp,di			; BP -> the copy
	mov	ax,cx			; AX = our SS
	mov	cx,(size REG_FRAME) SHR 1
	cld
	rep	movsw			; (DS:SI -> the caller's SP and SS)
	mov	cx,ss
	cmp	cx,ax			; are we on the caller's stack?
	jne	rs5			; yes (the parameters follow the copy)
	lds	si,[si]			; DS:SI -> the caller's parameters
	mov	cx,ds
	lsl	cx,cx			; CX = its stack segment's limit
	sub	cx,si			; CX = bytes after the first, if any
	jb	rs5
	cmp	cx,R3_PARAMS * 2
	jb	rs4
	mov	cx,R3_PARAMS * 2 - 1
rs4:	inc	cx
	shr	cx,1			; CX = # of words to copy
	rep	movsw
rs5:	mov	ds,ax
	mov	si,dx			; DS:SI -> sprintf's inputs
	lodsw				; restore them
	push	ax
	lodsw
	xchg	cx,ax
	lodsw
	xchg	di,ax
	lodsw
	push	ax			; (SI)
	lodsw
	mov	es,ax
	lodsw
	mov	ds,ax
	pop	si
	pop	ax
	call	sprintf			; AX = count, BX -> end of format
	mov	dx,ss			; DX = the stack that sprintf ran on
	pop	si
	pop	cx			; CX:SI -> sprintf's inputs again
	mov	ss,cx
	mov	sp,si			; back on our own stack
	cmp	dx,cx			; was it the caller's stack (an alias)?
	je	rs9			; no
	push	ax
	push	bx
	mov	bx,dx
	sub	cx,cx			; (one selector)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU	; free the alias
	pop	bx
	pop	ax
rs9:	add	sp,12			; discard sprintf's inputs (but BP)
	pop	bp
	ret
ENDPROC	r3_sprintf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_reflect
;
; An RVEC's RV_CALL (a vector's gate; see RVEC) calls this: from ring 3, in
; the RVEC's session, we push the caller's FLAGS, CS, and IP on its own stack,
; as its INT would have, and IRET to the ring 3 handler (RV_USER), with the
; caller's flags (but TF); otherwise, we enter the previous handler (RV_ORIG)
; with the interrupt's frame, as if the gate still went to it, as we also do
; if the program can't take the interrupt (the handler can't be entered, or
; the frame doesn't fit on its stack, where it will fault at ring 3 instead).
; If the vector had no previous handler, the interrupt is the caller's fault.
;
; Inputs:
;	SS:SP -> RVEC+3, then the interrupt's IP, CS, and FLAGS (and SP and SS,
;	from ring 3)
;
DEFPROC	r3_reflect,DOS
	ASSUME	DS:NOTHING
	push	bp
	mov	bp,sp			; BP+4 -> IP, CS, FLAGS, SP, SS
	push	ds
	push	si
	push	ax
	mov	si,[bp+2]
	sub	si,RV_VEC		; SI -> the RVEC (from past RV_CALL)
	test	byte ptr [bp+6],3	; from ring 3?
	jz	rr8			; no
	mov	ds,cs:[dos_data]
	ASSUME	DS:DOS
	push	bx
	mov	bx,[scb_active]
	mov	ah,[bx].SCB_NUM
	pop	bx
	cmp	ah,[si].RV_SESS		; the session whose handler it is?
	jne	rr8			; no
	push	cx
	push	dx
	push	di
	mov	ax,[si].RV_USER.SEG
	mov	cx,[si].RV_USER.OFF
	call	r3_chkcode		; can we enter the handler?
	jc	rr7			; no
	mov	dx,[bp+12]
	mov	di,[bp+10]
	sub	di,6			; DX:DI -> the caller's stack
	mov	cx,6
	call	r3_chkstk		; do the INT's 3 words fit?
	jc	rr7			; no
	push	es
	mov	es,dx
	mov	[bp+10],di		; (its SP, after the INT's 3 words)
	mov	ax,[bp+4]
	mov	es:[di],ax		; IP
	mov	ax,[bp+6]
	mov	es:[di+2],ax		; CS
	mov	ax,[bp+8]
	mov	es:[di+4],ax		; FLAGS
	and	ah,NOT (FL_TRAP SHR 8)	; (interrupts stay on, at ring 3)
	mov	[bp+8],ax
	mov	ax,[si].RV_USER.OFF
	mov	[bp+4],ax
	mov	ax,[si].RV_USER.SEG
	mov	[bp+6],ax		; IRET to the handler
	pop	es
	pop	di
	pop	dx
	pop	cx
	pop	ax
	pop	si
	pop	ds
	pop	bp
	add	sp,2			; (RV_CALL's return address)
	iret
	ASSUME	DS:NOTHING
rr7:	pop	di
	pop	dx
	pop	cx
rr8:	mov	ax,cs:[si].RV_ORIG.SEG
	test	ax,ax			; is there a previous handler?
	jz	rr9			; no
	mov	si,cs:[si].RV_ORIG.OFF
	xchg	si,[bp]			; [BP] -> the previous handler
	mov	[bp+2],ax
	mov	bp,si
	pop	ax
	pop	si
	pop	ds
	db	OP_RETF			; enter it, with the interrupt's frame
rr9:	mov	dx,[bp+4]
	mov	cx,[bp+6]		; CX:DX = the address after its INT
	jmp	r3_gp			; (AX = 0, the error code)
ENDPROC	r3_reflect
;
; The RVECs (see RVEC), whose RV_CALL is code, and their stubs
;
	DEFLBL	r3_vecs,byte
	REPT	R3_RVECS
	call	r3_reflect		; RV_CALL
	db	0,0			; RV_VEC and RV_SESS
	dw	0			; RV_OWNER
	dd	0,0			; RV_USER and RV_ORIG
	ENDM
	ASSERT	<offset r3_vecs + R3_RVECS * size RVEC>,EQ,<offset $>
	DEFLBL	r3_stubs,byte		; (see r3_vsel)
	REPT	R3_RVECS
	int	INT_DOSEXIT
	ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_getvec
;
; msc_getvec comes here, when a ring 3 program gets a vector (see RVEC): if
; it's one of its session's own handlers, we return it; otherwise, we return
; an RVEC's stub, which chains to it.  A vector that it can't hook (see
; r3_hookok), or with no free RVEC, is 0:0, so it can't chain to the handler.
;
; Inputs:
;	AL = vector #
;	DS = DOS
;
; Outputs:
;	DX:CX = vector
;
; Modifies:
;	AX, CX, DX, SI
;
	ASSUME	DS:DOS
DEFPROC	r3_getvec,DOS
	push	bx
	call	r3_hookok		; can it hook this vector?
	jc	rg8			; no
	call	far ptr DDINT_GETVEC	; DX:CX = vector
	test	dx,dx			; none (0:0)?
	jz	rg9			; yes, so that's what it gets
	call	r3_who			; BX = PSP, AH = session #
	mov	si,cs
	cmp	dx,si			; is the gate one of our RVECs?
	jne	rg1			; no
	mov	si,cx
	call	r3_isvec
	jc	rg1			; no
	cmp	ah,[si].RV_SESS		; this session's handler?
	jne	rg1			; no, so chain past it, as ring 0 does
	mov	cx,[si].RV_USER.OFF
	mov	dx,[si].RV_USER.SEG
	jmp	short rg9
rg1:	cmp	[r3_vsel],0		; can we give it a stub?
	je	rg8			; no
	call	r3_newvec		; SI -> a new RVEC for DX:CX
	jc	rg8			; none free
	call	r3_stubof		; CX = its stub's offset
	mov	dx,[r3_vsel]		; DX:CX -> the stub
	jmp	short rg9
rg8:	sub	cx,cx
	sub	dx,dx
rg9:	pop	bx
	ret
ENDPROC	r3_getvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_setvec
;
; msc_setvec comes here, when a ring 3 program sets a vector (see RVEC): to
; one of our stubs (for this vector, and this session), we restore the handler
; that the stub chains to; to 0:0, what r3_getvec returned when there was no
; handler, we remove its handler, if any; and to anything else, we put it in an
; RVEC (the one that r3_getvec gave the program for this vector, if any), with
; RPL 3, and make that RVEC the gate, so that a gate never holds a program's
; address.  A vector that it can't hook (see r3_hookok), or a stub that isn't
; for this vector, is ERR_ACCDENIED, and no free RVEC is ERR_NOMEMORY.
;
; Inputs:
;	AL = vector #
;	DX:CX = new vector
;	DS = DOS
;
; Outputs:
;	Carry clear if successful; carry set if not, REG_AX = error code
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	r3_setvec,DOS
	call	r3_hookok		; can it hook this vector?
	jnc	sv1			; yes
sv8:	mov	ax,ERR_ACCDENIED
sv9:	mov	[bp].REG_AX,ax
	stc
	ret
sv7:	pop	bx
	jmp	sv8
sv1:	push	bx
	call	r3_who			; BX = PSP, AH = session #
	cmp	dx,[r3_vsel]		; one of our stubs?
	jne	sv2			; no
	call	r3_vecof		; SI -> its RVEC
	jc	sv7			; (not a stub)
	cmp	[si].RV_OWNER,0		; is it in use?
	je	sv7			; no
	cmp	[si].RV_SESS,ah		; by this session?
	jne	sv7			; no
	cmp	[si].RV_VEC,al		; for this vector?
	jne	sv7			; no
	mov	cx,[si].RV_ORIG.OFF
	mov	dx,[si].RV_ORIG.SEG
	call	far ptr DDINT_SETVEC	; restore the handler it chains to
	call	r3_freevec		; and free the RVEC
	jmp	short sv6a
sv2:	mov	si,offset r3_vecs
	test	dx,dx			; removing its handler?
	jz	sv4a			; yes
	or	dl,3			; (always a ring 3 handler)
	push	cx
	mov	cx,R3_RVECS
sv3:	cmp	[si].RV_OWNER,bx	; one of this program's
	jne	sv4
	cmp	[si].RV_SESS,ah
	jne	sv4
	cmp	[si].RV_VEC,al		; for this vector
	jne	sv4
	cmp	[si].RV_USER.SEG,0	; that has no handler yet?
	je	sv5			; yes, so use it
sv4:	add	si,size RVEC
	loop	sv3
	pop	cx
	push	dx
	push	cx
	call	far ptr DDINT_GETVEC	; DX:CX = the gate's handler now
	call	r3_newvec		; SI -> a new RVEC for DX:CX
	pop	cx
	pop	dx
	jnc	sv6
	pop	bx
	mov	ax,ERR_NOMEMORY		; (none free)
	jmp	sv9
sv5:	pop	cx
sv6:	mov	[si].RV_USER.OFF,cx
	mov	[si].RV_USER.SEG,dx
	mov	cx,si
	mov	dx,cs			; DX:CX -> its RV_CALL
	call	far ptr DDINT_SETVEC
sv6a:	pop	bx
	clc
	ret
;
; Remove the handlers it has for this vector, if any.
;
sv4a:	mov	cx,R3_RVECS
sv4b:	cmp	[si].RV_OWNER,bx	; one of this program's
	jne	sv4c
	cmp	[si].RV_SESS,ah
	jne	sv4c
	cmp	[si].RV_VEC,al		; for this vector?
	jne	sv4c
	call	r3_freevec		; yes
sv4c:	add	si,size RVEC
	loop	sv4b
	jmp	sv6a
ENDPROC	r3_setvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_hookok
;
; Returns whether a ring 3 program can hook a vector.  The list is short,
; because a hook can't work for anything that ring 0 code issues (eg, the
; BIOS's INT 1Ch; see RVEC), and a hook of an IRQ that didn't chain to the
; previous handler would stop that interrupt for every session: so it's the
; exceptions that a program can handle, DOS, and the vectors that are free for
; programs to use.
;
; Inputs:
;	AL = vector #
;
; Outputs:
;	Carry clear if so
;
; Modifies:
;	None
;
DEFPROC	r3_hookok,DOS
	ASSUME	DS:NOTHING
	cmp	al,INT_OF		; INT_DV through INT_OF?
	ja	hk1			; no
	cmp	al,INT_NMI		; other than NMI?
	je	hk8			; no
	clc
	ret
hk1:	cmp	al,INT_DOSFUNC		; DOS?
	je	hk9			; yes (and carry is clear)
	cmp	al,R3_USERINT		; below the user vectors?
	jb	hk9			; yes (and carry is set)
	cmp	al,R3_USERMAX		; above them?
	jbe	hk7			; no
hk8:	stc
	ret
hk7:	clc
hk9:	ret
ENDPROC	r3_hookok
	ASSUME	DS:DOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_freevec
;
; Frees the RVEC at SI: if it's its vector's gate, the gate goes back to the
; RVEC's previous handler, and so does any other RVEC whose previous handler
; it was.
;
; Inputs:
;	SI -> RVEC
;	DS = DOS
;
; Modifies:
;	None
;
DEFPROC	r3_freevec,DOS
	push	ax
	push	bx
	push	cx
	push	dx
	mov	al,[si].RV_VEC
	call	far ptr DDINT_GETVEC	; DX:CX = the gate's handler
	mov	bx,cs
	cmp	dx,bx			; is it this RVEC?
	jne	fv1
	cmp	cx,si
	jne	fv1			; no
	mov	cx,[si].RV_ORIG.OFF
	mov	dx,[si].RV_ORIG.SEG
	call	far ptr DDINT_SETVEC	; yes, so restore its previous handler
fv1:	mov	bx,offset r3_vecs
	mov	cx,R3_RVECS
fv2:	cmp	[bx].RV_ORIG.OFF,si	; does another RVEC chain to this one?
	jne	fv3
	mov	ax,cs
	cmp	[bx].RV_ORIG.SEG,ax
	jne	fv3			; no
	mov	ax,[si].RV_ORIG.OFF
	mov	[bx].RV_ORIG.OFF,ax
	mov	ax,[si].RV_ORIG.SEG
	mov	[bx].RV_ORIG.SEG,ax	; yes, so it chains past it now
fv3:	add	bx,size RVEC
	loop	fv2
	mov	[si].RV_OWNER,0		; free
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	r3_freevec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_endvec
;
; psp_term calls this, when programs run at ring 3, to free the RVECs of the
; program that's ending (see RVEC), so that no gate is left with a handler in
; its freed memory.
;
; Inputs:
;	DS = DOS
;
; Modifies:
;	None
;
DEFPROC	r3_endvec,DOS
	push	ax
	push	bx
	push	cx
	push	si
	call	r3_who			; BX = PSP, AH = session #
	mov	si,offset r3_vecs
	mov	cx,R3_RVECS
ev1:	cmp	[si].RV_OWNER,bx	; one of this program's?
	jne	ev2
	cmp	[si].RV_SESS,ah
	jne	ev2			; no
	call	r3_freevec
ev2:	add	si,size RVEC
	loop	ev1
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	r3_endvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_newvec
;
; Inputs:
;	AL = vector #
;	DX:CX = its handler now (the new RVEC's RV_ORIG)
;	DS = DOS
;
; Outputs:
;	Carry clear if successful: SI -> a new RVEC, for the current program
;	Carry set if there's no free RVEC
;
; Modifies:
;	SI
;
DEFPROC	r3_newvec,DOS
	push	cx
	mov	si,offset r3_vecs
	mov	cx,R3_RVECS
nv1:	cmp	[si].RV_OWNER,0		; free?
	je	nv2			; yes
	add	si,size RVEC
	loop	nv1
	pop	cx
	stc
	ret
nv2:	pop	cx
	mov	[si].RV_VEC,al
	mov	[si].RV_ORIG.OFF,cx
	mov	[si].RV_ORIG.SEG,dx
	mov	[si].RV_USER.SEG,0	; (no handler yet)
	push	ax
	push	bx
	call	r3_who			; BX = PSP, AH = session #
	mov	[si].RV_SESS,ah
	mov	[si].RV_OWNER,bx
	pop	bx
	pop	ax
	clc
	ret
ENDPROC	r3_newvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_who
;
; Outputs:
;	BX = current PSP, AH = current session #
;
; Modifies:
;	AH, BX
;
DEFPROC	r3_who,DOS
	push	ax
	call	get_psp			; AX = PSP
	xchg	bx,ax
	pop	ax
	push	bx
	mov	bx,cs:[scb_active]
	mov	ah,cs:[bx].SCB_NUM
	pop	bx
	ret
ENDPROC	r3_who

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_stubof and r3_vecof
;
; Convert between an RVEC (SI) and its stub's offset in r3_stubs (CX).
;
; Outputs:
;	CX = stub offset (r3_stubof)
;	Carry clear if CX was a stub's offset: SI -> its RVEC (r3_vecof)
;
; Modifies:
;	CX (r3_stubof) or SI (r3_vecof)
;
DEFPROC	r3_stubof,DOS
	push	ax
	mov	ax,offset r3_vecs
	sub	cx,cx
so1:	cmp	ax,si			; is this the RVEC?
	je	so9			; yes
	add	ax,size RVEC
	inc	cx
	inc	cx
	jmp	so1
so9:	pop	ax
	ret
ENDPROC	r3_stubof

DEFPROC	r3_vecof,DOS
	push	cx
	test	cl,1			; a stub's offset is even
	jnz	vo8
	shr	cx,1			; CX = the RVEC's index
	cmp	cx,R3_RVECS
	jae	vo8
	mov	si,offset r3_vecs
	clc
	jcxz	vo9			; (index 0)
vo1:	add	si,size RVEC
	loop	vo1
	clc
	jmp	short vo9
vo8:	stc
vo9:	pop	cx
	ret
ENDPROC	r3_vecof

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_isvec
;
; Outputs:
;	Carry clear if SI -> one of the RVECs
;
; Modifies:
;	None
;
DEFPROC	r3_isvec,DOS
	push	ax
	push	cx
	mov	ax,offset r3_vecs
	mov	cx,R3_RVECS
iv1:	cmp	ax,si			; this RVEC? (if so, carry is clear)
	je	iv9			; yes
	add	ax,size RVEC
	loop	iv1
	stc
iv9:	pop	cx
	pop	ax
	ret
ENDPROC	r3_isvec

DOS	ends

	end
