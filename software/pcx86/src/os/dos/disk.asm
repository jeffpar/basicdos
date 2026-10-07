;
; BASIC-DOS Disk Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<dev_request,copy_name,parse_name,scb_release>

	EXTBYTE	<scb_locked>
	EXTWORD	<buf_head,scb_active>
	EXTLONG	<bpb_table,cdir_table>
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
;	AX (carry clear)
;
; Notes:
;	dsk_flush writes any modified buffers before invalidating them,
;	whereas drv_flush (used when the media has changed) simply discards
;	them.
;
DEFPROC	dsk_flush,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	mov	al,-1			; by default, flush all drives
	call	flush_buffers		; write any modified buffers first
	mov	al,-1
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
	mov	ds:[BUF_DIRTY],0	; and discard any unwritten data
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
	or	al,DIRATTR_SEARCH	; AL = search attributes
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
	REPS	MOVS,ES,CS,BYTE
	mov	ax,cs:[bx].SCB_DIRCLN
	stosw				; FFB_DIRCLN
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
	call	fmt_name		; FFB_NAME
	sub	ax,ax
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
	ASSERT	<FFB_FILESPEC + size FFB_FILESPEC>,EQ,<FFB_DIRCLN>
	lodsw				; AX = FFB_DIRCLN
	mov	es:[bx].SCB_DIRCLN,ax
	pop	si
	call	get_bpb			; DL = drive #
	jc	fn8
	mov	bl,[si].FFB_SATTR	; BL = search attributes
	mov	dh,bl
	or	bl,DIRATTR_SEARCH
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
;	On failure, carry set, AX = error code
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
	ASSERT	STRUCT,es:[bx],SCB
	lea	di,[bx].SCB_FILENAME	; ES:DI -> filename buffer
;
; If AH = 10h, then we've already got a "parsed name", so instead
; of calling get_path, just copy the name to the FILENAME buffer; FCBs
; always refer to the drive's current directory.
;
	cmp	ah,10h
	jne	cf3
	lodsb				; AL = FCB_DRIVE
	dec	al			; convert 1-based drive # to 0-based
	jge	cf1			; looks good
	mov	al,es:[bx].SCB_CURDRV
cf1:	stosb				; store drive # in the FILENAME buffer
	xchg	dx,ax			; DL = drive #
	call	copy_name
	mov	al,dl
	call	get_cdir		; BX -> drive's current directory
	mov	ax,es:[bx]
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,ax
	call	get_bpb			; DL = drive #
	jmp	short cf4

cf3:	call	get_path		; DS:SI -> filename or filespec
;
; FILENAME and DIRCLN have been successfully filled in, and DI -> BPB, so
; we're ready to search the directory's sectors for a matching name.
;
cf4:	jc	cf9
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
;	On failure, AX = error code (device or ERR_BADDRIVE), carry set
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
	mov	ax,ERR_BADDRIVE
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
	jl	gb7			; no, the media definitely changed
;
; The driver doesn't know if the media changed, but if we have any unwritten
; buffers for the drive, then (like PC DOS) we assume it hasn't.
;
	mov	al,cl			; AL = drive #
	call	chk_buffers		; any modified buffers for the drive?
	jnz	gb8			; yes (and carry is clear)
gb7:	mov	al,cl			; AL = drive #
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
	mov	cl,[si+bx]		; CL = 1st byte of the entry
	inc	bx
;
; An entry that begins at nibble 3FEh or 3FFh continues in the next sector.
; Note that DX must still contain the FAT LBA here, which is why the 1st byte
; of the entry is in CL.
;
	cmp	bp,03FEh		; at the sector boundary?
	jb	gc2			; no
	inc	dx			; DX = next FAT LBA
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset FAT_BUFHDR
	push	cx
	call	read_buffer
	pop	cx
	jc	gc4
	sub	bx,bx
