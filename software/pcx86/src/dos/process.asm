;
; BASIC-DOS Process Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<scb_locked>,byte
	EXTERNS	<mcb_head,mcb_limit,scb_active>,word
	EXTERNS	<sfh_addref,pfh_close,sfh_close>,near
	EXTERNS	<getsize,freeAll,dos_exit,dos_exit2,dos_ctrlc,dos_error>,near
	EXTERNS	<get_scbnum,scb_unload,scb_yield>,near
	IF REG_CHECK
	EXTERNS	<dos_check>,near
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
	cmp	es:[PSP_SCB],0		; are we allowed to kill this SCB?
	je	pt7			; no
;
; Close process file handles.
;
pt1:	push	ax			; save exit code/type on stack
	call	close_psp		; close all the process file handles
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
	call	freeAll			; free all blocks owned by PSP in AX
	pop	ax			; restore PSP of parent
	pop	cx			; CL = SCB #
;
; If this is a parent-less program, mark the SCB as unloaded and yield.
;
	test	ax,ax
	jnz	pt8
	call	scb_unload		; mark SCB # CL as unloaded
	jmp	scb_yield		; and call scb_yield with AX = zero
	ASSERT	NEVER
pt7:	jmp	short pt9

pt8:	mov	es,ax			; ES = PSP of parent
	pop	dx
	pop	cx			; we now have PSP_EXRET in CX:DX
	pop	ax			; AX = exit code (saved on entry above)
	mov	word ptr es:[PSP_EXCODE],ax
	mov	ax,es
	call	set_psp
	cli
	mov	ss,es:[PSP_STACK].SEG
	mov	sp,es:[PSP_STACK].OFF
	IF REG_CHECK
	add	sp,2
	ENDIF
	mov	bp,sp
;
; When a program (eg, SYMDEB.EXE) loads another program using DOS_PSP_EXEC1,
; it will necessarily be exec'ing the program itself, which means we can't be
; sure the stack used at the time of loading will be identical to the stack
; used at time of exec'ing.  So we will use dos_exit2 to bypass the REG_CHECK
; *and* we will create a fresh IRET frame at the top of REG_FRAME.
;
	mov	[bp].REG_IP,dx		; copy PSP_EXRET to caller's CS:IP
	mov	[bp].REG_CS,cx		; (normally they will be identical)
	mov	word ptr [bp].REG_FL,FL_DEFAULT
	jmp	dos_exit2		; we'll let dos_exit turn interrupts on

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
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	psp_create,DOS
	call	psp_init		; returns ES:DI -> PSP_PARENT
	stosw				; update PSP_PARENT
;
; Next up: the PFT (Process File Table); the first 5 PFT slots (PFHs) are
; predefined as STDIN (0), STDOUT (1), STDERR (2), STDAUX (3), and STDPRN (4),
; and apparently we're supposed to open an SFB for AUX first, CON second,
; and PRN third, so that the SFHs for the first five handles will always be:
; 1, 1, 1, 0, and 2.
;
	mov	al,[bx].SCB_SFHCON
	stosb
	stosb
	stosb
	mov	ah,3
	call	sfh_addref		; add 3 refs to this SFH
	mov	al,[bx].SCB_SFHAUX
	stosb
	mov	ah,1
	call	sfh_addref		; add 1 ref to this SFH
	mov	al,[bx].SCB_SFHPRN
	stosb
	mov	ah,1
	call	sfh_addref		; add 1 ref to this SFH
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
; psp_exec (REG_AX = 4Bh)
;
; TODO: Add support for EPB_ENVSEG.
;
; Inputs:
;	REG_AL = subfunction (only 0 and 1 are currently supported)
;	REG_DS:REG_DX -> name of program
;	REG_ES:REG_BX -> exec parameter block (EPB)
;
; Outputs:
;	If successful, carry clear
;	If error, carry set, AX = error code
;
DEFPROC	psp_exec,DOS
	cmp	al,2			; DOS_PSP_EXEC or DOS_PSP_EXEC1?
	cmc
	mov	ax,ERR_INVALID		; AX = error code if not
	jnb	px1			; yes
px0:	jmp	px9

px1:	mov	es,[bp].REG_DS		; ES:DX -> name of program
	ASSUME	ES:NOTHING
	call	load_program
	ASSUME	DS:NOTHING
	jc	px0			; hopefully AX contains an error code
