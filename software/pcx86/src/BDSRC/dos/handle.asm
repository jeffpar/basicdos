;
; BASIC-DOS Handle Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<bpb_table,sfb_table>,dword
	EXTERNS	<psp_active>,word
	EXTERNS	<cur_drv,file_name>,byte
	EXTERNS	<VALID_CHARS>,byte
	EXTERNS	<VALID_COUNT>,abs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_open (REG_AH = 3Dh)
;
; Inputs:
;	REG_AL = mode (see MODE_*)
;	REG_DS:REG_DX -> name of device/file
;
; Outputs:
;	On success, REG_AX = PFH (or SFH if no valid PSP), carry clear
;	On failure, REG_AX = error, carry set
;
DEFPROC	hdl_open,DOS
	call	get_pft_free		; DI = free handle entry
	jc	ho9
	push	di			; save free handle entry
	mov	bl,[bp].REG_AL		; BL = mode
	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS		; DS:SI = name of device/file
	ASSUME	DS:NOTHING
	call	sfb_open
	pop	di			; restore handle entry
	jc	ho9
	call	set_pft_free		; update free handle entry
ho9:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
	ret
ENDPROC	hdl_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_write (REG_AH = 40h)
;
; Inputs:
;	REG_BX = handle
;	REG_CX = byte count
;	REG_DS:REG_DX -> data to write
;
; Outputs:
;	On success, REG_AX = bytes written, carry clear
;	On failure, REG_AX = error, carry set
;
DEFPROC	hdl_write,DOS
	call	get_sfb
	ASSUME	ES:NOTHING
	jc	hw9
	mov	cx,[bp].REG_CX		; CX = byte count
	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS		; DS:SI = data to write
	ASSUME	DS:NOTHING
	call	sfb_write
hw9:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
	ret
ENDPROC	hdl_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_open
;
; Inputs:
;	BL = mode (see MODE_*)
;	DS:SI -> name of device/file
;
; Outputs:
;	On success, BX = SFB address, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	sfb_open,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
	push	si
	push	ds
	push	es
	call	chk_devname		; is it a device name?
	jnc	so1			; yes
	call	chk_filename		; is it a disk file name?
	jc	so9a			; no
	push	si			; yes
	push	ds			; save DIRENT at DS:SI
	int 3
	jmp	short so2

so1:	mov	ax,DDC_OPEN SHL 8	; ES:DI -> driver
	sub	dx,dx			; no initial context
	call	dev_request		; issue the DDC_OPEN request
	jc	so9			; failed
	sub	ax,ax			; no DIRENT for devices
	push	ax
	push	ax
;
; When looking for a matching existing SFB, all we require is that both
; the device driver and device context match.  For files, the context will
; be the cluster number; for devices, the context will be whatever
; dev_request returned in DX.
;
; Traditionally, checking used SFBs means those with non-zero HANDLES count;
; however, our SFBs are also used IFF their DRIVER seg is non-zero.
;
so2:	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	ax,es			; AX:DI is driver, DX is context
	mov	cl,bl			; save mode in CL
	mov	si,[sfb_table].off
	sub	bx,bx			; use BX to remember a free SFB
so3:	cmp	[si].SFB_DRIVER.off,di
	jne	so4			; check next SFB
	cmp	[si].SFB_DRIVER.seg,ax
	jne	so4			; check next SFB
	test	dx,dx			; any context?
	jz	so7			; no, so consider this SFB a match
	cmp	[si].SFB_CONTEXT,dx	; context match?
	je	so7			; match
so4:	test	bx,bx			; are we still looking for a free SFB?
	jnz	so5			; no
	cmp	[si].SFB_DRIVER.seg,bx	; is this one free?
	jne	so5			; no
	mov	bx,si			; yes, remember it
so5:	add	si,size SFB
	cmp	si,[sfb_table].seg
	jb	so3			; keep checking

	pop	ax
	pop	si
	test	bx,bx			; was there a free SFB?
	jz	so8			; no, tell the driver sorry

	test	si,si			; was a DIRENT provided?
	jz	so6			; no
	mov	ds,ax			; DS:SI -> DIRENT
	push	cx
	push	di
	push	es
	push	cs
	pop	es
	ASSUME	ES:DOS
	mov	di,bx			; ES:DI -> SFB (a superset of DIRENT)
	mov	cx,size DIRENT SHR 1
	rep	movsw			; copy the DIRENT into the SFB
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	pop	cx
	push	cs
	pop	ds
	ASSUME	DS:DOS

