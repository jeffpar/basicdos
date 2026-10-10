;
; BASIC-DOS Hard Drive Controller Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This driver supports IBM PC XT (model 5160) hard disks, by way of the ROM
; BIOS (INT 13h with drive numbers 80h and up).  At initialization, it reads
; the Master Boot Record (MBR) of every hard disk, and every FAT12 partition
; becomes a "volume" (ie, a unit of this driver), which the kernel presents as
; drives C:, D:, etc (see sysinit).
;
; Compared to the FDC driver, this driver is simpler in some respects (eg, no
; media changes), and more complicated in others (eg, every LBA is relative
; to the start of its volume).  Since INT 13h works the same way for hard
; disks as it does for diskettes (including DMA transfers that can't cross 64K
; boundaries), all our reads and writes are done by the FDC driver (see FDCX
; in dev.inc), using the geometry and volume start in our BPBs, so the FDC
; driver must be loaded too.
;
	BIOSEQU equ 1
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	HDC
HDC 	DDH	<offset DEV:ddhdc_end+16,,DDATTR_BLOCK,offset ddhdc_init,-1,2020202024434448h>

	DEFLBL	CMDTBL,word
	dw	ddhdc_none,  ddhdc_mediachk, ddhdc_buildbpb, ddhdc_none	; 0-3
	dw	ddhdc_rw,    ddhdc_none,     ddhdc_none,     ddhdc_none	; 4-7
	dw	ddhdc_rw,    ddhdc_none,     ddhdc_none,     ddhdc_none	; 8-11
	dw	ddhdc_none,  ddhdc_none,     ddhdc_none,     ddhdc_none	; 12-15
	dw	ddhdc_none,  ddhdc_none,     ddhdc_none,     ddhdc_none	; 16-19
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>
;
; The volume table describes each volume (ie, unit) of this driver.
;
VOL		struc
VOL_DRIVE	db	?		; 00h: BIOS drive # (eg, 80h)
VOL_HEADS	db	?		; 01h: # heads
VOL_TRACKSECS	db	?		; 02h: sectors per track
VOL_PAD		db	?		; 03h
VOL_CYLSECS	dw	?		; 04h: sectors per cylinder
VOL_START	dd	?		; 06h: LBA of 1st sector of volume
VOL		ends

MAX_DRIVES	equ	2		; max hard disks (80h and 81h)
MAX_VOLS	equ	8		; max volumes (4 partitions per disk)
PART_TABLE	equ	1BEh		; offset of partition table in MBR
PART_TYPE	equ	4		; offset of partition type in entry
PART_LBA	equ	8		; offset of partition LBA in entry
PART_FAT12	equ	01h		; FAT12 partition type
MAX_CLUS12	equ	4085		; max clusters in a FAT12 volume

	DEFBYTE	hdc_base,2		; drive # of the first volume
	DEFBYTE	hdc_vols,0		; # volumes
	DEFLBL	vol_table,byte
	db	(size VOL) * MAX_VOLS dup (0)

	DEFPTR	fdc_rw,0		; FDC driver's FDCX_RW entry
	DEFPTR	fdc_rdbuf,0		; FDC driver's FDCX_RDBUF entry

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddhdc_req,far
	mov	di,bx		; ES:DI -> DDP
	mov	bl,es:[di].DDP_CMD
	cmp	bl,CMDTBL_SIZE
	jb	ddq1
	mov	bl,0
ddq1:	push	cs
	pop	ds
	ASSUME	DS:CODE
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
	ret
ENDPROC	ddhdc_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddhdc_mediachk
;
; Hard disk media never changes, so the media is "unchanged", unless the BPB
; hasn't been built yet.
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	DDP_CONTEXT contains the MC (media check) status code
;
; Modifies:
;	AX, SI, DS
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddhdc_mediachk
	lds	si,es:[di].DDPRW_BPB
	ASSUME	DS:NOTHING	; DS:SI -> BPB
	mov	ax,MC_UNCHANGED
	cmp	[si].BPB_SECBYTES,0	; has the BPB been built yet?
	jne	mc9			; yes
	mov	ax,MC_CHANGED
