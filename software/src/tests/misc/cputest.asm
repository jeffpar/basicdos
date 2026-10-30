;
; BASIC-DOS CPU$ Driver Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Prints the CPU type and the CPU$ driver's memory arena, and then tests its
; functions: an allocation from the top of conventional memory, resized with
; CPU_REALLOC, copies with CPU_MOVE (including an overlapping one), and in
; protected mode, allocations with GDT and LDT selectors, a mapping of video
; memory, and aliases (code and read-only), or in real mode, the segments
; that CPU_MAP and CPU_ALIAS return instead; then invalid requests, and freeing
; everything, which must leave the arena as it was.  Exits with code 0 if
; every check passes, or 1 if any fails.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dosapi.inc
	include	cpu.inc

STR_LEN	equ	9			; length of str1 (see move)

CODE	segment
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:CODE
	org	100h

DEFPROC	main
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	mov	al,[CPU_TYPE]
	push	cs
	pop	es
	ASSUME	ES:CODE
	PRINTF	<"CPU type %d",13,10>,ax
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU
	jnc	m1
	PRINTF	<"CPU$ not loaded",13,10>
	jmp	m9
m1:	call	info
	mov	[pmflag],ah
	mov	[free0].LOW,cx
	mov	[free0].HIW,dx
	call	arena
	mov	[npmbs],bx
	sub	bp,bp			; BP = step #
	call	common
	test	byte ptr [pmflag],CPUF_PM
	jnz	m2
	call	realmode
	jmp	m7
;
; Allocate 100000 bytes with GDT selectors, and 4K with an LDT selector.
;
m2:	inc	bp
	mov	al,0
	mov	si,1
	mov	di,86A0h		; SI:DI = 100000
	call	alloc
	mov	[addr1].LOW,cx
	mov	[addr1].HIW,dx
	inc	bp
	mov	al,SELF_LDT
	sub	si,si
	mov	di,4096
	call	alloc
	mov	[sel2],ax
	mov	[addr2].LOW,cx
	mov	[addr2].HIW,dx
;
; Map 4000 bytes of CGA video memory (B8000h).
;
	inc	bp
	mov	al,0
	mov	dx,000Bh
	mov	cx,8000h
	sub	si,si
	mov	di,4000
	mov	ah,CPU_MAP
	call	cpu_ok
	mov	[sel3],ax
	PRINTF	<"Map %#lx at 000B8000: sel %#x",13,10>,di,si,ax
	call	arena
	call	aliases
;
; These requests must fail: freeing an unallocated address, unmapping a
; fixed selector, and allocating more memory than there is.
;
	inc	bp
	mov	[experr],ERR_BADADDR
	mov	cx,1234h
	sub	dx,dx
	mov	ah,CPU_FREE
	call	cpu_err
	inc	bp
	mov	[experr],ERR_INVALID
	mov	bx,08h
	mov	cx,1
	mov	ah,CPU_UNMAP
	call	cpu_err
	inc	bp
	mov	[experr],ERR_NOMEMORY
	mov	al,0
	mov	si,0FFFFh
	sub	di,di
	mov	ah,CPU_ALLOC
	call	cpu_err
;
; Free everything, and make sure the arena is back where it started.
;
	inc	bp
	mov	cx,[addr1].LOW
	mov	dx,[addr1].HIW
	mov	ah,CPU_FREE
	call	cpu_ok
	inc	bp
	mov	bx,[sel3]
	sub	cx,cx
	mov	ah,CPU_UNMAP
	call	cpu_ok
	inc	bp
	mov	cx,[addr2].LOW
	mov	dx,[addr2].HIW
	mov	ah,CPU_FREE
	call	cpu_ok
	inc	bp
	test	byte ptr [sel2],4	; was the 2nd selector an LDT selector?
	jz	m8			; no
m7:	inc	bp
	mov	cx,[addr6].LOW
	mov	dx,[addr6].HIW
	mov	ah,CPU_FREE
	call	cpu_ok
	call	info
	cmp	cx,[free0].LOW		; is the largest free block the same?
	jne	m8
	cmp	dx,[free0].HIW
	jne	m8
	call	arena
	cmp	bx,[npmbs]		; and the number of blocks?
	jne	m8
	PRINTF	<"CPUTEST passed",13,10>
m9:	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
m8:	PRINTF	<"CPUTEST failed (step %d)",13,10>,bp
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	main

