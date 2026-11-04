;
; BASIC-DOS File Services
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

	EXTWORD	<dos_data>
	EXTNEAR	<dev_request,scb_release,resize_file>
	EXTNEAR	<get_bpb,get_cln,get_dirent,read_buffer,flush_buffers>
	EXTNEAR	<alloc_cln,free_clns,chk_volopen,walk_cln,advance_cln>
	EXTNEAR	<vol_io,drv_flush>
	EXTNEAR	<dir_lba,get_dircln,merge_clns>
	EXTNEAR	<get_cdir,get_dirpath,new_buffer,write_buffer,zap_buffers>

	EXTBYTE	<scb_locked>
	EXTWORD	<scb_active>
	EXTLONG	<clk_ptr,scb_table>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sfb_commit
;
; Update the DIRENT for a modified file (ie, its time, date, first cluster,
; and size), and then write all modified buffers for the file's drive.  The
; time and date are the current time and date, unless they were set (see
; hdl_time).
;
; Inputs:
;	BX -> SFB
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX
;
DEFPROC	sfb_commit,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	mov	es,cs:[dos_data]
	ASSUME	ES:DOS
;
; Copy the SFB's directory, drive #, and filename to SCB_DIRCLN and
; SCB_FILENAME, so that get_dirent can verify the DIRENT at SFB_DIRNUM.
;
	mov	di,[scb_active]
	mov	ax,[bx].SFB_DIRCLN
	mov	[di].SCB_DIRCLN,ax
	lea	di,[di].SCB_FILENAME	; ES:DI -> SCB_FILENAME
	mov	al,[bx].SFB_DRIVE
	stosb
	mov	si,bx			; DS:SI -> SFB_NAME
	mov	cx,size SFB_NAME
	rep	movsb
	mov	dl,al			; DL = drive #
	call	get_bpb			; DI -> BPB
	jc	scm9
	push	bx
	mov	ax,[bx].SFB_DIRNUM	; AX = DIRENT #
	mov	bl,0			; BL = attributes (none)
	call	get_dirent		; DS:SI -> DIRENT
	pop	bx
	jc	scm9
	ASSUME	DS:BIOS
	call	get_dtime		; AX = time, DX = date
	test	es:[bx].SFB_FLAGS,SFBF_DTSET
	jz	scm1			; they weren't set
	mov	ax,es:[bx].SFB_TIME
	mov	dx,es:[bx].SFB_DATE
scm1:	mov	es:[bx].SFB_TIME,ax
	mov	es:[bx].SFB_DATE,dx
	mov	[si].DIR_TIME,ax
	mov	[si].DIR_DATE,dx
	mov	ax,es:[bx].SFB_CLN
	mov	[si].DIR_CLN,ax
	mov	ax,es:[bx].SFB_SIZE.LOW
	mov	[si].DIR_SIZE.LOW,ax
	mov	ax,es:[bx].SFB_SIZE.HIW
	mov	[si].DIR_SIZE.HIW,ax
	or	[si].DIR_ATTR,DIRATTR_ARCHIVE
	mov	ds:[BUF_DIRTY],1
	and	es:[bx].SFB_FLAGS,NOT SFBF_DIRTY
	mov	al,es:[bx].SFB_DRIVE
	call	flush_buffers		; write the DIRENT (and FAT)

scm9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	sfb_commit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_file (called by sfb_write for block devices)
;
; Inputs:
;	AL = I/O mode (not used)
;	BX -> SFB
;	CX = byte count
;	DS:SI -> data buffer
;
; Outputs:
;	On success, carry clear, AX = bytes written
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, BX, DX, DI, ES
;
; Notes:
;	Like PC DOS, running out of disk space is not treated as an error;
;	the number of bytes returned will simply be less than requested.
;
DEFPROC	write_file,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cx
	push	si
	push	ds
	mov	word ptr [bp].TMP_AX,0	; use TMP_AX to accumulate bytes written
	mov	[bp].TMP_ES,ds
	mov	[bp].TMP_DX,si		; TMP_ES:TMP_DX -> data buffer
	mov	ds,cs:[dos_data]
	ASSUME	DS:DOS
	LOCK_SCB
	mov	ax,ERR_ACCDENIED
	test	[bx].SFB_MODE,MODE_ACC_WO OR MODE_ACC_RW
	jz	wf7			; file was not opened for writing
	mov	dl,[bx].SFB_DRIVE
	call	get_bpb			; DI -> BPB if no error
	jnc	wf0
	jmp	short wf9
