;
; BASIC-DOS LE Program Host
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; le_host, which an LE program runs as, as far as DOS can tell, and which makes
; the program's DOS calls, along with le_sel and le_mapseg, which give it its
; selectors (see leload.asm, which this module follows, in the part of the
; kernel that only protected mode keeps).
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dos.inc
	include	dosapi.inc
	include	cpu.inc
	include	v86.inc
	include	leload.inc

DOS	segment word public 'CODE'

	EXTNEAR	<le_zero>
	EXTWORD	<dos_data>

	.286p

	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_sel
;
; Returns le_host's code selector (le_csel), which every LE program starts
; with: a ring 3 selector for just le_host's code (le_code to le_cend), that's
; readable as well as executable, since EXEC loads a new program's CS into ES
; (the kernel's own ring 3 alias, r3_code, is execute-only).  It's created
; the first time an LE program is loaded.
;
; Outputs:
;	Carry clear: AX = selector
;	Carry set: AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	le_sel
	mov	ax,cs:[le_csel]
	test	ax,ax			; do we have it yet?
	jnz	ls9			; yes (and carry is clear)
	mov	bx,cs
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	far ptr DDINT_CPU	; DX:CX = the kernel's address
	add	cx,offset le_code
	adc	dx,0			; DX:CX -> le_code
	sub	si,si
	mov	di,offset le_cend - offset le_code
	mov	ax,(CPU_MAP SHL 8) OR MEMF_CODE OR MEMF_USER
	call	far ptr DDINT_CPU	; AX = its selector
	jc	ls9
	or	al,3
	push	ds
	mov	ds,cs:[dos_data]
	mov	ds:[le_csel],ax
	pop	ds
ls9:	ret
ENDPROC	le_sel
	DEFWORD	le_csel,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_mapseg (see utl_mapseg)
;
; DOS_UTL_MAPSEG with REG_AL = 4 points one of a flat machine's two selectors
; at a linear address in it (see fl_lin), and with REG_AL = 5, it adds memory
; to the machine (see fl_grow), zeroed.
;
; Inputs:
;	REG_AL = 4, REG_BX = machine, REG_DX:REG_CX = linear address,
;	REG_SI = 0 or 1 (the selector to use)
;	REG_AL = 5, REG_BX = machine, REG_SI:REG_DI = # of bytes
;
; Outputs:
;	Carry clear if successful: REG_AX = selector and REG_CX = its limit
;	(REG_AL = 4), or REG_DX:REG_CX = the memory's linear address
;	Carry set if error: REG_AX = error code
;
DEFPROC	le_mapseg,DOS
	cmp	al,5
	mov	ax,ERR_INVALID
	ja	lm8			; no such option
	mov	al,byte ptr [bp].REG_AL
	add	al,3			; AL = 7 or 8 (see CPU_V86)
	mov	ah,CPU_V86
	mov	cx,[bp].REG_CX
	mov	dx,[bp].REG_DX
	mov	si,[bp].REG_SI
	mov	di,[bp].REG_DI
	push	ax
	call	far ptr DDINT_CPU
	pop	si			; SI = the CPU$ function
	jc	lm9
	mov	[bp].REG_CX,cx
	test	si,1			; did it add memory (8)?
	jnz	lm9			; no (and carry is clear)
	mov	[bp].REG_DX,dx
	mov	si,[bp].REG_SI
	mov	di,[bp].REG_DI
	add	di,LE_PGSIZE - 1
	adc	si,0
	and	di,NOT (LE_PGSIZE - 1)	; SI:DI = how much it added
	call	le_zero
	jmp	short lm9
lm8:	stc
lm9:	mov	[bp].REG_AX,ax
	ret
ENDPROC	le_mapseg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_host
;
; An LE program's 16-bit code (see load_le), which runs at ring 3, with only
; the PSP's block for its data and stack (SS), and without reading anything
; from CS (its tables are in the block, too).  It runs the program's machine
; until it exits, and for an INT 21h, makes the DOS call for it: the
; function's entry in LED_TBL says which registers are pointers (see LEF_*),
; each of which becomes one of the machine's two selectors with an offset of
; zero, and every other register is passed (and returned) as its low 16 bits.
; A pointer's segment is assumed to be the program's data selector.  Any other
; exit but a hardware interrupt's is a fault, which ends the program.
;
; Functions that aren't in the table (eg, those with FCBs, the DTA, or
; vectors) return carry set and ERR_INVALID.  DOS_HDL_IOCTL passes only
; registers, so only its requests without a buffer work (eg, IOCTL_GETDATA,
; which a C library uses to tell devices from files).  DOS_HDL_READ and
; DOS_HDL_WRITE take a 32-bit count in ECX and return one in EAX, and
; DOS_MEM_ALLOC takes a number of bytes in EBX, which it adds to the end of
; the machine's memory, returning its address in EAX.
;
	DEFLBL	le_code,near
