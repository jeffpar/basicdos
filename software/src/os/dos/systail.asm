;
; BASIC-DOS System Initialization Tail
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This module is linked last, after the rest of sysinit (SYSINIT, SYSHELP, and
; DRVINIT), so that it holds only what sysinit still needs while it loads the
; SHELLs: by then, sysinit has given back everything before sysinit_tail
; (except its stack), so that loading a SHELL can use that memory too (eg, on
; a 64K machine).
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

DOS	segment word public 'CODE'

	EXTBYTE	<def_drive,scb_locked,prog_user,r3_stubs>
	EXTWORD	<scb_active,ivt_save,sprintf_hook,r3_code,r3_stseg,r3_vsel>
	EXTWORD	<FUNCTBL,UTILTBL,r3_ksel>
	EXTLONG	<scb_table,clk_ptr>
	EXTNEAR	<dos_leave,int_enter,int_leave,dos_fault,sysinit_start>
	EXTNEAR	<r3_sprintf,r3_free,r3_realloc,init_fpu,utl_alias,utl_mapseg>
	EXTNEAR	<r3_term,r3_return,r3_uterm,r3_exec,r3_pspset>
	EXTNEAR	<r3_pspcopy,r3_pspnew,r3_uload,r3_read,r3_write>
	EXTNEAR	<r3_sread,r3_swrite,r3_rread,r3_rwrite,r3_rbread,r3_rbwrite>

	ASSUME	CS:DOS, DS:DOS, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sysinit_tail
;
; For each SHELL definition, load the corresponding file into the next
; available SCB.  The first time through, CFG_SHELL is used as a fallback,
; so even if there are no SHELL definitions, at least one will be loaded.
;
; None of sysinit's code before this point will run again, so first we move
; our stack up to sysinit_tail and give back the memory below it (see
; init_free), so that the SHELLs can use that memory too.
;
; Entry:
;	DS = our data (see sysinit_high)
;
DEFPROC	sysinit_tail,far
	mov	sp,offset sysinit_tail
	mov	ax,offset sysinit_tail - 200h
	call	init_free

	sub	sp,size SPB		; alloc SPB from the stack

	mov	es,[dos_seg]
	ASSUME	ES:DOS
;
; Lock the SCB until we're done: once a SHELL has been started, a yield in
; any DOS call we make (eg, a deferred yield on a full unlock) would switch to
; it, saving our stack in the active SCB, which could later resume it after
; we're gone.  Waits still end normally, since locked yields simply return.
;
	inc	es:[scb_locked]		; LOCK_SCB (see the end of sysinit)
	mov	al,es:[def_drive]
	mov	[boot_drive],al
	sub	dx,dx			; DX = SCB load count
	mov	bx,offset SHELL_FILE	; BX = default shell
si15:	mov	si,offset CFG_SHELL
	call	find_cfg		; look for "SHELL="
	jc	si16			; not found
	mov	bx,di
si16:	test	bx,bx			; do we still have a default?
	jnz	si16b			; yes
	jmp	si20			; no, done loading
;
; A SHELL whose file includes a drive (eg, "C:/COMMAND.COM") starts on that
; drive; otherwise, it starts on the boot drive (see init_scb).
;
si16b:	mov	es,[dos_seg]
	ASSUME	ES:DOS
	mov	al,[boot_drive]
	cmp	byte ptr [bx+1],':'	; does the SHELL specify a drive?
	jne	si16c			; no
	mov	al,[bx]
	and	al,0DFh			; upper-case the drive letter
	sub	al,'A'			; AL = drive #
