;
; BASIC-DOS Disk Services
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
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<dev_request,parse_name,scb_release>

	EXTBYTE	<scb_locked>
	EXTWORD	<buf_head,scb_active>
	EXTLONG	<bpb_table>
	EXTBYTE	<bpb_total>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_flush (REG_AH = 0Dh)
;
; Inputs:
;	None (use drv_flush to flush drive # in AL only)
;
; Outputs:
;	Flush all buffers containing data for the specified drive
;
; Modifies:
;	None (carry clear)
;
DEFPROC	dsk_flush,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	mov	al,-1			; by default, flush all drives
	DEFLBL	drv_flush,near		; otherwise, flush only drive # in AL
	push	dx
	push	ds
	mov	ds,[buf_head]
	mov	dx,ds			; DX = head
df1:	test	al,al
	jl	df2
	cmp	ds:[BUF_DRIVE],al
	jne	df3
;
; We use zero to zap BUF_LBA because we never read LBA 0 into our buffers;
; the disk driver will read LBA 0, but only when it needs to rebuild the BPB.
;
df2:	mov	ds:[BUF_LBA],0		; use 0 to invalidate the LBA
df3:	cmp	ds:[BUF_NEXT],dx	; looped back around?
	je	df9			; yes
	mov	ds,ds:[BUF_NEXT]
	jmp	df1
df9:	pop	ds
	pop	dx
	ret
ENDPROC	dsk_flush

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_setdrv (REG_AH = 0Eh)
;
; Inputs:
;	REG_DL = drive #
;
; Outputs:
;	REG_AL = # of (logical) drives
;
; Notes:
;	The spec isn't clear if this should return an error (carry set)
;	if REG_DL >= # drives; we assume that we should.
;
; TODO: Add support for logical drives; all we currently support are physical.
;
DEFPROC	dsk_setdrv,DOS
	mov	al,[bpb_total]		; AL = # (physical) drives
	cmp	dl,al			; DL valid?
	cmc
	jc	ds9			; no
	mov	bx,[scb_active]
	mov	[bx].SCB_CURDRV,dl
ds9:	mov	[bp].REG_AL,al
	ret
ENDPROC	dsk_setdrv

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_setdta (REG_AH = 1Ah)
;
; Inputs:
;	REG_DS:REG_DX -> Disk Transfer Area (DTA)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX
;
DEFPROC	dsk_setdta,DOS
	mov	bx,[scb_active]
	mov	[bx].SCB_DTA.OFF,dx
	mov	ax,[bp].REG_DS
	mov	[bx].SCB_DTA.SEG,ax
	ret
ENDPROC	dsk_setdta

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_getdrv (REG_AH = 19h)
;
; Inputs:
;	None
;
; Outputs:
;	REG_AL = current drive #
;
DEFPROC	dsk_getdrv,DOS
	mov	bx,[scb_active]
	mov	al,[bx].SCB_CURDRV
	mov	[bp].REG_AL,al
	ret
ENDPROC	dsk_getdrv

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_getdta (REG_AH = 2Fh)
;
; Inputs:
;	None
;
; Outputs:
;	REG_ES:REG_BX -> Disk Transfer Area (DTA)
;
; Modifies:
;	AX, BX
;
DEFPROC	dsk_getdta,DOS
	mov	bx,[scb_active]
	mov	ax,[bx].SCB_DTA.OFF
	mov	[bp].REG_BX,ax
	mov	ax,[bx].SCB_DTA.SEG
	mov	[bp].REG_ES,ax
	ret
ENDPROC	dsk_getdta

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_getinfo (REG_AH = 36h)
;
; Returns cluster info (incl. free space) for the specified disk.
;
; Inputs:
;	REG_DL = drive # (0 for default, 1 for A:, and so on)
;
; Outputs:
;	REG_AX = sectors per cluster (FFFFh if drive number invalid)
;	REG_BX = available clusters
;	REG_CX = bytes per sector
;	REG_DX = clusters per disk
;
; Modifies:
;	AX, BX
;
DEFPROC	dsk_getinfo,DOS
	LOCK_SCB
	dec	dl			; drive # specified?
	jge	gi1			; yes
	mov	bx,[scb_active]		; no, so get CURDRV
	mov	dl,[bx].SCB_CURDRV	; from the active SCB
gi1:	call	get_bpb			; DL = drive #
	jc	gi8
;
; DS:DI -> fresh BPB for disk in drive.
;
	mov	ax,[di].BPB_SECBYTES
	mov	[bp].REG_CX,ax
;
; Count all the clusters on the disk, using SI.
;
	sub	si,si			; SI = cluster count
	mov	cx,[di].BPB_CLUSTERS
	mov	[bp].REG_DX,cx
	mov	bx,2			; BX = starting cluster #
gi2:	mov	dx,bx			; DX = cluster # for get_cln
	call	get_cln			; get the CLN
	jc	gi8			; error
	test	dx,dx			; cluster in use?
	jnz	gi3			; yes
	inc	si			; increment free count
gi3:	inc	bx			; advance cluster #
	loop	gi2			; loop until all clusters checked
	mov	[bp].REG_BX,si
	mov	al,[di].BPB_CLUSSECS
	cbw
	jmp	short gi9

gi8:	sbb	ax,ax			; set AX to FFFFh on error
gi9:	mov	[bp].REG_AX,ax
	UNLOCK_SCB
	ret
ENDPROC	dsk_getinfo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_ffirst (REG_AH = 4Eh)
;
; Inputs:
;	REG_CX = attribute bits
;	REG_DS:REG_DX -> filespec
;
; Outputs:
;	If found, carry clear, DTA filled in
;	If not found, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS
;
DEFPROC	dsk_ffirst,DOS
	LOCK_SCB
	mov	al,[bp].REG_CL
	mov	ah,80h			; AH = 80h (filespec)
	mov	si,dx
	mov	ds,[bp].REG_DS		; DS:SI -> filespec
	call	chk_filename
	jc	ff8
	mov	ah,[bp].REG_CL
;
; Fill in the DTA with the relevant bits
;
	DEFLBL	dsk_ffill,near
	ASSUME	DS:NOTHING, ES:NOTHING	; DS:SI -> DIRENT
	mov	bx,[scb_active]
	les	di,cs:[bx].SCB_DTA	; ES:DI -> DTA (FFB)
	stosw				; FFB_DRIVE, FFB_SATTR
	push	cx
	push	si
	mov	cx,size FCB_NAME
	lea	si,[bx].SCB_FILENAME + 1; FFB_FILESPEC
	REPMOV	byte,CS
	pop	si
	pop	cx
	add	di,size FFB_RESERVED
	ASSERT	Z,<cmp di,80h + offset FFB_DIRNUM>
	xchg	ax,cx
	ASSERT	Z,<test ah,ah>		; assert DIRENT # < 256 (for now)
	stosw				; FFB_DIRNUM
	mov	al,[si].DIR_ATTR
	stosb				; FFB_ATTR
	mov	ax,[si].DIR_TIME
	stosw				; FFB_TIME
	mov	ax,[si].DIR_DATE
	stosw				; FFB_DATE
	mov	ax,[si].DIR_SIZE.OFF
	stosw				; FFB_SIZE
	mov	ax,[si].DIR_SIZE.SEG
	stosw
	mov	cx,8
ff3:	lodsb
	cmp	al,' '
	je	ff4
	stosb				; FFB_NAME
ff4:	loop	ff3
	mov	al,[si]
	cmp	al,' '
	je	ff7
	mov	al,'.'
	stosb
	mov	cx,3
ff5:	lodsb
	cmp	al,' '
	je	ff6
	stosb
ff6:	loop	ff5
ff7:	sub	ax,ax
	stosb
	jnc	ff9
ff8:	mov	[bp].REG_AX,ax
ff9:	UNLOCK_SCB
	ret
ENDPROC	dsk_ffirst

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_fnext (REG_AH = 4Fh)
;
; Inputs:
;	DTA -> data from previous dsk_ffirst/dsk_fnext
;
; Outputs:
;	If found, carry clear, DTA filled in
;	If not found, carry set, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS
;
DEFPROC	dsk_fnext,DOS
	LOCK_SCB
	mov	bx,[scb_active]
	lds	si,cs:[bx].SCB_DTA	; DS:SI -> DTA (FFB)
	ASSUME	DS:NOTHING
	mov	dl,[si].FFB_DRIVE
	push	si
	lea	si,[si].FFB_FILESPEC
	lea	di,[bx].SCB_FILENAME + 1
	mov	cx,size FFB_FILESPEC
	rep	movsb
	pop	si
	call	get_bpb			; DL = drive #
	jc	fn8
	mov	bl,[si].FFB_SATTR	; BL = search attributes
	mov	dh,bl
	mov	ax,[si].FFB_DIRNUM	; AX = prev DIRENT #
	inc	ax			; AX = next DIRENT #
	call	get_dirent
	jc	fn8
	ASSERT	Z,<test ah,ah>		; assert DIRENT # < 256 (for now)
	xchg	cx,ax			; CX = DIRENT #
	mov	ax,dx			; AL = drive #, AH = search attributes
	jmp	dsk_ffill
fn8:	mov	[bp].REG_AX,ax
	UNLOCK_SCB
	ret
ENDPROC	dsk_fnext

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_filename
;
; Inputs:
;	AL = search attributes (0 if none)
;	AH = 00h for filename, 10h for FCB, 80h for filespec (w/wildcards)
;	DS:SI -> filename or filespec
;
; Outputs:
;	On success:
;		AL = drive #
;		CX = DIRENT #
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
	push	bx
	push	ax
	mov	bx,[scb_active]
	lea	di,[bx].SCB_FILENAME	; ES:DI -> filename buffer
;
; If AH = 10h, then we've already got a "parsed name", so instead
; of calling parse_name, just copy the name to the FILENAME buffer.
;
	cmp	ah,10h
	jne	cf3
	lodsb				; AL = FCB_DRIVE
	dec	al			; convert 1-based drive # to 0-based
	jge	cf2			; looks good
	mov	bx,[scb_active]		; no, get SCB's default drive instead
	ASSERT	STRUCT,es:[bx],SCB
	mov	al,es:[bx].SCB_CURDRV
cf2:	stosb				; store drive # in the FILENAME buffer
	xchg	dx,ax			; DL = drive #
	mov	cx,size FCB_NAME
;
; Even though callers have provided a "parsed name", they are apparently NOT
; required to also upper-case it.
;
; TODO: Expand this code to a separate function which, like parse_name, upper-
; cases and validates all characters against FILENAME_CHARS.
;
cf2a:	lodsb
	cmp	al,'a'
	jb	cf2b
	cmp	al,'z'
	ja	cf2b
	sub	al,20h
cf2b:	stosb
	loop	cf2a
	jmp	short cf4

cf3:	call	parse_name		; DS:SI -> filename or filespec
	jc	cf9			; bail on error
;
; FILENAME has been successfully filled in, so we're ready to search
; directory sectors for a matching name.  This requires getting a fresh
; BPB for the drive.
;
cf4:	call	get_bpb			; DL = drive # (from above)
	jc	cf9
;
; DI -> BPB.  Start a directory search for FILENAME.
;
	pop	ax
	push	ax
	mov	bl,al			; BL = search attributes
	test	ah,ah
	mov	ax,0
	jnz	cf5
	dec	ax			; AX = DIRENT # (or -1)
cf5:	call	get_dirent
	jc	cf9
;
; DS:SI -> DIRENT.  Get the cluster number as the context for the SFB.
;
	xchg	cx,ax			; CX = DIRENT #
	les	di,es:[di].BPB_DEVICE	; ES:DI -> driver
	mov	al,dl			; AL = drive #
	mov	dx,[si].DIR_CLN		; DX = CLN from DIRENT

cf9:	inc	sp			; add sp,2 without affecting carry
	inc	sp
	pop	bx
	ret
ENDPROC	chk_filename

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
;	AX, DX, SI
;
DEFPROC	find_cln,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	cx
	sub	si,si			; SI:CX = cluster position
	sub	cx,cx			; (starting at zero)
	mov	dx,[bx].SFB_CLN		; DX = corresponding cluster #
;
; Add CLUSBYTES - 1 to the cluster position in SI:CX to produce a cluster
; limit, then subtract CURPOS.  As long as that subtraction produces a borrow,
; we haven't reached the target cluster yet.
;
fc1:	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	add	cx,ax
	adc	si,0			; SI:CX = cluster limit
	mov	ax,cx
	sub	ax,[bx].SFB_CURPOS.LOW
	mov	ax,si
	sbb	ax,[bx].SFB_CURPOS.HIW
	jnc	fc9			; we've traversed enough clusters
	call	get_cln			; DX = next CLN
	jnc	fc1			; keep checking as long as no error

fc9:	pop	cx
	ret
ENDPROC	find_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_bpb
;
; As part of getting the BPB for the specified drive, this function presumes
; that the request is due to an imminent I/O request; therefore, we verify
; that the BPB is "fresh", and if it isn't, we reload it and mark it "fresh".
;
; Inputs:
;	DL = drive # (0-based)
;
; Outputs:
;	On success, DI -> BPB, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, DI
;
DEFPROC	get_bpb,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cx
	push	dx
	mov	al,dl			; AL = drive #
	mov	cl,al			; save it in CL
	mov	ah,size BPBEX
	mul	ah			; AX = BPB offset
	mov	di,[bpb_table].OFF
	add	di,ax
	cmp	di,[bpb_table].SEG
	cmc
	jc	gb9			; we don't have a BPB for the drive
	push	di			; DI -> BPB
	push	es
	ASSERT	STRUCT,cs:[di],BPB
	les	di,cs:[di].BPB_DEVICE
	mov	al,cl			; AL = drive #
	mov	ah,DDC_MEDIACHK		; perform a MEDIACHK request
	call	dev_request
	jc	gb8
	test	dx,dx			; media unchanged?
	jg	gb8			; yes
	mov	al,cl			; AL = drive #
	mov	ah,DDC_BUILDBPB		; ask the driver to rebuild our BPB
	call	dev_request
	jc	gb8
	mov	al,cl			; AL = drive #
	call	drv_flush		; flush any buffers with data from drive
gb8:	pop	es
	pop	di
gb9:	pop	dx
	pop	cx
	ret
ENDPROC	get_bpb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_cln (see also: read_fat in boot.asm)
;
; For the CLN in DX, get the next CLN in DX, using the BPB at DI.
;
; Inputs:
;	DX = CLN
;	DI -> BPB
;
; Outputs:
;	On success, carry clear, DX = CLN
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, DX
;
DEFPROC	get_cln,DOS
	ASSUME	ES:NOTHING
	push	bx
	push	cx
	push	si
	push	bp
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
; That'll be tough to do without wasting buffer memory though, since sectors
; can be as large as 1K.
;
	mov	bx,dx
	add	dx,dx
	add	dx,bx
	mov	bx,dx
	mov	cl,10
	shr	dx,cl			; DX = FAT sector ((CLN * 3) SHR 10)
	add	dx,cs:[di].BPB_RESSECS	; DX = FAT LBA
;
; Next, we need the nibble offset within the sector, which is:
;
;	((CLN * 12) % 4096) / 4
;
	and	bx,03FFh		; nibble offset (assuming 1024 nibbles)
	mov	al,cs:[di].BPB_DRIVE
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
	mov	al,cs:[di].BPB_DRIVE
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
	pop	bp
	pop	si
	pop	cx
	pop	bx
	ret
ENDPROC	get_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_dirent
;
; Inputs:
;	AX = next DIRENT #, -1 if don't care
;	BL = file attributes, 0 if don't care
;	DI -> BPB
;	SCB_FILENAME contains the filename
;
; Outputs:
;	On success, DS:SI -> DIRENT, AX = DIRENT #, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, BX, CX, SI, DS
;
DEFPROC	get_dirent,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	push	dx
	push	bp
	sub	dx,dx
	mov	ds,dx
	ASSUME	DS:BIOS
	mov	si,offset DIR_BUFHDR
	mov	bp,es:[di].BPB_LBAROOT
	sub	cx,cx
	test	ax,ax
	jl	gd1
	mov	dx,DIRENT_SIZE		; AX = DIRENT #
	mul	dx			; DX:AX = DIRENT offset
	div	es:[di].BPB_SECBYTES	; AX = relative sector #
	mov	cx,dx			; CX = offset within sector
	mov	dx,bp
	add	dx,ax			; DX = LBA of directory sector
	jmp	short gd3
;
; If one of the sectors from the directory we're interested in is already
; in DIR_BUF, and we're not continuing from a specific DIRENT, then a nice
; optimization is to start with the current sector.  We simply loop around
; to the top of the directory and stop when we reach this same sector again.
;
gd1:	mov	al,es:[di].BPB_DRIVE	; AL = drive #
	cmp	[si].BUF_DRIVE,al
	jne	gd2
	mov	dx,[si].BUF_LBA
	test	dx,dx
	jz	gd2
	mov	bp,dx
gd2:	mov	dx,bp
;
; End of initialization code, beginning of main loop.
;
gd3:	mov	al,es:[di].BPB_DRIVE
	ASSERT	STRUCT,[si],BUF
	call	read_buffer		; AL = drive #, DX = LBA
	jc	gd7a

	mov	ax,es:[di].BPB_SECBYTES
	add	ax,si			; AX -> end of sector data
	add	si,cx			; DS:SI+CX -> DIRENT

gd5:	cmp	byte ptr [si],DIRENT_END
	je	gd6			; 0 indicates end of allocated entries
	cmp	byte ptr [si],DIRENT_DELETED
	je	gd5e
	test	bl,bl			; any attributes specified?
	jz	gd5a			; no
	mov	cl,[si].DIR_ATTR	; CL = attributes
	test	cl,bl			; any of the attributes we care about?
	jz	gd5e			; no

gd5a:	push	di
	mov	cx,size FCB_NAME
	push	bx
	mov	bx,[scb_active]
	lea	di,[bx].SCB_FILENAME + 1; skip drive # for DIRENT comparison
	pop	bx
gd5b:	mov	bh,es:[di]
	inc	di
	cmp	bh,'?'
	je	gd5c
	cmp	bh,[si]
	jne	gd5d
gd5c:	lea	si,[si+1]
	loop	gd5b
gd5d:	pop	di
	je	gd8

	add	si,cx
	sub	si,size FCB_NAME
gd5e:	add	si,size DIRENT
	cmp	si,ax
	jb	gd5

	inc	dx			; advance to the next directory sector
	cmp	dx,es:[di].BPB_LBADATA
	jb	gd7
gd6:	mov	dx,es:[di].BPB_LBAROOT

gd7:	sub	cx,cx			; start at offset zero of next sector
	mov	si,offset DIR_BUFHDR
	cmp	dx,bp			; back to the 1st LBA again?
	jne	gd3			; not yet

	mov	ax,ERR_NOFILE		; out of sectors, so no match
	stc
gd7a:	jmp	short gd9

gd8:	lea	si,[si-11]		; rewind SI to matching DIRENT
	mov	cx,si
	sub	ax,es:[di].BPB_SECBYTES
	sub	cx,ax			; CX = DIRENT offset
	sub	dx,es:[di].BPB_LBAROOT
	xchg	ax,dx			; AX = relative sector #
	mul	es:[di].BPB_SECBYTES
	add	ax,cx
	mov	cx,DIRENT_SIZE
	div	cx			; AX = DIRENT #
	clc				; make sure carry is still clear

gd9:	pop	bp
	pop	dx
	ret
ENDPROC	get_dirent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_buffer
;
; Inputs:
;	AL = drive #
;	DX = LBA
;	DS:SI -> BUFHDR
;	DI -> BPB
;
; Outputs:
;	On success, DS:SI -> buffer with requested data, carry clear
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, SI
;
DEFPROC	read_buffer,DOS
	ASSUMES	<DS,BIOS>,<ES,NOTHING>
	cmp	[si].BUF_DRIVE,al
	jne	rb1
	cmp	[si].BUF_LBA,dx
	jne	rb1
	add	si,size BUFHDR
	jmp	short rb9
rb1:	push	bx
	push	cx
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
	ASSERT	Z,<cmp al,cs:[di].BPB_DRIVE>
	les	di,cs:[di].BPB_DEVICE
	call	dev_request
	pop	es
	pop	di
	pop	dx
	pop	cx
	pop	bx
rb9:	ret
ENDPROC	read_buffer

DOS	ends

	end
