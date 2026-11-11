;
; BASIC-DOS Ring 3 Memory Table Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: MEMTESTS
;
; Checks that the PMB table and the LDTs can share the system area (see
; docs/bdtech/mmu) until it's full.  We start NCOPIES sessions, each of which
; allocates small blocks, with a code alias for half of them, until DOS
; refuses.  All the while, the sessions' LDTs are growing, which moves the LDTs
; of the other sessions, so each one keeps checking that all of its selectors
; still lead to its own blocks, and that its code aliases still work.  Once the
; pool is full, it makes sure that an EXEC either works or returns an error,
; and frees half of its blocks and allocates others.  We do all that twice, and
; in the end, the PMB table must be as long as it was when we started.  Each
; session that succeeds leaves a file that says whether it filled the pool, so
; we know if one ended with a fault, or if the pool never filled.  A problem
; prints "MEMTESTS failed", and a test that stops the system has failed, too.
;
; SESSIONS must be at least NCOPIES plus the session that runs this, and
; without enough of them, or anywhere but ring 3, it just prints that it was
; skipped.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	dosapi.inc

NCOPIES		equ	7		; enough to fill the pool
NROUNDS		equ	2
MAXBLOCKS	equ	300		; (more than a session's LDT can hold)
PMBLEN		equ	32		; length of a PMB (see cpu.inc)
TAG		equ	14		; where a block holds its own selector

CODE	segment
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	100h

	.286p

DEFPROC	main
	mov	ax,cs
	mov	bx,ds
	cmp	ax,bx			; real mode (a COM's CS = DS)?
	je	m0			; yes
	test	al,3			; ring 3?
	jnz	m1			; yes
m0:	PRINTF	<"MEMTESTS skipped (needs ring 3)",13,10>
	int	20h
;
; Our files are on the default drive (a session's first program doesn't have an
; environment to find COMSPEC in).
;
m1:	mov	ah,DOS_DSK_GETDRV
	int	21h
	add	al,'A'
	mov	[progname],al
	mov	[cmdline],al
	mov	[result],al
	push	ds
	pop	es
;
; A copy's tail is always a space and a letter.
;
	cmp	byte ptr ds:[PSP_CMDTAIL],2	; are we a copy?
	jne	parent			; no
	cmp	byte ptr ds:[PSP_CMDTAIL+2],'N'	; just a copy for an EXEC?
	je	ok			; yes
	jmp	child
ok:	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
ENDPROC	main

DEFPROC	parent
	call	pmb_count
	mov	[pmbs],ax
	mov	[spbx].SPB_ENVSEG,0
	mov	[spbx].SPB_CMDLINE.OFF,offset cmdline
	mov	[spbx].SPB_CMDLINE.SEG,ds
	mov	al,SFH_NONE
	mov	[spbx].SPB_SFHIN,al
	mov	[spbx].SPB_SFHOUT,al
	mov	[spbx].SPB_SFHERR,al
	mov	[spbx].SPB_SFHAUX,al
	mov	[spbx].SPB_SFHPRN,al
	mov	bp,NROUNDS
p1:	sub	si,si
p2:	mov	ax,si
	add	al,'A'
	mov	[cmdletter],al
	mov	bx,offset spbx
	sub	cx,cx			; (no pipeline stages)
	DOSUTIL	LOAD
	jnc	p2a
	jmp	p8
p2a:
	mov	[sessions][si],cl
	inc	si
	cmp	si,NCOPIES
	jb	p2
	sub	si,si
p3:	mov	cl,[sessions][si]
	DOSUTIL	START
	jc	pf
	inc	si
	cmp	si,NCOPIES
	jb	p3
	sub	si,si
p4:	mov	cl,[sessions][si]
	DOSUTIL	WAITEND
	jc	pf
	inc	si
	cmp	si,NCOPIES
	jb	p4
;
; Every session must have succeeded, and one must have filled the pool.
;
	sub	si,si
	mov	[anyfull],0
p4a:	mov	ax,si
	add	al,'A'
	mov	[resletter],al
	mov	dx,offset result
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jc	pf
	xchg	bx,ax
	mov	dx,offset isfull
	mov	cx,1
	mov	ah,DOS_HDL_READ
	int	21h
	jc	pf
	mov	al,[isfull]
	or	[anyfull],al
	mov	ah,DOS_HDL_CLOSE
	int	21h
	mov	dx,offset result
	mov	ah,DOS_DSK_DELETE
	int	21h
	inc	si
	cmp	si,NCOPIES
	jb	p4a
	cmp	[anyfull],0		; did the pool fill?
	je	pf			; no
	dec	bp
	jz	p4b
	jmp	p1
p4b:
	call	pmb_count
	cmp	ax,[pmbs]		; did every block go away?
	je	p5			; yes
pf:	jmp	fail
p5:
	PRINTF	<"MEMTESTS passed",13,10>
	int	20h
p8:	cmp	ax,ERR_NOSESSION	; not enough sessions?
	jne	pf			; no
	cmp	bp,NROUNDS		; (the first round had enough)
	jne	pf
;
; The copies we loaded hold their sessions and memory until they end (and
; if we left one above COMMAND, it couldn't grow back to reload itself), so
; end each one: mark it, and then start it, so that it ends.
;
p8a:	dec	si			; any (more) copies loaded?
	js	p8b			; no
	mov	cl,[sessions][si]
	DOSUTIL	END,1
	DOSUTIL	START
	DOSUTIL	WAITEND
	jmp	p8a
p8b:	PRINTF	<"MEMTESTS skipped (needs more sessions)",13,10>
	int	20h
ENDPROC	parent

DEFPROC	fail
	PRINTF	<"MEMTESTS failed",13,10>
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	fail

;
; pmb_count returns the number of PMBs in AX.
;
DEFPROC	pmb_count
	sub	si,si
pc1:	mov	cx,si
	mov	dl,4
	mov	di,offset pmbbuf
	DOSUTIL	QRYMEM
	jc	pc9
	inc	si
	jmp	pc1
pc9:	xchg	ax,si
	ret
ENDPROC	pmb_count

;
; alloc allocates a block and records its selector in entry SI, which it tags,
; and for every other block, runs code through an alias of it.  Carry is set
; if DOS refused (and any other error fails the test).
;
DEFPROC	alloc
	mov	bx,1
	mov	ah,DOS_MEM_ALLOC
	int	21h
	jc	al8
	mov	es,ax
	mov	bx,si
	add	bx,bx
	mov	word ptr [blocks][bx],ax
	mov	es:[TAG],ax
	inc	si			; (it's ours, even if its alias fails)
	test	si,1
	jnz	al9
	mov	word ptr es:[0],034B8h	; MOV AX,1234h
	mov	word ptr es:[2],0CB12h	; RETF
	mov	bx,ax
	mov	ax,DOS_UTL_ALIAS SHL 8
	int	INT_DOSUTIL
	jc	al8
	mov	word ptr [target+2],ax
	mov	word ptr [target],0
	sub	ax,ax
	call	dword ptr [target]
	cmp	ax,1234h
	jne	alf
	clc
al9:	ret
al8:	cmp	ax,ERR_NOMEMORY
	stc
	je	al9
alf:	jmp	fail
ENDPROC	alloc

;
; verify checks that the blocks that we have are still ours.
;
DEFPROC	verify
	push	si
	add	si,si
v1:	sub	si,2
	jb	v9
	mov	bx,word ptr [blocks][si]
	test	bx,bx			; did we free this one?
	jz	v1			; yes
	lar	ax,bx			; is its selector still in use?
	jnz	vf			; no
	mov	es,bx
	cmp	es:[TAG],bx		; is it still the same block?
	je	v1			; yes
vf:	jmp	fail
v9:	pop	si
	ret
ENDPROC	verify

DEFPROC	child
	mov	al,ds:[PSP_CMDTAIL+2]
	mov	[resletter],al
	sub	si,si			; SI = # of blocks
c1:	call	alloc
	jc	c2
	test	si,7
	jnz	c1a
	call	verify
c1a:	cmp	si,MAXBLOCKS
	jb	c1
c2:	call	verify
;
; A session whose LDT isn't near its limit must have run out of pool.
;
	mov	ax,si
	shr	ax,1
	add	ax,si			; AX = # of descriptors, about
	cmp	ax,240
	jae	c3
	mov	[isfull],1
	PRINTF	<"MEMTESTS pool full at %d blocks",13,10>,si
	jmp	short c4
c3:	PRINTF	<"MEMTESTS LDT full at %d blocks",13,10>,si
;
; With little or no room, an EXEC must either work or report it.
;
c4:	push	si
	push	ds
	pop	es
	mov	[epbx].EPB_CMDTAIL.OFF,offset tail
	mov	[epbx].EPB_CMDTAIL.SEG,ds
	mov	[epbx].EPB_FCB1.OFF,-1
	mov	dx,offset progname
	mov	bx,offset epbx
	mov	ax,DOS_PSP_EXEC
	int	21h
	pop	si
	jnc	c5
	cmp	ax,ERR_NOMEMORY
	jne	cfail
;
; Keep checking while other sessions' LDTs grow, and they move ours.
;
c5:	mov	di,20
c6:	push	di
	call	verify
	sub	cx,cx
	mov	dx,100
	DOSUTIL	SLEEP
	pop	di
	dec	di
	jnz	c6
;
; Free every other block, and allocate others, which should reuse the room.
;
	mov	di,si			; DI = # of blocks
	and	di,NOT 1
c7:	sub	di,2
	jb	c8
	mov	bx,di
	add	bx,bx
	mov	es,word ptr [blocks][bx]
	mov	word ptr [blocks][bx],0
	mov	ah,DOS_MEM_FREE
	int	21h
	jc	cfail
	jmp	c7
c8:	call	verify
	mov	di,8
c9:	cmp	si,MAXBLOCKS
	jae	c10
	push	di
	call	alloc
	pop	di
	jc	c10
	dec	di
	jnz	c9
c10:	call	verify
	push	ds
	pop	es
	mov	dx,offset result
	sub	cx,cx
	mov	ah,DOS_HDL_CREATE
	int	21h
	jc	cfail
	xchg	bx,ax
	mov	dx,offset isfull
	mov	cx,1
	mov	ah,DOS_HDL_WRITE
	int	21h
	jc	cfail
	mov	ah,DOS_HDL_CLOSE
	int	21h
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
cfail:	jmp	fail
ENDPROC	child

progname db	"A:\TESTS\MISC\MEMTESTS.COM",0
cmdline	db	"A:\TESTS\MISC\MEMTESTS.COM "
cmdletter db	"A",0
result	db	"A:\MEMTESTS."
resletter db	"A",0
isfull	db	0
anyfull	db	0
tail	db	2," N",13
pmbs	dw	0
target	dd	0
sessions db	NCOPIES dup (0)
	even
spbx	SPB	<>
epbx	EPB	<>
pmbbuf	db	PMBLEN dup (0)

	COMHEAP	<MAXBLOCKS*2+1024>	; (must be the last item)
blocks	equ	$

CODE	ends
	end	main
