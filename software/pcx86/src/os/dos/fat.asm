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

	EXTNEAR	<get_cln,read_buffer>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_cln (see also: get_cln in disk.asm)
;
; For the CLN in DX, set its FAT entry to the value in AX, using the BPB at DI.
;
; The FAT sector (or sectors, if the entry straddles a sector boundary) is
; modified in FAT_BUF and marked dirty; it will be written to every FAT copy
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
	mov	[FAT_BUFHDR].BUF_DIRTY,1
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
	mov	[FAT_BUFHDR].BUF_DIRTY,1
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

DOS	ends

	end
