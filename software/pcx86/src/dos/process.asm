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
	EXTERNS	<mcb_limit,scb_active,psp_active>,word
	EXTERNS	<sfh_addref,pfh_close,sfh_close>,near
	EXTERNS	<free,dos_exit,dos_ctrlc,dos_error>,near
	EXTERNS	<get_scbnum,scb_unload,scb_yield>,near
	IF REG_CHECK
	EXTERNS	<dos_check>,near
	ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	sub	ax,ax			; default exit code/exit type

	DEFLBL	psp_term_exitcode,near
	ASSERT	Z,<cmp [scb_locked],-1>	; SCBs should never be locked now

	mov	es,[psp_active]
	ASSUME	ES:NOTHING
	mov	si,es:[PSP_PARENT]

	test	si,si			; if there's a parent
	jnz	pt1			; then the SCB is still healthy
	cmp	es:[PSP_SCB],0		; are we allowed to kill this SCB?
	je	pt7			; no
;
; Close process file handles.
;
pt1:	push	ax			; save exit code/exit type on stack
	mov	cx,size PSP_PFT
	sub	bx,bx			; BX = handle (PFH)
pt2:	call	pfh_close		; close process file handle
	inc	bx
	loop	pt2
;
; Restore the SCB's CTRLC and ERROR handlers from the values in the PSP.
;
	mov	bx,[scb_active]
	push	bx
	mov	bl,[bx].SCB_SFHCON
	call	sfh_close
	pop	bx
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
	mov	[bx].SCB_DTA.OFF,ax	; ("REAL DOS" probably requires every
	mov	ax,es:[PSP_DTAPREV].SEG	;  process to restore this itself after
	mov	[bx].SCB_DTA.SEG,ax	;  an exec)

	mov	al,es:[PSP_SCB]		; save SCB #
	push	ax
	push	si			; save PSP of parent
	mov	ax,es
	call	free			; free PSP in AX
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
	mov	[psp_active],es
	cli
	mov	ss,es:[PSP_STACK].SEG
	mov	sp,es:[PSP_STACK].OFF
	mov	bp,sp
	IF REG_CHECK
	add	bp,2
	ENDIF
	mov	[bp].REG_CS,cx		; copy PSP_EXRET to caller's CS:IP
	mov	[bp].REG_IP,dx		; (normally they will be identical)
	jmp	dos_exit		; we'll let dos_exit turn interrupts on

pt9:	ret
ENDPROC	psp_term

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_create (REG_AH = 26h)
;
; Apparently, this is more of a "copy" function than a "create" function,
; especially starting with DOS 2.0, which copies the PSP from the caller's
; CS:0 (although the INT 22h/23h/24h addresses may still be copied from the
; IVT).  As a result, any PSP "created" with this function automatically
; "inherits" all of the caller's open files.
;
; Well, the first time we call it (from sysinit), there are no existing PSPs,
; so there's nothing to copy.  And if we want to create a PSP with accurate
; memory information, we either need more inputs OR we have to assume that the
; new segment was allocated with DOS_MEM_ALLOC (we assume the latter).
;
; A new psp_create function (REG_AH = 55h) solved a few problems: it
; automatically increments reference counts for all "inheritable" files, it
; marks all "uninheritable" files as closed in the new PSP, and as of DOS 3.0,
; it uses SI to specify a memory size.
;
; TODO: Mimic the "copy" behavior when we're not being called by sysinit (ie,
; whenever psp_active is valid).
;
; Inputs:
;	REG_DX = segment of new PSP
;
; Outputs:
;	None
;
DEFPROC	psp_create,DOS
	mov	bx,[mcb_limit]		; BX = fallback memory limit
	mov	dx,[bp].REG_DX
	dec	dx
	mov	es,dx			; ES:0 -> MCB
	ASSUME	ES:NOTHING
	mov	al,es:[MCB_SIG]		; MCB signature sanity check
	cmp	al,MCBSIG_NEXT
	je	pc1
	cmp	al,MCBSIG_LAST
	jne	pc2
pc1:	mov	bx,es:[MCB_PARAS]	; BX = actual available paragraphs
	add	bx,dx
	inc	bx			; BX = actual memory limit
pc2:	inc	dx
	mov	es,dx
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
	jae	pc3			; yes
	shl	bx,cl			; BX = number of bytes available
	xchg	ax,bx
