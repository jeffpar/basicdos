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
	call	get_pft_free		; ES:DI = free handle entry
	ASSUME	ES:NOTHING
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
; hdl_read (REG_AH = 3Fh)
;
; Inputs:
;	REG_BX = handle
;	REG_CX = byte count
;	REG_DS:REG_DX -> data buffer
;
; Outputs:
;	On success, REG_AX = bytes read, carry clear
;	On failure, REG_AX = error, carry set
;
DEFPROC	hdl_read,DOS
	call	get_sfb			; BX -> SFB
	jc	hr8
	mov	cx,[bp].REG_CX		; CX = byte count
	call	sfb_read
	jnc	hr9
hr8:	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
hr9:	ret
ENDPROC	hdl_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hdl_write (REG_AH = 40h)
;
; Inputs:
;	REG_BX = handle
;	REG_CX = byte count
;	REG_DS:REG_DX -> data buffer
;
; Outputs:
;	On success, REG_AX = bytes written, carry clear
;	On failure, REG_AX = error, carry set
;
DEFPROC	hdl_write,DOS
	call	get_sfb			; BX -> SFB
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
;	On success, BX -> SFB, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, BX, CX, DX, DI
;
DEFPROC	sfb_open,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	si
	push	ds
	push	es
	call	chk_devname		; is it a device name?
	jnc	so1			; yes
	call	chk_filename		; is it a disk file name?
	jnc	so1a			; yes
so9a:	jmp	so9			; no

so1:	mov	ax,DDC_OPEN SHL 8	; ES:DI -> driver
	sub	dx,dx			; no initial context
	call	dev_request		; issue the DDC_OPEN request
	jc	so9a			; failed
	mov	al,-1			; no drive # for devices
so1a:	push	ds			;
	push	si			; save DIRENT at DS:SI (if any)
;
; When looking for a matching existing SFB, all we require is that three
; pieces of data match: the device driver (ES:DI), the drive # (AL), and the
; device context (DX).  For files, the context will be the starting cluster
; number; for devices, the context will be whatever dev_request returned.
;
; Traditionally, detecting unused SFBs meant those with a zero HANDLES count;
; however, our SFBs are also unused IFF the DRIVER seg is zero.
;
so2:	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	ah,bl			; save mode in AH
	mov	cx,es			; CX:DI is driver, DX is context
	mov	si,[sfb_table].off
	sub	bx,bx			; use BX to remember a free SFB
so3:	cmp	[si].SFB_DEVICE.off,di
	jne	so4			; check next SFB
	cmp	[si].SFB_DEVICE.seg,cx
	jne	so4			; check next SFB
	cmp	[si].SFB_DRIVE,al
	jne	so4			; check next SFB
	test	dx,dx			; any context?
	jz	so7			; no, so consider this SFB a match
	cmp	[si].SFB_CONTEXT,dx	; context match?
	je	so7			; match
so4:	test	bx,bx			; are we still looking for a free SFB?
	jnz	so5			; no
	cmp	[si].SFB_DEVICE.seg,bx	; is this one free?
	jne	so5			; no
	mov	bx,si			; yes, remember it
so5:	add	si,size SFB
	cmp	si,[sfb_table].seg
	jb	so3			; keep checking

	pop	si
	pop	ds
	test	bx,bx			; was there a free SFB?
	jz	so8			; no, tell the driver sorry

	test	al,al			; was a DIRENT provided?
	jl	so6			; no
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

so6:	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	[bx].SFB_DEVICE.off,di
	mov	[bx].SFB_DEVICE.seg,es
	mov	[bx].SFB_CONTEXT,dx	; set DRIVE (AL) and MODE (AH) next
	mov	word ptr [bx].SFB_DRIVE,ax
	sub	ax,ax
	mov	[bx].SFB_HANDLES,al	; no process handles yet
	mov	[bx].SFB_CURPOS.off,ax	; zero the initial file position
	mov	[bx].SFB_CURPOS.seg,ax
	mov	[bx].SFB_CURCLN,dx	; initial position cluster
	jmp	short so9		; return new SFB

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
; sfb_read
;
; Inputs:
;	BX -> SFB
;	CX = byte count
;	REG_DS:REG_DX -> data buffer
;
; Outputs:
;	On success, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	sfb_read,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
	mov	[bp].REG_AX,0		; use REG_AX to accumulate bytes read
	mov	dl,[bx].SFB_DRIVE
	test	dl,dl
	jge	sr0
	jmp	sr8			; character device

