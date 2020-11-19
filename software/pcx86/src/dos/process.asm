;
; BASIC-DOS Process Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	devapi.inc
	include	dos.inc

DOS	segment word public 'CODE'

	EXTBYTE	<scb_locked>
	EXTWORD	<mcb_head,mcb_limit,scb_active>
	EXTNEAR	<sfh_add_ref,pfh_close,sfh_close>
	EXTNEAR	<mcb_getsize,mcb_free_all>
	EXTNEAR	<dos_exit,dos_exit2,dos_ctrlc,dos_error>
	EXTNEAR	<mcb_setname,scb_getnum,scb_release,scb_unload,scb_yield>
	IF REG_CHECK
	EXTNEAR	<dos_check>
	ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_term (REG_AH = 00h)
;
; Inputs:
;	None
;
; Outputs:
;	None
;
DEFPROC	psp_term,DOS
	sub	ax,ax			; default exit code/type

	DEFLBL	psp_term_exitcode,near
	ASSERT	Z,<cmp [scb_locked],-1>	; SCBs should never be locked now

	push	ax
	call	get_psp
	mov	es,ax
	pop	ax
	ASSUME	ES:NOTHING
	mov	si,es:[PSP_PARENT]

	test	si,si			; if there's a parent
	jnz	pt1			; then the SCB is still healthy
	cmp	es:[PSP_SCB],0		; are we allowed to terminate this SCB?
	je	pt7			; no
;
; Close process file handles.
;
pt1:	push	ax			; save exit code/type on stack
	call	psp_close		; close all the process file handles
;
; Restore the SCB's CTRLC and ERROR handlers from the values in the PSP.
;
	mov	bx,[scb_active]
	push	es:[PSP_EXRET].SEG	; push PSP_EXRET (exec return address)
	push	es:[PSP_EXRET].OFF

	mov	ax,es:[PSP_CTRLC].OFF	; brute-force restoration
	mov	[bx].SCB_CTRLC.OFF,ax	; of CTRLC and ERROR handlers
	mov	ax,es:[PSP_CTRLC].SEG
	mov	[bx].SCB_CTRLC.SEG,ax

	mov	ax,es:[PSP_ERROR].OFF
	mov	[bx].SCB_ERROR.OFF,ax
	mov	ax,es:[PSP_ERROR].SEG
	mov	[bx].SCB_ERROR.SEG,ax

	mov	ax,es:[PSP_DTAPREV].OFF	; restore the previous DTA
	mov	[bx].SCB_DTA.OFF,ax	; (PC DOS may require every process
	mov	ax,es:[PSP_DTAPREV].SEG	; to restore this itself after an exec)
	mov	[bx].SCB_DTA.SEG,ax

	mov	al,es:[PSP_SCB]		; save SCB #
	push	ax
	push	si			; save PSP of parent
	mov	ax,es
	call	mcb_free_all		; free all blocks owned by PSP in AX
	pop	ax			; restore PSP of parent
	pop	cx			; CL = SCB #
;
; If this is a parent-less program, mark the SCB as unloaded and yield.
;
	call	set_psp			; update SCB_PSP (even if zero)
	test	ax,ax
	jnz	pt8
	call	scb_unload		; mark SCB # CL as unloaded
	jc	pt7
	jmp	scb_yield		; and call scb_yield with AX = zero
	ASSERT	NEVER
pt7:	jmp	short pt9

pt8:	mov	es,ax			; ES = PSP of parent
	pop	dx
	pop	cx			; we now have PSP_EXRET in CX:DX
	pop	ax			; AX = exit code (saved on entry above)
	mov	word ptr es:[PSP_EXCODE],ax

	cli
	mov	ss,es:[PSP_STACK].SEG
	mov	sp,es:[PSP_STACK].OFF
;
; When a program (eg, SYMDEB.EXE) loads another program using DOS_PSP_EXEC1,
; it will necessarily be exec'ing the program itself, which means we can't be
; sure the stack used at the time of loading will be identical to the stack
; used at time of exec'ing.  So we will use dos_exit2 to bypass the REG_CHECK
; *and* we will create a fresh IRET frame at the top of REG_FRAME.
;
	IF REG_CHECK
	add	sp,2
	ENDIF
	mov	bp,sp
	mov	[bp].REG_IP,dx		; copy PSP_EXRET to caller's CS:IP
	mov	[bp].REG_CS,cx		; (normally they will be identical)
	mov	word ptr [bp].REG_FL,FL_DEFAULT
	jmp	dos_exit2		; let dos_exit turn interrupts back on

pt9:	ret
ENDPROC	psp_term

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_copy (REG_AH = 26h)
;
; Initializes the PSP with current memory values and vectors and then copies
; rest of the PSP from the active PSP.
;
; Inputs:
;	REG_DX = segment of new PSP
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	psp_copy,DOS
	call	psp_init		; returns ES:DI -> PSP_PARENT
	ASSUME	ES:NOTHING
	ASSERT	NZ,<test ax,ax>
	mov	ds,ax
	ASSUME	DS:NOTHING
	mov	si,PSP_PARENT
	mov	cx,(size PSP - PSP_PARENT) SHR 1
	rep	movsw
	ret