;
; Writes to a volume (see chk_volume) go straight to its sectors, and then
; any buffers for the drive are discarded (since they may now be stale), and
; the SFB is marked dirty, so that the BPB is rebuilt on close.
;
wf0:	test	[bx].SFB_ATTR,DIRATTR_VOLUME
	jz	wf0a			; not a volume
	mov	ah,DDC_WRITE
	call	vol_io
	jc	wf9
	push	ax
	mov	al,[bx].SFB_DRIVE
	call	drv_flush
	pop	ax
	or	[bx].SFB_FLAGS,SFBF_DIRTY ; (and carry is clear)
	jmp	short wf9

wf7:	stc
	jmp	short wf9
wf8:	mov	ax,[bp].TMP_AX		; AX = total bytes written
	clc
wf9:	pop	ds
	ASSUME	DS:NOTHING
	pop	si
	pop	cx
	UNLOCK_SCB_RET

	ASSUME	DS:DOS
;
; As in PC DOS, a zero-length write truncates (or extends) the file to CURPOS.
;
wf0a:	test	cx,cx			; zero-length write?
	jnz	wf1			; no
	call	resize_file		; yes, so set the file's size to CURPOS
	jnc	wf8			; (with 0 bytes written)
	jmp	wf9

wf1:	jcxz	wf8			; nothing (more) to write
	call	get_wcln		; DX = CLN for CURPOS
	jnc	wf2
	cmp	ax,ERR_DISKFULL		; out of disk space?
	je	wf8			; yes, return the bytes written so far
	jmp	wf7
;
;
; Like PC DOS, allocate any clusters the rest of the request needs first (by
; finding the CLN of its last byte), so that the ones that are next to each
; other on disk can be written with one request (see clns_request).  An error
; isn't reported until we need a cluster that couldn't be allocated (see wf1).
;
wf2:	push	dx			; save CLN for CURPOS
	push	[bx].SFB_CURPOS.LOW
	push	[bx].SFB_CURPOS.HIW
	mov	ax,cx
	dec	ax
	add	[bx].SFB_CURPOS.LOW,ax
	adc	[bx].SFB_CURPOS.HIW,0
	mov	[bx].SFB_CURCLN,0
	call	get_wcln
	pop	[bx].SFB_CURPOS.HIW
	pop	[bx].SFB_CURPOS.LOW
	pop	[bx].SFB_CURCLN
	push	cx			; save byte count
	mov	ah,DDC_WRITE
	call	clns_request		; DX = bytes written (if no error)
	pop	cx			; restore byte count
	jc	wf9
;
; Time for some bookkeeping: adjust the SFB's CURPOS by DX, and if CURPOS
; is now beyond SIZE, then update SIZE as well.
;
	add	[bx].SFB_CURPOS.LOW,dx
	adc	[bx].SFB_CURPOS.HIW,0
	add	[bp].TMP_AX,dx		; update accumulation of bytes written
	add	[bp].TMP_DX,dx		; update data buffer offset
	or	[bx].SFB_FLAGS,SFBF_DIRTY
	mov	ax,[bx].SFB_CURPOS.LOW
	mov	si,[bx].SFB_CURPOS.HIW
	cmp	si,[bx].SFB_SIZE.HIW
	jb	wf5
	ja	wf4
	cmp	ax,[bx].SFB_SIZE.LOW
	jbe	wf5
wf4:	mov	[bx].SFB_SIZE.LOW,ax
	mov	[bx].SFB_SIZE.HIW,si
;
; As in sfb_read, if CURPOS is now at a cluster boundary, advance SFB_CURCLN
; to the next cluster, or zero it if there is no next cluster (get_wcln will
; extend the chain if and when another write occurs).
;
wf5:	call	advance_cln
	sub	cx,dx			; reduce the write count
	jmp	wf1			; and keep writing clusters
