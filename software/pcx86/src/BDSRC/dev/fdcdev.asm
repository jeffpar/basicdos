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
FDC 	DDH	<offset DEV:ddend+16,,DDATTR_BLOCK,offset ddinit,-1,2020202024434446h>

	DEFLBL	CMDTBL,word
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none	; 0-3
	dw	ddcmd_read, ddcmd_none, ddcmd_none, ddcmd_none	; 4-7
	dw	ddcmd_write, ddcmd_none, ddcmd_none, ddcmd_none	; 8-11
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none	; 12-15
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none	; 16-19
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddreq,far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	ds
	mov	di,bx			; ES:DI -> DDP
	mov	bl,es:[di].DDP_CMD
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	cmp	bl,CMDTBL_SIZE
	jae	ddi9
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
ddi9:	pop	ds
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	ddreq

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
	mov	bh,FDC_READ
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
;	DDPRW updated appropriately
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
DEFPROC	ddcmd_write
	mov	bh,FDC_WRITE
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
; Issue BIOS FDC command in BH
;
; Inputs:
;	BH = FDC cmd
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW updated appropriately
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
DEFPROC	readwrite_sectors
	push	bp
	push	es
	mov	ax,es:[di].DDPRW_LBA
	mov	cx,es:[di].DDPRW_LENGTH
	mov	dx,es:[di].DDPRW_OFFSET
	lds	si,es:[di].DDPRW_BPB
;
; If the offset in DX is zero and the length in CX is a multiple of
; [si].BPB_SECBYTES, then we can simply convert CX to a sector count and
; call readwrite_sectors without further ado.
;
	test	dx,dx
	jnz	ddr1		; no such luck
	mov	bp,[si].BPB_SECBYTES
	dec	bp
	test	cx,bp
	jz	ddr8

ddr1:	int 3

ddr8:	xchg	ax,cx		; AX = length (CX is saving LBA)
	inc	bp
	div	bp
	xchg	cx,ax		; AX = LBA again (CL is # sectors)
	mov	bl,cl		; BL = # sectors
	call	get_chs		; convert LBA in AX to CHS in CX,DX
	xchg	ax,bx		; AH = FDC cmd, AL = # sectors

	les	bx,es:[di].DDPRW_ADDR
	int	INT_FDC		; AX and carry are whatever the ROM returns

	pop	es
	pop	bp
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	ddr9
;
; TODO: Map the error and set the sector count to the correct values
;
	mov	es:[di].DDPRW_LENGTH,0
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_SEEK
ddr9:	ret
ENDPROC	readwrite_sectors

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_UNITS and DDPI_END updated
;
DEFPROC	ddinit,far
	push	ax
	push	cx
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,[EQUIP_FLAG]
	mov	es:[bx].DDPI_END.off,offset ddinit + 512
	mov	cs:[0].DDH_REQUEST,offset DEV:ddreq
;
; Determine how many floppy disk drives are in the system.
;
	sub	cx,cx
	test	al,EQ_IPL_DRIVE
	jz	ddin9
	and	ax,EQ_NUM_DRIVES
	mov	cl,6
	shr	ax,cl
	inc	ax
	xchg	cx,ax
ddin9:	mov	es:[bx].DDPI_UNITS,cl
	pop	ds
	ASSUME	DS:NOTHING
	pop	cx
	pop	ax
	ret
ENDPROC	ddinit

CODE	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