ENDPROC	psp_copy

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_exec (REG_AX = 4Bh)
;
; NOTE: If REG_BX = -1, then load_command is used instead of load_program.
;
; TODO: Add support for EPB_ENVSEG.
;
; Inputs:
;	REG_AL = subfunction
;		0: load program
;		1: load program w/o starting
;		2: start program
;	REG_ES:REG_BX -> Exec Parameter Block (EPB)
;	REG_DS:REG_DX -> program name or command line
;
; Outputs:
;	If successful, carry clear
;	If error, carry set, AX = error code
;
DEFPROC	psp_exec,DOS
	cmp	al,2			; valid subfunction?
	mov	ax,ERR_INVALID		; AX = error code if not
	ja	px9
	je	px5

	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	mov	si,dx			; DS:SI -> program/command (from DS:DX)
	inc	bx			; BX = -1?
	jnz	px1			; no
;
; No EPB was provided, so treat DS:SI as a command line.
;
	call	load_command		; load the program and parse the tail
	jc	px9			; AX should contain an error code
	jmp	short px2		; otherwise, launch the program

px1:	dec	bx			; restore BX pointer to EPB
	call	load_program		; load the program
	ASSUME	ES:NOTHING
	jc	px9			; AX should contain an error code
;
; Use load_args to build the FCBs and CMDTAIL in the PSP from the EBP.
;
	mov	ds,[bp].REG_ES
	mov	bx,[bp].REG_BX		; DS:BX -> EPB (from ES:BX)
	call	load_args		; DX:AX -> new stack
	cmp	byte ptr [bp].REG_AL,0	; was AL zero?
	jne	px4			; no
;
; This was a DOS_PSP_EXEC call, and unlike scb_load, it's a synchronous
; exec, meaning we launch the program directly from this call.
;
px2:	cli
	mov	ss,dx			; switch to the new program's stack
	mov	sp,ax
	jmp	dos_exit		; and let dos_exit turn interrupts on
;
; This is a DOS_PSP_EXEC1 call: an undocumented call that only loads the
; program, fills in the undocumented EPB_INIT_SP and EPB_INIT_IP fields,
; and then returns to the caller.
;
; Note that EPB_INIT_SP will normally be PSP_STACK (PSP:2Eh) - 2, since we
; push a zero on the stack, and EPB_INIT_IP should match PSP_START (PSP:40h).
;
; The current PSP is the new PSP (which is still in ES) and DX:AX now points
; to the program's stack.  However, the stack we created contains our usual
; REG_FRAME, which the caller has no use for, so we remove it.  In fact, the
; new stack is supposed to contain only the initial value for REG_AX, which
; we take care of below.
;
px4:
	IF REG_CHECK
	add	ax,REG_CHECK
	ENDIF
	mov	di,ax
	add	ax,size REG_FRAME-2	; leave just REG_FL on the stack
	mov	[bx].EPB_INIT_SP.OFF,ax
	mov	[bx].EPB_INIT_SP.SEG,dx	; return the program's SS:SP
	mov	es,dx			; ES:DI -> REG_FRAME
	mov	ax,es:[di].REG_AX
	mov	es:[di].REG_FL,ax	; store REG_AX in place of REG_FL
	les	di,dword ptr es:[di].REG_IP
	mov	[bx].EPB_INIT_IP.OFF,di
	mov	[bx].EPB_INIT_IP.SEG,es	; return the program's CS:IP
	clc
	ret
;
; This is a DOS_PSP_EXEC2 "start" request.  ES:BX must point to a previously
; initialized EPB with EPB_INIT_SP pointing to REG_FL in a REG_FRAME, and the
; current PSP must be the new PSP (ie, exactly as DOS_PSP_EXEC1 left it).
;
; In addition, we copy the caller's REG_CS:REG_IP into PSP_EXRET, because we
; don't want the program returning to the original EXEC call on termination.
;
px5:	mov	ds,[bp].REG_ES
	mov	bx,[bp].REG_BX		; DS:BX -> EPB (from ES:BX)
	lds	bx,[bx].EPB_INIT_SP	; DS:BX -> stack (@REG_FL)
	sub	bx,size REG_FRAME-2	; DS:BX -> REG_FRAME
	mov	[bx].REG_FL,FL_DEFAULT	; fix REG_FL
	mov	dx,ds
	call	get_psp
	jz	px6
	mov	ds,ax			; DS -> new PSP
	mov	ax,[bp].REG_IP
	mov	ds:[PSP_EXRET].OFF,ax
	mov	ax,[bp].REG_CS
	mov	ds:[PSP_EXRET].SEG,ax
px6:	xchg	ax,bx			; DX:AX -> REG_FRAME
	IF REG_CHECK
	sub	ax,REG_CHECK
	ENDIF
	jmp	px2

px9:	mov	[bp].REG_AX,ax		; return any error code in REG_AX
	stc
	ret
ENDPROC	psp_exec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_exit (REG_AH = 4Ch)
;
; Inputs:
;	REG_AL = return code
;
; Outputs:
;	None
;
DEFPROC	psp_exit,DOS
	mov	ah,EXTYPE_NORMAL
	jmp	psp_term_exitcode
ENDPROC	psp_exit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_retcode (REG_AH = 4Dh)
;
; Returns the exit code (AL) and exit type (AH) from the child process.
;
; Inputs:
;	None
;
; Outputs:
;	REG_AL = exit code
;	REG_AH = exit type (see EXTYPE_*)
;
; Modifies:
;	AX
;
DEFPROC	psp_retcode,DOS
	call	get_psp
	mov	ds,ax
	mov	ax,word ptr ds:[PSP_EXCODE]
	mov	[bp].REG_AX,ax
	ret
