;
; BASIC-DOS FAT Services
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
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<read_buffer,get_bpb,get_wcln,scb_release>
	EXTBYTE	<scb_locked>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fat_pos
;
; Locate a FAT entry for get_cln and set_cln.  FAT12 and FAT16 differ only
; in their entry width and mask; all sector and bit-offset arithmetic is shared.
; Start with CLN * 4 nibbles, then subtract CLN for FAT12's 3-nibble entries.
; Keep the offset in DX:AX so FAT16 entries beyond 64K remain addressable.
;
; Inputs:
;	DX = CLN
;	DI -> BPB
;
; Outputs:
;	DX = FAT LBA
;	BX = byte offset within sector
;	CL = shift within the first byte (0 or 4)
;	BP = entry mask (0FFFh or FFFFh)
;
; Modifies:
;	BX, CX, DX, BP (AX preserved for set_cln)
;
DEFPROC	fat_pos,DOS
	push	ax
	mov	ax,dx
	mov	bx,dx
	sub	dx,dx
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1			; DX:AX = CLN * 4 nibbles (FAT16)
	mov	bp,0FFFh
	cmp	cs:[di].BPB_CLUSTERS,CLN_FAT12 ; fewer than 4085 clusters means FAT12
	jb	fp1
	mov	bp,0FFFFh
	sub	bx,bx			; FAT16 keeps all 4 nibbles
fp1:	sub	ax,bx
	sbb	dx,0			; FAT12 subtracts CLN, leaving CLN * 3 nibbles
	mov	bx,ax			; save low offset bits for byte and nibble offsets
	mov	cl,10
	shr	ax,cl			; 1024 nibbles per sector
	mov	cl,6
	shl	dx,cl			; include the offset bits above bit 15
	or	dx,ax			; DX = FAT sector
	add	dx,cs:[di].BPB_RESSECS
	mov	cl,bl
	and	cl,1
	shl	cl,1
	shl	cl,1			; CL = bit offset within first byte (0 or 4)
	and	bx,03FFh		; nibble offset within sector
	shr	bx,1			; BX = byte offset within sector
	pop	ax
	ret
ENDPROC	fat_pos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_cln (see also: get_cln)
;
; For the CLN in DX, set its FAT entry to the value in AX, using the BPB at DI.
;
; The FAT sector (or sectors, if the entry straddles a sector boundary) is
; modified in a FAT buffer and marked dirty; it will be written to every FAT copy
; when the buffer is reused or flushed (see write_buffer).
;
; Inputs:
;	AX = new FAT entry value (set_cln masks to 12 bits on FAT12)
;	DX = CLN
;	DI -> BPB
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX
;
DEFPROC	set_cln,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	push	cx
	push	dx
	push	si
	push	bp
	push	ds
;
; Invalidate before changing the FAT, including a partially failed update.
;
	mov	cs:[di].BPB_FREECLNS,-1
	call	fat_pos			; BX = byte offset, CL = shift, BP = entry mask
	and	ax,bp			; mask the value to the FAT's entry width
	shl	ax,cl			; position its bits within the two bytes
	shl	bp,cl
	not	bp			; bits belonging to adjacent entries
	mov	cx,bp			; CX = bits to preserve in each byte
	mov	bp,ax			; BP = shifted value
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	jc	sc9
	mov	ax,bp
;
; Both FAT widths use the same byte updates.  Only FAT12 entries can cross
; a sector boundary, in which case read_buffer also writes the first sector.
;
	and	[si+bx],cl
	or	[si+bx],al
	mov	ds:[BUF_DIRTY],1
	inc	bx
	cmp	bx,512			; does the second byte belong to the next sector?
	jb	sc2
	push	ax
	inc	dx
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	pop	bx			; BX = shifted value (from AX)
	jc	sc9			; leave the buffer error in AX
	mov	ax,bx
	sub	bx,bx
sc2:	and	[si+bx],ch
	or	[si+bx],ah
	mov	ds:[BUF_DIRTY],1
	clc

sc9:	pop	ds
	ASSUME	DS:NOTHING
	pop	bp
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	set_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; alloc_cln
;
; Allocate a free cluster, mark it as the end of a chain, and if a previous
; CLN is specified, link the previous CLN to the new CLN.
;
; The search starts at BPB_NEXTCLN (the cluster after the last one allocated),
; wrapping around to the first cluster, so every cluster is still checked
; before the disk is considered full; BPB_NEXTCLN is reset whenever the BPB
; is rebuilt (eg, after a media change).
;
; Inputs:
;	DX = previous CLN (0 if none)
;	DI -> BPB
;
; Outputs:
;	On success, carry clear, DX = new CLN
;	On failure, carry set, AX = error code (eg, ERR_DISKFULL)
;
; Modifies:
;	AX, DX
;
DEFPROC	alloc_cln,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	push	cx
	mov	bx,dx			; BX = previous CLN
	mov	cx,cs:[di].BPB_CLUSTERS	; CX = # clusters to check
	mov	dx,cs:[di+BPB_NEXTCLN]	; DX = first CLN to check
