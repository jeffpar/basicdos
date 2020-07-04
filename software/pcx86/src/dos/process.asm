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

	EXTERNS	<mcb_limit,scb_active,psp_active>,word
	EXTERNS	<free,get_scbnum,dos_exit,dos_ctrlc,dos_error>,near
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
	mov	es,[psp_active]
	ASSUME	ES:NOTHING
;
; TODO: Close file handles, once psp_create has been updated to make
; additional handle references.
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

	mov	ax,es:[PSP_DTAPREV].OFF	; restore the current process' DTA
	mov	[bx].SCB_DTA.OFF,ax	; ("REAL DOS" probably requires every
	mov	ax,es:[PSP_DTAPREV].SEG	;  process to restore this itself after
	mov	[bx].SCB_DTA.SEG,ax	;  an exec)

	push	es:[PSP_PARENT]		; save PSP of parent
	mov	ax,es
	call	free			; free PSP in AX
	pop	ax			; restore PSP of parent
	test	ax,ax
	ASSERT	NZ			; if there's no parent
	jz	pt9			; we don't have a stack to switch to
	mov	es,ax			; ES = PSP of parent
	pop	ax
	pop	dx			; we now have PSP_EXRET in DX:AX
	mov	[psp_active],es
	cli
	mov	ss,es:[PSP_STACK].SEG
	mov	sp,es:[PSP_STACK].OFF
	mov	bp,sp
	IF REG_CHECK
	add	bp,2
	ENDIF
	mov	[bp].REG_CS,dx		; copy PSP_EXRET to caller's CS:IP
	mov	[bp].REG_IP,ax		; (normally they will be identical)
	jmp	dos_exit		; we'll let dos_exit turn interrupts on
pt9:	ret
ENDPROC	psp_term

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_create (REG_AH = 26h)
;
; Apparently, this is more of a "copy" function than a "create" function,
; especially starting with DOS 2.0, which apparently assumed that the PSP to
; copy is at the caller's CS:0 (although the INT 22h/23h/24h addresses may
; still be copied from the IVT instead).  As a result, any PSP "created" with
; this function automatically inherits all of the caller's open files.
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
; We can mimic the "copy" behavior later, if need be, perhaps by relying on
; whether psp_active is set.
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
	mov	al,[bx].SCB_SFHAUX
	stosb
	mov	al,[bx].SCB_SFHPRN
	stosb
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
	mov	ss,dx
	mov	sp,di
	jmp	dos_exit		; we'll let dos_exit turn interrupts on

px9:	mov	[bp].REG_AX,ax		; return any error code in REG_AX
	ret
ENDPROC	psp_exec

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
;	If successful, carry clear, DX:DI -> new stack
;	If error, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	load_program,DOS
	ASSUME	ES:NOTHING
	mov	bx,1000h		; alloc 64K
	mov	ah,DOS_MEM_ALLOC
	int	21h			; returns a new segment in AX
	jnc	lp2
	cmp	bx,11h			; is there a usable amount of memory?
	jb	lp1			; no
	mov	ah,DOS_MEM_ALLOC	; try again with max paras in BX
	int	21h
	jnc	lp2			; success
lp1:	jmp	lp9			; abort

lp2:	sub	bx,10h			; subtract paras for the PSP header
	mov	cl,4
	shl	bx,cl			; convert to bytes
	mov	si,bx			; SI = bytes for new PSP
	xchg	dx,ax			; DX = segment for new PSP
	xchg	di,ax			; DI = command-line (previously in DX)

	mov	ah,DOS_PSP_CREATE
	int	21h			; create new PSP at DX

	mov	bx,[psp_active]
	test	bx,bx
	jz	lp2a
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

