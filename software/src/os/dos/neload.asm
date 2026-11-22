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

	EXTNEAR	<mem_alias,load_done,load_fail,load_le>
	EXTWORD	<dos_data>
	EXTBYTE	<def_drive,def_pathchar>

	.286p
;
; While loading, a module's block holds its NE header at NEBUF, followed by
; its segment table, module reference table, and entry table, and then up to
; NE_RELMAX relocation records at a time.  The program's block is its PSP's,
; and each library has a block of its own, which starts with an NELIB (where
; the program has its PSP) and is freed when the program has been loaded.
;
; Three of the header's fields are replaced as they're used: NE_CRC with the
; header's file offset, NE_LINKVER with the offset (in the block) of the
; relocation records, and the offset of each table that ne_tab reads with
; the table's offset in the block.
;
NEBUF		equ	size PSP
NE_RELMAX	equ	64

NELIB		struc
NL_NEXT		dw	?	; 00h: next library's block (0 if none)
NL_NAME		db	9 dup(?); 02h: module name (length byte and name)
NL_PATH		db     46 dup(?); 0Bh: file name (see ne_lib)
NELIB		ends

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_ne
;
; In protected mode, load_program can't load an MZ program, whose relocations
; are paragraph arithmetic, but it can load an NE program, whose segment table
; gives each segment's type (code or data) and size, and whose relocations
; refer to segments by number (eg, PRIMES.EXE; see tests/misc/PRIMES.DEF).
; Each segment gets its own block, which the new PSP owns (so it's freed when
; the program ends, or by load_program if loading fails), and its own selector
; (for a code segment, the block's code alias).  The program must be marked
; NEF_PROTMODE (or be an OS/2 program, which gets OS/2's starting registers
; instead; see ne_os2) and have only FIXED segments, and it starts with DS
; and ES addressing its PSP, as an MZ program does.
;
; Its relocations can also refer to functions in libraries, by ordinal (see
; ne_lib).  The program gets its own copy of each library's segments, in
; blocks that its PSP owns, too; a library's entry point isn't called.
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
	sub	cx,cx
	push	cx			; [BP-2] = first library's block (none)
	mov	dx,NEF_PROTMODE
	call	ne_load			; load the program's segments
;
; The program starts at CS:IP, which must be within a code segment, and its
; stack (SS:SP, where SP 0 means the top of the segment) must be in a data
; segment, with room below SP for the initial REG_FRAME (see load_program).
;
	mov	ax,ds:[NEBUF].NE_START._SEG
	call	ne_seg			; DS:DI -> CS's segment table entry
	jc	ne_err
	test	[di].NES_FLAGS,NESF_DATA; is it a code segment?
	jnz	ne_err			; no
	mov	ax,[di].NES_SIZE
	lsl	cx,ax			; CX = limit of segment
	cmp	ds:[NEBUF].NE_START._OFF,cx
	ja	ne_err			; IP isn't in it (its IRET would fault)
	call	mem_alias		; AX = its code alias
	jc	ne_fail
	mov	ds:[PSP_START]._SEG,ax
	mov	ax,ds:[NEBUF].NE_START._OFF
	mov	ds:[PSP_START]._OFF,ax
	mov	ax,ds:[NEBUF].NE_STACKPTR._SEG
	call	ne_seg			; DS:DI -> SS's segment table entry
	jc	ne_err
	test	[di].NES_FLAGS,NESF_DATA; is it a data segment?
	jz	ne_err			; no
	mov	ax,[di].NES_SIZE
	mov	ds:[PSP_STACK]._SEG,ax
	lsl	cx,ax			; CX = limit of segment
	mov	ax,ds:[NEBUF].NE_STACKPTR._OFF
	test	ax,ax			; SP zero?
	jnz	ne1			; no
	mov	ax,cx
	inc	ax			; AX = top of segment
ne1:	mov	ds:[PSP_STACK]._OFF,ax
	dec	ax			; AX = offset of top byte of stack
	cmp	ax,cx			; within the segment?
	ja	ne_err			; no
	cmp	ax,size REG_FRAME + 3	; with room for REG_FRAME and a zero?
	jb	ne_err			; no
	call	ne_os2			; (an OS/2 program starts in DOSCALLS)
	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the file
	jc	ne_fail
;
; Free the libraries' blocks (not their segments), now that their tables
; aren't needed.
;
	mov	ax,[bp-2]		; AX = first library's block
ne2:	test	ax,ax			; any more?
	jz	ne3			; no
	mov	es,ax
	push	es:[NL_NEXT]
	mov	ah,DOS_MEM_FREE
	int	21h			; free the block (which zeroes ES)
	pop	ax			; AX = next library's block
	jmp	ne2
;
; A program (not a library) whose new header isn't an NE header may have an
; LE header (see leload.asm).
;
ne_le:	test	dh,NEF_LIBRARY SHR 8	; a library?
	jnz	ne_err			; yes
	jmp	load_le
;
; Every failure, in any of our procedures, ends up here (ne_mz if the file
; has no NE or LE header, so it's a real-mode program, which COMMAND reports
; as one that a V86 machine can run; ne_err if it's anything else we can't
; load; and ne_fail with an error code in AX).
;
	DEFLBL	ne_mz,near
	mov	ax,ERR_BADMODE
	jmp	short ne_fail
ne_err:	mov	ax,ERR_BADFORMAT	; COMMAND reports "Unable to load X"
ne_fail:
	mov	sp,bp
	pop	bp
	jmp	load_fail
ne3:	mov	sp,bp
	pop	bp
	push	ds
	pop	es			; ES = PSP
	mov	bx,size PSP SHR 4	; BX = paras for the PSP's block
	sub	dx,dx			; DX = 0 (no heap to zero)
	jmp	load_done
ENDPROC	load_ne

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_load
;
; Loads a module (the program, or a library that it or another library
; imports from): resizes the module's block to hold its tables, allocates and
; zeroes a block for each segment, loads the libraries it refers to (see
; ne_lib), and then reads each segment's data and applies its relocations.
; Any failure continues at ne_err or ne_fail (see load_ne), which discard our
; stack.
;
; Inputs:
;	AX = # bytes read from the start of the file
;	BX = file handle
;	DX = the NE_FLAGS it must have (of those we check)
;	DS = module's block, with the file's EXE header at NEBUF
;	SS:BP -> load_ne's frame
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	ne_load
	mov	si,NEBUF		; DS:SI -> EXE header
	cmp	ax,EXE_NEHDR + 4	; did we read the NE header's offset?
	jb	ne_mz			; no
	cmp	[si].EXE_OFFRELOC,EXE_NEHDR + 4
	jb	ne_mz			; there's no NE header
	push	dx
	mov	ax,[si+EXE_NEHDR]._OFF
	mov	dx,[si+EXE_NEHDR]._SEG	; DX:AX = file offset of NE header
	push	dx
	push	ax
	mov	cx,size NEHDR
	call	ne_read			; read the NE header
	pop	[si].NE_CRC._OFF
	pop	[si].NE_CRC._SEG	; NE_CRC = file offset of NE header
	pop	dx
	jc	ne_mz			; there's none (the file's too short)
	cmp	[si].NE_SIG,SIG_NE	; is it an NE header?
	jne	ne_le			; no
	mov	cx,[si].NE_FLAGS
	and	cx,NEF_PROTMODE OR NEF_SELFLOAD OR NEF_ERRORS OR NEF_LIBRARY
	cmp	cx,dx			; the right kind, and nothing we lack?
	jne	nl0a			; no (unless it's an OS/2 module)
nl0:	mov	cx,[si].NE_NSEGS	; CX = # segments
	jcxz	ne_err			; there are none
	cmp	cx,1F00h		; too many (for a block)?
	jae	ne_err			; yes
	shl	cx,3			; CX = size of segment table
;
; Resize the block (for the program, the largest available, which must
; shrink before we can allocate anything; see load_program) to what we'll
; read into it: the three tables and NE_RELMAX relocation records.
;
	mov	di,NEBUF + size NEHDR + NE_RELMAX*(size NEREL) + 15
	add	di,cx
	mov	ax,[si].NE_NMODS
	add	ax,ax			; AX = size of module reference table
	jc	ne_err
	add	di,ax
	jc	ne_err
	add	di,[si].NE_ENTLEN
	jc	ne_err			; the tables don't fit in a block
	push	bx
	mov	bx,di
	shr	bx,4			; BX = paras
	push	ds
	pop	es
	mov	ah,DOS_MEM_REALLOC
	int	21h			; resize ES to BX paras
	pop	bx
	jc	ne_fail
	jmp	short nl0d
;
; An OS/2 module needn't be marked NEF_PROTMODE, and its NE_OS is NEOS_OS2
; or, from a linker that didn't set NE_OS (eg, LINK4, and the linker of every
; OS/2 1.0 program), zero.  In a module whose NE_OS is NEOS_OS2, NEF_SELFLOAD
; is OS/2's bit for a "bound" program (one whose stub runs it on DOS, too).
;
nl0a:	or	cl,NEF_PROTMODE
	cmp	[si].NE_OS,NEOS_OS2	; is it an OS/2 module?
	ja	nl0c			; no
	jb	nl0b			; perhaps
	and	ch,NOT (NEF_SELFLOAD SHR 8)
