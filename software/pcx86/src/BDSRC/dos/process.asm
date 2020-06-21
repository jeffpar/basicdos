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
	EXTERNS	<get_scbnum>,near

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_quit (REG_AH = 00h)
;
; Inputs:
;	REG_CS = segment of PSP
;
; Outputs:
;	None
;
DEFPROC	psp_quit,DOS
	ret				; TODO
ENDPROC	psp_quit

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
; Copy current INT 22h (ABORT), INT 23h (CTRLC), and INT 24h (ERROR) vectors.
;
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	si,22h * 4
	mov	cx,6
	rep	movsw
	pop	ds
	ASSUME	DS:DOS

	mov	ax,[psp_active]		; 16h: PSP_PARENT
	stosw
;
; Next up: the PFT (Process File Table); the first 5 PFT slots (PFHs) are
; predefined as STDIN (0), STDOUT (1), STDERR (2), STDAUX (3), and STDPRN (4),
; and apparently we're supposed to open an SFB for AUX first, CON second,
; and PRN third, so that the SFHs for the first five handles will always be:
; 1, 1, 1, 0, and 2.
;
	mov	bx,[scb_active]
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
	mov	di,PSP_CMDLINE + 1
	mov	al,0Dh
	stosb				; done for now
	ret
ENDPROC	psp_create

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_set (REG_AH = 50h)
;
; In BASICDOS, this only changes SCB_CURPSP, NOT the global psp_active.
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
	ASSERT_STRUC [bx],SCB
	mov	[bx].SCB_CURPSP,ax
	ret
ENDPROC	psp_set

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_get (REG_AH = 51h)
;
; In BASICDOS, this only retrieves SCB_CURPSP, NOT the global psp_active.
;
; Inputs:
;	None
;
; Outputs:
;	REG_BX = segment of current PSP
;
DEFPROC	psp_get,DOS
	mov	bx,[scb_active]
	ASSERT_STRUC [bx],SCB
	mov	ax,[bx].SCB_CURPSP
	mov	[bp].REG_BX,ax
	ret
ENDPROC	psp_get

DOS	ends

	end
