;
; BASIC-DOS Hard Drive Controller Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This driver supports IBM PC XT (model 5160) and PC AT (model 5170) hard
; disks, by way of the ROM BIOS (INT 13h with drive numbers 80h and up).  At
; initialization, it reads the Master Boot Record (MBR) of every hard disk, and
; every FAT12/FAT16 partition becomes a "volume" (ie, a unit of this driver),
; which the kernel presents as drives C:, D:, etc (see sysinit).
;
; Compared to the FDC driver, this driver is simpler in some respects (eg, no
; media changes), and more complicated in others (eg, every LBA is relative
; to the start of its volume).  Since INT 13h works the same way for hard
; disks as it does for diskettes (including, on an XT, DMA transfers that
; can't cross 64K boundaries), all our reads and writes are done by the FDC
; driver (see FDCX in dev.inc), using the geometry and volume start in our
; BPBs, so the FDC driver must be loaded too.
;
; A hard disk with no FAT partitions (eg, a new disk, with no MBR) is still
; given a unit: the whole disk, whose media is unknown until it's partitioned
; and formatted.  That's what FORMAT uses: IOCTL_GETPART returns a disk's
; geometry and partition table, IOCTL_SETPART writes a new MBR (with our MBR
; code and a partition table) to such a disk and makes the unit its first FAT
; partition, and IOCTL_SETPARMS gives a volume a BPB, so that it can be
; written (see ddhdc_ioctl).
;
	BIOSAPI equ 1
	DISKIOCTL equ 1
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	HDC
HDC 	DDH	<offset DEV:ddhdc_end+16,,DDATTR_BLOCK+DDATTR_IOCTL,offset ddhdc_init,-1,2020202024434448h>

	DEFLBL	CMDTBL,word
	dw	ddhdc_none,  ddhdc_mediachk, ddhdc_buildbpb, ddhdc_ioctl
	dw	ddhdc_rw,    ddhdc_none,     ddhdc_none,     ddhdc_none
	dw	ddhdc_rw,    ddhdc_none,     ddhdc_none,     ddhdc_none
	dw	ddhdc_none,  ddhdc_none,     ddhdc_none,     ddhdc_none
	dw	ddhdc_none,  ddhdc_none,     ddhdc_none,     ddhdc_none
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
VOL_CYLS	dw	?		; 0Ah: cylinders (see IOCTL_GETPART)
VOL		ends

MAX_DRIVES	equ	2		; max hard disks (80h and 81h)
MAX_VOLS	equ	8		; max volumes (4 partitions per disk)
PART_TABLE	equ	1BEh		; offset of partition table in MBR
PART_TYPE	equ	4		; offset of partition type in entry
PART_LBA	equ	8		; offset of partition LBA in entry
PART_FAT12	equ	01h		; FAT12 partition type
PART_FAT16	equ	04h		; FAT16 with fewer than 65536 sectors

	DEFBYTE	hdc_base,2		; drive # of the first volume
	DEFBYTE	hdc_vols,0		; # volumes
	DEFLBL	vol_table,byte
	db	(size VOL) * MAX_VOLS dup (0)

	DEFPTR	fdc_rw,0		; FDC driver's FDCX_RW entry
	DEFPTR	fdc_rdbuf,0		; FDC driver's FDCX_RDBUF entry
	DEFPTR	fdc_mbr,0		; FDC driver's FDCX_MBR entry

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
; We read the boot sector of the volume, and then init_bpb copies its BPB (up
; to BPB_HIDDENSECS) and fills in the rest of the BPB (and our BPB extensions),
; using the drive geometry and volume location that we found during
; initialization.
;
; Since the kernel currently supports only FAT12/FAT16 volumes with 16-bit sector
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
bb0:	stc
	jmp	bb8
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
	lea	si,[bp+BOOT_BPB]	; DS:SI -> boot sector's BPB
	call	init_bpb

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
; init_bpb
;
; Copies the standard BPB fields (from a boot sector, or from IOCTL_SETPARMS)
; to the BPB provided, restores the geometry and location from the volume
; table, and then fills in the rest of the BPB, after making sure we can
; support the volume (512-byte sectors, 16-bit sector numbers, and a
; power-of-two number of sectors per cluster).
;
; Inputs:
;	CS:BX -> VOL
;	DS:SI -> BPB data (at least BPB_HIDDENSECS bytes)
;	ES:DI -> BPB to initialize
;
; Outputs:
;	Carry clear if successful; otherwise, carry set, AX = DDERR_UNKMEDIA,
;	and BPB_SECBYTES is zero
;
; Modifies:
;	AX, BX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	init_bpb
	push	di
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
; per cluster, or just another shift using CLUSLOG2).  The kernel selects
; FAT12 or FAT16 from this count; FAT32 volumes are unsupported.
;
	mov	dx,es:[di].BPB_DISKSECS
	sub	dx,ax			; DX = total data sectors
	shr	dx,cl			; DX = data clusters
	mov	es:[di].BPB_CLUSTERS,dx
	cmp	dx,CLN_FAT16		; fewer than 65525 clusters means FAT12/FAT16
	jae	bb7			; FAT32 is not supported
	mov	ax,512
	mov	es:[di].BPB_SECBYTES,ax	; the BPB is valid now
	clc
	ret