ENDPROC	psp_retcode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_set (REG_AH = 50h)
;
; Inputs:
;	REG_BX = segment of new PSP
;
; Outputs:
;	None
;
DEFPROC	psp_set,DOS
	mov	ax,[bp].REG_BX
	jmp	set_psp
ENDPROC	psp_set

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_get (REG_AH = 51h)
;
; Inputs:
;	None
;
; Outputs:
;	REG_BX = segment of current PSP
;
DEFPROC	psp_get,DOS
	call	get_psp
	mov	[bp].REG_BX,ax
	ret
ENDPROC	psp_get

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_create (REG_AH = 55h)
;
; Creates a new PSP with a process file table filled with system file handles
; from the active SCB.
;
; Inputs:
;	REG_DX = segment of new PSP
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	psp_create,DOS
	call	psp_init		; returns ES:DI -> PSP_PARENT
	stosw				; update PSP_PARENT
;
; Next up: the PFT (Process File Table); the first 5 PFT slots (PFHs) are
; predefined as STDIN (0), STDOUT (1), STDERR (2), STDAUX (3), and STDPRN (4),
; and apparently we should open SFBs for AUX first, CON second, and PRN third,
; so that the SFHs for the first five handles will always be 1, 1, 1, 0, and 2.
;
	mov	ah,1
	mov	cx,5
	lea	si,[bx].SCB_SFHIN
pc1:	lodsb
	stosb
	call	sfh_add_ref
	loop	pc1
	mov	al,SFH_NONE		; AL = 0FFh (indicates unused entry)
	mov	cl,15			; 15 more PFT slots left
	rep	stosb			; finish up PSP_PFT (20 bytes total)
	mov	cl,(size PSP - PSP_ENVSEG) SHR 1
	sub	ax,ax
	rep	stosw			; zero the rest of the PSP
	mov	di,PSP_DISPATCH
	mov	ax,OP_INT21
	stosw
	mov	al,OP_RETF
	stosb
	mov	di,PSP_FCB1
	mov	al,' '
	mov	cl,size FCB_NAME
	rep	stosb
	mov	cl,size FCB_NAME
	mov	di,PSP_FCB2
	rep	stosb
	mov	di,PSP_CMDTAIL
	mov	ax,0D00h
	stosw
	ret
ENDPROC	psp_create

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_command
;
; This is a wrapper around load_program, which takes care of splitting a
; command line into a program name and a command tail, as well as creating
; the (up to) two initial FCBs.
;
; Inputs:
;	DS:SI -> command line
;
; Outputs:
;	If successful, carry clear, DX:AX -> new stack (from load_args)
;	If error, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	load_command,DOS
	ASSUME	DS:NOTHING,ES:NOTHING

	push	si			; save starting point
lc1:	lodsb
	cmp	al,CHR_SPACE
	ja	lc1
	dec	si
	mov	byte ptr [si],0
	mov	bx,si			; AL = separator, BX -> separator
	pop	si

	push	ax
	push	bx
	push	ds
	push	si
	call	load_program		; DS:SI -> program name
	pop	si
	pop	ds
	pop	bx
	pop	cx
	jc	lc9			; if carry set, AX is error code
;
; DS:SI -> command line, CL = separator, BX = separator address, and
; ES:DI -> new program's stack.
;
	push	ds
	push	bp
	sub	sp,size EPB
	mov	bp,sp			; BP -> EPB followed by two FCBs
	mov	[bp].EPB_ENVSEG,0
	mov	[bx],cl			; restore separator
	mov	si,bx
	DOSUTIL	STRLEN			; AX = # chars at DS:SI
	ASSERT	BE,<cmp ax,126>
	dec	bx
	xchg	cx,ax			; CX = length
	xchg	[bx],cl			; set length
	mov	[bp].EPB_CMDTAIL.OFF,bx
	mov	[bp].EPB_CMDTAIL.SEG,ds
	mov	[bp].EPB_FCB1.OFF,-1	; tell load_args to build the FCBs
	push	bx
	mov	bx,bp
	push	ss
	pop	ds			; DS:BX -> EBP
	call	load_args
	pop	bx
	add	sp,size EPB
	pop	bp
	pop	ds
	mov	[bx],cl			; restore byte overwritten by length
	ASSERT	NC