sr0:	int 3
	call	get_bpb			; DI -> BPB if no error
	jc	sr3a
;
; As a preliminary matter, make sure the requested number of bytes doesn't
; exceed the current file size; if it does, reduce it.
;
	mov	ax,[bx].SFB_SIZE.off
	mov	dx,[bx].SFB_SIZE.seg
	sub	ax,[bx].SFB_CURPOS.off
	sbb	dx,[bx].SFB_CURPOS.seg
	test	dx,dx			; lots of data ahead?
	jnz	sr1			; yes
	cmp	cx,ax
	jbe	sr1
	mov	cx,ax			; CX reduced
;
; Next, convert CURPOS into cluster # and cluster offset.  That's simplified
; if there's a valid CURCLN (which must be in sync with CURPOS if present);
; otherwise, we'll have to walk the cluster chain to find the correct cluster #.
;
sr1:	mov	dx,[bx].SFB_CURCLN
	test	dx,dx
	jnz	sr1a
	call	find_cln		; find cluster # for CURPOS
	mov	[bx].SFB_CURCLN,dx

sr1a:	mov	dx,[bx].SFB_CURPOS.off
	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	and	dx,ax			; DX = offset within current cluster

	push	bx			; save SFB pointer
	push	di			; save BPB pointer
	push	es

	mov	bx,[bx].SFB_CURCLN
	sub	bx,2
	jb	sr3			; invalid cluster #
	xchg	ax,cx			; save CX
	mov	cl,[di].BPB_CLUSLOG2
	shl	bx,cl
	xchg	ax,cx			; restore CX
	add	bx,[di].BPB_LBADATA	; BX = LBA
;
; We're almost ready to read, except for the byte count in CX, which must be
; limited to whatever's in the current cluster.
;
	push	cx			; save byte count
	mov	ax,[di].BPB_CLUSBYTES
	sub	ax,dx			; AX = bytes available in cluster
	cmp	cx,ax			; if CX <= AX, we're fine
	jbe	sr2
	mov	cx,ax			; reduce CX
sr2:	mov	ah,DDC_READ
	mov	al,[di].BPB_UNIT
	les	di,[di].BPB_DEVICE
	ASSUME	ES:NOTHING
	push	ds
	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS		; DS:SI = data buffer
	ASSUME	DS:NOTHING
	call	dev_request
	pop	ds
	ASSUME	DS:DOS
	mov	dx,cx			; DX = bytes read (assuming no error)
	pop	cx			; restore byte count

sr3:	pop	es
	ASSUME	ES:DOS
	pop	di			; BPB pointer restored
	pop	bx			; SFB pointer restored
sr3a:	jc	sr9
;
; Time for some bookkeeping: adjust the SFB's CURPOS by DX.
;
	add	[bx].SFB_CURPOS.off,dx
	adc	[bx].SFB_CURPOS.seg,0
	add	[bp].REG_AX,dx		; update accumulation of bytes read
;
; We're now obliged to determine whether or not we've exhausted the current
; cluster, because if we have, then we MUST zero SFB_CURCLN.
;
	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	test	[bx].SFB_CURPOS.off,ax	; is CURPOS at a cluster boundary?
	jnz	sr4			; no
	push	dx
	sub	dx,dx
	xchg	dx,[bx].SFB_CURCLN	; yes, get next cluster
	call	get_cln
	xchg	ax,dx
	pop	dx
	jc	sr9
	mov	[bx].SFB_CURCLN,ax
sr4:	sub	cx,dx			; have we exhausted the read count yet?
	jbe	sr9			; yes
	jmp	sr1a			; no, keep reading clusters

sr8:	push	ds
	push	es
	mov	ax,DDC_READ SHL 8
	les	di,[bx].SFB_DEVICE
	mov	dx,[bx].SFB_CONTEXT
	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS		; DS:SI = data buffer
	call	dev_request		; issue the DDC_READ request
	pop	es
	pop	ds
