;
; BASIC-DOS Ring 3 Program Lifecycle
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This module holds what r3supp.asm's programs need to start and end, and the
; checks on the DOS calls that change their memory and their PSPs.  Like
; r3supp.asm, it's resident only in protected mode.
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
; How much of a session's ring 0 stack must be left to start another program
; from it (see r3_exec).
;
R3_EXECMIN	equ	512
;
; A ring 3 program's record of what it needs when it ends, at the top of its
; ring 0 stack (SCB_SP0), just below its parent's REG_FRAME; a session's first
; program has no parent, so RR_SP0 and RR_PSP are zero, and it doesn't use the
; rest.
;
R3REC		struc
RR_SP0		dw	?		; its parent's ring 0 stack
RR_PSP		dw	?		; its parent's PSP
RR_SELF		dw	?		; its own PSP
RR_CTRLC	dd	?		; its parent's CTRLC handler
RR_ERROR	dd	?		; its parent's ERROR handler
RR_DTAPREV	dd	?		; its parent's DTA
R3REC		ends
R3_SELTI	equ	04h		; an LDT selector (see 386dev.asm)

DOS	segment word public 'CODE'

	EXTBYTE	<load_user>
	EXTWORD	<dos_data,r3_cbsp,r3_stseg,scb_active>
	EXTNEAR	<dos_func,dos_leave,get_psp,psp_owner,mem_free,mem_realloc>
	EXTNEAR	<psp_termcode,psp_exec,psp_set,psp_copy,psp_create,utl_load>
	EXTNEAR	<hdl_read,hdl_write,fcb_sread,fcb_swrite,fcb_rread,fcb_rwrite>
	EXTNEAR	<fcb_rbread,fcb_rbwrite>
	EXTNEAR	<r3_chkstk,r3_chkrd,r3_chkcode,r3_gp,r3_cbabort>
	EXTNEAR	<r3_pfhok,r3_sfhok,r3_pftfix>

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
; stack, is copied to our stack, just below the parent's REG_FRAME and the
; program's R3REC, followed by the program's SS and SP (which an IRET to ring 3
; pops), with RPL 3 in its SS too (its DS and ES, the PSP's selector, are the
; same as at ring 0, eg, for msc_setvec).  The end of the copy is also the
; program's ring 0 stack (see r3_sp0).
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
rx1:	lea	di,[bp-(2*REG_CHECK + size REG_FRAME + 4 + size R3REC)]
	mov	sp,di			; (psp_exec won't return)
	push	ss
	pop	es			; ES:DI -> the copy
	call	r3_frame		; ES:DI -> its R3REC
	mov	bx,[scb_active]
	mov	ax,di
	xchg	ax,[bx].SCB_SP0		; AX -> the parent's R3REC
	xchg	si,ax
	mov	ax,si
	stosw				; RR_SP0
	mov	ax,es:[si].RR_SELF
	stosw				; RR_PSP
	mov	ax,[bx].SCB_PSP
	stosw				; RR_SELF
	push	ds
	mov	ds,ax
	mov	si,offset PSP_CTRLC
	mov	cx,4
	rep	movsw			; RR_CTRLC and RR_ERROR
	mov	si,offset PSP_DTAPREV
	movsw
	movsw				; RR_DTAPREV
	pop	ds
	mov	cx,[bx].SCB_SP0
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
; its REG_FRAME, followed by its SS and SP and its R3REC, is copied to the top
; of the session's ring 0 stack (see r3_top), where the session will start it.
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
	sub	di,REG_CHECK + size REG_FRAME + 4 + size R3REC
	pop	dx
	push	di
	call	r3_frame		; ES:DI -> its R3REC
	mov	[bx].SCB_SP0,di
	sub	ax,ax
	stosw				; RR_SP0 (no parent)
	stosw				; RR_PSP
	mov	ax,[bx].SCB_PSP
	stosw				; RR_SELF
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
; Sets the ring 0 stack (CPU_SETSTACK) for the session's current program, when
; it becomes current (when a session switch resumes it, or, through r3_resume,
; when the program it started ends, which also ends any fault in that program;
; see r3_end).
;
; Inputs:
;	DS:BX -> SCB
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	r3_resume,DOS
	and	[bx].SCB_STATUS,NOT SCSTAT_FAULT
	DEFLBL	r3_sp0,near
	mov	cx,[bx].SCB_SP0
	jcxz	sp9			; (no program yet)
	mov	dx,[r3_stseg]
	mov	ah,CPU_SETSTACK
	call	far ptr DDINT_CPU
sp9:	ret
ENDPROC	r3_resume

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_free (REG_AH = 49h) and r3_realloc (REG_AH = 4Ah)
;
; With ring 3 programs, set_fault puts these in FUNCTBL, in place of mem_free
; and mem_realloc.  A ring 3 caller may change only a block that it owns (see
; r3_chkblk).  Afterward, any of its selectors that are gone can't be reloaded
; when it returns: a DS or ES selector becomes 0, as in mem_free, and if the
; code it would return to, or its stack, is gone, it ends, as it would have at
; its next instruction, or its next use of the stack.
;
; Inputs and outputs:
;	See mem_free and mem_realloc
;
	ASSUME	DS:DOS
DEFPROC	r3_free,DOS
	mov	si,offset mem_free
	sub	bx,bx			; BX = 0 (no paragraphs left)
	jmp	short rm1
	DEFLBL	r3_realloc,near
	mov	si,offset mem_realloc
	mov	bx,[bp].REG_BX		; BX = paragraphs
rm1:	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jnz	rm2			; yes
	jmp	si
rm2:	mov	cx,[bp].REG_ES
	call	r3_chkblk		; may it change the block?
	jnc	rm3			; yes
	mov	[bp].REG_AX,ax		; no, so update REG_AX and return
	ret				; (carry is set)
rm3:	call	si
	jc	rm9
	mov	ax,[bp].REG_DS
	lar	ax,ax			; can DS still be reloaded?
	jz	rm4			; yes
	mov	[bp].REG_DS,0
rm4:	mov	ax,[bp].REG_ES
	lar	ax,ax			; can ES still be reloaded?
	jz	rm5			; yes
	mov	[bp].REG_ES,0
rm5:	mov	ax,[bp].REG_CS
	mov	cx,[bp].REG_IP
	call	r3_chkcode		; can it return to CS:IP?
	jc	rm8			; no
	mov	ax,[bp + size REG_FRAME + 2]
	lar	ax,ax			; can SS still be reloaded?
	jz	rm9			; yes (and carry is clear)
rm8:	jmp	short r3_gpcall
rm9:	ret
;
; This ends the caller, for what it just asked DOS to do.
;
	DEFLBL	r3_gpcall,near
	sub	ax,ax
	mov	dx,[bp].REG_IP
	mov	cx,[bp].REG_CS
	jmp	r3_gp
ENDPROC	r3_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_read (REG_AH = 3Fh), r3_write (REG_AH = 40h), and the FCB equivalents
;
; With ring 3 programs, set_fault puts these in FUNCTBL, in place of the
; functions they name: a disk transfer goes to a physical address, which a
; driver computes from just the base of the buffer's selector, ignoring its
; limit, and a fault in a driver is fatal; so before we let the kernel transfer
; anything for a ring 3 caller, the entire buffer has to be in the caller's
; memory.
;
; Inputs and outputs:
;	See the functions named
;
	ASSUME	DS:DOS
DEFPROC	r3_read,DOS
	mov	si,offset hdl_read
	sub	bx,bx			; BX = 0 (it will write the buffer)
	jmp	short rw1
	DEFLBL	r3_write,near
	mov	si,offset hdl_write
	mov	bx,1			; BX = 1 (it will read the buffer)
rw1:	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jnz	rw1a			; yes
	jmp	si
rw1a:	pusha
	push	bx
	mov	bx,[bp].REG_BX
	call	r3_pfhok		; may it use the handle?
	pop	bx
	jnc	rw1b			; yes
	popa
	mov	ax,ERR_BADHANDLE
	mov	[bp].REG_AX,ax
	stc
	ret
rw1b:	mov	di,dx
	mov	dx,[bp].REG_DS		; DX:DI -> buffer, CX = # of bytes
	jmp	short rw4
;
; The FCB functions transfer FCB_RECSIZE bytes per record, between the DTA and
; the file: the random block functions do CX records, and the others, just one.
;
	DEFLBL	r3_sread,near
	mov	si,offset fcb_sread
	sub	bx,bx
	jmp	short rw2
	DEFLBL	r3_swrite,near
	mov	si,offset fcb_swrite
	mov	bx,1
	jmp	short rw2
	DEFLBL	r3_rread,near
	mov	si,offset fcb_rread
	sub	bx,bx
	jmp	short rw2
	DEFLBL	r3_rwrite,near
	mov	si,offset fcb_rwrite
	mov	bx,1
	jmp	short rw2
	DEFLBL	r3_rbread,near
	mov	si,offset fcb_rbread
	sub	bx,bx
	jmp	short rw2
	DEFLBL	r3_rbwrite,near
	mov	si,offset fcb_rbwrite
	mov	bx,1
rw2:	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	rw8			; no
	pusha
	push	ds
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	mov	di,dx			; DS:DI -> FCB
	cmp	byte ptr [di],0FFh	; an extended FCB?
	jne	rw2a			; no
	add	di,7			; yes (the FCB follows its header)
rw2a:	mov	cx,[di].FCB_RECSIZE
	cmp	ah,DOS_FCB_RBREAD	; a block function?
	jb	rw3			; no
	mov	ax,[bp].REG_CX
	mul	cx			; DX:AX = # of bytes
	xchg	cx,ax
	test	dx,dx			; more than a segment?
	jz	rw3			; no
	mov	cx,0			; yes (which those functions refuse)
rw3:	pop	ds
	ASSUME	DS:DOS
	mov	di,[scb_active]
	mov	dx,[di].SCB_DTA.SEG
	mov	di,[di].SCB_DTA.OFF	; DX:DI -> DTA, CX = # of bytes
	mov	ax,di
	add	ax,cx			; does it wrap around the segment?
	jnc	rw4			; no
	test	ax,ax			; (ending at the very end is fine)
	jz	rw4			; no
	sub	cx,cx			; yes (which those functions refuse)
rw4:	jcxz	rw7			; (nothing to transfer)
	test	bx,bx			; will it read the buffer?
	jnz	rw5			; yes
	call	r3_chkstk		; can it write the buffer?
	jmp	short rw6
rw5:	call	r3_chkrd		; can it read the buffer?
rw6:	jnc	rw7			; yes
	jmp	r3_gpcall
rw7:	popa
rw8:	jmp	si
ENDPROC	r3_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_chkblk
;
; Checks that a ring 3 caller may change the block in CX: it must own the
; block, since any of its selectors with the same base address leads to the
; block (eg, one for the low memory block, from DOS_UTL_MAPSEG), and if the
; block holds its PSP, it must still fit, since DOS needs it until the program
; ends.
;
; Inputs:
;	BX = paragraphs that the block will have (zero if it's being freed)
;	CX = block
;
; Outputs:
;	Carry clear if so; otherwise, carry set and AX = ERR_BADADDR
;
; Modifies:
;	AX, CX, DX, DI, ES
;
DEFPROC	r3_chkblk,DOS
	ASSUME	DS:NOTHING
	sub	sp,size PMB
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> PMB buffer
	push	bx
	mov	bx,-1
	mov	dx,bx			; DX = -1 (CX is a selector)
	mov	ah,CPU_QUERY
	call	far ptr DDINT_CPU	; its PMB (or carry set, AX = error)
	pop	bx
	jc	cb9
	push	es:[di].PMB_OWNER
	push	es:[di].PMB_SEL
	call	get_psp			; AX = current PSP
	call	psp_owner		; AX = its owner ID, ES:DI -> its PMB
	pop	cx			; CX = the block's first selector
	pop	dx			; DX = the block's owner ID
	jc	cb9
	cmp	dx,ax			; does the caller own the block?
	jne	cb8			; no
	cmp	es:[di].PMB_SEL,cx	; is it the PSP's block?
	clc
	jne	cb9			; no
	cmp	bx,size PSP SHR 4	; will the PSP still fit in it?
	jae	cb9			; yes (and carry is clear)
cb8:	mov	ax,ERR_BADADDR
	stc
cb9:	lea	sp,[di + size PMB]	; (LEA leaves carry alone)
	ret
ENDPROC	r3_chkblk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_pspcopy (REG_AH = 26h) and r3_pspnew (REG_AH = 55h)
;
; With ring 3 programs, set_fault puts these in FUNCTBL, in place of psp_copy
; and psp_create, which write a PSP at the selector in REG_DX; since that's not
; in a segment register, the processor hasn't checked it, so a ring 3 caller's
; must be a block that it owns (see r3_chkblk).
;
	ASSUME	DS:DOS
DEFPROC	r3_pspcopy,DOS
	mov	si,offset psp_copy
	jmp	short rn1
	DEFLBL	r3_pspnew,near
	mov	si,offset psp_create
rn1:	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	rn8			; no
	call	get_psp
	call	r3_pftfix		; (the new PSP inherits its handles)
	mov	bx,size PSP SHR 4	; (the PSP must fit)
	mov	cx,[bp].REG_DX
	call	r3_chkblk
	jnc	rn8
	mov	[bp].REG_AX,ax		; update REG_AX (and carry is set)
	ret
rn8:	jmp	si
ENDPROC	r3_pspcopy

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_pspset (REG_AH = 50h)
;
; With ring 3 programs, set_fault puts this in FUNCTBL, in place of psp_set:
; the kernel uses the current PSP constantly, so a ring 3 caller's must be a
; PSP: a block's first selector, in this session's LDT, whose block owns itself
; (see enc_owner).
;
; Inputs:
;	REG_BX = segment of new PSP
;
; Outputs:
;	On failure, carry set, REG_AX = ERR_BADADDR
;
DEFPROC	r3_pspset,DOS
	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	pp7			; no
	sub	sp,size PMB
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> PMB buffer
	mov	si,[scb_active]
	mov	cx,[bp].REG_BX
	mov	bx,-1
	mov	dx,bx			; DX = -1 (CX is a selector)
	mov	ah,CPU_QUERY
	call	far ptr DDINT_CPU	; its PMB (or carry set, AX = error)
	jc	pp8
	mov	ax,es:[di].PMB_SEL
	mov	cx,[bp].REG_BX
	and	cl,NOT 3
	cmp	ax,cx			; is it the block's first selector?
	jne	pp6			; no
	test	al,R3_SELTI		; in an LDT?
	jz	pp6			; no
	shr	ax,3
	mov	ah,[si].SCB_LDT
	or	ah,80h			; AX = its owner ID, if it owns itself
	cmp	ax,es:[di].PMB_OWNER	; does it, in this session's LDT?
	je	pp6a			; yes
pp6:	mov	ax,ERR_BADADDR
	stc
	jmp	short pp8
pp6a:	add	sp,size PMB
pp7:	jmp	psp_set
pp8:	add	sp,size PMB
	mov	[bp].REG_AX,ax
	stc
	ret
ENDPROC	r3_pspset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_exec (REG_AH = 4Bh)
;
; With ring 3 programs, set_fault puts this in FUNCTBL, in place of psp_exec.
; The pointers in a ring 3 caller's EPB aren't in segment registers, so the
; processor hasn't checked them, and they could be anything the kernel can use,
; so they all get RPL 3, which keeps the kernel from using a ring 0 selector
; (if one of them is otherwise invalid, it's just a fault; see r3_end).
;
; An EXEC2 must start a program that was loaded and hasn't started, and its
; initial stack and address must be usable, since we write the one and return
; to the other; DOS_PSP_EXEC1 returned them, but the caller could have changed
; them.
;
; Inputs and outputs:
;	See psp_exec
;
DEFPROC	r3_exec,DOS
	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jnz	xe1			; yes
	jmp	psp_exec
xe1:	pusha
;
; A program's ring 0 stack is its parent's, so each program in a chain leaves
; less of its session's stack for the kernel, and running out would overwrite
; another session's stack (or stop the system); so a chain has a limit.  The
; check doesn't apply to an ERROR handler, which isn't on that stack.
;
	mov	ax,ss
	cmp	ax,[r3_stseg]		; on the session's ring 0 stack?
	jne	xe0			; no
	mov	bx,[scb_active]
	mov	al,[bx].SCB_NUM
	mov	ah,R3_STACK_SIZE SHR 8
	mul	ah
	mov	ah,al
	mov	al,0			; AX = the bottom of its ring 0 stack
	add	ax,R3_EXECMIN
	cmp	sp,ax			; enough left for another program?
	jae	xe0			; yes
	popa
	mov	ax,ERR_NOMEMORY
	jmp	short xe9a
xe0:	call	get_psp
	call	r3_pftfix		; (the new program inherits them)
	mov	ax,[bp].REG_AX		; (AL = the EXEC's type)
	push	ds
	mov	ds,[bp].REG_ES
	ASSUME	DS:NOTHING
	mov	si,[bp].REG_BX		; DS:SI -> EPB
	mov	ah,3			; (for each pointer's selector)
	or	byte ptr [si].EPB_CMDTAIL.SEG,ah
	or	byte ptr [si].EPB_FCB1.SEG,ah
	or	byte ptr [si].EPB_FCB2.SEG,ah
	or	byte ptr [si].EPB_INIT_SP.SEG,ah
	or	byte ptr [si].EPB_INIT_IP.SEG,ah
	cmp	al,DOS_PSP_EXEC2 AND 0FFh
	jne	xe6			; not an EXEC2
	push	ds
	mov	ds,cs:[dos_data]
	ASSUME	DS:DOS
	mov	bx,[scb_active]
	mov	di,[bx].SCB_SP0
	mov	es,[r3_stseg]		; ES:DI -> the running program's R3REC
	mov	cx,[bx].SCB_PSP		; CX = the current PSP
	call	r3_inchain		; is it running (ie, not just loaded)?
	mov	ax,es:[di].RR_SELF	; AX = the running program's PSP
	pop	ds
	ASSUME	DS:NOTHING
	je	xe9			; yes
	mov	es,cx
	mov	es:[PSP_PARENT],ax	; psp_exec uses this
	mov	ax,[si].EPB_INIT_IP.SEG
	mov	cx,[si].EPB_INIT_IP.OFF
	call	r3_chkcode		; can we start the program there?
	jc	xe8			; no
	mov	dx,[si].EPB_INIT_SP.SEG
	mov	di,[si].EPB_INIT_SP.OFF
	sub	di,size REG_FRAME - 2 + REG_CHECK
	mov	cx,size REG_FRAME + REG_CHECK
	call	r3_chkstk		; does its REG_FRAME fit on that stack?
	jc	xe8			; no
xe6:	pop	ds
	ASSUME	DS:DOS
	popa
xe7:	jmp	psp_exec
xe8:	jmp	r3_gpcall
xe9:	pop	ds
	popa
	mov	ax,ERR_INVALID
xe9a:	mov	[bp].REG_AX,ax
	stc
	ret
ENDPROC	r3_exec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_uload (DOS_UTL_LOAD)
;
; With ring 3 programs, set_fault puts this in UTILTBL, in place of utl_load,
; which reads an SPB's command line after making the new session's SCB active,
; where a fault couldn't end the caller; so we read it first.  It's a pointer
; in memory, too, so it gets RPL 3, as in r3_exec.
;
; Inputs and outputs:
;	See utl_load
;
DEFPROC	r3_uload,DOS
	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	ru9			; no
	pusha
	push	ds
	mov	ds,[bp].REG_ES
	ASSUME	DS:NOTHING
	mov	si,[bp].REG_BX		; DS:SI -> SPB
;
; The new session can have only the SFHs that the caller may use.
;
	mov	cx,5
	lea	di,[si].SPB_SFHIN
ru0:	mov	al,[di]
	call	r3_sfhok
	jnc	ru0a
	mov	byte ptr [di],SFH_NONE
ru0a:	inc	di
	loop	ru0
	or	byte ptr [si].SPB_CMDLINE.SEG,3
	lds	si,[si].SPB_CMDLINE	; DS:SI -> the command line
	mov	cx,CMDLINE_MAX
ru1:	lodsb				; (up to CMDLINE_MAX bytes)
	test	al,al
	loopnz	ru1
	pop	ds
	ASSUME	DS:DOS
	popa
ru9:	jmp	utl_load
ENDPROC	r3_uload

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_term (REG_AH = 00h), r3_return (REG_AH = 4Ch), and r3_uterm (DOS_UTL_TERM)
;
; With ring 3 programs, set_fault puts these in FUNCTBL and UTILTBL, in place
; of psp_term, psp_return, and utl_term.  If the kernel called this (eg,
; dos_abort, on behalf of dos_fault or dos_restart), we start over at the top
; of the ring 0 stack, as if the program had made this call, since that's where
; its registers are (eg, for its CTRLC handler; see r3_ctrlc).  Then the PSP's
; fields get what they should have (see r3_chkterm).
;
; If it's a ring 3 ERROR handler that's ending, DOS is waiting for its
; response, and an ABORT ends the program, once DOS has finished its call.
;
; Inputs:
;	AL = exit code (r3_return)
;	DL = exit code, DH = exit type (r3_uterm)
;
	ASSUME	DS:DOS
DEFPROC	r3_term,DOS
	sub	dx,dx			; DX = 0 (the default code and type)
	jmp	short rt1
	DEFLBL	r3_return,near
	mov	dl,al
	mov	dh,EXTYPE_NORMAL
	DEFLBL	r3_uterm,near
rt1:	cmp	[r3_cbsp],0		; in a ring 3 ERROR handler?
	je	rt2			; no
	mov	al,CRERR_ABORT
	jmp	r3_cbabort
rt2:	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jnz	rt3			; yes
	mov	bx,[scb_active]
	mov	cx,[bx].SCB_SP0
	jcxz	rt4			; (no ring 3 program)
	mov	si,cx
	mov	es,[r3_stseg]
	test	byte ptr es:[si-8],3	; is its CS really from ring 3?
	jz	rt4			; no (starting over wouldn't help)
	cli
	mov	[bx].SCB_INDOS,0
	mov	ss,[r3_stseg]
	mov	sp,cx
	sub	sp,10			; SS:SP -> IP, CS, FLAGS, SP, and SS
	mov	ah,DOS_UTL_TERM + 80h
	jmp	dos_func
rt3:	call	r3_chkterm
rt4:	xchg	ax,dx			; AL = exit code, AH = exit type
	jmp	psp_termcode
ENDPROC	r3_term

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_chkterm
;
; Before a ring 3 program ends, gives the fields of its PSP (and its parent's)
; that the kernel will use the values they should have, since the program could
; have changed them.  Usually, the current PSP is the running program's, whose
; R3REC says who its parent is, and where its parent's REG_FRAME is.
;
; Otherwise, it's a program that the running program loaded and hasn't started
; (eg, DEBUG's Q command), so the running program is its parent, and resumes at
; the top of its ring 0 stack, or it's one of the running program's ancestors
; (see DOS_PSP_SET), whose memory we can't free yet, so the running program
; ends instead.
;
; Its PSP_EXIT can be any address that's usable at ring 3; if it isn't, it gets
; the address in its parent's REG_FRAME.  A running program's PSP_CTRLC,
; PSP_ERROR, and PSP_DTAPREV come from its R3REC; a program that never started
; couldn't have changed them, but its parent could, so its PSP_DTAPREV gets
; RPL 3 (see r3_exec), and handlers are checked when they're used.
;
; Inputs:
;	DS = DOS
;
; Modifies:
;	None
;
DEFPROC	r3_chkterm,DOS
	pusha
	push	ds
	push	es
	mov	bx,[scb_active]
	mov	di,[bx].SCB_SP0
	mov	es,[r3_stseg]		; ES:DI -> the running program's R3REC
	mov	cx,[bx].SCB_PSP		; CX = the PSP that's ending
	mov	ax,es:[di].RR_SELF	; AX = the running program's PSP
	call	r3_inchain		; is it running?
	jne	ct1			; no
	mov	[bx].SCB_PSP,ax		; (the running program is ending)
	xchg	cx,ax
	mov	si,es:[di].RR_PSP	; SI = its parent's PSP (zero if none)
	test	si,si
	jz	ct2
	mov	ax,es:[di].RR_SP0
	mov	[bx].SCB_SP0,ax		; its parent's ring 0 stack
	push	ds
	push	es
	push	di
	push	cx
	push	es
	pop	ds
	mov	es,cx			; ES = the PSP that's ending
	lea	si,[di].RR_CTRLC	; (DS:SI -> what the PSP should have)
	mov	di,offset PSP_CTRLC
	mov	cx,4
	rep	movsw			; its parent's CTRLC and ERROR handlers
	mov	di,offset PSP_DTAPREV
	movsw
	movsw				; and its parent's DTA
	pop	cx
	pop	di
	pop	es
	pop	ds
	mov	si,es:[di].RR_PSP
ct2:	lea	di,[di + size R3REC]	; DI = its parent's PSP_STACK
	jmp	short ct3
ct1:	xchg	si,ax			; SI = its parent's PSP
	sub	di,size REG_FRAME + 4 + REG_CHECK
ct3:	mov	dl,[bx].SCB_NUM
	mov	ds,cx			; DS = the PSP that's ending
	ASSUME	DS:NOTHING
	mov	ax,cx
	call	r3_pftfix		; (the kernel will close its handles)
	mov	ds:[PSP_SCB],dl
	mov	ds:[PSP_PARENT],si
	or	byte ptr ds:[PSP_DTAPREV].SEG,3
	test	si,si			; does it have a parent?
	jz	ct9			; no
	mov	bl,dl			; (r3_chkcode modifies DX)
	mov	ax,ds:[PSP_EXIT].SEG
	mov	cx,ds:[PSP_EXIT].OFF
	call	r3_chkcode		; can we return there?
	jnc	ct5			; yes
	mov	ax,es:[di + REG_CHECK].REG_CS
	mov	ds:[PSP_EXIT].SEG,ax
	mov	ax,es:[di + REG_CHECK].REG_IP
	mov	ds:[PSP_EXIT].OFF,ax
ct5:	mov	ds,si			; DS = its parent's PSP
	mov	ds:[PSP_SCB],bl
	mov	ds:[PSP_STACK].OFF,di
	mov	ds:[PSP_STACK].SEG,es
ct9:	pop	es
	pop	ds
	ASSUME	DS:DOS
	popa
	ret
ENDPROC	r3_chkterm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_inchain
;
; Inputs:
;	ES:DI -> the running program's R3REC
;	CX = PSP
;
; Outputs:
;	Zero flag set if CX is the running program's, or one of its ancestors'
;
; Modifies:
;	None
;
DEFPROC	r3_inchain,DOS
	ASSUME	DS:NOTHING
	push	si
	mov	si,di
ic1:	cmp	es:[si].RR_SELF,cx	; is it this program's?
	je	ic9			; yes
	mov	si,es:[si].RR_SP0	; SI -> its parent's R3REC
	test	si,si			; any more?
	jnz	ic1			; yes
	inc	si			; no (and clears the zero flag)
ic9:	pop	si
	ret
ENDPROC	r3_inchain

DOS	ends

	end