DEFPROC	le_host
lh1:	cld
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	ds:[LED_DS],ds
	mov	ds:[LED_ES],ds
	mov	bx,ds:[LED_MACH]
	mov	di,LED_REGS
	DOSUTIL	MAPSEG,3		; run it (AL = V86X_*)
	jnc	lh1a
	jmp	lh9
lh1a:	cmp	al,V86X_TICK
	jne	lh1b
;
; DOS checks for a CTRLC only when a program reads or writes a character
; device, so after a hardware interrupt, we write nothing to STDERR, or a
; program that never called DOS could never be stopped.
;
	mov	ah,DOS_HDL_WRITE
	mov	bx,STDERR
	sub	cx,cx
	int	INT_DOSFUNC
	jmp	lh1
lh1b:	cmp	al,V86X_INT
	jne	lh8
	cmp	ds:[LED_REGS].VR_VEC,INT_DOSFUNC
	jne	lh8
	and	byte ptr ds:[LED_REGS].VR_EFL,NOT FL_CARRY
	mov	dl,byte ptr ds:[LED_REGS].VR_EAX+1
	mov	si,LED_TBL
lh2:	lodsw				; AL = range's last function
	cmp	dl,al
	ja	lh2
	mov	al,ah
	cbw				; AX = LEF_*
	mov	bx,LED_REGS + VR_EDX
	dec	ax
	js	lh3			; LEF_PASS (or LEF_NONE)
	jz	lh4			; LEF_STR
	dec	ax
	jz	lh5			; LEF_RW
	dec	ax
	jz	lh4a			; LEF_CWD
	dec	ax
	jz	lh2a			; LEF_REN
	jmp	lh_mem			; LEF_MEM
;
; LEF_REN: ES:EDI is a pointer, too.
;
lh2a:
	mov	bx,LED_REGS + VR_EDI
	mov	si,1			; (VR_ESSEL)
	call	le_ptr
	jc	lh7
	mov	ds:[LED_ES],ax
	push	word ptr ds:[LED_REGS].VR_EDI
	mov	word ptr ds:[LED_REGS].VR_EDI,0
	mov	bx,LED_REGS + VR_EDX
	call	le_one
	pop	word ptr ds:[LED_REGS].VR_EDI
	jmp	short lh6
lh3:	inc	ax			; LEF_PASS?
	jnz	lh7			; no
	call	le_call
	jmp	lh1
lh4a:	mov	bx,LED_REGS + VR_ESI
lh4:	call	le_one
lh6:	jc	lh7
	jmp	lh1
lh5:	jmp	lh_rw
lh7:	mov	ax,ERR_INVALID
lh7a:	mov	word ptr ds:[LED_REGS].VR_EAX,ax
	or	byte ptr ds:[LED_REGS].VR_EFL,FL_CARRY
	jmp	lh1
