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
; to the start of its volume).  Like the FDC, the XT hard disk controller uses
; DMA, so transfers must not cross 64K boundaries (see readwrite_sectors).
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
	dw	ddhdc_read,  ddhdc_none,     ddhdc_none,     ddhdc_none	; 4-7
	dw	ddhdc_write, ddhdc_none,     ddhdc_none,     ddhdc_none	; 8-11
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

	DEFBYTE	ddbuf_drv,-1
	DEFWORD	ddbuf_lba,-1
	DEFPTR	ddbuf_ptr,<offset ddhdc_init>

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
;
; Read the volume's boot sector (ie, relative LBA 0) into our buffer.
;
	push	es
	pop	ds
	ASSUME	DS:NOTHING
	mov	si,di			; DS:SI -> BPB
	sub	dx,dx			; DX = LBA (0)
	mov	bx,(FDC_READ SHL 8) OR 1
	push	es
	les	bp,[ddbuf_ptr]		; ES:BP -> our own buffer
	call	readwrite_sectors	; (which also validates the drive #)
	pop	es
	jnc	bb1
	jmp	bb8
bb1:	mov	al,es:[di].BPB_DRIVE
	call	get_vol			; CS:BX -> VOL
	mov	[ddbuf_lba],-1		; (our buffer isn't tied to an LBA)
;
; Copy the standard BPB fields from the boot sector to the BPB provided.
;
	push	di
	lds	si,[ddbuf_ptr]
	add	si,BOOT_BPB		; DS:SI -> boot sector's BPB
	mov	cx,BPB_HIDDENSECS
	rep	movsb
	pop	di
;
; Fill in the rest of the BPB from the volume table.
;
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
	stc

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
; ddhdc_read
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
DEFPROC	ddhdc_read
	push	es
	mov	cx,es:[di].DDPRW_LENGTH
	test	cx,cx		; is length zero (ie, nothing to do)?
	jnz	dcr1		; no
	jmp	dcr8		; yes, all done
;
; If the offset is zero, then there's no need to read a partial first sector.
;
dcr1:	lds	si,es:[di].DDPRW_BPB
	ASSUME	DS:NOTHING	; DS:SI -> BPB
	mov	ax,es:[di].DDPRW_OFFSET
	test	ax,ax
	jz	dcr4
;
; As a preliminary matter, reduce offset and advance LBA until offset is
; within the first sector to read; moreover, if this reduces offset to zero,
; then once again, there's no need for a partial first sector read.
;
; We presume that DOS will not get carried here and generate ridiculously
; large offsets, hence the simple loop; the most common scenario would be
; requesting an offset beyond the first sector of a multi-sector cluster (but
; still within the cluster).
;
dcr1a:	cmp	ax,[si].BPB_SECBYTES
	jb	dcr1b
	inc	es:[di].DDPRW_LBA
	sub	ax,[si].BPB_SECBYTES
	jz	dcr4
	jmp	dcr1a
dcr1b:	mov	es:[di].DDPRW_OFFSET,ax

	mov	dx,es:[di].DDPRW_LBA
	call	read_buffer	; read LBA (DX) into ddbuf
	jc	dcr4a
;
; Reload the offset: copy bytes from ddbuf+offset to the target address.
;
dcr2:	mov	ax,es:[di].DDPRW_OFFSET
	mov	cx,[si].BPB_SECBYTES
	sub	cx,ax
	mov	dx,es:[di].DDPRW_LENGTH
	cmp	cx,dx		; partial read smaller than requested?
	jb	dcr2a		; yes
	mov	cx,dx		; no, limit it to the requested length
dcr2a:	push	si
	push	di
	push	ds
	push	es
	lds	si,[ddbuf_ptr]	; DS:SI -> our own buffer
	add	si,ax		; add offset
	mov	ax,cx		; save byte transfer count in AX
	les	di,es:[di].DDPRW_ADDR
	shr	cx,1
	rep	movsw		; transfer CX words from our own buffer
	jnc	dcr2b
	movsb
dcr2b:	pop	es
	pop	ds
	pop	di
	pop	si
	mov	es:[di].DDPRW_OFFSET,cx
	inc	es:[di].DDPRW_LBA
	add	es:[di].DDPRW_ADDR.OFF,ax
	sub	es:[di].DDPRW_LENGTH,ax
	ASSERT	NC
	mov	cx,es:[di].DDPRW_LENGTH
;
; At this point, we know that the transfer offset is now zero, so we're free to
; transfer as many whole sectors as remain in the request.
;
dcr4:	xchg	ax,cx		; convert length in AX to # sectors
	cwd
	div	[si].BPB_SECBYTES
	mov	cx,dx		; CX = final partial sector bytes, if any
	test	al,al		; any whole sectors?
	jz	dcr5		; no
	push	es
	mov	ah,FDC_READ
	xchg	bx,ax		; BH = BIOS cmd, BL = # sectors
	mov	dx,es:[di].DDPRW_LBA
	les	bp,es:[di].DDPRW_ADDR
	call	readwrite_sectors
	pop	es
dcr4a:	jc	dcr8
	mov	al,bl
	cbw
	add	es:[di].DDPRW_LBA,ax
	mul	[si].BPB_SECBYTES
	add	es:[di].DDPRW_ADDR.OFF,ax
	sub	es:[di].DDPRW_LENGTH,ax
;
; And finally, the tail end of the request, if there are CX bytes remaining.
;
dcr5:	test	cx,cx		; anything remaining?
	jz	dcr8		; no

dcr6:	mov	dx,es:[di].DDPRW_LBA
	call	read_buffer	; read LBA (DX) into ddbuf
	jc	dcr8

dcr7:	push	di
	push	es
	lds	si,[ddbuf_ptr]	; DS:SI -> our own buffer
	les	di,es:[di].DDPRW_ADDR
	mov	ax,cx
	shr	cx,1
	rep	movsw		; transfer words from our own buffer
	jnc	dcr7a
	movsb
dcr7a:	pop	es
	pop	di
	add	es:[di].DDPRW_ADDR.OFF,ax
	sub	es:[di].DDPRW_LENGTH,ax
	ASSERT	Z,<cmp es:[di].DDPRW_LENGTH,cx>

dcr8:	pop	es
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	dcr9

	mov	es:[di].DDPRW_LENGTH,0
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
dcr9:	ret
ENDPROC	ddhdc_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddhdc_write
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
; Notes:
;	This is essentially the inverse of ddhdc_read: a partial first
;	sector and/or a partial last sector are read into ddbuf, merged with
;	the caller's data, and then written back, while all whole sectors are
;	written directly from the caller's buffer.
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddhdc_write
	push	es
	mov	cx,es:[di].DDPRW_LENGTH
	test	cx,cx		; is length zero (ie, nothing to do)?
	jnz	dcw1		; no
	jmp	dcw8		; yes, all done
;
; If the offset is zero, then there's no need to write a partial first sector.
;
dcw1:	lds	si,es:[di].DDPRW_BPB
	ASSUME	DS:NOTHING	; DS:SI -> BPB
	mov	ax,es:[di].DDPRW_OFFSET
	test	ax,ax
	jz	dcw4
;
; As in ddhdc_read, reduce offset and advance LBA until offset is within
; the first sector to write; if this reduces offset to zero, then once again,
; there's no need for a partial first sector write.
;
dcw1a:	cmp	ax,[si].BPB_SECBYTES
	jb	dcw1b
	inc	es:[di].DDPRW_LBA
	sub	ax,[si].BPB_SECBYTES
	jz	dcw4
	jmp	dcw1a
dcw1b:	mov	es:[di].DDPRW_OFFSET,ax

	mov	dx,es:[di].DDPRW_LBA
	call	read_buffer	; read LBA (DX) into ddbuf
	jc	dcw4a
;
; Reload the offset: copy bytes from the source address to ddbuf+offset.
;
dcw2:	mov	ax,es:[di].DDPRW_OFFSET
	mov	cx,[si].BPB_SECBYTES
	sub	cx,ax
	mov	dx,es:[di].DDPRW_LENGTH
	cmp	cx,dx		; partial write smaller than requested?
	jb	dcw2a		; yes
	mov	cx,dx		; no, limit it to the requested length
dcw2a:	push	si
	push	di
	push	ds
	push	es
	mov	bx,ax		; BX = offset
	mov	ax,cx		; save byte transfer count in AX
	lds	si,es:[di].DDPRW_ADDR
	les	di,[ddbuf_ptr]	; ES:DI -> our own buffer
	add	di,bx		; add offset
	shr	cx,1
	rep	movsw		; transfer CX words to our own buffer
	jnc	dcw2b
	movsb
dcw2b:	pop	es
	pop	ds
	pop	di
	pop	si
	push	ax		; save byte transfer count
	mov	dx,es:[di].DDPRW_LBA
	call	write_buffer	; write ddbuf to LBA (DX)
	pop	cx		; CX = byte transfer count
	jc	dcw4a
	mov	es:[di].DDPRW_OFFSET,0
	inc	es:[di].DDPRW_LBA
	add	es:[di].DDPRW_ADDR.OFF,cx
	sub	es:[di].DDPRW_LENGTH,cx
	ASSERT	NC
	mov	cx,es:[di].DDPRW_LENGTH
;
; At this point, we know that the transfer offset is now zero, so we're free to
; transfer as many whole sectors as remain in the request.
;
dcw4:	xchg	ax,cx		; convert length in AX to # sectors
	cwd
	div	[si].BPB_SECBYTES
	mov	cx,dx		; CX = final partial sector bytes, if any
	test	al,al		; any whole sectors?
	jz	dcw5		; no
	push	es
	mov	ah,FDC_WRITE
	xchg	bx,ax		; BH = BIOS cmd, BL = # sectors
	mov	dx,es:[di].DDPRW_LBA
	les	bp,es:[di].DDPRW_ADDR
	call	readwrite_sectors
	pop	es
;
; Since ddbuf may contain a copy of one of the sectors we just wrote,
; invalidate it.
;
	mov	[ddbuf_lba],-1
dcw4a:	jc	dcw8
	mov	al,bl
	cbw
	add	es:[di].DDPRW_LBA,ax
	mul	[si].BPB_SECBYTES
	add	es:[di].DDPRW_ADDR.OFF,ax
	sub	es:[di].DDPRW_LENGTH,ax
;
; And finally, the tail end of the request, if there are CX bytes remaining;
; like the partial first sector, the rest of the sector must be read first.
;
dcw5:	test	cx,cx		; anything remaining?
	jz	dcw8		; no

	mov	dx,es:[di].DDPRW_LBA
	call	read_buffer	; read LBA (DX) into ddbuf
	jc	dcw8

	push	si
	push	di
	push	ds
	push	es
	lds	si,es:[di].DDPRW_ADDR
	les	di,[ddbuf_ptr]	; ES:DI -> our own buffer
	mov	ax,cx
	shr	cx,1
	rep	movsw		; transfer words to our own buffer
	jnc	dcw7a
	movsb
dcw7a:	pop	es
	pop	ds
	pop	di
	pop	si
	push	ax		; save byte transfer count
	mov	dx,es:[di].DDPRW_LBA
	call	write_buffer	; write ddbuf to LBA (DX)
	pop	cx		; CX = byte transfer count
	jc	dcw8
	add	es:[di].DDPRW_ADDR.OFF,cx
	sub	es:[di].DDPRW_LENGTH,cx
	ASSERT	Z

dcw8:	pop	es
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	dcw9

	mov	es:[di].DDPRW_LENGTH,0
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
dcw9:	ret
ENDPROC	ddhdc_write

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Read 1 sector into our internal buffer
;
; Inputs:
;	DX = LBA
;	DS:SI -> BPB (drive to read is BPB_DRIVE)
;
; Outputs:
;	Carry clear if successful
;
; Modifies:
;	AX, BX, DX, BP
;
DEFPROC	read_buffer
	mov	al,[si].BPB_DRIVE
	cmp	al,[ddbuf_drv]
	jne	rb1
	cmp	dx,[ddbuf_lba]
	je	rb9		; skipping the read (we've already got it)
rb1:	push	es
	mov	bx,(FDC_READ SHL 8) OR 1
	les	bp,[ddbuf_ptr]	; ES:BP -> our own buffer
	call	readwrite_sectors
	pop	es
	jc	rb9		; TODO: can errors damage the buffer contents?
	mov	al,[si].BPB_DRIVE
	mov	[ddbuf_drv],al
	mov	[ddbuf_lba],dx
rb9:	ret
ENDPROC	read_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Write 1 sector from our internal buffer
;
; Inputs:
;	DX = LBA
;	DS:SI -> BPB (drive to write is BPB_DRIVE)
;
; Outputs:
;	Carry clear if successful (and ddbuf is now a valid copy of the LBA)
;	Carry set if error (and ddbuf is invalidated), AX = driver error code
;
; Modifies:
;	AX, BX, BP
;
DEFPROC	write_buffer
	push	es
	mov	bx,(FDC_WRITE SHL 8) OR 1
	les	bp,[ddbuf_ptr]	; ES:BP -> our own buffer
	call	readwrite_sectors
	pop	es
	jc	wb8
	mov	al,[si].BPB_DRIVE
	mov	[ddbuf_drv],al
	mov	[ddbuf_lba],dx
	ret
wb8:	mov	[ddbuf_lba],-1	; ddbuf no longer matches the disk
	ret
ENDPROC	write_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Call BIOS to read/write sectors
;
; We break every request into one or more single-track requests, and like the
; FDC, we limit each request to the sectors that precede the next 64K boundary;
; a sector that would cross a 64K boundary is transferred through our own
; buffer instead (otherwise, the BIOS reports DDERR_DMA64K).
;
; Inputs:
;	BH = BIOS cmd (FDC_READ or FDC_WRITE)
;	BL = # sectors
;	DX = LBA (relative to the volume)
;	DS:SI -> BPB
;	ES:BP -> buffer
;
; Outputs:
;	If carry clear, success (AX is whatever the BIOS returned)
;	If carry set, AX is a driver error code (ie, the BIOS error code)
;
; Modifies:
;	AX
;
; NOTE: Like the FDC driver, we advance the transfer address by adding to ES
; rather than BP.
;
DEFPROC	readwrite_sectors
	ASSUME	DS:NOTHING
	push	bx
	push	cx
	push	dx
	push	di
	push	es
	push	bx
	mov	al,[si].BPB_DRIVE
	call	get_vol			; CS:BX -> VOL
	mov	di,bx			; CS:DI -> VOL
	pop	bx
	mov	ax,DDERR_UNKUNIT
	jnc	rw1
	jmp	rw8a

rw1:	push	dx			; save LBA
	push	bx			; save BIOS cmd and # sectors
	mov	ax,dx
	sub	dx,dx
	add	ax,cs:[di].VOL_START.LOW
	adc	dx,cs:[di].VOL_START.HIW; DX:AX = absolute LBA
	div	cs:[di].VOL_CYLSECS	; AX = cylinder, DX = cylinder sector
	mov	cx,ax			; CX = cylinder
	xchg	ax,dx
	div	cs:[di].VOL_TRACKSECS	; AL = head, AH = sector in track
	mov	dh,al			; DH = head
	mov	al,cs:[di].VOL_TRACKSECS
	sub	al,ah			; AL = # sectors left on the track
	cmp	al,bl			; more than requested?
	jbe	rw2			; no
	mov	al,bl			; yes, so use the # requested
rw2:	inc	ah			; AH = sector ID
	xchg	ch,cl			; CH = cylinder bits 0-7
	ror	cl,1
	ror	cl,1			; CL bits 6-7 = cylinder bits 8-9
	or	cl,ah			; CL bits 0-5 = sector ID
	mov	dl,cs:[di].VOL_DRIVE	; DL = BIOS drive #
	mov	ah,bh			; AH = BIOS cmd, AL = # sectors
;
; Reduce AL to the # sectors that precede the next 64K boundary.
;
	push	cx
	mov	bx,es
	mov	cl,4
	shl	bx,cl
	add	bx,bp			; BX = low 16 bits of physical address
	mov	cl,al			; CL = # sectors
	mov	al,0			; AL = # sectors before the boundary
rw2a:	add	bx,512
	jc	rw2b
	inc	ax
	cmp	al,cl
	jb	rw2a
rw2b:	pop	cx
	test	al,al			; any sectors before the boundary?
	jz	rw4			; no
	push	ax
	mov	bx,bp			; ES:BX -> buffer
	int	INT_FDC			; AX and carry are from the ROM
rw3:	pop	cx
	mov	ch,0			; CX = # sectors this iteration
	pop	bx			; BL = total # sectors
	pop	dx			; DX = LBA again
	jc	rw8
	sub	bl,cl			; any sectors remaining?
	jbe	rw9			; no
	add	dx,cx			; advance LBA in DX
	xchg	ax,cx
	mov	cl,5			; (512-byte sectors are 32 paragraphs)
	shl	ax,cl			; AX = # paragraphs in request
	mov	cx,es
	add	cx,ax
	mov	es,cx			; advance transfer address in ES
	jmp	rw1
;
; The next sector crosses a 64K boundary, so transfer it through our own
; buffer (which no longer matches ddbuf_lba afterward).
;
rw4:	mov	al,1			; AL = 1 sector
	push	ax			; save BIOS cmd and # sectors
	push	si
	push	di
	push	ds
	push	es
	push	cx
	mov	cx,256			; CX = # words in a sector
	push	es
	pop	ds
	mov	si,bp			; DS:SI -> caller's buffer
	les	di,cs:[ddbuf_ptr]	; ES:DI -> our own buffer
	cmp	ah,FDC_READ		; reading?
	je	rw4a			; yes
	rep	movsw			; no, so copy the sector to our buffer
rw4a:	pop	cx			; CX = cylinder and sector ID again
	mov	bx,cs:[ddbuf_ptr].OFF	; ES:BX -> our own buffer
	int	INT_FDC			; AX and carry are from the ROM
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	bx			; BH = BIOS cmd, BL = 1
	jc	rw4c
	mov	cs:[ddbuf_lba],-1	; invalidate our buffer's LBA
	cmp	bh,FDC_READ		; reading?
	jne	rw4c			; no (and carry is clear)
	push	si
	push	di
	push	ds
	push	cx
	lds	si,cs:[ddbuf_ptr]	; DS:SI -> our own buffer
	mov	di,bp			; ES:DI -> caller's buffer
	mov	cx,256
	rep	movsw			; copy the sector to the caller
	pop	cx
	pop	ds
	pop	di
	pop	si			; (carry is still clear)
rw4c:	push	bx
	jmp	rw3
;
; BIOS error codes (in AH) are also driver error codes (see DDERR in dev.inc).
;
rw8:	mov	al,ah
	mov	ah,0			; AX = driver error code
rw8a:	stc

rw9:	pop	es
	pop	di
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	readwrite_sectors

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
	mov	[ddbuf_ptr].SEG,cs
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
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
; We're not keeping any of this code, but we are reserving 512 bytes
; for an internal sector buffer (ddbuf), unless there are no volumes, in
; which case we're not keeping anything.
;
	sub	cx,cx
	test	al,al
	jz	hi9
	mov	cx,offset ddhdc_init + 512
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