pc3:	sub	ax,256			; AX = max available bytes this segment
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
;
; Copy current INT 22h (EXRET), INT 23h (CTRLC), and INT 24h (ERROR) vectors,
; but copy them from the SCB, not the IVT.
;
	mov	bx,[scb_active]
	lea	si,[bx].SCB_EXRET
	mov	cx,6
	rep	movsw

	mov	ax,[psp_active]		; 16h: PSP_PARENT
	stosw
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
	mov	cl,15
	rep	stosb			; finish up PSP_PFT (20 bytes total)
	mov	cl,(100h - PSP_ENVSEG) SHR 1
	sub	ax,ax
	rep	stosw			; zero the rest of the PSP
	mov	di,PSP_DISPATCH
	mov	ax,21CDh
	stosw
	mov	al,0CBh
	stosb
	mov	al,' '
	mov	cl,size FCB_NAME
	mov	di,PSP_FCB1
	rep	stosb
	mov	cl,size FCB_NAME
	mov	di,PSP_FCB2
	rep	stosb
	mov	di,PSP_CMDTAIL + 1
	mov	al,0Dh
	stosb				; done for now
	ret
ENDPROC	psp_create

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_exec (REG_AX = 4Bh)
;
; Inputs:
;	REG_AL = exec code
;	REG_DS:REG_DX -> name of program
;	REG_ES:REG_BX -> exec parameter block (EPB)
;
; Outputs:
;	If successful, carry clear
;	If error, carry set, AX = error code
;
DEFPROC	psp_exec,DOS
	cmp	al,0
	jne	px9

	mov	es,[bp].REG_DS		; ES:DX -> name of program
	ASSUME	ES:NOTHING
	call	load_program
	ASSUME	DS:NOTHING
	jc	px9
;
; Now we deal with the EPB we've been given.  load_program already set up
; a default command tail in the PSP, but for this call, we must replace it.
;
; TODO: Add support for EPB_ENVSEG, EPB_FCB1, and EPB_FCB2.
;
	push	si
	push	di
	push	ds
	push	es
	mov	ds,[bp].REG_ES
	ASSUME	DS:NOTHING
	mov	si,[bp].REG_BX
	lds	si,[si].EPB_CMDTAIL
	mov	es,[psp_active]
	mov	di,PSP_CMDTAIL
	mov	cl,[si]
	mov	ch,0
	add	cx,2
	rep	movsb
	pop	es
	pop	ds
	pop	di
	pop	si
;
; Unlike scb_load, this is a "synchronous" operation, meaning we launch
; the program ourselves.
;
	cli
	push	es
	pop	ss
	mov	sp,di
	jmp	dos_exit		; we'll let dos_exit turn interrupts on

px9:	mov	[bp].REG_AX,ax		; return any error code in REG_AX
	ret
ENDPROC	psp_exec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	ds,[psp_active]
	mov	ax,word ptr ds:[PSP_EXCODE]
	mov	[bp].REG_AX,ax
	ret
ENDPROC	psp_retcode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_set (REG_AH = 50h)
;
; In BASIC-DOS, this only changes SCB_CURPSP, NOT the global psp_active.
;
; Inputs:
;	REG_BX = segment of new PSP
;
; Outputs:
;	None
;
DEFPROC	psp_set,DOS
	mov	ax,[bp].REG_BX
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	mov	[bx].SCB_CURPSP,ax
	ret
ENDPROC	psp_set

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_get (REG_AH = 51h)
;
; In BASIC-DOS, this only retrieves SCB_CURPSP, NOT the global psp_active.
;
; Inputs:
;	None
;
; Outputs:
;	REG_BX = segment of current PSP
;
DEFPROC	psp_get,DOS
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	mov	ax,[bx].SCB_CURPSP
	mov	[bp].REG_BX,ax
	ret
ENDPROC	psp_get

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	bx,10h			; alloc a new PSP segment
	mov	ah,DOS_MEM_ALLOC
	int	21h			; returns a new segment in AX
	jnc	lp1			; success
	jmp	lp9			; abort

lp1:	xchg	dx,ax			; DX = segment for new PSP
	xchg	di,ax			; DI = command-line (previously in DX)

	mov	ah,DOS_PSP_CREATE
	int	21h			; create new PSP at DX

	mov	bx,[psp_active]
	test	bx,bx
	jz	lp2
;
; Let's update the PSP_STACK field in the current PSP before we switch
; to the new PSP, since we rely on it to gracefully return to the caller
; when this new program terminates.  "REAL DOS" updates PSP_STACK on every
; DOS call, because it loves switching stacks all the time; we don't.
;
	mov	ds,bx
	ASSUME	DS:NOTHING
	mov	ax,sp
	add	ax,4			; toss 2 near-call return addresses
	mov	ds:[PSP_STACK].SEG,ss
	mov	ds:[PSP_STACK].OFF,ax

lp2:	push	bx			; save original PSP
	mov	[psp_active],dx		; we must update the *real* PSP now
