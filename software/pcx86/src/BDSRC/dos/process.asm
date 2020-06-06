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

	EXTERNS	<mcb_limit,psp_active>,word
	EXTERNS	<sfh_con,sfh_aux,sfh_prn>,byte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; psp_create (REG_AH = 26h)
;
; Inputs:
;	REG_DX = segment of new PSP
;
; Outputs:
;	None
;
DEFPROC	psp_create,DOS
	mov	dx,[bp].REG_DX
	mov	es,dx			; ES:0 -> segment
	ASSUME	ES:NOTHING
	sub	di,di
	mov	ax,20CDh
	stosw				; 00h: PSP_EXIT
	mov	ax,[mcb_limit]
	stosw				; 02h: PSP_PARAS
	xchg	bx,ax
	mov	ax,9A00h
	stosw				; 05h: PSP_FARCALL (9Ah)
	sub	bx,dx			; BX = top para - this para
	sub	ax,ax			; default to 64K
	mov	cl,4
	cmp	bx,1000h		; 64K or more available?
	jae	pc1			; yes
	shl	bx,cl			; BX = number of bytes available
	xchg	ax,bx
pc1:	sub	ax,256			; AX = max available bytes this segment
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
; Copy the current INT 22h, INT 23h, and INT 24h vectors next.
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
; Next up: the PFT (Process File Table); the first 5 PFT slots ("handles") are
; predefined as STDIN (0), STDOUT (1), STDERR (2), STDAUX (3), and STDPRN (4),
; and apparently we're supposed to open an SFB for AUX first, CON second,
; and PRN third, so that the SFB numbers for the first five handles will always
; be: 1, 1, 1, 0, and 2.
;
	mov	al,[sfh_con]
	stosb
	stosb
	stosb
	mov	al,[sfh_aux]
	stosb
	mov	al,[sfh_prn]
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
; Inputs:
;	REG_BX = segment of new PSP
;
; Outputs:
;	None
;
DEFPROC	psp_set,DOS
	mov	ax,[bp].REG_BX
	mov	[PSP_ACTIVE],ax
	ret
ENDPROC	psp_set

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	ax,[PSP_ACTIVE]
	mov	[bp].REG_BX,ax
	ret
ENDPROC	psp_get

DOS	ends

	end