gc2:	mov	dl,cl
	mov	dh,[si+bx]
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
;
;	If BL includes DIRATTR_SEARCH, then the DOS rules for "find first" and
;	"find next" apply: an entry matches only if all its HIDDEN, SYSTEM,
;	VOLUME, and SUBDIR attributes are included in BL, so BL = DIRATTR_SEARCH
;	alone matches only normal files (eg, not volume labels).  Otherwise,
;	an entry matches if it has any of the attributes in BL.
;	DI -> BPB
;	SCB_DIRCLN contains the directory (1st cluster, or 0 for the root)
;	SCB_FILENAME contains the filename
;
; Outputs:
;	On success, DS:SI -> DIRENT, AX = DIRENT #, carry clear
;	On failure, AX = error code, carry set
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
	sub	bp,bp			; BP = 1st relative sector to search
	sub	cx,cx
	test	ax,ax
	jl	gd1
	mov	dx,DIRENT_SIZE		; AX = DIRENT #
	mul	dx			; DX:AX = DIRENT offset
	div	es:[di].BPB_SECBYTES	; AX = relative sector #
	mov	cx,dx			; CX = offset within sector
	xchg	dx,ax			; DX = relative sector #
	jmp	short gd3
;
; If one of the sectors from the directory we're interested in is already
; in DIR_BUF, and we're not continuing from a specific DIRENT, then a nice
; optimization is to start with that sector.  We simply loop around to the
; top of the directory and stop when we reach this same sector again.
;
gd1:	mov	al,es:[di].BPB_DRIVE	; AL = drive #
	cmp	[si].BUF_DRIVE,al
	jne	gd2
	cmp	[si].BUF_LBA,dx		; is the buffer valid (DX is zero)?
	je	gd2			; no
	call	get_dircln		; AX = directory
	cmp	[si].BUF_DIRCLN,ax	; is the buffer from this directory?
	jne	gd2			; no
	mov	bp,[si].BUF_DIRREL	; yes, so start with its sector
gd2:	mov	dx,bp
;
; End of initialization code, beginning of main loop.
;
gd3:	call	dir_lba			; AX = LBA of relative sector DX
	jc	gd6a
	push	dx
	xchg	dx,ax			; DX = LBA
	mov	al,es:[di].BPB_DRIVE
	ASSERT	STRUCT,[si],BUF
	call	read_buffer		; AL = drive #, DX = LBA
	pop	dx
	jnc	gd4
	jmp	gd9
gd4:	call	get_dircln		; record the buffer's directory
	mov	[DIR_BUFHDR].BUF_DIRCLN,ax
	mov	[DIR_BUFHDR].BUF_DIRREL,dx

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
	test	bl,DIRATTR_SEARCH	; DOS search rules?
	jnz	gd5f			; yes
	test	cl,bl			; any of the attributes we care about?
	jz	gd5e			; no
	jmp	short gd5a
gd5f:	and	cl,DIRATTR_HIDDEN OR DIRATTR_SYSTEM OR DIRATTR_VOLUME OR DIRATTR_SUBDIR
	mov	ch,bl
	not	ch
	test	cl,ch			; any attributes that weren't requested?
	jnz	gd5e			; yes

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
	jmp	short gd7