;
; Since we stashed pointer to the command-line in DI, let's parse it now,
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
	mov	ds,[psp_active]		; DS = segment of new PSP
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
	add	ax,10h			; AX = # paras (plus PSP)
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
	cmp	[di].EXE_SIG,EXESIG
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
	mov	ax,[psp_active]
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
; minimum of 11h paragraphs, it would trash the memory arena when creating a
; PSP.
;
	add	bx,20h			; add another 0.5Kb (in paras)

	mov	ds,ax			; DS = PSP segment
	add	ax,10h			; AX = EXE base segment (again)
	pop	ds:[PSP_STACK].OFF
	pop	ds:[PSP_STACK].SEG
	add	ds:[PSP_STACK].SEG,ax
	pop	ds:[PSP_START].OFF
	pop	ds:[PSP_START].SEG
	add	ds:[PSP_START].SEG,ax
	IFDEF DEBUG
	PRINTF	<"min,cur,max paragraphs: %#06x,%#06x,%#06x",13,10>,si,bx,di
	ENDIF
	jmp	short lp8		; realloc the PSP segment
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
; we'll need the file handle anyway.
;
	; mov	ah,DOS_HDL_CLOSE
	; int	21h			; close the file
	; jc	lpef1
;
; Check the word at [BX-2]: if it contains BASICDOS_SIG ("BD"), then the
; preceding word must be the program's desired additional memory (in paras).
;
lp7b:	mov	bx,dx			; BX -> end of program file
	mov	dx,MINHEAP SHR 4	; minimum add'l space (1Kb in paras)
	cmp	word ptr [bx-2],BASICDOS_SIG
	jne	lp7c
	mov	ax,word ptr [bx-4]
	sub	bx,4			; don't count the BASIC_DOS sig words
	cmp	ax,dx			; larger than our minimum?
	jbe	lp7c			; no
	xchg	dx,ax			; yes, set DX to the larger value
lp7c:	add	bx,15
	mov	cl,4
	shr	bx,cl			; BX = size of program (in paras)
	add	bx,dx			; add add'l space (in paras)

	mov	di,bx
	cmp	di,1000h
	jb	lp7d
	mov	di,1000h
lp7d:	shl	di,cl			; ES:DI -> top of the segment
	mov	ds:[PSP_STACK].OFF,di
	mov	ds:[PSP_STACK].SEG,ds
	mov	ds:[PSP_START].OFF,100h
	mov	ds:[PSP_START].SEG,ds

lp8:	mov	ah,DOS_MEM_REALLOC	; resize the memory block in ES
	int	21h
lpef1:	jc	lpef			; TODO: try to use a smaller size?
;
; Mark the segment as being "owned" by the PSP now.
; TODO: Consider adding an interface for this operation.
;
	push	es
	mov	bx,es
	dec	bx
	mov	es,bx
	mov	es:[MCB_OWNER],ds
	pop	es
;
; Since we're past the point of no return now, let's take care of some
; initialization outside of the program segment; namely, resetting the CTRLC
; and ERROR handlers to their default values.  And as always, we set these
; handlers inside the SCB rather than the IVT (ie, exactly as DOS_MSC_SETVEC
; does).
;
	mov	bx,[scb_active]
	mov	cs:[bx].SCB_CTRLC.OFF,offset dos_ctrlc
	mov	cs:[bx].SCB_CTRLC.SEG,cs
	mov	cs:[bx].SCB_ERROR.OFF,offset dos_error
	mov	cs:[bx].SCB_ERROR.SEG,cs
;
; Initialize the DTA to its default (PSP:80h), while simultaneously preserving
; the previous DTA in the new PSP.
;
	mov	ax,80h
	xchg	cs:[bx].SCB_DTA.OFF,ax
	mov	ds:[PSP_DTAPREV].OFF,ax
	mov	ax,ds
	xchg	cs:[bx].SCB_DTA.SEG,ax
	mov	ds:[PSP_DTAPREV].SEG,ax
;
; Create an initial REG_FRAME at the top of the stack segment.
;
; TODO: Verify that we're setting proper initial values for all the registers.
;
	les	di,ds:[PSP_STACK]
	dec	di
	dec	di
	std
	mov	cx,ds:[PSP_START].SEG
	mov	dx,ds:[PSP_START].OFF	; CX:DX = start address
	sub	ax,ax
	stosw				; store a zero at the top of the stack
	mov	ax,FL_INTS
	stosw				; REG_FL (with interrupts enabled)
	mov	ax,cx
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
	xchg	ax,cx
	stosw				; REG_DS
	xchg	ax,cx
	stosw				; REG_SI
	xchg	ax,cx
	stosw				; REG_ES
	xchg	ax,cx
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
	mov	es,[psp_active]
	mov	ah,DOS_MEM_FREE
	int	21h
	pop	ax
	pop	[psp_active]		; restore original PSP
	stc

lp9:	ret
ENDPROC	load_program

DOS	ends

	end