lc9:	ret
ENDPROC	load_command

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_args
;
; NOTE: If EPB_FCB1.OFF is -1, then this function will build both FCBs
; from the command tail at EPB_CMDTAIL.
;
; NOTE: While EPB_CMDTAIL normally ends with a CHR_RETURN, load_command
; doesn't bother, because it knows load_args will copy only the specified
; number of tail characters and then output CHR_RETURN.
;
; Inputs:
;	DS:BX -> EPB
;	ES:DI -> new stack
;
; Outputs:
;	ES -> PSP
;	DX:AX -> new stack
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	load_args,DOS
	ASSUME	DS:NOTHING,ES:NOTHING

	push	es			; save ES:DI (new program's stack)
	push	di
	push	cx
	push	si
	call	get_psp
	mov	es,ax			; ES -> PSP

	push	ds
	mov	di,PSP_FCB1		; ES:DI -> PSP_FCB1
	lds	si,[bx].EPB_FCB1
	cmp	si,-1
	jne	la1
	pop	ds
	push	ds			; DS:BX -> EPB again
	lds	si,[bx].EPB_CMDTAIL
	inc	si
	mov	ax,(DOS_FCB_PARSE SHL 8) or 01h
	int	21h
	mov	ax,(DOS_FCB_PARSE SHL 8) or 01h
	mov	di,PSP_FCB2
	int	21h
	jmp	short la2

la1:	mov	cx,size FCB
	rep	movsb			; fill in PSP_FCB1
	pop	ds
	push	ds			; DS:BX -> EPB again
	lds	si,[bx].EPB_FCB2
	mov	di,PSP_FCB2
	mov	cx,size FCB
	rep	movsb			; fill in PSP_FCB2

la2:	pop	ds
	push	ds			; DS:BX -> EPB again
	lds	si,[bx].EPB_CMDTAIL
	mov	di,PSP_CMDTAIL
	mov	cl,[si]
	mov	ch,0
	inc	cx
	rep	movsb			; fill in PSP_CMDTAIL
	mov	al,CHR_RETURN
	stosb
	pop	ds			; DS:BX -> EPB again

	pop	si
	pop	cx
	pop	ax
	pop	dx			; recover new program's stack in DX:AX
	ret
ENDPROC	load_args

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_program
;
; Inputs:
;	DS:SI -> name of program
;
; Outputs:
;	If successful, carry clear, ES:DI -> new stack
;	If error, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	load_program,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
;
; We used to start off with a small allocation (10h paras), since that's
; all we initially need for the PSP, but that can get us into trouble later
; if there isn't enough free space after the block.  So it's actually best
; to allocate the largest possible block now.  We'll shrink it down once
; we know how large the program is.
;
; TODO: Allocating all memory can get us into trouble with other sessions,
; if they need any memory while this function is running.  So, while we
; originally didn't want to wrap this entire operation with LOCK_SCB, because
; 1) it's lengthy and 2) everything it does other than the memory allocations
; is session-local, that's the only solution we have available at the moment.
;
	LOCK_SCB
	mov	bx,0A000h		; alloc a PSP segment
	mov	ah,DOS_MEM_ALLOC	; with a size that should fail
	int	21h			; in order to get max paras avail
	ASSERT	C
	jnc	lp1			; if it didn't fail, use it anyway?
	cmp	bx,11h			; enough memory to do anything useful?
	jb	lp0			; no
	mov	ah,DOS_MEM_ALLOC	; BX = max paras avail
	int	21h			; returns a new segment in AX
	jnc	lp1
lp0:	jmp	lp9			; abort

lp1:	mov	[bp].TMP_DX,bx		; TMP_DX = size of segment (in paras)
	xchg	dx,ax			; DX = segment for new PSP
	mov	ah,DOS_PSP_CREATE
	int	21h			; create new PSP at DX
;
; Let's update the PSP_STACK field in the current PSP before we switch to
; the new PSP, since we rely on it to gracefully return to the caller when
; this new program terminates.  PC DOS updates PSP_STACK on every DOS call,
; because it loves switching stacks; we do not.
;
	call	get_psp
	jz	lp2			; jump if no PSP exists yet
	mov	es,ax
	ASSUME	ES:NOTHING
	mov	bx,bp
	IF REG_CHECK
	sub	bx,2
	ENDIF
	mov	es:[PSP_STACK].OFF,bx
	mov	es:[PSP_STACK].SEG,ss

lp2:	push	ax			; save original PSP
	xchg	ax,dx			; AX = new PSP
	call	set_psp

	mov	dx,si			; DS:DX -> name of program
	mov	ax,DOS_HDL_OPENRO
	int	21h			; open the file
	jc	lpf1
	xchg	bx,ax			; BX = file handle

	call	get_psp
	mov	ds,ax			; DS = segment of new PSP
	mov	ax,[bp].REG_IP
	mov	ds:[PSP_EXRET].OFF,ax	; update the PSP's EXRET address
	mov	ax,[bp].REG_CS
	mov	ds:[PSP_EXRET].SEG,ax

	sub	cx,cx
	sub	dx,dx
	mov	[bp].TMP_CX,cx
	mov	ax,(DOS_HDL_SEEK SHL 8) OR SEEK_END
	int	21h			; returns new file position in DX:AX
	jc	lpc1
	test	dx,dx
	jnz	lp3
	mov	[bp].TMP_CX,ax		; record size ONLY if < 64K
;
; Now that we have a file size, verify that the PSP segment is large enough.
; We don't know EXACTLY how much we need yet, because there might be a COMHEAP
; signature if it's a COM file, and EXE files have numerous unknowns at this
; point.  But having at LEAST as much memory as there are bytes in the file
; (plus a little extra) is necessary for the next stage of the loading process.
;
; How much is "a little extra"?  Currently, it's 40h paragraphs (1Kb).  See
; the discussion below ("Determine a reasonable amount to add to the minimum").
;
lp3:	add	ax,15
	adc	dx,0			; round DX:AX to next paragraph
	mov	cx,16
	cmp	dx,cx			; can we safely divide DX:AX by 16?
	ja	lpc2			; no, the program is much too large
	div	cx			; AX = # paras
	mov	si,ax			; SI = # paras in file
	add	ax,50h			; AX = min paras (10h for PSP + 40h)
	cmp	ax,[bp].TMP_DX		; can the segment accommodate that?
	ja	lpc2			; no

	sub	cx,cx
	sub	dx,dx
	mov	ax,(DOS_HDL_SEEK SHL 8) OR SEEK_BEG
	int	21h			; reset file position to beginning
	jc	lpc1