si16c:	mov	es:[def_drive],al
;
; Note that during the LOAD process, the SCB is locked and active, so that
; the program file can be opened and read using the SCB's PSP.  It's unlocked
; when the load finishes, but it won't start running until after START is set.
;
	push	ss
	pop	es
	mov	di,sp			; ES:DI -> SPB on stack
	mov	ax,-1
	stosw				; SPB_ENVSEG <- -1
	xchg	ax,bx
	stosw				; SPB_CMDLINE.OFF <- BX
	mov	ax,ds
	stosw				; SPB_CMDLINE.OFF <- DS
	xchg	ax,bx			; AX = -1 again (aka SFH_NONE)
	stosb				; SPB_SFHIN  <- SFH_NONE
	stosb				; SPB_SFHOUT <- SFH_NONE
	stosb				; SPB_SFHERR <- SFH_NONE
	stosb				; SPB_SFHAUX <- SFH_NONE
	stosb				; SPB_SFHPRN <- SFH_NONE
	mov	bx,sp			; ES:BX -> SPB on stack
	mov	cx,0FFh			; CL = invalid SCB # (for errors),
					; CH = no programs follow
;
; Skip the SHELL of a CONSOLE that couldn't be opened (see si11), and reject
; any SHELL beyond the last console, since its session would have none.
;
	shr	[con_fails].SEG,1
	rcr	[con_fails].OFF,1
	jc	si17			; its CONSOLE failed
	mov	ax,ERR_NOSESSION
	cmp	dl,[con_count]
	jae	si18
	DOSUTIL	LOAD			; load specified SHELL into an SCB
	jc	si18
	push	ax
	DOSUTIL	START			; CL = SCB # (from the LOAD call)
	pop	ax			; must be valid, so no error checking
	inc	dx
	test	ax,ax			; any program data to cache?
	jz	si17			; no
	mov	si,bx			; SI = its offset
	mov	bx,di			; BX = its segment (or selector)
	call	cache_free		; free the previous alias, if any
	cmp	es:[prog_user],0	; ring 3 programs?
	je	si16a			; no
;
; A ring 3 program's selectors are in its session's LDT, which isn't active
; while another session's SHELL loads (see scb_load), so cache_int21 needs a
; GDT alias of the data, which we make with the loaded session's LDT active.
;
	push	ax
	push	dx
	mov	al,cl			; AL = the loaded session #
	mov	ah,CPU_SETLDT
	call	far ptr DDINT_CPU	; make its LDT active
	sub	al,al			; AL = MEMF_* for a DPL 0 data alias
	mov	ah,CPU_ALIAS
	call	far ptr DDINT_CPU	; AX = an alias of the selector in BX
	pop	dx
	xchg	bx,ax			; BX = the alias (carry unchanged)
	pop	ax
	jnc	si16a
	sub	si,si			; no alias, so no cache
si16a:	mov	[cbCacheData],ax
	mov	[pCacheData].OFF,si
	mov	[pCacheData].SEG,bx

si17:	sub	bx,bx			; no default shell now
	jmp	si15

si18:	mov	si,sp			; SS:SI -> SPB
	mov	si,ss:[si].SPB_CMDLINE.OFF
;
; Print the error on the console of the session we tried to load (CL), if
; any; since there's no PSP yet, PRINTF would always use SFH 1 (ie, the first
; session's console), so we use HPRINTF with that session's SFHOUT instead.
;
	push	ax			; save error code
	mov	al,size SCB
	mul	cl
	push	es
	mov	es,[dos_seg]
	ASSUME	ES:DOS
	add	ax,es:[scb_table].OFF
	xchg	bx,ax			; BX -> SCB
	mov	al,1			; default to SFH 1
	cmp	bx,es:[scb_table].SEG	; valid SCB?
	jae	$+6			; no
	mov	al,es:[bx].SCB_SFHOUT	; (4 bytes)
	pop	es
	ASSUME	ES:NOTHING
	xchg	bx,ax			; BL = SFH
	pop	ax			; AX = error code
;
; The only ERR_BADFORMAT that loading a SHELL returns is load_command's
; "tail too long" error, which leaves the whole SHELL line intact, so show
; the start of it.
;
	cmp	ax,ERR_BADFORMAT	; SHELL line too long?
	jne	si19			; no
	ECCALL	DOS_UTL_HPRINTF,<"SHELL line too long: %.40s...">,<13,10>,ax,si
	jmp	si17
