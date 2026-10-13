;
; BASIC-DOS Disk Buffer Services
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

DOS	segment word public 'CODE'

	EXTNEAR	<dev_request>
	EXTWORD	<buf_head>
	EXTLONG	<bpb_table>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; zap_buffers
;
; Discard any buffers containing data for the specified drive and range of
; LBAs, without writing them (eg, when the media has changed, or when the
; sectors are about to be overwritten; see init_cln).
;
; Inputs:
;	AL = drive # (-1 for all drives)
;	DX = 1st LBA
;	CX = # of LBAs
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	zap_buffers,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	si
	push	ds
	mov	si,[buf_head]
zb1:	mov	ds,si
	test	al,al
	jl	zb2
	cmp	ds:[BUF_DRIVE],al
	jne	zb3
zb2:	mov	si,ds:[BUF_LBA]
	sub	si,dx
	cmp	si,cx			; is the LBA within the range?
	jae	zb3			; no
;
; We use zero to zap BUF_LBA because we never read LBA 0 into our buffers;
; the disk driver will read LBA 0, but only when it needs to rebuild the BPB.
;
	mov	ds:[BUF_LBA],0		; use 0 to invalidate the LBA
	mov	ds:[BUF_DIRTY],0	; and discard any unwritten data
zb3:	mov	si,ds:[BUF_NEXT]
	cmp	si,[buf_head]		; looped back around?
	jne	zb1			; no
	pop	ds
	pop	si
	ret
ENDPROC	zap_buffers

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_buffer
;
; Finds the buffer containing the requested sector (reading the sector into
; the least recently used buffer if necessary), and makes it the most recently
; used buffer.  SI says what kind of data the sector contains (FAT or DIR),
; and to ensure that a caller can keep using the most recent sector of one
; kind while reading sectors of the other kind (eg, keeping a DIRENT while
; reading the FAT), the most recently used buffer of the other kind is never
; reused (so there must be at least two buffers).
;
; new_buffer is the same, except that the sector is not read (the caller is
; going to fill the buffer and mark it dirty).
;
; Inputs:
;	AL = drive #
;	DX = LBA
;	SI = offset FAT_BUFHDR or offset DIR_BUFHDR
;	DI -> BPB
;
; Outputs:
;	On success, DS:SI -> buffer with requested data, carry clear
;	(the buffer's BUFHDR is at DS:0)
;	On failure, AX = device error code, carry set
;
; Modifies:
;	AX, SI, DS
;
; Notes:
;	If the buffer being reused contains modified data for another LBA,
;	that data is written (see write_buffer) before the buffer is reused.
;
DEFPROC	read_buffer,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	mov	ah,DDC_READ
	DEFLBL	new_buffer,near		; (AH = 0 to skip the read)
	push	bx
	push	cx
	push	bp
	xchg	cx,si
	sub	cx,offset FAT_BUFHDR
	mov	ch,0			; CL = type, CH = # of other type seen
	mov	bp,cs:[buf_head]	; BP = head (most recently used)
	mov	si,bp
rb1:	mov	ds,si
	cmp	ds:[BUF_DRIVE],al
	jne	rb2
	cmp	ds:[BUF_LBA],dx
	je	rb6			; we found the sector
rb2:	cmp	ds:[BUF_LBA],0		; an invalid buffer
	je	rb3			; can always be reused
	cmp	ds:[BUF_TYPE],cl	; and so can a buffer of the same type
	je	rb3
	inc	ch			; but the first buffer of the other
	cmp	ch,1			; type can't be
	je	rb4
rb3:	mov	bx,si			; BX = least recent reusable buffer
rb4:	mov	si,ds:[BUF_NEXT]
	cmp	si,bp			; looped back around?
	jne	rb1			; no
	mov	ds,bx
	sub	si,si			; DS:SI -> BUFHDR to reuse
	call	write_buffer		; write the buffer first if it's dirty
	jc	rb9
	mov	ds:[BUF_DRIVE],al
	mov	ds:[BUF_LBA],dx
	mov	ch,-1			; CH = -1 (read the sector)
	jmp	short rb7
rb6:	mov	bx,si			; BX = buffer with the sector
	mov	ch,0			; CH = 0 (no read required)
;
; Make the buffer in BX the most recently used buffer (ie, the head).
;
rb7:	mov	ds,bx
	mov	ds:[BUF_TYPE],cl
	cmp	bx,bp			; already the head?
	je	rb8			; yes
	push	ax
	push	dx
	mov	ax,ds:[BUF_PREV]	; unlink the buffer
	mov	dx,ds:[BUF_NEXT]
	mov	ds,ax
	mov	ds:[BUF_NEXT],dx
	mov	ds,dx
	mov	ds:[BUF_PREV],ax
	mov	ds,bp			; and insert it before the head
	mov	ax,ds:[BUF_PREV]
	mov	ds:[BUF_PREV],bx
	mov	ds,ax
	mov	ds:[BUF_NEXT],bx
	mov	ds,bx
	mov	ds:[BUF_PREV],ax
	mov	ds:[BUF_NEXT],bp
	mov	cs:[buf_head],bx	; the buffer is now the head
	pop	dx
	pop	ax
rb8:	mov	si,size BUFHDR		; DS:SI -> data buffer
	and	ch,ah			; read the sector?
	jz	rb9			; no (and carry is clear)
	push	cx
	push	dx
	push	di
	push	es
	ASSERT	Z,<cmp al,cs:[di].BPB_DRIVE>
	mov	cx,ds:[BUF_SIZE]	; CX = byte count
	mov	bx,dx			; BX = LBA
	sub	dx,dx			; DX = offset (0)
	les	di,cs:[di].BPB_DEVICE
	call	dev_request		; AH = DDC_READ, AL = drive #
	pop	es
	pop	di
	pop	dx
	pop	cx
	jnc	rb9
	mov	ds:[BUF_LBA],0		; invalidate the buffer on error
	stc
rb9:	pop	bp
	pop	cx
	pop	bx
	ret
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
