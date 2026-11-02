;
; BASIC-DOS NE Program Loader
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Only protected mode needs this code, so it follows dos_fault, in the part of
; the kernel's resident code that real mode doesn't keep (see set_fault).
;
	DOSPSP equ 1
	DOSFUNC equ 1
	DOSNE equ 1
	include	macros.inc
	include	bios.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<mem_alias,load_done,load_fail>

	.286p
;
; While loading, the PSP's block holds the NE header at NEBUF, followed by
; the segment table, and then up to NE_RELMAX relocation records at a time.
;
NEBUF		equ	size PSP
NE_RELMAX	equ	64

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_ne
;
; In protected mode, load_program can't load an MZ program, whose relocations
; are paragraph arithmetic, but it can load an NE program, whose segment table
; gives each segment's type (code or data) and size, and whose relocations
; refer to segments by number (eg, PRIMES.EXE; see tests/primes/PRIMES.DEF).
; Each segment gets its own block, which the new PSP owns (so it's freed when
; the program ends, or by load_program if loading fails), and its own selector
; (for a code segment, the block's code alias).  The program must be marked
; NEF_PROTMODE and have only FIXED segments, no imports, and only internal
; relocations, and it starts with DS and ES addressing its PSP, as an MZ
; program does.
;
; load_program jumps here, and we continue at load_done (with the file closed,
; PSP_START and PSP_STACK set, ES = PSP, BX = paras for the PSP's block, and
; DX = 0) or at load_fail (with AX = error code).
;
; Inputs:
;	AX = # bytes read from the start of the file
;	BX = file handle
;	DS:DI = ES:DI -> EXE header (at NEBUF in the PSP's block)
;	SS:BP -> REG_FRAME (see load_program)
;
DEFPROC	load_ne,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	mov	word ptr [bp].TMP_CX,0	; image can't be cached (see scb_load)
	push	bp
	mov	bp,sp
	cmp	ax,EXE_NEHDR + 4	; did we read the NE header's offset?
	jae	ne1			; yes
ne8:	mov	ax,ERR_NOMEMORY		; COMMAND reports "Unable to load X"
ne9:	mov	sp,bp
	pop	bp
	jmp	load_fail
ne1:	cmp	[di].EXE_OFFRELOC,EXE_NEHDR + 4
	jb	ne8			; there's no NE header
	mov	si,di			; DS:SI -> NEBUF
	push	[si+EXE_NEHDR].SEG
	push	[si+EXE_NEHDR].OFF	; [BP-4] = file offset of NE header
	mov	ax,[bp-4]
	mov	dx,[bp-2]
	mov	cx,size NEHDR
	call	ne_read			; read the NE header
	jc	ne9
	cmp	[si].NE_SIG,SIG_NE	; is it an NE header?
	jne	ne8			; no
	mov	cx,[si].NE_FLAGS
	and	cx,NEF_PROTMODE OR NEF_SELFLOAD OR NEF_ERRORS OR NEF_LIBRARY
	cmp	cx,NEF_PROTMODE		; protected mode, and nothing we lack?
	jne	ne8			; no
	cmp	[si].NE_NMODS,0		; does it import anything?
	jne	ne8			; yes
	mov	cx,[si].NE_NSEGS	; CX = # segments
	jcxz	ne8			; there are none
	cmp	cx,1F00h		; too many (for our buffer)?
	jae	ne8			; yes
	shl	cx,3			; CX = size of segment table
	add	si,size NEHDR		; DS:SI -> segment table
	mov	di,si
	add	di,cx
	push	di			; [BP-6] -> relocation records
;
; Shrink the PSP's block (the largest available; see load_program) to what
; we'll read into it, so that we can allocate the segments.
;
	push	bx
	lea	bx,[di+NE_RELMAX*(size NEREL)+15]
	shr	bx,4			; BX = paras
	mov	ah,DOS_MEM_REALLOC
	int	21h			; resize ES to BX paras
	pop	bx
	jc	ne9
	mov	ax,[bp-4]
	mov	dx,[bp-2]
	add	ax,ds:[NEBUF].NE_SEGTAB
	adc	dx,0			; DX:AX = file offset of segment table
	call	ne_read			; read the segment table
	jc	ne9
;
; Allocate a block for each segment (DGROUP's includes its heap and stack),
; zero it, and replace the segment's size in the table with its selector.
;
	mov	cx,ds:[NEBUF].NE_NSEGS
	sub	dx,dx			; DX = segment #
nl1:	inc	dx
	test	[si].NES_FLAGS,NESF_ITERATED OR NESF_MOVEABLE
	jnz	nl1a			; (not supported)
	push	cx
	push	bx
	mov	ax,[si].NES_SIZE
	cmp	ax,1
	sbb	cx,cx
	neg	cx			; CX:AX = size (0 means 64K)
	cmp	dx,ds:[NEBUF].NE_AUTODATA
	jne	nl2
	add	ax,ds:[NEBUF].NE_HEAP
	adc	cx,0
	add	ax,ds:[NEBUF].NE_STACK
	adc	cx,0			; CX:AX = size of DGROUP
nl2:	add	ax,15
	adc	cx,0
	shr	ax,4
	shl	cx,12
	or	ax,cx			; AX = paras
	cmp	ax,1000h		; more than 64K?
	ja	nl1a			; yes
	xchg	bx,ax			; BX = paras
	mov	ax,(DOS_MEM_ALLOC SHL 8) OR MCBTYPE_HIGH
	int	21h			; AX = new selector
	jc	nl1b
	mov	[si].NES_SIZE,ax
	mov	es,ax
	sub	di,di
	mov	cx,bx
	shl	cx,3			; CX = # words in block
	sub	ax,ax
	rep	stosw			; zero the block
	pop	bx
	pop	cx
	add	si,size NESEG
	loop	nl1
	jmp	short nl3
nl1a:	jmp	ne8
nl1b:	jmp	ne9
;
; Read each segment's data (if any) into its block, followed by its
; relocation records (if any), and apply them.
;
nl3:	mov	si,NEBUF + size NEHDR	; DS:SI -> segment table
	mov	cx,ds:[NEBUF].NE_NSEGS
nl4:	push	cx
	mov	ax,[si].NES_SECTOR
	test	ax,ax			; any data?
	jz	nl7			; no
	mov	cx,ds:[NEBUF].NE_SHIFT
	test	cx,cx
	jnz	nl5
	mov	cl,9			; (a shift of 0 means 9)
nl5:	sub	dx,dx
nl5a:	shl	ax,1
	rcl	dx,1
	loop	nl5a			; DX:AX = file offset of data
	mov	cx,[si].NES_LENGTH	; CX = length of data
	jcxz	nl1a			; (64K of data isn't supported)
	mov	di,[si].NES_SIZE
	lsl	di,di			; DI = limit of segment
	dec	cx
	cmp	cx,di			; does the data fit?
	ja	nl1a			; no
	inc	cx
	push	ds
	push	si
	mov	ds,[si].NES_SIZE
	sub	si,si			; DS:SI -> segment
	call	ne_read			; read its data
	pop	si
	pop	ds
	jc	nl1b
	test	[si].NES_FLAGS,NESF_RELOCS
	jz	nl7
	mov	es,[si].NES_SIZE	; ES = segment
	push	si
	mov	si,[bp-6]		; DS:SI -> relocation records
	mov	cx,2
	call	ne_next			; read the # of records
	jc	nl1b
	mov	cx,[si]			; CX = # of records
nl6:	jcxz	nl6b
	push	cx
	cmp	cx,NE_RELMAX
	jb	nl6a
	mov	cx,NE_RELMAX
nl6a:	push	cx
	shl	cx,3
	call	ne_next			; read up to NE_RELMAX records
	pop	cx
	jc	nl1b
	call	ne_fix			; and apply them
	jc	nl1a
	mov	si,[bp-6]
	pop	cx
	sub	cx,NE_RELMAX		; any more records?
	ja	nl6			; yes
nl6b:	pop	si
nl7:	pop	cx
	add	si,size NESEG
	loop	nl4
;
; The program starts at CS:IP, which must be in a code segment, and its stack
; (SS:SP, where SP 0 means the top of the segment) must be in a data segment,
; with room below SP for the initial REG_FRAME (see load_program).
;
	mov	ax,ds:[NEBUF].NE_START.SEG
	call	ne_seg			; DS:DI -> CS's segment table entry
	jc	nl9
	test	[di].NES_FLAGS,NESF_DATA; is it a code segment?
	jnz	nl9			; no
	mov	ax,[di].NES_SIZE
	call	mem_alias		; AX = its code alias
	jc	nl9a
	mov	ds:[PSP_START].SEG,ax
	mov	ax,ds:[NEBUF].NE_START.OFF
	mov	ds:[PSP_START].OFF,ax
	mov	ax,ds:[NEBUF].NE_STACKPTR.SEG
	call	ne_seg			; DS:DI -> SS's segment table entry
	jc	nl9
	test	[di].NES_FLAGS,NESF_DATA; is it a data segment?
	jz	nl9			; no
	mov	ax,[di].NES_SIZE
	mov	ds:[PSP_STACK].SEG,ax
	lsl	cx,ax			; CX = limit of segment
	mov	ax,ds:[NEBUF].NE_STACKPTR.OFF
	test	ax,ax			; SP zero?
	jnz	nl8			; no
	mov	ax,cx
	inc	ax			; AX = top of segment
nl8:	mov	ds:[PSP_STACK].OFF,ax
	dec	ax			; AX = offset of top byte of stack
	cmp	ax,cx			; within the segment?
	ja	nl9			; no
	cmp	ax,size REG_FRAME + 3	; with room for REG_FRAME and a zero?
	jb	nl9			; no
	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the file
	jc	nl9a
	mov	sp,bp
	pop	bp
	push	ds
	pop	es			; ES = PSP
	mov	bx,size PSP SHR 4	; BX = paras for the PSP's block
	sub	dx,dx			; DX = 0 (no heap to zero)
	jmp	load_done
nl9:	jmp	ne8
nl9a:	jmp	ne9
ENDPROC	load_ne

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_fix
;
; Applies relocation records to a segment, as load_ne requires: each record
; must be an internal reference, whose target is a selector, a 32-bit pointer,
; or an offset.
;
; Inputs:
;	CX = # of records
;	DS:SI -> records (DS = PSP; see load_ne)
;	ES = segment
;
; Outputs:
;	Carry clear if successful, set if not
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	ne_fix
	push	bx
	push	bp
	mov	bx,es
	lsl	bx,bx			; BX = limit of segment
nf1:	mov	al,[si].NER_TYPE
	cmp	al,NERT_SEL
	je	nf2
	cmp	al,NERT_FAR
	je	nf2
	cmp	al,NERT_OFF
	jne	nf8			; unsupported source type
nf2:	test	[si].NER_FLAGS,NERF_TARGET
	jnz	nf8			; not an internal reference
	mov	ax,[si].NER_SEG
	call	ne_sel			; AX = selector of target segment
	jc	nf8
	mov	dx,[si].NER_OFFSET	; AX:DX = target
	mov	di,[si].NER_SOURCE	; ES:DI -> first source
	mov	bp,8000h		; BP = most sources a segment can have
nf3:	push	cx
	mov	cx,1
	cmp	[si].NER_TYPE,NERT_FAR
	jne	nf4
	mov	cl,3
nf4:	add	cx,di			; CX = offset of source's last byte
	jc	nf7
	cmp	cx,bx			; within the segment?
	ja	nf7			; no
	mov	cx,es:[di]		; CX = offset of next source
	test	[si].NER_FLAGS,NERF_ADDITIVE
	jz	nf5
	add	dx,cx			; add the target offset to the source
	mov	cx,-1			; (and there's no next source)
nf5:	cmp	[si].NER_TYPE,NERT_SEL
	je	nf6
	mov	es:[di],dx		; store the offset
	cmp	[si].NER_TYPE,NERT_OFF
	je	nf6a
	inc	di
	inc	di
nf6:	mov	es:[di],ax		; store the selector
nf6a:	mov	di,cx			; ES:DI -> next source
	pop	cx
	cmp	di,-1			; any more sources?
	je	nf6b			; no
	dec	bp			; too many?
	jnz	nf3			; no
	jmp	short nf8
nf6b:	add	si,size NEREL
	loop	nf1
	jmp	short nf9		; (carry is clear)
nf7:	pop	cx
nf8:	stc
nf9:	pop	bp
	pop	bx
	ret
ENDPROC	ne_fix

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_read
;
; Reads CX bytes into DS:SI, from file offset DX:AX (or from the current file
; position, with ne_next); load_ne makes sure that they fit.
;
; Inputs:
;	BX = file handle
;	DX:AX = file offset (ne_read only)
;	CX = # bytes
;	DS:SI -> buffer
;
; Outputs:
;	Carry clear if successful; otherwise, carry set, AX = error code
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	ne_read
	push	cx
	xchg	cx,dx
	xchg	dx,ax			; CX:DX = file offset
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	pop	cx
	jc	nr9
ne_next:
	mov	dx,si
	mov	ah,DOS_HDL_READ
	int	21h
	jc	nr9
	cmp	ax,cx			; did we read all the data?
	je	nr9			; yes (and carry is clear)
	mov	ax,ERR_NOMEMORY
	stc
nr9:	ret
ENDPROC	ne_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_sel
;
; Returns the selector of a segment (load_ne puts each one in the segment
; table), or for a code segment, its code alias.
;
; Inputs:
;	AX = segment #
;	DS = PSP (see load_ne)
;
; Outputs:
;	Carry clear if successful, AX = selector
;
; Modifies:
;	AX
;
DEFPROC	ne_sel
	push	di
	call	ne_seg			; DS:DI -> segment table entry
	jc	ns9
	mov	ax,[di].NES_SIZE	; AX = selector
	test	[di].NES_FLAGS,NESF_DATA; is it a data segment?
	jnz	ns9			; yes (and carry is clear)
	call	mem_alias		; no, so AX = its code alias
ns9:	pop	di
	ret
ENDPROC	ne_sel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_seg
;
; Inputs:
;	AX = segment # (1 or more)
;	DS = PSP (see load_ne)
;
; Outputs:
;	Carry clear if valid, DS:DI -> segment table entry
;
; Modifies:
;	AX, DI
;
DEFPROC	ne_seg
	dec	ax
	cmp	ax,ds:[NEBUF].NE_NSEGS	; is it a valid segment #?
	cmc
	jc	ng9			; no
	shl	ax,3
	add	ax,NEBUF + size NEHDR
	xchg	di,ax			; DS:DI -> entry (and carry is clear)
ng9:	ret
ENDPROC	ne_seg

DOS	ends

	end
