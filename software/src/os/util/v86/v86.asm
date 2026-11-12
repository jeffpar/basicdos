;
; BASIC-DOS V86 Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: V86 [PATH$="path"[:]] [/M:size] [program [arguments]]
;
; Runs a real-mode program (COMMAND.COM if none is given; a name without a
; drive or directory is also looked for in each directory of the PATH$ given
; before it, as START gives one, or else of our environment's PATH) in a V86
; machine (see v86.inc) with size K of memory (640 if none is given),
; which needs an 80386 in protected mode (CPU_TYPE 3),
; and provides the DOS services that its programs ask for: the ones that
; involve the machine itself (eg, its vectors, its PSPs, its memory, and
; running programs) here, and the rest by passing them on to BASIC-DOS (with
; selectors for the machine's DS and ES).  See v86host.inc for the machine's
; memory, and V86DOS.ASM, V86PROC.ASM, and V86UTIL.ASM for the rest.
;
	include	v86host.inc

CODE    SEGMENT word public 'CODE'

	EXTBYTE	<VARS>
	EXTNEAR	<int21,int2b,load_prog,start_prog,mem_init,mem_alloc>
	EXTNEAR	<term_prog,pft_save>
;
; Only the CPU check (and its message) must run on an 8086; everything after
; it runs on an 80386.
;
	.286c

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	sub	bx,bx
	mov	si,BIOS_DATA + offset CPU_TYPE
	DOSUTIL	MAPSEG,1		; AL = CPU_TYPE (or in real mode, 0)
	cmp	al,CPUTYPE_80386	; protected mode with 80386 features?
	je	m1			; yes
	PRINTF	<"V86 mode not available",13,10>
	jmp	m8a
;
; Get the program's name, and its arguments, which follow it; the only switch
; we accept before the name is /M:size (the machine's memory, in K).  A
; PATH$="..." before the name (as START gives us, with a colon after it, as
; a SHELL line's has) is the path to search, whose ending quote becomes a
; null; otherwise, our environment's PATH (if any) is.
;
m1:	mov	[our_ds],ds		; (for v86_ctrlc)
	mov	si,PSP_CMDTAIL + 1
m1a:	mov	ax,DOS_MSC_GETSWC
	int	21h			; DL = switch character
m1f:	lodsb
	cmp	al,' '			; skip leading whitespace
	je	m1f
	cmp	al,9
	je	m1f
	dec	si
	mov	bx,si
	cmp	al,dl			; a switch?
	jne	m1g			; no
	inc	si
	lodsw
	and	al,NOT 20h		; (upper-case)
	cmp	ax,(':' SHL 8) OR 'M'
	jne	m1e
	DOSUTIL	ATOI32D			; DX:AX = size, SI -> what follows it
	jc	m1e			; no digits
	cmp	byte ptr [si],' '	; whitespace (or a CR) after it?
	ja	m1e			; no
;
; The size must be at least V86_MINK (so that there's an arena, which
; mem_init assumes) and at most V86_MAXK (the most that a machine can have).
;
	sub	ax,V86_MINK
	sbb	dx,0
	jnz	m1e			; too small (or much too large)
	cmp	ax,V86_MAXK - V86_MINK
	ja	m1e			; too large
	add	ax,V86_MINK
	shl	ax,6			; AX = size in paragraphs
	mov	[mach_paras],ax
	mov	dx,ax
	shl	ax,4
	shr	dx,12			; DX:AX = size in bytes
	mov	[mach_top].OFF,ax
	mov	[mach_top].SEG,dx
	jmp	m1a
m1g:
	mov	di,offset PATH_STR
	mov	cx,PATH_STR_LEN
	repe	cmpsb			; a PATH$?
	jne	m1c			; no
	mov	[path_arg],si
m1b:	lodsb
	cmp	al,CHR_RETURN
	je	m1e			; it has no ending quote
	cmp	al,'"'
	jne	m1b
	mov	byte ptr [si-1],0
	cmp	byte ptr [si],':'	; a colon after it?
	jne	m1a			; no
	inc	si
	jmp	m1a
m1e:	PRINTF	<"Syntax error",13,10>
	jmp	m8a
m1c:	mov	si,bx
	mov	di,offset VARS + V_NAME
	cmp	al,CHR_RETURN		; no program?
	jne	m2			; no
	push	si
	mov	si,offset COMMAND_COM
	call	copy_name
	pop	si
	jmp	short m3
m2:	call	copy_name		; DI -> the null after the name
	mov	[com_added],ah		; (zero if it added ".COM")
m3:	mov	[args],si		; SI -> the arguments
;
; Only a name without a drive or directory is searched for.
;
	mov	cx,di
	mov	di,offset VARS + V_NAME
	sub	cx,di			; CX = the name's length
	mov	al,'\'
	repne	scasb			; a directory?
	je	m3d			; yes
	cmp	byte ptr [VARS + V_NAME + 1],':'
	je	m3d			; a drive
	mov	ax,[path_arg]
	test	ax,ax			; were we given a PATH$?
	jz	m3a			; no
	mov	[path].OFF,ax
	mov	[path].SEG,ds
	jmp	short m3d
m3a:	mov	cx,ds:[PSP_ENVSEG]
	jcxz	m3d			; we have no environment
	mov	es,cx
	sub	di,di			; ES:DI -> our environment
m3b:	cmp	byte ptr es:[di],0	; the end of it?
	je	m3d			; yes
	mov	si,offset PATH_STR
	mov	cx,4
	repe	cmpsb			; "PATH"?
	jne	m3c			; no
	cmp	byte ptr es:[di],'='	; "PATH="?
	jne	m3c			; no
	inc	di
	mov	[path].OFF,di
	mov	[path].SEG,es
	jmp	short m3d
m3c:	dec	di			; (in case the mismatch was its null)
	mov	al,0
	mov	ch,4			; (CX >= 400h)
	repne	scasb			; skip to the next variable
	jmp	m3b
m3d:	push	ds
	pop	es
;
; Open the program, as named, and then in each directory of the path.
;
	mov	di,offset VARS + V_PATH
m3e:	call	try_open
	jnc	m4
	mov	cx,[path].SEG
	jcxz	m3j			; no more directories
	push	ds
	lds	si,[path]
	mov	di,offset VARS + V_PATH
m3f:	lodsb
	cmp	al,';'			; the end of a directory?
	je	m3h			; yes
	test	al,al			; the end of the path?
	jnz	m3g			; no
	sub	cx,cx			; yes, so this is the last directory
	jmp	short m3h
m3g:	stosb
	jmp	m3f
m3h:	pop	ds
	mov	[path].OFF,si
	mov	[path].SEG,cx
	cmp	byte ptr [di-1],'\'	; does the directory end with one?
	je	m3e			; yes
	mov	al,'\'
	stosb
	jmp	m3e
m3j:	mov	dx,offset VARS + V_NAME
	EPRINTF	<"Unable to find %s">,<13,10>,ax,dx
	jmp	m8a
;
; Create a machine, fill in its memory, and load the program into it.
;
m4:	push	ax			; save the program's handle
	mov	bx,[mach_paras]
	DOSUTIL	MAPSEG,2		; AX = machine
	jc	m4d
	mov	[machine],ax
	call	init_mem		; AX = the program's environment
	jc	m4d
	xchg	dx,ax			; DX = the environment
;
; Its command tail is our arguments.
;
	push	ds
	pop	es
	mov	si,[args]
	mov	di,offset VARS + V_TAIL + 1
	sub	cx,cx
m4a:	lodsb
	stosb
	cmp	al,CHR_RETURN
	je	m4b
	inc	cx
	jmp	m4a
m4b:	mov	[VARS + V_TAIL],cl
	pop	bx			; BX = handle
	sub	cx,cx			; CX = 0 (no parent)
	mov	word ptr [VARS + V_EPB + EPB_FCB1],-1	; (build its FCBs)
	mov	ax,dx
	push	ax
	call	load_prog		; AX = its PSP
	pop	dx			; DX = the environment
	jc	m4e
	mov	[root_psp],ax
	mov	[cur_psp],ax
	xchg	ax,dx
	dec	ax
	mov	di,MCB_OWNER
	call	put_word		; its program owns the environment
	call	start_prog
	jmp	short m5
m4d:	pop	bx
m4e:	mov	dx,offset VARS + V_PATH
	EPRINTF	<"Unable to load %s">,<13,10>,ax,dx
	jmp	m8a
;
; Have CTRLC signals come to us (see v86_ctrlc), and run the machine until
; its first program ends (see term_prog).
;
m5:	push	ds
	push	cs
	pop	ds
	mov	dx,offset v86_ctrlc
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_DOSCTRLC
	int	21h
	pop	ds

	DEFLBL	run,near
	mov	[run_sp],sp		; (see v86_ctrlc)
	mov	bx,[machine]
	mov	di,offset VARS
	push	ds
	pop	es
	DOSUTIL	MAPSEG,3		; AL = V86X_*
	jnc	run1
	jmp	m8
run1:
	cmp	al,V86X_INT
	jb	run			; a timer tick
	mov	ax,word ptr [VARS+VR_VEC]
	je	do_int			; an INT
	cmp	al,INT_GP		; a general protection fault?
	jne	fault			; no
;
; A HLT at STUB_SEG:vector is a jump (or call) to a default handler, by a
; handler that came before it (eg, a program's hook), which left an interrupt
; frame on the stack, so return to that first (as the default handler would).
;
	cmp	word ptr [VARS+VR_CS],STUB_SEG
	jne	fault
	mov	ax,word ptr [VARS+VR_EIP]
	cmp	ax,STUB_CTRLC		; a CTRLC handler's return?
	jb	run2			; no, one of the HLTs
	je	run1a			; yes
	jmp	fault			; no, not one of ours
run1a:	jmp	ctrlc_ret
run2:
	push	ax
	call	pop_word
	mov	word ptr [VARS+VR_EIP],ax
	call	pop_word
	mov	word ptr [VARS+VR_CS],ax
	call	pop_word
	mov	word ptr [VARS+VR_EFL],ax
	pop	ax			; AL = vector
;
; An INT to a default vector: the DOS ones are ours, and a few others (that
; only check whether something is installed) do nothing; any other ends the
; program, as a fault does.
;
do_int:	cmp	al,INT_DOSFUNC
	jne	di1
	jmp	int21
di1:	cmp	al,INT_DOSUTIL
	jne	di2
	jmp	int2b
di2:	cmp	al,INT_DOSTERM
	jne	di3
	sub	ax,ax			; exit code 0
	jmp	term_prog
di3:	cmp	al,INT_DOSCTRLC
	jne	di4
	jmp	ctrlc_end
di4:
	mov	di,offset NOP_INTS
	mov	cx,NOP_INTS_LEN
	push	ds
	pop	es
	repne	scasb			; does nothing?
	je	run			; right
;
; Report a fault (or an interrupt that we can't do) and end the program; if
; it's the first, we end, too.
;
fault:	mov	cx,word ptr [VARS+VR_CS]
	mov	dx,word ptr [VARS+VR_EIP]
	PRINTF	<"CPU fault %02x at %04x:%04x",13,10>,ax,cx,dx
	mov	ax,(EXTYPE_FAULT SHL 8) OR 1
	mov	bx,[cur_psp]
	cmp	bx,[root_psp]		; the first program?
	je	m8			; yes
	jmp	term_prog
m8:	mov	dx,offset VARS + V_PATH
	PRINTF	<"Unable to run %s",13,10>,dx
m8a:	mov	al,1
	DEFLBL	do_exit,near
;
; If we're ending with an error (or the program did) and we're the first
; program of our session (eg, START V86), its console closes as we end, so
; wait for a key, so that the messages can be read.
;
	test	al,al			; an error?
	jz	m9			; no
	cmp	word ptr ds:[PSP_PARENT],0	; are we the first program?
	jne	m9			; no
	push	ax
	PRINTF	<"Press any key">
	mov	ah,DOS_TTY_IN
	int	21h			; wait for a key
	pop	ax
m9:	mov	ah,DOS_PSP_RETURN
	int	21h
;
; A program's INT 23h to the default vector ends it, as CTRLC does.
;
ctrlc_end:
	mov	ax,EXTYPE_CTRLC SHL 8
	jmp	term_prog
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_ctrlc
;
; Our CTRLC handler, which DOS calls when it sees a CTRLC during a call that
; we passed on for the machine's program (see in_call), or one of our own:
; the program gets the CTRLC instead (see do_ctrlc), and its call is
; restarted when its handler returns (as DOS would).
;
DEFPROC	v86_ctrlc,far
	mov	ds,cs:[our_ds]
	mov	sp,[run_sp]		; (SS is still ours)
	DEFLBL	do_ctrlc,near
	cmp	[in_call],0		; were we doing a call for the program?
	je	dc1			; no
	mov	[in_call],0
	call	pft_save		; (in case the call changed it)
	sub	word ptr [VARS+VR_EIP],2; the program's INT, to restart it
;
; Unless its CTRLC vector is the default (which ends it), simulate an INT 23h
; that returns to STUB_CTRLC (see ctrlc_ret), so that we know how it returned.
;
dc1:	sub	ax,ax
	mov	di,INT_DOSCTRLC * 4
	call	seg_ptr			; ES:DI -> its CTRLC vector
	mov	cx,es:[di].OFF
	mov	dx,es:[di].SEG
	cmp	cx,INT_DOSCTRLC
	jne	dc2
	cmp	dx,STUB_SEG		; the default?
	je	ctrlc_end		; yes
dc2:	mov	ax,word ptr [VARS+VR_EIP]
	mov	[ctrlc_ip],ax
	mov	ax,word ptr [VARS+VR_CS]
	mov	[ctrlc_cs],ax
	mov	ax,word ptr [VARS+VR_EFL]
	call	push_word
	mov	ax,STUB_SEG
	call	push_word
	mov	ax,STUB_CTRLC
	call	push_word
	mov	ax,word ptr [VARS+VR_ESP]
	mov	[ctrlc_sp],ax
	mov	word ptr [VARS+VR_EIP],cx
	mov	word ptr [VARS+VR_CS],dx
	and	word ptr [VARS+VR_EFL],NOT (FL_INTS OR FL_TRAP)
	jmp	run
;
; The handler returned: with IRET (or RETF 2), the program continues; with
; RETF, its flags are still on the stack, and carry set means it ends.
;
	DEFLBL	ctrlc_ret,near
	mov	ax,word ptr [VARS+VR_ESP]
	sub	ax,[ctrlc_sp]
	cmp	ax,4			; a RETF?
	jne	cr1			; no
	test	byte ptr [VARS+VR_EFL],FL_CARRY
	jz	cr0
	jmp	ctrlc_end		; carry, so it ends
cr0:
	call	pop_word
	mov	word ptr [VARS+VR_EFL],ax
cr1:	mov	ax,[ctrlc_ip]
	mov	word ptr [VARS+VR_EIP],ax
	mov	ax,[ctrlc_cs]
	mov	word ptr [VARS+VR_CS],ax
	jmp	run
ENDPROC	v86_ctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_mem
;
; Fills in the machine's vectors, BIOS data (a copy, with the machine's
; MEMORY_SIZE, and CPU_TYPE zero, as in real mode), and HLTs, starts its
; memory blocks (see mem_init), and makes
; the first program's environment: the PATH$ we were given (if any), as PATH,
; and a copy of ours, followed by a count (1) and the program's name, as DOS
; 3.0 and up provide.
;
; Outputs:
;	Carry clear if successful, AX = the environment's segment
;	Carry set if error, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	init_mem
	sub	ax,ax
	cwd				; DX:AX = 0
	call	v86_ptr			; ES:DI -> the machine's vectors
	sub	cx,cx
im1:	xchg	ax,cx
	stosw				; offset = vector
	xchg	ax,cx
	mov	ax,STUB_SEG
	stosw
	inc	cx
	cmp	ch,1
	jb	im1
	push	ds
	mov	bx,BIOS
	DOSUTIL	MAPSEG,0		; AX = selector for the BIOS data
	mov	ds,ax
	sub	si,si
	mov	cx,100h / 2
	rep	movsw			; a copy of the BIOS data
	pop	ds
	mov	bx,BIOS_DATA + offset CPU_TYPE
	mov	byte ptr es:[bx],0	; (in real mode, CPU_TYPE is 0)
	mov	ax,[mach_paras]
	shr	ax,6			; AX = the machine's memory, in K
	mov	es:[bx + offset MEMORY_SIZE - offset CPU_TYPE],ax
	mov	cx,100h + 16
	mov	al,OP_HLT
	rep	stosb			; the HLTs (and STUB_CTRLC)
	call	mem_init
	mov	bx,ENV_PARAS
	mov	al,MCBTYPE_EBLK
	mov	dx,MCBOWNER_SYSTEM	; (until its program is loaded)
	call	mem_alloc		; AX = the environment's segment
	jc	im9
	push	ax
	sub	di,di
	call	seg_ptr			; ES:DI -> the environment
	push	ds
	mov	si,[path_arg]
	test	si,si			; were we given a PATH$?
	jz	im2b			; no
	push	si
	mov	si,offset PATH_STR
	movsw
	movsw				; "PATH"
	pop	si
	mov	al,'='
	stosb
im1a:	lodsb				; and the path (and its null)
	stosb
	test	al,al
	jnz	im1a
im2b:	mov	cx,ds:[PSP_ENVSEG]
	jcxz	im2a			; we have none
	mov	ds,cx
	sub	si,si
	mov	cx,ENV_PARAS * 16 - NAME_LEN * 2 - 16
im2:	lodsb
	stosb
	or	al,[si]			; two nulls?
	loopnz	im2			; no
im2a:	mov	al,0
	stosb
	pop	ds
	mov	ax,1
	stosw
	mov	si,offset VARS + V_PATH
	call	copy_name
	pop	ax			; AX = the environment's segment
	clc
im9:	ret
ENDPROC	init_mem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; try_open
;
; Appends the program's name to a directory (if any) in V_PATH, and opens it
; (or if copy_name added ".COM", and there's no such file, with ".EXE").
;
; Inputs:
;	DI -> the end of the directory in V_PATH
;
; Outputs:
;	If carry clear, AX = handle; otherwise, AX = error
;
; Modifies:
;	AX, DX, SI, DI
;
DEFPROC	try_open
	mov	si,offset VARS + V_NAME
to1:	lodsb
	stosb
	test	al,al
	jnz	to1
	mov	dx,offset VARS + V_PATH
	mov	ax,DOS_HDL_OPEN SHL 8	; AL = 0 (read)
	int	21h
	jnc	to9
	cmp	[com_added],0		; did we add ".COM"?
	stc
	jne	to9			; no
	mov	word ptr [di-4],'XE'
	mov	byte ptr [di-2],'E'	; ".EXE" instead
	mov	ax,DOS_HDL_OPEN SHL 8
	int	21h
to9:	ret
ENDPROC	try_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copy_name
;
; Copies a name (up to whitespace, a CR, or a null) to DI, and adds ".COM"
; if it has no extension (there's room for one in NAME_LEN, since a command
; line has at most 127 characters).
;
; Inputs:
;	DS:SI -> name, ES:DI -> buffer
;
; Outputs:
;	DS:SI -> what follows the name, ES:DI -> the null after the copy
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	copy_name
	mov	ah,0			; AH = 0 (no period yet)
cn1:	lodsb
	cmp	al,' '
	jbe	cn2			; whitespace, a CR, or a null
	cmp	al,'.'
	jne	cn1a
	mov	ah,al
cn1a:	cmp	al,'\'			; a new part of a path?
	jne	cn1b
	mov	ah,0			; yes, so no period yet
cn1b:	stosb
	jmp	cn1
cn2:	dec	si
	test	ah,ah			; did it have an extension?
	jnz	cn3			; yes
	push	si
	mov	si,offset COMMAND_COM + 7	; (".COM")
	movsw
	movsw
	pop	si
cn3:	mov	byte ptr es:[di],0
	ret
ENDPROC	copy_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_ptr and seg_ptr
;
; Return a pointer to the machine's memory at a linear address (or at a
; segment and offset), through the machine's selectors (one for every 32K,
; each covering 64K), so that anything smaller than 32K is in reach; above
; its memory (mach_top), everything below 1Mb (eg, the ROMs and video memory)
; is the system's, and the 64K above 1Mb wraps to the first 64K, as on an
; 8086.
;
; Inputs:
;	DX:AX = linear address (v86_ptr), or AX:DI = segment:offset (seg_ptr)
;
; Outputs:
;	ES:DI -> the address
;
; Modifies:
;	DI, ES
;
DEFPROC	seg_ptr
	push	ax
	push	dx
	mov	dx,ax
	shl	ax,4
	shr	dx,12
	add	ax,di
	adc	dx,0			; DX:AX = linear address
	call	v86_ptr
	pop	dx
	pop	ax
	ret
ENDPROC	seg_ptr

DEFPROC	v86_ptr
	cmp	dx,10h			; below 1Mb?
	jb	vp0			; yes
	sub	dx,10h			; no, the 64K above 1Mb, which wraps
	call	v86_ptr			; to the first 64K
	add	dx,10h
	ret
vp0:	cmp	dx,[mach_top].SEG	; in the machine's memory?
	jb	vp1			; yes
	ja	vp2			; no
	cmp	ax,[mach_top].OFF
	jb	vp1			; yes
;
; Everything above the machine's memory (eg, the ROMs) is the system's, so we
; get a selector for that real segment (and DI is the offset in its first
; paragraph).
;
vp2:	push	ax
	push	bx
	push	dx
	mov	di,ax
	and	di,0Fh
	push	di
	shr	ax,4
	shl	dx,12
	or	ax,dx
	xchg	bx,ax			; BX = segment
	DOSUTIL	MAPSEG,0		; AX = its selector
	mov	es,ax
	pop	di
	pop	dx
	pop	bx
	pop	ax
	ret
vp1:	push	ax
	push	dx
	shl	ax,1
	rcl	dx,1			; DX = which 32K
	shl	dx,3
	add	dx,[machine]
	mov	es,dx
	pop	dx
	pop	ax
	mov	di,ax
	and	di,7FFFh
	ret
ENDPROC	v86_ptr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; v86_get and v86_put
;
; Copy CX bytes (less than 32K) from the machine's memory at AX:SI to our DI
; (v86_get), or from our SI to the machine's memory at AX:DI (v86_put).
;
; Modifies:
;	CX, SI, DI, ES
;
DEFPROC	v86_get
	push	ds
	push	di
	mov	di,si
	call	seg_ptr			; ES:DI -> the machine's memory
	mov	si,di
	pop	di
	push	es
	push	ds
	pop	es			; ES:DI -> ours
	pop	ds			; DS:SI -> the machine's
	rep	movsb
	pop	ds
	ret
ENDPROC	v86_get

DEFPROC	v86_put
	call	seg_ptr			; ES:DI -> the machine's memory
	rep	movsb
	ret
ENDPROC	v86_put

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_word and put_word
;
; Get (into AX) or put (from DX) the word at the machine's AX:DI.
;
; Modifies:
;	AX (get_word), DI, ES
;
DEFPROC	get_word
	call	seg_ptr
	mov	ax,es:[di]
	ret
ENDPROC	get_word

DEFPROC	put_word
	call	seg_ptr
	mov	es:[di],dx
	ret
ENDPROC	put_word

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; push_word and pop_word
;
; Push AX onto (or pop AX from) the machine's stack.
;
; Modifies:
;	AX (pop_word), DI, ES
;
DEFPROC	push_word
	sub	word ptr [VARS+VR_ESP],2
	push	dx
	xchg	dx,ax
	call	stk_ptr
	mov	es:[di],dx
	xchg	ax,dx
	pop	dx
	ret
ENDPROC	push_word

DEFPROC	pop_word
	call	stk_ptr
	mov	ax,es:[di]
	add	word ptr [VARS+VR_ESP],2
	ret
ENDPROC	pop_word

DEFPROC	stk_ptr
	push	ax
	mov	ax,word ptr [VARS+VR_SS]
	mov	di,word ptr [VARS+VR_ESP]
	call	seg_ptr
	pop	ax
	ret
ENDPROC	stk_ptr

	DEFSTR	COMMAND_COM,<"COMMAND.COM",0>
	DEFSTR	PATH_STR,<"PATH$=",22h>
;
; The vectors whose INTs (to a default vector) do nothing.
;
	DEFSTR	NOP_INTS,<INT_DOSIDLE,INT_DOSNET,INT_DOSMULTI,INT_MOUSE>

	DEFWORD	our_ds,0		; our DS (for v86_ctrlc)
	DEFWORD	machine,0		; the machine's first selector
	DEFWORD	mach_paras,V86_PARAS	; its memory, in paragraphs
	DEFWORD	mach_top,<0,V86_PARAS SHR 12>	; and in bytes (a long)
	DEFWORD	root_psp,0		; the PSP of its first program
	DEFWORD	cur_psp,0		; and its current PSP
	DEFLONG	dta,0			; and the DTA
	DEFWORD	args,0			; our arguments (after the name)
	DEFLONG	path,0			; the next directory to search, if any
	DEFWORD	path_arg,0		; the PATH$ we were given, if any
	DEFBYTE	com_added,1		; zero if copy_name added ".COM"
	DEFWORD	run_sp,0		; our SP while the machine runs
	DEFBYTE	in_call,0		; nonzero during a call for a program
	DEFWORD	ctrlc_ip,0		; where a CTRLC interrupted it
	DEFWORD	ctrlc_cs,0
	DEFWORD	ctrlc_sp,0		; its SP in its CTRLC handler

CODE	ENDS

	end	main