sr9:	ret
ENDPROC	sfb_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_seek
;
; Inputs:
;	BX -> SFB
;	AL = SEEK method (eg, SEEK_CUR)
;	CX:DX = seek value
;
; Outputs:
;	On success, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX
;
DEFPROC	sfb_seek,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>

ss9:	ret
ENDPROC	sfb_seek

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_write
;
; Inputs:
;	BX -> SFB
;	CX = byte count
;	DS:SI -> data buffer
;
; Outputs:
;	On success, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	sfb_write,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	cmp	cs:[bx].SFB_DRIVE,0
	jl	sw8
	stc				; no writes to block devices (yet)
	jmp	short sw9
sw8:	mov	ax,DDC_WRITE SHL 8
	les	di,cs:[bx].SFB_DEVICE
	mov	dx,cs:[bx].SFB_CONTEXT
	call	dev_request		; issue the DDC_WRITE request
sw9:	ret
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
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
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
	je	cd3			; match
;
; This could still be a match if DS:[SI-1] is a colon or a null, and
; ES:[DI-1] is a space.
;
	mov	al,[si-1]
	test	al,al
	jz	cd2
	cmp	al,':'
	jne	cd3
cd2:	cmp	byte ptr es:[di-1],' '
cd3:	pop	di
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
;	On success:
;		AL = drive #
;		DS:SI -> DIRENT
;		ES:DI -> driver header (DDH)
;		DX = context (1st cluster)
;	On failure, carry set
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	chk_filename,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
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
cf4:	call	get_bpb			; DL = drive #
	jc	cf9
;
; ES:DI -> BPB.  Start a directory search for file_name.
;
	call	get_dirent
	jc	cf9
;
; DS:SI -> DIRENT.  Get the cluster number as the context for the SFB.
;
	les	di,es:[di].BPB_DEVICE	; ES:DI -> driver
	mov	al,dl			; AL = drive #
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
;	AL = unit # (block devices only)
;	DX = device driver context, zero if none
;	ES:DI -> device driver header (DDH)
;
; Additionally, for read/write requests:
;	BX = LBA (block devices only)
;	CX = byte count
;	DX = offset within LBA
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
;	allocating memory for BPBs.  I didn't feel that was appropriate.
;
;	Here, DOS creates the BPBs and requests the driver to check them
;	and rebuild them as needed.  Also, most drivers commands look up the
;	BPB and pass it to the driver via the DDP_PARMS field.
;
DEFPROC	dev_request,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
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

dr2:	cmp	ah,DDC_READ
	je	dr3
	cmp	ah,DDC_WRITE
	jne	dr4
dr3:	mov	word ptr [bp].DDP_LEN,size DDPRW
	mov	[bp].DDPRW_ADDR.off,si
	mov	[bp].DDPRW_ADDR.seg,ds
	mov	[bp].DDPRW_LENGTH,cx
	mov	[bp].DDPRW_OFFSET,dx
	mov	[bp].DDPRW_LBA,bx
dr4:	mov	ah,size BPBEX		; AL still contains the unit #
	mul	ah
	add	ax,[bpb_table].off	; AX = BPB address
	mov	[bp].DDP_PARMS.off,ax	; save it in the request packet
	mov	[bp].DDP_PARMS.seg,cs

dr5:	mov	bx,bp
	push	es
	push	es:[di].DDH_REQUEST
	push	ss
	pop	es			; ES:BX -> packet
	call	dword ptr [bp-4]	; far call to DDH_REQUEST
	pop	ax
	pop	es			; ES restored
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
; find_cln
;
; Find the CLN corresponding to CURPOS.
;
; Inputs:
;	BX -> SFB
;	DI -> BPB
;
; Outputs:
;	On success, DX = CLN, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	find_cln,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
	mov	dx,[bx].SFB_CLN
	sub	si,si			; zero current position in CX:SI
	sub	cx,cx
;
; If our current position in CX:SI, plus CLUSBYTES, is greater than CURPOS,
; then we have reached the target cluster.
;
gc1:	add	si,[di].BPB_CLUSBYTES
	adc	cx,0
	push	cx			; save current position in CX:SI
	push	si
	sub	si,[bx].SFB_CURPOS.off
	sbb	cx,[bx].SFB_CURPOS.seg
	jnc	gc9			; we've traversed enough clusters
	call	get_cln			; DX = next CLN
	pop	si
	pop	cx			; restore current position in CX:SI
	jnc	gc1
	jmp	short gc9a
