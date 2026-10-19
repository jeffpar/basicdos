;
; BASIC-DOS Floppy Drive Controller Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This driver supports diskette drives, by way of the ROM BIOS (INT 13h).  Its
; read and write code (and its sector buffer) are shared with the HDC driver,
; which calls fdc_rw and fdc_rdbuf (see FDCX in dev.inc), since INT 13h
; works the same way for both: the code uses the geometry in the BPB, along
; with BPB_HIDDENSECS as a hard disk volume's first sector (diskettes have
; no hidden sectors), and the caller provides the BIOS drive # (rw_drive).
; Requests are never concurrent (the kernel locks the session while it uses
; a driver), so one buffer suffices.
;
; Two IOCTLs support formatting: IOCTL_SETPARMS gives a volume a BPB (so that
; an unformatted diskette can be written), and IOCTL_FORMAT formats and
; verifies a track (see ddfdc_ioctl).
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

	public	FDC
FDC 	DDH	<offset DEV:ddfdc_end+16,,DDATTR_BLOCK+DDATTR_IOCTL,offset ddfdc_init,-1,2020202024434446h>
	dw	offset DEV:fdc_rw, offset DEV:fdc_rdbuf	; FDCX (see dev.inc)
	dw	offset DEV:fdc_mbr

	DEFLBL	CMDTBL,word
	dw	ddfdc_none,  ddfdc_mediachk, ddfdc_buildbpb, ddfdc_ioctl
	dw	ddfdc_read,  ddfdc_none,     ddfdc_none,     ddfdc_none
	dw	ddfdc_write, ddfdc_none,     ddfdc_none,     ddfdc_none
	dw	ddfdc_none,  ddfdc_none,     ddfdc_none,     ddfdc_none
	dw	ddfdc_none,  ddfdc_none,     ddfdc_none,     ddfdc_none
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFBYTE	rw_drive,0		; BIOS drive # for readwrite_sectors
	DEFBYTE	rw_pio,0		; 80h if hard disks don't use DMA
	DEFBYTE	ddbuf_drv,-1
	DEFWORD	ddbuf_lba,-1
	DEFPTR	ddbuf_ptr,<offset ddfdc_init>

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
DEFPROC	ddfdc_req,far
	mov	di,bx		; ES:DI -> DDP
	mov	al,es:[di].DDP_UNIT
	mov	cs:[rw_drive],al; (diskette units are BIOS drive #s)
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
ENDPROC	ddfdc_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddfdc_mediachk
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	DDP_CONTEXT contains the MC (media check) status code
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddfdc_mediachk
	lds	si,es:[di].DDPRW_BPB
	ASSUME	DS:NOTHING	; DS:SI -> BPB
	mov	ah,TIME_GETTICKS
	int	INT_TIME	; CX:DX is current tick count
	push	cx
	push	dx
	mov	ax,[si].BPB_TIMESTAMP.OFF
	mov	bx,[si].BPB_TIMESTAMP.SEG
	or	ax,bx
	mov	ax,MC_UNKNOWN	; default to UNKNOWN
	jz	mc1		; existing timestamp is zero, treat as UNKNOWN
	sub	dx,[si].BPB_TIMESTAMP.OFF
	sbb	cx,bx
	jb	mc1		; underflow, use default
	test	cx,cx		; large difference?
	jnz	mc1		; yes, use default
	cmp	dx,38		; more than 2 seconds of ticks?
	jae	mc1		; yes, use default
	inc	ax		; change from UNKNOWN to UNCHANGED
mc1:	cmp	[si].BPB_SECBYTES,0	; has the BPB been built?
	jne	mc2			; yes
	mov	ax,MC_CHANGED		; no, so it must be (re)built
mc2:	pop	[si].BPB_TIMESTAMP.OFF
	pop	[si].BPB_TIMESTAMP.SEG
	mov	es:[di].DDP_CONTEXT,ax
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddfdc_mediachk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddfdc_buildbpb
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
DEFPROC	ddfdc_buildbpb
	push	di
	push	es
	lds	si,es:[di].DDPRW_BPB
	ASSUME	DS:NOTHING	; DS:SI -> BPB
	mov	[si].BPB_SECBYTES,0	; the BPB isn't valid (yet)
;
; If this is an uninitialized BPB, then it won't have the geometry that
; readwrite_sectors requires; that's what happens when we use a single
; parameter block to describe everything from volume geometry to media
; geometry to drive geometry.  Oh well.
;
; For now, we resolve this by providing some hard-coded drive geometry,
; which should be good enough for reading the first sector.
;
	mov	[si].BPB_CYLSECS,8
	mov	[si].BPB_TRACKSECS,8

	sub	dx,dx		; DX = LBA (0)
	mov	al,[si].BPB_DRIVE
	mov	bx,(FDC_READ SHL 8) OR 1
	les	bp,[ddbuf_ptr]	; ES:BP -> our own buffer
	call	readwrite_sectors
	jc	bb8
;
; Initialize the BPB provided from the boot sector in our buffer, which now
; holds LBA 0 of the drive.
;
	mov	al,[si].BPB_DRIVE
	mov	cs:[ddbuf_drv],al
	mov	cs:[ddbuf_lba],dx	; (DX is still LBA 0)
	push	ds
	pop	es
	mov	di,si		; ES:DI -> BPB
	lds	si,cs:[ddbuf_ptr]
	add	si,BOOT_BPB	; DS:SI -> BPB in the boot sector
	call	init_bpb

bb8:	pop	es
	pop	di
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	bb9
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
bb9:	ret
ENDPROC	ddfdc_buildbpb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_bpb
;
; Copies a BPB (from a boot sector, or from IOCTL_SETPARMS) to a volume's
; BPB, timestamps it, and initializes the rest of the BPB extension data,
; after making sure the BPB is usable (512-byte sectors, a power-of-two
; number of sectors per cluster, and sensible geometry); otherwise (eg, a
; diskette whose boot sector has no BPB, like PC DOS 1.0), the media is
; unknown.
;
; Inputs:
;	DS:SI -> BPB data (at least BPB_DRIVE bytes)
;	ES:DI -> BPB to initialize (BPB_DRIVE is preserved)
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
	mov	bl,es:[di].BPB_DRIVE
	mov	cx,size BPB SHR 1
	rep	movsw
	mov	ah,TIME_GETTICKS
	int	INT_TIME	; CX:DX is current tick count
	xchg	ax,dx
	stosw			; update BPB_TIMESTAMP.OFF
	xchg	ax,cx
	stosw			; update BPB_TIMESTAMP.SEG
	sub	ax,ax
	stosw			; update BPB_DEVICE.OFF
	mov	ax,cs
	stosw			; update BPB_DEVICE.SEG
	pop	di
	mov	es:[di].BPB_DRIVE,bl

	cmp	es:[di].BPB_SECBYTES,512
	je	bb4a
bb4:	jmp	bb5
bb4a:	mov	al,es:[di].BPB_CLUSSECS
	mov	ah,al
	dec	ah
	test	al,ah			; zero or a power-of-two?
	jnz	bb4			; no
	test	al,al			; zero?
	jz	bb4			; yes
	mov	ax,es:[di].BPB_TRACKSECS
	dec	ax
	cmp	ax,63			; 1-63 sectors per track?
	jae	bb4			; no
	mov	ax,es:[di].BPB_DRIVEHEADS
	dec	ax
	cmp	ax,255			; 1-255 heads?
	jae	bb4			; no
	mov	ax,es:[di].BPB_TRACKSECS
	mul	es:[di].BPB_DRIVEHEADS
	mov	es:[di].BPB_CYLSECS,ax
	mov	ax,es:[di].BPB_FATSECS
	mov	dl,es:[di].BPB_FATS
	mov	dh,0
	mul	dx
	add	ax,es:[di].BPB_RESSECS
	mov	es:[di].BPB_LBAROOT,ax
	mov	ax,es:[di].BPB_DIRENTS
	mov	dx,size DIRENT
	mul	dx
	mov	cx,es:[di].BPB_SECBYTES
	add	ax,cx
	dec	ax
	div	cx
	add	ax,es:[di].BPB_LBAROOT
	mov	es:[di].BPB_LBADATA,ax
	xchg	dx,ax		; save LBADATA in DX

	sub	cx,cx
	mov	al,es:[di].BPB_CLUSSECS
	test	al,al		; calculate LOG2 of CLUSSECS
	ASSERT	NZ		; assert that CLUSSECS is non-zero
bb6:	shr	al,1
	jc	bb7
	inc	cx
	jmp	bb6
bb7:	ASSERT	Z		; assert CLUSSECS was a power-of-two
	mov	es:[di].BPB_CLUSLOG2,cl
	mov	ax,es:[di].BPB_SECBYTES
	shl	ax,cl		; use CLUSLOG2 to calculate CLUSBYTES
	mov	es:[di].BPB_CLUSBYTES,ax
;
; Finally, calculate total clusters on the disk (total data sectors
; divided by sectors per cluster, or just another shift using CLUSLOG2).
;
	mov	ax,es:[di].BPB_DISKSECS
	sub	ax,dx		; AX = DISKSECS - LBADATA = total data sectors
	shr	ax,cl		; AX = data clusters
	mov	es:[di].BPB_CLUSTERS,ax
	clc
	ret

bb5:	mov	es:[di].BPB_SECBYTES,0	; the BPB isn't valid
	mov	ax,DDERR_UNKMEDIA
	stc
	ret
ENDPROC	init_bpb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddfdc_read
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
DEFPROC	ddfdc_read
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
	inc	es:[di].DDPRW_LBA
	add	es:[di].DDPRW_ADDR.OFF,ax
	sub	es:[di].DDPRW_LENGTH,ax
	ASSERT	NC
	mov	cx,es:[di].DDPRW_LENGTH
;
; At this point, we know that the transfer offset is now zero, so we're free to
; transfer as many whole sectors as remain in the request.
; Save that offset in the packet so RETRY cannot advance the LBA again after
; normalizing an offset that was an exact multiple of the sector size.
;
dcr4:	mov	es:[di].DDPRW_OFFSET,0
	xchg	ax,cx		; convert length in AX to # sectors
	sub	dx,dx		; (lengths can exceed 32K, so no CWD)
	div	[si].BPB_SECBYTES
	mov	cx,dx		; CX = final partial sector bytes, if any
	test	al,al		; any whole sectors?
	jz	dcr5		; no
	push	es
	mov	ah,FDC_READ
	xchg	bx,ax		; BH = FDC cmd, BL = # sectors
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
;
; Preserve the remaining length so DOS can reissue the request on RETRY.
;
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
dcr9:	ret
ENDPROC	ddfdc_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddfdc_write
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
;	This is essentially the inverse of ddfdc_read: a partial first
;	sector and/or a partial last sector are read into ddbuf, merged with
;	the caller's data, and then written back, while all whole sectors are
;	written directly from the caller's buffer.
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddfdc_write
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
; As in ddfdc_read, reduce offset and advance LBA until offset is within
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
	inc	es:[di].DDPRW_LBA
	add	es:[di].DDPRW_ADDR.OFF,cx
	sub	es:[di].DDPRW_LENGTH,cx
	ASSERT	NC
	mov	cx,es:[di].DDPRW_LENGTH
;
; At this point, we know that the transfer offset is now zero, so we're free to
; transfer as many whole sectors as remain in the request.
; Save that offset in the packet so RETRY cannot advance the LBA again after
; normalizing an offset that was an exact multiple of the sector size.
;
dcw4:	mov	es:[di].DDPRW_OFFSET,0
	xchg	ax,cx		; convert length in AX to # sectors
	sub	dx,dx		; (lengths can exceed 32K, so no CWD)
	div	[si].BPB_SECBYTES
	mov	cx,dx		; CX = final partial sector bytes, if any
	test	al,al		; any whole sectors?
	jz	dcw5		; no
	push	es
	mov	ah,FDC_WRITE
	xchg	bx,ax		; BH = FDC cmd, BL = # sectors
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
;
; Preserve the remaining length so DOS can reissue the request on RETRY.
;
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
dcw9:	ret
ENDPROC	ddfdc_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddfdc_none (handler for unimplemented functions)
;
; Inputs:
;	DS:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddfdc_none
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	ret
ENDPROC	ddfdc_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddfdc_ioctl
;
; IOCTL_SETPARMS copies a BPB (eg, the one that FORMAT puts in a new boot
; sector) from DDPRW_ADDR to the volume's BPB (see init_bpb), so that the
; volume of an unformatted diskette can be written, and IOCTL_FORMAT formats
; and verifies the track at cylinder DDPRW_LENGTH, head DDPRW_LBA (see
; format_track).  IOCTL_GETPART returns nothing (diskettes have no partition
; table), so FORMAT can tell a diskette from a hard disk.  Errors are returned
; to the caller (see dev_request).
;
; Inputs:
;	ES:DI -> DDPRW (DDP_CODE = IOCTL code)
;
; Outputs:
;	DDP_STATUS updated (and DDP_CONTEXT is zero)
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddfdc_ioctl
	mov	es:[di].DDP_CONTEXT,0
	mov	al,es:[di].DDP_CODE
	cmp	al,IOCTL_SETPARMS
	je	dio1
	cmp	al,IOCTL_FORMAT
	je	dio2
	cmp	al,IOCTL_GETPART	; (carry clear if equal)
	je	dio8
	jmp	ddfdc_none
dio1:	mov	ax,DDERR_BADREQ
	cmp	es:[di].DDPRW_LENGTH,BPB_DRIVE	; enough data for a BPB?
	jb	dio8				; no
	push	di
	push	es
	lds	si,es:[di].DDPRW_ADDR	; DS:SI -> caller's BPB
	les	di,es:[di].DDPRW_BPB	; ES:DI -> volume's BPB
	call	init_bpb
	jmp	short dio7
dio2:	push	di
	push	es
	call	format_track
dio7:	pop	es
	pop	di
dio8:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	dio9
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
dio9:	ret
ENDPROC	ddfdc_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; format_track
;
; Formats and verifies one track, with the sectors per track in the volume's
; BPB (which IOCTL_SETPARMS supplied, if the diskette was unformatted).  The
; BIOS formats a track from a table of sector IDs (cylinder, head, sector,
; and size code), which we build in ddbuf, and it takes the number of sectors
; from the DPT (see set_dpt); on a PC AT, the media type must be set first
; (FDC_SETDASD), since the BIOS can't determine it from unformatted media.
; The BPB is timestamped afterward, so that the media check that follows
; (eg, when FORMAT writes the boot sector) treats the media as unchanged.
;
; Inputs:
;	ES:DI -> DDPRW (DDPRW_LENGTH = cylinder, DDPRW_LBA = head)
;
; Outputs:
;	Carry clear if successful; otherwise, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	format_track
	lds	si,es:[di].DDPRW_BPB	; DS:SI -> BPB
	mov	ch,byte ptr es:[di].DDPRW_LENGTH; CH = cylinder
	mov	dh,byte ptr es:[di].DDPRW_LBA	; DH = head
	mov	bl,byte ptr [si].BPB_TRACKSECS	; BL = sectors per track
	mov	dl,[si].BPB_DRIVE		; DL = drive #
	mov	al,bl
	call	set_dpt			; set the DPT's sectors per track
	test	cs:[rw_pio],80h		; PC AT?
	jz	ft2			; no
;
; Set the media type: 1 (360K in a 360K drive), 2 (360K in a 1.2M drive),
; 3 (1.2M), or 4 (720K), from the drive type that HDC_GETPARMS returns in BL
; (1 = 360K, 2 = 1.2M, 3 = 720K, 4 = 1.44M); that function also returns the
; DPT address in ES:DI, so those registers are preserved.
;
	push	bx
	push	cx
	push	dx
	push	es
	push	di
	mov	ah,HDC_GETPARMS
	int	INT_FDC			; BL = drive type
	mov	al,bl			; AL = drive type
	pop	di
	pop	es
	pop	dx
	pop	cx
	pop	bx
	jc	ft2			; no drive type, so leave it alone
	cmp	al,3			; 3.5" drive?
	jb	ft1			; no
	mov	al,4			; yes, so the media type is 720K
ft1:	cmp	bl,15			; 1.2M media?
	jb	ft1a			; no
	mov	al,3
ft1a:	mov	ah,FDC_SETDASD
	int	INT_FDC
;
; Build the table of sector IDs in ddbuf, which no longer holds a sector.
;
ft2:	mov	cs:[ddbuf_lba],-1
	les	di,cs:[ddbuf_ptr]	; ES:DI -> ddbuf
	push	di
	mov	bh,1			; BH = sector ID
ft3:	mov	al,ch
	mov	ah,dh
	stosw				; cylinder, head
	mov	al,bh
	mov	ah,2			; (the size code for 512-byte sectors)
	stosw				; sector, size code
	inc	bh
	cmp	bh,bl
	jbe	ft3
	mov	al,bl			; AL = # sectors
	pop	bx			; ES:BX -> sector IDs
	mov	cl,1			; (CL bits 6-7 = cylinder bits 8-9)
	mov	ah,FDC_FORMAT
	push	ax
	call	bios_rw			; format the track
	pop	ax
	jc	ft8
	mov	ah,FDC_VERIFY
	call	bios_rw			; verify the track
	jc	ft8
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	mov	[si].BPB_TIMESTAMP.OFF,dx
	mov	[si].BPB_TIMESTAMP.SEG,cx
	clc
	ret
;
; BIOS error codes (in AH) are also driver error codes (see DDERR in dev.inc).
;
ft8:	mov	al,ah
	mov	ah,0			; AX = driver error code
	stc
	ret
ENDPROC	format_track

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_dpt
;
; Sets the DPT's sectors per track (its "end of track" sector, which the
; BIOS needs for every diskette transfer, as well as for formatting) and
; its format gap length.  The boot code moved the DPT to RAM (see boot.asm),
; so it can be changed.
;
; Inputs:
;	AL = sectors per track
;
; Outputs:
;	None
;
; Modifies:
;	AH
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_dpt
	push	ds
	push	bx
	sub	bx,bx
	mov	ds,bx
	ASSUME	DS:BIOS
	lds	bx,dword ptr ds:[INT_DPT*4]
	ASSUME	DS:NOTHING		; DS:BX -> DPT
	mov	[bx].DP_SPT,al
	mov	ah,50h			; gap length for 8 or 9 sectors
	cmp	al,9
	jbe	sd1
	mov	ah,54h			; gap length for 15 sectors