;
; A fault (or an INT that the program can't issue, which is reported as the
; general protection fault that it would be in any ring 3 program).
;
lh8:	mov	bx,ds:[LED_REGS].VR_VEC
	mov	dx,word ptr ds:[LED_REGS].VR_ERR
	cmp	al,V86X_INT
	jne	lh8a
	shl	bx,3
	inc	bx
	inc	bx
	mov	dx,bx			; DX = error code (the vector's gate)
	mov	bx,INT_GP
lh8a:	xchg	ax,bx			; AX = vector
	mov	di,LED_MSG + LE_MSGVEC
	mov	cx,2
	call	le_hex
	xchg	ax,dx			; AX = error code
	mov	di,LED_MSG + LE_MSGERR
	call	le_hex4
	mov	ax,word ptr ds:[LED_REGS].VR_CS
	mov	di,LED_MSG + LE_MSGSEG
	call	le_hex4
	mov	ax,word ptr ds:[LED_REGS].VR_EIP+2
	inc	di			; (past the colon)
	call	le_hex4
	mov	ax,word ptr ds:[LED_REGS].VR_EIP
	call	le_hex4
	mov	dx,LED_MSG
	mov	ah,DOS_TTY_PRINT
	int	INT_DOSFUNC
lh9:	mov	dx,(EXTYPE_FAULT SHL 8) OR 0FFh
	DOSUTIL	TERM
;
; LEF_MEM: add EBX bytes to the machine's memory.
;
lh_mem:	mov	di,word ptr ds:[LED_REGS].VR_EBX
	mov	si,word ptr ds:[LED_REGS].VR_EBX+2
	mov	bx,ds:[LED_MACH]
	DOSUTIL	MAPSEG,5		; DX:CX = its linear address
	jc	lh7a
	mov	word ptr ds:[LED_REGS].VR_EAX,cx
	mov	word ptr ds:[LED_REGS].VR_EAX+2,dx
	jmp	lh1
;
; LEF_RW: transfer ECX bytes at DS:EDX, as much at a time as one selector
; covers (see fl_lin), until they're all done, or one transfers less than it
; was asked to (or fails).
;
lh_rw:	push	word ptr ds:[LED_REGS].VR_ECX
	push	word ptr ds:[LED_REGS].VR_EDX
	push	word ptr ds:[LED_REGS].VR_EAX
	mov	si,LED_REGS + VR_EDX
	mov	di,LED_PTR
	movsw
	movsw				; LED_PTR = EDX
	movsw
	movsw				; LED_CNT = ECX
	sub	ax,ax
	stosw
	stosw				; LED_TOT = 0
lr1:	mov	ax,ds:[LED_CNT]
	mov	dx,ds:[LED_CNT+2]
	mov	cx,ax
	or	cx,dx			; anything left?
	jz	lr8			; no
	push	ax
	push	dx
	mov	bx,LED_PTR
	sub	si,si
	call	le_ptr			; AX = selector, CX = its limit
	pop	dx
	pop	bx			; DX:BX = bytes left
	jc	lr7
	mov	ds:[LED_DS],ax
	inc	cx			; CX = # of bytes there (0 if 64K)
	jz	lr2
	cmp	cx,8000h
	jbe	lr3
lr2:	mov	cx,8000h		; (at most 32K at a time)
lr3:	test	dx,dx			; 64K or more left?
	jnz	lr4			; yes
	cmp	cx,bx
	jbe	lr4
	mov	cx,bx
lr4:	mov	word ptr ds:[LED_REGS].VR_ECX,cx
	mov	word ptr ds:[LED_REGS].VR_EDX,0
	mov	bx,sp
	mov	ax,ss:[bx]
	mov	word ptr ds:[LED_REGS].VR_EAX,ax
	call	le_call
	test	byte ptr ds:[LED_REGS].VR_EFL,FL_CARRY
	jnz	lr9			; (EAX = error code)
	mov	ax,word ptr ds:[LED_REGS].VR_EAX
	sub	dx,dx
	add	ds:[LED_TOT],ax
	adc	ds:[LED_TOT+2],dx
	add	ds:[LED_PTR],ax
	adc	ds:[LED_PTR+2],dx
	sub	ds:[LED_CNT],ax
	sbb	ds:[LED_CNT+2],dx
	cmp	ax,word ptr ds:[LED_REGS].VR_ECX
	je	lr1			; it did all we asked, so go on
lr8:	mov	si,LED_TOT
	mov	di,LED_REGS + VR_EAX
	movsw
	movsw				; EAX = bytes transferred
	jmp	short lr9
lr7:	mov	word ptr ds:[LED_REGS].VR_EAX,ERR_INVALID
	or	byte ptr ds:[LED_REGS].VR_EFL,FL_CARRY
lr9:	pop	ax
	pop	word ptr ds:[LED_REGS].VR_EDX
	pop	word ptr ds:[LED_REGS].VR_ECX
	jmp	lh1
ENDPROC	le_host
	ASSERT	<VR_ECX - VR_EDX>,EQ,4
	ASSERT	<LED_CNT - LED_PTR>,EQ,4
	ASSERT	<LED_TOT - LED_CNT>,EQ,4

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_one, le_ptr, and le_call (for le_host)
;
; le_ptr points one of the machine's selectors at the linear address in a
; register; le_call makes the program's DOS call, with the low words of its
; registers, DS = LED_DS, and ES = LED_ES, and stores the results (EAX's upper
; half is zeroed, and the others' are unchanged); and le_one makes a DOS call
; with DS:0 for the pointer in a register.
;
; Inputs:
;	DS = ES = SS = PSP
;	BX -> the register (le_one and le_ptr), SI = selector to use (le_ptr)
;
; Outputs:
;	Carry set if the pointer isn't in the machine's memory (le_one and
;	le_ptr); otherwise, AX = selector, CX = its limit (le_ptr)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	le_one
	sub	si,si			; SI = 0 (VR_DSSEL)
	push	bx
	call	le_ptr
	pop	bx
	jc	lo9
	mov	ds:[LED_DS],ax
	push	bx
	push	word ptr ds:[bx]
	mov	word ptr ds:[bx],0
	call	le_call
	pop	ax
	pop	bx
	mov	ds:[bx],ax
;
; Carry is the DOS call's, which isn't ours to report: the program's flags
; and EAX already say that it failed.
;
	clc
lo9:	ret
ENDPROC	le_one

DEFPROC	le_ptr
	mov	cx,ds:[bx]
	mov	dx,ds:[bx+2]
	mov	bx,ds:[LED_MACH]
	DOSUTIL	MAPSEG,4
	ret
ENDPROC	le_ptr

DEFPROC	le_call
	mov	ax,word ptr ds:[LED_REGS].VR_EAX
	mov	bx,word ptr ds:[LED_REGS].VR_EBX
	mov	cx,word ptr ds:[LED_REGS].VR_ECX
	mov	dx,word ptr ds:[LED_REGS].VR_EDX
	mov	si,word ptr ds:[LED_REGS].VR_ESI
	mov	di,word ptr ds:[LED_REGS].VR_EDI
	mov	es,ds:[LED_ES]
	mov	ds,ds:[LED_DS]
	int	INT_DOSFUNC
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	word ptr ds:[LED_REGS].VR_EAX,ax
	mov	word ptr ds:[LED_REGS].VR_EAX+2,0
	lahf
	mov	byte ptr ds:[LED_REGS].VR_EFL,ah
	mov	word ptr ds:[LED_REGS].VR_EBX,bx
	mov	word ptr ds:[LED_REGS].VR_ECX,cx
	mov	word ptr ds:[LED_REGS].VR_EDX,dx
	mov	word ptr ds:[LED_REGS].VR_ESI,si
	mov	word ptr ds:[LED_REGS].VR_EDI,di
	ret
ENDPROC	le_call

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; le_hex and le_hex4 (for le_host)
;
; Store AX as CX hex digits (4, for le_hex4) at DS:DI.
;
; Outputs:
;	DI -> after the digits
;
; Modifies:
;	AX, CX
;
DEFPROC	le_hex4
	mov	cx,4
ENDPROC	le_hex4				; fall into le_hex

DEFPROC	le_hex
	add	di,cx
	push	di
lx1:	dec	di
	push	ax
	and	al,0Fh
	cmp	al,10
	sbb	al,69h
	das				; AL = hex digit
	mov	[di],al
	pop	ax
	shr	ax,4
	loop	lx1
	pop	di
	ret
ENDPROC	le_hex
	DEFLBL	le_cend,near
	DEFABS	LE_HOSTOFF,<le_host - le_code>

DOS	ends

	end