si19:	ECCALL	DOS_UTL_HPRINTF,<"Unable to load %s">,<13,10>,ax,si
	jmp	si17
;
; Although it may appear every SCB was started immediately after loading,
; nothing can ACTUALLY run until we obtain access to the CLOCK$ device and
; re-vector all the hardware interrupt handlers that drive our scheduler.
;
si20:	add	sp,size SPB		; free SPB on the stack
					; (somewhat moot, but let's stay tidy)
	call	cache_free		; and the cache data's alias, if any
	mov	cx,dx			; CX = SCB load count
	lds	dx,[pCacheInt21]	; restore INT 21h vector
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 21h
	int	21h
	push	ss
	pop	ds

	test	cx,cx			; if no SCBs loaded, that's not good
	jnz	si20a
	mov	dx,offset HALTED+2	; (the errors were reported; see si18)
	jmp	fe1
si20a:
;
; Utility functions like SLEEP need access to the clock device, so we save
; its address in clk_ptr.  While we could open the device normally and obtain
; a system file handle, that would require the utility functions to use SFB
; interfaces (sfb_get, sfb_read, etc) with no benefit.
;
	mov	dx,offset CLK_DEVICE
	DOSUTIL	GETDEV
	jnc	$+5
	jmp	open_error
	mov	ds,[dos_seg]
	mov	[clk_ptr].OFF,di
	mov	[clk_ptr].SEG,es
;
; "Revector" DDINT_ENTER and DDINT_LEAVE to int_enter and int_leave.
;
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	cli
	mov	di,offset DDINT_ENTER + DDINT_BIAS
	mov	ax,offset int_enter
	call	set_ddint
	mov	ax,offset int_leave
	call	set_ddint
	ASSUME	ES:NOTHING
;
; Now that every SHELL has been loaded, free the memory containing our code
; and stack (which CPU$ merges with the free block before it, if any).
; Interrupts are off, and nothing will allocate memory until we're gone.
;
	sub	ax,ax
	call	init_free
;
; Save the vectors that programs commonly hook directly (00h, 01h, 03h, 08h,
; 09h, 1Bh, and 1Ch), now that the drivers have hooked theirs (see
; psp_restvec).
;
	mov	si,offset ivt_save	; DS:SI -> vector #s and saved vectors
iv1:	lodsb				; AL = vector #
	test	al,al			; end of the list (-1)?
	js	iv2			; yes
	call	far ptr DDINT_GETVEC	; DX:CX = vector
	mov	[si].OFF,cx
	mov	[si].SEG,dx
	add	si,4
	jmp	iv1
iv2:
;
; Activate and start running the first session.  We must mimic scb_switch
; rather than calling it, because we're not switching SCBs (sysinit is not
; a session).
;
; The end of sysinit used to just turn on interrupts and spin, knowing that
; the first scb_yield would never return here, but that required us to also
; zero scb_active and include "null SCB" tests in scb_yield and scb_switch;
; this approach eliminates the need for those special tests.
;
; Interrupts are still off, so we can release our SCB lock (see si15) without
; scb_release; any deferred yield will occur on the session's next unlock.
;
	dec	[scb_locked]
	mov	bx,[scb_table].OFF	; BX -> the first SCB
	mov	[scb_active],bx		; make it active (for consistency)
;
; With a ring 3 first program, make its session's LDT active and set its ring
; 0 stack now (as scb_switch would), since this first start doesn't go through
; scb_switch, and the processor needs the stack the moment the program's first
; interrupt arrives.  We use CPU$ directly, rather than near calls to r3_setldt
; and r3_sp0, which aren't in this block (see sysinit_high).
;
	cmp	[prog_user],0		; ring 3 programs?
	je	stt1			; no
	mov	al,[bx].SCB_NUM		; DS:BX -> the first SCB
	push	ax
	mov	ah,CPU_SETLDT
	call	far ptr DDINT_CPU	; load the first session's LDT
	pop	ax
	mov	cx,[bx].SCB_SP0
	mov	dx,[r3_stseg]		; DX:CX = the session's ring 0 stack
	mov	ah,CPU_SETSTACK
	call	far ptr DDINT_CPU