mc9:	mov	es:[di].DDP_CONTEXT,ax
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddhdc_mediachk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddhdc_buildbpb
;
; We read the boot sector of the volume, copy its BPB (up to BPB_HIDDENSECS),
; and then fill in the rest of the BPB (and our BPB extensions), using the
; drive geometry and volume location that we found during initialization.
;
; Since the kernel currently supports only FAT12 volumes with 16-bit sector
; numbers, any other volume is reported as unknown media.
;
; Inputs:
;	ES:DI -> DDP (in particular, DDPRW_BPB -> BPB)
;
; Outputs:
;	BPB is updated
;
; Modifies:
;	AX, BX, CX, DX, BP, SI, DS
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddhdc_buildbpb
	push	di
	push	es
	mov	al,es:[di].DDP_UNIT	; AL = drive #
	les	di,es:[di].DDPRW_BPB	; ES:DI -> BPB
	ASSUME	ES:NOTHING
	mov	es:[di].BPB_DRIVE,al
	mov	es:[di].BPB_SECBYTES,0	; the BPB isn't valid (yet)
	call	get_vol			; CS:BX -> VOL
	mov	ax,DDERR_UNKUNIT
	jnc	bb1
bb0:	jmp	bb7a
bb1:	call	set_geo			; set the BPB's geometry and location
;
; Read the volume's boot sector (ie, relative LBA 0) into the FDC's buffer.
;
	push	bx
	push	es
	pop	ds
	ASSUME	DS:NOTHING
	mov	si,di			; DS:SI -> BPB
	sub	dx,dx			; DX = LBA (0)
	mov	al,cs:[bx].VOL_DRIVE	; AL = BIOS drive #
	push	es
	call	cs:[fdc_rdbuf]		; ES:BP -> FDC's buffer
	push	es
	pop	ds
	pop	es			; ES:DI -> BPB again
	pop	bx			; CS:BX -> VOL again
	jc	bb0
;
; Copy the standard BPB fields from the boot sector to the BPB provided, and
; then restore the geometry and location from the volume table.
;
	push	di
	lea	si,[bp+BOOT_BPB]	; DS:SI -> boot sector's BPB
	mov	cx,BPB_HIDDENSECS
	rep	movsb
	pop	di
	call	set_geo
	sub	ax,ax
	mov	es:[di].BPB_LARGESECS.LOW,ax
	mov	es:[di].BPB_LARGESECS.HIW,ax
	mov	es:[di].BPB_DEVICE.OFF,ax
	mov	es:[di].BPB_DEVICE.SEG,cs
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	mov	es:[di].BPB_TIMESTAMP.OFF,dx
	mov	es:[di].BPB_TIMESTAMP.SEG,cx
;
; Make sure we can support the volume (512-byte sectors, 16-bit sector
; numbers, and a power-of-two number of sectors per cluster).
;
	cmp	es:[di].BPB_SECBYTES,512
	jne	bb7
	mov	dx,es:[di].BPB_DISKSECS
	test	dx,dx			; more than 65535 sectors?
	jz	bb7			; yes
	sub	cx,cx
	mov	al,es:[di].BPB_CLUSSECS
	test	al,al			; calculate LOG2 of CLUSSECS
	jz	bb7
bb6:	shr	al,1
	jc	bb6a
	inc	cx
	jmp	bb6
bb6a:	jnz	bb7			; CLUSSECS isn't a power-of-two
	mov	es:[di].BPB_CLUSLOG2,cl
	mov	ax,512
	shl	ax,cl			; use CLUSLOG2 to calculate CLUSBYTES
	mov	es:[di].BPB_CLUSBYTES,ax
;
; Calculate the LBAs of the root directory and the first data sector.
;
	mov	ax,es:[di].BPB_FATSECS
	mov	dl,es:[di].BPB_FATS
	mov	dh,0
	mul	dx
	add	ax,es:[di].BPB_RESSECS
	mov	es:[di].BPB_LBAROOT,ax
	xchg	bx,ax			; BX = LBAROOT
	mov	ax,es:[di].BPB_DIRENTS
	add	ax,(512 / size DIRENT) - 1
	mov	dx,512 / size DIRENT
	div	dl			; AL = # root directory sectors
	mov	ah,0
	add	ax,bx
	mov	es:[di].BPB_LBADATA,ax