ENDPROC	write_file

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clns_request
;
; Issue a read or write request for a file's next bytes, up to CX: whatever's
; in the current cluster, and in any clusters that immediately follow it on
; disk, so that one request can transfer them all (see merge_clns).
;
; Inputs:
;	AH = DDC_READ or DDC_WRITE
;	BX -> SFB (SFB_CURCLN = CLN for CURPOS)
;	CX = byte count
;	DI -> BPB
;	TMP_ES:TMP_DX -> data buffer
;
; Outputs:
;	On success, carry clear, DX = bytes transferred, SFB_CURCLN = last CLN
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	clns_request,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	bx
	push	di
	push	es
	push	ax			; save the request
	mov	dx,[bx].SFB_CURPOS.LOW
	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	and	dx,ax			; DX = offset within current cluster
	call	merge_clns		; CX = bytes to transfer, SI = last CLN
	pop	ax
	push	si			; save last CLN
	mov	bx,[bx].SFB_CURCLN

	IFDEF	MAXDEBUG
	DPRINTF	<"Accessing cluster %#05x...\r\n">,bx
	ENDIF

	sub	bx,2
	jb	cq8			; invalid cluster #
	push	cx
	mov	cl,[di].BPB_CLUSLOG2
	shl	bx,cl
	pop	cx
	add	bx,[di].BPB_LBADATA	; BX = LBA
	call	file_request
	mov	dx,cx			; DX = bytes transferred (if no error)
cq8:	pop	si
	pop	es
	pop	di
	pop	bx
	jc	cq9
	mov	[bx].SFB_CURCLN,si