stt1:	mov	ss,[bx].SCB_STACK.SEG
	mov	sp,[bx].SCB_STACK.OFF
	push	cs:[dos_code]		; (the kernel's code segment, not DS)
	mov	ax,offset dos_leave
	push	ax
	ret				; we let dos_leave turn interrupts on
ENDPROC	sysinit_tail

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fatal_error (print halt message and halt)
;
; Inputs:
;	None
;
; Outputs:
;	None (system halted)
;
	DEFLBL	fatal_error,near
	mov	dx,offset HALTED
fe1:	mov	ah,DOS_TTY_PRINT
	int	21h
	sti				; (so that a COM console can finish)
	jmp	$			; "halt"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_ddint
;
; Inputs:
;	AX = offset of the target in the kernel (see dos_code)
;	ES:DI -> where to store a far jump to it
;
; Outputs:
;	ES:DI -> just past the far jump
;
; Modifies:
;	AX, DI
;
DEFPROC	set_ddint
	push	ax
	mov	al,OP_JMPF
	stosb
	pop	ax
	stosw
	mov	ax,cs:[dos_code]
	stosw
	ret
ENDPROC	set_ddint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_fault
;
; In protected mode, has CPU$ give us any exception that it can't handle (see
; dos_fault), before any DEVICE= driver (eg, DEBUG.COM) can take them, so that
; a debugger can pass them on to us.  Otherwise, exceptions go through the
; vectors, so the kernel doesn't need dos_fault or the NE loader that follows
; it (see neload.asm), and its resident code ends at dos_fault.
;
; Outputs:
;	AX = offset of the end of the kernel's resident code
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	set_fault
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; AH = CPUF_* flags
	test	ah,CPUF_PM		; protected mode?
	mov	ax,offset dos_fault
	jnz	sf0			; yes
	jmp	sf9			; no
sf0:	mov	[UTILTBL + DOS_UTL_ALIAS * 2],offset utl_alias
	mov	[UTILTBL + DOS_UTL_MAPSEG * 2],offset utl_mapseg
	xchg	cx,ax
	mov	dx,cs:[dos_code]	; DX:CX -> dos_fault
	mov	ah,CPU_SETFAULT
	call	far ptr DDINT_CPU
