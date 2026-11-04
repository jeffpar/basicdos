;
; BASIC-DOS CPU$ Driver Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Prints the CPU type (and the processor's own, CPUF_HWTYPE) and the CPU$
; driver's memory arena, and then tests its functions: an allocation from
; the top of conventional memory, resized with CPU_REALLOC, copies with
; CPU_MOVE (including an overlapping one), and in protected mode, allocations
; with GDT and LDT selectors, a mapping of video memory, and aliases (code
; and read-only), or in real mode, the segments that CPU_MAP and CPU_ALIAS
; return instead; then invalid requests, and freeing everything, which must
; leave the arena as it was.  Along the way, it names a block (CPU_SETBLK),
; finds it by its selector (CPU_QUERY), and frees all the blocks of an owner
; (CPU_FREEALL), and tests the functions for debuggers (see debugfns), and
; in protected mode, runs code at ring 3 (see ring3).  Exits with code 0
; if every check passes, or 1 if any fails.
;
; CPU$ is for the kernel and drivers (DDINT_CPU is DPL 0), so at ring 3 (the
; default in protected mode; see RING= in CONFIG.SYS), we print "CPUTESTS
; skipped" and exit with code 0, rather than fault.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc
	include	fpu.inc

STR_LEN	equ	9			; length of str1 (see move)
R0_STACK equ	1024			; size of the ring 0 stack (see ring3)

CODE	segment
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:CODE
	org	100h

DEFPROC	main
	mov	ax,cs
	mov	bx,ds
	cmp	ax,bx			; real mode (where CS = DS)?
	je	m0			; yes
	test	al,3			; ring 3?
	jz	m0			; no
	PRINTF	<"CPUTESTS skipped (needs RING=0)",13,10>
	jmp	m9
m0:	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; AH = CPUF_* flags
	jnc	m1
	PRINTF	<"CPU$ not loaded",13,10>
	jmp	m9
m1:	mov	[pmflag],ah
	mov	cl,6
	shr	ah,cl
	mov	bl,ah
	mov	bh,0			; BX = CPUF_HWTYPE
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	mov	al,[CPU_TYPE]		; (and AH = 0)
	push	ds
	pop	es
	ASSUME	ES:CODE
	PRINTF	<"CPU type %d (hardware %d)",13,10>,ax,bx
	call	info
	mov	[free0].LOW,cx
	mov	[free0].HIW,dx
	call	arena
	mov	[npmbs],bx
	sub	bp,bp			; BP = step #
	call	common
	call	blocks
	call	debugfns
	test	byte ptr [pmflag],CPUF_PM
	jnz	m2
	call	realmode
	jmp	m7
;
; Allocate 100000 bytes with GDT selectors, and 4K with an LDT selector.
;
m2:	call	ring3
	inc	bp
	mov	al,0
	mov	si,1
	mov	di,86A0h		; SI:DI = 100000
	call	alloc
	mov	[addr1].LOW,cx
	mov	[addr1].HIW,dx
	inc	bp
	mov	al,MEMF_LDT
	sub	si,si
	mov	di,4096
	call	alloc
	mov	[sel2],ax
	mov	[addr2].LOW,cx
	mov	[addr2].HIW,dx
;
; Map 4000 bytes of CGA video memory (B8000h).
;
	inc	bp
	mov	al,0
	mov	dx,000Bh
	mov	cx,8000h
	sub	si,si
	mov	di,4000
	mov	ah,CPU_MAP
	call	cpu_ok
	mov	[sel3],ax
	PRINTF	<"Map %#lx at 000B8000: sel %#x",13,10>,di,si,ax
	call	arena
	call	aliases
;
; These requests must fail: freeing an unallocated address, unmapping a
; fixed selector, and allocating more memory than there is.
;
	inc	bp
	mov	[experr],ERR_BADADDR
	mov	cx,1234h
	sub	dx,dx
	mov	ah,CPU_FREE
	call	cpu_err
	inc	bp
	mov	[experr],ERR_INVALID
	mov	bx,08h
	mov	cx,1
	mov	ah,CPU_UNMAP
	call	cpu_err
	inc	bp
	mov	[experr],ERR_NOMEMORY
	mov	al,0
	mov	si,0FFFFh
	sub	di,di
	mov	ah,CPU_ALLOC
	call	cpu_err
;
; Free everything, and make sure the arena is back where it started.
;
	inc	bp
	mov	cx,[addr1].LOW
	mov	dx,[addr1].HIW
	mov	ah,CPU_FREE
	call	cpu_ok
	inc	bp
	mov	bx,[sel3]
	sub	cx,cx
	mov	ah,CPU_UNMAP
	call	cpu_ok
	inc	bp
	mov	cx,[addr2].LOW
	mov	dx,[addr2].HIW
	mov	ah,CPU_FREE
	call	cpu_ok
	inc	bp
	test	byte ptr [sel2],4	; was the 2nd selector an LDT selector?
	jz	m8			; no
m7:	inc	bp
	mov	cx,[sel6]
	mov	dx,-1			; DX:CX = the block, by its selector
	mov	ah,CPU_FREE
	call	cpu_ok
	call	info
	cmp	cx,[free0].LOW		; is the largest free block the same?
	jne	m8
	cmp	dx,[free0].HIW
	jne	m8
	call	arena
	cmp	bx,[npmbs]		; and the number of blocks?
	jne	m8
	PRINTF	<"CPUTESTS passed",13,10>
m9:	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
m8:	PRINTF	<"CPUTESTS failed (step %d)",13,10>,bp
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	main

;
; common
;
; Allocates 4K at the top of conventional memory, shrinks it to 2K, makes sure
; it can't grow to 8K (the next block is reserved), grows it back to 4K, and
; copies a string with CPU_MOVE, forward and then onto itself, 1 byte higher
; (backward); the block stays allocated (see addr6).
;
DEFPROC	common
	inc	bp
	mov	al,MEMF_LOW OR MEMF_HIGH
	sub	si,si
	mov	di,4096
	call	alloc
	mov	[sel6],ax
	mov	[addr6].LOW,cx
	mov	[addr6].HIW,dx
	inc	bp
	mov	di,2048
	call	resize
	call	cpu_ok
	inc	bp
	mov	[experr],ERR_NOMEMORY
	mov	di,8192
	call	resize
	call	cpu_err
	inc	bp
	mov	di,4096
	call	resize
	call	cpu_ok
	inc	bp
	mov	si,offset str1
	mov	di,offset str2
	call	move			; copy str1 to str2
	mov	si,offset str1
	mov	di,offset str2
	mov	cx,STR_LEN
	repe	cmpsb
	jne	cm8
	inc	bp
	mov	si,offset str2
	mov	di,offset str2 + 1
	call	move			; copy str2 to str2 + 1
	mov	si,offset str1
	mov	di,offset str2 + 1
	mov	cx,STR_LEN
	repe	cmpsb
	jne	cm8
	mov	si,offset str2
	PRINTF	<"Move %s",13,10>,si
	ret
	DEFLBL	fail,near
cm8:	jmp	m8
ENDPROC	common

;
; resize
;
; Sets up a CPU_REALLOC of the block at addr6 to DI bytes.
;
DEFPROC	resize
	mov	cx,[addr6].LOW
	mov	dx,[addr6].HIW
	sub	si,si
	mov	ah,CPU_REALLOC
	ret
ENDPROC	resize

;
; realmode
;
; In real mode, CPU_ALLOC, CPU_MAP, and CPU_ALIAS return segments.
;
DEFPROC	realmode
	inc	bp
	mov	al,MEMF_LOW OR MEMF_HIGH
	sub	si,si
	mov	di,16
	call	alloc			; AX = segment
	mov	bx,ax
	mov	ax,cx
	mov	cl,4
	shr	ax,cl
	mov	cl,12
	shl	dx,cl
	or	ax,dx			; AX = segment of the address
	cmp	ax,bx			; are they the same?
	jne	fail
	mov	cl,4
	mov	dx,bx
	shl	bx,cl
	mov	cl,12
	shr	dx,cl
	mov	cx,bx
	mov	ah,CPU_FREE
	call	cpu_ok
	inc	bp
	mov	al,0
	mov	dx,000Bh
	mov	cx,8000h
	sub	si,si
	mov	di,4000
	mov	ah,CPU_MAP
	call	cpu_ok
	cmp	ax,0B800h		; segment of B8000h?
	jne	rm8
	inc	bp
	mov	bx,ax
	mov	al,MEMF_CODE
	mov	ah,CPU_ALIAS
	call	cpu_ok
	cmp	ax,bx			; the same segment?
	jne	rm8
	cmp	cx,8000h		; for B8000h?
	jne	rm8
	cmp	dx,000Bh
	jne	rm8
	PRINTF	<"Map and alias: %#x",13,10>,ax
	inc	bp
	mov	[experr],ERR_INVALID
	mov	ah,CPU_SETSTACK		; (there's no ring 3 in real mode)
	call	cpu_err
	inc	bp
	mov	[experr],ERR_BADADDR
	mov	cx,1234h
	sub	dx,dx
	mov	ah,CPU_FREE
	call	cpu_err
	inc	bp
	mov	[experr],ERR_NOMEMORY
	mov	al,0
	mov	si,0FFFFh
	sub	di,di
	mov	ah,CPU_ALLOC
	jmp	cpu_err
rm8:	jmp	m8
ENDPROC	realmode

;
; move
;
; Copies STR_LEN bytes from DS:SI to DS:DI with CPU_MOVE.
;
DEFPROC	move
	mov	al,[pmflag]
	and	al,CPUF_PM		; AL = ADDR_SEL (the same bit) or 0
	mov	bx,ds
	mov	ah,CPU_SEGINFO
	call	cpu_ok			; DX:CX = address of DS
	xchg	ax,cx			; DX:AX = address of DS
	mov	bx,offset mvpkt
	mov	[bx].MV_SRC.LOW,si
	add	[bx].MV_SRC.LOW,ax
	mov	[bx].MV_SRC.HIW,dx
	adc	[bx].MV_SRC.HIW,0
	mov	[bx].MV_DST.LOW,di
	add	[bx].MV_DST.LOW,ax
	mov	[bx].MV_DST.HIW,dx
	adc	[bx].MV_DST.HIW,0
	mov	[bx].MV_LEN.LOW,STR_LEN
	mov	[bx].MV_LEN.HIW,0
	mov	ah,CPU_MOVE
	jmp	cpu_ok
ENDPROC	move

;
; cpu_ok
;
; Calls CPU$ function AH, and fails the test if it returns an error.
;
DEFPROC	cpu_ok
	call	far ptr DDINT_CPU
	jc	ce8
	ret
ENDPROC	cpu_ok

;
; cpu_err
;
; Calls CPU$ function AH, and fails the test unless it returns error experr.
;
DEFPROC	cpu_err
	call	far ptr DDINT_CPU
	jnc	ce8
	cmp	ax,[experr]		; is it the expected error?
	jne	ce8
	ret
ce8:	jmp	m8
ENDPROC	cpu_err

;
; aliases
;
; Aliases the 4K block's LDT selector as ring 3 code, and the video selector as
; read-only data: each alias must be a new selector for the same address.
; Then frees the code alias, after which aliasing it must fail.
;
DEFPROC	aliases
	inc	bp
	mov	al,MEMF_LDT OR MEMF_CODE OR MEMF_USER
	mov	bx,[sel2]
	mov	ah,CPU_ALIAS
	call	cpu_ok
	cmp	ax,bx			; is it a new selector?
	je	al7
	test	al,4			; an LDT selector?
	jz	al7
	cmp	cx,[addr2].LOW		; for the same address?
	jne	al7
	cmp	dx,[addr2].HIW
	je	al1
al7:	jmp	m8
al1:	mov	[sel4],ax
	PRINTF	<"Alias %#x as code: sel %#x at %#lx",13,10>,bx,ax,cx,dx
	inc	bp
	mov	al,MEMF_RDONLY
	mov	bx,[sel3]
	mov	ah,CPU_ALIAS
	call	cpu_ok
	cmp	ax,bx			; is it a new selector?
	je	al8
	cmp	cx,8000h		; for B8000h?
	jne	al8
	cmp	dx,000Bh
	je	al2
al8:	jmp	m8
al2:	mov	[sel5],ax
	PRINTF	<"Alias %#x as read-only: sel %#x at %#lx",13,10>,bx,ax,cx,dx
	inc	bp
	mov	bx,[sel4]
	sub	cx,cx
	mov	ah,CPU_UNMAP
	call	cpu_ok
	inc	bp
	mov	[experr],ERR_INVALID
	mov	al,MEMF_LDT
	mov	bx,[sel4]
	mov	ah,CPU_ALIAS
	call	cpu_err
	inc	bp
	mov	bx,[sel5]
	sub	cx,cx
	mov	ah,CPU_UNMAP
	call	cpu_ok
	ret
ENDPROC	aliases

;
; ring3
;
; Gives CPU$ a ring 0 stack of our own (CPU_SETSTACK), and runs r3code at ring
; 3, through DPL 3 aliases (MEMF_USER) of our PSP block: it calls FPU$'s
; FPU_DTOA (if FPU$ is loaded), whose conforming code must run at ring 3, and
; then issues INT 21h (a DPL 3 gate), which must reach DOS on the ring 0 stack
; and return to ring 3, INT 0 (also DPL 3), which we hook (see r3int0), and
; INT 0Dh (a DPL 0 gate), which must fault, and which our fault handler
; (CPU_SETFAULT) takes as the way back to ring 0; the handler runs through a
; ring 0 code alias, since CPU$ won't call a handler for a fault in its own
; code segment, and returns to our usual CS.  Then we restore the fault
; handler, vector 0, and the ring 0 stack (which must return ours), check
; the results, and free everything.  First, though, the fault handler lets us
; test returns to an invalid IP (see r3limit).
;
DEFPROC	ring3
	inc	bp
	mov	al,0
	sub	si,si
	mov	di,R0_STACK
	call	alloc			; AX = selector, DX:CX = address
	mov	[sel2],ax
	mov	[addr1].LOW,cx
	mov	[addr1].HIW,dx
	xchg	dx,ax
	mov	cx,R0_STACK		; DX:CX = the ring 0 stack
	mov	ah,CPU_SETSTACK
	call	cpu_ok			; DX:CX = the previous one
	push	dx
	push	cx
	inc	bp
	mov	al,MEMF_CODE OR MEMF_USER
	mov	bx,ds
	mov	ah,CPU_ALIAS
	call	cpu_ok
	mov	[sel4],ax		; ring 3 code alias
	mov	al,MEMF_USER
	mov	ah,CPU_ALIAS
	call	cpu_ok
	mov	[sel5],ax		; ring 3 data alias
	mov	bx,ax			; (DS would just return our CS)
	mov	al,MEMF_CODE
	mov	ah,CPU_ALIAS
	call	cpu_ok
	mov	[sel7],ax		; ring 0 code alias (for r3fault)
	call	r3fpu			; fpu_fn -> FPU_DTOA (if any)
	mov	ax,(DOS_MSC_GETVEC SHL 8) OR INT_DV
	int	21h			; ES:BX = vector 0
	push	es
	push	bx
	push	ds
	pop	es
	mov	dx,offset r3int0	; DS:DX -> r3int0
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_DV
	int	21h
	mov	dx,[sel7]
	mov	cx,offset r3fault
	mov	ah,CPU_SETFAULT
	call	cpu_ok			; DX:CX = the previous handler
	push	dx
	push	cx
	inc	bp
	call	r3limit
	inc	bp
	push	cs
	call	r3go			; (see r3fault for the results)
	push	ss
	pop	ds
	push	ss
	pop	es
	sti
	pop	cx
	pop	dx
	mov	ah,CPU_SETFAULT
	call	cpu_ok			; restore the previous fault handler,
	pop	dx
	pop	ds
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_DV
	int	21h			; vector 0,
	push	ss
	pop	ds
	pop	cx
	pop	dx
	mov	ah,CPU_SETSTACK
	call	cpu_ok			; and ring 0 stack
	cmp	cx,R0_STACK		; did we get our stack back?
	jne	r3x
	cmp	dx,[sel2]
	jne	r3x
	inc	bp
	cmp	byte ptr [r3lim],0	; did those returns fault correctly?
	jne	r3x
	inc	bp
	cmp	[r3vec],0Dh		; did INT 0Dh fault?
	jne	r3x
	cmp	[r3ec],0Dh*8+2		; with its IDT entry as the error code?
	jne	r3x
	mov	ax,[r3cs]
	cmp	[r3fcs],ax		; at ring 3's CS?
	jne	r3x
	and	al,3
	cmp	al,3			; and was that CS at ring 3?
	jne	r3x
	cmp	[r3bx],SIG_BASICDOS	; did INT 21h work there?
	jne	r3x
	cmp	byte ptr [r3flag],1	; and did INT 0 reach r3int0?
	jne	r3x
	inc	bp
	cmp	[fpu_fn].SEG,0		; is FPU$ loaded?
	je	r3a			; no
	cmp	[r3di],offset pmb_buf+3	; did FPU_DTOA store 3 chars
	jne	r3x
	cmp	word ptr [pmb_buf],'.2'	; ("2." in memory order)
	jne	r3x
	cmp	byte ptr [pmb_buf+2],'5'; and "5"?
	je	r3a
r3x:	jmp	m8
r3a:	mov	ax,[r3cs]
	mov	bx,[r3bx]
	mov	dx,[r3ec]
	PRINTF	<"Ring 3 at %#x: INT 21h %#x, INT 0Dh EC %#x",13,10>,ax,bx,dx
	cmp	[fpu_fn].SEG,0
	je	r3b
	PRINTF	<"FPU_DTOA at ring 3: 2.5",13,10>
r3b:	inc	bp
	mov	bx,[sel4]
	sub	cx,cx
	mov	ah,CPU_UNMAP
	call	cpu_ok
	mov	bx,[sel5]
	sub	cx,cx
	mov	ah,CPU_UNMAP
	call	cpu_ok
	mov	bx,[sel7]
	sub	cx,cx
	mov	ah,CPU_UNMAP
	call	cpu_ok
	mov	cx,[addr1].LOW
	mov	dx,[addr1].HIW
	mov	ah,CPU_FREE
	jmp	cpu_ok
ENDPROC	ring3

;
; r3limit
;
; A RETF or IRET to an IP past the limit of the new CS must fault at that
; instruction, with CS, SS, and SP as they were, rather than at the new IP
; (which, after an IRET to ring 3, would be at ring 3).  We try an IRET to ring
; 3 and a RETF within ring 0, each of which r3fault returns from, and set r3lim
; if either goes wrong (ring3 checks it once it has restored everything).
;
DEFPROC	r3limit
	mov	bx,0FFFFh		; BX = an IP past the limit of our CS
	push	cs
	call	r3enter			; IRET to it
	mov	ax,offset r3iret	; AX = where that must have faulted
	mov	cx,12			; CX = 5 words + the fault's flags
	call	rl1
	push	cs
	call	rl8			; RETF to it
	mov	ax,offset r3retf
	mov	cx,6			; (2 words + the fault's flags)
rl1:	push	ss
	pop	ds
	push	ss
	pop	es
	sti
	cmp	[r3fip],ax		; did it fault at the instruction?
	jne	rl7
	cmp	[r3vec],0Dh		; with a general protection fault?
	jne	rl7
	cmp	[r3ec],0		; whose error code is 0?
	jne	rl7
	mov	ax,cs
	cmp	[r3fcs],ax		; with CS unchanged?
	jne	rl7
	mov	ax,ss
	cmp	[r3fss],ax		; and SS?
	jne	rl7
	mov	ax,[r0stk].OFF
	sub	ax,cx
	cmp	[r3fsp],ax		; and SP?
	je	rl9
rl7:	inc	byte ptr [r3lim]
rl9:	ret
rl8:	mov	[r0stk].OFF,sp		; SS:SP -> our return address
	mov	[r0stk].SEG,ss
	push	cs
	push	bx			; CS:IP
	DEFLBL	r3retf,near
	db	OP_RETF
ENDPROC	r3limit

;
; r3go
;
; Enters ring 3 at r3code (or, at r3enter, at BX) with the aliases and our
; current stack, and "returns" (far) from r3fault.
;
DEFPROC	r3go
	mov	bx,offset r3code
	DEFLBL	r3enter,near
	mov	[r0stk].OFF,sp		; SS:SP -> our return address
	mov	[r0stk].SEG,ss
	mov	ax,[sel5]
	or	al,3			; AX = data alias, with RPL 3
	push	ax			; SS
	push	[r0stk].OFF		; SP
	pushf
	mov	cx,[sel4]
	or	cl,3
	push	cx			; CS = code alias, with RPL 3
	push	bx			; IP
	mov	ds,ax			; (IRET would leave DPL 0 data
	mov	es,ax			; selectors null at ring 3)
	DEFLBL	r3iret,near
	iret
r3code:	mov	cx,[fpu_fn].SEG
	jcxz	r3c1			; no FPU$
	mov	si,offset dbl_2_5	; DS:SI -> 2.5
	mov	di,offset pmb_buf	; ES:DI -> buffer
	mov	cx,16			; CX = buffer length
	sub	dx,dx			; DX = width (none)
	mov	ax,00FFh		; AL = precision (none), AH = flags
	call	dword ptr [fpu_fn]	; DI -> after the chars
r3c1:	mov	ah,DOS_MSC_GETVER
	int	21h			; BX = SIG_BASICDOS
	int	INT_DV			; (a DPL 3 gate, to r3int0)
	mov	ax,cs			; AX = our CS
	int	0Dh			; (a DPL 0 gate, so this must fault)
;
; CPU$ calls r3fault (see CPU_SETFAULT) at ring 0 with interrupts disabled,
; the registers as they were (eg, AX, BX, and DI from r3code, and DS = our
; data alias), and SS:SP -> its return address, the vector, the error code,
; and the faulting instruction's frame, which we record before switching
; back to our stack.
;
	DEFLBL	r3fault,near
	add	sp,4			; discard the return address
	pop	[r3vec]
	pop	[r3ec]
	pop	[r3fip]
	pop	[r3fcs]
	mov	[r3fss],ss
	mov	[r3fsp],sp		; (which leaves the fault's flags)
	mov	[r3cs],ax
	mov	[r3bx],bx
	mov	[r3di],di
	mov	ss,[r0stk].SEG
	mov	sp,[r0stk].OFF
	db	OP_RETF			; (from the alias, back to our CS)
;
; r3code's INT 0 comes here, at ring 0 (on the ring 0 stack).
;
	DEFLBL	r3int0,near
	mov	byte ptr [r3flag],1	; (DS = our data alias)
	iret
ENDPROC	r3go

;
; r3fpu
;
; Sets fpu_fn to FPU$'s FPU_DTOA (from the FPUTBL that IOCTL_GETFPU returns),
; or leaves it 0:0 if FPU$ isn't loaded.
;
DEFPROC	r3fpu
	mov	dx,offset fpu_name
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	rf9
	xchg	bx,ax			; BX = handle
	mov	si,offset fpu_fn	; DS:SI -> fpu_fn
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETFPU
	int	21h			; fpu_fn -> FPUTBL
	mov	ah,DOS_HDL_CLOSE
	int	21h
	les	si,[fpu_fn]
	mov	cx,es
	jcxz	rf8			; (none)
	mov	ax,es:[si].FPU_DTOA
	mov	[fpu_fn].OFF,ax		; fpu_fn -> FPU_DTOA
rf8:	push	ds
	pop	es
rf9:	ret
ENDPROC	r3fpu

;
; blocks
;
; Names the 4K block (by its selector) with CPU_SETBLK, which CPU_QUERY must
; then find (by its selector too), and frees two blocks of another owner with
; CPU_FREEALL, after which freeing either of them must fail.
;
DEFPROC	blocks
	inc	bp
	mov	cx,[sel6]
	mov	dx,-1			; DX:CX = the 4K block
	mov	bx,2			; BX = owner
	mov	si,offset name1		; ES:SI -> name
	mov	ax,(CPU_SETBLK SHL 8) OR MCBTYPE_TBLK
	call	cpu_ok
	inc	bp
	mov	cx,[sel6]
	mov	dx,-1
	mov	bx,dx			; BX = -1 (the block at DX:CX)
	mov	di,offset pmb_buf
	mov	ah,CPU_QUERY
	call	cpu_ok
	mov	ax,[addr6].LOW
	cmp	[di].PMB_ADDR.LOW,ax
	jne	bk8
	mov	ax,[addr6].HIW
	cmp	[di].PMB_ADDR.HIW,ax
	jne	bk8
	cmp	[di].PMB_OWNER,2
	jne	bk8
	cmp	[di].PMB_MCBTYPE,MCBTYPE_TBLK
	jne	bk8
	lea	di,[di].PMB_NAME
	mov	si,offset name1
	mov	cx,8
	repe	cmpsb
	je	bk1
bk8:	jmp	m8
bk1:	inc	bp
	mov	bx,3			; BX = another owner
	sub	si,si
	mov	di,16			; SI:DI = length
	mov	ax,(CPU_ALLOC SHL 8) OR MEMF_LOW OR MEMF_HIGH
	call	cpu_ok
	mov	[addr1].LOW,cx
	mov	[addr1].HIW,dx
	mov	ax,(CPU_ALLOC SHL 8) OR MEMF_LOW OR MEMF_HIGH
	call	cpu_ok
	mov	[addr2].LOW,cx
	mov	[addr2].HIW,dx
	inc	bp
	mov	ah,CPU_FREEALL
	call	cpu_ok
	inc	bp
	mov	[experr],ERR_BADADDR
	mov	cx,[addr1].LOW
	mov	dx,[addr1].HIW
	mov	ah,CPU_FREE
	call	cpu_err			; it's free already
	inc	bp
	mov	cx,[addr2].LOW
	mov	dx,[addr2].HIW
	mov	ah,CPU_FREE
	call	cpu_err			; and so is this one
	mov	si,offset name1
	PRINTF	<"Named %.8s, freed owner 3",13,10>,si
	ret
ENDPROC	blocks

;
; debugfns
;
; Tests the functions for debuggers: CPU_SEGINFO of CS as a segment (whose
; base must be CS * 16, with a limit of FFFFh), CPU_RWMEM through CS (a
; selector in protected mode) reading our PSP's INT 20h and writing 4 bytes
; (which must then match), a CPU_RWMEM that would wrap past the end of the
; segment (which must fail), CPU_SETFAULT (which must return the handler we
; set, before we restore the original), and CPU_SYSREGS, which only the
; 80286 driver supports.
;
DEFPROC	debugfns
	inc	bp
	mov	al,0
	mov	bx,cs
	mov	ah,CPU_SEGINFO
	call	cpu_ok			; DX:CX = base, AX = limit
	inc	ax			; is the limit FFFFh?
	jnz	df8			; no
	push	cx
	push	dx
	mov	ax,16
	mul	bx			; DX:AX = our address
	pop	si
	pop	cx
	cmp	ax,cx
	jne	df8
	cmp	dx,si
	jne	df8
	inc	bp
	mov	al,[pmflag]
	and	al,CPUF_PM		; AL = ADDR_SEL or 0 (see move)
	sub	si,si			; BX:SI -> our PSP's INT 20h
	mov	cx,2
	mov	di,offset pmb_buf
	mov	ah,CPU_RWMEM
	call	cpu_ok
	cmp	word ptr [pmb_buf],20CDh
	jne	df8
	inc	bp
	mov	al,[pmflag]
	and	al,CPUF_PM
	or	al,ADDR_WRITE
	mov	si,offset pmb_buf	; BX:SI -> pmb_buf
	mov	cx,4
	mov	di,offset str1		; ES:DI -> str1
	mov	ah,CPU_RWMEM
	call	cpu_ok
	mov	si,offset str1
	mov	di,offset pmb_buf
	mov	cx,4
	repe	cmpsb			; were they written?
	jne	df8			; no
	inc	bp
	mov	[experr],ERR_INVALID
	mov	al,0
	mov	si,0FFFFh		; (the second byte would wrap)
	mov	cx,2
	mov	di,offset pmb_buf
	mov	ah,CPU_RWMEM
	call	cpu_err
	jmp	short df1
df8:	jmp	m8
df1:	inc	bp
	mov	cx,1234h
	mov	dx,5678h		; DX:CX = a handler (never called)
	mov	ah,CPU_SETFAULT
	call	cpu_ok			; DX:CX = the previous handler
	mov	ah,CPU_SETFAULT
	call	cpu_ok			; (restored) DX:CX = ours
	cmp	cx,1234h		; did we get ours back?
	jne	df8			; no
	cmp	dx,5678h
	jne	df8
;
; CPU_SYSREGS must fail exactly when this isn't the 80286 driver.
;
	inc	bp
	mov	ah,CPU_SYSREGS
	call	far ptr DDINT_CPU	; AX = MSW (or an error)
	sbb	dx,dx
	inc	dx			; DX = 1 if it succeeded, 0 if not
	mov	cl,[pmflag]
	and	cx,CPUF_PMOK		; CX = CPUF_PMOK if the 80286 driver
	shr	cx,1			; CX = 1 if so, 0 if not
	cmp	dx,cx
	jne	df8
	PRINTF	<"SYSREGS %d (MSW %#x)",13,10>,dx,ax
	ret
ENDPROC	debugfns

;
; info
;
; Prints and returns the CPU_GETINFO results (DX:CX = largest free block).
;
DEFPROC	info
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU
	mov	bl,ah
	mov	ah,0
	mov	bh,ah
	PRINTF	<"CPU$ %d, flags %#x, free %#lx",13,10>,ax,bx,cx,dx
	ret
ENDPROC	info

;
; alloc
;
; Allocates SI:DI bytes with MEMF_* flags AL, prints the results, and returns
; the selector in AX and the address in DX:CX (the test fails if it fails).
;
DEFPROC	alloc
	mov	ah,CPU_ALLOC
	mov	bx,1			; owner
	call	cpu_ok
	push	ax
	PRINTF	<"Alloc %#lx at %#lx: sel %#x",13,10>,di,si,cx,dx,ax
	pop	ax
	ret
ENDPROC	alloc

;
; arena
;
; Prints every PMB, returning the number of PMBs in BX.
;
DEFPROC	arena
	PRINTF	<"PMB Sig Type Address  Length   Owner Sel  #",13,10>
	sub	bx,bx
ar1:	mov	di,offset pmb_buf
	mov	ah,CPU_QUERY
	call	far ptr DDINT_CPU
	jc	ar9
	mov	al,[di].PMB_SIG
	cbw
	mov	cl,[di].PMB_TYPE
	mov	ch,ah
	PRINTF	<"%3d  %c  %3d  ">,bx,ax,cx
	PRINTF	<"%08lx %08lx ">,[di].PMB_ADDR,:2,[di].PMB_LEN,:2
	mov	ax,[di].PMB_OWNER
	mov	cx,[di].PMB_SEL
	mov	dx,[di].PMB_NSEL
	PRINTF	<"%04x  %04x %d",13,10>,ax,cx,dx
	inc	bx
	jmp	ar1
ar9:	ret
ENDPROC	arena

	DEFBYTE	pmflag,0
	DEFWORD	npmbs,0
	DEFWORD	experr,0
	DEFWORD	sel2,0
	DEFWORD	sel3,0
	DEFWORD	sel4,0
	DEFWORD	sel5,0
	DEFWORD	sel6,0
	DEFWORD	sel7,0
	DEFLONG	free0,0
	DEFLONG	addr1,0
	DEFLONG	addr2,0
	DEFLONG	addr6,0
	DEFLONG	r0stk,0			; our SS:SP while at ring 3
	DEFLONG	fpu_fn,0		; FPU$'s FPU_DTOA (see r3fpu)
;
; What r3code saw at ring 3 (see r3fault and r3int0)
;
	DEFWORD	r3vec,0			; the fault's vector
	DEFWORD	r3ec,0			; and error code
	DEFWORD	r3fip,0			; and IP
	DEFWORD	r3fcs,0			; and CS
	DEFWORD	r3fss,0			; and SS
	DEFWORD	r3fsp,0			; and SP
	DEFWORD	r3cs,0			; ring 3's CS
	DEFWORD	r3bx,0			; BX from INT 21h
	DEFWORD	r3di,0			; DI from FPU_DTOA
	DEFBYTE	r3flag,0		; 1 if INT 0 reached r3int0
	DEFBYTE	r3lim,0			; nonzero if r3limit failed
	even
mvpkt	MOVEPKT	<>
	DEFLBL	dbl_2_5,word
	dw	0,0,0,4004h		; 2.5 (a double)
	DEFLBL	name1,byte
	db	"CPUTESTS"
	DEFLBL	fpu_name,byte
	db	"FPU$",0
	DEFLBL	str1,byte
	db	"CPU_MOVE",0
	DEFLBL	str2,byte
	db	STR_LEN+1 dup (0)

	COMHEAP	<size PMB>	; COMHEAP (heap size) must be the last item

pmb_buf	equ	$

CODE	ends
	end	main