bb7:	mov	es:[di].BPB_SECBYTES,0	; the BPB isn't valid
	mov	ax,DDERR_UNKMEDIA
	stc
	ret
ENDPROC	init_bpb

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
; ddhdc_ioctl
;
; IOCTL_SETPARMS copies a BPB from DDPRW_ADDR to the volume's BPB (see
; init_bpb), IOCTL_GETPART stores a PARTINFO (the disk's geometry, the drive
; letter of each partition, and the partition table) at DDPRW_ADDR (see
; get_part), and IOCTL_SETPART writes a new MBR with the partition table at
; DDPRW_ADDR (see set_part).  Errors are returned to the caller.
;
; Inputs:
;	ES:DI -> DDPRW (DDP_CODE = IOCTL code)
;
; Outputs:
;	DDP_STATUS and DDP_CONTEXT (the # of bytes stored, if any) updated
;
; Modifies:
;	AX, BX, CX, DX, SI, BP, DS
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddhdc_ioctl
	mov	al,es:[di].DDP_CODE
	cmp	al,IOCTL_SETPARMS
	je	dio1
	cmp	al,IOCTL_GETPART
	je	dio2
	cmp	al,IOCTL_SETPART
	je	dio3
	jmp	ddhdc_none
dio1:	push	di
	push	es
	call	set_parms
	jmp	short dio7
dio2:	push	di
	push	es
	call	get_part
	jmp	short dio7
dio3:	push	di
	push	es
	call	set_part
dio7:	pop	es
	pop	di
	mov	es:[di].DDP_CONTEXT,dx
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	dio9
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
dio9:	ret
ENDPROC	ddhdc_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_parms (IOCTL_SETPARMS)
;
; Inputs:
;	ES:DI -> DDPRW (DDPRW_ADDR -> BPB data, DDPRW_LENGTH = its length)
;
; Outputs:
;	Carry clear if successful; otherwise, carry set, AX = error code
;	DX = 0
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_parms
	mov	al,es:[di].DDP_UNIT
	call	get_vol			; CS:BX -> VOL
	mov	ax,DDERR_BADREQ
	jc	sp9
	cmp	es:[di].DDPRW_LENGTH,BPB_HIDDENSECS ; enough for a BPB?
	jb	sp8				    ; no
	lds	si,es:[di].DDPRW_ADDR	; DS:SI -> caller's BPB
	les	di,es:[di].DDPRW_BPB	; ES:DI -> volume's BPB
	call	init_bpb
sp9:	mov	dx,0			; (flags are unaffected)
	ret
sp8:	stc
	jmp	short sp9
ENDPROC	set_parms

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_part (IOCTL_GETPART)
;
; Reads the MBR of the unit's disk and stores a PARTINFO at DDPRW_ADDR.
;
; Inputs:
;	ES:DI -> DDPRW (DDPRW_ADDR -> buffer, DDPRW_LENGTH = its length)
;
; Outputs:
;	Carry clear if successful (DX = size PARTINFO); otherwise, carry set,
;	AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, DS, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_part
	mov	al,es:[di].DDP_UNIT
	call	get_vol			; CS:BX -> VOL
	mov	ax,DDERR_BADREQ
	jc	gp9
	cmp	es:[di].DDPRW_LENGTH,size PARTINFO ; enough room?
	jb	gp8				   ; no
	push	bx
	push	di
	push	es
	mov	al,cs:[bx].VOL_DRIVE
	mov	ah,FDC_READ
	call	cs:[fdc_mbr]		; ES:BP -> MBR
	push	es
	pop	ds
	mov	si,bp			; DS:SI -> MBR
	pop	es
	pop	di			; ES:DI -> DDPRW again
	pop	bx			; CS:BX -> VOL again
	jc	gp9
	les	di,es:[di].DDPRW_ADDR	; ES:DI -> PARTINFO
	mov	ax,cs:[bx].VOL_CYLS
	stosw				; PI_CYLS
	mov	ax,word ptr cs:[bx].VOL_HEADS
	stosw				; PI_HEADS, PI_TRACKSECS
	mov	al,cs:[bx].VOL_DRIVE
	mov	ah,0
	cmp	word ptr [si+510],0AA55h; valid MBR?
	jne	gp1			; no
	inc	ah			; yes
gp1:	stosw				; PI_DRIVE, PI_VALID
	push	si
	add	si,PART_TABLE		; DS:SI -> partition table
	mov	cx,4
gp2:	mov	al,0			; AL = no drive letter
	cmp	byte ptr [si+PART_TYPE],PART_FAT12
	je	gp3
	cmp	byte ptr [si+PART_TYPE],PART_FAT16
	jne	gp4
gp3:	call	find_vol		; AL = drive letter, if any
gp4:	stosb				; PI_LETTERS
	add	si,16
	loop	gp2
	pop	si
	add	si,PART_TABLE
	mov	cx,32
	rep	movsw			; PI_TABLE
	mov	dx,size PARTINFO	; DX = # bytes stored (carry clear)
	ret
gp8:	stc
gp9:	ret
ENDPROC	get_part

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_vol
;
; Inputs:
;	CS:BX -> a VOL on the disk
;	DS:SI -> a partition entry on the same disk
;
; Outputs:
;	AL = drive letter of the volume that begins at the partition (0 if none)
;
; Modifies:
;	AX
;
DEFPROC	find_vol
	push	bx
	push	cx
	push	dx
	mov	dl,cs:[bx].VOL_DRIVE	; DL = BIOS drive #
	mov	cl,cs:[hdc_vols]
	mov	ch,0			; CX = # volumes
	mov	bx,offset vol_table
	mov	al,cs:[hdc_base]
	add	al,'A'			; AL = drive letter of the first volume
	jcxz	fv8
fv1:	cmp	cs:[bx].VOL_DRIVE,dl	; same disk?
	jne	fv2			; no
	push	ax
	mov	ax,[si+PART_LBA]
	cmp	cs:[bx].VOL_START.LOW,ax
	jne	fv1a
	mov	ax,[si+PART_LBA+2]
	cmp	cs:[bx].VOL_START.HIW,ax
fv1a:	pop	ax			; (flags are unaffected)
	je	fv9			; same start, so it's the volume
fv2:	inc	ax			; next drive letter
	add	bx,size VOL
	loop	fv1
fv8:	mov	al,0
fv9:	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	find_vol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_part (IOCTL_SETPART)
;
; Writes a new MBR, consisting of our MBR code (see mbr_code), the caller's
; partition table, and the signature, to a disk that has no partitions (ie,
; the unit is the whole disk; see add_vols), and then makes the unit the first
; FAT partition in the table, which IOCTL_SETPARMS can then initialize.
;
; Inputs:
;	ES:DI -> DDPRW (DDPRW_ADDR -> 64-byte partition table)
;
; Outputs:
;	Carry clear if successful; otherwise, carry set, AX = error code
;	DX = 0
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, DS, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_part
	mov	al,es:[di].DDP_UNIT
	call	get_vol			; CS:BX -> VOL
	mov	ax,DDERR_BADREQ
	jnc	stp0
stp0a:	jmp	stp8
stp0:	cmp	es:[di].DDPRW_LENGTH,64	; a whole partition table?
	jb	stp0a			; no
	mov	cx,cs:[bx].VOL_START.LOW
	or	cx,cs:[bx].VOL_START.HIW; is the unit the whole disk?
	jnz	stp0a			; no
	push	bx
	push	di
	push	es
	mov	ah,0
	call	cs:[fdc_mbr]		; ES:BP -> FDC buffer
	mov	di,bp
	push	cs
	pop	ds
	mov	si,offset mbr_code	; DS:SI -> our MBR code
	mov	cx,MBR_SIZE
	rep	movsb
	sub	ax,ax
	mov	cx,PART_TABLE - MBR_SIZE
	rep	stosb			; zero the rest of the code area
	pop	ds
	pop	si			; DS:SI -> DDPRW
	push	si
	push	ds
	lds	si,[si].DDPRW_ADDR	; DS:SI -> partition table
	mov	cx,32
	rep	movsw			; copy the partition table
	mov	ax,0AA55h
	stosw				; and add the signature
	pop	es
	pop	di			; ES:DI -> DDPRW again
	pop	bx			; CS:BX -> VOL again
	mov	al,cs:[bx].VOL_DRIVE
	mov	ah,FDC_WRITE
	push	bx
	push	di
	push	es
	call	cs:[fdc_mbr]		; write the MBR (modifies BX, ES:BP)
	pop	es
	pop	di			; ES:DI -> DDPRW again
	pop	bx			; CS:BX -> VOL again
	jc	stp9
;
; Make the unit the first FAT partition in the table (the only one FORMAT
; creates); if there isn't one, the unit remains the whole disk.
;
	lds	si,es:[di].DDPRW_ADDR
	mov	cx,4
stp3:	cmp	byte ptr [si+PART_TYPE],PART_FAT12
	je	stp4
	cmp	byte ptr [si+PART_TYPE],PART_FAT16
	je	stp4
	add	si,16
	loop	stp3
	jmp	short stp7		; (carry is clear)
stp4:	push	cs
	pop	es
	mov	ax,[si+PART_LBA]
	mov	es:[bx].VOL_START.LOW,ax
	mov	ax,[si+PART_LBA+2]
	mov	es:[bx].VOL_START.HIW,ax
stp7:	sub	dx,dx			; (carry is clear)
	ret
stp8:	stc
stp9:	mov	dx,0			; (flags are unaffected)
	ret
ENDPROC	set_part

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The MBR that set_part writes, modeled on the pc.js MBR (tools/pc/mbr.asm in
; the PCjs repository) without its drive tables: it moves itself from 7C00h to
; MBR_ORG (7E00h), finds the active partition (rejecting a table with more
; than one, or with any status other than active or inactive), loads the
; partition's boot sector at 7C00h, and jumps to it with SI -> the partition
; entry (which some boot sectors rely on).  Since it runs at MBR_ORG, the
; addresses of its messages are computed from there.
;
MBR_ORG		equ	7E00h

	DEFLBL	mbr_code,byte
	cli
	xor	ax,ax
	mov	ss,ax
	mov	sp,7C00h		; stack below 7C00h
	mov	ds,ax
	mov	es,ax
	sti
	cld
	mov	si,sp			; DS:SI -> 7C00h
	mov	di,MBR_ORG		; ES:DI -> MBR_ORG
	mov	cx,100h
	rep	movsw			; move the MBR to MBR_ORG
	mov	bx,MBR_ORG + (mbr1 - mbr_code)
	jmp	bx			; continue at MBR_ORG
mbr1:	mov	cl,4			; CX = # entries (CH is zero)
	xor	di,di			; DI -> active entry, if any
	mov	si,MBR_ORG + PART_TABLE	; DS:SI -> partition table
mbr2:	cmp	byte ptr [si],80h	; active?
	je	mbr3			; yes
	cmp	byte ptr [si],0		; inactive?
	jne	mbr7			; no, the table is invalid
mbr2a:	add	si,16
	loop	mbr2
	test	di,di			; was there an active entry?
	jnz	mbr4			; yes
	int	18h			; no, so start ROM BASIC
mbr3:	test	di,di			; a second active entry?
	jnz	mbr7			; yes, the table is invalid
	mov	dx,[si]			; DL = drive # (80h), DH = head
	mov	ax,[si+2]		; AL = sector, AH = cylinder
	mov	di,si			; DI -> active entry
	jmp	mbr2a
mbr4:	mov	bp,5			; BP = retries
	mov	bx,sp			; ES:BX -> 7C00h
	xchg	cx,ax			; CH = cylinder, CL = sector
mbr5:	mov	ax,0201h		; AH = read, AL = 1 sector
	int	13h
	jnc	mbr6
	xor	ax,ax
	int	13h			; reset the drive and retry
	dec	bp
	jnz	mbr5
	mov	si,MBR_ORG + (mbr_err - mbr_code)
;
; Display the message at DS:SI and stop.
;
mbr8:	lodsb
	test	al,al
mbr9:	jz	mbr9			; end of message, so stop here
	mov	ah,0Eh
	mov	bx,7			; BH = page 0, BL = attribute 07h
	int	10h
	jmp	mbr8
mbr7:	mov	si,MBR_ORG + (mbr_inv - mbr_code)
	jmp	mbr8
mbr6:	mov	si,MBR_ORG + (mbr_mis - mbr_code)
	cmp	word ptr [bx+1FEh],0AA55h
	jne	mbr8			; no boot sector signature
	mov	si,di			; SI -> active entry
	jmp	sp			; jump to 7C00h
mbr_inv	db	"Invalid partition table",0
mbr_err	db	"Error loading operating system",0
mbr_mis	db	"Missing operating system",0
	DEFABS	MBR_SIZE,<$ - mbr_code>

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
; FAT12/FAT16 partition.  If there are no volumes, the driver isn't needed.
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
	push	cs
	pop	ds
	mov	ds:[0].DDH_REQUEST,offset DEV:ddhdc_req
	mov	ax,BIOS
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
	push	cs
	pop	es
	ASSUME	ES:CODE			; (ES:BX -> DDPI is on the stack)
	mov	ax,[si + size DDH].FDCX_RW
	mov	[fdc_rw].OFF,ax
	mov	ax,[si + size DDH].FDCX_RDBUF
	mov	[fdc_rdbuf].OFF,ax
	mov	ax,[si + size DDH].FDCX_MBR
	mov	[fdc_mbr].OFF,ax
	mov	[fdc_rw].SEG,ds
	mov	[fdc_rdbuf].SEG,ds
	mov	[fdc_mbr].SEG,ds
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
hi1:	mov	[hdc_base],al
	ASSUME	ES:NOTHING
	mov	bp,sp
	mov	es,[bp+2]		; ES:BX -> DDPI again
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
	push	cs
	pop	ds
	ASSUME	DS:CODE
	mov	di,offset vol_table	; DS:DI -> next VOL
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
;	DS:DI -> next VOL (DS = CS)
;
; Outputs:
;	DS:DI -> next VOL (and hdc_vols updated)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	add_vols
	mov	ah,HDC_GETPARMS
	push	dx
	int	INT_FDC			; DH = max head, CX = max cyl/sector
	pop	ax			; AL = BIOS drive #
	jnc	av0
av0a:	jmp	av9
av0:	inc	dh			; DH = # heads
	mov	bl,cl
	and	cl,3Fh			; CL = sectors per track
	jz	av0a
	mov	dl,al			; DL = BIOS drive # again
	mov	al,bl
	and	al,0C0h			; AL = cylinder bits 8-9 (in bits 6-7)
	mov	ah,0
	shl	ax,1
	shl	ax,1
	add	al,ch
	adc	ah,0
	inc	ax			; AX = # cylinders
	mov	bx,ax
	mov	ds:[di].VOL_CYLS,ax	; (for a whole-disk unit, if any)
	push	dx
	push	cx
	mov	ax,(FDC_READ SHL 8) OR 1
	mov	cx,1			; CH = cylinder 0, CL = sector 1
	mov	dh,0			; DH = head 0
	push	bx
	mov	bx,bp			; ES:BX -> scratch buffer
	int	INT_FDC			; read the MBR
	pop	bx
	pop	cx
	pop	dx
	jc	av9
	mov	al,ds:[hdc_vols]	; AL = # volumes before this disk
	cmp	word ptr es:[bp+510],0AA55h
	jne	av7			; not a valid MBR
	lea	si,[bp+PART_TABLE]	; ES:SI -> first partition entry
	mov	ah,4			; AH = # partition entries
av1:	cmp	byte ptr es:[si+PART_TYPE],PART_FAT12
	je	av2			; accept FAT12 primary partitions
	cmp	byte ptr es:[si+PART_TYPE],PART_FAT16 ; FAT16 with 16-bit sector numbers?
	jne	av8			; skip other partition types
av2:	push	ax
	mov	ax,es:[si+PART_LBA]
	mov	ds:[di].VOL_START.LOW,ax
	mov	ax,es:[si+PART_LBA+2]
	mov	ds:[di].VOL_START.HIW,ax
	call	add_vol			; add a volume for the partition
	pop	ax
	jc	av9
av8:	add	si,16
	dec	ah
	jnz	av1
;
; If the disk has no FAT partitions (eg, no MBR), add a unit for the whole
; disk, so that it has a drive letter (and FORMAT can partition it).
;
av7:	cmp	al,ds:[hdc_vols]	; were any volumes added?
	jne	av9			; yes
	sub	ax,ax
	mov	ds:[di].VOL_START.LOW,ax
	mov	ds:[di].VOL_START.HIW,ax
	call	add_vol
av9:	ret
ENDPROC	add_vols

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_vol
;
; Inputs:
;	BX = # cylinders
;	CL = sectors per track
;	DH = # heads
;	DL = BIOS drive #
;	DS:DI -> VOL (with VOL_START already set; DS = CS)
;
; Outputs:
;	Carry clear if added (DS:DI -> next VOL, hdc_vols updated); otherwise,
;	carry set (there's no room for more)
;
; Modifies:
;	AX, DI
;
DEFPROC	add_vol
	cmp	ds:[hdc_vols],MAX_VOLS
	cmc
	jc	avl9
	mov	ds:[di].VOL_DRIVE,dl
	mov	ds:[di].VOL_HEADS,dh
	mov	ds:[di].VOL_TRACKSECS,cl
	mov	ds:[di].VOL_CYLS,bx
	mov	al,cl
	mul	dh
	mov	ds:[di].VOL_CYLSECS,ax
	add	di,size VOL
	inc	ds:[hdc_vols]		; (carry is clear)
avl9:	ret
ENDPROC	add_vol

CODE	ends

DATA	segment para public 'DATA'

ddhdc_end	db	16 dup(0)

DATA	ends

	end