;
; Regardless whether this is a COM or EXE file, we're going to read the first
; 512 bytes (or less if that's all there is) and decide what to do next.
;
	push	ds
	pop	es			; DS = ES = PSP segment
	mov	dx,size PSP
	mov	[bp].TMP_ES,ds
	mov	[bp].TMP_BX,dx
	mov	cx,200h
	mov	ah,DOS_HDL_READ		; BX = file handle, CX = # bytes
	int	21h
	jnc	lp6
lpc1:	jmp	lpc
lpc2:	mov	ax,ERR_NOMEMORY
	jmp	short lpc1

lp6:	mov	di,dx			; DS:DI -> end of PSP
	cmp	[di].EXE_SIG,SIG_EXE
	je	lp6a
	jmp	lp7
lpf1:	jmp	lpf

lp6a:	cmp	ax,size EXEHDR
	jb	lpc2			; file too small
;
; Load the EXE file.  First, we move all the header data we've already read
; to the top of the allocated memory, then determine how much more header data
; there is to read, read that as well, and then read the rest of the file
; into the bottom of the allocated memory.
;
	mov	dx,ds
	add	dx,si
	add	dx,10h
	sub	dx,[di].EXE_PARASHDR

	push	si			; save allocated paras
	push	es
	mov	si,di			; DS:SI -> actual EXEHDR
	sub	di,di
	mov	es,dx			; ES:DI -> space for EXEHDR
	mov	cx,ax			; CX = # of bytes read so far
	shr	cx,1
	rep	movsw			; move them into place
	jnc	lp6b
	movsb
lp6b:	mov	ds,dx
	mov	dx,di			; DS:DX -> space for remaining hdr data
	pop	es
	pop	si

	mov	cl,4
	shr	ax,cl			; AX = # paras read
	mov	di,ds:[0].EXE_PARASHDR
	sub	di,ax			; DI = # paras left to read
	ASSERT	NC
	shl	di,cl			; DI = # bytes left to read
	mov	cx,di			; CX = # bytes
	jcxz	lp6c
	mov	ah,DOS_HDL_READ		; BX = file handle, CX = # bytes
	int	21h
	jc	lpc1

lp6c:	push	es
	push	ds
	pop	es			; ES = header segment
	pop	dx			; DX = PSP segment
	add	dx,10h
lp6d:	mov	ds,dx
	sub	dx,dx			; DS:DX -> next read location
	mov	cx,32 * 1024		; read 32K at a time
	mov	ah,DOS_HDL_READ		; BX = file handle, CX = # bytes
	int	21h
	jc	lpc1
	mov	dx,ds
	cmp	ax,cx			; done?
	jb	lp6e			; presumably
	add	dx,800h			; add 32K of paras to segment
	jmp	lp6d
;
; Time to start working through the relocation entries in the ES segment.
;
lp6e:	add	ax,15
	mov	cl,4
	shr	ax,cl
	add	dx,ax			; DX = next available segment
	call	get_psp
	add	ax,10h			; AX = base segment of EXE
	mov	cx,es:[EXE_NRELOCS]
	mov	di,es:[EXE_OFFRELOC]	; ES:DI -> first relocation entry
	jcxz	lp6g			; it's always possible there are none
lp6f:	mov	bx,es:[di].OFF		; BX = offset
	mov	si,es:[di].SEG		; SI = segment
	add	si,ax
	mov	ds,si
	add	[bx],ax			; add base segment to DS:[BX]
	add	di,4
	loop	lp6f
;
; DX - (AX - 10h) is the base # of paragraphs required for the EXE.  Add the
; minimum specified in the EXEHDR.
;
; TODO: Decide what to do about the maximum.  The default setting seems to be
; "give me all the memory" (eg, FFFFh), which we do not want to do.
;
lp6g:	push	es:[EXE_START_SEG]
	push	es:[EXE_START_OFF]
	push	es:[EXE_STACK_SEG]
	push	es:[EXE_STACK_OFF]
	mov	si,es:[EXE_PARASMIN]
	IFDEF DEBUG
	mov	di,es:[EXE_PARASMAX]
	ENDIF
	sub	ax,10h
	mov	es,ax			; ES = PSP segment
	sub	dx,ax			; DX = base # paras
	add	dx,si			; DX = base + minimum
	mov	bx,dx			; BX = realloc size (in paras)
;
; TODO: Determine a reasonable amount to add to the minimum.  SYMDEB.EXE 4.0
; was the first non-BASIC-DOS EXE I tried to load, and if I provided only its
; minimum of 11h paragraphs (for a total of 90Bh), it would trash the memory
; arena when creating a PSP, so it's unclear the minimum, at least in SYMDEB's
; case, can be fully trusted.
;
; More info on SYMDEB.EXE 4.0 and PC DOS 2.00: it seems the smallest amount of
; free memory where DOS 2.0 will still load SYMDEB is when COMMAND.COM "owns"
; at least 967h paras in the final memory segment (CHKDSK reports 38336 bytes
; free at that point; SYMDEB.EXE is 37021 bytes).
;
; The PSP that SYMDEB created under those conditions was located at 7FAFh
; (this was on a 512K machine so the para limit was 8000h), so the PSP had 51h
; paragraphs available to it.  However, SYMDEB could not load even a tiny
; (11-byte) COM file; it would report "EXEC failure", which seems odd with 51h
; paragraphs available.  Also, the word at 7FAF:0006 (memory size) contained
; 8460h, which seems way too large.
;
; I also discovered that if I tried to load "SYMDEB E.COM" (where E.COM was an
; 11-byte COM file) with 8 more paras available (96Fh total), the system would
; crash while trying to load E.COM.  I haven't investigated further, so it's
; unclear if the cause is a DOS/EXEC bug or a SYMDEB bug.
;
; Anyway, since BASIC-DOS can successfully load SYMDEB.EXE 4.0 with only 92Bh
; paras (considerably less than 967h), either we're being insufficiently
; conservative, or PC DOS had some EXEC overhead (perhaps in the transient
; portion of COMMAND.COM) that it couldn't eliminate.
;
; NOTE: DEBUG.COM from PC DOS 2.00 has a file size of 11904 bytes (image size
; 2F80h) and resets its stack pointer to 2AE2h, which is an area that's too
; small to safely run in BASIC-DOS:
;
;	083B:011C BCE22A           MOV      SP,2AE2
;	...
;	083B:0211 BCE22A           MOV      SP,2AE2
;
; If we want to run such apps (which we don't), we'll have to detect them and
; implement stack switching (which we won't).
;
; DEBUG.COM from PC DOS 1.00 has a file size of 6049 bytes (image size 18A1h)
; and resets its stack pointer to 17F8h, but it's less susceptible to problems
; since copyright and error message strings are located below the stack.
;
	add	bx,40h			; add another 1Kb (in paras)

	mov	ds,ax			; DS = PSP segment
	add	ax,10h			; AX = EXE base segment (again)
	pop	ds:[PSP_STACK].OFF
	pop	ds:[PSP_STACK].SEG
	add	ds:[PSP_STACK].SEG,ax
	pop	ds:[PSP_START].OFF
	pop	ds:[PSP_START].SEG
	add	ds:[PSP_START].SEG,ax

	DPRINTF	'p',<"New PSP %04x, %04x paras, min,max=%04x,%04x\r\n">,ds,bx,si,di

	sub	dx,dx			; no heap
	jmp	lp8			; realloc the PSP segment
;
; Load the COM file.  All we have to do is finish reading it.
;
lp7:	add	dx,ax
	cmp	ax,cx
	jb	lp7a			; we must have already finished
	sub	si,20h
	mov	cl,4
	shl	si,cl
	mov	cx,si			; CX = maximum # bytes left to read
	mov	ah,DOS_HDL_READ
	int	21h
	jc	lpc3
	add	dx,ax			; DX -> end of program image
;
; We could leave the executable file open and close it on process termination,
; because it provides us with valuable information about all the processes that
; are running (info that perhaps should have been recorded in the PSP).  The
; handle could eventually be useful for overlay support, too.  But for now,
; we close the handle, just like PC DOS.
;
lp7a:	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the file
	jnc	lp7b
	jmp	lpf
lpc3:	jmp	lpc

lp7b:	mov	ds:[PSP_START].OFF,100h
	mov	ds:[PSP_START].SEG,ds
	mov	di,dx			; DI -> uninitialized heap space
	mov	dx,MINHEAP SHR 4	; DX = additional space (1Kb in paras)
;
; Check the word at [DI-2]: if it contains SIG_BASICDOS ("BD"), then the
; image ends with COMDATA, where the preceding word (CD_HEAPSIZE) specifies
; the program's desired additional memory (in paras).
;
	cmp	word ptr [di - 2],SIG_BASICDOS
	jne	lp7e
	mov	ax,[di - size COMDATA].CD_HEAPSIZE; AX = heap size, in paras
	cmp	ax,dx			; larger than our minimum?
	jbe	lp7c			; no
	xchg	dx,ax			; yes, set DX to the larger value
;
; Since there's a COMDATA structure, fill in the relevant PSP fields.
; In addition, if a code size is specified, checksum the code, and then
; see if there's another block with the same code.
;
lp7c:	mov	cx,[di - size COMDATA].CD_CODESIZE
	mov	ds:[PSP_CODESIZE],cx	; record end of code
	mov	ds:[PSP_HEAPSIZE],dx	; record heap size
	mov	ds:[PSP_HEAP],di	; by default, heap starts after COMDATA
	jcxz	lp7d			; but if a code size was specified
	mov	ds:[PSP_HEAP],cx	; heap starts at the end of the code

lp7d:	call	psp_calcsum		; calc checksum for code
	mov	ds:[PSP_CHECKSUM],ax	; record checksum (zero if unspecified)
	jcxz	lp7e
;
; We found another copy of the code segment (CX), so we can move everything
; from PSP_CODESIZE to DI down to 100h, and then set DI to the new program end.
;
; The bytes, if any, between PSP_CODESIZE and the end of the COMDATA structure
; (which is where DI is now pointing) represent statically initialized data
; that is also considered part of the program's "heap".
;
	mov	ds:[PSP_START].SEG,cx
	mov	si,ds:[PSP_CODESIZE]
	mov	cx,di
	sub	cx,si
	mov	di,100h
	mov	ds:[PSP_HEAP],di	; record the new heap offset
	rep	movsb			; DI -> uninitialized heap space
	mov	[bp].TMP_CX,cx		; this program image can't be cached

lp7e:	mov	bx,di			; BX = size of program image
	add	bx,15
	mov	cl,4
	shr	bx,cl			; BX = size of program (in paras)
	add	bx,dx			; add additional space (in paras)
	mov	ax,bx
	cmp	ax,1000h
	jb	lp7f
	mov	ax,1000h
lp7f:	shl	ax,cl			; DS:AX -> top of the segment
	mov	ds:[PSP_STACK].OFF,ax
	mov	ds:[PSP_STACK].SEG,ds

	DPRINTF	'p',<"New PSP %04x, %04x paras, stack @%08lx\r\n">,ds,bx,ax,ds

lp8:	mov	ah,DOS_MEM_REALLOC	; resize ES memory block to BX paras
	int	21h
	jnc	lp8a
	jmp	lpf
;
; Zero any additional heap paragraphs (DX) starting at ES:DI.  Note that
; although heap size is specified in paragraphs, it's not required to start
; on a paragraph boundary, so there may be some unused (and uninitialized)
; bytes at the end of the heap.
;
lp8a:	test	dx,dx			; additional heap?
	jz	lp8b			; no
	mov	cl,3
	shl	dx,cl			; convert # paras to # words
	mov	cx,dx
	sub	ax,ax
	rep	stosw			; zero the words

lp8b:	mov	dx,es
	push	cs
	pop	ds
	ASSUME	DS:DOS
	call	psp_setmem		; DX = PSP segment to update
	call	mcb_setname		; ES = PSP segment
;
; Since we're past the point of no return now, let's take care of some
; initialization outside of the program segment; namely, resetting the CTRLC
; and ERROR handlers to their default values.  And as always, we set these
; handlers inside the SCB rather than the IVT (exactly as DOS_MSC_SETVEC does).
;
	mov	bx,[scb_active]
	mov	[bx].SCB_CTRLC.OFF,offset dos_ctrlc
	mov	[bx].SCB_CTRLC.SEG,cs
	mov	[bx].SCB_ERROR.OFF,offset dos_error
	mov	[bx].SCB_ERROR.SEG,cs
;
; Initialize the DTA to its default (PSP:80h), while simultaneously preserving
; the previous DTA in the new PSP.
;
	mov	ax,80h
	xchg	[bx].SCB_DTA.OFF,ax
	mov	es:[PSP_DTAPREV].OFF,ax
	mov	ax,es
	xchg	[bx].SCB_DTA.SEG,ax
	mov	es:[PSP_DTAPREV].SEG,ax
;
; Create an initial REG_FRAME at the top of the stack segment.
;
; TODO: Verify that we're setting proper initial values for all the registers.
;
	push	es
	pop	ds
	ASSUME	DS:NOTHING
	les	di,ds:[PSP_STACK]	; ES:DI -> stack (NOT PSP)
	dec	di
	dec	di
	std
	mov	dx,ds:[PSP_START].OFF	; CX:DX = start address
	mov	cx,ds:[PSP_START].SEG
;
; NOTE: Pushing a zero on the top of the program's stack is expected by
; COM files, but what about EXE files?  Do they have the same expectation
; or are we just wasting a word (or worse, confusing them)?
;
	sub	ax,ax
	stosw				; store a zero at the top of the stack

	mov	ax,FL_DEFAULT
	stosw				; REG_FL (with interrupts enabled)
	xchg	ax,cx
	stosw				; REG_CS
	xchg	ax,dx
	stosw				; REG_IP
	sub	ax,ax
	REPT (size WS_TEMP) SHR 1
	stosw				; REG_WS
	ENDM
;
; TODO: Set AL to 0FFh if the 1st filespec drive is invalid; ditto for AH
; if the 2nd filespec drive is invalid.  I don't believe any of the other
; general-purpose registers have any special predefined values, so zero is OK.
;
	stosw				; REG_AX
	stosw				; REG_BX
	stosw				; REG_CX
	stosw				; REG_DX
	mov	ax,ds			; DS = PSP segment
	stosw				; REG_DS
	sub	ax,ax
	stosw				; REG_SI
	mov	ax,ds			; DS = PSP segment
	stosw				; REG_ES
	sub	ax,ax
	stosw				; REG_DI
	stosw				; REG_BP
	IF REG_CHECK
	mov	ax,offset dos_check
	stosw
	ENDIF
	inc	di
	inc	di			; ES:DI -> REG_BP
	cld
	add	sp,2			; discard original PSP
	jmp	short lp9
;
; Error paths (eg, close the file handle, free the memory for the new PSP)
;
lpc:	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	ax

lpf:	push	ax
	push	cs
	pop	ds
	ASSUME	DS:DOS
	call	psp_close
	call	get_psp
	mov	es,ax
	mov	ah,DOS_MEM_FREE
	int	21h
	pop	ax
	pop	dx			; DX = original PSP
	xchg	ax,dx			; AX = original PSP, DX = error code
	call	set_psp			; update PSP
	xchg	ax,dx			; AX = error code
	stc

lp9:	UNLOCK_SCB
	ret
ENDPROC	load_program

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_calcsum
;
; Inputs:
;	DS:100h -> bytes to checksum
;	CX = end of region to checksum
;
; Outputs:
;	AX = 16-bit checksum
;	CX = segment with matching checksum (zero if none)
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	psp_calcsum
	ASSUME	DS:NOTHING, ES:NOTHING

	push	dx
	sub	dx,dx
	jcxz	crc8
	push	cx
	mov	si,100h			; SI -> 1st byte to sum
	sub	cx,si			; CX = # bytes to checksum
	shr	cx,1			; CX = # words
crc1:	lodsw
	add	dx,ax
	loop	crc1
	pop	ax
;
; Scan the arena for a PSP block with matching PSP_CODESIZE and PSP_CHECKSUM.
;
	push	es
	mov	si,[mcb_head]
crc2:	mov	es,si
	ASSUME	ES:NOTHING
	inc	si
	mov	cx,es:[MCB_OWNER]
	jcxz	crc5
	cmp	cx,si			; MCB_OWNER = PSP?
	jne	crc5			; no
	cmp	es:[size MCB].PSP_CODESIZE,ax
	jne	crc5
	cmp	es:[size MCB].PSP_CHECKSUM,dx
	jne	crc5
	mov	cx,si			; CX = matching segment
	jmp	short crc7		; done scanning
crc5:	cmp	es:[MCB_SIG],MCBSIG_LAST
	jne	crc6
	sub	cx,cx			; CX = zero (no match found)
	jmp	short crc7		; done scanning
crc6:	add	si,es:[MCB_PARAS]
	jmp	crc2
crc7:	pop	es

crc8:	xchg	ax,dx			; AX = checksum
	pop	dx
	ret
ENDPROC	psp_calcsum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_close
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	psp_close,DOS
	mov	cx,size PSP_PFT
	sub	bx,bx			; BX = handle (PFH)
cp1:	call	pfh_close		; close process file handle
	inc	bx
	loop	cp1
	ret
ENDPROC	psp_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_init
;
; Helper for psp_copy and psp_create APIs.  PSP fields up to (but not
; including) PSP_PARENT are initialized.
;
; Inputs:
;	REG_DX = segment of new PSP
;
; Outputs:
;	AX = active PSP
;	BX -> active SCB
;	ES:DI -> PSP_PARENT of new PSP
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	psp_init,DOS
	mov	dx,[bp].REG_DX
	call	psp_setmem		; DX = PSP segment to initialize
	ASSUME	ES:NOTHING
;
; On return from psp_setmem, ES = PSP segment and DI -> PSP_EXRET.
;
; Copy current INT 22h (EXRET), INT 23h (CTRLC), and INT 24h (ERROR) vectors,
; but copy them from the SCB, not the IVT.
;
	mov	bx,[scb_active]		; BX = active SCB
	lea	si,[bx].SCB_EXRET
	mov	cx,6
	rep	movsw
	call	get_psp			; AX = active PSP
	ret
ENDPROC	psp_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_setmem
;
; This is called by psp_copy and psp_create to initialize the first 10 bytes
; of the PSP, as well as by load_program after a program has been loaded and
; the PSP has been resized, requiring many of those bytes to be updated again.
;
; Inputs:
;	DX = PSP segment
;
; Outputs:
;	ES = PSP segment
;	DI -> PSP_EXRET of PSP
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	psp_setmem,DOS
	ASSUME	ES:NOTHING
	mov	bx,[mcb_limit]		; BX = fallback memory limit
	call	mcb_getsize		; if segment has a size, get it
	jc	ps1			; nope, use BX
	mov	bx,dx
	add	bx,ax			; BX = actual memory limit
	ASSERT	NZ,<test cx,cx>
	jcxz	ps1			; jump if segment unowned (unusual)
	dec	dx
	mov	es,dx			; ES -> MCB
	inc	dx
	mov	es:[MCB_OWNER],dx	; set MCB owner to PSP
ps1:	mov	es,dx
	sub	di,di			; start building the new PSP at ES:0
	mov	ax,20CDh
	stosw				; 00h: PSP_EXIT
	xchg	ax,bx
	stosw				; 02h: PSP_PARAS (ie, memory limit)
	xchg	bx,ax			; save PSP_PARAS in BX
	call	scb_getnum		; 04h: SCB #
	mov	ah,9Ah			; 05h: PSP_FARCALL (9Ah)
	stosw
	sub	bx,dx			; BX = PSP_PARAS - PSP segment
	sub	ax,ax			; default to 64K
	mov	cl,4
	cmp	bx,1000h		; 64K or more available?
	jae	ps3			; yes
	shl	bx,cl			; BX = number of bytes available
	xchg	ax,bx
ps3:	sub	ax,256			; AX = max available bytes this segment
	stosw				; 06h: PSP_SIZE
;
; Compute the code segment which, when shifted left 4 and added to AX, yields
; wrap-around linear address 000C0h, aka INT_DOSCALL5 * 4.
;
	xchg	bx,ax
	shr	bx,cl
	mov	ax,(INT_DOSCALL5 * 4) SHR 4
	sub	ax,bx			; basically, compute 000Ch - (BX SHR 4)
	stosw				; 08h: PSP_FCSEG
	ret
ENDPROC	psp_setmem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_psp
;
; In BASIC-DOS, this replaces all references to (the now obsolete) psp_active.
;
; Inputs:
;	None
;
; Outputs:
;	AX = segment of current PSP (zero if none; ZF set as well)
;
DEFPROC	get_psp,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	sub	ax,ax
	mov	bx,[scb_active]
	test	bx,bx
	jz	gp9
	ASSERT	STRUCT,cs:[bx],SCB
	mov	ax,cs:[bx].SCB_PSP
	test	ax,ax
gp9:	pop	bx
	ret
ENDPROC	get_psp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_psp
;
; In BASIC-DOS, this replaces all references to (the now obsolete) psp_active.
;
; Inputs:
;	AX = segment of new PSP
;
; Outputs:
;	None
;
DEFPROC	set_psp,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	mov	bx,[scb_active]
	ASSERT	STRUCT,cs:[bx],SCB
	mov	cs:[bx].SCB_PSP,ax
	pop	bx
	ret
ENDPROC	set_psp

DOS	ends

	end