ac1:	mov	ax,dx
	sub	ax,2
	cmp	ax,cs:[di].BPB_CLUSTERS	; is DX past the end (or unknown)?
	jb	ac1a			; no
	mov	dx,2			; yes, so wrap around to the first
ac1a:	push	dx
	call	get_cln			; DX = FAT entry for CLN
	jc	ac7
	test	dx,dx			; is the cluster free?
	pop	dx
	jz	ac2			; yes
	inc	dx			; no, advance to the next CLN
	loop	ac1
	mov	ax,ERR_DISKFULL
	stc
	jmp	short ac9
ac7:	pop	dx
	jmp	short ac9

ac2:	mov	ax,CLN_LAST
	call	set_cln			; mark new CLN as the end of a chain
	jc	ac9
	mov	ax,dx
	inc	ax
	mov	cs:[di+BPB_NEXTCLN],ax	; the next search starts after it
	test	bx,bx			; was a previous CLN specified?
	jz	ac9			; no (and carry is clear)
	mov	ax,dx			; AX = new CLN
	xchg	dx,bx			; DX = previous CLN, BX = new CLN
	call	set_cln			; link previous CLN to new CLN
	xchg	dx,bx			; DX = new CLN

ac9:	pop	cx
	pop	bx
	ret
ENDPROC	alloc_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; free_clns
;
; Free every cluster in the chain beginning with the specified CLN.
;
; Inputs:
;	DX = first CLN of chain (0 if none)
;	DI -> BPB
;
; Outputs:
;	On success, carry clear
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, DX
;
DEFPROC	free_clns,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	push	cx
	mov	cx,cs:[di].BPB_CLUSTERS	; CX = limit (in case of a bad chain)
fc1:	mov	ax,dx
	sub	ax,2
	cmp	ax,cs:[di].BPB_CLUSTERS	; is CLN a valid data cluster?
	jae	fc8			; no, so we're done
	mov	bx,dx			; BX = current CLN
	call	get_cln			; DX = next CLN
	jc	fc9
	xchg	dx,bx			; DX = current CLN, BX = next CLN
	mov	ax,CLN_FREE
	call	set_cln			; mark current CLN free
	jc	fc9
	mov	dx,bx			; DX = next CLN
	loop	fc1
fc8:	clc
fc9:	pop	cx
	pop	bx
	ret
ENDPROC	free_clns

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_cln
;
; Find the CLN corresponding to CURPOS (see walk_cln).
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
	call	walk_cln		; DX = CLN
	pop	cx
	ret
ENDPROC	find_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; walk_cln (for find_cln and get_wcln)
;
; Walk the cluster chain toward the cluster containing CURPOS, starting from
; the SFB's cluster hint, unless the hint is beyond that cluster, in which case
; we start from the file's first cluster (which the caller must ensure exists).
;
; The hint (SFB_HINTCLN) is a CLN known to be at cluster index SFB_HINTIDX in
; the file.  We update it here, and it follows sequential reads and writes (see
; next_hint), so seeks rarely require walking the chain from the beginning.
; Since it doesn't depend on CURPOS, seeks don't affect it, but like SFB_CLN,
; it's only valid as long as the chain isn't shortened (see resize_file).
;
; Inputs:
;	BX -> SFB
;	DI -> BPB
;
; Outputs:
;	On success, carry clear, DX = last CLN reached (which is also the new
;	hint), and CX = # clusters past DX still needed to reach CURPOS (zero
;	unless the chain ended first)
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	walk_cln,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	mov	ax,[bx].SFB_CURPOS.LOW
	mov	dx,[bx].SFB_CURPOS.HIW
	cmp	dx,[di].BPB_CLUSBYTES	; would the division overflow?
	jae	wc8			; yes (the position is far too large)
	div	[di].BPB_CLUSBYTES	; AX = cluster index of CURPOS
	xchg	cx,ax			; CX = target index
	mov	si,[bx+SFB_HINTIDX]	; SI = hint index
	mov	dx,[bx+SFB_HINTCLN]	; DX = hint CLN
	test	dx,dx			; is there a hint?
	jz	wc1			; no
	cmp	si,cx			; is the hint beyond the target?
	jbe	wc2			; no
