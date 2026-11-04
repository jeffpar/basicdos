;
; BASIC-DOS File I/O Buffer Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Writes a file from one memory block and reads it back into another, whole
; and from the middle (so with partial first and last sectors, and at an odd
; offset in the block), and then rewrites its middle and reads it all again,
; comparing the data each time.  The blocks come from the top of memory, which
; in protected mode is above 1Mb, where the diskette BIOS can't reach them (so
; FDC$ goes through its own buffer, and the fixed disk BIOS, a selector of the
; buffer's own), and at ring 0, we make sure of that.
;
; It also makes small reads, which go through the disk buffers: before and
; after the rewrite (so a stale copy of a sector is noticed), and of the
; current volume's first sector, which no buffer can keep (see read_buffer),
; comparing that with a read of the whole sector.  Exits with code 0 if every
; check passes, or 1 if any fails.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dosapi.inc
	include	cpu.inc

FILELEN	 equ	8000			; a few tracks on the test floppy
READOFF	 equ	1001			; file offset of the partial read
READLEN	 equ	5000
READBUF	 equ	123			; block offset of the partial read
WRITEOFF equ	3001			; file offset of the rewrite
WRITELEN equ	4000
SMALLLEN equ	16			; a read of part of a sector

CODE	SEGMENT
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:CODE
	org	100h

DEFPROC	main
	cld
	mov	si,offset block1
	call	alloc
	mov	si,offset block2
	call	alloc
	mov	es,[block1]		; fill the first block with a pattern
	sub	di,di
	mov	cx,FILELEN
m1:	mov	ax,di
	xor	al,ah
	add	al,ah
	stosb
	loop	m1
	mov	ah,DOS_HDL_CREATE
	sub	cx,cx
	mov	dx,offset filename
	call	dos
	xchg	bx,ax			; BX = handle
	mov	si,offset block1
	mov	ah,DOS_HDL_WRITE
	mov	cx,FILELEN
	sub	dx,dx
	call	xfer
	mov	ah,DOS_HDL_CLOSE
	call	dos
	mov	ax,DOS_HDL_OPENRW
	mov	dx,offset filename
	call	dos
	xchg	bx,ax			; BX = handle
	call	readall
	mov	dx,READOFF
	call	seek
	mov	si,offset block2
	mov	ah,DOS_HDL_READ
	mov	cx,READLEN
	mov	dx,READBUF
	call	xfer
	mov	si,READOFF
	mov	di,READBUF
	mov	cx,READLEN
	call	compare
	call	readsmall		; (leaves the sector in a disk buffer)
	mov	es,[block1]		; change part of the first block
	mov	di,WRITEOFF
	mov	cx,WRITELEN
m2:	not	byte ptr es:[di]
	inc	di
	loop	m2
	mov	dx,WRITEOFF
	call	seek
	mov	si,offset block1
	mov	ah,DOS_HDL_WRITE
	mov	cx,WRITELEN
	mov	dx,WRITEOFF
	call	xfer
	call	readsmall		; (and it mustn't have the old data)
	call	readall
	mov	ah,DOS_HDL_CLOSE
	call	dos
	mov	ah,DOS_DSK_DELETE
	mov	dx,offset filename
	call	dos
	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	[volume],al		; volume name = current drive
	mov	ax,DOS_HDL_OPENRO
	mov	dx,offset volume
	call	dos
	xchg	bx,ax			; BX = handle
	mov	si,offset block1
	mov	ah,DOS_HDL_READ
	mov	cx,SMALLLEN
	sub	dx,dx
	call	xfer			; part of the first sector
	sub	dx,dx
	call	seek
	mov	si,offset block2
	mov	ah,DOS_HDL_READ
	mov	cx,512
	sub	dx,dx
	call	xfer			; all of the first sector
	sub	si,si
	sub	di,di
	mov	cx,SMALLLEN
	call	compare
	mov	ah,DOS_HDL_CLOSE
	call	dos
	mov	dx,offset passed
	call	print
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
ENDPROC	main

;
; alloc allocates a block from the top of memory, and stores its segment (or
; selector) at DS:SI.
;
DEFPROC	alloc
	mov	ax,(DOS_MEM_ALLOC SHL 8) OR MCBTYPE_HIGH
	mov	bx,(FILELEN + READBUF + 15) SHR 4
	call	dos
	mov	[si],ax
	mov	cx,cs
	mov	dx,ds
	cmp	cx,dx			; real mode (where CS = DS)?
	je	al9			; yes
	test	cl,3			; ring 3 (where CPU$ is out of reach)?
	jnz	al9			; yes
	xchg	bx,ax			; BX = selector
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	far ptr DDINT_CPU	; DX:CX = base address
	cmp	dx,10h			; above 1Mb?
	jb	fail			; no
	mov	dx,offset above
	call	print
al9:	ret
ENDPROC	alloc

;
; readsmall reads a few bytes from the part of the file that's rewritten, and
; compares them with the first block.
;
DEFPROC	readsmall
	mov	dx,WRITEOFF
	call	seek
	mov	si,offset block2
	mov	ah,DOS_HDL_READ
	mov	cx,SMALLLEN
	sub	dx,dx
	call	xfer
	mov	si,WRITEOFF
	sub	di,di
	mov	cx,SMALLLEN
	jmp	short compare
ENDPROC	readsmall

;
; readall reads the whole file into the second block, and compares the blocks.
;
DEFPROC	readall
	sub	dx,dx
	call	seek
	mov	si,offset block2
	mov	ah,DOS_HDL_READ
	mov	cx,FILELEN
	sub	dx,dx
	call	xfer
	sub	si,si
	sub	di,di
	mov	cx,FILELEN
	DEFLBL	compare,near		; compare block1:SI with block2:DI
	mov	es,[block2]
	push	ds
	mov	ds,[block1]
	repe	cmpsb
	pop	ds
	jne	fail
	ret
ENDPROC	readall

DEFPROC	fail
	mov	dx,offset failed
	call	print
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	fail

;
; xfer issues read or write function AH for CX bytes at offset DX of the block
; whose segment is at DS:SI, and all CX bytes must be transferred.
;
DEFPROC	xfer
	push	ds
	mov	ds,[si]
	int	21h
	pop	ds
	jc	fail
	cmp	ax,cx
	jne	fail
	ret
ENDPROC	xfer

DEFPROC	seek
	mov	ax,DOS_HDL_SEEKBEG
	sub	cx,cx			; CX:DX = file offset
	DEFLBL	dos,near		; any DOS function that can't fail
	int	21h
	jc	fail
	ret
ENDPROC	seek

DEFPROC	print
	mov	ah,DOS_TTY_PRINT
	int	21h
	ret
ENDPROC	print

block1		dw	0
block2		dw	0
filename	db	"BUFTESTS.TMP",0
volume		db	"A:",0
above		db	"BUFTESTS block above 1Mb",13,10,'$'
passed		db	"BUFTESTS passed",13,10,'$'
failed		db	"BUFTESTS failed",13,10,'$'
	COMHEAP	0
CODE	ENDS
	end	main