gc9:	pop	si
	pop	cx
gc9a:	ret
ENDPROC	find_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_cln
;
; For the CLN in DX, get the next CLN.
;
; Inputs:
;	DI -> BPB
;
; Outputs:
;	On success, DX = CLN, carry clear
;	On failure, AX = error code, carry set
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	get_cln,DOS
	push	bx
	push	cx
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
;
; We observe that the FAT sector # containing a 12-bit CLN is:
;
;	(CLN * 12) / 4096
;
; assuming a 512-byte sector with 4096 or 2^12 bits.  The expression
; can be simplified to (CLN * 12) SHR 12, or (CLN * 3) SHR 10, or simply
; (CLN + CLN + CLN) SHR 10.
;
; TODO: If we're serious about being sector-size-agnostic, our BPB should
; contain a (precalculated) LOG2 of BPB_SECBYTES, to avoid hard-coded shifts.
;
	mov	bx,dx
	add	dx,dx
	add	dx,bx
	mov	bx,dx
	mov	cl,10
	shr	dx,cl			; DX = FAT sector ((CLN * 3) SHR 10)
	add	dx,es:[di].BPB_RESSECS	; DX = FAT LBA
;
; Next, we need the nibble offset within the sector, which is:
;
;	((CLN * 12) % 4096) / 4
;
	and	bx,03FFh		; nibble offset (assuming 1024 nibbles)
	mov	al,es:[di].BPB_UNIT
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	jc	gc4
	mov	bp,bx			; save nibble offset in BP
	shr	bx,1			; BX -> byte, carry set if odd nibble
	mov	dl,[si+bx]
	inc	bx
	cmp	bp,03FFh		; at the sector boundary?
	jb	gc2			; no
	inc	dx			; DX = next FAT LBA
	mov	al,es:[di].BPB_UNIT
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	jc	gc4
	sub	bx,bx
gc2:	mov	dh,[si+bx]
	shr	bp,1			; was that an odd nibble again?
	jc	gc3			; yes
	and	dx,0FFFh		; no, so make sure top 4 bits clear
	jmp	short gc4		;
gc3:	mov	cl,4			;
	shr	dx,cl			; otherwise, shift all 12 bits down
	clc

gc4:	pop	ds
	pop	cx
	pop	bx
	ret
ENDPROC	get_cln

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
;	On success, ES:DI -> BPB, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, DI
;
DEFPROC	get_bpb,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	push	dx
	mov	al,dl			; AL = drive #
	mov	ah,size BPBEX
	mul	ah			; AX = BPB offset
	mov	di,[bpb_table].off
	add	di,ax
	cmp	di,[bpb_table].seg
	cmc
	jc	gb9			; we don't have a BPB for the drive
	push	di			; ES:DI -> BPB
	push	es
	les	di,es:[di].BPB_DEVICE
	mov	ah,DDC_MEDIACHK		; perform a MEDIACHK request
	call	dev_request
	jc	gb8
	test	dx,dx			; media unchanged?
	jg	gb8			; yes
	mov	ah,DDC_BUILDBPB		; ask the driver to rebuild our BPB
	call	dev_request
	jc	gb8
	call	flush_buffers		; flush any buffers with data from drive
gb8:	pop	es
	pop	di
gb9:	pop	dx
	ret
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
;	AX, BX, SI, DS
;
DEFPROC	get_dirent,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>	; ES = DOS since BPBs are in DOS
;
; Instead of blindly starting at LBAROOT, we'll start at whatever LBA
; directory sector we read last, if valid, and we'll stop when we 1) find
; a match, or 2) reach that same sector again (after looping around).
;
	push	dx
	push	bp
	sub	dx,dx
	mov	ds,dx
	ASSUME	DS:BIOS
	mov	si,offset DIR_BUFHDR
	mov	al,es:[di].BPB_DRIVE	; AL = drive #
	cmp	[si].BUF_DRIVE,al
	jne	gd1
	mov	dx,[si].BUF_LBA
	test	dx,dx
	jnz	gd2
gd1:	mov	dx,es:[di].BPB_LBAROOT
gd2:	mov	bp,dx			; BP = 1st LBA we'll check