;
; common
;
; Allocates 4K at the top of conventional memory, shrinks it to 2K, makes sure
; it can't grow to 8K (the next block is reserved), grows it back to 4K, and
; copies a string with CPU_MOVE, forward and then onto itself, 1 byte higher
; (backward); the block stays allocated (see addr6).
;
DEFPROC	common
	inc	bp
	mov	al,SELF_LOW OR SELF_HIGH
	sub	si,si
	mov	di,4096
	call	alloc
	mov	[addr6].LOW,cx
	mov	[addr6].HIW,dx
	inc	bp
	mov	di,2048
	call	resize
	call	cpu_ok
	inc	bp
	mov	[experr],ERR_NOMEMORY
	mov	di,8192
	call	resize
	call	cpu_err
	inc	bp
	mov	di,4096
	call	resize
	call	cpu_ok
	inc	bp
	mov	si,offset str1
	mov	di,offset str2
	call	move			; copy str1 to str2
	mov	si,offset str1
	mov	di,offset str2
	mov	cx,STR_LEN
	repe	cmpsb
	jne	cm8
	inc	bp
	mov	si,offset str2
	mov	di,offset str2 + 1
	call	move			; copy str2 to str2 + 1
	mov	si,offset str1
	mov	di,offset str2 + 1
	mov	cx,STR_LEN
	repe	cmpsb
	jne	cm8
	mov	si,offset str2
	PRINTF	<"Move %s",13,10>,si
	ret
	DEFLBL	fail,near
cm8:	jmp	m8
ENDPROC	common

;
; resize
;
; Sets up a CPU_REALLOC of the block at addr6 to DI bytes.
;
DEFPROC	resize
	mov	cx,[addr6].LOW
	mov	dx,[addr6].HIW
	sub	si,si
	mov	ah,CPU_REALLOC
	ret
ENDPROC	resize

;
; realmode
;
; In real mode, CPU_ALLOC, CPU_MAP, and CPU_ALIAS return segments.
;
DEFPROC	realmode
	inc	bp
	mov	al,SELF_LOW OR SELF_HIGH
	sub	si,si
	mov	di,16
	call	alloc			; AX = segment
	mov	bx,ax
	mov	ax,cx
	mov	cl,4
	shr	ax,cl
	mov	cl,12
	shl	dx,cl
	or	ax,dx			; AX = segment of the address
	cmp	ax,bx			; are they the same?
	jne	fail
	mov	cl,4
	mov	dx,bx
	shl	bx,cl
	mov	cl,12
	shr	dx,cl
	mov	cx,bx
	mov	ah,CPU_FREE
	call	cpu_ok
	inc	bp
	mov	al,0
	mov	dx,000Bh
	mov	cx,8000h
	sub	si,si
	mov	di,4000
	mov	ah,CPU_MAP
	call	cpu_ok
	cmp	ax,0B800h		; segment of B8000h?
	jne	rm8
	inc	bp
	mov	bx,ax
	mov	al,SELF_CODE
	mov	ah,CPU_ALIAS
	call	cpu_ok
	cmp	ax,bx			; the same segment?
	jne	rm8
	cmp	cx,8000h		; for B8000h?
	jne	rm8
	cmp	dx,000Bh
	jne	rm8
	PRINTF	<"Map and alias: %#x",13,10>,ax
	inc	bp
	mov	[experr],ERR_BADADDR
	mov	cx,1234h
	sub	dx,dx
	mov	ah,CPU_FREE
	call	cpu_err
	inc	bp
	mov	[experr],ERR_NOMEMORY
	mov	al,0
	mov	si,0FFFFh
	sub	di,di
	mov	ah,CPU_ALLOC
	jmp	cpu_err
rm8:	jmp	m8
ENDPROC	realmode

;
; move
;
; Copies STR_LEN bytes from DS:SI to DS:DI with CPU_MOVE.
;
DEFPROC	move
	mov	ax,ds
	mov	dx,ax
	mov	cl,4
	shl	ax,cl
	mov	cl,12
	shr	dx,cl			; DX:AX = address of DS
	mov	bx,offset mvpkt
	mov	[bx].MV_SRC.LOW,si
	add	[bx].MV_SRC.LOW,ax
	mov	[bx].MV_SRC.HIW,dx
	adc	[bx].MV_SRC.HIW,0
	mov	[bx].MV_DST.LOW,di
	add	[bx].MV_DST.LOW,ax
	mov	[bx].MV_DST.HIW,dx
	adc	[bx].MV_DST.HIW,0
	mov	[bx].MV_LEN.LOW,STR_LEN
	mov	[bx].MV_LEN.HIW,0
	mov	ah,CPU_MOVE
	jmp	cpu_ok
ENDPROC	move

;
; cpu_ok
;
; Calls CPU$ function AH, and fails the test if it returns an error.
;
DEFPROC	cpu_ok
	call	far ptr DDINT_CPU
	jc	ce8
	ret
ENDPROC	cpu_ok