;
; Now we deal with the EPB we've been given.  load_program already set up
; default FCBs and CMDTAIL in the PSP, but for this call, we must replace them.
;
	push	es			; save ES:DI (new program's stack)
	push	di

	mov	ds,[bp].REG_ES
	mov	si,[bp].REG_BX		; DS:SI is now caller's ES:BX (EPB)
	call	get_psp
	mov	es,ax			; ES -> PSP

	push	ds
	push	si
	lds	si,[si].EPB_FCB1
	mov	di,PSP_FCB1
	mov	cx,size FCB
	rep	movsb			; fill in PSP_FCB1
	pop	si
	pop	ds			; DS:SI -> EPB again
	push	ds
	push	si
	lds	si,[si].EPB_FCB2
	mov	di,PSP_FCB2
	mov	cx,size FCB
	rep	movsb			; fill in PSP_FCB2
	pop	si
	pop	ds			; DS:SI -> EPB again
	push	ds
	push	si
	lds	si,[si].EPB_CMDTAIL
	add	di,size PSP_RESERVED3
	mov	cl,[si]
	mov	ch,0
	add	cx,2
	rep	movsb			; fill in PSP_CMDTAIL
	pop	si
	pop	ds			; DS:SI -> EPB again

	pop	ax			; recover new program's stack in DX:AX
	pop	dx

	cmp	[bp].REG_AL,cl		; was AL zero?
	jne	px8			; no
;
; This was a DOS_PSP_EXEC call, and unlike scb_load, it's a synchronous
; exec, meaning we launch the program directly from this call.
;
	cli
	mov	ss,dx			; switch to the new program's stack
	mov	sp,ax
	jmp	dos_exit		; and let dos_exit turn interrupts on
;
; This was a DOS_PSP_EXEC1 call, an undocumented call that only loads the
; program, fills in the undocumented EPB_INIT_SP and EPB_INIT_IP fields,
; and then returns to the caller.
;
; Note that EPB_INIT_SP will normally be right below PSP_STACK (PSP:2Eh),
; since we push a zero word on the stack, and EPB_INIT_IP is identical to
; PSP_START (PSP:40h).
;
; The new PSP is still in ES, and DX:AX now points to the program's stack,
; which contains a REG_FRAME that the DOS_PSP_EXEC1 caller can't use.
; So we return a stack pointer with the REG_FRAME popped off, along with the
; REG_CS and REG_IP that was stored in the REG_FRAME.
;
; TODO: Determine why SYMDEB.EXE requires us to subtract another word from
; the stack pointer in AX, in addition to the zero word we already pushed.
;
px8:	mov	di,ax
	add	ax,size REG_FRAME + REG_CHECK - 2
	mov	[si].EPB_INIT_SP.OFF,ax
	mov	[si].EPB_INIT_SP.SEG,dx	; return the program's SS:SP
	; mov	es:[PSP_STACK].LOW,ax	; TODO: determine if mirroring the
	; mov	es:[PSP_STACK].HIW,dx	; stack pointer in the PSP is useful
	mov	es,dx
	les	di,dword ptr es:[di+REG_CHECK].REG_IP
	mov	[si].EPB_INIT_IP.OFF,di
	mov	[si].EPB_INIT_IP.SEG,es	; return the program's CS:IP
	clc
	ret

px9:	mov	[bp].REG_AX,ax		; return any error code in REG_AX
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
; load_program
;
; Inputs:
;	ES:DX -> name of program (or command-line)
;
; Outputs:
;	If successful, carry clear, ES:DI -> new stack
;	If error, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	load_program,DOS
	ASSUME	ES:NOTHING
;
; I used to start off with a small allocation (10h paras), since that's
; all we initially need for the PSP, but that can get us into trouble later
; if there isn't enough free space after the block.  So it's actually best
; to allocate the largest possible block now.  We'll shrink it down once
; we know how large the program is.
;
; Perhaps someday there will be a DOS_MEM_REALLOC function that can move a
; block for callers that can deal with movable blocks.  However, the utility
; of such a function might be minimal, since it still couldn't rearrange any
; blocks allocated by other callers.
;
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

lp1:	xchg	dx,ax			; DX = segment for new PSP
	xchg	di,ax			; DI = command-line (previously in DX)

	mov	ah,DOS_PSP_CREATE
	int	21h			; create new PSP at DX

	call	get_psp
	jz	lp2			; jump if no PSP exists yet
;
; Let's update the PSP_STACK field in the current PSP before we switch
; to the new PSP, since we rely on it to gracefully return to the caller
; when this new program terminates.  PC DOS updates PSP_STACK on every
; DOS call, because it loves switching stacks; we do not.
;
	mov	ds,ax
	ASSUME	DS:NOTHING
	mov	bx,bp
	IF REG_CHECK
	sub	bx,2
	ENDIF
	mov	ds:[PSP_STACK].OFF,bx
	mov	ds:[PSP_STACK].SEG,ss

lp2:	push	ax			; save original PSP
	xchg	ax,dx			; AX = new PSP
	call	set_psp
;
; Since we stashed the pointer to the command-line in DI, let's parse it now,
; separating the filename portion from the "tail" portion.
;
	mov	dx,di
	mov	cx,14			; CX = max filename length
lp3:	mov	al,es:[di]
	test	al,al
	jz	lp3b
	cmp	al,' '
	je	lp3a
	cmp	al,CHR_RETURN
	je	lp3a
	inc	di
	loop	lp3
lp3a:	mov	es:[di],ch		; null-terminate the filename
lp3b:	mov	cl,al			; CL = original terminator
	push	es
	pop	ds			; DS:DX -> name of program
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h			; open the file
	jnc	lp3c
	jmp	lpef
lp3c:	xchg	bx,ax			; BX = file handle
;
; Since we successfully opened the filename, let's massage the rest of the
; command-line now.  And before we do, let's also update the PSP EXRET address.
;
	push	bx
	call	get_psp
	mov	ds,ax			; DS = segment of new PSP
	mov	ax,[bp].REG_IP
	mov	ds:[PSP_EXRET].OFF,ax
	mov	ax,[bp].REG_CS
	mov	ds:[PSP_EXRET].SEG,ax

	mov	bx,offset PSP_CMDTAIL+1
	mov	es:[di],cl		; restore the original terminator
lp4:	mov	al,es:[di]
	inc	di
	test	al,al
	jz	lp5
	mov	[bx],al
	inc	bx
	cmp	bl,0FFh
	jb	lp4
lp5:	mov	byte ptr [bx],CHR_RETURN
	sub	bx,offset PSP_CMDTAIL+1
	mov	ds:[PSP_CMDTAIL],bl
	pop	bx

	sub	cx,cx
	sub	dx,dx
	mov	ax,(DOS_HDL_SEEK SHL 8) OR SEEK_END
	int	21h			; returns new file position in DX:AX
	jc	lpec1
;
; Now that we have a file size, we can reallocate the PSP segment to a size
; closer to what we actually need.  We won't know EXACTLY how much we need yet,
; because there might be a COMHEAP signature if it's a COM file, and EXE files
; have numerous unknowns at this point.  But having at LEAST as much memory
; as there are bytes in the file is a reasonable starting point.
;
	add	ax,15
	adc	dx,0			; round DX:AX to next paragraph
	mov	cx,16
	cmp	dx,cx			; can we safely divide DX:AX by 16?
	ja	lpec2			; no, the program is much too large
	div	cx			; AX = # paras
	push	ds
	pop	es			; ES = PSP segment
	mov	si,ax			; SI = # paras in file
	add	ax,50h			; AX = # paras (10h for PSP + 40h)
	push	bx			; save file handle
	xchg	bx,ax			; BX = new size in paras
	mov	ah,DOS_MEM_REALLOC
	int	21h			; resize the segment
	pop	bx			; restore file handle
	jc	lpec1			; we could be more forgiving; oh well

	sub	cx,cx
	sub	dx,dx
	mov	ax,(DOS_HDL_SEEK SHL 8) OR SEEK_BEG
	int	21h			; reset file position to beginning
	jc	lpec1
;
; We're going to make this code executable-agnostic, which means regardless
; whether it's a COM or EXE file, we're going to read the first 512 bytes (or
; less if that's all there is) and decide what to do next.
;
	push	es
	pop	ds
	mov	dx,size PSP
	mov	cx,200h
	mov	ah,DOS_HDL_READ		; BX = file handle, CX = # bytes
	int	21h
	jnc	lp6
lpec1:	jmp	lpec
lpec2:	mov	ax,ERR_NOMEM
	jmp	short lpec1

lp6:	mov	di,dx			; ES:DI -> end of PSP
	cmp	[di].EXE_SIG,SIG_EXE
	je	lp6a
	jmp	lp7
lp6a:	cmp	ax,size EXEHDR
	jb	lpec2			; file too small
;
; Load the EXE file.  First, we move all the header data we've already read
; to the top of the allocated memory, then determine how much more header data
; there is to read, read that as well, and then read the rest of the file
; into the bottom of the allocated memory.
;
	mov	dx,es
	add	dx,si
	add	dx,10h
	sub	dx,[di].EXE_PARASHDR

	push	si			; save allocated paras
	push	es			; save allocated segment
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
	jc	lpec1

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
	jc	lpec1
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
; free at that point).  The PSP that SYMDEB created under those conditions was
; located at 7FAFh (this was on a 512K machine so the para limit was 8000h),
; so the PSP had 51h paragraphs available to it.  However, SYMDEB could not
; load even a tiny (11-byte) COM file; it would report "EXEC failure", which
; seems odd with 51h paragraphs available.  Also, the word at 7FAF:0006 (memory
; size) contained 8460h, which seems way too large.
;
; I also discovered that if I tried to load "SYMDEB E.COM" (where E.COM was an
; 11-byte COM file) with 8 more paras available (96Fh total), the system would
; crash while trying to load E.COM.  I didn't investigate further (yet), so it
; is unclear if the cause is a DOS/EXEC bug or a SYMDEB bug.
;
; Anyway, since BASIC-DOS can successfully load SYMDEB.EXE 4.0 with only 92Bh
; paras (considerably less than 967h), either we're being insufficiently
; conservative, or PC DOS had some EXEC overhead (perhaps in the transient
; portion of COMMAND.COM) that it couldn't eliminate.
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

	DPRINTF	<"min,cur,max paragraphs: %#06x,%#06x,%#06x",13,10>,si,bx,di

	sub	dx,dx			; no heap
	jmp	lp8			; realloc the PSP segment
;
; Load the COM file.  All we have to do is finish reading it.
;
lp7:	add	dx,ax
	cmp	ax,cx
	jb	lp7b			; we must have already finished
	sub	si,20h
	mov	cl,4
	shl	si,cl
	mov	cx,si			; CX = maximum # bytes left to read
	mov	ah,DOS_HDL_READ
	int	21h
	jnc	lp7a
	jmp	lpec
lp7a:	add	dx,ax			; DX -> end of program file
;
; We now leave the executable file open and close it on process termination,
; because it provides us with valuable information about all the processes that
; are running (info that should have been recorded in the PSP but never was).
;
; Additionally, in order to support executables with overlays down the road,
; I assume we'll want the file handle anyway.
;
	; mov	ah,DOS_HDL_CLOSE
	; int	21h			; close the file
	; jc	lpef
;
; Check the word at [BX-2]: if it contains SIG_BASICDOS ("BD"), then the
; image ends with a COMDATA, where the preceding word (CD_HEAPSIZE) specifies
; the program's desired additional memory (in paras).
;
lp7b:	mov	ds:[PSP_START].OFF,100h
	mov	ds:[PSP_START].SEG,ds
	mov	bx,dx			; BX -> end of program file
	mov	dx,MINHEAP SHR 4	; minimum add'l space (1Kb in paras)
	cmp	word ptr [bx-2],SIG_BASICDOS
	jne	lp7e
	sub	bx,size COMDATA		; rewind BX to the COMDATA struc
	mov	ax,[bx].CD_HEAPSIZE	; AX = heap size, in paras
	cmp	ax,dx			; larger than our minimum?
	jbe	lp7c			; no
	xchg	dx,ax			; yes, set DX to the larger value
;
; Since there's a COMDATA structure, fill in the relevant PSP fields.
; In addition, if a code size is specified, checksum the code, and then
; see if there's another block with the same code.
;
lp7c:	mov	cx,[bx].CD_CODESIZE
	mov	ds:[PSP_CODESIZE],cx	; record end of code
	mov	ds:[PSP_HEAPSIZE],dx	; record heap size
	mov	ds:[PSP_HEAP],bx	; by default, heap starts at COMDATA
	jcxz	lp7d			; but if a code size was specified
	mov	ds:[PSP_HEAP],cx	; heap starts at the end of the code

lp7d:	call	psp_calcsum		; calc checksum for code
	mov	ds:[PSP_CHECKSUM],ax	; record checksum (zero if unspecified)
	jcxz	lp7e
;
; We found another copy of the code segment (CX), so we can move everything
; from PSP_CODESIZE to BX down to 100h, and then set BX to the new program end.
;
; TODO: While sharing a code segment (more precisely, the initial code-only
; portion of a COM segment) is a nice feature of BASIC-DOS, it would be even
; nicer if we could do it without re-reading the entire COM image again.
; We really need to 1) move the COMDATA structure near the beginning of the
; image (ie, within the first 512 bytes), 2) include a precalculated checksum
; of the code-only portion in COMDATA, and 3) search for an existing PSP with
; a matching PSP_CHECKSUM.
;
; The bytes, if any, between PSP_CODESIZE and the COMDATA structure (which is
; where BX is now pointing) represent statically initialized data that is also
; considered part of the program's "heap".
;
	mov	ds:[PSP_START].SEG,cx
	mov	si,ds:[PSP_CODESIZE]
	mov	cx,bx
	sub	cx,si
	mov	di,100h
	mov	ds:[PSP_HEAP],di	; record the new heap offset
	rep	movsb
	mov	bx,di