wc1:	sub	si,si
	mov	dx,[bx].SFB_CLN		; start with the first CLN (index 0)
wc2:	push	cx			; save the target index
	sub	cx,si			; CX = # clusters to advance
	jcxz	wc6
wc3:	mov	si,dx			; SI = current CLN
	call	get_cln			; DX = next CLN
	jc	wc7
	mov	ax,dx
	sub	ax,2
	cmp	ax,[di].BPB_CLUSTERS	; is the next CLN valid?
	jae	wc5			; no (the chain ended)
	loop	wc3
	jmp	short wc6
wc5:	mov	dx,si			; DX = last CLN of the chain
wc6:	pop	ax
	sub	ax,cx			; AX = index of DX (and carry is clear)
	mov	[bx+SFB_HINTIDX],ax
	mov	[bx+SFB_HINTCLN],dx
	ret
wc7:	pop	cx
	ret
wc8:	mov	ax,ERR_DISKFULL
	stc
	ret
ENDPROC	walk_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; next_hint
;
; Called whenever a file's current CLN advances to the next CLN in its chain,
; so that the SFB's cluster hint (see walk_cln) can follow it.
;
; Inputs:
;	AX = next CLN (from get_cln)
;	DX = current CLN
;	BX -> SFB
;	DI -> BPB
;
; Outputs:
;	AX = next CLN, or zero if it's not a valid data cluster (eg, the end
;	of the chain); carry clear
;
; Modifies:
;	AX
;
DEFPROC	next_hint,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	ax
	sub	ax,2
	cmp	ax,[di].BPB_CLUSTERS	; is the next CLN valid?
	pop	ax
	jb	nh1			; yes
	sub	ax,ax			; no (and carry is clear)
	ret
nh1:	cmp	[bx+SFB_HINTCLN],dx	; is the hint the current CLN?
	jne	nh9			; no
	mov	[bx+SFB_HINTCLN],ax	; yes, so advance it
	inc	word ptr [bx+SFB_HINTIDX]
nh9:	clc
	ret
ENDPROC	next_hint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; advance_cln
;
; Advance SFB_CURCLN and its hint if CURPOS is at a cluster boundary.  Clear
; CURCLN before the FAT lookup, leaving it invalid if the lookup fails.
;
; Inputs:
;	DS:BX -> SFB
;	DS:DI -> BPB
;
; Outputs:
;	On success, carry clear, SFB_CURCLN and its hint updated if CURPOS
;	is at a cluster boundary (SFB_CURCLN is zero at the end of the chain)
;	On failure, carry set, AX = error code, SFB_CURCLN = 0
;
; Modifies:
;	AX
;
DEFPROC	advance_cln,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	test	[bx].SFB_CURPOS.LOW,ax	; is CURPOS at a cluster boundary?
	jnz	anc9			; no (and carry is clear)
	push	dx
	sub	dx,dx
	xchg	dx,[bx].SFB_CURCLN	; DX = current CLN (and zero CURCLN)
	push	dx
	call	get_cln
	xchg	ax,dx			; AX = next CLN
	pop	dx			; DX = current CLN
	jc	anc8
	call	next_hint		; AX = next CLN (zero if none)
	mov	[bx].SFB_CURCLN,ax
anc8:	pop	dx
anc9:	ret
ENDPROC	advance_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; merge_clns (for sfb_read)
;
; Limit a read beginning in SFB_CURCLN to the bytes available in that cluster
; and in any clusters of the chain that immediately follow it on disk, so that
; a single request can read them all.
;
; Inputs:
;	BX -> SFB
;	CX = # bytes requested
;	DX = offset within SFB_CURCLN
;	DI -> BPB
;
; Outputs:
;	CX = # bytes to read
;	SI = CLN containing the last byte to read
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	merge_clns,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	push	dx
	mov	si,[bx].SFB_CURCLN	; SI = current CLN
	mov	ax,[di].BPB_CLUSBYTES
	sub	ax,dx			; AX = bytes available through SI