;
; If the directory has no sector DX, but that's where we started (which can
; happen only if the DIR_BUF hint was stale), then search from the first
; sector instead (unless that's where we started).
;
gd6a:	cmp	ax,ERR_NOFILE		; beyond the end of the directory?
	stc
	jne	gd7a			; no, return the error
	cmp	dx,bp			; was this the first sector searched?
	jne	gd6			; no
	test	bp,bp			; was it sector 0?
	jz	gd7b			; yes, so the directory is empty
	sub	bp,bp
	jmp	gd2

gd6:	sub	dx,dx			; start over at the first sector

gd7:	sub	cx,cx			; start at offset zero of next sector
	mov	si,offset DIR_BUFHDR
	cmp	dx,bp			; back to the 1st sector again?
	je	gd7b			; yes
	jmp	gd3			; not yet

gd7b:	mov	ax,ERR_NOFILE		; out of sectors, so no match
	stc
gd7a:	jmp	short gd9

gd8:	lea	si,[si-11]		; rewind SI to matching DIRENT
	mov	cx,si
	sub	ax,es:[di].BPB_SECBYTES
	sub	cx,ax			; CX = DIRENT offset
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
; get_dircln
;
; Inputs:
;	None
;
; Outputs:
;	AX = SCB_DIRCLN of the active SCB
;
; Modifies:
;	AX
;
DEFPROC	get_dircln,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	mov	bx,cs:[scb_active]
	mov	ax,cs:[bx].SCB_DIRCLN
	pop	bx
	ret
ENDPROC	get_dircln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dir_lba
;
; Get the LBA of a sector of the directory in SCB_DIRCLN.  The root directory
; occupies a fixed range of sectors, whereas a subdirectory is a cluster chain.
;
; Inputs:
;	DX = relative sector # within the directory
;	DI -> BPB
;
; Outputs:
;	On success, carry clear, AX = LBA
;	On failure, carry set, AX = error code (ERR_NOFILE if the directory
;	has no such sector)
;
; Modifies:
;	AX
;
DEFPROC	dir_lba,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	push	cx
	push	dx
	call	get_dircln		; AX = directory
	test	ax,ax			; root directory?
	jnz	dl2			; no
	xchg	ax,dx			; AX = relative sector #
	add	ax,cs:[di].BPB_LBAROOT
	cmp	ax,cs:[di].BPB_LBADATA	; still within the root?
	jb	dl8			; yes
	jmp	short dl7

dl2:	mov	bx,dx			; BX = relative sector #
	mov	cl,cs:[di].BPB_CLUSLOG2
	shr	dx,cl
	xchg	cx,dx			; CX = cluster index
	xchg	dx,ax			; DX = 1st cluster
dl3:	mov	ax,dx
	sub	ax,2
	cmp	ax,cs:[di].BPB_CLUSTERS	; valid cluster?
	jae	dl7			; no, so we've reached the end
	jcxz	dl4
	call	get_cln			; DX = next cluster
	jc	dl9
	dec	cx
	jmp	dl3
dl4:	mov	cl,cs:[di].BPB_CLUSLOG2
	shl	ax,cl
	add	ax,cs:[di].BPB_LBADATA	; AX = cluster's 1st LBA
	mov	dl,cs:[di].BPB_CLUSSECS
	dec	dl			; DL = mask for sector within cluster
	and	bl,dl
	mov	bh,0
	add	ax,bx			; AX = LBA
	jmp	short dl8

dl7:	mov	ax,ERR_NOFILE
	stc
	jmp	short dl9
dl8:	clc
dl9:	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	dir_lba

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_cdir
;
; Get the address of a session's current directory (1st cluster, or 0 for
; the root) for a drive.  cdir_table contains bpb_total words for each SCB.
;
; Inputs:
;	AL = drive #
;	BX -> SCB
;
; Outputs:
;	BX -> current directory word (in the DOS segment)
;
; Modifies:
;	AX, BX
;
DEFPROC	get_cdir,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	dx
	xchg	dx,ax			; DL = drive #
	mov	al,cs:[bpb_total]
	mul	cs:[bx].SCB_NUM		; AX = SCB's 1st entry #
	add	al,dl
	adc	ah,0			; AX = drive's entry #
	add	ax,ax
	add	ax,cs:[cdir_table].OFF
	xchg	bx,ax
	pop	dx
	ret
ENDPROC	get_cdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_path
;
; Parse the drive, directory names (separated by SCB_PATHCHAR), and filename
; at DS:SI, walking the directories as we go.  A path that begins with
; SCB_PATHCHAR starts at the root directory; otherwise, it starts at the
; drive's current directory.
;
; Inputs:
;	AH = parse flags (00h for a filename, 80h for a filespec w/wildcards)
;	BX -> active SCB
;	DS:SI -> path
;	ES:DI -> SCB_FILENAME
;
; Outputs:
;	On success, carry clear:
;		DL = drive #
;		DI -> BPB
;		SCB_DIRCLN = directory containing the filename
;		SCB_FILENAME = drive # and filename (which may be blank)
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	get_path,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	push	ax			; save parse flags
	push	bx
	call	parse_comp		; parse the drive and 1st name
	pop	bx
	mov	es:[di],dl		; store a 0-based drive # (parse_name
	mov	ax,ERR_BADDRIVE		; stores 1-based), unless it's invalid
	jc	gp9
	call	get_bpb			; DI -> BPB
	jc	gp9
	push	bx
	mov	al,dl
	call	get_cdir		; BX -> drive's current directory
	mov	ax,es:[bx]
	pop	bx
	mov	cl,es:[bx].SCB_PATHCHAR
	cmp	[si],cl			; is there a directory to walk?
	jne	gp7			; no
	cmp	es:[bx].SCB_FILENAME+1,' '
	jne	gp2			; the path doesn't start at the root
	sub	ax,ax