so6:	mov	[bx].SFB_DRIVER.off,di
	mov	[bx].SFB_DRIVER.seg,es
	mov	[bx].SFB_CONTEXT,dx
	mov	ch,0			; no process handles yet
	mov	word ptr [bx].SFB_MODE,cx
so9a:	jmp	short so9		; return new SFB

so7:	pop	ax			; throw away any DIRENT on the stack
	pop	ax
	mov	bx,si			; return matching SFB
	jmp	short so9

so8:	mov	ax,DDC_CLOSE SHL 8	; ES:DI -> driver, DX = context
	call	dev_request		; issue the DDC_CLOSE request
	mov	ax,ERR_MAXFILES
	stc				; return no SFB (and BX is zero)

so9:	pop	es
	pop	ds
	pop	si
	ASSUME	DS:NOTHING,ES:NOTHING
	ret
ENDPROC	sfb_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_write
;
; Inputs:
;	BX = SFB address
;	CX = byte count
;	DS:SI -> data to write
;
; Outputs:
;	On success, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	sfb_write,DOS
	ASSUME	DS:NOTHING
	mov	ax,DDC_WRITE SHL 8
	les	di,cs:[bx].SFB_DRIVER
	mov	dx,cs:[bx].SFB_CONTEXT
	call	dev_request		; issue the DDC_WRITE request
	ret
ENDPROC	sfb_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_devname
;
; Inputs:
;	DS:SI -> name
;
; Outputs:
;	On success, ES:DI -> device driver header (DDH)
;
; Modifies:
;	AX, CX, DI, ES
;
DEFPROC	chk_devname,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING
cd1:	cmp	di,-1			; end of device list?
	stc
	je	cd9			; yes, search failed
	mov	cx,8
	push	si
	push	di
	add	di,DDH_NAME
	repe	cmpsb			; compare DS:SI to ES:DI
	je	cd8			; match
;
; This could still be a match if DS:[SI-1] is an "end of device name" character
; (eg, ':', '.', ' ', or null) and ES:[DI-1] is a space.
;
	mov	al,[si-1]
	test	al,al
	jz	cd2
	cmp	al,':'
	je	cd2
	cmp	al,'.'
	je	cd2
	cmp	al,' '
	jne	cd8
cd2:	cmp	byte ptr es:[di-1],' '
cd8:	pop	di
	pop	si
	je	cd9			; jump if all our compares succeeded
	les	di,es:[di]		; otherwise, on to the next device
	jmp	cd1
cd9:	ret
ENDPROC	chk_devname

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_filename
;
; Inputs:
;	DS:SI -> name
;
; Outputs:
;	On success, DS:SI -> DIRENT, ES:DI -> driver header (DDH),
;		DX = context (1st cluster)
;	On failure, carry set
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	chk_filename,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
	push	cs
	pop	es
	ASSUME	ES:DOS
;
; See if the name begins with a drive letter.  If so, convert to a drive
; number and then skip over it; otherwise, use cur_drv as the drive number.
;
	push	bx
	sub	bx,bx			; BL is current file_name position
	mov	dh,8			; DH is current file_name limit
	mov	di,offset file_name
	mov	cx,11
	mov	al,' '
	rep	stosb			; initialize file_name
	cmp	byte ptr [si+1],':'	; check for drive letter
	mov	dl,[cur_drv]		; DL = drive number
	jne	cf1
	lodsb				; AL = drive letter
	sub	al,'A'
	jb	cf9			; error
	cmp	al,26
	cmc
	jb	cf9
	inc	si
	mov	dl,al			; DL = specified drive number
;
; Build file_name at ES:BX from the string at DS:SI, making sure that all
; characters exist within VALID_CHARS.
;
cf1:	lodsb				; get next char
	test	al,al			; terminating null?
	jz	cf4			; yes, end of name
	cmp	al,'.'			; period?
	jne	cf2			; no
	mov	bl,8			; BL -> file_name extension
	mov	dh,11			; DH -> file_name limit
	jmp	cf1
