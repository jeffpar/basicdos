;
; BASIC-DOS Floppy Drive Controller Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	FDC
FDC 	DDH	<offset DEV:ddfdc_end+16,,DDATTR_BLOCK,offset ddfdc_init,-1,2020202024434446h>

	DEFLBL	CMDTBL,word
	dw	ddfdc_none,  ddfdc_mediachk, ddfdc_buildbpb, ddfdc_none	; 0-3
	dw	ddfdc_read,  ddfdc_none,     ddfdc_none,     ddfdc_none	; 4-7
	dw	ddfdc_write, ddfdc_none,     ddfdc_none,     ddfdc_none	; 8-11
	dw	ddfdc_none,  ddfdc_none,     ddfdc_none,     ddfdc_none	; 12-15
	dw	ddfdc_none,  ddfdc_none,     ddfdc_none,     ddfdc_none	; 16-19
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

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
	mov	ax,MC_UNKNOWN	; default to UNKNOWN
	push	cx
	push	dx
	sub	dx,ds:[si].BPB_TIMESTAMP.OFF
	sbb	cx,ds:[si].BPB_TIMESTAMP.SEG
	jb	mc1		; underflow, use default
	test	cx,cx		; large difference?
	jnz	mc1		; yes, use default
	cmp	dx,38		; more than 2 seconds of ticks?
	jae	mc1		; yes, use default
	inc	ax		; change from UNKNOWN to UNCHANGED
mc1:	pop	ds:[si].BPB_TIMESTAMP.OFF
	pop	ds:[si].BPB_TIMESTAMP.SEG
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
; If this is an uninitialized BPB, then it won't have the necessary
; geometry info that get_chs requires; that's what happens when we use
; a single parameter block to describe everything from volume geometry
; to media geometry to drive geometry.  Oh well.
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
;	AX, BX, CX, DX, SI, DS
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddfdc_write
	ret
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Get CHS from LBA in AX, using BPB at SI
;
; Inputs:
;	DX = LBA
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
	ASSUME	DS:NOTHING
	xchg	ax,dx
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	jc	rb9		; TODO: can errors "damage" the buffer contents?
	mov	al,[si].BPB_DRIVE
	mov	[ddbuf_drv],al
	mov	[ddbuf_lba],dx
rb9:	ret
ENDPROC	read_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Call BIOS to read/write sectors
;
; There are several annoying problems that the IBM PC diskette system suffers
; from, which you'll be happy to know this function (finally) addresses:
;
;    1)	Multi-sector requests that cross track boundaries
;    2)	Requests that cross 64K memory boundaries
;
; We break every request into one or more single-track requests, and within
; each single-track request, we read all sectors that precede a 64K boundary,
; then we read the next sector, if any, into an internal buffer, and then we
; finish reading any remaining sectors on the track.
;
; Inputs:
;	BH = FDC cmd
;	BL = # sectors
;	DX = LBA
;	DS:SI -> BPB
;	ES:BP -> buffer
;
; Outputs:
;	If carry clear, success (AX is whatever the BIOS returned)
;	If carry set, AX is a driver error code (based on the BIOS error code)
;
; Modifies:
;	AX
;
; Limitations:
;	The entire transfer must occur within ES:BP to ES:FFFFh.
;
DEFPROC	readwrite_sectors
	ASSUME	DS:NOTHING
	push	bx
	push	cx

rw0:	push	dx		; save LBA
	call	get_chs		; convert LBA in DX to CHS in CX,DX
	push	bx
	mov	al,byte ptr [si].BPB_TRACKSECS
	sub	al,cl
	inc	ax		; AL = max # sectors available this track
	cmp	al,bl		; AL < BL?
	jb	rw1		; yes, so use AL as # sectors
	mov	al,bl
;
; Calculate how many sectors are safe from crossing a 64K boundary.
;
rw1:	cbw			; AH = new (safe for 64K) sector count
	push	cx
	push	dx
	mov	dx,es
	mov	cl,4
	shl	dx,cl
	add	dx,bp
