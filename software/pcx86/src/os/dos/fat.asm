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
; set_cln (see also: get_cln)
;
; For the CLN in DX, set its FAT entry to the value in AX, using the BPB at DI.
;
; The FAT sector (or sectors, if the entry straddles a sector boundary) is
; modified in a FAT buffer and marked dirty; it will be written to every FAT copy
; when the buffer is reused or flushed (see write_buffer).
;
; Inputs:
;	AX = new FAT entry value (12 bits)
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
	mov	bp,ax			; BP = new value
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
;
; As in get_cln, the FAT sector containing a 12-bit CLN is (CLN * 3) SHR 10,
; and the nibble offset within that sector is (CLN * 3) AND 03FFh (again,
; assuming 512-byte sectors).
;
	mov	bx,dx
	add	dx,dx
	add	dx,bx
	mov	bx,dx
	mov	cl,10
	shr	dx,cl			; DX = FAT sector ((CLN * 3) SHR 10)
	add	dx,cs:[di].BPB_RESSECS	; DX = FAT LBA
	and	bx,03FFh		; nibble offset (assuming 1024 nibbles)
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset FAT_BUFHDR
	call	read_buffer
	jc	sc9
;
; If the nibble offset is even, the new value occupies the entire first byte
; and the low nibble of the second byte; if odd, it occupies the high nibble of
; the first byte and the entire second byte.  CX is a mask of the bits in each
; byte to preserve, and AX is the value shifted into position.
;
	mov	ax,bp			; AX = new value
	mov	cx,0F000h		; CX = mask for an even nibble offset
	shr	bx,1			; BX -> byte, carry set if odd nibble
	jnc	sc1
	mov	cl,4
	shl	ax,cl			; shift the value up one nibble
	mov	cx,000Fh		; CX = mask for an odd nibble offset
sc1:	and	[si+bx],cl
	or	[si+bx],al
	mov	ds:[BUF_DIRTY],1
	inc	bx
	cmp	bx,512			; at the sector boundary?
	jb	sc2			; no
	push	ax
	inc	dx			; DX = next FAT LBA
	mov	al,cs:[di].BPB_DRIVE
	mov	si,offset FAT_BUFHDR
	call	read_buffer		; (writes the previous FAT sector first)
	pop	bx			; BX = shifted value (from AX)
	jc	sc9
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
	mov	dx,2			; DX = first CLN to check
ac1:	push	dx
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
fn1:	mov	ax,[di].BPB_CLUSBYTES
	dec	ax
	add	cx,ax
	adc	si,0			; SI:CX = cluster limit
	mov	ax,cx
	sub	ax,[bx].SFB_CURPOS.LOW
	mov	ax,si
	sbb	ax,[bx].SFB_CURPOS.HIW
	jnc	fn9			; we've traversed enough clusters
	call	get_cln			; DX = next CLN
	jnc	fn1			; keep checking as long as no error

fn9:	pop	cx
	ret
ENDPROC	find_cln

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
	jc	rz9
	mov	[bx].SFB_SIZE.LOW,cx
	mov	[bx].SFB_SIZE.HIW,dx
	or	[bx].SFB_FLAGS,SFBF_DIRTY ; (and carry is clear)
rz9:	pop	si
	pop	cx
	UNLOCK_SCB
ENDPROC	resize_file

DOS	ends

	end