;
; Finally, calculate total clusters (total data sectors divided by sectors
; per cluster, or just another shift using CLUSLOG2), which must be within
; the FAT12 limit.
;
	mov	dx,es:[di].BPB_DISKSECS
	sub	dx,ax			; DX = total data sectors
	shr	dx,cl			; DX = data clusters
	mov	es:[di].BPB_CLUSTERS,dx
	cmp	dx,MAX_CLUS12		; FAT12?
	jae	bb7			; no
	mov	ax,512
	mov	es:[di].BPB_SECBYTES,ax	; the BPB is valid now
	clc
	jmp	short bb8
bb7:	mov	es:[di].BPB_SECBYTES,0	; the BPB isn't valid
	mov	ax,DDERR_UNKMEDIA
bb7a:	stc

bb8:	pop	es
	pop	di
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	bb9
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
bb9:	ret
ENDPROC	ddhdc_buildbpb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_geo
;
; Inputs:
;	CS:BX -> VOL
;	ES:DI -> BPB
;
; Outputs:
;	The BPB's geometry and location (BPB_HIDDENSECS) are set from the VOL
;
; Modifies:
;	AX
;
DEFPROC	set_geo
	mov	ah,0
	mov	al,cs:[bx].VOL_TRACKSECS
	mov	es:[di].BPB_TRACKSECS,ax
	mov	al,cs:[bx].VOL_HEADS
	mov	es:[di].BPB_DRIVEHEADS,ax
	mov	ax,cs:[bx].VOL_CYLSECS
	mov	es:[di].BPB_CYLSECS,ax
	mov	ax,cs:[bx].VOL_START.LOW
	mov	es:[di].BPB_HIDDENSECS.LOW,ax
	mov	ax,cs:[bx].VOL_START.HIW
	mov	es:[di].BPB_HIDDENSECS.HIW,ax
	ret
ENDPROC	set_geo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddhdc_rw
;
; Reads and writes are done by the FDC driver (see fdc_rw in fdcdev.asm),
; using our BPB and the volume's BIOS drive #.
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW updated appropriately
;
; Modifies:
;	AX, BX, CX, DX, BP, SI, DS
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddhdc_rw
	mov	al,es:[di].DDP_UNIT
	call	get_vol			; CS:BX -> VOL
	jc	hrw8
	mov	al,cs:[bx].VOL_DRIVE	; AL = BIOS drive #
	call	[fdc_rw]
	ret
hrw8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKUNIT
	ret
ENDPROC	ddhdc_rw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddhdc_none (handler for unimplemented functions)
;
; Inputs:
;	DS:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddhdc_none
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	ret
ENDPROC	ddhdc_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_vol
;
; Inputs:
;	AL = drive #
;
; Outputs:
;	If carry clear, CS:BX -> VOL
;
; Modifies:
;	AX, BX
;
	ASSUME	DS:NOTHING
DEFPROC	get_vol
	sub	al,cs:[hdc_base]	; AL = unit #
	jb	gv9
	cmp	al,cs:[hdc_vols]
	cmc
	jc	gv9			; unit # too large
	mov	ah,size VOL
	mul	ah
	xchg	bx,ax
	add	bx,offset vol_table	; (carry clear)
gv9:	ret
ENDPROC	get_vol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; For every hard disk, get the drive geometry, read the MBR (into the scratch
; buffer that devinit provides at DDPI_BUFPTR), and add a volume for every
; FAT12 partition.  If there are no volumes, the driver isn't needed.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_UNITS and DDPI_END updated
;
DEFPROC	ddhdc_init,far
	push	es
	push	bx
	mov	cs:[0].DDH_REQUEST,offset DEV:ddhdc_req
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
;
; Get the FDC driver's entry points for reading and writing (see FDCX); if
; there's no FDC driver, then we can't support any volumes.
;
	push	ds
	lds	si,[FDC_DEVICE]		; DS:SI -> FDC driver header
	ASSUME	DS:NOTHING
	mov	ax,ds
	test	ax,ax
	jz	hi0
	mov	ax,[si + size DDH].FDCX_RW
	mov	cs:[fdc_rw].OFF,ax
	mov	ax,[si + size DDH].FDCX_RDBUF
	mov	cs:[fdc_rdbuf].OFF,ax
	mov	cs:[fdc_rw].SEG,ds
	mov	cs:[fdc_rdbuf].SEG,ds