cf2:	cmp	al,'a'
	jb	cf3
	cmp	al,'z'
	ja	cf3
	sub	al,20h
cf3:	mov	cx,VALID_COUNT
	mov	di,offset VALID_CHARS
	repne	scasb
	stc
	jne	cf9			; invalid character
	cmp	bl,dh
	jae	cf1			; valid character but we're at limit
	mov	es:[file_name][bx],al	; store it
	inc	bx
	jmp	cf1
;
; file_name has been successfully filled in, so we're ready to search
; directory sectors for a matching name.  This requires getting a fresh
; BPB for the drive.
;
cf4:	push	cs
	pop	ds
	ASSUME	DS:DOS
	call	get_bpb			; DL = drive #
	jc	cf9
;
; ES:DI -> BPB.  Start a directory search for file_name.
;
	call	get_dirent
	ASSUME	DS:BIOS
	jc	cf9
;
; DS:SI -> DIRENT.  Get the cluster number as the context for the SFB.
;
	les	di,[FDC_DRIVER]		; ES:DI -> driver
	mov	dx,[si].DIR_CLN		; DX = CLN from DIRENT

cf9:	pop	bx
	ret
ENDPROC	chk_filename

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dev_request
;
; Inputs:
;	AH = device driver command (DDC)
;	AL = unit # (relevant for block devices only)
;	DX = device driver context, zero if none
;	ES:DI -> device driver header (DDH)
;
; Additionally, for read/write requests:
;	BX = LBA (block devices only)
;	CX = byte/sector count
;	DS:SI -> read/write data buffer
;
; Outputs:
;	If carry set, then AL contains error code
;	If carry clear, then DX contains the context, if any
;
; Modifies:
;	AX, DX
;
; Notes:
;	One of the main differences between our disk drivers and actual
;	MS-DOS disk drivers is that the latter puts the driver in charge of
;	allocating memory for BPBs, checking them, and rebuilding them as
;	needed; consequently, their request packets don't need a BPB pointer.
;
;	However, I don't feel that BPBs really "belong" to the drivers;
;	they are creations of DOS, describing how the DOS volume is laid out
;	on the media.  The only reason the driver even cares about BPBs is
;	to perform the necessary LBA-to-CHS calculations for the volume
;	currently in the drive.
;
DEFPROC	dev_request,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
	push	bx
	push	bp
	sub	sp,DDP_MAXSIZE
	mov	bp,sp			; packet created on stack

	mov	word ptr [bp].DDP_UNIT,ax; sets DDP_UNIT (AL) and DDP_CMD (AH)
	mov	[bp].DDP_STATUS,0
	mov	[bp].DDP_CONTEXT,dx

	cmp	ah,DDC_OPEN
	jne	dr2
	mov	word ptr [bp].DDP_LEN,size DDP
	mov	[bp].DDP_PARMS.off,si
	mov	[bp].DDP_PARMS.seg,ds
	jmp	short dr5

dr2:	mov	word ptr [bp].DDP_LEN,size DDPRW
	mov	[bp].DDPRW_ADDR.off,si
	mov	[bp].DDPRW_ADDR.seg,ds
	mov	[bp].DDPRW_COUNT,cx
	mov	[bp].DDPRW_SECTOR,bx

	mov	ah,size BPBEX		; AL still contains the unit #
	mul	ah
	add	ax,[bpb_table].off	; AX = BPB address
	mov	[bp].DDPRW_BPB.off,ax	; save it in the request packet
	mov	[bp].DDPRW_BPB.seg,cs

dr5:	mov	bx,bp
	push	es
	push	es:[di].DDH_STRATEGY
	push	es
	push	es:[di].DDH_INTERRUPT
	push	ss
	pop	es			; ES:BX -> packet
	call	dword ptr [bp-4]	; far call to DDH_STRATEGY
	call	dword ptr [bp-8]	; far call to DDH_INTERRUPT
	pop	ax
	pop	es			; ES restored
	add	sp,4
	mov	ax,[bp].DDP_STATUS
	mov	dx,[bp].DDP_CONTEXT
	add	sp,DDP_MAXSIZE
	test	ax,DDSTAT_ERROR
	jz	dr9
	stc				; AL contains device error code
