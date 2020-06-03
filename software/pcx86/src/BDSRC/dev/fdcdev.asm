;
; BASIC-DOS Floppy Disk Controller Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dev.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	FDC
FDC 	DDH	<offset DEV:ddend+16,,DDATTR_BLOCK,offset ddreq,offset ddinit,2020202024434446h>

	DEFPTR	ddpkt		; last request packet address
	DEFPTR	bpb_ptr,<offset BPB_ACTIVE - offset IVT>,0
	DEFLBL	CMDTBL,word
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none	; 0-3
	dw	ddcmd_read, ddcmd_none, ddcmd_none, ddcmd_none	; 4-7
	dw	ddcmd_write, ddcmd_none, ddcmd_none, ddcmd_none	; 8-11
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none	; 12-15
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none	; 16-19
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddreq,far
	mov	[ddpkt].off,bx
	mov	[ddpkt].seg,es
	ret
ENDPROC	ddreq

DEFPROC	ddint,far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	ds
	push	es
	les	di,[ddpkt]
	mov	bl,es:[di].DDP_CMD
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	cmp	bl,CMDTBL_SIZE
	jae	ddi9
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
ddi9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	ddint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_read
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW updated appropriately
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
DEFPROC	ddcmd_read
	mov	bl,FDC_READ
	call	readwrite_sectors
	ret
ENDPROC	ddcmd_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_write
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
DEFPROC	ddcmd_write
	mov	bl,FDC_WRITE
	call	readwrite_sectors
	ret
ENDPROC	ddcmd_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_none (handler for unimplemented functions)
;
; Inputs:
;	DS:DI -> DDP
;
; Outputs:
;
DEFPROC	ddcmd_none
	ret
ENDPROC	ddcmd_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Get CHS from LBA in AX, using BPB at SI
;
; Inputs:
;	AX = LBA
;	DS:SI -> BPB
;
; Outputs:
;	CH = cylinder #
;	CL = sector ID
;	DH = head #
;	DL = drive #
;
; Modifies:
;	AX, CX, DX
;
; TODO: Keep this in sync with BOOT.ASM (better yet, factor it out somewhere)
;
DEFPROC	get_chs
	sub	dx,dx		; DX:AX is LBA
	div	[si].BPB_CYLSECS; AX = cylinder, DX = remaining sectors
	xchg	al,ah		; AH = cylinder, AL = cylinder bits 8-9
	ror	al,1		; future-proofing: saving cylinder bits 8-9
	ror	al,1
	xchg	cx,ax		; CH = cylinder #
	xchg	ax,dx		; AX = remaining sectors from last divide
	div	byte ptr [si].BPB_TRACKSECS
	mov	dh,al		; DH = head # (quotient of last divide)
	or	cl,ah		; CL = sector # (remainder of last divide)
	inc	cx		; LBA are zero-based, sector IDs are 1-based
	mov	dl,[si].BPB_DRIVE
	ret
ENDPROC	get_chs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Issue BIOS FDC command in BL
;
; Inputs:
;	BL = FDC cmd
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW updated appropriately
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
DEFPROC	readwrite_sectors
	mov	ax,es:[di].DDPRW_SECTOR
	lds	si,[bpb_ptr]	; convert LBA in AX to CHS in CX,DX
	call	get_chs
	mov	ax,es:[di].DDPRW_COUNT
	mov	ah,bl
	push	es
	les	bx,es:[di].DDPRW_ADDR
	int	INT_FDC		; AX and carry are whatever the ROM returns
	pop	es
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	rw9
	;
	; TODO: Map the error and set the sector count to the correct values
	;
	mov	es:[di].DDPRW_COUNT,0
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_SEEK
rw9:	ret
ENDPROC	readwrite_sectors

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	[ddpkt] -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
DEFPROC	ddinit,far
	push	di
	push	es
	les	di,[ddpkt]
	mov	es:[di].DDPI_END.off,offset ddinit
	mov	cs:[0].DDH_INTERRUPT,offset DEV:ddint
	pop	es
	pop	di
	ret
ENDPROC	ddinit

CODE	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
