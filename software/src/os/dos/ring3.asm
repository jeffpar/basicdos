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

DOS	segment word public 'CODE'

	EXTBYTE	<load_user>
	EXTWORD	<dos_data,err_stack,r3_code,r3_cbsp,r3_stseg,r3_vsel>
	EXTWORD	<scb_active>
	EXTBYTE	<cmdline_buf>
	EXTLONG	<r3_cbsp0>
	EXTNEAR	<dos_func,dos_leave,dos_abort,sprintf,get_psp>

	.286p

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_start
;
; psp_exec comes here, when programs run at ring 3, to start a program that
; it loaded (or that EXEC1 loaded, for EXEC2): a program loaded for ring 3
; (see load_user) has a CS with RPL 3 (see mem_alias), and starts at ring 3;
; any other (eg, one that a debugger loaded with EXEC1) starts as psp_exec
; would start it.  Either way, the load is done, so load_user is cleared.
;
; A ring 3 program's REG_FRAME, which load_program built on the program's own
; stack, is copied to our stack, just below the parent's REG_FRAME, followed
; by the program's SS and SP (which an IRET to ring 3 pops), with RPL 3 in
; its SS too (its DS and ES, the PSP's selector, are the same as at ring 0, eg,
; for msc_setvec).  The end of the copy is also the program's ring 0 stack
; (see r3_sp0).
;
; Inputs:
;	DX:AX -> the REG_CHECK marker (if any) and REG_FRAME
;	SS:BP -> the parent's REG_FRAME
;
; Outputs:
;	None (we leave through dos_leave)
;
	ASSUME	CS:DOS, DS:DOS, ES:NOTHING, SS:NOTHING
DEFPROC	r3_start,DOS
	mov	ds,cs:[dos_data]
	mov	[load_user],0
	mov	es,dx
	xchg	si,ax			; DX:SI -> REG_FRAME
	test	byte ptr es:[si+REG_CHECK].REG_CS,3	; a ring 3 program?
	jnz	rx1			; yes
	cli
	mov	ss,dx			; no, so switch to its stack
	mov	sp,si
	jmp	dos_leave