dr9:	pop	bp
	pop	bx
	ret
ENDPROC	dev_request

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_bpb
;
; As part of getting the BPB for the specified drive, this function presumes
; that the request is due to an imminent I/O request; therefore, we verify
; that the BPB is "fresh", and if it isn't, we reload it and mark it "fresh".
;
; Inputs:
;	DL = drive #
;
; Outputs:
;	On success, DS:DI -> BPB, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, CX, DX, DI
;
DEFPROC	get_bpb,DOS
	mov	al,dl			; AL = drive #
	mov	ah,size BPBEX
	mul	ah			; AX = BPB offset
	mov	di,[bpb_table].off
	add	di,ax
	cmp	di,[bpb_table].seg
	cmc
	jc	gb9			; we don't have a BPB for that drive

	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	push	cx
	push	dx
	sub	dx,[di].BPB_TIMESTAMP.off
	sbb	cx,[di].BPB_TIMESTAMP.seg
	jb	gb1			; underflow unexpected, refresh the BPB
	test	cx,cx
	jnz	gb1			; large difference, refresh the BPB
	cmp	dx,38
	cmc
	jnc	gb8			; small difference, update tick count
;
; We need to reload the BPB, which means reading the boot sector;
; for now, we use the FAT_SECTOR buffer for that purpose.
;
gb1:	mov	al,[di].BPB_DRIVE	; AL = drive (unit) #
	sub	bx,bx			; BX = LBA (0)
	mov	cx,1			; CX = sector count (1)
	push	si
	push	ds
	mov	ds,bx
	ASSUME	DS:BIOS
	call	flush_buffers		; flush all buffers for drive
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	jc	gb7
;
; Copy the BPB from the boot sector in the buffer (at DS:SI) to our BPB
;
	push	di
	add	si,BPB_OFFSET
	mov	cx,size BPB SHR 1
	rep	movsw
	pop	di

gb7:	pop	ds
	ASSUME	DS:DOS
	pop	si
	jc	gb9
;
; Get a fresh timestamp, since it took some amount of time to read the disk
;
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	add	sp,4
	push	cx
	push	dx

gb8:	pop	[di].BPB_TIMESTAMP.off
	pop	[di].BPB_TIMESTAMP.seg

gb9:	ret
ENDPROC	get_bpb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_dirent
;
; Inputs:
;	ES:DI -> BPB
;	DS:file_name contains file name
;
; Outputs:
;	On success, DS:SI -> DIRENT, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, DX, SI, DS
;
DEFPROC	get_dirent,DOS
;
; Instead of blindly starting at LBAROOT, we'll start at whatever LBA
; directory sector we read last, if valid, and we'll stop when we 1) find
; a match, or 2) reach that same sector again (after looping around).
;
	push	bp
	sub	bx,bx
	mov	ds,bx
	ASSUME	DS:BIOS
	mov	si,offset DIR_BUFHDR
	mov	al,es:[di].BPB_DRIVE
	cmp	[si].BUF_DRV,al
	jne	gd1
	mov	bx,[si].BUF_LBA
	test	bx,bx
	jnz	gd2
gd1:	mov	bx,es:[di].BPB_LBAROOT
gd2:	mov	bp,bx			; BP = 1st LBA we'll check

gd4:	mov	cx,1
	call	read_buffer
	jc	gd9

	mov	dx,es:[di].BPB_SECBYTES
	add	dx,si			; DX -> end of sector data
gd5:	cmp	byte ptr [si],0
	je	gd6			; 0 indicates end of allocated entries
	mov	di,offset file_name
	mov	cl,11
	repe	cmpsb
	je	gd9
	add	si,cx
	add	si,size DIRENT - 11
	cmp	si,dx
	jb	gd5
;
; Advance to next directory sector
;
	mov	si,offset DIR_BUFHDR
	inc	bx
	cmp	bx,es:[di].BPB_LBADATA
	jb	gd7
gd6:	mov	bx,es:[di].BPB_LBAROOT
gd7:	cmp	bx,bp			; back to the 1st LBA again?
	jne	gd4			; not yet
	stc				; out of sectors, so no match

gd9:	lea	si,[si-11]		; rewind SI, in case it was a match
	pop	bp
	ret
