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

	EXTNEAR	<dev_request,name_fcb,get_path,fmt_name,get_cln>
	EXTNEAR	<read_buffer,flush_buffers,zap_buffers,chk_buffers,scb_release>
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
	push	cx
	push	dx
	sub	dx,dx			; DX = 1st LBA
	mov	cx,-1			; CX = # LBAs (all)
	call	zap_buffers
	pop	dx
	pop	cx
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
; of calling get_path, let name_fcb copy the name to the FILENAME buffer;
; FCBs always refer to the drive's current directory.
;
	cmp	ah,10h
	jne	cf3
	call	name_fcb		; DL = drive #, DI -> BPB
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
; new_bpb
;
; Same as get_bpb, except that the BPB is always rebuilt (eg, after a volume
; has been written by a program that may have reformatted it).
;
DEFPROC	new_bpb,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cx
	push	dx
	mov	ch,DDC_BUILDBPB		; CH = request
	jmp	short gb0
ENDPROC	new_bpb

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
	mov	ch,DDC_MEDIACHK		; CH = request
gb0:	mov	al,dl			; AL = drive #
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
	mov	ah,ch			; perform a MEDIACHK request
	cmp	ah,DDC_BUILDBPB		; unless new_bpb wants a new BPB
	je	gb7
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
; in a buffer, and we're not continuing from a specific DIRENT, then a nice
; optimization is to start with that sector (the most recently used one).
; We simply loop around to the top of the directory and stop when we reach
; this same sector again.
;
gd1:	call	get_dircln
	xchg	si,ax			; SI = directory
	mov	al,es:[di].BPB_DRIVE	; AL = drive #
	mov	dx,es:[buf_head]
	mov	ds,dx			; DX = head
	ASSUME	DS:NOTHING
gd1a:	cmp	ds:[BUF_TYPE],(offset DIR_BUFHDR - offset FAT_BUFHDR) AND 0FFh
	jne	gd1b			; not a DIR buffer
	cmp	ds:[BUF_DRIVE],al
	jne	gd1b
	cmp	ds:[BUF_LBA],0		; is the buffer valid?
	je	gd1b			; no
	cmp	ds:[BUF_DIRCLN],si	; is the buffer from this directory?
	jne	gd1b			; no
	mov	bp,ds:[BUF_DIRREL]	; yes, so start with its sector
	jmp	short gd2
gd1b:	cmp	ds:[BUF_NEXT],dx	; looped back around?
	je	gd2			; yes
	mov	ds,ds:[BUF_NEXT]
	jmp	gd1a
gd2:	mov	dx,bp
;
; End of initialization code, beginning of main loop.
;
gd3:	call	dir_lba			; AX = LBA of relative sector DX
	jc	gd6a
	push	dx
	xchg	dx,ax			; DX = LBA
	mov	al,es:[di].BPB_DRIVE
	mov	si,offset DIR_BUFHDR
	call	read_buffer		; AL = drive #, DX = LBA
	pop	dx
	jnc	gd4
	jmp	gd9
	ASSUME	DS:BIOS
gd4:	call	get_dircln		; record the buffer's directory
	mov	ds:[BUF_DIRCLN],ax
	mov	ds:[BUF_DIRREL],dx

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

gd6:	cmp	dx,bp			; did we already start over?
	jb	gd7b			; yes, so no match
	sub	dx,dx			; start over at the first sector

gd7:	sub	cx,cx			; start at offset zero of next sector
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

DOS	ends

	end
