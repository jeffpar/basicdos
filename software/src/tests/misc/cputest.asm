;
; BASIC-DOS CPU$ Driver Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Prints the CPU type and, if the CPU$ driver is loaded, its physical memory
; arena, and then tests its functions: allocations with GDT and LDT selectors,
; a mapping of video memory, invalid requests, and freeing everything, which
; must leave the arena as it was.  Exits with code 0 if every check passes
; (including when CPU$ isn't loaded, eg, on an 8086), or 1 if any fails.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dosapi.inc
	include	cpu.inc

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
	mov	[free0].LOW,cx
	mov	[free0].HIW,dx
	call	arena
	mov	[npmbs],bx
;
; Allocate 100000 bytes with GDT selectors, and 4K with an LDT selector.
;
	mov	bp,1
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
; cpu_ok
;
; Calls CPU$ function AH, and fails the test if it returns an error.
;
DEFPROC	cpu_ok
	call	far ptr DDINT_CPU
	jc	m8
	ret
ENDPROC	cpu_ok

;
; cpu_err
;
; Calls CPU$ function AH, and fails the test unless it returns error experr.
;
DEFPROC	cpu_err
	call	far ptr DDINT_CPU
	jnc	m8
	cmp	ax,[experr]		; is it the expected error?
	jne	m8
	ret
ENDPROC	cpu_err

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

	DEFWORD	npmbs,0
	DEFWORD	experr,0
	DEFWORD	sel2,0
	DEFWORD	sel3,0
	DEFLONG	free0,0
	DEFLONG	addr1,0
	DEFLONG	addr2,0

	COMHEAP	<size PMB>	; COMHEAP (heap size) must be the last item

pmb_buf	equ	$

CODE	ends
	end	main