cq9:	ret
ENDPROC	clns_request

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; file_request
;
; Issue a file or volume read/write request using the drive and device from
; the BPB and the data buffer saved in the caller's temporary workspace.
;
; A read of part of a sector goes through the disk buffers (as file data, so
; it can't be mistaken for a directory sector; see read_buffer), and whole
; sectors go straight to the driver, which only reads whole sectors.  Writes
; are always written through, so any buffered copy of those sectors is now
; stale.  File data is never dirty, so it's safe to read around it.
;
; Inputs:
;	AH = DDC_READ or DDC_WRITE
;	BX = LBA
;	CX = byte count
;	DX = offset within LBA
;	DS:DI -> BPB
;	TMP_ES:TMP_DX -> data buffer
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, DX, SI, DI, ES
;
DEFPROC	file_request,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
	cmp	ah,DDC_READ		; reading?
	je	fq2			; yes
;
; Any buffered copy of these sectors is about to be stale.  The count must be
; exact, because zap_buffers discards unwritten data, and the next sector could
; be part of a directory, with changes in a buffer.
;
	push	cx
	push	dx
	mov	si,cx
	dec	si
	add	si,dx			; SI = offset of the last byte
	rcr	si,1
	mov	cl,8
	shr	si,cl
	inc	si
	mov	cx,si			; CX = # LBAs
	mov	dx,bx			; DX = 1st LBA
	mov	al,cs:[di].BPB_DRIVE
	call	zap_buffers
	pop	dx
	pop	cx
fq1:	mov	al,cs:[di].BPB_DRIVE
	les	di,cs:[di].BPB_DEVICE
	push	ds
	mov	si,[bp].TMP_DX
	mov	ds,[bp].TMP_ES		; DS:SI -> data buffer
	call	dev_request
	pop	ds
	ret

fq2:	push	ds
	push	bx
	push	cx
	push	[bp].TMP_DX
	mov	al,dh
	shr	al,1
	cbw
	add	bx,ax			; BX = LBA of the first sector
	and	dh,1			; DX = offset within it
fq3:	jcxz	fq9			; nothing left (and carry is clear)
	test	dx,dx			; at the start of a sector?
	jnz	fq4			; no
	cmp	ch,512 SHR 8		; at least one whole sector?
	jb	fq4			; no
	push	cx
	push	di
	and	cx,NOT 511		; CX = bytes in whole sectors
	mov	ah,DDC_READ
	call	fq1
	pop	di
	mov	si,cx			; SI = bytes in whole sectors
	pop	cx
	jc	fq9			; (AX = error code)
	add	[bp].TMP_DX,si
	sub	cx,si
	xchg	ax,si
	mov	al,ah
	shr	al,1
	cbw
	add	bx,ax			; BX = LBA of the next sector
	jmp	fq3

fq4:	mov	ax,512
	sub	ax,dx			; AX = bytes left in the sector
	cmp	ax,cx
	jbe	fq5
	mov	ax,cx			; AX = bytes to copy
fq5:	push	cx
	push	ax
	push	dx
	mov	dx,bx			; DX = LBA
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset FAT_BUFHDR + 1
	call	read_buffer		; DS:SI -> sector data
	pop	dx
	pop	cx			; CX = bytes to copy
	jc	fq8			; (AX = error code)
	add	si,dx
	push	di
	mov	es,[bp].TMP_ES
	mov	di,[bp].TMP_DX
	add	[bp].TMP_DX,cx
	mov	ax,cx
	rep	movsb
	pop	di
	pop	cx
	sub	cx,ax			; CX = bytes left (and carry is clear)
	inc	bx			; BX = LBA of the next sector
	sub	dx,dx			; DX = offset within it (carry clear)
	jmp	fq3

fq8:	pop	cx
fq9:	pop	[bp].TMP_DX
	pop	cx
	pop	bx
	pop	ds
	ret
ENDPROC	file_request

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_wcln (see also: find_cln in fat.asm)
;
; Find the CLN corresponding to CURPOS for writing, which means allocating
; the file's first cluster and/or extending its cluster chain as needed.
;
; Inputs:
;	BX -> SFB
;	DI -> BPB
;
; Outputs:
;	On success, carry clear, DX = CLN
;	On failure, carry set, AX = error code (eg, ERR_DISKFULL)
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	get_wcln,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	mov	dx,[bx].SFB_CURCLN
	mov	ax,dx
	sub	ax,2
	cmp	ax,[di].BPB_CLUSTERS	; is CURCLN a valid data cluster?
	jae	gw1			; no
	clc
	ret
;
; We have to walk the cluster chain (see walk_cln), allocating the file's
; first cluster beforehand if necessary, and then extending the chain if it
; ends before CURPOS.
;
gw1:	push	cx
	mov	dx,[bx].SFB_CLN		; DX = first CLN
	test	dx,dx			; does the file have any clusters yet?
	jnz	gw2			; yes
	call	alloc_cln		; DX = new CLN (with no previous CLN)
	jc	gw8
	mov	[bx].SFB_CLN,dx
	mov	[bx].SFB_CONTEXT,dx
gw2:	call	walk_cln		; DX = last CLN reached
	jc	gw8
	jcxz	gw8			; DX is CURPOS's CLN (carry clear)
	push	cx			; CX = # CLNs to add
gw3:	call	alloc_cln		; DX = new CLN (linked to DX)
	jc	gw7
	loop	gw3
	pop	cx
	add	[bx+SFB_HINTIDX],cx	; the new CLN is the new hint
	mov	[bx+SFB_HINTCLN],dx	; (and carry is clear)
	jmp	short gw8
gw7:	pop	cx
gw8:	pop	cx
	ret
ENDPROC	get_wcln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_dirent
;
; Find a free (ie, unused or deleted) DIRENT in the SCB_DIRCLN directory, and
; initialize it with the name in SCB_FILENAME, the specified attributes, the
; current time and date, and zero for both the first cluster and file size.
;
; Inputs:
;	BL = attributes
;	DI -> BPB
;	SCB_FILENAME contains the filename
;
; Outputs:
;	On success, carry clear, DS:SI -> DIRENT, AX = DIRENT #
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, DX, SI, DS
;
DEFPROC	add_dirent,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	sub	dx,dx			; DX = relative directory sector #
	sub	cx,cx			; CX = DIRENT #
ad1:	call	dir_lba			; AX = LBA
	jc	ad7
	push	dx
	xchg	dx,ax			; DX = LBA
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset DIR_BUFHDR
	call	read_buffer		; DS:SI -> directory sector
	pop	dx
	jnc	ad1a
	ret
ad1a:	mov	ax,cs:[di].BPB_SECBYTES
	add	ax,si			; AX -> end of sector data
ad2:	cmp	byte ptr [si],DIRENT_END
	je	ad8
	cmp	byte ptr [si],DIRENT_DELETED
	je	ad8
	add	si,size DIRENT
	inc	cx
	cmp	si,ax
	jb	ad2
	inc	dx			; advance to the next directory sector
	jmp	ad1
;
; The directory is full, so if it's a subdirectory, extend it with another
; cluster (DX is already the relative sector # of the new cluster).
;
ad7:	cmp	ax,ERR_NOFILE		; is the directory full?
	stc
	jne	ad9			; no, it's some other error
	call	get_dircln
	test	ax,ax			; is it the root directory?
	jz	ad7c			; yes, so it can't grow
	push	dx
	xchg	dx,ax			; DX = 1st cluster
ad7a:	mov	si,dx			; SI = current cluster
	call	get_cln			; DX = next cluster
	jc	ad7b
	mov	ax,dx
	sub	ax,2
	cmp	ax,cs:[di].BPB_CLUSTERS	; is the next cluster valid?
	jb	ad7a			; yes
	mov	dx,si			; DX = last cluster
	call	alloc_cln		; DX = new cluster (linked to the last)
	jc	ad7b
	call	init_cln		; zero the new cluster
ad7b:	pop	dx
	jnc	ad1			; search the new cluster
	ret
ad7c:	mov	ax,ERR_ACCDENIED
	stc
	ret

ad8:	push	cx			; save DIRENT #
	push	si			; save DIRENT address
	push	di
	push	es
	push	ds
	pop	es
	ASSUME	ES:BIOS
	mov	di,si			; ES:DI -> DIRENT
	mov	si,[scb_active]
	lea	si,[si].SCB_FILENAME+1	; CS:SI -> filename
	mov	cx,size FCB_NAME
	REPS	MOVS,ES,CS,BYTE		; DIR_NAME
	mov	al,bl
	stosb				; DIR_ATTR
	sub	ax,ax
	mov	cx,size DIR_PAD SHR 1
	rep	stosw			; DIR_PAD
	call	get_dtime		; AX = time, DX = date
	stosw				; DIR_TIME
	xchg	ax,dx
	stosw				; DIR_DATE
	sub	ax,ax
	stosw				; DIR_CLN
	stosw				; DIR_SIZE.LOW
	stosw				; DIR_SIZE.HIW
	mov	ds:[BUF_DIRTY],1
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	pop	si			; DS:SI -> DIRENT
	pop	ax			; AX = DIRENT # (and carry is clear)
ad9:	ret
ENDPROC	add_dirent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_cln
;
; Zero every sector of a new directory cluster, using a single DIR buffer (see
; new_buffer): the buffer is zeroed once and then written to each sector after
; the first by changing only its LBA, so that no other buffers are evicted
; (any old copies of the sectors are discarded first; see zap_buffers).
; The buffer is left holding the cluster's first sector (marked dirty).
;
; Inputs:
;	DX = CLN
;	DI -> BPB
;
; Outputs:
;	On success, carry clear, DS:SI -> the 1st sector's data
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, SI, DS
;
DEFPROC	init_cln,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	cx
	push	dx
	push	di
	push	es
	xchg	ax,dx
	sub	ax,2
	mov	cl,cs:[di].BPB_CLUSLOG2
	shl	ax,cl
	add	ax,cs:[di].BPB_LBADATA	; AX = cluster's 1st LBA
	xchg	dx,ax			; DX = LBA
	mov	al,cs:[di].BPB_DRIVE
	mov	cl,cs:[di].BPB_CLUSSECS
	mov	ch,0			; CX = # sectors
	call	zap_buffers		; discard any old copies of the sectors
	mov	si,offset DIR_BUFHDR
	mov	ah,0
	call	new_buffer		; DS:SI -> buffer for LBA
	jc	ic9
	ASSUME	DS:NOTHING
	push	di
	push	ds
	pop	es
	mov	di,si
	mov	cx,ds:[BUF_SIZE]
	shr	cx,1
	sub	ax,ax			; (and carry is clear)
	rep	stosw
	pop	di
	mov	cl,cs:[di].BPB_CLUSSECS	; CX = # sectors
	sub	si,si			; DS:SI -> BUFHDR
	push	dx			; save 1st LBA
	jmp	short ic2
ic1:	inc	dx
	mov	ds:[BUF_LBA],dx
	call	write_buffer		; write the zeroed sector
	jc	ic8
ic2:	mov	ds:[BUF_DIRTY],1
	loop	ic1
ic8:	pop	dx
	jc	ic9
	mov	ds:[BUF_LBA],dx		; buffer is the 1st sector again
	mov	si,size BUFHDR		; DS:SI -> data
ic9:	pop	es
	pop	di
	pop	dx
	pop	cx
	ret
ENDPROC	init_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_mkdir (REG_AH = 39h)
;
; Inputs:
;	REG_DS:REG_DX -> path of new directory
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	dsk_mkdir,DOS
	LOCK_SCB
	call	chk_dirname		; DL = drive #, DI -> BPB
	jc	md0
	push	bx
	mov	ax,-1
	mov	bl,0			; BL = 0 (any attributes)
	call	get_dirent		; does the name already exist?
	pop	bx
	jnc	md0a			; yes
	cmp	ax,ERR_NOFILE
	je	md1
	stc
md0:	jmp	md8
md0a:	jmp	md6
;
; Allocate a cluster for the new directory, initialize it (with "." and ".."
; entries), and write it and the FAT, before adding the new directory's DIRENT
; to the parent directory, so that a crash can't leave a DIRENT that refers to
; a free (or uninitialized) cluster; at worst, the cluster will be lost.  If we
; can't add the DIRENT, the cluster is released.
;
md1:	sub	dx,dx
	call	alloc_cln		; DX = new CLN
	jc	md8
	push	dx			; save the new CLN
	mov	bx,dx			; BX = new CLN
	call	get_dircln
	xchg	cx,ax			; CX = parent CLN
	call	init_cln		; DS:SI -> new directory's 1st sector
	jc	md7
;
; Fill in the "." entry (with the new CLN) and ".." entry (with the
; parent CLN).
;
	push	di
	push	es
	push	ds
	pop	es
	ASSUME	ES:BIOS
	mov	di,si			; ES:DI -> 1st DIRENT
	call	get_dtime		; AX = time, DX = date
	mov	si,1			; SI = # dots in the name
md3:	push	ax
	push	cx
	mov	cx,si
	mov	al,'.'
	rep	stosb
	mov	cx,size FCB_NAME
	sub	cx,si
	mov	al,' '
	rep	stosb			; DIR_NAME
	mov	al,DIRATTR_SUBDIR
	stosb				; DIR_ATTR
	add	di,size DIR_PAD
	pop	cx
	pop	ax
	stosw				; DIR_TIME
	xchg	ax,dx
	stosw				; DIR_DATE
	xchg	ax,dx
	xchg	ax,bx
	stosw				; DIR_CLN
	xchg	ax,bx
	add	di,size DIR_SIZE
	mov	bx,cx			; BX = parent CLN (for "..")
	inc	si
	cmp	si,2
	jbe	md3
	pop	es
	ASSUME	ES:NOTHING
	pop	di
	mov	al,cs:[di].BPB_DRIVE
	call	flush_buffers		; write the new directory and the FAT
	jc	md7
;
; Now add the new directory's DIRENT to the parent directory.
;
	mov	bl,DIRATTR_SUBDIR
	call	add_dirent		; DS:SI -> new DIRENT
	jc	md7
	ASSUME	DS:BIOS
	pop	dx			; DX = new CLN
	mov	[si].DIR_CLN,dx
	mov	al,ds:[BUF_DRIVE]
	call	flush_buffers		; write the parent directory
	jnc	md9
	jmp	short md8
md7:	pop	dx			; DX = new CLN
	push	ax
	call	free_clns		; release the new cluster
	pop	ax
	stc
	jmp	short md8
md6:	mov	ax,ERR_ACCDENIED
	stc
md8:	mov	[bp].REG_AX,ax
md9:	UNLOCK_SCB_RET
ENDPROC	dsk_mkdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dsk_rmdir (REG_AH = 3Ah)
;
; Inputs:
;	REG_DS:REG_DX -> path of directory to remove
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, REG_AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; Notes:
;	The directory must be empty, and it can't be the current directory
;	of any session.
;
DEFPROC	dsk_rmdir,DOS
	LOCK_SCB
	call	chk_dirname		; DL = drive #, DI -> BPB
	jc	rd0
	push	bx
	mov	ax,-1
	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; DS:SI -> DIRENT, AX = DIRENT #
	pop	bx
	jnc	rd1
	cmp	ax,ERR_NOFILE
	stc
	jne	rd0
	mov	ax,ERR_NOPATH
rd0:	jmp	rd8
	ASSUME	DS:BIOS
rd1:	push	[si].DIR_CLN		; save the directory
	push	ax			; save its DIRENT #
	call	get_dircln
	push	ax			; save its parent
	mov	si,sp
	mov	cx,ss:[si+4]		; CX = directory
;
; Make sure the directory isn't the current directory of any session.
;
	mov	bx,[scb_table].OFF
rd2:	push	bx
	mov	al,dl			; AL = drive #
	call	get_cdir		; BX -> session's current directory
	cmp	cs:[bx],cx
	pop	bx
	mov	ax,ERR_CURDIR
	stc
	je	rd7
	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	rd2
;
; Make sure the directory is empty (except for "." and "..").
;
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,cx
	push	di
	lea	di,[bx].SCB_FILENAME+1
	mov	al,'?'
	mov	cx,size FCB_NAME
	rep	stosb
	pop	di
	sub	ax,ax			; start with DIRENT # 0
rd3:	mov	bl,0			; BL = 0 (any attributes)
	call	get_dirent		; DS:SI -> DIRENT, AX = DIRENT #
	jc	rd4
	inc	ax			; AX = next DIRENT #
	cmp	[si].DIR_NAME,'.'	; "." or ".."?
	je	rd3			; yes
	mov	ax,ERR_ACCDENIED	; no, so the directory isn't empty
	stc
	jmp	short rd7
rd4:	cmp	ax,ERR_NOFILE		; did we run out of entries?
	stc
	jne	rd7			; no, some other error
;
; Find its DIRENT in the parent again (using the "?" name and its DIRENT #),
; delete it, and then free the directory's clusters.
;
	pop	ax			; AX = parent
	mov	bx,[scb_active]
	mov	es:[bx].SCB_DIRCLN,ax
	pop	ax			; AX = DIRENT #
	mov	bl,DIRATTR_SUBDIR
	call	get_dirent		; DS:SI -> DIRENT
	pop	dx			; DX = directory
	jc	rd8
	mov	[si].DIR_NAME,DIRENT_DELETED
	mov	ds:[BUF_DIRTY],1
	call	free_clns		; free the directory's clusters
	jc	rd8
	mov	al,ds:[BUF_DRIVE]
	call	flush_buffers		; write the modified DIRENT and FAT
	jnc	rd9
	jmp	short rd8
rd7:	pop	cx			; discard the saved values
	pop	cx			; (without affecting carry)
	pop	cx
rd8:	mov	[bp].REG_AX,ax
rd9:	UNLOCK_SCB_RET
ENDPROC	dsk_rmdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_dirname
;
; Parse the path at REG_DS:REG_DX for dsk_mkdir or dsk_rmdir, whose final
; name can't be blank, ".", or "..".
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
DEFPROC	chk_dirname,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	call	get_dirpath		; DL = drive #, DI -> BPB
	jc	cn9
	ASSUME	ES:DOS
	mov	al,dl
	call	chk_volopen		; is the volume open?
	jc	cn9			; yes
	mov	al,es:[bx].SCB_FILENAME+1
	cmp	al,' '			; blank?
	je	cn8			; yes
	cmp	al,'.'			; "." or ".."?
	clc
	jne	cn9			; no
cn8:	mov	ax,ERR_ACCDENIED
	stc
cn9:	ret
ENDPROC	chk_dirname

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_dtime
;
; Get the current time and date in "packed" DIRENT format (see DIR_TIME and
; DIR_DATE in disk.inc).
;
; Inputs:
;	None
;
; Outputs:
;	AX = time
;	DX = date
;
; Modifies:
;	AX, DX
;
DEFPROC	get_dtime,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	di
	push	es
	les	di,cs:[clk_ptr]
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_GETTIME
	call	dev_request		; DX = time
	push	dx
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_GETDATE
	call	dev_request		; DX = date
	pop	ax			; AX = time
	pop	es
	pop	di
	ret
ENDPROC	get_dtime

DOS	ends

	end