sd1:	mov	[bx].DP_GAP3,ah
	pop	bx
	pop	ds
	ret
ENDPROC	set_dpt

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
	ASSUME	DS:NOTHING
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
; There are several annoying problems that the IBM PC disk system suffers
; from, which you'll be happy to know this function (finally) addresses:
;
;    1)	Multi-sector requests that cross track boundaries
;    2)	Requests that cross 64K memory boundaries (since disks use DMA)
;
; We break every request into one or more single-track requests, and within
; each single-track request, we transfer all sectors that precede a 64K
; boundary, then the next sector, if any, by way of our own buffer, and then
; any remaining sectors on the track.  The DPT's sectors per track is set
; from the BPB first, since the BIOS stops a transfer at that sector (and the
; ROM's value may not match the media, eg, 8-sector diskettes).
;
; PC AT hard disks are the exception: the AT fixed disk BIOS uses programmed
; I/O rather than DMA, and it normalizes ES:BX, so a single-track request can
; never cross a boundary it cares about (see rw_pio).
;
; Inputs:
;	BH = BIOS cmd (FDC_READ or FDC_WRITE)
;	BL = # sectors
;	DX = LBA (relative to the volume; see BPB_HIDDENSECS)
;	DS:SI -> BPB
;	ES:BP -> buffer
;	CS:[rw_drive] = BIOS drive #
;
; Outputs:
;	If carry clear, success (AX is whatever the BIOS returned)
;	If carry set, AX is a driver error code (ie, the BIOS error code)
;
; Modifies:
;	AX
;
; NOTE: We advance the transfer address by adding to ES rather than BP, so
; that a large transfer can extend beyond ES:FFFFh (eg, when loading a large
; program into a buffer that doesn't begin at offset zero).
;
DEFPROC	readwrite_sectors
	ASSUME	DS:NOTHING
	push	bx
	push	cx
	push	dx
	push	es
	test	cs:[rw_drive],80h	; hard disk?
	jnz	rw1			; yes (the DPT is only for diskettes)
	mov	al,byte ptr [si].BPB_TRACKSECS
	call	set_dpt			; set the DPT's sectors per track

rw1:	push	dx			; save LBA
	push	bx			; save BIOS cmd and # sectors
	mov	ax,dx
	sub	dx,dx
	test	cs:[rw_drive],80h	; hard disk?
	jz	rw1a			; no (diskettes have no hidden sectors)
	add	ax,[si].BPB_HIDDENSECS.LOW
	adc	dx,[si].BPB_HIDDENSECS.HIW; DX:AX = absolute LBA
rw1a:	div	[si].BPB_CYLSECS	; AX = cylinder, DX = cylinder sector
	mov	cx,ax			; CX = cylinder
	xchg	ax,dx
	div	byte ptr [si].BPB_TRACKSECS
	mov	dh,al			; DH = head, AH = sector in track
	mov	al,byte ptr [si].BPB_TRACKSECS
	sub	al,ah			; AL = # sectors left on the track
	cmp	al,bl			; more than requested?
	jbe	rw2			; no
	mov	al,bl			; yes, so use the # requested
rw2:	inc	ah			; AH = sector ID
	xchg	ch,cl			; CH = cylinder bits 0-7
	ror	cl,1
	ror	cl,1			; CL bits 6-7 = cylinder bits 8-9
	or	cl,ah			; CL bits 0-5 = sector ID
	mov	dl,cs:[rw_drive]	; DL = BIOS drive #
	mov	ah,bh			; AH = BIOS cmd, AL = # sectors
;
; Reduce AL to the # sectors that precede the next 64K boundary, unless
; this is a PC AT hard disk (DL bit 7 set and rw_pio is 80h).
;
	test	dl,cs:[rw_pio]		; hard disk without DMA?
	jnz	rw2c			; yes, so no boundary to worry about
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
rw2c:	push	ax
	mov	bx,bp			; ES:BX -> buffer
	call	bios_rw			; AX and carry are from the ROM
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
	call	bios_rw			; AX and carry are from the ROM
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
	stc

rw9:	pop	es
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	readwrite_sectors

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Call BIOS to read/write sectors, retrying once on a media change
;
; On a PC AT, if a drive's change line is active, the BIOS resets the line
; and fails the request with FDCERR_CHANGED, so the request must be retried.
; We retry only once, because the line stays active if the drive is empty.
;
; Inputs:
;	Same as INT_FDC
;
; Outputs:
;	Same as INT_FDC
;
; Modifies:
;	AX
;
DEFPROC	bios_rw
	push	di
	mov	di,ax			; DI = BIOS cmd and # sectors
	int	INT_FDC			; AX and carry are from the ROM
	jnc	if9
	cmp	ah,FDCERR_CHANGED	; media changed?
	stc
	jne	if9			; no
	xchg	ax,di
	int	INT_FDC			; yes, so try again
if9:	pop	di
	ret
ENDPROC	bios_rw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fdc_rw (far entry for the HDC driver)
;
; Performs a read or write request for another block driver (ie, the HDC),
; whose BPB describes the volume's geometry.
;
; Inputs:
;	AL = BIOS drive #
;	ES:DI -> DDPRW (DDC_READ or DDC_WRITE)
;
; Outputs:
;	DDPRW updated appropriately
;
; Modifies:
;	AX, BX, CX, DX, BP, SI, DS
;
DEFPROC	fdc_rw,far
	mov	cs:[rw_drive],al
	push	cs
	pop	ds
	ASSUME	DS:CODE
	cmp	es:[di].DDP_CMD,DDC_READ
	jne	fw1
	call	ddfdc_read
	ret
fw1:	call	ddfdc_write
	ret
ENDPROC	fdc_rw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fdc_mbr (far entry for the HDC driver)
;
; Reads or writes a hard disk's MBR (cylinder 0, head 0, sector 1) using our
; buffer, or with no command, simply returns the buffer (eg, for the HDC
; driver to build an MBR in before writing it).
;
; Inputs:
;	AL = BIOS drive #
;	AH = FDC_READ, FDC_WRITE, or 0 (just return the buffer)
;
; Outputs:
;	Carry clear if successful (AX = driver error code otherwise)
;	ES:BP -> our buffer
;
; Modifies:
;	AX, BX, CX, DX, BP, ES
;
DEFPROC	fdc_mbr,far
	ASSUME	DS:NOTHING
	mov	cs:[ddbuf_lba],-1	; ddbuf won't hold a volume sector
	les	bp,cs:[ddbuf_ptr]	; ES:BP -> ddbuf
	test	ah,ah			; any transfer?
	jz	fm9			; no
	mov	bx,bp			; ES:BX -> ddbuf
	mov	dl,al			; DL = drive #
	mov	al,1			; AL = 1 sector
	mov	cx,1			; CH = cylinder 0, CL = sector 1
	mov	dh,0			; DH = head 0
	call	bios_rw			; AX and carry are from the ROM
	jc	fm8
fm9:	ret
fm8:	mov	al,ah
	mov	ah,0			; AX = driver error code
	stc
	ret
ENDPROC	fdc_mbr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fdc_rdbuf (far entry for the HDC driver)
;
; Reads a sector into our buffer for another block driver (eg, to read the
; boot sector of a volume while building its BPB).
;
; Inputs:
;	AL = BIOS drive #
;	DX = LBA
;	DS:SI -> BPB
;
; Outputs:
;	Carry clear if successful (AX = driver error code otherwise)
;	ES:BP -> our buffer
;
; Modifies:
;	AX, BX, BP, ES
;
DEFPROC	fdc_rdbuf,far
	ASSUME	DS:NOTHING
	mov	cs:[rw_drive],al
	call	read_buffer
	les	bp,cs:[ddbuf_ptr]
	ret
ENDPROC	fdc_rdbuf

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
DEFPROC	ddfdc_init,far
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,[EQUIP_FLAG]
;
; We're not keeping any of this code, but we are reserving 512 bytes
; for an internal sector buffer (ddbuf).
;
	mov	es:[bx].DDPI_END.OFF,offset ddfdc_init + 512
	mov	cs:[0].DDH_REQUEST,offset DEV:ddfdc_req
	mov	[ddbuf_ptr].SEG,cs
;
; PC AT-class machines (model byte FCh at F000:FFFEh) have a fixed disk
; BIOS that uses programmed I/O, so hard disk transfers aren't subject to
; 64K DMA boundaries (see readwrite_sectors).
;
	mov	dx,0F000h
	mov	ds,dx
	ASSUME	DS:NOTHING
	cmp	byte ptr ds:[0FFFEh],0FCh	; PC AT model byte?
	jne	ddin1				; no
	mov	cs:[rw_pio],80h
ddin1:
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
	ret
ENDPROC	ddfdc_init

CODE	ends

DATA	segment para public 'DATA'

ddfdc_end	db	16 dup(0)

DATA	ends

	end
