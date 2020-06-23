;
; BASIC-DOS Miscellaneous Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<ctrlc_all,ctrlc_active>,byte
	EXTERNS	<scb_active>,word
	EXTERNS	<write_string>,near

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_setvec (REG_AH = 25h)
;
; Inputs:
;	REG_AL = vector #
;	REG_DS:REG_DX = address for vector
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI, ES
;
; Notes:
; 	Too bad this function wasn't defined to also return the original vector.
;
DEFPROC	msc_setvec,DOS
	call	get_vecoff		; AX = vector offset
	jnc	msv1
	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
msv1:	xchg	di,ax			; ES:DI -> vector to write
	cli
	mov	ax,[bp].REG_DX
	stosw
	mov	ax,[bp].REG_DS
	stosw
	sti
	clc
	ret
ENDPROC	msc_setvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_setctrlc (REG_AH = 33h)
;
; Inputs:
;	REG_AL = 0 to get current CTRLC state in REG_DL
;	REG_AL = 1 to set current CTRLC state in REG_DL
;
; Outputs:
;	REG_DL = current state if REG_AL = 1, or 0FFh if REG_AL neither 0 nor 1
;
DEFPROC	msc_setctrlc,DOS
	sub	al,1
	jae	msc1
	mov	al,[ctrlc_all]		; AL was 0
	mov	[bp].REG_DL,al		; so return ctrlc_all in REG_DL
	clc
	jmp	short msc9
msc1:	jnz	msc2			; jump if AL was neither 0 nor 1
	mov	al,[bp].REG_DL		; AL was 1
	sub	al,1			; so convert REG_DL to 0 or 1
	sbb	al,al
	inc	ax
	mov	[ctrlc_all],al
	clc
	jmp	short msc9
msc2:	mov	al,0FFh
	stc
msc9:	ret
ENDPROC	msc_setctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_sigctrlc
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	msc_sigctrlc,DOS
	mov	[ctrlc_active],0
	push	cx
	push	si
	mov	cx,4
	mov	si,offset STR_CTRLC
	call	write_string
	pop	si
	pop	cx
	push	bx
	push	bp
	clc
	pushf				; fake "INT_DOSCTRLC"
	push	cs			; using the SCB CTRLC address
	mov	bx,offset msg1		; instead of the IVT CTRLC address
	push	bx
	mov	bx,[scb_active]
	ASSERT_STRUC [bx],SCB
	push	[bx].SCB_CTRLC.seg
	push	[bx].SCB_CTRLC.off
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	mov	bx,[bp].REG_BX
	mov	bp,[bp].REG_BP		; all registers restored for the "call"
	ASSUME	DS:NOTHING, ES:NOTHING
	db	0CBh			; RETF
msg1:	jnc	msg2
	mov	bx,[scb_active]
	pushf
	call	cs:[bx].SCB_ABORT	; should not return
msg2:	mov	bx,cs
	mov	ds,bx
	mov	es,bx
	ASSUME	DS:DOS, ES:DOS		; restore entry conditions
	pop	bp
	pop	bx
	ret
ENDPROC	msc_sigctrlc

STR_CTRLC db	"^C",CHR_RETURN,CHR_LINEFEED

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_getvec (REG_AH = 35h)
;
; Inputs:
;	REG_AL = vector #
;
; Outputs:
;	REG_ES:REG_BX = address from vector
;
; Modifies:
;	AX, SI, DS
;
DEFPROC	msc_getvec,DOS
	call	get_vecoff		; AX = vector offset
	jnc	mgv1
	sub	si,si
	mov	ds,si
	ASSUME	DS:BIOS
mgv1:	xchg	si,ax			; DS:SI -> vector to read
	cli
	lodsw
	mov	[bp].REG_BX,ax
	lodsw
	mov	[bp].REG_ES,ax
	sti
	clc
	ret
ENDPROC	msc_getvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_vecoff
;
; Inputs:
;	AL = vector #
;
; Outputs:
;	AX = vector offset (carry set if IVT, clear if SCB)
;
; Modifies:
;	AX
;
DEFPROC	get_vecoff,DOS
	mov	ah,0			; AX = vector #
	add	ax,ax
	add	ax,ax			; AX = vector # * 4
	cmp	ax,INT_DOSABORT * 4
	jb	gv9			; use IVT (carry set)
	cmp	ax,INT_DOSERROR * 4 + 4
	cmc
	jb	gv9			; use IVT (carry set)
	sub	ax,(INT_DOSABORT * 4) - offset SCB_ABORT
	add	ax,[scb_active]		; AX = vector offset in current SCB
	ASSERTNC
gv9:	ret
ENDPROC	get_vecoff

DOS	ends

	end