lp7e:	add	bx,15
	mov	cl,4
	shr	bx,cl			; BX = size of program (in paras)
	add	bx,dx			; add add'l space (in paras)

	mov	di,bx
	cmp	di,1000h
	jb	lp7f
	mov	di,1000h
lp7f:	shl	di,cl			; ES:DI -> top of the segment
	mov	ds:[PSP_STACK].OFF,di
	mov	ds:[PSP_STACK].SEG,ds

lp8:	mov	ah,DOS_MEM_REALLOC	; resize ES memory block to BX
	int	21h
	jnc	lp8a
	jmp	lpef			; TODO: try to use a smaller size?
;
; Zero the additional heap paragraphs requested, if any.
;
lp8a:	test	dx,dx
	jz	lp8b
	sub	bx,dx			; BX = 1st para to zero
	mov	cl,4
	shl	bx,cl			; convert BX to offset within ES
	dec	cx
	shl	dx,cl			; convert # paras to number of words
	mov	cx,dx
	sub	ax,ax
	mov	di,bx
	rep	stosw			; zero the words

lp8b:	mov	dx,es
	push	cs
	pop	ds
	ASSUME	DS:DOS
	call	psp_setmem		; DX = PSP segment to update
;
; Since we're past the point of no return now, let's take care of some
; initialization outside of the program segment; namely, resetting the CTRLC
; and ERROR handlers to their default values.  And as always, we set these
; handlers inside the SCB rather than the IVT (ie, exactly as DOS_MSC_SETVEC
; does).
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

	mov	ax,FL_INTS
	stosw				; REG_FL (with interrupts enabled)
	xchg	ax,cx
	stosw				; REG_CS
	xchg	ax,dx
	stosw				; REG_IP
	sub	ax,ax
	REPT (size WS_TEMP) SHR 1
	stosw				; REG_WS
	ENDM
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
lpec:	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	ax

lpef:	push	ax
	push	cs
	pop	ds
	ASSUME	DS:DOS
	call	close_psp
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

lp9:	ret
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
	call	getsize			; if segment has a size, get it
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
	call	get_scbnum		; 04h: SCB #
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
	mov	ax,cs:[bx].SCB_CURPSP
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
	mov	cs:[bx].SCB_CURPSP,ax
	pop	bx
	ret
ENDPROC	set_psp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; close_psp
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
DEFPROC	close_psp,DOS
	mov	cx,size PSP_PFT
	sub	bx,bx			; BX = handle (PFH)
pc1:	call	pfh_close		; close process file handle
	inc	bx
	loop	pc1
	ret
ENDPROC	close_psp

DOS	ends

	end