;
; Programs run at ring 3 (see r3supp.asm), unless a "RING=0" line keeps them
; at ring 0.
;
	push	si
	push	di
	mov	si,offset CFG_RING
	call	find_cfg		; look for "RING="
	jc	sf7			; none, so ring 3
	cmp	byte ptr ss:[di],'0'	; RING=0? (find_cfg's data is in SS)
	jne	sf7			; no
	jmp	sf8			; yes
sf7:	mov	[prog_user],MEMF_USER
	mov	[sprintf_hook],offset r3_sprintf
	mov	si,offset r3_funcs
sf7c:	lods	word ptr cs:[si]
	xchg	di,ax			; DI -> a function's table entry
	lods	word ptr cs:[si]
	mov	[di],ax			; (its ring 3 version)
	cmp	si,offset r3_fend
	jb	sf7c
	push	bx
	mov	bx,cs:[dos_code]
	mov	[r3_ksel],bx
	mov	ax,(CPU_ALIAS SHL 8) OR MEMF_CODE OR MEMF_RDONLY OR MEMF_USER
	call	far ptr DDINT_CPU
	or	al,3
	mov	[r3_code],ax		; (see r3_stub)
;
; So that a fault in the kernel reaches dos_fault (see r3_end), dos_fault gets
; a code selector of its own, since CPU$ won't call a fault handler for a
; fault in the handler's own code segment; a fault in dos_fault itself is
; still fatal.
;
	mov	ax,(CPU_ALIAS SHL 8) OR MEMF_CODE
	call	far ptr DDINT_CPU	; AX = another selector for the kernel
	pop	bx
	jc	sf7a			; (none, so kernel faults stay fatal)
	xchg	dx,ax
	mov	cx,offset dos_fault	; DX:CX -> dos_fault
	mov	ah,CPU_SETFAULT
	call	far ptr DDINT_CPU
sf7a:
;
; The vector stubs (see RVEC) get a readable code selector of their own, since
; a ring 3 program gets their address in ES:BX, and r3_code (execute-only, for
; the whole kernel) can't be loaded into ES.
;
	push	bx
	mov	bx,cs:[dos_code]
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	far ptr DDINT_CPU	; DX:CX = the kernel's base
	pop	bx
	add	cx,offset r3_stubs
	adc	dx,0			; DX:CX -> r3_stubs
	sub	si,si
	mov	di,R3_RVECS * 2		; SI:DI = their length
	mov	ax,(CPU_MAP SHL 8) OR MEMF_CODE OR MEMF_USER
	call	far ptr DDINT_CPU	; AX = their selector
	jc	sf8			; (none, so no stubs)
	or	al,3
	mov	[r3_vsel],ax
sf8:	pop	di
	pop	si
	mov	ax,offset sysinit_start
sf9:	ret
ENDPROC	set_fault
;
; The DOS functions that have versions for ring 3 programs (see r3prog.asm), as
; the address of each one's table entry and its ring 3 version.
;
	DEFLBL	r3_funcs,word
	dw	FUNCTBL + DOS_MEM_FREE * 2,r3_free
	dw	FUNCTBL + DOS_MEM_REALLOC * 2,r3_realloc
	dw	FUNCTBL + DOS_PSP_TERM * 2,r3_term
	dw	FUNCTBL + DOS_PSP_RETURN * 2,r3_return
	dw	FUNCTBL + (DOS_PSP_EXEC SHR 8) * 2,r3_exec
	dw	FUNCTBL + DOS_PSP_SET * 2,r3_pspset
	dw	FUNCTBL + DOS_PSP_COPY * 2,r3_pspcopy
	dw	FUNCTBL + DOS_PSP_CREATE * 2,r3_pspnew
	dw	FUNCTBL + DOS_HDL_READ * 2,r3_read
	dw	FUNCTBL + DOS_HDL_WRITE * 2,r3_write
	dw	FUNCTBL + DOS_FCB_SREAD * 2,r3_sread
	dw	FUNCTBL + DOS_FCB_SWRITE * 2,r3_swrite
	dw	FUNCTBL + DOS_FCB_RREAD * 2,r3_rread
	dw	FUNCTBL + DOS_FCB_RWRITE * 2,r3_rwrite
	dw	FUNCTBL + DOS_FCB_RBREAD * 2,r3_rbread
	dw	FUNCTBL + DOS_FCB_RBWRITE * 2,r3_rbwrite
	dw	UTILTBL + DOS_UTL_TERM * 2,r3_uterm
	dw	UTILTBL + DOS_UTL_LOAD * 2,r3_uload
	DEFLBL	r3_fend,word

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_sess
;
; Allocates what every session needs one of: with programs at ring 3 (see
; set_fault), a ring 0 stack (see r3_top), and then an FPU state (see
; init_fpu).  If there's no room for the stacks, programs run at ring 0.
;
; Inputs:
;	AL = # of sessions, DH = FPU type (FPUTYPE_*, from IOCTL_GETFPU)
;	ES = DOS
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
	ASSUME	ES:DOS
DEFPROC	init_sess
	cmp	es:[prog_user],0	; ring 3 programs?
	je	is9			; no
	push	ax
	push	dx
	mov	ah,R3_STACK_SIZE SHR 8
	mul	ah
	mov	ah,al
	mov	al,0
	xchg	di,ax
	sub	si,si			; SI:DI = sessions * R3_STACK_SIZE
	mov	bx,MCBOWNER_SYSTEM
	mov	ax,CPU_ALLOC SHL 8	; AL = 0 (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = selector
	jnc	is1
	sub	ax,ax
	mov	es:[prog_user],al	; no room, so programs run at ring 0
is1:	mov	es:[r3_stseg],ax
	pop	dx
	pop	ax
is9:	jmp	init_fpu
ENDPROC	init_sess
	ASSUME	ES:NOTHING

;
; Initialization variables (these follow sysinit_tail, since they're used
; until we're done).
;
	DEFWORD	dos_seg
	DEFWORD	dos_code		; kernel's code segment (or selector)
	DEFWORD	cfg_data
	DEFWORD	cfg_size

	DEFPTR	pCacheInt21
	DEFPTR	pCacheData
	DEFWORD	cbCacheData
	DEFPTR	pCacheFile
	DEFPTR	pCacheActive
	DEFWORD	cbCacheActive

	DEFLONG	con_fails,0		; bits for CONSOLE lines that failed
	DEFBYTE	con_count,1		; number of consoles opened
	DEFBYTE	boot_drive		; default drive for each SHELL

CFG_SHELL	db	6,"SHELL="
CFG_RING	db	5,"RING="
CLK_DEVICE	db	"CLOCK$",0
SHELL_FILE	db	"COMMAND.COM",0	; default SHELL file
HALTED		db	13,10,"System halted",13,10,'$'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_cfg
;
; Search for length-prefixed string at CS:SI in CFG_FILE, and if found,
; set DI to 1st character after match.
;
; Outputs:
;	Carry clear on success (DI -> 1st character after match)
;	Carry set on failure (AX = default value following string at SI)
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	find_cfg
	ASSUME	DS:NOTHING, ES:NOTHING
	push	bx
	push	cx
	push	dx
	push	es
	push	ss			; (our data; see sysinit_high)
	pop	es
	ASSUME	ES:DOS
	mov	bx,si
	mov	di,[cfg_data]		; DI points to CFG_FILE data
	mov	dx,di
	add	dx,[cfg_size]		; DX points to end of CFG_FILE data
fc1:	lods	byte ptr cs:[si]	; 1st byte at CS:SI is length
	cbw
	xchg	cx,ax			; CX = length of string to find
	cli				; avoid 8086 string interrupt errata
	repe	cmps byte ptr cs:[si],es:[di]
	sti
	jne	fc2
	mov	es:[di-1],cl		; zap the CFG match to prevent reuse
	jmp	short fc9		; found it!
fc2:	add	si,cx			; move SI forward to the minimum value
	mov	al,0			; (CR and LF are now nulls)
	mov	cx,dx
	sub	cx,di			; CX = bytes left to search
	jb	fc8			; ran out
	repne	scasb
	stc
	jne	fc8			; couldn't find another line
	repe	scasb			; skip any more nulls (eg, CR+LF)
	stc
	je	fc8			; ran out
	dec	di			; DI -> 1st character of next line
	mov	si,bx
	jmp	fc1
fc8:	mov	ax,cs:[si]		; return the minimum value at SI
fc9:	pop	es
	ASSUME	ES:NOTHING
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	find_cfg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; def_sessions
;
; Without a "SESSIONS=" line, there's a session for each console (each "CON="
; line in CFG_FILE, or just one without any), plus 4 for the filters of
; pipelines, unless the PIPE$ driver isn't loaded (eg, it unloads itself with
; 64K of memory or less, or SKIP=PIPE$).  We can't use find_cfg, because it
; zaps each match, and the consoles haven't been opened yet.
;
; Outputs:
;	AX = default number of sessions
;
; Modifies:
;	AX, DI
;
DEFPROC	def_sessions
	ASSUME	DS:NOTHING, ES:NOTHING
	push	bx
	push	cx
	push	dx
	push	es
	push	ss			; (our data; see sysinit_high)
	pop	es
	ASSUME	ES:DOS
	mov	di,[cfg_data]		; DI points to CFG_FILE data
	mov	dx,di
	add	dx,[cfg_size]		; DX points to end of CFG_FILE data
	sub	bx,bx			; BX = number of consoles
ds1:	cmp	word ptr es:[di],4F43h	; does this line start with "CO"?
	jne	ds2			; no
	cmp	word ptr es:[di+2],3D4Eh; and "N="?
	jne	ds2			; no
	inc	bx
ds2:	mov	al,0			; (CR and LF are now nulls)
	mov	cx,dx
	sub	cx,di			; CX = bytes left to search
	jb	ds3			; ran out
	repne	scasb
	jne	ds3			; couldn't find another line
	repe	scasb			; skip any more nulls (eg, CR+LF)
	je	ds3			; ran out
	dec	di			; DI -> 1st character of next line
	jmp	ds1
ds3:	cmp	bx,1			; no consoles?
	adc	bx,0			; then there's still the default one
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING
ds4:	cmp	di,-1			; end of device list?
	je	ds8			; yes, so PIPE$ isn't loaded
	cmp	word ptr es:[di].DDH_NAME,4950h
	jne	ds5			; it doesn't start with "PI"
	cmp	word ptr es:[di].DDH_NAME+2,4550h
	je	ds7			; and it continues with "PE"
ds5:	les	di,es:[di]		; on to the next device
	jmp	ds4
ds7:	add	bx,4
ds8:	xchg	ax,bx			; AX = number of sessions
	cmp	ax,MAX_SESSIONS		; more than the limit?
	jbe	ds9			; no
	mov	ax,MAX_SESSIONS
ds9:	pop	es
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	def_sessions

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cache_int21
;
; The sole purpose of this function is to intercept OPEN and READ requests
; that occur during our DOSUTIL LOAD operations, which we also know will be
; completely sequential (and therefore our caching logic can be very simple).
;
; This allows us to preload multiple copies of COMMAND.COM into memory without
; having to reread the file from disk every time.  Since we run on the caller's
; stack, we get our data segment (or selector) from init_data.
;
; Inputs:
;	AH = DOS function #
;
; Outputs:
;	Varies (function-specific)
;
DEFPROC	cache_int21,FAR
	cmp	ah,DOS_HDL_OPEN
	jne	ci2

	push	ax
	push	cx
	push	si
	push	di
	push	es
	mov	si,dx
	DOSUTIL	STRLEN			; AX = length of string at DS:SI
	xchg	cx,ax			; CX = length
	les	di,[pCacheFile]		; ES:DI -> previous filename, if any
	sub	ax,ax			; AX = 0 (no active cache data)
	test	di,di			; is there a previous filename?
	jz	ci1			; no
	repe	cmpsb			; does previous filename match current?
	jne	ci1			; no
	mov	ax,[pCacheData].OFF	; yes, init active cache data
ci1:	mov	es,cs:[init_data]
	ASSUME	ES:DOS
	mov	[pCacheActive].OFF,ax
	mov	ax,[pCacheData].SEG
	mov	[pCacheActive].SEG,ax
	mov	ax,[cbCacheData]
	mov	[cbCacheActive],ax
	mov	[pCacheFile].OFF,dx	; in any case, remember this filename
	mov	[pCacheFile].SEG,ds
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	pop	si
	pop	cx
	pop	ax
	jmp	ci9

ci2:	cmp	ah,DOS_HDL_SEEK
	jne	ci4
	cmp	[pCacheActive].OFF,0	; is the cached file open?
	je	ci9			; no
;
; Only SEEK_BEG and SEEK_END are supported (with offsets in DX), since those
; are the only methods load_program uses.
;
	push	bx
	push	es
	mov	es,cs:[init_data]
	ASSUME	ES:DOS
	mov	bx,dx			; BX = offset
	sub	al,SEEK_END
	cmp	al,1			; carry set if SEEK_END
	sbb	ax,ax
	and	ax,[cbCacheData]
	add	bx,ax			; BX = new position
	mov	ax,[pCacheData].OFF
	add	ax,bx
	mov	[pCacheActive].OFF,ax
	mov	ax,[cbCacheData]
	sub	ax,bx
	mov	[cbCacheActive],ax
	xchg	ax,bx			; DX:AX = new position
	sub	dx,dx
	pop	es
	ASSUME	ES:NOTHING
	pop	bx
	jmp	short ci10		; (carry is clear)

ci4:	cmp	ah,DOS_HDL_READ
	jne	ci9

	push	cx
	push	si
	push	di
	push	ds
	push	es
	push	ds
	pop	es
	mov	di,dx			; ES:DI -> destination
	lds	si,[pCacheActive]	; DS:SI -> source data
	test	si,si			; does any source data exist?
	stc
	jz	ci8			; no
	mov	ax,cx			; AX = # bytes to copy
	cmp	ax,[cbCacheActive]	; do we have as much data as requested?
	jbe	ci3			; yes
	mov	ax,[cbCacheActive]	; no
ci3:	mov	cx,ax
	rep	movsb
	mov	es,cs:[init_data]
	ASSUME	ES:DOS
	sub	[cbCacheActive],ax
	add	[pCacheActive].OFF,ax
	ASSERT	NC
	ASSUME	ES:NOTHING
ci8:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	cx
	jnc	ci10

ci9:	pushf
	call	[pCacheInt21]
ci10:	ret	2
ENDPROC	cache_int21

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; open_error (print an open error and halt)
;
; Inputs:
;	AX = error code
;	DX -> device setting (eg, "COM2:9600,N,8,1")
;
	DEFLBL	open_error,near
	EPRINTF	<"Unable to open %s">,,ax,dx
	jmp	fatal_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cache_free (free the cache data's GDT alias, if any; see si16a)
;
; Outputs:
;	ES = DOS data segment (all other registers are preserved, since
;	the SHELL loop still needs AX, CX, and DX, which CPU_UNMAP changes)
;
	DEFLBL	cache_free,near
	mov	es,[dos_seg]
	cmp	es:[prog_user],0	; ring 3 programs (so an alias)?
	je	cf9			; no
	push	ax
	push	bx
	push	cx
	push	dx
	mov	bx,[pCacheData].SEG
	test	bx,bx			; is there one yet?
	jz	cf8			; no
	sub	cx,cx			; CX = 0 (one selector)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU	; free it
cf8:	pop	dx
	pop	cx
	pop	bx
	pop	ax
cf9:	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_free
;
; Frees the block that move_init allocated, or with AX nonzero, gives back
; only the memory before offset AX (rounded down to a paragraph), by freeing
; it and claiming the rest again.  This runs in that block (SS = its data).
;
; Inputs:
;	AX = new offset of the start (or zero)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	init_free
	push	ax
	mov	cx,cs:[init_addr].LOW
	mov	dx,cs:[init_addr].HIW
	mov	ah,CPU_FREE
	call	far ptr DDINT_CPU
	ASSERT	NC
	pop	ax
	test	ax,ax
	jz	if9
	and	al,0F0h
	sub	ax,cs:[init_base]	; AX = bytes to give back
	add	ss:[init_base],ax
	sub	ss:[init_len],ax
	add	ss:[init_addr].LOW,ax
	adc	ss:[init_addr].HIW,0
	mov	cx,ss:[init_addr].LOW
	mov	dx,ss:[init_addr].HIW
	sub	si,si
	mov	di,ss:[init_len]	; SI:DI = length
	mov	bx,MCBOWNER_SYSTEM
	mov	ax,(CPU_ALLOC SHL 8) OR MEMF_AT OR MEMF_NONE
	call	far ptr DDINT_CPU
	ASSERT	NC
if9:	ret
ENDPROC	init_free

	DEFWORD	init_base,0		; offset of the start of our block
	DEFWORD	init_len,0		; and its length
	DEFLONG	init_addr,0		; and its address
	DEFWORD	init_data,0		; and its data segment (or selector)

	DEFLBL	sysinit_end

DOS	ends

	end
