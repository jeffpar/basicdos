;
; BASIC-DOS NE Loader Stub
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; An MZ stub that makes an NE program run in real mode, on BASIC-DOS or any
; other DOS, with no second copy of the program.  In protected mode, BASIC-DOS
; loads the NE image, and ignores this code.  tools/misc/mkne.js adds it to an
; NE file (node tools/misc/mkne.js --stub in.exe out.exe), with an MZ header
; whose header size is zero and whose load image is the entire file, so that:
;
;	- DOS loads the header, this code, and the NE image, so we don't have
;	  to find and open the program's file, and a file offset is an image
;	  offset
;	- the header's minimum allocation leaves room for our work, and its
;	  SS:SP is above all of that, since we do all of this on that stack
;
; We mirror what BASIC-DOS's NE loader does in protected mode (see load_ne),
; with paragraphs in place of selectors, for the same kind of NE program, whose
; segments are FIXED, with no imports, and only internal relocations; we don't
; check any of that, since only the program's linker can get it wrong:
;
;	1. Pick each segment's final paragraph, at or above its data in the
;	   file (and past the segment before it), leaving that in NES_SIZE.
;	2. Apply each segment's relocation records, which follow its data.
;	3. Starting with the last segment, move each one up to its final
;	   paragraph, since it can then only overwrite what's already been
;	   used, and zero the rest of it, up to the next segment.
;	4. Start the program as load_ne does, with DS and ES addressing the
;	   PSP.
;
; We use only 8086 instructions, so an NE program that does, too, can run on an
; 8088.  This never runs in protected mode, so writing to our own image (ie,
; the copy of the NE header and segment table) is fine.
;
; Assemble with MASM 4.00, and make a flat binary (the code has no relocations
; of its own), which mkne.js reads:
;
;	MASM /MX /R /DFINAL /I..\OS\INC NESTUB.ASM,NESTUB.OBJ,NUL;
;	LINK NESTUB.OBJ,NESTUB.EXE;
;	EXE2BIN NESTUB.EXE NESTUB.BIN
;
	DOSPSP equ 1
	DOSNE equ 1
	include	macros.inc
	include	8086.inc
	include	dosapi.inc

CODE	segment
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;
; Every register gets reused, so the initial AX and the PSP go on the stack.
;
main:	push	ax
	push	es
	push	cs
	pop	ds			; DS:0 = the start of the file
	mov	si,ds:[EXE_NEHDR].OFF	; DS:SI -> NE header
	mov	di,si
	add	di,[si].NE_SEGTAB	; DS:DI -> segment table
	mov	ax,[si].NE_SHIFT
	test	ax,ax
	jnz	m1
	mov	al,9			; (a shift of 0 means 9)
m1:	sub	al,4
	mov	byte ptr [si].NE_SHIFT,al; from alignment units to paragraphs
;
; DX is the next free paragraph, starting after the segment table.
;
	mov	ax,[si].NE_NSEGS
	mov	cl,3
	shl	ax,cl
	add	ax,di
	add	ax,15
	inc	cx			; CL = 4
	shr	ax,cl
	mov	dx,cs
	add	dx,ax
	mov	bp,1			; BP = segment #
;
; Step 1: replace NES_SECTOR with the paragraph of the segment's data (if any),
; and NES_SIZE with its final paragraph.
;
p1:	mov	ax,[di].NES_SECTOR
	test	ax,ax			; any data?
	jz	p2			; no
	mov	cl,byte ptr [si].NE_SHIFT
	shl	ax,cl
	mov	bx,cs
	add	ax,bx			; AX = paragraph of its data
	mov	[di].NES_SECTOR,ax
	cmp	ax,dx			; is that past the previous segment?
	jb	p2			; no
	mov	dx,ax			; yes, so it needn't move
p2:	mov	ax,[di].NES_SIZE
	cmp	ax,1
	sbb	bx,bx
	neg	bx			; BX:AX = size (0 means 64K)
	cmp	bp,[si].NE_AUTODATA
	jne	p3
	add	ax,[si].NE_HEAP
	adc	bx,0
	add	ax,[si].NE_STACK
	adc	bx,0			; BX:AX = size of DGROUP
p3:	add	ax,15
	adc	bx,0
	mov	cl,4
	shr	ax,cl
	ror	bx,cl
	or	ax,bx			; AX = paragraphs
;
; An initial SP of 0 means the top of the segment, which we know only here.
;
	cmp	bp,[si].NE_STACKPTR.SEG	; the stack's segment?
	jne	p4			; no
	cmp	[si].NE_STACKPTR.OFF,0
	jne	p4
	mov	bx,ax
	shl	bx,cl
	mov	[si].NE_STACKPTR.OFF,bx