hi0:	pop	ds
	ASSUME	DS:BIOS
	jz	hi8
;
; Like PC DOS, drives A: and B: are reserved for diskettes, so the first
; volume is C: (or later, if there are more than 2 diskette drives).
;
	mov	al,[FDC_UNITS]
	cmp	al,2
	jae	hi1
	mov	al,2
hi1:	mov	cs:[hdc_base],al
	les	bp,es:[bx].DDPI_BUFPTR	; ES:BP -> scratch buffer
	mov	ah,HDC_GETPARMS
	mov	dl,80h
	int	INT_FDC			; DL = # hard disks
	jc	hi8
	mov	cl,dl
	mov	ch,0
	cmp	cl,MAX_DRIVES
	jbe	hi2
	mov	cl,MAX_DRIVES
hi2:	jcxz	hi8
	mov	dl,80h			; DL = BIOS drive #
	mov	di,offset vol_table	; CS:DI -> next VOL
hi3:	push	cx
	push	dx
	call	add_vols		; add volumes for drive DL
	pop	dx
	pop	cx
	inc	dx
	loop	hi3

hi8:	pop	bx
	pop	es
	mov	al,cs:[hdc_vols]
	mov	es:[bx].DDPI_UNITS,al
;
; We're not keeping any of this code (and the FDC driver's buffer serves as
; ours), and if there are no volumes, we're not keeping anything.
;
	sub	cx,cx
	test	al,al
	jz	hi9
	mov	cx,offset ddhdc_init
hi9:	mov	es:[bx].DDPI_END.OFF,cx
	ret
ENDPROC	ddhdc_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_vols
;
; Inputs:
;	DL = BIOS drive #
;	ES:BP -> scratch buffer
;	CS:DI -> next VOL
;
; Outputs:
;	CS:DI -> next VOL (and hdc_vols updated)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	add_vols
	mov	ah,HDC_GETPARMS
	push	dx
	int	INT_FDC			; DH = max head, CL = max sector
	pop	ax			; AL = BIOS drive #
	jc	av9
	inc	dh			; DH = # heads
	and	cl,3Fh			; CL = sectors per track
	jz	av9
	mov	dl,al			; DL = BIOS drive # again
	push	dx
	push	cx
	mov	ax,(FDC_READ SHL 8) OR 1
	mov	cx,1			; CH = cylinder 0, CL = sector 1
	mov	dh,0			; DH = head 0
	mov	bx,bp			; ES:BX -> scratch buffer
	int	INT_FDC			; read the MBR
	pop	cx
	pop	dx
	jc	av9
	cmp	word ptr es:[bp+510],0AA55h
	jne	av9			; not a valid MBR
	lea	si,[bp+PART_TABLE]	; ES:SI -> first partition entry
	mov	ah,4			; AH = # partition entries
av1:	cmp	byte ptr es:[si+PART_TYPE],PART_FAT12
	jne	av8
	cmp	cs:[hdc_vols],MAX_VOLS
	jae	av9
	mov	cs:[di].VOL_DRIVE,dl
	mov	cs:[di].VOL_HEADS,dh
	mov	cs:[di].VOL_TRACKSECS,cl
	push	ax
	mov	al,cl
	mul	dh
	mov	cs:[di].VOL_CYLSECS,ax
	mov	ax,es:[si+PART_LBA]
	mov	cs:[di].VOL_START.LOW,ax
	mov	ax,es:[si+PART_LBA+2]
	mov	cs:[di].VOL_START.HIW,ax
	pop	ax
	add	di,size VOL
	inc	cs:[hdc_vols]
av8:	add	si,16
	dec	ah
	jnz	av1
av9:	ret
ENDPROC	add_vols

CODE	ends

DATA	segment para public 'DATA'

ddhdc_end	db	16 dup(0)

DATA	ends

	end
