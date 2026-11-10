;
; BASIC-DOS 80286/80386 Processor (CPU$) Driver Initialization
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The CPU$ driver's initialization is linked last, after 386dev.asm (the code
; that every 80286 or later keeps) and 386v86.asm (the code that only an
; 80386 keeps; see DDPI_END), whose segment it shares.
;
	BIOSAPI equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc
	include	386dev.inc

DEV	group	CODE

CODE	segment para public 'CODE'

	EXTERNS	<ddcpu_req,cpu_entry>,far
	EXTNEAR	<exc_stubs,irq_stubs,sw_int,v86_begin>
	EXTWORD	<sys_seg>

	.286p
;
; Everything here is discarded after initialization (see DDPI_END), and
; until we know it's an 80286 (see di3), it must run on an 8086.
;
	.8086
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Only 8086 instructions may be used until the CPU type is known.
;
; We're always the first driver, so we also apply any "MEMSIZE=" line (see
; docs/bdman/cfg), by lowering MEMORY_SIZE, before either driver builds its
; arena.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated (left zero if we're not staying), and if
;	we're staying, CPU_ARENA (see cpu.inc)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, DS
;
DEFPROC	ddcpu_init,far
	mov	ds,cs:[0].DDH_DATA
	mov	ds:[0].DDH_REQUEST,offset DEV:ddcpu_req
	push	es
	push	bx
	mov	di,offset DEV:cfg_memsize
	call	find_cfg		; is there a "MEMSIZE=" line?
	jne	di0			; no
	add	si,8			; DS:SI -> its value
	sub	ax,ax
dm1:	mov	cl,[si]
	sub	cl,'0'
	cmp	cl,9			; another digit?
	ja	dm2			; no
	inc	si
	mov	dx,ax
	shl	ax,1
	shl	ax,1
	add	ax,dx
	shl	ax,1			; AX = AX * 10
	mov	ch,0
	add	ax,cx
	jmp	dm1
dm2:	mov	dx,BIOS
	mov	ds,dx
	ASSUME	DS:BIOS
	cmp	ax,16			; is the value at least 16 (Kb)?
	jb	di0			; no
	cmp	ax,[MEMORY_SIZE]	; and less than we have?
	jae	di0			; no
	mov	[MEMORY_SIZE],ax
di0:	mov	di,offset DEV:cfg_cpu
	call	find_cfg		; is there a "CPU=80" line?
	mov	bl,0			; BL = its next digit (zero if none)
	jne	di0a			; no
	mov	bl,[si+6]
di0a:	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
;
; Even then, we determine the processor type (for CPU_HWTYPE).
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
di2:	mov	[CPU_HWTYPE],al
;
; We act as if this is an 8088 unless protected mode is requested, by a CONFIG
; line or a P at the boot message, and an R then overrides a line.
;
	mov	ah,byte ptr [BOOT_KEY]
	or	ah,20h			; AH = boot key, in lower-case
	mov	bh,bl
	and	bh,0FEh
	cmp	bh,'2'			; a "CPU=802xx" or "CPU=803xx" line?
	je	di2c			; yes
	cmp	ah,'p'			; was the boot key P?
	jne	di2b			; no
di2c:	cmp	ah,'r'			; was the boot key R?
	je	di2b			; yes
;
; Protected mode also needs at least 256K of conventional memory (after any
; "MEMSIZE=" line), so with less, we act as if this is an 8088, too.
;
	cmp	[MEMORY_SIZE],256	; enough conventional memory?
	jae	di2a			; yes
di2b:	mov	al,CPUTYPE_8086		; no, so act as if this is an 8088
di2a:
;
; On an 80386 or later, we use its features, unless there's a "CPU=80286"
; line, and then we use only an 80286's (and CPU_TYPE says which).
;
	cmp	al,CPUTYPE_80386	; an 80386 or later?
	jb	di2e			; no
	cmp	bl,'2'			; but a "CPU=80286" line?
	jne	di2e			; no
	dec	ax			; AL = CPUTYPE_80286
di2e:	mov	[CPU_TYPE],al
	cmp	al,CPUTYPE_80286	; protected mode available?
	jb	di9			; no
;
; Extended memory is optional.  A20 isn't, because an 80286 returns to real
; mode through a reset (see pm_call), and the ROM's reset vector at FFFFF0h
; needs it.  If A20 isn't enabled, then writing FFFF:0010h changes its
; wrap-around alias in low memory (and if it is, the write has no effect there,
; whether or not there's any memory at that address).
;
	mov	ah,CAS_GETEXTMEM
	int	INT_CASSETTE
	jnc	di2d
	sub	ax,ax			; no extended memory
di2d:	xchg	si,ax			; SI = Kb of extended memory
	call	a20_on
	mov	ax,0FFFFh
	mov	es,ax
	ASSUME	ES:NOTHING
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:NOTHING
	mov	bx,ds:[0]		; BX = word at the low memory alias
	mov	ax,bx
	not	ax
	mov	es:[10h],ax
	cmp	ds:[0],ax		; did the alias change?
	mov	ds:[0],bx		; (restore it, in case it did)
	pop	ds
	ASSUME	DS:BIOS
	jne	di3			; no, so A20 is enabled
;
; On an 8086 (or without A20, or if the protected mode self-test fails), we
; unload ourselves (DDPI_END is still zero), and the 8086 driver stays instead,
; so CPU_TYPE must say we're acting as an 8088.
;
di9:	mov	[CPU_TYPE],CPUTYPE_8086
	pop	bx
	pop	es
	ret
;
; The system area is the last whole 64K of conventional memory.  Clear all of
; it (so that unused GDT entries, including the gaps between the identity
; selectors, aren't present), and then fill in SYSVARS, the PMBs, and the GDT.
;
	.286p
	ASSUME	DS:BIOS
di3:	mov	ax,[MEMORY_SIZE]
	and	ax,0FFC0h		; AX = Kb, in whole 64K units
	sub	ax,64
	shl	ax,6			; AX = segment of the last whole 64K
	mov	cs:[sys_seg],ax
	mov	es,ax
	sub	ax,ax
	mov	di,ax
	mov	cx,8000h		; (64K)
	rep	stosw

	mov	di,SYS_VARS
	mov	ax,word ptr [CPU_TYPE]	; AL = CPU_TYPE, AH = CPU_HWTYPE
	ror	ah,1
	ror	ah,1			; AH = CPUF_HWTYPE
	mov	word ptr es:[di].SV_TYPE,ax	; (and SV_FLAGS)
	cbw				; (AL is 2 or 3)
	dec	ax
	shl	ax,1
	mov	es:[di].SV_TSSSP0,ax	; 2 (80286 TSS) or 4 (80386 TSS)
	mov	es:[di].SV_RMCS,cs
	mov	es:[di].SV_GDTR,GDT_LIMIT
	mov	es:[di].SV_GDTR+2,SYS_GDT
	mov	es:[di].SV_PIDTR,IDT_MAX * (size DESC) - 1
	mov	es:[di].SV_PIDTR+2,SYS_PIDT
	mov	es:[di].SV_RMIDTR,3FFh
	mov	ax,SYS_LDTTOP
	mov	es:[di].SV_LDT,ax	; LDT 0 (see CPU_SETLDT)
	push	di
	add	di,SV_LDTTOP
	mov	cx,LDT_SESSIONS + 1
	rep	stosw			; every LDT is empty
	pop	di
	call	cpu_len			; AX = length of CPU$
	call	init_arena

	push	cs
	pop	ds
	ASSUME	DS:NOTHING
	mov	si,offset DEV:gdt_init
	mov	di,SYS_GDT + (size DESC)
	mov	cx,offset DEV:gdt_init_end - offset DEV:gdt_init
	rep	movsb
;
; Every system area address has the same upper base bits (and the lower bits
; are its offset, since the area starts on a 64K boundary).
;
	mov	ax,es
	mov	al,ah
	shr	al,4			; AL = base bits 23-16
	mov	byte ptr es:[SYS_VARS].SV_GDTR+4,al
	mov	byte ptr es:[SYS_VARS].SV_PIDTR+4,al
	mov	es:[SYS_GDT+SEL_SYS].DESC_BASE16,al
	mov	es:[SYS_GDT+SEL_LDTD].DESC_BASE16,al
	mov	es:[SYS_GDT+SEL_TSS].DESC_BASE16,al
	cmp	es:[SYS_VARS].SV_TYPE,CPUTYPE_80386	; an 80386 TSS?
	jb	di3a			; no
	mov	es:[SYS_GDT+SEL_TSS].DESC_ACC,ACC_TSS386
	mov	word ptr es:[SYS_TSS+TSS_IOMAP],TSS_LEN	; (no I/O bitmap)
di3a:	mov	ax,cs
	mov	dx,ax
	shl	ax,4
	shr	dx,12			; DX:AX = linear address of CS
	mov	es:[SYS_GDT+SEL_CPUCODE].DESC_BASE,ax
	mov	es:[SYS_GDT+SEL_CPUCODE].DESC_BASE16,dl
;
; The identity selectors: data for video memory (A000h-B800h) and code for
; the adapter and system ROMs (C000h-F800h), all DPL 0, for the BIOS and the
; drivers.  A ring 3 program that draws directly (eg, COMMAND.COM's graphics)
; gets an LDT selector from the CONSOLE driver instead (IOCTL_GETMODE), which
; the driver can change or take away (see pm_remap).
;
	mov	bx,SEL_VIDEO
di4a:	lea	di,[bx+SYS_GDT]
	mov	ax,0FFFFh
	stosw				; limit
	mov	ax,bx
	shl	ax,4
	stosw				; base bits 15-0
	mov	ax,bx
	shr	ax,12			; AL = base bits 23-16
	mov	ah,ACC_DATA
	cmp	bx,SEL_ROM
	jb	di4b
	mov	ah,ACC_CODE
di4b:	stosw
	add	bx,SEL_IDSTEP
	jnc	di4a			; through F800h

	mov	di,SYS_PIDT		; pm_call's gates, for the test
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
; Switch to protected mode and back; we keep all of this only if the test
; succeeds, and otherwise, act as we do on an 8086.
;
	mov	bx,offset DEV:pm_test
	call	pm_call
	mov	es,cs:[sys_seg]
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	test	es:[SYS_VARS].SV_FLAGS,CPUF_PMOK
	jnz	di7
	mov	ah,0DDh			; output port: A20 off, no reset
	call	a20_set
	jmp	di9
di7:	call	a20_on			; (in case the ROM turned it off)
	mov	di,SYS_PIDT		; now the protected-mode gates
	sub	bx,bx
di6:	call	idt_default		; AX = handler, DH = access rights
	stosw
	mov	ax,SEL_CPUCODE
	stosw
	mov	al,0
	mov	ah,dh
	stosw
	sub	ax,ax
	stosw
	inc	bl
	jnz	di6
	cmp	es:[SYS_VARS].SV_TYPE,CPUTYPE_80386
	jb	di8			; no paging (see LIN_HI)
	call	pg_init
di8:	mov	[CPU_ARENA].OFF,SYS_PMBS
	mov	[CPU_ARENA].SEG,es	; CPU_ARENA -> the PMB table
	call	cpu_len
	mov	byte ptr ds:[DDINT_CPU],OP_JMPF
	mov	word ptr ds:[DDINT_CPU+1],offset DEV:cpu_entry
	mov	word ptr ds:[DDINT_CPU+3],cs
	pop	bx
	pop	es
	ASSUME	ES:NOTHING
	mov	es:[bx].DDPI_END.OFF,ax
	ret
ENDPROC	ddcpu_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cpu_len
;
; Without the 80386's features (see SV_TYPE), there are no V86 machines, so
; CPU$ keeps none of 386v86.asm's code.
;
; Inputs:
;	ES:SYS_VARS -> SYSVARS
;
; Outputs:
;	AX = length of CPU$ (what DDPI_END keeps)
;
DEFPROC	cpu_len
	mov	ax,offset DEV:v86_begin
	cmp	es:[SYS_VARS].SV_TYPE,CPUTYPE_80386
	jb	cl9
	mov	ax,offset DEV:ddcpu_init
cl9:	ret
ENDPROC	cpu_len

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_arena
;
; Builds the arena (the PMB table): everything below BIOS_END (the vectors,
; the BIOS data, and BASIC-DOS's low memory) and CPU$ are used (by the
; system), the rest of conventional memory is free, except for the system
; area (and on an 80386, the page tables below it; see LIN_HI), the rest of
; the first 1Mb is reserved, and any extended memory is free.
;
; Inputs:
;	AX = length of CPU$ (rounded up to a multiple of 16 here)
;	SI = Kb of extended memory (zero if none)
;	DS = BIOS
;	ES:SYS_VARS -> SYSVARS
;
; Modifies:
;	BX, CX, DX, DI
;
DEFPROC	init_arena
	push	ax
	add	ax,15
	and	al,0F0h
	mov	bp,ax			; BP = length of CPU$
	mov	di,SYS_PMBS
	sub	dx,dx
	mov	ax,offset BIOS_END + BIOS_DATA
	mov	bl,PMBTYPE_USED
	call	pmb_add			; 0 to BIOS_END
	add	ax,bp
	call	pmb_add			; CPU$
	mov	cx,es			; CX = segment of the system area
	cmp	es:[SYS_VARS].SV_TYPE,CPUTYPE_80386
	jb	ia0			; no paging (see LIN_HI)
	mov	ax,si
	add	ax,1024 + 4095
	rcr	ax,1
	shr	ax,11			; AX = # of page tables (one per 4Mb)
	mov	es:[SYS_VARS].SV_NPT,al
	inc	ax			; plus the page directory
	mov	ah,al
	mov	al,0			; AX = their paragraphs
	sub	cx,ax			; CX = segment of the page directory
	mov	ax,cx
	shl	ax,4
	mov	dx,cx
	shr	dx,12
	mov	es:[SYS_VARS].SV_PDIR.LOW,ax
	mov	es:[SYS_VARS].SV_PDIR.HIW,dx
ia0:	mov	ax,cx
	shl	ax,4
	mov	dx,cx
	shr	dx,12			; DX:AX = system area (or page directory)
	mov	bl,PMBTYPE_FREE
	call	pmb_add			; conventional memory below it
	mov	dx,es
	shr	dx,12
	inc	dx
	sub	ax,ax			; DX:0000h = end of the system area
	mov	bl,PMBTYPE_SYS
	call	pmb_add			; the page tables and the system area
	mov	bl,PMBTYPE_FREE
	test	byte ptr [MEMORY_SIZE],3Fh
	jz	ia1			; no memory above the system area
	mov	ax,[MEMORY_SIZE]
	call	kb_addr			; DX:AX = end of conventional memory
	call	pmb_add			; the rest of conventional memory
ia1:	mov	dx,10h
	sub	ax,ax
	mov	bl,PMBTYPE_RSVD
	call	pmb_add			; the rest of the first 1Mb
	test	si,si			; any extended memory?
	jz	ia9			; no
	mov	ax,si
	call	kb_addr
	add	dx,10h			; DX:AX = end of extended memory
	mov	bl,PMBTYPE_FREE
	call	pmb_add			; extended memory
ia9:	mov	es:[di-(size PMB)].PMB_SIG,PMBSIG_LAST
	sub	di,SYS_PMBS
	mov	cl,5
	shr	di,cl			; DI = number of PMBs
	mov	es:[SYS_VARS].SV_NPMBS,di
	pop	ax
	ret
ENDPROC	init_arena

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pg_init
;
; Builds the page directory and the page tables (see init_arena), which map
; the first SV_NPT * 4Mb of physical memory at C0000000h (see LIN_HI), and
; at linear address 0, too, for the switch (see pm_pmode).  Then adds LIN_HI
; to the bases of every descriptor in the GDT except the gates (none of the
; LDTs are in use yet), and to the GDTR's and IDTR's, after which CPU$ adds
; it to every base it creates (SV_LINHI).
;
; Inputs:
;	ES = system area
;
; Modifies:
;	AX, BX, CX, DX, DI, BP
;
DEFPROC	pg_init
	push	es
	mov	ax,es:[SYS_VARS].SV_PDIR.LOW
	mov	dx,es:[SYS_VARS].SV_PDIR.HIW
	mov	cl,es:[SYS_VARS].SV_NPT
	mov	ch,0
	mov	bp,cx			; BP = # of page tables
	shr	ax,4
	shl	dx,12
	or	ax,dx
	mov	es,ax			; ES:0 -> the page directory
	xchg	bx,ax			; BX = its segment
	sub	ax,ax
	mov	di,ax
	mov	cx,PG_SIZE / 2
	cld
	rep	stosw			; (no PDEs yet)
	lea	ax,[bx+(PG_SIZE SHR 4)]	; AX = segment of the first page table
	mov	cx,bp
	sub	bx,bx			; BX = PDE offset
	mov	dx,ax
	shr	dx,12
	shl	ax,4
	or	al,PG_USER		; DX:AX = its PDE
pi1:	mov	es:[bx],ax
	mov	es:[bx+2],dx
	mov	es:[bx+PDE_KERNEL],ax
	mov	es:[bx+PDE_KERNEL+2],dx
	add	bx,4
	add	ax,PG_SIZE
	adc	dx,0
	loop	pi1
	mov	cx,bp
	mov	bx,es
	mov	ax,PG_USER
	cwd				; DX:AX = the first PTE
pi2:	add	bx,PG_SIZE SHR 4
	mov	es,bx			; ES:0 -> the next page table
	sub	di,di
	push	cx
	mov	cx,PG_SIZE / 4
pi3:	stosw
	xchg	ax,dx
	stosw
	xchg	ax,dx
	add	ax,PG_SIZE
	adc	dx,0
	loop	pi3
	pop	cx
	loop	pi2
	pop	es
	mov	bx,SYS_GDT + (size DESC)
pi4:	call	pg_base			; the GDT's entries
	add	bx,size DESC
	cmp	bx,SYS_GDT + GDT_MAX * (size DESC)
	jb	pi4
	mov	bx,SYS_GDT + SEL_VIDEO
pi5:	call	pg_base			; and its identity selectors
	add	bx,SEL_IDSTEP
	jnc	pi5
	mov	byte ptr es:[SYS_VARS].SV_GDTR+5,LIN_HI
	mov	byte ptr es:[SYS_VARS].SV_PIDTR+5,LIN_HI
	mov	es:[SYS_VARS].SV_LINHI,LIN_HI
	ret
;
; pg_base adds LIN_HI to the base of the descriptor at ES:BX, if it's present
; and not a gate (whose "base" is a selector).
;
	DEFLBL	pg_base,near
	mov	al,es:[bx].DESC_ACC
	test	al,ACC_PRESENT		; is it present?
	jz	pb9			; no
	and	al,14h			; a system descriptor that's a gate?
	cmp	al,04h
	je	pb9			; yes
	add	byte ptr es:[bx].DESC_EXT+1,LIN_HI
pb9:	ret
ENDPROC	pg_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pmb_add
;
; Adds a PMB from the end of the last one (or 0) to DX:AX (a USED block is
; owned by the system).
;
; Inputs:
;	ES:DI -> next PMB, BL = PMBTYPE_*, DX:AX = end address
;
; Outputs:
;	ES:DI -> next PMB
;
DEFPROC	pmb_add
	push	ax
	push	cx
	push	dx
	push	si
	sub	cx,cx
	sub	si,si			; SI:CX = start (0 if first)
	cmp	di,SYS_PMBS
	je	pa1
	mov	cx,es:[di-(size PMB)].PMB_ADDR.LOW
	mov	si,es:[di-(size PMB)].PMB_ADDR.HIW
	add	cx,es:[di-(size PMB)].PMB_LEN.LOW
	adc	si,es:[di-(size PMB)].PMB_LEN.HIW
pa1:	mov	es:[di].PMB_SIG,PMBSIG_NEXT
	mov	es:[di].PMB_TYPE,bl
	mov	es:[di].PMB_ADDR.LOW,cx
	mov	es:[di].PMB_ADDR.HIW,si
	sub	ax,cx
	sbb	dx,si			; DX:AX = length
	mov	es:[di].PMB_LEN.LOW,ax
	mov	es:[di].PMB_LEN.HIW,dx
	sub	ax,ax
	mov	es:[di].PMB_SEL,ax
	mov	es:[di].PMB_NSEL,ax
	cmp	bl,PMBTYPE_USED
	jne	pa2
	mov	ax,MCBOWNER_SYSTEM
pa2:	mov	es:[di].PMB_OWNER,ax
	add	di,size PMB
	pop	si
	pop	dx
	pop	cx
	pop	ax
	ret
ENDPROC	pmb_add

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; a20_on
;
; Enables A20 with the 8042 keyboard controller, as on a PC AT.  Enter at
; a20_set with AH = the 8042 output port value instead (0DDh turns A20 off).
;
; Modifies:
;	AX
;
DEFPROC	a20_on
	mov	ah,0DFh			; output port: A20 on, no reset
	DEFLBL	a20_set,near
	call	kbc_wait
	mov	al,0D1h			; 8042 command: write output port
	out	64h,al
	call	kbc_wait
	mov	al,ah
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
; kb_addr
;
; Inputs:
;	AX = Kb
;
; Outputs:
;	DX:AX = bytes
;
; Modifies:
;	CL
;
DEFPROC	kb_addr
	mov	dx,ax
	mov	cl,10
	shl	ax,cl
	mov	cl,6
	shr	dx,cl
	ret
ENDPROC	kb_addr

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

	DEFLBL	cfg_cpu,byte
	db	6,"CPU=80"
	DEFLBL	cfg_memsize,byte
	db	8,"MEMSIZE="

	.286p
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
	mov	ds,cs:[sys_seg]
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
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	mov	[EDGE_CNT],offset pm_resume
	mov	[CRC_REG],cs
	lgdt	qword ptr ds:[SYS_VARS].SV_GDTR
	lidt	qword ptr ds:[SYS_VARS].SV_PIDTR
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
;
; For now, every IDT gate points here (see ddcpu_init).  Since interrupts are
; disabled, this can only be an exception, so we abandon the function and
; return to real mode (pm_resume restores the caller's stack).
;
	DEFLBL	pm_fault,near
	mov	ax,SEL_SYS
	mov	ds,ax
	cmp	ds:[SYS_VARS].SV_FLAGS,CPUTYPE_80386 SHL 6
	jb	pm3			; CPUF_HWTYPE is below an 80386's
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
	mov	ds,cs:[sys_seg]
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
; pm_test (called in protected mode by pm_call)
;
; Writes and reads back a pattern through ES (SEL_SYS), at the start of the
; system area (which is otherwise unused), and if that works, sets CPUF_PMOK.
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pm_test
	smsw	ax
	test	al,1			; are we in protected mode?
	jz	pt9			; no
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
; idt_default
;
; Returns the default gate for an entry in the protected-mode IDT: exceptions
; (00h-02h and 06h-0Fh) go to exc_stubs, hardware interrupts (70h-7Fh) to
; irq_stubs, and everything else (software interrupts) to sw_int.  Only INT 0
; (eg, FPU$ signals a divide error with it, since its frame is the same as a
; divide error's) and the software interrupts meant for programs (see idd2)
; have DPL 3 gates, so ring 3 code may not issue any BIOS interrupt.
;
; Inputs:
;	BL = IDT entry
;
; Outputs:
;	AX = offset of handler, DH = access rights
;
DEFPROC	idt_default
	mov	dh,ACC_INTGATE		; DPL 0, for exceptions and IRQs
	mov	al,bl
	sub	al,70h
	cmp	al,10h			; 70h-7Fh?
	jae	idd1			; no
	mov	ah,7			; each IRQ stub is 7 bytes
	mul	ah
	add	ax,offset DEV:irq_stubs
	ret
idd1:	mov	al,bl
	cmp	al,10h			; 00h-0Fh?
	jae	idd2			; no
	cmp	al,INT_BP
	jb	idd1a
	cmp	al,INT_UD		; 03h-05h are software interrupts
	jb	idd2
idd1a:	test	al,al			; INT 0?
	jnz	idd1b			; no
	mov	dh,ACC_INTGATE + ACC_DPL3
idd1b:	mov	ah,5			; each exception stub is 5 bytes
	mul	ah
	add	ax,offset DEV:exc_stubs
	ret
;
; Ring 3 code may issue only the software interrupts that are meant for it:
; breakpoint and overflow, DOS's vectors, the mouse, and the user vectors.
; Ring 0 code can issue any of them, but a BIOS function run for a ring 3
; program would trust whatever it was given (eg, a disk function computes its
; DMA address from a segment value), and a fault in the ROM stops the system.
;
idd2:	cmp	al,INT_PRTSC
	je	idd4			; DPL 0
	cmp	al,10h			; INT 03h or 04h?
	jb	idd3			; yes
	cmp	al,INT_MOUSE
	je	idd3
	mov	ah,al
	and	ah,0F0h
	cmp	ah,INT_DOSTERM		; DOS's vectors (20h-2Fh)?
	je	idd3			; yes
	cmp	al,R3_USERINT		; below the user vectors?
	jb	idd4			; yes
	cmp	al,R3_USERMAX		; above them?
	ja	idd4			; yes
idd3:	mov	dh,ACC_INTGATE + ACC_DPL3
idd4:	mov	ax,offset DEV:sw_int
	ret
ENDPROC	idt_default

	DEFLBL	gdt_init,byte
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_SYS
	DESC	<0,SYS_LDTTOP,0,ACC_LDT,0>		; SEL_LDTD
	DESC	<0FFFFh,0,0,ACC_CODE,0>			; SEL_CPUCODE
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_LOW
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_STACK
	DESC	<0FFFFh,0,0,ACC_DATA,0>			; SEL_TMP
	DESC	<offset DEV:cpu_entry,SEL_CPUCODE,0,ACC_CALLGATE,0>
	DESC	<0FFFFh,BIOS_DATA,0,ACC_DATA,0>		; SEL_BIOS
	DESC	<0,0,0,0,0>				; (unused)
	DESC	<0FFFFh,BIOS_DATA+100h,0,ACC_CODE,0>	; SEL_DDINT
	DESC	<INT_DOSCALL5*4+4,0,0,ACC_CODE,0>	; SEL_C5CODE
	DESC	<INT_DOSCALL5*4,SEL_C5CODE,0,ACC_CALLGATE+ACC_DPL3,0>
	DESC	<TSS_LEN-1,SYS_TSS,0,ACC_TSS,0>		; SEL_TSS
	DEFLBL	gdt_init_end,byte
	ASSERT	<offset gdt_init_end - offset gdt_init>,EQ,<(GDT_FIXED-1)*8>


CODE	ends

	end
