;
; BASIC-DOS System Initialization Helpers
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; These functions are used only by SYSINIT (see sysinit.asm), and since this
; module is linked immediately after it, they are moved and recycled along
; with the rest of the system initialization code (before the SHELLs are
; loaded; see systail.asm).
;
	BIOSAPI equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<sysinit_error,find_cfg>
	EXTWORD	<dos_seg>

	DEFWORD	tbl_next		; offset of next table (see init_table)

	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_bpbtime
;
; Set the timestamp of a BPB to the current BIOS tick count (as the FDC and
; HDC drivers do whenever they access the media).
;
; Inputs:
;	DS:DI -> BPB
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	set_bpbtime
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	mov	[di].BPB_TIMESTAMP.OFF,dx
	mov	[di].BPB_TIMESTAMP.SEG,cx
	ret
ENDPROC	set_bpbtime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_table
;
; Initializes a table of AX entries of length DX at tbl_next (an offset in the
; DOS segment), stores the table's offset at [BX] and its limit at [BX+2] (in
; the DOS segment too), and advances tbl_next to the next paragraph.  This
; runs in sysinit's block (SS = its data), where tbl_next is.
;
; Outputs:
;	Nothing
;
; Modifies: CX, DX, DI
;
DEFPROC	init_table
	ASSUME	DS:NOTHING, ES:NOTHING
	push	ax
	push	es
	mov	es,[dos_seg]
	mul	dx			; AX = length of table in bytes
	xchg	cx,ax			; CX = length
	mov	di,ss:[tbl_next]	; ES:DI -> table
	mov	es:[bx].OFF,di		; save DS-relative offset
	mov	ax,di
	add	ax,cx			; does the table fit in the segment?
	jc	it8			; no
	add	ax,15
	jc	it8
	and	al,0F0h
	mov	ss:[tbl_next],ax
	mov	al,0
	rep	stosb			; zero the table
	mov	es:[bx].SEG,di		; save DS-relative limit
	pop	es
	pop	ax
	ret
it8:	jmp	sysinit_error		; no, sadly
ENDPROC	init_table

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; open_dev
;
; Opens the device in a CONFIG.SYS setting (eg, "PRN=LPT2"), or if there's
; no such setting, the default device.  If the device can't be opened, the
; session has no such device (SFH_NODEV), which is reported for a setting
; but not for a default (eg, LPT1 on a machine without a parallel port).
;
; Inputs:
;	SI -> setting (eg, CFG_PRN)
;	DX -> default device (eg, "LPT1")
;
; Outputs:
;	AL = SFH, or SFH_NODEV
;
; Modifies:
;	AX, DX, SI, DI
;
DEFPROC	open_dev
	call	find_cfg		; look for the setting
	jc	od1			; not found
	mov	dx,di			; DX -> setting
od1:	sbb	si,si			; SI = -1 if not found, 0 if found
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jnc	od9
	inc	si			; was the device from a setting?
	jz	od8			; no
	call	open_warning
od8:	mov	al,SFH_NODEV
od9:	ret
ENDPROC	open_dev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; open_warning
;
; Inputs:
;	AX = error code
;	DX -> device setting (eg, "COM2:9600,N,8,1")
;
; Modifies:
;	AX
;
DEFPROC	open_warning
	EPRINTF	<"Warning: unable to open %s">,<13,10>,ax,dx
	ret
ENDPROC	open_warning

DOS	ends

	end