p4:	mov	[di].NES_SIZE,dx
	add	dx,ax
	add	di,size NESEG
	inc	bp
	cmp	bp,[si].NE_NSEGS
	jbe	p1
	push	dx			; save the end of the last segment
;
; Step 2: apply the relocation records.
;
	mov	bp,si
	add	bp,[si].NE_SEGTAB	; BP -> segment table (for seg_para)
	mov	di,bp
	mov	cx,[si].NE_NSEGS
r1:	test	[di].NES_FLAGS,NESF_RELOCS
	jz	r8
	mov	ax,[di].NES_SECTOR
	test	ax,ax			; any data?
	jz	r8			; no
	push	cx
	push	di
	mov	si,[di].NES_LENGTH
	mov	ds,ax			; DS:SI -> # of records
	lodsw
	xchg	cx,ax			; CX = # of records
	jcxz	r7
r3:	mov	ax,[si].NER_SEG
	call	seg_para		; AX = target's paragraph
	mov	dx,[si].NER_OFFSET	; AX:DX = target
	mov	di,[si].NER_SOURCE	; DS:DI -> first source
r4:	mov	bx,[di]			; BX = next source
	test	[si].NER_FLAGS,NERF_ADDITIVE
	jz	r5
	add	dx,bx			; add the target offset to the source
	mov	bx,-1			; (and there's no next source)
r5:	cmp	[si].NER_TYPE,NERT_SEL
	je	r6
	mov	[di],dx			; store the offset
	cmp	[si].NER_TYPE,NERT_OFF
	je	r6a
	inc	di
	inc	di
r6:	mov	[di],ax			; store the paragraph
r6a:	mov	di,bx			; DS:DI -> next source
	inc	bx			; any more sources?
	jnz	r4			; yes
	add	si,size NEREL
	loop	r3
r7:	pop	di
	pop	cx
	push	cs
	pop	ds
r8:	add	di,size NESEG
	loop	r1
;
; Step 3: move and zero the segments, from the last to the first; DX is the
; paragraph after the one we're on, and DI is just past its table entry.
;
	pop	dx
	mov	si,ds:[EXE_NEHDR].OFF
	mov	cx,[si].NE_NSEGS
m3:	sub	di,size NESEG
	push	cx
	push	di
	mov	ax,[di].NES_SIZE	; AX = final paragraph
	mov	bx,[di].NES_SECTOR	; BX = paragraph of data
	mov	cx,[di].NES_LENGTH	; CX = length of data
	test	bx,bx			; any data?
	jnz	m3a			; yes
	sub	cx,cx			; no
m3a:	mov	ds,bx
	mov	es,ax
	push	cx
	cmp	ax,bx			; does it need to move?
	je	m4			; no
	mov	si,cx
	dec	si
	mov	di,si			; DS:SI, ES:DI -> last byte of data
	std
	rep	movsb
	cld
m4:	pop	di			; ES:DI -> just past the data
	mov	cx,dx
	sub	cx,ax			; CX = paragraphs to the next segment
	mov	dx,ax			; (DX is now the paragraph of this one)
	add	cx,cx
	add	cx,cx
	add	cx,cx			; CX = words (at most 64K's worth)
	mov	bx,di
	inc	bx
	shr	bx,1
	sub	cx,bx			; less the data's
	sub	ax,ax
	test	di,1			; odd length?
	jz	m5			; no
	stosb				; yes, so the rest starts on a word
m5:	rep	stosw
	pop	di
	pop	cx
	push	cs
	pop	ds
	loop	m3
;
; Step 4: start the program.
;
	mov	si,ds:[EXE_NEHDR].OFF
	pop	es			; ES = PSP
	pop	bx			; BX = initial AX
	mov	ax,[si].NE_STACKPTR.SEG
	call	seg_para
	mov	dx,[si].NE_STACKPTR.OFF
	cli
	mov	ss,ax
	mov	sp,dx
	sti
	mov	ax,[si].NE_START.SEG
	call	seg_para
	push	ax
	push	[si].NE_START.OFF
	push	es
	pop	ds			; DS = PSP
	xchg	ax,bx			; AX = initial AX
	db	OP_RETF

;
; Returns a segment's final paragraph.
;
; Inputs:
;	AX = segment # (1 or more)
;	BP -> segment table
;
; Outputs:
;	AX = final paragraph
;
; Modifies:
;	AX, DI
;
seg_para:
	dec	ax
	add	ax,ax
	add	ax,ax
	add	ax,ax
	add	ax,bp
	xchg	di,ax
	mov	ax,cs:[di].NES_SIZE
	ret

CODE	ends

	end	main