;
; cpu_err
;
; Calls CPU$ function AH, and fails the test unless it returns error experr.
;
DEFPROC	cpu_err
	call	far ptr DDINT_CPU
	jnc	ce8
	cmp	ax,[experr]		; is it the expected error?
	jne	ce8
	ret
ce8:	jmp	m8
ENDPROC	cpu_err

;
; aliases
;
; Aliases the 4K block's LDT selector as ring 3 code, and the video selector as
; read-only data: each alias must be a new selector for the same address.
; Then frees the code alias, after which aliasing it must fail.
;
DEFPROC	aliases
	inc	bp
	mov	al,SELF_LDT OR SELF_CODE OR SELF_USER
	mov	bx,[sel2]
	mov	ah,CPU_ALIAS
	call	cpu_ok
	cmp	ax,bx			; is it a new selector?
	je	al7
	test	al,4			; an LDT selector?
	jz	al7
	cmp	cx,[addr2].LOW		; for the same address?
	jne	al7
	cmp	dx,[addr2].HIW
	je	al1
al7:	jmp	m8
al1:	mov	[sel4],ax
	PRINTF	<"Alias %#x as code: sel %#x at %#lx",13,10>,bx,ax,cx,dx
	inc	bp
	mov	al,SELF_RDONLY
	mov	bx,[sel3]
	mov	ah,CPU_ALIAS
	call	cpu_ok
	cmp	ax,bx			; is it a new selector?
	je	al8
	cmp	cx,8000h		; for B8000h?
	jne	al8
	cmp	dx,000Bh
	je	al2
al8:	jmp	m8
al2:	mov	[sel5],ax
	PRINTF	<"Alias %#x as read-only: sel %#x at %#lx",13,10>,bx,ax,cx,dx
	inc	bp
	mov	bx,[sel4]
	sub	cx,cx
	mov	ah,CPU_UNMAP
	call	cpu_ok
	inc	bp
	mov	[experr],ERR_INVALID
	mov	al,SELF_LDT
	mov	bx,[sel4]
	mov	ah,CPU_ALIAS
	call	cpu_err
	inc	bp
	mov	bx,[sel5]
	sub	cx,cx
	mov	ah,CPU_UNMAP
	call	cpu_ok
	ret
ENDPROC	aliases

;
; info
;
; Prints and returns the CPU_GETINFO results (DX:CX = largest free block).
;
DEFPROC	info
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU
	mov	bl,ah
	mov	ah,0
	mov	bh,ah
	PRINTF	<"CPU$ %d, flags %#x, free %#lx",13,10>,ax,bx,cx,dx
	ret
ENDPROC	info

;
; alloc
;
; Allocates SI:DI bytes with SELF_* flags AL, prints the results, and returns
; the selector in AX and the address in DX:CX (the test fails if it fails).
;
DEFPROC	alloc
	mov	ah,CPU_ALLOC
	mov	bx,1			; owner
	call	cpu_ok
	push	ax
	PRINTF	<"Alloc %#lx at %#lx: sel %#x",13,10>,di,si,cx,dx,ax
	pop	ax
	ret
ENDPROC	alloc

;
; arena
;
; Prints every PMB, returning the number of PMBs in BX.
;
DEFPROC	arena
	PRINTF	<"PMB Sig Type Address  Length   Owner Sel  #",13,10>
	sub	bx,bx
ar1:	mov	di,offset pmb_buf
	mov	ah,CPU_QUERY
	call	far ptr DDINT_CPU
	jc	ar9
	mov	al,[di].PMB_SIG
	cbw
	mov	cl,[di].PMB_TYPE
	mov	ch,ah
	PRINTF	<"%3d  %c  %3d  ">,bx,ax,cx
	PRINTF	<"%08lx %08lx ">,[di].PMB_ADDR,:2,[di].PMB_LEN,:2
	mov	ax,[di].PMB_OWNER
	mov	cx,[di].PMB_SEL
	mov	dx,[di].PMB_NSEL
	PRINTF	<"%04x  %04x %d",13,10>,ax,cx,dx
	inc	bx
	jmp	ar1
ar9:	ret
ENDPROC	arena

	DEFBYTE	pmflag,0
	DEFWORD	npmbs,0
	DEFWORD	experr,0
	DEFWORD	sel2,0
	DEFWORD	sel3,0
	DEFWORD	sel4,0
	DEFWORD	sel5,0
	DEFLONG	free0,0
	DEFLONG	addr1,0
	DEFLONG	addr2,0
	DEFLONG	addr6,0
	even
mvpkt	MOVEPKT	<>
	DEFLBL	str1,byte
	db	"CPU_MOVE",0
	DEFLBL	str2,byte
	db	STR_LEN+1 dup (0)

	COMHEAP	<size PMB>	; COMHEAP (heap size) must be the last item

pmb_buf	equ	$

CODE	ends
	end	main