ENDPROC	get_dirent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_sfb
;
; Inputs:
;	REG_BX = handle
;
; Outputs:
;	On success, BX -> SFB, carry clear
;	On failure, AX = ERR_BADHANDLE, carry set
;
; Modifies:
;	AX, BX, CX, ES
;
DEFPROC	get_sfb,DOS
	mov	es,[psp_active]
	ASSUME	ES:NOTHING
	mov	bx,[bp].REG_BX		; BX = handle
	cmp	bx,size PSP_PFT
	cmc
	jb	gs9
	mov	al,es:[PSP_PFT][bx]
	mov	cl,size SFB
	mul	cl
	add	ax,[sfb_table].off
	cmp	ax,[sfb_table].seg
	cmc
	jb	gs9
	xchg	bx,ax			; BX -> SFB
	ret
gs9:	mov	ax,ERR_BADHANDLE
	ret
ENDPROC	get_sfb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_pft_free
;
; Inputs:
;	None
;
; Outputs:
;	On success, ES:DI -> PFT, carry clear
;	On failure, AX = ERR_MAXFILES, carry set
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	get_pft_free,DOS
	mov	es,[psp_active]		; get the current PSP
	ASSUME	ES:NOTHING		; and if there IS a PSP
	mov	di,es			; then find a free handle entry
	test	di,0FFF0h
	jz	gj9			; no valid PSP yet
	mov	al,SFH_NONE		; AL = 0FFh (indicates unused entry)
	mov	cx,size PSP_PFT
	mov	di,offset PSP_PFT
	repne	scasb
	mov	ax,ERR_MAXFILES
	stc
	jne	gj9			; if no entry, return error w/carry set
	dec	di			; rewind to entry
	clc
gj9:	ret
ENDPROC	get_pft_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_pft_free
;
; This returns a PFT # (aka PFH or Process File Handle) if get_pft_free
; detected a valid PSP; otherwise, it returns the SFB # (aka SFH or System File
; Handle).
;
; Inputs:
;	BX -> SFB
;	ES:DI -> PFT
;
; Outputs:
;	FT updated, AX = PFH or SFH (see above), carry clear
;
; Modifies:
;	AX, BX, CX, DI
;
DEFPROC	set_pft_free,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	xchg	ax,bx			; AX = SFB address
	sub	ax,[sfb_table].off
	mov	cl,size SFB
	div	cl			; AL = SFB # (from SFB address)
	DEBUGEQ	<test ah,ah>		; assert that the remainder is zero
	test	di,0FFF0h		; did we find a free PFT entry?
	jz	sj9			; no
	stosb				; yes, store SFB # in the PFT entry
	sub	di,offset PSP_PFT + 1	; convert PFT entry into PFH
	xchg	ax,di			; AX = handle
sj9:	ret
ENDPROC	set_pft_free

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_buffer
;
; Inputs:
;	AL = unit #
;	BX = LBA
;	CX = sector count
;	DS:SI -> BUFHDR
;
; Outputs:
;	On success, DS:SI -> buffer with requested data, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	read_buffer,DOS
	ASSUME	DS:BIOS
	mov	[si].BUF_DRV,al
	mov	[si].BUF_LBA,bx
	add	si,size BUFHDR
	mov	ah,DDC_READ
	push	di
	push	es
	les	di,[FDC_DRIVER]
	call	dev_request
	pop	es
	pop	di
	ret
ENDPROC	read_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; flush_buffers
;
; TODO: For now, since we haven't yet implemented a buffer cache, all we
; have to do is zap the LBAs in the two BIOS sector buffers.
;
; Inputs:
;	AL = drive #
;
; Outputs:
;	Flush all buffers containing data for the specified drive
;
; Modifies:
;	None
;
DEFPROC	flush_buffers,DOS
	ASSUME	DS:BIOS
	cmp	ds:[FAT_BUFHDR].BUF_DRV,al
	jne	fb2
	mov	ds:[FAT_BUFHDR].BUF_LBA,0
fb2:	cmp	ds:[DIR_BUFHDR].BUF_DRV,al
	jne	fb3
	mov	ds:[DIR_BUFHDR].BUF_LBA,0
fb3:	ret
ENDPROC	flush_buffers

DOS	ends

	end
