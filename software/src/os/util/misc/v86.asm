;
; BASIC-DOS V86 Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: V86 [PATH$="path"[:]] [program [arguments]]
;
; Runs a real-mode program (COMMAND.COM if none is given; a name without a
; drive or directory is also looked for in each directory of the PATH$ given
; before it, as START gives one, or else of our environment's PATH) in a V86
; machine (see v86.inc), which needs an 80386 in protected mode (CPU_TYPE 3),
; and provides the DOS services that the program asks for, passing most of its
; DOS calls on to BASIC-DOS (with selectors for its DS and ES), and doing
; the ones that involve the machine itself (eg, its vectors, its PSP, and its
; memory) here.
;
; The machine's memory starts with its vectors (each pointing to its own HLT,
; at STUB_SEG:vector, so that the machine exits when a program's interrupt
; or exception goes to a default handler), then a copy of the BIOS data, the
; HLTs, the program's environment (at ENV_SEG), and its PSP (at PSP_SEG),
; followed by the program.
;
; This first version runs only COM programs, and can't run another program
; from one (EXEC), or allocate more memory.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc
	include	v86.inc

V86_PARAS	equ	0A000h	; the machine's memory (640K), in paragraphs
STUB_SEG	equ	0050h	; the HLTs (one for each vector)
ENV_SEG		equ	0060h	; the program's environment
ENV_LEN		equ	0400h	; and its length (with the program's name)
PSP_SEG		equ	ENV_SEG + (ENV_LEN SHR 4)
COM_MAX		equ	0FF00h - 2	; most of a COM program that can load
FL_RESULTS	equ	FL_CARRY OR FL_ZERO OR FL_SIGN OR FL_OVFL

CODE    SEGMENT
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
; Get the program's name, and its arguments, which follow it; any switch
; before the name is one we don't accept.  A PATH$="..." before the name (as
; START gives us, with a colon after it, as a SHELL line's has) is the path
; to search, whose ending quote becomes a null; otherwise, our environment's
; PATH (if any) is.
;
m1:	mov	ax,DOS_MSC_GETSWC
	int	21h			; DL = switch character
	mov	si,PSP_CMDTAIL + 1
m1a:	lodsb
	cmp	al,' '			; skip leading whitespace
	je	m1a
	cmp	al,9
	je	m1a
	dec	si
	cmp	al,dl			; a switch?
	je	m1e			; yes
	mov	bx,si
	mov	di,offset PATH_STR
	mov	cx,PATH_STRLEN
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
	mov	di,offset base_name
	cmp	al,CHR_RETURN		; no program?
	jne	m2			; no
	push	si
	mov	si,offset COMMAND_COM
	call	copy_name
	pop	si
	jmp	short m3
m2:	call	copy_name		; DI -> the null after the name
m3:	mov	[args],si		; SI -> the arguments
;
; Only a name without a drive or directory is searched for.
;
	mov	cx,di
	mov	di,offset base_name
	sub	cx,di			; CX = the name's length
	mov	al,'\'
	repne	scasb			; a directory?
	je	m3d			; yes
	cmp	byte ptr [base_name+1],':'
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
	mov	di,offset prog_name
m3e:	call	try_open
	jnc	m4
	mov	cx,[path].SEG
	jcxz	m3j			; no more directories
	push	ds
	lds	si,[path]
	mov	di,offset prog_name
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
m3j:	mov	dx,offset base_name
	EPRINTF	<"Unable to find %s">,<13,10>,ax,dx
	jmp	m8a
m4:	mov	[handle],ax
	mov	bx,V86_PARAS
	DOSUTIL	MAPSEG,2		; AX = machine
	jnc	m5
	EPRINTF	<"Unable to load %s">,<13,10>,ax,dx
	jmp	m8a
m5:	mov	[machine],ax
	call	init_mem
	jc	m8
;
; Run the machine until its program ends (see do_exit).
;
run:	mov	bx,[machine]
	mov	di,offset regs
	push	ds
	pop	es
	DOSUTIL	MAPSEG,3		; AL = V86X_*
	jc	m8
	cmp	al,V86X_INT
	jb	run			; a timer tick
	mov	ax,word ptr [regs+VR_VEC]
	je	do_int			; an INT
	cmp	al,INT_GP		; a general protection fault?
	jne	fault			; no
;
; A HLT at STUB_SEG:vector is a jump (or call) to a default handler, by a
; handler that came before it (eg, a program's hook), which left an interrupt
; frame on the stack, so return to that first (as the default handler would).
;
	cmp	word ptr [regs+VR_CS],STUB_SEG
	jne	fault
	mov	ax,word ptr [regs+VR_EIP]
	cmp	ax,100h			; one of the HLTs?
	jae	fault			; no
	push	ax
	call	pop_word
	mov	word ptr [regs+VR_EIP],ax
	call	pop_word
	mov	word ptr [regs+VR_CS],ax
	call	pop_word
	mov	word ptr [regs+VR_EFL],ax
	pop	ax			; AL = vector
do_int:	cmp	al,INT_DOSFUNC
	je	int21
	cmp	al,INT_DOSTERM
	je	do_exit0
fault:	mov	cx,word ptr [regs+VR_CS]
	mov	dx,word ptr [regs+VR_EIP]
	PRINTF	<"CPU fault %02x at %04x:%04x",13,10>,ax,cx,dx
m8:	mov	dx,offset prog_name
	PRINTF	<"Unable to run %s",13,10>,dx
m8a:	mov	al,1
	jmp	short do_exit
do_exit0:
	mov	al,0
;
; If we're ending with an error (or the program did) and we're the first
; program of our session (eg, START V86), its console closes as we end, so
; wait for a key, so that the messages can be read.
;
do_exit:
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
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; int21
;
; Does the DOS function that the machine's program asked for, here if it
; involves the machine (its vectors, PSP, DTA, memory, and ending), and
; otherwise by passing it on to BASIC-DOS, and then runs the machine again.
;
DEFPROC	int21
	push	ds
	pop	es
	mov	al,byte ptr [regs+VR_EAX+1]
	mov	di,offset I21_FUNCS
	mov	cx,I21_NFUNCS
	repne	scasb			; one we do here?
	jne	i21p			; no
	sub	di,offset I21_FUNCS + 1
	shl	di,1
	mov	ax,word ptr [regs+VR_EAX]
	jmp	I21_PROCS[di]
;
; Pass anything else on to BASIC-DOS, with selectors for the machine's DS
; and ES, and return its registers and result flags.
;
i21p:	push	ds
	mov	ax,word ptr [regs+VR_EAX]
	mov	bx,word ptr [regs+VR_EBX]
	mov	cx,word ptr [regs+VR_ECX]
	mov	dx,word ptr [regs+VR_EDX]
	mov	si,word ptr [regs+VR_ESI]
	mov	di,word ptr [regs+VR_EDI]
	mov	bp,word ptr [regs+VR_EBP]
	mov	es,word ptr [regs+VR_ESSEL]
	mov	ds,word ptr [regs+VR_DSSEL]
	int	21h
	pop	ds
	mov	word ptr [regs+VR_EAX],ax
	mov	word ptr [regs+VR_EBX],bx
	mov	word ptr [regs+VR_ECX],cx
	mov	word ptr [regs+VR_EDX],dx
	mov	word ptr [regs+VR_ESI],si
	mov	word ptr [regs+VR_EDI],di
	mov	word ptr [regs+VR_EBP],bp
	pushf
	pop	ax
	and	ax,FL_RESULTS
	jmp	i21f
i21x:	cmp	ah,DOS_PSP_TERM		; (AL = exit code for DOS_PSP_RETURN)
	jne	i21xa
	mov	al,0
i21xa:	jmp	do_exit
i21sv:	mov	bl,al			; set vector AL to DS:DX
	mov	bh,0
	shl	bx,2
	sub	ax,ax
	cwd				; DX:AX = 0 (the vectors)
	call	v86_ptr			; ES:DI -> vectors
	mov	ax,word ptr [regs+VR_EDX]
	mov	es:[bx],ax
	mov	ax,word ptr [regs+VR_DS]
	mov	es:[bx+2],ax
	jmp	short i21ok
i21gv:	mov	bl,al			; get vector AL in ES:BX
	mov	bh,0
	shl	bx,2
	sub	ax,ax
	cwd				; DX:AX = 0 (the vectors)
	call	v86_ptr
	mov	ax,es:[bx]
	mov	cx,es:[bx+2]
	jmp	short i21esbx
i21sd:	mov	ax,word ptr [regs+VR_EDX]
	mov	[dta].OFF,ax		; set DTA to DS:DX
	mov	ax,word ptr [regs+VR_DS]
	mov	[dta].SEG,ax
	jmp	short i21ok
i21gd:	mov	ax,[dta].OFF		; get DTA in ES:BX
	mov	cx,[dta].SEG
i21esbx:mov	word ptr [regs+VR_EBX],ax
	mov	word ptr [regs+VR_ES],cx
	jmp	short i21ok
i21gp:	mov	word ptr [regs+VR_EBX],PSP_SEG
	jmp	short i21ok
;
; The program's PSP block is the machine's memory, from PSP_SEG on, so it can
; shrink, or grow back up to that; there's no memory to allocate.
;
i21ra:	mov	ax,V86_PARAS - PSP_SEG
	cmp	word ptr [regs+VR_ES],PSP_SEG
	jne	i21nm1
	cmp	word ptr [regs+VR_EBX],ax
	jbe	i21ok
	jmp	short i21nm1
i21nm:	sub	ax,ax
i21nm1:	mov	word ptr [regs+VR_EBX],ax	; the largest it could be
	mov	word ptr [regs+VR_EAX],ERR_NOMEMORY
	mov	ax,FL_CARRY
	jmp	short i21f
i21ok:	sub	ax,ax			; no result flags (carry is clear)
i21f:	and	word ptr [regs+VR_EFL],NOT FL_RESULTS
	or	word ptr [regs+VR_EFL],ax
	jmp	run
ENDPROC	int21
;
; The DOS functions that we do here, and their handlers.
;
	DEFLBL	I21_FUNCS,byte
	db	DOS_PSP_TERM, DOS_PSP_RETURN, DOS_MSC_SETVEC, DOS_MSC_GETVEC
	db	DOS_DSK_SETDTA, DOS_DSK_GETDTA, DOS_PSP_GET, DOS_PSP_SET
	db	DOS_MEM_FREE, DOS_MEM_REALLOC, DOS_MEM_ALLOC
	db	DOS_PSP_EXEC SHR 8
I21_NFUNCS	equ	$ - I21_FUNCS
	DEFLBL	I21_PROCS,word
	dw	i21x, i21x, i21sv, i21gv, i21sd, i21gd, i21gp, i21ok
	dw	i21ok, i21ra, i21nm, i21nm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_mem
;
; Fills in the machine's memory (its vectors, BIOS data, HLTs, environment,
; and PSP), loads the program after its PSP, and sets its registers.
;
; Outputs:
;	Carry clear if successful
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
	mov	cx,100h
	mov	al,OP_HLT
	rep	stosb			; the HLTs
;
; The environment is the PATH$ we were given (if any), as PATH, and a copy of
; ours, followed by a count (1) and the program's name, as DOS 3.0 and up
; provide.
;
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
	mov	cx,ENV_LEN - NAME_LEN * 2 - 16
im2:	lodsb
	stosb
	or	al,[si]			; two nulls?
	loopnz	im2			; no
im2a:	mov	al,0
	stosb
	pop	ds
	mov	ax,1
	stosw
	mov	si,offset prog_name
	call	copy_name
	inc	di			; (past its null)
;
; The PSP (the parts that programs use): INT 20h, the top of memory, the
; environment, empty FCBs, and the command tail.
;
	mov	di,PSP_SEG * 16
	mov	cx,100h / 2
	sub	ax,ax
	rep	stosw
	mov	di,PSP_SEG * 16
	mov	word ptr es:[di].PSP_TERMCALL,OP_INT20
	mov	es:[di].PSP_PARAS,V86_PARAS
	mov	es:[di].PSP_PARENT,PSP_SEG
	mov	es:[di].PSP_ENVSEG,ENV_SEG
	lea	di,[di].PSP_FCB1 + 1
	mov	al,' '
	mov	cx,11
	rep	stosb
	mov	di,PSP_SEG * 16 + PSP_FCB2 + 1
	mov	cx,11
	rep	stosb
	mov	di,PSP_SEG * 16 + PSP_CMDTAIL + 1
	mov	si,[args]
	sub	cx,cx
im3:	lodsb
	stosb
	cmp	al,CHR_RETURN
	je	im4
	inc	cx
	jmp	im3
im4:	mov	es:[PSP_SEG * 16 + PSP_CMDTAIL],cl
;
; The program (a COM file) follows the PSP, in the same segment, whose last
; word is zero, so that its RET goes to the PSP's INT 20h.
;
	mov	bx,[handle]
	mov	ax,PSP_SEG * 16 + 100h
	sub	dx,dx			; DX:AX = where it goes
	mov	cx,COM_MAX
im5:	push	ax
	push	cx
	push	dx
	call	v86_ptr			; ES:DI -> the next part
	mov	dx,di
	neg	di			; DI = bytes to the end of this 64K
	jz	im6			; (all of it)
	cmp	cx,di
	jbe	im6
	mov	cx,di			; CX = bytes to read into it
im6:	push	ds
	push	es
	pop	ds
	mov	ah,DOS_HDL_READ
	int	21h			; AX = bytes read
	pop	ds
	pop	dx
	pop	cx
	jc	im8
	sub	cx,ax			; CX = bytes that are still allowed
	pop	si
	add	si,ax
	adc	dx,0
	test	ax,ax			; the end of the file?
	xchg	ax,si			; DX:AX = where the next part goes
	jz	im7			; yes
	jcxz	im7			; or as much as fits
	jmp	im5
im7:	mov	ah,DOS_HDL_CLOSE
	int	21h
	mov	ax,PSP_SEG
	mov	word ptr [regs+VR_CS],ax
	mov	word ptr [regs+VR_DS],ax
	mov	word ptr [regs+VR_ES],ax
	mov	word ptr [regs+VR_SS],ax
	mov	word ptr [regs+VR_EIP],100h
	mov	word ptr [regs+VR_ESP],0FFFEh
	mov	word ptr [regs+VR_EFL],FL_DEFAULT
	mov	[dta].OFF,PSP_DTA
	mov	[dta].SEG,ax
	mov	ax,PSP_SEG * 16 - 2
	mov	dx,1			; DX:AX = PSP_SEG:FFFEh
	call	v86_ptr
	mov	word ptr es:[di],0	; (for the program's RET)
	clc
	ret
im8:	pop	ax
	ret
ENDPROC	init_mem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; try_open
;
; Appends the program's name to a directory (if any) in prog_name, and opens
; it.
;
; Inputs:
;	DI -> the end of the directory in prog_name
;
; Outputs:
;	If carry clear, AX = handle; otherwise, AX = error
;
; Modifies:
;	AX, DX, SI, DI
;
DEFPROC	try_open
	mov	si,offset base_name
to1:	lodsb
	stosb
	test	al,al
	jnz	to1
	mov	dx,offset prog_name
	mov	ax,DOS_HDL_OPEN SHL 8	; AL = 0 (read)
	int	21h
	ret
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
; v86_ptr
;
; Returns a pointer to the machine's memory at a linear address, through the
; machine's selectors (one for every 64K).
;
; Inputs:
;	DX:AX = linear address (or, with AX = 0, the vectors)
;
; Outputs:
;	ES:DI -> the address
;
; Modifies:
;	DI, ES
;
DEFPROC	v86_ptr
	mov	di,dx
	shl	di,3
	add	di,[machine]
	mov	es,di
	mov	di,ax
	ret
ENDPROC	v86_ptr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pop_word
;
; Pops a word from the machine's stack.
;
; Outputs:
;	AX = word
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	pop_word
	mov	ax,word ptr [regs+VR_SS]
	mov	dx,ax
	shl	ax,4
	shr	dx,12
	add	ax,word ptr [regs+VR_ESP]
	adc	dx,0			; DX:AX = linear address
	add	word ptr [regs+VR_ESP],2
	call	v86_ptr
	mov	ax,es:[di]
	ret
ENDPROC	pop_word

	DEFSTR	COMMAND_COM,<"COMMAND.COM",0>
	DEFSTR	PATH_STR,<"PATH$=",22h>
PATH_STRLEN	equ	$ - PATH_STR
	DEFWORD	machine,0
	DEFWORD	handle,0
	DEFWORD	args,0
	DEFLONG	dta,0
	DEFLONG	path,0			; the next directory to search, if any
	DEFWORD	path_arg,0		; the PATH$ we were given, if any
;
; The machine's registers (V86REGS), the program's name (as given), and its
; name with the directory where it was found are in the heap.
;
NAME_LEN	equ	132
	COMHEAP	<size V86REGS + NAME_LEN * 2 + 512>	; (the last item)
regs	equ	$
base_name	equ	regs + size V86REGS
prog_name	equ	base_name + NAME_LEN

CODE	ENDS

	end	main