mc1:	cmp	cx,ax			; are enough bytes available?
	jbe	mc9			; yes
	push	ax
	mov	dx,si
	call	get_cln			; DX = next CLN
	xchg	ax,dx			; AX = next CLN
	mov	dx,si			; DX = current CLN
	inc	si			; SI = next cluster on disk
	jc	mc6			; stop at a FAT error (reported later)
	call	next_hint		; AX = next CLN (zero if none)
	cmp	ax,si			; is the next CLN next on disk too?
	jne	mc6			; no
	pop	ax
	add	ax,[di].BPB_CLUSBYTES	; AX = bytes available through SI
	jnc	mc1			; (unless that's too many bytes)
	sub	ax,[di].BPB_CLUSBYTES
	push	ax
mc6:	pop	ax
	dec	si			; SI = last CLN that can be read
	mov	cx,ax			; CX = bytes available
mc9:	pop	dx
	ret
ENDPROC	merge_clns

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
	call	fat_pos			; BX = byte offset, CL = shift, BP = entry mask
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	jc	gc9
;
; Read both bytes, including the FAT12 sector-boundary case, then extract
; the entry's bits using the shift and mask supplied by fat_pos.
;
	mov	ah,[si+bx]		; AH = first byte
	inc	bx
	cmp	bx,512			; does the second byte belong to the next sector?
	jb	gc2
	push	ax
	inc	dx
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	pop	bx			; BH = first byte (saved in AH)
	jc	gc9			; leave the buffer error in AX
	mov	ah,bh
	sub	bx,bx
gc2:	mov	dl,ah
	mov	dh,[si+bx]
	shr	dx,cl
	and	dx,bp			; mask to 12 or 16 bits, and clear carry

gc9:	pop	ds
	pop	bp
	pop	si
	pop	cx
	pop	bx
	ret
ENDPROC	get_cln

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resize_file
;
; Sets a file's size to its current position (CURPOS), freeing any clusters
; past the new end of the file or allocating clusters up to it, and marks the
; SFB dirty, so that its DIRENT is updated when it's closed (see sfb_commit).
; CURPOS is unchanged, but CURCLN is zeroed, since the cluster it refers to
; may no longer belong to the file.
;
; Inputs:
;	BX -> SFB
;
; Outputs:
;	On success, carry clear, SFB_SIZE updated
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	resize_file,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	LOCK_SCB
	push	cx
	push	si
	mov	dl,[bx].SFB_DRIVE
	call	get_bpb			; DI -> BPB
	mov	ax,[bx].SFB_CURPOS.LOW
	mov	cx,[bx].SFB_CURPOS.HIW	; CX:AX = new size
	push	cx
	push	ax
	jc	rz8
	sub	dx,dx
	mov	[bx].SFB_CURCLN,dx
	or	dx,ax
	or	dx,cx			; is the new size zero?
	jz	rz3			; yes, so free every cluster
;
; Back CURPOS up to the new last byte, so that find_cln (or get_wcln) will
; return the new last cluster.
;
	sub	[bx].SFB_CURPOS.LOW,1
	sbb	[bx].SFB_CURPOS.HIW,0
	cmp	cx,[bx].SFB_SIZE.HIW
	ja	rz2
	jb	rz1
	cmp	ax,[bx].SFB_SIZE.LOW
	ja	rz2			; the file is growing
;
; The file is shrinking (or staying the same size), so end the cluster chain
; at the new last cluster, and free the rest.
;
rz1:	call	find_cln		; DX = new last CLN
	jc	rz8
	push	dx
	call	get_cln			; DX = next CLN
	pop	si			; SI = new last CLN
	jc	rz8
	push	dx
	mov	dx,si
	mov	ax,CLN_LAST
	call	set_cln			; end the chain at the new last CLN
	pop	dx			; DX = 1st CLN to free
	jc	rz8
	call	free_clns
	jmp	short rz8
;
; The file is growing, so let get_wcln allocate clusters through CURPOS.
;
rz2:	call	get_wcln
	jmp	short rz8
;
; The new size is zero (and so is DX), so the file no longer has clusters.
;
rz3:	mov	[bx].SFB_CONTEXT,dx
	xchg	dx,[bx].SFB_CLN		; DX = 1st CLN (and zero SFB_CLN)
	call	free_clns
rz8:	pop	cx
	pop	dx			; DX:CX = new size
	mov	[bx].SFB_CURPOS.LOW,cx	; restore CURPOS
	mov	[bx].SFB_CURPOS.HIW,dx
	mov	[bx].SFB_CURCLN,0
	mov	word ptr [bx+SFB_HINTCLN],0	; the chain may be shorter now
	jc	rz9
	mov	[bx].SFB_SIZE.LOW,cx
	mov	[bx].SFB_SIZE.HIW,dx
	or	[bx].SFB_FLAGS,SFBF_DIRTY ; (and carry is clear)
rz9:	pop	si
	pop	cx
	UNLOCK_SCB_RET
ENDPROC	resize_file

DOS	ends

	end
