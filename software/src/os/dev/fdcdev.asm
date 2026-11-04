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
	include	cpu.inc

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
	DEFBYTE	rw_pm,0			; # sectors in ddbuf if pm_rw is used
	DEFBYTE	ddbuf_drv,-1
	DEFWORD	ddbuf_lba,-1
	DEFPTR	ddbuf_ptr,<offset pm_rw>; (see ddfdc_init)

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
	mov	bl,es:[di].DDP_CMD
	cmp	bl,CMDTBL_SIZE
	jb	ddq1
	mov	bl,0
ddq1:	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	al,es:[di].DDP_UNIT
	mov	[rw_drive],al	; (diskette units are BIOS drive #s)
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
	push	ds
	pop	es
	mov	di,si		; ES:DI -> BPB
	lds	si,cs:[ddbuf_ptr]
	mov	ds:[ddbuf_drv],al	; (DS = CS)
	mov	ds:[ddbuf_lba],dx	; (DX is still LBA 0)
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
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	[ddbuf_lba],-1
	pop	ds
	ASSUME	DS:NOTHING
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
; ddfdc_read
;
; DOS reads partial sectors through its own buffers (see file_request), so a
; read request is always for whole sectors, with an offset of zero; on an
; error, the packet is unchanged, so RETRY simply reissues it.
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
	ASSERT	Z,<cmp es:[di].DDPRW_OFFSET,0>
	lds	si,es:[di].DDPRW_BPB
	ASSUME	DS:NOTHING	; DS:SI -> BPB
	mov	bl,byte ptr es:[di].DDPRW_LENGTH.HIB
	shr	bl,1		; BL = # sectors
	mov	bh,FDC_READ
	mov	dx,es:[di].DDPRW_LBA
	push	es
	les	bp,es:[di].DDPRW_ADDR
	call	readwrite_sectors
	pop	es
	jc	dcw8
	mov	es:[di].DDPRW_LENGTH,0
	jmp	short dcw8
ENDPROC	ddfdc_read

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
; format_track).  Since diskettes have no partition table, IOCTL_GETPART
; stores only the drive's type, as one byte (1 = 360K, 2 = 1.2M, 3 = 720K,
; or 4 = 1.44M), or nothing if the BIOS can't tell (eg, on a PC or XT), so
; FORMAT can tell a diskette from a hard disk, and choose a diskette size.
; Errors are returned to the caller (see dev_request).
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
	cmp	al,IOCTL_GETPART
	je	dio3
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
	jmp	short dio7
dio3:	push	di
	push	es
	lds	si,es:[di].DDPRW_BPB	; DS:SI -> BPB
	mov	dl,[si].BPB_DRIVE	; DL = drive #
	mov	ah,HDC_GETPARMS
	int	INT_FDC			; BL = drive type (AT only)
	pop	es
	pop	di
	jnc	dio4
	mov	bl,0			; no drive type
dio4:	test	bl,bl			; (carry clear)
	jz	dio8			; no drive type, so store nothing
	lds	si,es:[di].DDPRW_ADDR
	mov	[si],bl			; store the drive type
	mov	es:[di].DDP_CONTEXT,1	; (one byte)
	jmp	short dio8
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
ft2:	les	di,cs:[ddbuf_ptr]	; ES:DI -> ddbuf
	mov	es:[ddbuf_lba],-1
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
; its format gap length.  The boot code moved the DPT to RAM (DPT_ACTIVE, at
; 40:122h; see boot.asm), so it can be changed, and since BIOS is also a
; selector (SEL_BIOS), this works in either mode.
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
	mov	bx,BIOS
	mov	ds,bx
	ASSUME	DS:BIOS
	mov	[DPT_ACTIVE].DP_SPT,al
	mov	ah,50h			; gap length for 8 or 9 sectors
	cmp	al,9
	jbe	sd1
	mov	ah,54h			; gap length for 15 sectors
sd1:	mov	[DPT_ACTIVE].DP_GAP3,ah
	pop	bx
	pop	ds
	ASSUME	DS:NOTHING
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
	jc	rb8		; TODO: can errors damage the buffer contents?
	mov	al,[si].BPB_DRIVE
	mov	es:[ddbuf_drv],al
	mov	es:[ddbuf_lba],dx
rb8:	pop	es
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
	jc	wb8
	mov	al,[si].BPB_DRIVE
	mov	es:[ddbuf_drv],al
	mov	es:[ddbuf_lba],dx
	pop	es
	ret
wb8:	mov	es:[ddbuf_lba],-1	; ddbuf no longer matches the disk
	pop	es
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
; never cross a boundary it cares about (see rw_pio).  In protected mode,
; pm_dma supplies the buffer's address, and a buffer that the diskette BIOS
; can't reach (see pm_rw) goes through our own buffer, which holds a track
; (see ddfdc_init), since a BIOS call per sector could cost a disk revolution
; per sector.
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
; NOTE: We advance the transfer address by adding to BP, not ES, so that ES
; can be a selector; requests never extend beyond offset FFFFh, since DOS
; advances only the offsets of its buffers, too (and the program loader reads
; at most FF00h bytes at offset 100h).
;
DEFPROC	readwrite_sectors
	ASSUME	DS:NOTHING
	push	bx
	push	cx
	push	dx
	push	bp
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
	cmp	cs:[rw_pm],0		; protected mode?
	je	rw2d			; no
	call	pm_dma			; yes, so BX comes from ES's base
	jne	rw3a			; the BIOS can't reach ES:BP