nl0b:	cmp	cx,dx			; is that all it lacked?
	je	nl0			; yes
nl0c:	jmp	ne_err
nl0d:
	mov	si,NEBUF + size NEHDR	; DS:SI -> segment table
	mov	di,NEBUF + NE_SEGTAB
	call	ne_tab			; read the segment table
	mov	cx,ds:[NEBUF].NE_NMODS
	shl	cx,1
	mov	di,NEBUF + NE_MODTAB
	call	ne_tab			; read the module reference table
	mov	cx,ds:[NEBUF].NE_ENTLEN
	mov	di,NEBUF + NE_ENTTAB
	call	ne_tab			; read the entry table
	mov	ds:[NEBUF].NE_LINKVER,si; NE_LINKVER -> relocation records
;
; Allocate a block for each segment (DGROUP's includes its heap and stack),
; zero it, and replace the segment's size in the table with its selector.
;
	mov	si,NEBUF + size NEHDR	; DS:SI -> segment table
	mov	cx,ds:[NEBUF].NE_NSEGS
	sub	dx,dx			; DX = segment #
nl1:	inc	dx
	test	[si].NES_FLAGS,NESF_ITERATED OR NESF_MOVEABLE
	jnz	nl3			; (not supported)
	push	cx
	push	bx
	mov	ax,[si].NES_SIZE
	cmp	ax,1
	sbb	cx,cx
	neg	cx			; CX:AX = size (0 means 64K)
	cmp	dx,ds:[NEBUF].NE_AUTODATA
	jne	nl1a
	add	ax,ds:[NEBUF].NE_HEAP
	adc	cx,0
	add	ax,ds:[NEBUF].NE_STACK
	adc	cx,0			; CX:AX = size of DGROUP
nl1a:	add	ax,15
	adc	cx,0
	shr	ax,4
	shl	cx,12
	or	ax,cx			; AX = paras
	cmp	ax,1000h		; more than 64K?
	ja	nl3			; yes
	xchg	bx,ax			; BX = paras
	mov	ax,(DOS_MEM_ALLOC SHL 8) OR MCBTYPE_HIGH
	int	21h			; AX = new selector
	jc	nl3a
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
;
; Load each library that the module refers to (unless it's already loaded),
; now that the module's own segments have selectors, in case a library
; refers back to it.
;
	mov	cx,ds:[NEBUF].NE_NMODS
	jcxz	nl4			; it has no module references
	mov	si,ds:[NEBUF].NE_MODTAB	; DS:SI -> module references
nl2:	call	ne_lib			; replace the reference with a block
	inc	si
	inc	si
	loop	nl2
	jmp	short nl4
nl3:	jmp	ne_err
nl3a:	jmp	ne_fail
;
; Read each segment's data (if any) into its block, followed by its
; relocation records (if any), and apply them.
;
nl4:	mov	si,NEBUF + size NEHDR	; DS:SI -> segment table
	mov	cx,ds:[NEBUF].NE_NSEGS
nl5:	push	cx
	mov	ax,[si].NES_SECTOR
	test	ax,ax			; any data?
	jz	nl8			; no
	mov	cx,ds:[NEBUF].NE_SHIFT
	test	cx,cx
	jnz	nl6
	mov	cl,9			; (a shift of 0 means 9)
nl6:	sub	dx,dx
nl6a:	shl	ax,1
	rcl	dx,1
	loop	nl6a			; DX:AX = file offset of data
	mov	cx,[si].NES_LENGTH	; CX = length of data
	jcxz	nl3			; (64K of data isn't supported)
	mov	di,[si].NES_SIZE
	lsl	di,di			; DI = limit of segment
	dec	cx
	cmp	cx,di			; does the data fit?
	ja	nl3			; no
	inc	cx
	push	ds
	push	si
	mov	ds,[si].NES_SIZE
	sub	si,si			; DS:SI -> segment
	call	ne_read			; read its data
	pop	si
	pop	ds
	jc	nl3a
	test	[si].NES_FLAGS,NESF_RELOCS
	jz	nl8
	mov	es,[si].NES_SIZE	; ES = segment
	push	si
	mov	si,ds:[NEBUF].NE_LINKVER; DS:SI -> relocation records
	mov	cx,2
	call	ne_next			; read the # of records
	jc	nl3a
	mov	cx,[si]			; CX = # of records
nl7:	jcxz	nl7b
	push	cx
	cmp	cx,NE_RELMAX
	jb	nl7a
	mov	cx,NE_RELMAX
nl7a:	push	cx
	shl	cx,3
	call	ne_next			; read up to NE_RELMAX records
	pop	cx
	jc	nl3a
	call	ne_fix			; and apply them
	jc	nl3
	mov	si,ds:[NEBUF].NE_LINKVER
	pop	cx
	sub	cx,NE_RELMAX		; any more records?
	ja	nl7			; yes
nl7b:	pop	si
nl8:	pop	cx
	add	si,size NESEG
	loop	nl5
	ret
ENDPROC	ne_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_lib
;
; Replaces a module reference with the block of the library that it names,
; loading the library if this program hasn't loaded it yet.  A library is a
; file with the module's name and a DLL extension, in the directory that a
; "LIBPATH=" line in CONFIG.SYS names (lib_path, which sysinit sets), or by
; default, EXT\DLL on the system drive (see def_drive; eg, DOSCALLS is
; C:\EXT\DLL\DOSCALLS.DLL), that's marked NEF_PROTMODE and NEF_LIBRARY and
; has only FIXED segments.  Any failure continues at ne_err or ne_fail (see
; load_ne).
;
; Inputs:
;	BX = file handle
;	DS:SI -> module reference (DS = module's block)
;	SS:BP -> load_ne's frame
;
; Outputs:
;	[SI] = library's block
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	ne_lib
	push	bx
	push	cx
	push	si
	mov	ax,[si]
	add	ax,ds:[NEBUF].NE_IMPTAB
	sub	dx,dx
	add	ax,ds:[NEBUF].NE_CRC._OFF
	adc	dx,ds:[NEBUF].NE_CRC._SEG
	mov	si,ds:[NEBUF].NE_LINKVER
	mov	cx,size NL_NAME
	call	ne_read			; read the name (where records go)
	jc	nb1b
	mov	cl,[si]			; CX = length of name (CH is zero)
;
; A module's name is also its file's, so it can't be longer than 8.
;
	cmp	cl,size NL_NAME - 1
	ja	nb1a
	inc	cx			; CX = length with the length byte
	mov	ax,[bp-2]		; AX = first library's block
nb1:	test	ax,ax			; any more?
	jz	nb2			; no, so load this one
	mov	es,ax
	push	cx
	push	si
	mov	di,NL_NAME
	repe	cmpsb			; is this the library?
	pop	si
	pop	cx
	jne	nb1c			; no
	jmp	nb7
nb1c:	mov	ax,es:[NL_NEXT]
	jmp	nb1
nb1a:	jmp	ne_err
nb1b:	jmp	ne_fail
;
; Allocate a block with room for the file's EXE header (ne_load resizes it)
; and add it to the list of libraries.
;
nb2:	mov	bx,(NEBUF + EXE_NEHDR + 4 + 15) SHR 4
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h			; AX = new selector
	jc	nb1b
	mov	es,ax
	sub	di,di
	xchg	ax,[bp-2]
	stosw				; NL_NEXT
	push	cx
	push	si
	rep	movsb			; NL_NAME
	pop	si
	pop	cx
	mov	di,NL_PATH
	push	si
	push	ds
	mov	ds,cs:[dos_data]
	ASSUME	DS:DOS
	mov	dl,[def_pathchar]
	mov	si,offset lib_path
	cmp	byte ptr [si],0		; did a LIBPATH line name a directory?
	jne	nb3			; yes
	mov	al,[def_drive]
	add	al,'A'
	mov	ah,':'
	stosw
	mov	si,offset LIB_DIR	; no, so it's the system drive's
nb3:	lodsb
	cmp	al,'\'
	jne	nb3a
	mov	al,dl			; (the system's path character)
nb3a:	stosb
	test	al,al
	jnz	nb3
	dec	di			; ES:DI -> the directory's null
	cmp	es:[di-1],dl		; does it end with a path character?
	je	nb3b			; yes
	mov	al,dl
	stosb
nb3b:	pop	ds
	ASSUME	DS:NOTHING
	pop	si
	inc	si
	dec	cx
	rep	movsb
	mov	ax,'D.'
	stosw
	mov	ax,'LL'
	stosw
	sub	ax,ax
	stosb				; (eg, "C:\EXT\DLL\DOSCALLS.DLL")
	push	ds
	push	es
	pop	ds			; DS = library's block
	mov	dx,NL_PATH
	mov	ah,DOS_HDL_OPEN
	int	21h			; open the file (AL = 0: read-only)
	jc	nb8
	xchg	bx,ax			; BX = file handle
	mov	si,NEBUF
	mov	cx,EXE_NEHDR + 4
	call	ne_next			; read the EXE header
	jc	nb9
	cmp	[si].EXE_SIG,SIG_EXE
	jne	nb8
	mov	dx,NEF_PROTMODE OR NEF_LIBRARY
	call	ne_load			; load the library's segments
	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the file
	mov	ax,ds			; AX = library's block
	pop	ds
nb7:	pop	si
	mov	[si],ax
	pop	cx
	pop	bx
	ret
nb8:	jmp	ne_err
nb9:	jmp	ne_fail
ENDPROC	ne_lib
;
; The libraries' directory: lib_path is a "LIBPATH=" line's (null-terminated,
; and empty if there's none; lib_end is its last byte, which stays null), and
; LIB_DIR is the default, on the system drive.
;
	DEFLBL	lib_path,byte
	db	31 dup (0)
	DEFLBL	lib_end,byte
	db	0
LIB_DIR	db	"\EXT\DLL",0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_tab
;
; Reads one of a module's tables into its block, and replaces the table's
; offset in the NE header with its offset in the block.  A failure continues
; at ne_fail (see load_ne).
;
; Inputs:
;	BX = file handle
;	CX = size of table
;	DS:SI -> where to read it (DS = module's block)
;	DS:DI -> the table's offset in the NE header
;
; Outputs:
;	SI -> end of the table
;
; Modifies:
;	AX, DX, SI
;
DEFPROC	ne_tab
	mov	ax,si
	xchg	ax,[di]			; AX = offset from the NE header
	sub	dx,dx
	add	ax,ds:[NEBUF].NE_CRC._OFF
	adc	dx,ds:[NEBUF].NE_CRC._SEG
	push	cx
	call	ne_read
	pop	cx
	jc	nt9
	add	si,cx
	ret
nt9:	jmp	ne_fail
ENDPROC	ne_tab

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_fix
;
; Applies relocation records to a segment, as ne_load requires: each record's
; target must be an internal reference or a library's function (by ordinal),
; and its source must be a selector, a 32-bit pointer, or an offset.
;
; Inputs:
;	CX = # of records
;	DS:SI -> records (DS = module's block)
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
;
; A record with both target type bits set is an operating system fixup, which
; marks a floating-point instruction for a system that would replace it with
; a call to an emulator; it's skipped, as OS/2 skips it.
;
nf1:	mov	al,[si].NER_FLAGS
	and	al,NERF_TARGET
	cmp	al,NERF_TARGET		; an operating system fixup?
	je	nf6b			; yes
	mov	al,[si].NER_TYPE
	cmp	al,NERT_SEL
	je	nf2
	cmp	al,NERT_FAR
	je	nf2
	cmp	al,NERT_OFF
	jne	nf8			; unsupported source type
nf2:	mov	al,[si].NER_FLAGS
	and	al,NERF_TARGET
	jz	nf2a			; an internal reference
	cmp	al,NERF_ORDINAL		; a library's function, by ordinal?
	jne	nf8			; no
	call	ne_imp			; AX:DX = target
	jmp	short nf2b
nf2a:	mov	ax,[si].NER_SEG
	call	ne_sel			; AX = selector of target segment
	mov	dx,[si].NER_OFFSET	; AX:DX = target
nf2b:	jc	nf8
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
; ne_imp
;
; Returns the address of the library function that a relocation record
; refers to: the record has a module reference # (ne_lib has replaced that
; reference with the library's block) and the function's ordinal, which the
; library's entry table must list as an exported entry.
;
; Inputs:
;	DS:SI -> record (DS = module's block)
;
; Outputs:
;	Carry clear if successful, AX = selector, DX = offset
;
; Modifies:
;	AX, DX, DI
;
DEFPROC	ne_imp
	push	bx
	push	cx
	push	si
	push	ds
	mov	bx,[si].NER_SEG		; BX = module reference #
	mov	dx,[si].NER_OFFSET	; DX = ordinal
	dec	bx
	cmp	bx,ds:[NEBUF].NE_NMODS	; is it a valid reference #?
	jae	ni8			; no
	shl	bx,1
	add	bx,ds:[NEBUF].NE_MODTAB
	mov	ds,[bx]			; DS = library's block
	mov	si,ds:[NEBUF].NE_ENTTAB	; DS:SI -> entry table
	mov	di,si
	add	di,ds:[NEBUF].NE_ENTLEN	; DI -> end of entry table
	dec	dx			; DX = ordinal - next bundle's first
ni1:	cmp	si,di			; any more bundles?
	jae	ni8			; no
	lodsw				; AL = # of ordinals, AH = their type
	mov	cl,al
	mov	ch,0
	jcxz	ni8			; no more bundles
	cmp	ah,0FFh			; moveable entries?
	je	ni8			; yes (not supported)
	cmp	dx,cx			; is the ordinal in this bundle?
	jb	ni2			; yes
	sub	dx,cx
	test	ah,ah			; any entries to skip?
	jz	ni1			; no (the ordinals are unused)
	add	si,cx
	add	si,cx
	add	si,cx
	jmp	ni1
ni2:	test	ah,ah			; is the ordinal unused?
	jz	ni8			; yes
	add	si,dx
	add	si,dx
	add	si,dx			; DS:SI -> entry (flags and offset)
	cmp	si,di			; within the table?
	jae	ni8			; no
	test	byte ptr [si],NEEF_EXPORTED
	jz	ni8			; it isn't exported
	mov	dx,[si+1]		; DX = offset
	mov	al,ah
	mov	ah,0			; AX = segment #
	call	ne_sel			; AX = selector
	jmp	short ni9
ni8:	stc
ni9:	pop	ds
	pop	si
	pop	cx
	pop	bx
	ret
ENDPROC	ne_imp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_read
;
; Reads CX bytes into DS:SI, from file offset DX:AX (or from the current file
; position, with ne_next); ne_load makes sure that they fit.
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
	mov	ax,ERR_BADFORMAT
	stc
nr9:	ret
ENDPROC	ne_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_sel
;
; Returns the selector of a module's segment (ne_load puts each one in the
; segment table), or for a code segment, its code alias.
;
; Inputs:
;	AX = segment #
;	DS = module's block
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
;	DS = module's block
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ne_os2
;
; An OS/2 program (one whose NE_OS is NEOS_OS2, or that isn't marked
; NEF_PROTMODE; see ne_load) expects OS/2's starting registers, not ours:
; DS is its automatic data segment, AX is its environment's selector,
; BX is the offset there of its command line, and CX is its data segment's
; size.  Setting those up is the DOSCALLS library's job (see os2start in
; DOSCALLS.ASM), so we make that library's entry point the program's starting
; address, and push the program's own starting address on its stack, where
; the library finds it.  The program must have loaded DOSCALLS, as every
; OS/2 program does; otherwise, we continue at ne_err (see load_ne).
;
; Inputs:
;	DS = PSP, with PSP_START and PSP_STACK set (see load_ne)
;	SS:BP -> load_ne's frame
;
; Modifies:
;	AX, CX, DX, SI, DI, ES
;
DEFPROC	ne_os2
	cmp	ds:[NEBUF].NE_OS,NEOS_OS2
	je	no0			; it's an OS/2 program
	test	byte ptr ds:[NEBUF].NE_FLAGS,NEF_PROTMODE
	jnz	no9			; it's one of ours
no0:	mov	ax,[bp-2]		; AX = first library's block
no1:	test	ax,ax			; any more?
	jz	no8			; no
	mov	es,ax
	mov	si,offset OS2_LIB
	mov	di,NL_NAME
	mov	cx,OS2_LIB_LEN
	repe	cmps byte ptr cs:[si],byte ptr es:[di]
	je	no2			; this is DOSCALLS
	mov	ax,es:[NL_NEXT]
	jmp	no1
no2:	push	ds
	push	es
	pop	ds			; DS = library's block
	mov	dx,ds:[NEBUF].NE_START._OFF
	mov	ax,ds:[NEBUF].NE_START._SEG
	call	ne_sel			; AX:DX = library's entry point
	pop	ds
	jc	no8			; it has none
	les	di,ds:[PSP_STACK]
	sub	di,4
	mov	ds:[PSP_STACK]._OFF,di
;
; The stack still needs room for REG_FRAME and a zero (see load_ne).
;
	cmp	di,size REG_FRAME + 4
	jb	no8
	xchg	dx,ds:[PSP_START]._OFF
	xchg	ax,ds:[PSP_START]._SEG
	xchg	ax,dx
	stosw				; push the program's starting IP
	xchg	ax,dx
	stosw				; and CS
no9:	ret
no8:	jmp	ne_err

OS2_LIB	db	8,"DOSCALLS"		; DOSCALLS's module name (see NL_NAME)
OS2_LIB_LEN equ	$ - OS2_LIB
ENDPROC	ne_os2

DOS	ends

	end