rw1a:	add	dx,[si].BPB_SECBYTES
	jc	rw1b
	inc	ah
	dec	al
	jnz	rw1a
rw1b:	mov	al,ah
	test	al,al		; are any safe?
	pop	dx
	pop	cx
	jnz	rw3		; yes
;
; No, so check the command.  For reads, read the next sector into our
; internal buffer, copy it out, and proceed with the next sector(s).  For
; writes, the process is obviously reversed.
;
	cmp	bh,FDC_READ
	jne	rw2
	push	es
	push	bx
	mov	ah,bh		; AH = FDC cmd
	mov	al,1		; AL = 1 sector
	les	bx,[ddbuf_ptr]	; ES:BX -> our own buffer
	int	INT_FDC		; AX and carry are whatever the ROM returns
	pop	bx
	pop	es
	jc	rw3a
	push	si
	push	di
	push	ds
	mov	cx,[si].BPB_SECBYTES
	lds	si,[ddbuf_ptr]	; DS:SI -> our own buffer
	mov	di,bp		; ES:DI -> caller's buffer
	shr	cx,1
	rep	movsw
	pop	ds
	pop	di
	pop	si
	dec	cx
	mov	[ddbuf_lba],cx	; store -1 in ddbuf_lba to invalidate it
	inc	cx
	inc	cx		; CX = 1 sector read
	jmp	short rw3a

rw2:	push	es
	push	bx
	push	si
	push	di
	push	ds
	mov	cx,[si].BPB_SECBYTES
	push	es
	pop	ds
	mov	si,bp		; DS:SI -> caller's buffer
	les	di,[ddbuf_ptr]	; ES:DI -> our own buffer
	shr	cx,1
	rep	movsw
	pop	ds
	pop	di
	pop	si
	mov	ah,bh		; AH = FDC cmd
	mov	al,1		; AL = 1 sector
	mov	bx,[ddbuf_ptr].OFF
	int	INT_FDC		; AX and carry are whatever the ROM returns
	pop	bx
	pop	es
	jc	rw3a
	mov	cx,-1
	mov	[ddbuf_lba],cx	; store -1 in ddbuf_lba to invalidate it
	neg	cx		; CX = 1 sector written
	jmp	short rw3a

rw3:	cbw
	push	ax		; AX = # sectors this iteration
	mov	ah,bh		; AH = FDC cmd
	mov	bx,bp		; ES:BX -> buffer
	int	INT_FDC		; AX and carry are whatever the ROM returns
	pop	cx		; CX = # sectors this iteration
rw3a:	pop	bx		; BL = total # sectors
	pop	dx		; DX = LBA again
	jc	rw8
	sub	bl,cl		; any sectors remaining?
	ASSERT	NC
	jbe	rw9		; no
	add	dx,cx		; advance LBA in DX
	xchg	ax,cx
	mov	cl,9		; TODO: Should we add BPB_SECLOG2 to the BPB?
	shl	ax,cl		; AX = # bytes in request
	add	bp,ax		; advance transfer address in BP
	jc	rw8e		; BP should never overflow, but just in case...
	jmp	rw0
;
; Map BIOS error code (in AH) to driver error code (in AX)
;
rw8:	cmp	ah,FDCERR_WP
	jne	rw8a
	mov	al,DDERR_WP
rw8a:	cmp	ah,FDCERR_NOSECTOR
	jne	rw8b
	mov	al,DDERR_NOSECTOR
rw8b:	cmp	ah,FDCERR_CRC
	jne	rw8c
	mov	al,DDERR_CRC
rw8c:	cmp	ah,FDCERR_SEEK
	jne	rw8d
	mov	al,DDERR_SEEK
rw8d:	cmp	ah,FDCERR_NOTREADY
	jne	rw8e
	mov	al,DDERR_NOTREADY
	jmp	short rw8f
rw8e:	mov	al,DDERR_GENFAIL
rw8f:	cbw
	stc

rw9:	pop	cx
	pop	bx
	ret
ENDPROC	readwrite_sectors

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