rx1:	lea	di,[bp-(2*REG_CHECK + size REG_FRAME + 4)]
	mov	sp,di			; (psp_exec won't return)
	push	ss
	pop	es			; ES:DI -> the copy
	call	r3_frame
	mov	di,sp
	lea	cx,[di+REG_CHECK+size REG_FRAME+4]
	mov	dx,ss			; DX:CX = its ring 0 stack
	mov	ah,CPU_SETSTACK
	call	far ptr DDINT_CPU
	jmp	dos_leave
ENDPROC	r3_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_load
;
; scb_load calls this, when programs run at ring 3, once it has loaded a
; session's first program: if it was loaded for ring 3 (as r3_start checks),
; its REG_FRAME, followed by its SS and SP, is copied to the top of the
; session's ring 0 stack (see r3_top), where the session will start it.
;
; Inputs:
;	DX:AX -> the REG_CHECK marker (if any) and REG_FRAME
;	DS:BX -> SCB
;
; Outputs:
;	DX:AX -> the session's initial stack
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	r3_load,DOS
	mov	es,dx
	xchg	si,ax			; DX:SI -> REG_FRAME
	test	byte ptr es:[si+REG_CHECK].REG_CS,3	; a ring 3 program?
	jz	rl9			; no
	push	dx
	call	r3_top			; DX:CX = the session's ring 0 stack
	mov	es,dx
	mov	di,cx
	sub	di,REG_CHECK + size REG_FRAME + 4
	pop	dx
	push	di
	call	r3_frame
	pop	si
	mov	dx,es			; DX:SI -> the copy
rl9:	xchg	ax,si
	ret
ENDPROC	r3_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_frame
;
; Copies a program's REG_FRAME (and REG_CHECK marker, if any) from its own
; stack to a ring 0 stack, followed by the program's SP and SS (with RPL 3),
; which an IRET to ring 3 pops.
;
; Inputs:
;	DX:SI -> the REG_CHECK marker (if any) and REG_FRAME
;	ES:DI -> the copy
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	r3_frame,DOS
	push	ds
	mov	ds,dx			; DS:SI -> REG_FRAME
	mov	cx,(REG_CHECK + size REG_FRAME) SHR 1
	cld
	rep	movsw			; DS:SI -> the program's stack
	xchg	ax,si
	stosw				; its SP
	xchg	ax,dx
	or	al,3
	stosw				; and SS (with RPL 3)
	pop	ds
	ret
ENDPROC	r3_frame

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_top
;
; Returns the top of a session's ring 0 stack, in the block of them that
; sysinit allocates (see init_sess).
;
; Inputs:
;	DS:BX -> SCB
;
; Outputs:
;	DX:CX = the top of the session's ring 0 stack
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	r3_top,DOS
	mov	al,[bx].SCB_NUM
	inc	ax
	mov	ah,R3_STACK_SIZE SHR 8
	mul	ah
	mov	ch,al
	mov	cl,0			; CX = (SCB_NUM + 1) * R3_STACK_SIZE
	mov	dx,[r3_stseg]
	ret
ENDPROC	r3_top

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_sp0
;
; Sets the ring 0 stack (CPU_SETSTACK) for the program whose PSP is in AX,
; when it becomes current (eg, when a session switch resumes it, or when the
; program it started ends): everything below its parent's PSP_STACK belongs
; to it, or for a program without a parent (a session's first program), the
; session's own ring 0 stack (see r3_top).
;
; Inputs:
;	AX = PSP (or zero)
;	DS:BX -> SCB
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	r3_sp0,DOS
	test	ax,ax
	jz	sp9
	push	es
	mov	es,ax
	mov	ax,es:[PSP_PARENT]
	test	ax,ax			; does it have a parent?
	jz	sp7			; no
	mov	es,ax
	mov	cx,es:[PSP_STACK].OFF
	mov	dx,es:[PSP_STACK].SEG	; DX:CX = the parent's PSP_STACK
	jmp	short sp8
sp7:	call	r3_top			; DX:CX = the session's ring 0 stack
sp8:	mov	ah,CPU_SETSTACK
	call	far ptr DDINT_CPU
	pop	es
sp9:	ret
ENDPROC	r3_sp0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_setldt
;
; Makes the LDT of the session in AL the active one (CPU_SETLDT), when a
; session becomes current or is loaded into (see scb_switch, scb_load, and
; sysinit_tail), so that its programs' selectors (MEMF_LDT) resolve in its own
; LDT; it preserves every register.
;
; Inputs:
;	AL = session #
;
DEFPROC	r3_setldt,DOS
	push	ax
	push	cx
	push	dx
	mov	ah,CPU_SETLDT
	call	far ptr DDINT_CPU
	pop	dx
	pop	cx
	pop	ax
	ret
ENDPROC	r3_setldt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; stage_cmdline
;
; Copies the null-terminated command line at DS:SI to cmdline_buf (in our data
; segment) and returns DS:SI pointing at the copy, so that scb_load can keep
; reading it after it switches to the loaded session's LDT, where the caller's
; command line (an LDT selector) is no longer addressable.
;
; For the same reason, we leave ES (like DS) pointing at our data segment --
; a GDT selector that stays addressable in any LDT -- rather than restoring
; the caller's ES, which the LDT switch makes unaddressable.  Otherwise a
; nested DOS call after the switch (eg, load_command's STRLEN) would fault
; restoring the caller's ES on its way out (see dos_leave2).
;
; Inputs:
;	DS:SI -> command line (in the caller's memory)
;
; Outputs:
;	DS:SI -> cmdline_buf, ES -> our data segment
;
; Modifies:
;	AX, CX, SI, DI, DS, ES
;
DEFPROC	stage_cmdline,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	mov	ax,cs:[dos_data]
	mov	es,ax
	mov	di,offset cmdline_buf
	mov	cx,CMDLINE_MAX - 1
	cld
sg0:	lodsb
	stosb
	test	al,al			; end of the command line?
	jz	sg1			; yes
	loop	sg0
	mov	byte ptr es:[di],0	; or truncate it (null-terminated)
sg1:	push	es
	pop	ds
	mov	si,offset cmdline_buf	; DS:SI -> the copy (ES stays our data)
	ret
ENDPROC	stage_cmdline

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
	push	si
	lds	si,dword ptr [bp+6]	; DS:SI -> the near return address
	lodsw
	mov	[bp+6],si		; (popped)
	pop	si
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
; response) don't disturb the DOS call in progress.
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
	mov	[r3_cbsp],sp		; SP -> our return address
	push	ax
	push	di			; save the handler's AX and DI
	mov	di,[err_stack]
	mov	cx,[di-4]
	mov	dx,[di-2]		; DX:CX = dev_error's caller's stack
	mov	ah,CPU_SETSTACK
	call	far ptr DDINT_CPU	; DX:CX = the program's ring 0 stack
	mov	[r3_cbsp0].OFF,cx
	mov	[r3_cbsp0].SEG,dx
	mov	es,dx
	xchg	di,cx
	les	di,es:[di-4]		; ES:DI -> the program's stack
	sub	di,size DDH + 6
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
ENDPROC	r3_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_ctrlc
;
; msc_sigctrlc calls this when a session's CTRLC handler is at ring 3, once
; it has filled in the REG_WS frames that would RETF to the handler: since a
; RETF can't go to ring 3 that way, the RETF goes to r3_iret instead, which
; IRETs to the handler, on the stack of the program that called DOS, where we
; put the handler's return address (r3_stub, whose INT 22h takes it back to
; r3_cbret) and the DOS call's.
;
; Inputs:
;	SS:BP -> REG_FRAME (REG_WS.JMP_CS:JMP_IP = the CTRLC handler)
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	r3_ctrlc,DOS
	les	di,dword ptr [bp + size REG_FRAME]
	sub	di,12
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
; stack, which the caller could have changed, so the CS must have RPL 3 (and
; the FLAGS IOPL 0, and interrupts on).
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
	push	bp
	mov	bp,sp			; BP+6 -> IP, CS, FLAGS, SP, SS
	push	ax
	push	si
	mov	ax,cs:[r3_vsel]
	cmp	[bp+8],ax		; did one of our stubs issue it?
	jne	rc0			; no
	push	cx
	mov	cx,[bp+6]
	dec	cx
	dec	cx			; CX = the stub's offset
	call	r3_vecof		; SI -> its RVEC
	pop	cx
	jc	rc0			; (not a stub)
	mov	ax,cs:[si].RV_ORIG.OFF
	mov	[bp+2],ax
	mov	ax,cs:[si].RV_ORIG.SEG
	mov	[bp+4],ax		; [BP+2] -> the handler
	push	ds
	lds	si,dword ptr [bp+12]	; DS:SI -> the stub's caller's stack
	mov	ax,[si]
	mov	[bp+6],ax		; IP
	mov	ax,[si+2]
	mov	[bp+8],ax		; CS
	mov	ax,[si+4]
	mov	[bp+10],ax		; and FLAGS
	add	word ptr [bp+12],6	; (popped)
	pop	ds
	pop	si
	pop	ax
	pop	bp
	db	OP_RETF			; enter the handler
rc0:	pop	si
	pop	ax
	pop	bp
	add	sp,4
	cmp	cs:[r3_cbsp],0		; is the ERROR handler running?
	je	rc5			; no
	mov	ds,cs:[dos_data]
	ASSUME	DS:DOS
	DEFLBL	r3_cbabort,near
	push	ax
	mov	cx,[r3_cbsp0].OFF
	mov	dx,[r3_cbsp0].SEG
	mov	ah,CPU_SETSTACK
	call	far ptr DDINT_CPU	; restore the program's ring 0 stack
	pop	ax
	sub	cx,cx
	xchg	cx,[r3_cbsp]
	cli
	mov	ss,[dos_data]
	mov	sp,cx			; SS:SP -> r3_error's return address
	sti
	ret
	ASSUME	DS:NOTHING
rc5:	push	bp
	mov	bp,sp
	test	byte ptr [bp+6],FL_CARRY; end the program?
	jz	rc6			; no
	mov	ah,EXTYPE_CTRLC
	jmp	dos_abort
rc6:	push	ds
	push	si
	push	ax
	lds	si,dword ptr [bp+8]	; DS:SI -> the DOS call's IP, CS, FLAGS
	cld
	lodsw
	mov	[bp+2],ax
	lodsw
	or	al,3			; (ring 3 only)
	mov	[bp+4],ax
	lodsw
	and	ah,(FL_OVFL+FL_DOWN+FL_INTS+FL_TRAP) SHR 8
	or	ah,FL_INTS SHR 8	; (no IOPL or NT, and interrupts on)
	mov	[bp+6],ax
	mov	[bp+8],si		; (popped)
	pop	ax
	pop	si
	pop	ds
	pop	bp
	jmp	dos_func
ENDPROC	r3_cbret

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
; alias, we copy the REG_FRAME and up to R3_PARAMS words of parameters (as
; many as the caller's stack segment's limit allows) below our stack instead.
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
	mov	ax,CPU_ALIAS SHL 8	; (AL = 0: a DPL 0 data selector)
	call	far ptr DDINT_CPU	; AX = an alias of the caller's SS
	pop	bx
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
; with the interrupt's frame, as if the gate still went to it.
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
	push	es
	push	di
	les	di,dword ptr [bp+10]	; ES:DI -> the caller's stack
	sub	di,6
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
	pop	di
	pop	es
	pop	ax
	pop	si
	pop	ds
	pop	bp
	add	sp,2			; (RV_CALL's return address)
	iret
	ASSUME	DS:NOTHING
rr8:	mov	ax,cs:[si].RV_ORIG.SEG
	mov	si,cs:[si].RV_ORIG.OFF
	xchg	si,[bp]			; [BP] -> the previous handler
	mov	[bp+2],ax
	mov	bp,si
	pop	ax
	pop	si
	pop	ds
	db	OP_RETF			; enter it, with the interrupt's frame
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
; an RVEC's stub, which chains to it.
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
	je	rg9			; no (so the vector as it is)
	call	r3_newvec		; SI -> a new RVEC for DX:CX
	jc	rg9			; none free (ditto)
	call	r3_stubof		; CX = its stub's offset
	mov	dx,[r3_vsel]		; DX:CX -> the stub
rg9:	pop	bx
	ret
ENDPROC	r3_getvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_setvec
;
; msc_setvec comes here, when a ring 3 program sets a vector (see RVEC): to
; one of our stubs, we restore the handler that the stub chains to; to a ring
; 3 handler, we put it in an RVEC (the one that r3_getvec gave the program
; for this vector, if any) and make that RVEC the gate; anything else goes in
; the gate as it is (as it does if there's no free RVEC).
;
; Inputs:
;	AL = vector #
;	DX:CX = new vector
;	DS = DOS
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	r3_setvec,DOS
	push	bx
	cmp	dx,[r3_vsel]		; one of our stubs?
	jne	sv2			; no
	call	r3_vecof		; SI -> its RVEC
	jc	sv8			; (not a stub)
	mov	cx,[si].RV_ORIG.OFF
	mov	dx,[si].RV_ORIG.SEG
	call	far ptr DDINT_SETVEC	; restore the handler it chains to
	pop	bx
	jmp	short r3_freevec	; and free the RVEC
sv2:	test	dl,3			; a ring 3 handler?
	jz	sv8			; no
	call	r3_who			; BX = PSP, AH = session #
	mov	si,offset r3_vecs
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
	jmp	short sv8		; (none free)
sv5:	pop	cx
sv6:	mov	[si].RV_USER.OFF,cx
	mov	[si].RV_USER.SEG,dx
	mov	cx,si
	mov	dx,cs			; DX:CX -> its RV_CALL
sv8:	call	far ptr DDINT_SETVEC
	pop	bx
	ret
ENDPROC	r3_setvec

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