rw2d:	mov	cl,al			; CL = # sectors
	mov	al,0			; AL = # sectors before the boundary
rw2a:	add	bx,512
	jc	rw2b
	inc	ax
	cmp	al,cl
	jb	rw2a
rw2b:	pop	cx
	test	al,al			; any sectors before the boundary?
	jnz	rw2c			; yes
	inc	ax			; no, so AL = 1 sector
	jmp	short rw4
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
	mov	cl,9			; (512-byte sectors)
	shl	ax,cl			; AX = # bytes in request
	add	bp,ax			; advance transfer address in BP
	jmp	rw1
;
; Either the BIOS can't reach the caller's buffer, so we transfer as much of
; the track as our own buffer holds (see pm_dma), or the next sector crosses a
; 64K boundary, so we transfer just that sector (AL = 1), through our own
; buffer (which no longer matches ddbuf_lba afterward).
;
rw3a:	pop	cx			; CX = cylinder and sector ID again
rw4:	push	ax			; save BIOS cmd and # sectors
	push	si
	push	di
	push	ds
	push	es
	push	cx
	mov	ch,al
	mov	cl,0			; CX = # words in AL sectors
	push	es
	pop	ds
	mov	si,bp			; DS:SI -> caller's buffer
	les	di,cs:[ddbuf_ptr]	; ES:DI -> our own buffer
	mov	es:[ddbuf_lba],-1	; which won't match ddbuf_lba
	cmp	ah,FDC_READ		; reading?
	je	rw4a			; yes
	rep	movsw			; no, so copy the sectors to our buffer
rw4a:	pop	cx			; CX = cylinder and sector ID again
	mov	bx,cs:[ddbuf_ptr].OFF	; ES:BX -> our own buffer
	call	bios_rw			; AX and carry are from the ROM
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	bx			; BH = BIOS cmd, BL = # sectors
	jc	rw4c
	cmp	bh,FDC_READ		; reading?
	jne	rw4c			; no (and carry is clear)
	push	si
	push	di
	push	ds
	push	cx
	lds	si,cs:[ddbuf_ptr]	; DS:SI -> our own buffer
	mov	di,bp			; ES:DI -> caller's buffer
	mov	ch,bl
	mov	cl,0			; CX = # words in BL sectors
	rep	movsw			; copy the sectors to the caller
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

rw9:	pop	bp
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
; In protected mode, requests go to pm_rw first (see int_rw).
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
	cmp	cs:[rw_pm],0		; protected mode?
	jne	pm_rw			; yes
	DEFLBL	int_rw,near
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
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	[rw_drive],al
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
	les	bp,cs:[ddbuf_ptr]	; ES:BP -> ddbuf
	mov	es:[ddbuf_lba],-1	; which won't hold a volume sector
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
	les	bp,cs:[ddbuf_ptr]	; ES:BP -> ddbuf (read_buffer keeps it)
	mov	es:[rw_drive],al
	call	read_buffer
	ret
ENDPROC	fdc_rdbuf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_rw
;
; INT 13h work-arounds for protected mode, where ES is a selector:
;
; 1) The diskette BIOS turns ES:BX into a DMA address (ES * 16 + BX), so
;    ES:BX becomes BIOS (SEL_BIOS, whose base is 400h) and the buffer's
;    offset from 400h, which must be less than 64K (see pm_dma).
; 2) The AT fixed disk BIOS normalizes ES:BX by adding BX / 16 to ES, which
;    makes ES an invalid selector unless BX is less than 16, so ES:BX becomes
;    a selector of the buffer's own (CPU_MAP) and zero.
;
; In real mode, this code is part of ddbuf (see ddfdc_init).
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
DEFPROC	pm_rw
	push	bx
	push	si
	push	di
	push	es
	push	cx
	push	dx
	push	ax
	mov	di,dx			; DI = drive # (in the low byte)
	call	pm_addr			; DX:CX = address of ES:BX
	test	di,80h			; a hard disk?
	jnz	pr2			; yes
	sub	cx,BIOS_DATA
	sbb	dx,0			; DX:CX = buffer's offset from 400h
	mov	bx,BIOS
	jz	pr3			; it's within 64K of 400h
	mov	ah,DDERR_DMA64K		; (BIOS errors are driver errors)