gp2:	mov	es:[bx].SCB_DIRCLN,ax
	inc	si			; skip SCB_PATHCHAR
	mov	ax,ERR_NOPATH
	test	dh,dh			; any wildcards in the directory name?
	stc
	jnz	gp9			; yes
	call	get_dir			; AX = directory
	jc	gp9
	mov	es:[bx].SCB_DIRCLN,ax
	pop	ax			; restore parse flags (AH)
	push	ax
	or	ah,02h			; leave the drive # unchanged
	push	dx
	push	di
	lea	di,[bx].SCB_FILENAME
	push	bx
	call	parse_comp		; parse the next name
	pop	bx
	pop	di
	mov	al,dh			; AL = wildcards flag
	pop	dx			; DL = drive # again
	mov	dh,al			; DH = wildcards flag
	mov	ax,es:[bx].SCB_DIRCLN
	mov	cl,es:[bx].SCB_PATHCHAR
	cmp	[si],cl			; another directory?
	je	gp2			; yes
	jmp	short gp8
gp7:	mov	es:[bx].SCB_DIRCLN,ax
gp8:	clc
gp9:	inc	sp			; discard parse flags
	inc	sp			; without affecting carry
	ret
ENDPROC	get_path

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; parse_comp
;
; Use parse_name to parse one component of a path, and then fix up any "."
; or ".." component, which parse_name would otherwise leave blank.
;
; Inputs:
;	AH = parse flags (see parse_name)
;	DS:SI -> component (optionally preceded by a drive)
;	ES:DI -> filename buffer
;
; Outputs:
;	Same as parse_name
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	parse_comp,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	si
	call	parse_name
	pop	bx			; BX -> start of component
	pushf
	cmp	byte ptr [bx+1],':'	; does it start with a drive?
	jne	pc1			; no
	inc	bx
	inc	bx
pc1:	mov	al,'.'
	cmp	[bx],al			; does the component start with a dot?
	jne	pc9			; no
	cmp	byte ptr es:[di+9],' '	; and have no extension?
	jne	pc9			; no
	lea	si,[bx+1]		; it's "." (or "..")
	mov	es:[di+1],al
	cmp	[si],al
	jne	pc9
	inc	si
	mov	es:[di+2],al
pc9:	popf
	ret
ENDPROC	parse_comp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_dir
;
; Get the directory for the name in SCB_FILENAME, which must be either a
; subdirectory of SCB_DIRCLN, or blank or "." (ie, SCB_DIRCLN itself).
;
; Inputs:
;	DI -> BPB
;	SCB_DIRCLN and SCB_FILENAME
;
; Outputs:
;	On success, carry clear, AX = directory (1st cluster, or 0 for root)
;	On failure, carry set, AX = error code (ERR_NOPATH if not found)
;
; Modifies:
;	AX, CX
;
DEFPROC	get_dir,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	push	bx
	push	si
	push	ds
	mov	bx,[scb_active]
	mov	ax,es:[bx].SCB_DIRCLN
	mov	cx,word ptr es:[bx].SCB_FILENAME+1
	cmp	cl,' '			; blank?
	je	gr9			; yes (and carry is clear)
	cmp	cx,' .'			; "."?
	je	gr9			; yes (and carry is clear)
	mov	ax,-1
	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; DS:SI -> DIRENT
	jc	gr8
	mov	ax,[si].DIR_CLN
	jmp	short gr9
gr8:	cmp	ax,ERR_NOFILE
	stc
	jne	gr9
	mov	ax,ERR_NOPATH
gr9:	pop	ds
	pop	si
	pop	bx
	ret
