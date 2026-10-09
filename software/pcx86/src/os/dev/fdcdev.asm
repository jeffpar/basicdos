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
; which calls fdc_rw and fdc_rdbuf (see FDCX in devapi.inc), since INT 13h
; works the same way for both: the code uses the geometry in the BPB, along
; with BPB_HIDDENSECS as a hard disk volume's first sector (diskettes have
; no hidden sectors), and the caller provides the BIOS drive # (rw_drive).
; Requests are never concurrent (the kernel locks the session while it uses
; a driver), so one buffer suffices.
;
	BIOSEQU equ 1
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	FDC
FDC 	DDH	<offset DEV:ddfdc_end+16,,DDATTR_BLOCK,offset ddfdc_init,-1,2020202024434446h>
	dw	offset DEV:fdc_rw, offset DEV:fdc_rdbuf	; FDCX (see devapi.inc)

	DEFLBL	CMDTBL,word
	dw	ddfdc_none,  ddfdc_mediachk, ddfdc_buildbpb, ddfdc_none	; 0-3
	dw	ddfdc_read,  ddfdc_none,     ddfdc_none,     ddfdc_none	; 4-7
	dw	ddfdc_write, ddfdc_none,     ddfdc_none,     ddfdc_none	; 8-11
	dw	ddfdc_none,  ddfdc_none,     ddfdc_none,     ddfdc_none	; 12-15
	dw	ddfdc_none,  ddfdc_none,     ddfdc_none,     ddfdc_none	; 16-19
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFBYTE	rw_drive,0		; BIOS drive # for readwrite_sectors
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
mc1:	pop	[si].BPB_TIMESTAMP.OFF
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
	jnc	bb1
	jmp	bb8
;
; Copy the BPB from the boot sector in our buffer to the BPB provided.
;
bb1:	push	ds
	pop	es
	mov	di,si
	push	di
	mov	bl,[si].BPB_DRIVE
	lds	si,[ddbuf_ptr]	; BL = drive #
	add	si,BOOT_BPB	; DS:SI -> our own buffer
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
	mov	[ddbuf_lba],ax	; (zero ddbuf_lba while AX is zero)
	mov	ax,cs
	stosw			; update BPB_DEVICE.SEG
	pop	di
	mov	[ddbuf_drv],bl
;
; Initialize the rest of the BPB extension data now
;
	mov	es:[di].BPB_DRIVE,bl
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

	mov	es:[di].DDPRW_LENGTH,0
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

	mov	es:[di].DDPRW_LENGTH,0
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
; any remaining sectors on the track.
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
	stc

rw9:	pop	es
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	readwrite_sectors

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