gd4:	call	read_buffer		; DX = LBA
	jc	gd9

	mov	bx,es:[di].BPB_SECBYTES
	add	bx,si			; BX -> end of sector data
gd5:	cmp	byte ptr [si],0
	je	gd6			; 0 indicates end of allocated entries
	mov	di,offset file_name
	mov	cx,11
	repe	cmpsb
	je	gd9
	add	si,cx
	add	si,size DIRENT - 11
	cmp	si,bx
	jb	gd5
;
; Advance to next directory sector
;
	mov	si,offset DIR_BUFHDR
	inc	dx
	cmp	dx,es:[di].BPB_LBADATA
	jb	gd7
gd6:	mov	dx,es:[di].BPB_LBAROOT
gd7:	cmp	dx,bp			; back to the 1st LBA again?
	jne	gd4			; not yet
	stc				; out of sectors, so no match

gd9:	lea	si,[si-11]		; rewind SI, in case it was a match
	pop	bp
	pop	dx
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
;	AX, BX, CX
;
DEFPROC	get_sfb,DOS
	push	ds
	mov	ds,[psp_active]
	ASSUME	DS:NOTHING
	mov	bx,[bp].REG_BX		; BX = PFH ("handle")
	mov	al,ds:[PSP_PFT][bx]	; AL = SFH (we're being hopeful)
	pop	ds
	ASSUME	DS:DOS
	cmp	bx,size PSP_PFT		; is the PFH within PFT bounds?
	cmc
	jb	gs8			; no, our hope was misplaced
	mov	cl,size SFB		; convert SFH to SFB
	mul	cl
	add	ax,[sfb_table].off
	cmp	ax,[sfb_table].seg	; is the SFB valid?
	xchg	bx,ax			; BX -> SFB
	cmc
	jnb	gs9			; yes
gs8:	mov	ax,ERR_BADHANDLE
gs9:	ret
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
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	xchg	ax,bx			; AX = SFB address
	sub	ax,[sfb_table].off
	mov	cl,size SFB
	div	cl			; AL = SFB # (from SFB address)
	ASSERTZ	<test ah,ah>		; assert that the remainder is zero
	test	di,0FFF0h		; did we find a free PFT entry?
	jz	sj9			; no
	stosb				; yes, store SFB # in the PFT entry
	sub	di,offset PSP_PFT + 1	; convert PFT entry into PFH
	xchg	ax,di			; AX = handle
sj9:	ret
ENDPROC	set_pft_free

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
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	dx
	push	ds
	sub	dx,dx
	mov	ds,dx
	ASSUME	DS:BIOS
	cmp	ds:[FAT_BUFHDR].BUF_DRIVE,al
	jne	fb2
	mov	ds:[FAT_BUFHDR].BUF_LBA,0
fb2:	cmp	ds:[DIR_BUFHDR].BUF_DRIVE,al
	jne	fb3
	mov	ds:[DIR_BUFHDR].BUF_LBA,0
fb3:	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	ret
ENDPROC	flush_buffers

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_buffer
;
; Inputs:
;	AL = drive #
;	DX = LBA
;	DS:SI -> BUFHDR
;	ES:DI -> BPB
;
; Outputs:
;	On success, DS:SI -> buffer with requested data, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	read_buffer,DOS
	ASSUMES	<DS,BIOS>,<ES,DOS>	; ES = DOS since BPBs are in DOS
	cmp	[si].BUF_DRIVE,al
	jne	rb1
	cmp	[si].BUF_LBA,dx
	jne	rb1
	add	si,size BUFHDR
	jmp	short rb9
rb1:	push	bx
	push	dx
	mov	[si].BUF_DRIVE,al	; AL = unit #
	mov	[si].BUF_LBA,dx
	mov	cx,[si].BUF_SIZE	; CX = byte count
	mov	bx,dx			; BX = LBA
	sub	dx,dx			; DX = offset (0)
	add	si,size BUFHDR		; DS:SI -> data buffer
	mov	ah,DDC_READ
	push	di
	push	es
	ASSERTZ <cmp al,es:[di].BPB_UNIT>
	les	di,es:[di].BPB_DEVICE
	call	dev_request
	pop	es
	pop	di
	pop	dx
	pop	bx
rb9:	ret
ENDPROC	read_buffer

DOS	ends

	end