lp2a:	push	bx			; save original PSP
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
	ASSUME	DS:NOTHING
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h			; open the file
	jc	lp6a
	xchg	bx,ax			; BX = file handle
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
	jc	lp5a

	xchg	cx,ax			; file size now in DX:CX
	mov	ax,ERR_NOMEM
	test	dx,dx			; more than 64K?
	jnz	lp5a			; yes
	cmp	cx,si			; larger than the memory we allocated?
	ja	lp5a			; yes
	mov	si,cx			; no, SI is the new length

	sub	cx,cx
	sub	dx,dx
	mov	ax,(DOS_HDL_SEEK SHL 8) OR SEEK_BEG
	int	21h			; reset file position to beginning
	jc	lp5a

	mov	cx,si			; CX = # bytes to read
	mov	dx,size PSP		; DS:DX -> memory after PSP
	mov	ah,DOS_HDL_READ		; BX = file handle, CX = # bytes
	int	21h
	jnc	lp6
lp5a:	jmp	lp8

lp6:	ASSERT	Z,<cmp ax,cx>		; assert bytes read = bytes requested
	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the file
lp6a:	jc	lp7a
;
; Check the word at [BX+100h-2]: if it contains BASICDOS_SIG ("BD"), then
; the preceding word must be the program's desired additional memory (in paras).
;
	mov	bx,cx			; BX = lenth of program file
	mov	dx,MINHEAP SHR 4	; minimum add'l space (1Kb in paras)
	cmp	word ptr [bx+size PSP-2],BASICDOS_SIG
	jne	lp7
	mov	ax,word ptr [bx+size PSP-4]
	cmp	ax,dx			; larger than our minimum?
	jbe	lp7			; no
	xchg	dx,ax			; yes, use their larger value

lp7:	add	bx,15
	mov	cl,4
	shr	bx,cl			; BX = size of program (in paras)
	add	bx,dx			; add add'l space (in paras)
	add	bx,10h			; add size of PSP (in paras)
	push	ds
	pop	es
	ASSUME	ES:NOTHING
	mov	ah,DOS_MEM_REALLOC	; resize the memory block
	int	21h
lp7a:	jc	lp8a			; TODO: try to use a smaller size?
;
; Since we're past the point of no return now, let's take care of some
; initialization outside of the program segment; namely, resetting the CTRLC
; and ERROR handlers to their default values.  And as always, we set these
; defaults inside the SCB rather than the IVT.
;
	mov	bx,[scb_active]
	mov	cs:[bx].SCB_CTRLC.OFF,offset dos_ctrlc
	mov	cs:[bx].SCB_CTRLC.SEG,cs
	mov	cs:[bx].SCB_ERROR.OFF,offset dos_error
	mov	cs:[bx].SCB_ERROR.SEG,cs
;
; Initialize the DTA to its default (PSP:80h), while simultaneously
; preserving the previous DTA in the new PSP.
;
	mov	ax,80h
	xchg	cs:[bx].SCB_DTA.OFF,ax
	mov	ds:[PSP_DTAPREV].OFF,ax
	mov	ax,ds
	xchg	cs:[bx].SCB_DTA.SEG,ax
	mov	ds:[PSP_DTAPREV].SEG,ax
;
; Create an initial REG_FRAME at the top of the segment (or the top of
; allocated memory, whichever's lower).
;
; TODO: Verify that we're setting proper initial values for all the registers.
;
	mov	di,bx
	cmp	di,1000h
	jb	lp7b
	mov	di,1000h
lp7b:	shl	di,cl			; ES:DI -> top of the segment
	dec	di
	dec	di			; ES:DI -> last word at top of segment
	std
	mov	dx,ds
	sub	ax,ax
	stosw				; store a zero at the top of the stack
	mov	ax,FL_INTS
	stosw				; REG_FL (with interrupts enabled)
	mov	ax,dx
	stosw				; REG_CS
	mov	ax,100h
	stosw				; REG_IP
	sub	ax,ax
	REPT (size WS_TEMP) SHR 1
	stosw				; REG_WS
	ENDM
	stosw				; REG_AX
	stosw				; REG_BX
	stosw				; REG_CX
	stosw				; REG_DX
	xchg	ax,dx
	stosw				; REG_DS
	xchg	ax,dx
	stosw				; REG_SI
	xchg	ax,dx
	stosw				; REG_ES
	xchg	ax,dx
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
lp8:	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	ax
lp8a:	push	ax
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