ENDPROC	get_dir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_parent
;
; Get the parent of a subdirectory, along with the subdirectory's name, by
; reading its ".." entry and then finding its entry in the parent.
;
; Inputs:
;	DX = subdirectory (1st cluster)
;	DI -> BPB
;
; Outputs:
;	On success, carry clear:
;		AX = parent directory (1st cluster, or 0 for the root)
;		SCB_FILENAME = subdirectory name (eg, "NAME.EXT")
;		CX = length of name
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, SCB_DIRCLN
;
DEFPROC	get_parent,DOS
	ASSUMES	<DS,NOTHING>,<ES,DOS>
	push	bx
	push	si
	push	ds
	push	di
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,dx
	lea	di,[bx].SCB_FILENAME+1
	mov	ax,'..'
	stosw
	mov	al,' '
	mov	cx,size FCB_NAME - 2
	rep	stosb
	pop	di
	sub	ax,ax			; start with DIRENT # 0
	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; DS:SI -> ".." DIRENT
	jc	gt8
	mov	ax,[si].DIR_CLN		; AX = parent
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,ax
	push	di
	lea	di,[bx].SCB_FILENAME+1
	mov	al,'?'
	mov	cx,size FCB_NAME
	rep	stosb
	pop	di
	sub	ax,ax