pr1:	pop	dx			; (discard the caller's AX)
	pop	dx
	pop	cx
	pop	es
	stc
	jmp	short pr9
pr2:	sub	si,si
	mov	di,0FFFFh		; SI:DI = length (any transfer fits)
	mov	ax,CPU_MAP SHL 8	; (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = selector
	xchg	bx,ax			; BX = selector
	mov	ah,DDERR_GENFAIL
	jc	pr1			; no selector
	sub	cx,cx			; CX = offset (zero)
pr3:	mov	es,bx
	mov	bx,cx			; ES:BX -> buffer
	pop	ax
	pop	dx
	pop	cx			; AX, CX, and DX for INT_FDC again
	mov	si,cx
	mov	di,dx			; (SI and DI keep CX and DX)
	push	es
	call	int_rw			; AX and carry are from the ROM
	pop	bx			; BX = selector (or BIOS)
	pop	es			; (ES can't hold a freed selector)
	pushf				; (TEST would clear the ROM's carry)
	test	di,80h			; a hard disk?
	jz	pr8			; no
	push	ax
	mov	ah,CPU_UNMAP
	sub	cx,cx			; CX = 0 (one selector)
	call	far ptr DDINT_CPU
	pop	ax
pr8:	popf
	mov	cx,si
	mov	dx,di			; CX and DX again
pr9:	pop	di
	pop	si
	pop	bx
	ret
ENDPROC	pm_rw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_dma
;
; Gets the address of ES:BP for readwrite_sectors' DMA boundary check, which
; in protected mode can't be computed from ES.
;
; Inputs:
;	AL = # sectors
;
; Outputs:
;	BX = low 16 bits of ES:BP's address
;	ZF set if the diskette BIOS can reach it (see pm_rw); otherwise,
;	ZF clear, AL = # sectors that fit in ddbuf
;
DEFPROC	pm_dma
	push	ax
	push	cx
	push	dx
	mov	bx,bp
	call	pm_addr			; DX:CX = address of ES:BP
	mov	bx,cx
	sub	cx,BIOS_DATA
	sbb	dx,0			; ZF set if it's within 64K of 400h
	pop	dx
	pop	cx
	pop	ax
	jz	pd9
	cmp	al,cs:[rw_pm]		; do they all fit in our buffer?
	jbe	pd8			; yes
	mov	al,cs:[rw_pm]		; no, so AL = as many as do
pd8:	test	al,al			; (AL is non-zero, so ZF is clear)
pd9:	ret
ENDPROC	pm_dma

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pm_addr
;
; Inputs:
;	ES:BX -> buffer
;
; Outputs:
;	DX:CX = address of ES:BX
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	pm_addr
	push	bx
	mov	bx,es
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	far ptr DDINT_CPU	; DX:CX = base of ES
	pop	bx
	add	cx,bx
	adc	dx,0
	ret
ENDPROC	pm_addr

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
;
; PC AT-class machines (model byte FCh at F000:FFFEh) have a fixed disk
; BIOS that uses programmed I/O, so hard disk transfers aren't subject to
; 64K DMA boundaries (see readwrite_sectors).
;
	mov	ax,0F000h
	mov	ds,ax
	ASSUME	DS:NOTHING
	cmp	byte ptr ds:[0FFFEh],0FCh	; PC AT model byte?
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,[EQUIP_FLAG]
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	jne	ddin0				; not a PC AT
	mov	[rw_pio],80h
;
; We're not keeping any of this code, but we are reserving 512 bytes
; for an internal sector buffer (ddbuf), which begins at pm_rw (and
; overlays the code that only protected mode needs) unless we're in
; protected mode (AH is unchanged, ie, zero, if there's no CPU$).
;
; In protected mode, ddbuf begins here instead, and it holds a track of the
; drive with the most sectors per track, since most buffers go through it (see
; readwrite_sectors); a drive that isn't there has no sectors, so it always
; holds at least one.  The drivers are loaded well below 64K, so the diskette
; BIOS can reach all of it (see pm_rw).
;
ddin0:	push	ax
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; AH = CPUF_* flags
	mov	si,1			; SI = # sectors in ddbuf
	test	ah,CPUF_PM		; protected mode?
	jz	ddin4			; no
	mov	[ddbuf_ptr].OFF,offset ddfdc_init
	push	bx
	push	es
	mov	dx,1			; DL = BIOS drive #
ddin1:	push	dx
	mov	ah,HDC_GETPARMS
	int	INT_FDC			; CL bits 0-5 = sectors per track
	pop	dx
	jc	ddin2
	and	cx,3Fh
	cmp	si,cx			; more than any other drive so far?
	jae	ddin2			; no
	mov	si,cx
ddin2:	dec	dx
	jns	ddin1
	pop	es
	pop	bx
	cmp	si,FDC_BUFSECS		; more than devinit makes room for?
	jbe	ddin3			; no
	mov	si,FDC_BUFSECS
ddin3:	mov	ax,si
	mov	[rw_pm],al		; keep pm_rw (etc)
ddin4:	pop	ax
	mov	cx,si
	xchg	ch,cl
	shl	cx,1			; CX = length of ddbuf
	add	cx,[ddbuf_ptr].OFF
	mov	es:[bx].DDPI_END.OFF,cx
	mov	ds:[0].DDH_REQUEST,offset DEV:ddfdc_req
	mov	[ddbuf_ptr].SEG,ds	; (our data segment)
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
