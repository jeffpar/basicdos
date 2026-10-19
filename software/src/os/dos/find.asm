;
; BASIC-DOS Find Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSFFB equ 1
	include	macros.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<chk_filename,fmt_name,get_bpb,get_dirent,scb_release>
	EXTBYTE	<scb_locked>
	EXTWORD	<scb_active>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_ffirst (REG_AH = 4Eh)
;
; Inputs:
;	REG_CX = attribute bits
;	REG_DS:REG_DX -> filespec
;
; Outputs:
;	If found, carry clear, DTA filled in
;	If not found, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS
;
DEFPROC	dsk_ffirst,DOS
	LOCK_SCB
	mov	al,[bp].REG_CL
	or	al,DIRATTR_SEARCH	; AL = search attributes
	mov	ah,80h			; AH = 80h (filespec)
	mov	si,dx
	mov	ds,[bp].REG_DS		; DS:SI -> filespec
	call	chk_filename
	jc	ff8
	mov	ah,[bp].REG_CL
;
; Fill in the DTA with the relevant bits
;
	DEFLBL	dsk_ffill,near
	ASSUME	DS:NOTHING, ES:NOTHING	; DS:SI -> DIRENT
	mov	bx,[scb_active]
	les	di,cs:[bx].SCB_DTA	; ES:DI -> DTA (FFB)
	stosw				; FFB_DRIVE, FFB_SATTR
	push	cx
	push	si
	mov	cx,size FCB_NAME
	lea	si,[bx].SCB_FILENAME + 1; FFB_FILESPEC
	REPS	MOVS,ES,CS,BYTE
	mov	ax,cs:[bx].SCB_DIRCLN
	stosw				; FFB_DIRCLN
	pop	si
	pop	cx
	add	di,size FFB_RESERVED
	ASSERT	Z,<cmp di,80h + offset FFB_DIRNUM>
	xchg	ax,cx
	ASSERT	Z,<test ah,ah>		; assert DIRENT # < 256 (for now)
	stosw				; FFB_DIRNUM
	mov	al,[si].DIR_ATTR
	stosb				; FFB_ATTR
	mov	ax,[si].DIR_TIME
	stosw				; FFB_TIME
	mov	ax,[si].DIR_DATE
	stosw				; FFB_DATE
	mov	ax,[si].DIR_SIZE.OFF
	stosw				; FFB_SIZE
	mov	ax,[si].DIR_SIZE.SEG
	stosw
	call	fmt_name		; FFB_NAME
	sub	ax,ax
	stosb
	jnc	ff9
ff8:	mov	[bp].REG_AX,ax
ff9:	UNLOCK_SCB
	ret
ENDPROC	dsk_ffirst

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_fnext (REG_AH = 4Fh)
;
; Inputs:
;	DTA -> data from previous dsk_ffirst/dsk_fnext
;
; Outputs:
;	If found, carry clear, DTA filled in
;	If not found, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS
;
DEFPROC	dsk_fnext,DOS
	LOCK_SCB
	mov	bx,[scb_active]
	lds	si,cs:[bx].SCB_DTA	; DS:SI -> DTA (FFB)
	ASSUME	DS:NOTHING
	mov	dl,[si].FFB_DRIVE
	push	si
	lea	si,[si].FFB_FILESPEC
	lea	di,[bx].SCB_FILENAME + 1
	mov	cx,size FFB_FILESPEC
	rep	movsb
	ASSERT	<FFB_FILESPEC + size FFB_FILESPEC>,EQ,<FFB_DIRCLN>
	lodsw				; AX = FFB_DIRCLN
	mov	es:[bx].SCB_DIRCLN,ax
	pop	si
	call	get_bpb			; DL = drive #
	jc	fn8
	mov	bl,[si].FFB_SATTR	; BL = search attributes
	mov	dh,bl
	or	bl,DIRATTR_SEARCH
	mov	ax,[si].FFB_DIRNUM	; AX = prev DIRENT #
	inc	ax			; AX = next DIRENT #
	call	get_dirent
	jc	fn8
	ASSERT	Z,<test ah,ah>		; assert DIRENT # < 256 (for now)
	xchg	cx,ax			; CX = DIRENT #
	mov	ax,dx			; AL = drive #, AH = search attributes
	jmp	dsk_ffill
fn8:	mov	[bp].REG_AX,ax
	UNLOCK_SCB
	ret
ENDPROC	dsk_fnext


DOS	ends

	end