gt2:	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; AX = DIRENT #, DS:SI -> DIRENT
	jc	gt8
	inc	ax			; AX = next DIRENT # (if no match)
	cmp	[si].DIR_CLN,dx		; is this the subdirectory?
	jne	gt2			; no
	cmp	[si].DIR_NAME,'.'	; ("." and ".." don't count)
	je	gt2
	mov	bx,[scb_active]
	push	di
	lea	di,[bx].SCB_FILENAME
	call	fmt_name		; copy the name to SCB_FILENAME
	xchg	cx,di
	pop	di
	lea	ax,[bx].SCB_FILENAME
	sub	cx,ax			; CX = length of name
	mov	ax,es:[bx].SCB_DIRCLN	; AX = parent (and carry is clear)
	jmp	short gt9
gt8:	cmp	ax,ERR_NOFILE
	stc
	jne	gt9
	mov	ax,ERR_NOPATH
gt9:	pop	ds
	pop	si
	pop	bx
	ret
ENDPROC	get_parent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fmt_name
;
; Format the name of a DIRENT as "NAME.EXT" (no null terminator).
;
; Inputs:
;	DS:SI -> DIRENT
;	ES:DI -> buffer
;
; Outputs:
;	ES:DI -> end of name in buffer
;
; Modifies:
;	AX, CX, SI, DI
;
DEFPROC	fmt_name,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	mov	cx,8
fn1:	lodsb
	cmp	al,' '
	je	fn2
	stosb
fn2:	loop	fn1
	mov	al,[si]
	cmp	al,' '
	je	fn9
	mov	al,'.'
	stosb
	mov	cl,3
fn3:	lodsb
	cmp	al,' '
	je	fn4
	stosb
fn4:	loop	fn3
fn9:	ret
ENDPROC	fmt_name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_chdir (REG_AH = 3Bh)
;
; Inputs:
;	REG_DS:REG_DX -> path of new current directory
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error code (eg, ERR_NOPATH)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	dsk_chdir,DOS
	LOCK_SCB
	call	get_dirpath		; DL = drive #, DI -> BPB
	jc	cd8
	call	get_dir			; AX = directory
	jc	cd8
	xchg	cx,ax			; CX = directory
	mov	al,dl
	call	get_cdir		; BX -> drive's current directory
	mov	es:[bx],cx
	jmp	short cd9
cd8:	mov	[bp].REG_AX,ax
cd9:	UNLOCK_SCB
	ret
ENDPROC	dsk_chdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_dirpath
;
; Use get_path to parse the path at REG_DS:REG_DX (eg, for dsk_chdir).
;
; Inputs:
;	REG_DS:REG_DX -> path
;
; Outputs:
;	Same as get_path (and BX -> active SCB, ES = DOS)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	get_dirpath,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cs
	pop	es
	ASSUME	ES:DOS
	mov	si,[bp].REG_DX
	mov	ds,[bp].REG_DS		; DS:SI -> path
	mov	bx,[scb_active]
	lea	di,[bx].SCB_FILENAME
	mov	ah,0			; AH = 0 (no wildcards)
	jmp	get_path		; DL = drive #, DI -> BPB
ENDPROC	get_dirpath

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_getcwd (REG_AH = 47h)
;
; Inputs:
;	REG_DL = drive # (0 for default, 1 for A:, and so on)
;	REG_DS:REG_SI -> 64-byte buffer
;
; Outputs:
;	On success, carry clear, and the buffer contains the path of the
;	current directory, without a drive or leading SCB_PATHCHAR (so the
;	root directory is an empty string)
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; Notes:
;	We don't store paths, just the 1st cluster of each current directory,
;	so we rebuild the path (from the end of the buffer back) by walking
;	".." entries up to the root, finding each subdirectory's name in its
;	parent along the way.
;
DEFPROC	dsk_getcwd,DOS
	LOCK_SCB
	mov	bx,[scb_active]
	dec	dl			; drive # specified?
	jge	cw1			; yes
	mov	dl,cs:[bx].SCB_CURDRV
cw1:	mov	ax,ERR_BADDRIVE
	cmp	dl,[bpb_total]		; valid drive #?
	cmc
	jc	cw8			; no
	mov	al,dl
	call	get_cdir		; BX -> drive's current directory
	mov	cx,cs:[bx]		; CX = current directory
	jcxz	cw1a			; the root doesn't require a fresh BPB
	call	get_bpb			; DI -> BPB
	jc	cw8
cw1a:	mov	dx,cx			; DX = current directory
	mov	bx,[bp].REG_SI
	add	bx,63			; BX -> last byte of buffer
	mov	es,[bp].REG_DS
	ASSUME	ES:NOTHING
	mov	byte ptr es:[bx],0
cw2:	push	cs
	pop	es
	ASSUME	ES:DOS
	test	dx,dx			; at the root yet?
	jz	cw6			; yes
	call	get_parent		; AX = parent, CX = length of name
	jc	cw8
	sub	bx,cx
	dec	bx			; BX -> room for SCB_PATHCHAR and name
	cmp	bx,[bp].REG_SI		; is there enough room?
	jb	cw7			; no
	xchg	dx,ax			; DX = parent
	push	di
	mov	di,bx
	mov	es,[bp].REG_DS
	ASSUME	ES:NOTHING
	mov	si,[scb_active]
	mov	al,cs:[si].SCB_PATHCHAR
	stosb
	lea	si,[si].SCB_FILENAME
	REPS	MOVS,ES,CS,BYTE
	pop	di
	jmp	cw2

cw6:	mov	es,[bp].REG_DS		; ES:BX -> path
	cmp	byte ptr es:[bx],0	; empty?
	je	cw6a			; yes
	inc	bx			; skip the leading SCB_PATHCHAR
cw6a:	mov	di,[bp].REG_SI		; ES:DI -> start of buffer
	lea	cx,[di+64]
	sub	cx,bx			; CX = length of path (incl. null)
	mov	si,bx
	push	es
	pop	ds			; DS:SI -> path
	rep	movsb			; (carry is clear)
	jmp	short cw9

cw7:	mov	ax,ERR_NOPATH
	stc
cw8:	mov	[bp].REG_AX,ax
cw9:	UNLOCK_SCB
	ret
ENDPROC	dsk_getcwd

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
; Notes:
;	If the buffer currently contains modified data for another LBA,
;	that data is written (see write_buffer) before the buffer is reused.
;
DEFPROC	read_buffer,DOS
	ASSUMES	<DS,BIOS>,<ES,NOTHING>
	cmp	[si].BUF_DRIVE,al
	jne	rb1
	cmp	[si].BUF_LBA,dx
	jne	rb1
	add	si,size BUFHDR
	jmp	short rb9
rb1:	call	write_buffer		; write the buffer first if it's dirty
	jc	rb9
	push	bx
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
	jnc	rb8
	sub	si,size BUFHDR
	mov	[si].BUF_LBA,0		; invalidate the buffer on error
	stc
rb8:	pop	es
	pop	di
	pop	dx
	pop	cx
	pop	bx
rb9:	ret
ENDPROC	read_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_buffer
;
; Writes the buffer's data to disk if the buffer is dirty (ie, BUF_DIRTY is
; set).  If the buffer contains a sector from the first FAT, then the data is
; also written to the corresponding sector of every other FAT.
;
; Inputs:
;	DS:SI -> BUFHDR
;
; Outputs:
;	On success, carry clear (AX preserved)
;	On failure, carry set, AX = device error code (and buffer invalidated)
;
; Modifies:
;	AX
;
DEFPROC	write_buffer,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	cmp	[si].BUF_DIRTY,0	; any modified data?
	je	wb9a			; no (and carry is clear)
	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	push	bp
	push	es
	mov	al,[si].BUF_DRIVE
	mov	ah,size BPBEX
	mul	ah			; AX = BPB offset
	mov	di,cs:[bpb_table].OFF
	add	di,ax			; DI -> BPB
	ASSERT	STRUCT,cs:[di],BPB
	mov	bx,[si].BUF_LBA		; BX = LBA
	mov	bp,1			; BP = # copies to write (default is 1)
	mov	ax,bx
	sub	ax,cs:[di].BPB_RESSECS
	cmp	ax,cs:[di].BPB_FATSECS	; is the LBA within the first FAT?
	jae	wb1			; no
	mov	al,cs:[di].BPB_FATS	; yes, so write every copy of the FAT
	cbw
	xchg	bp,ax

