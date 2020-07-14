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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	jnz	mc1		; yes, use defaut
	cmp	dx,38		; more than 2 seconds of ticks?
	jae	mc1		; yes, use default
	inc	ax		; change from UNKNOWN to UNCHANGED
mc1:	pop	ds:[si].BPB_TIMESTAMP.OFF
	pop	ds:[si].BPB_TIMESTAMP.SEG
	mov	es:[di].DDP_CONTEXT,ax
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddfdc_mediachk

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
; geometry info that get_chs requires; that's what we deserve when we use
; a single parameter block to describe everything from volume geometry
; to media geometry to drive geometry.
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
	add	si,BPB_OFFSET	; DS:SI -> our own buffer
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
	mov	es:[di].BPB_UNIT,bl
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
	shl	ax,cl		; use CLOSLOG2 to calculate CLUSBYTES
	mov	es:[di].BPB_CLUSBYTES,ax
	clc

bb8:	pop	es
	pop	di
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	bb9
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
bb9:	ret
ENDPROC	ddfdc_buildbpb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

	call	read_buffer	; read DDPRW_LBA into ddbuf
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

dcr6:	call	read_buffer	; read DDPRW_LBA into ddbuf
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
; Call BIOS to read/write sectors
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
DEFPROC	readwrite_sectors
	ASSUME	DS:NOTHING
	push	bx
	push	cx
	push	dx

	call	get_chs		; convert LBA in DX to CHS in CX,DX
	xchg	ax,bx		; AH = FDC cmd, AL = # sectors
	mov	bx,bp
	int	INT_FDC		; AX and carry are whatever the ROM returns
	jnc	rw9
;
; Map BIOS error code (in AH) to driver error code (in AX)
;
	cmp	ah,FDCERR_WP
	jne	rw1
	mov	al,DDERR_WP
rw1:	cmp	ah,FDCERR_NOSECTOR
	jne	rw2
	mov	al,DDERR_NOSECTOR
rw2:	cmp	ah,FDCERR_CRC
	jne	rw3
	mov	al,DDERR_CRC
rw3:	cmp	ah,FDCERR_SEEK
	jne	rw4
	mov	al,DDERR_SEEK
rw4:	cmp	ah,FDCERR_NOTREADY
	jne	rw7
	mov	al,DDERR_NOTREADY
	jmp	short rw8
rw7:	mov	al,DDERR_GENFAIL
rw8:	cbw
	stc

rw9:	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	readwrite_sectors

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Read 1 sector into our internal buffer
;
; Inputs:
;	DS:SI -> BPB (drive to read is BPB_DRIVE)
;	ES:DI -> DDPRW (sector to read is DDPRW_LBA)
;
; Outputs:
;	Carry clear if successful
;
; Modifies:
;	AX, BX, DX, BP
;
DEFPROC	read_buffer
	mov	dx,es:[di].DDPRW_LBA
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
	jc	rb9
	mov	al,[si].BPB_DRIVE
	mov	[ddbuf_drv],al
	mov	[ddbuf_lba],dx
rb9:	ret
ENDPROC	read_buffer

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