wb1:	mov	[si].BUF_DIRTY,0
wb2:	mov	al,[si].BUF_DRIVE
	mov	ah,DDC_WRITE
	mov	cx,[si].BUF_SIZE	; CX = byte count
	sub	dx,dx			; DX = offset (0)
	push	si
	push	di
	add	si,size BUFHDR		; DS:SI -> data buffer
	les	di,cs:[di].BPB_DEVICE
	call	dev_request
	pop	di
	pop	si
	jc	wb8
	add	bx,cs:[di].BPB_FATSECS	; advance LBA to the next FAT copy
	dec	bp			; any more copies?
	jnz	wb2			; yes
	jmp	short wb9		; no (and carry is clear)

wb8:	mov	[si].BUF_LBA,0		; invalidate the buffer on error
	stc

wb9:	pop	es
	pop	bp
	pop	di
	pop	dx
	pop	cx
	pop	bx
	jc	wb9b
	pop	ax			; restore AX on success
wb9a:	ret
wb9b:	inc	sp			; discard AX without affecting carry
	inc	sp
	ret
ENDPROC	write_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; flush_buffers
;
; Writes all dirty buffers containing data for the specified drive.
;
; Inputs:
;	AL = drive # (-1 for all drives)
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = device error code
;
; Modifies:
;	AX
;
DEFPROC	flush_buffers,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cx
	push	dx
	push	si
	push	ds
	mov	cl,al			; CL = drive #
	mov	dx,cs:[buf_head]
	mov	ds,dx			; DX = head
	sub	si,si			; DS:SI -> BUFHDR
fb1:	test	cl,cl
	jl	fb2
	cmp	[si].BUF_DRIVE,cl
	jne	fb3
fb2:	call	write_buffer
	jc	fb9
fb3:	cmp	[si].BUF_NEXT,dx	; looped back around?
	je	fb9			; yes (and carry is clear)
	mov	ds,[si].BUF_NEXT
	jmp	fb1
fb9:	pop	ds
	pop	si
	pop	dx
	pop	cx
	ret
ENDPROC	flush_buffers

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_buffers
;
; Checks for any dirty buffers containing data for the specified drive.
;
; Inputs:
;	AL = drive #
;
; Outputs:
;	ZF clear if there are dirty buffers for the drive, set if not
;	(carry is always clear)
;
; Modifies:
;	None
;
DEFPROC	chk_buffers,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	dx
	push	ds
	mov	dx,cs:[buf_head]
	mov	ds,dx			; DX = head
cb1:	cmp	ds:[BUF_DRIVE],al
	jne	cb2
	test	ds:[BUF_DIRTY],0FFh	; is this buffer dirty?
	jnz	cb9			; yes (ZF clear, carry clear)
cb2:	cmp	ds:[BUF_NEXT],dx	; looped back around?
	je	cb8			; yes
	mov	ds,ds:[BUF_NEXT]
	jmp	cb1
cb8:	test	al,0			; set ZF and clear carry
cb9:	pop	ds
	pop	dx
	ret
ENDPROC	chk_buffers

DOS	ends

	end
