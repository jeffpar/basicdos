;
; BASIC-DOS Ring 3 Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: R3TESTS
;
; Checks that a ring 3 program can't harm the kernel, or stop the system, by
; misusing DOS, or using CLI, OUT, or BIOS interrupts (see docs/bdtech/mmu).
; Many of these tests are supposed to end the program, so each one runs in its
; own copy (R3TESTS, plus a letter), and we check how the copy ended: normally,
; or with a CPU fault, whose line it prints.  A test that stops the system
; instead has failed, too.
;
; Anywhere but ring 3, it just prints that it was skipped.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	devapi.inc
	include	dosapi.inc

R3_USERINT	equ	60h		; a vector for programs to hook
INT_IRQ0	equ	08h		; a vector that they can't
INT_BIOS	equ	13h		; one that they can't issue, either
GDT_WINDOW	equ	0800h		; what follows the GDT's first part
GDT_IDENTITY	equ	0A000h		; and the first identity selector
F		equ	EXTYPE_FAULT

CODE	segment
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	5
	DEFLBL	CALL5,near
	org	100h

	.286p

DEFPROC	main
	mov	ax,cs
	mov	bx,ds
	cmp	ax,bx			; real mode (a COM's CS = DS)?
	je	m0			; yes
	test	al,3			; ring 3?
	jnz	m1			; yes
m0:	PRINTF	<"R3TESTS skipped (needs ring 3)",13,10>
	int	20h
;
; BASIC-DOS puts COMSPEC first in the environment, and we're on the same drive.
;
m1:	mov	es,ds:[PSP_ENVSEG]
	mov	al,es:[8]
	mov	[progname],al
	mov	[epbx].EPB_CMDTAIL.OFF,offset tail
	mov	[epbx].EPB_CMDTAIL.SEG,ds
	mov	[epbx].EPB_FCB1.OFF,-1
	push	ds
	pop	es
	mov	al,ds:[PSP_CMDTAIL+2]	; AL = letter, if any
	cmp	ds:[PSP_CMDTAIL],0	; are we a copy?
	je	m2			; no
	sub	al,'A'
	cbw
	add	ax,ax
	xchg	bx,ax
	jmp	tests[bx]		; run the test
m2:	sub	si,si			; SI = test #
m3:	mov	ax,si
	add	al,'A'
	mov	[tail+2],al
	mov	dx,offset progname
	mov	bx,offset epbx
	mov	ax,DOS_PSP_EXEC
	int	21h
	jc	m7			; it couldn't be loaded
	mov	ah,DOS_PSP_RETCODE
	int	21h			; AL = exit code, AH = exit type
	cmp	ah,[results][si]	; did it end as it should?
	jne	m7			; no
	test	ah,ah			; normally?
	jnz	m4			; no
	test	al,al			; with no errors?
	jnz	m7			; no
m4:	inc	si
	mov	bx,si
	add	bx,bx
	cmp	tests[bx],0		; any more?
	jne	m3			; yes
	PRINTF	<"R3TESTS passed",13,10>
	int	20h
m7:	mov	al,[tail+2]
	cbw
	PRINTF	<"R3TESTS test %c failed",13,10>,ax
	jmp	bad
ENDPROC	main
;
; Copies end here, normally: "failif" is for a call that should have failed.
;
failif:	jnc	bad
ok:	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
bad:	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
;
; alloc allocates BX paragraphs in ES.
;
alloc:	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h
	jc	bad
	mov	es,ax
	ret
;
; The null selector has base address zero, as does a selector for segment 0.
;
ta:	sub	ax,ax
	mov	es,ax
	mov	ah,DOS_MEM_FREE
	int	21h
	jmp	failif
tb:	sub	bx,bx
	DOSUTIL	MAPSEG,0
	mov	es,ax
	mov	ah,DOS_MEM_FREE
	int	21h
	jmp	failif
;
; Our PSP's block, which the kernel needs until we end.
;
tc:	mov	ah,DOS_MEM_FREE
	int	21h
	jmp	failif
;
; A block's selector must follow its length, in both directions.
;
td:	mov	bx,1
	call	alloc
	inc	bx
	mov	ah,DOS_MEM_REALLOC
	int	21h
	jc	bad
	mov	word ptr es:[16],1	; (the new part)
	jmp	ok
te:	mov	bx,2
	call	alloc
	dec	bx
	mov	ah,DOS_MEM_REALLOC
	int	21h
	mov	word ptr es:[16],1	; (the freed part, which should fault)
	jmp	bad
;
; A block has a selector for every 64K, which it loses when it shrinks, and
; gets back when it grows (which needs its next descriptor to be free).
;
tf:	mov	bx,2000h
	call	alloc
	mov	dx,es
	add	dx,8			; DX = its next selector
	mov	bx,1000h
	mov	ah,DOS_MEM_REALLOC
	int	21h
	jc	tf2
	lar	cx,dx			; is that selector gone?
	jz	tf2			; no
	mov	bx,1800h
	mov	ah,DOS_MEM_REALLOC
	int	21h
	jc	tf2
	lsl	cx,dx
	cmp	cx,7FFFh		; does it cover the rest of the block?
	jne	tf2
tf1:	jmp	ok
tf2:	jmp	bad
;
; DS in a selector that a shrink frees has to be 0 when DOS returns.
;
tg:	mov	bx,2000h
	call	alloc
	mov	ax,es
	add	ax,8
	mov	ds,ax
	mov	bx,1
	mov	ah,DOS_MEM_REALLOC
	int	21h
	mov	ax,ds
	test	ax,ax
	jz	tf1
	jmp	bad
;
; INT 22h is only for the kernel's stubs, even with a stack it can't read, or a
; return address that it can't use.
;
th:	mov	sp,-1
	clc
	int	INT_DOSEXIT
	jmp	bad
ti:	push	FL_INTS
	push	1234h
	push	5678h
	clc
	int	INT_DOSEXIT
	jmp	bad
;
; A stub for a vector that isn't this program's (our INT 21h stub is first).
;
tj:	mov	ax,(DOS_MSC_GETVEC SHL 8) OR INT_DOSFUNC
	int	21h
	pushf
	push	cs
	push	offset bad
	push	es
	push	14			; (the last stub)
	db	OP_RETF
;
; An interrupt that can't be reflected to a hook, and has no previous handler.
;
tk:	mov	dx,offset hook
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR R3_USERINT
	int	21h
	mov	sp,5
	int	R3_USERINT
	jmp	bad
hook:	mov	ax,1234h
	iret
;
; CALL 5 reads its return address from the caller's stack.
;
tl:	mov	cl,DOS_MSC_GETVER
	mov	sp,-1
	jmp	CALL5
;
; PRINTF on a stack with no room for it.
;
tm:	mov	bp,sp
	mov	sp,16
	PRINTF	<13,10>
	mov	sp,bp
	jmp	ok
;
; Freeing the memory that we're running in.
;
tn:	mov	bx,1
	call	alloc
	mov	si,offset stub
	sub	di,di
	mov	cx,stubend-stub
	cld
	rep	movsb
	mov	bx,es
	mov	ax,DOS_UTL_ALIAS SHL 8
	int	INT_DOSUTIL		; AX = its code alias
	push	ax
	push	0
	db	OP_RETF
stub:	mov	ah,DOS_MEM_FREE
	int	21h
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
stubend:
;
; Shrinking the PSP's block below the code that we're running.
;
to:	mov	bx,size PSP SHR 4
	mov	ah,DOS_MEM_REALLOC
	int	21h
	jmp	bad
;
; Bad pointers: the kernel faults on the first, and we find the others first,
; since the transfers don't respect limits, and a fault in a driver is fatal.
;
tp:	sub	dx,dx
	mov	ds,dx
	mov	ax,DOS_DSK_GETATTR
	int	21h
	jmp	bad
tq:	mov	bx,1
	call	alloc
	mov	bx,STDOUT
	mov	ah,DOS_HDL_WRITE
	jmp	short tr1
tr:	mov	bx,1
	call	alloc
	mov	bx,STDIN
	mov	ah,DOS_HDL_READ
tr1:	push	es
	pop	ds
	mov	dx,8
	mov	cx,32			; (16 bytes past its limit)
	int	21h
	jmp	bad
ts:	mov	bx,1
	call	alloc
	push	ds
	push	es
	pop	ds
	mov	dx,8
	mov	ah,DOS_DSK_SETDTA
	int	21h			; (8 bytes from its limit)
	pop	ds
	mov	dx,offset fcbx
	mov	ah,DOS_FCB_SREAD
	int	21h
	jmp	bad
;
; DOS_PSP_SET with our PSP, which must work, and with something that isn't one.
;
tt:	mov	bx,ds
	mov	ah,DOS_PSP_SET
	int	21h
	jnc	tt1
	jmp	bad
tt1:	mov	bx,1234h
	mov	ah,DOS_PSP_SET
	int	21h
	jmp	failif
;
; A hook of a vector that isn't on the list, and one that is.
;
tu:	mov	dx,offset hook
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_IRQ0
	int	21h
	jc	tu1
tu0:	jmp	bad
tu1:	mov	ax,(DOS_MSC_GETVEC SHL 8) OR INT_IRQ0
	int	21h
	mov	ax,es
	or	ax,bx			; 0:0, so there's nothing to chain to?
	jnz	tu0
	jmp	ok
tv:	mov	dx,offset hook
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR R3_USERINT
	int	21h
	jc	tu0
	sub	ax,ax
	int	R3_USERINT
	cmp	ax,1234h
	jne	tu0
	jmp	ok
;
; Overwriting what the kernel used to trust in our PSP, and in our parent's
; (every test after these depends on the kernel ignoring it).
;
tw:	mov	word ptr ds:[PSP_PARENT],1234h
	mov	word ptr ds:[PSP_STACK].OFF,2
	mov	word ptr ds:[PSP_STACK].SEG,1234h
	mov	word ptr ds:[PSP_EXIT].OFF,5678h
	mov	word ptr ds:[PSP_EXIT].SEG,1234h
	mov	byte ptr ds:[PSP_SCB],5
	mov	ax,ds:[PSP_ERROR].SEG	; AX = the kernel's selector
	mov	ds:[PSP_CTRLC].SEG,ax
	mov	word ptr ds:[PSP_CTRLC].OFF,0FFF0h
	mov	ds:[PSP_DTAPREV].SEG,ax
	jmp	ok
tx:	mov	es,ds:[PSP_PARENT]
	mov	word ptr es:[PSP_STACK].OFF,2
	mov	word ptr es:[PSP_STACK].SEG,1234h
	mov	byte ptr es:[PSP_SCB],5
	jmp	ok
;
; A selector in a register (DOS_PSP_CREATE), or in an EPB, that we can't use.
;
ty:	mov	dx,ds:[PSP_ERROR].SEG	; DX = the kernel's selector
	mov	ah,DOS_PSP_CREATE
	int	21h
	jmp	failif
tz:	mov	ax,ds:[PSP_ERROR].SEG	; AX = the kernel's selector
	mov	[epbx].EPB_CMDTAIL.SEG,ax
	mov	dx,offset progname
	mov	bx,offset epbx
	mov	ax,DOS_PSP_EXEC
	int	21h
	mov	ah,DOS_PSP_RETCODE
	int	21h			; AH = exit type
	cmp	ah,EXTYPE_FAULT		; did the kernel fault using it?
	jne	tz1			; no
	jmp	ok
tz1:	jmp	bad
;
; An EXEC2 with nothing loaded.
;
tza:	mov	bx,offset epbx
	sub	dx,dx
	mov	ax,DOS_PSP_EXEC2
	int	21h
	jmp	failif
;
; Instructions that need more than the IOPL 0 that we have (the OUT is to the
; diagnostic port, which is harmless on a machine that doesn't fault).
;
tzb:	cli
	jmp	tz1
tzc:	out	80h,al
	jmp	tz1
;
; The system tables that the GDT's limit covers must not be usable as segments
; (they hold other sessions' descriptors).
;
tzd:	mov	si,GDT_WINDOW + 3
tzd1:	verr	si
	jz	tzd9
	verw	si
	jz	tzd9
	add	si,8
	cmp	si,GDT_IDENTITY
	jb	tzd1
	jmp	ok
tzd9:	jmp	bad
;
; Ring 3 code can't issue a BIOS interrupt.
;
tze:	int	INT_BIOS
	jmp	bad
;
; Functions for drivers and the kernel fail at ring 3.
;
tzf:	DOSUTIL	LOCK
	jmp	failif
;
; DOS_UTL_ALIAS works only for a block of our own.
;
tzg:	mov	bx,ds:[PSP_ERROR].SEG	; BX = the kernel's selector
	mov	ax,DOS_UTL_ALIAS SHL 8
	int	INT_DOSUTIL
	jmp	failif
;
; An IOCTL's data must be in our memory, before a driver can use it.
;
tzh:	mov	bx,1
	call	alloc
	push	es
	pop	ds
	mov	si,15
	mov	bx,STDOUT
	mov	cx,200
	sub	dx,dx
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETLEN
	int	21h
	jmp	bad
;
; A chain of programs has to stop with an error, before it runs out of the
; session's ring 0 stack.
;
tzi:	mov	al,ds:[PSP_CMDTAIL+2]
	mov	[tail+2],al
	mov	dx,offset progname
	mov	bx,offset epbx
	mov	ax,DOS_PSP_EXEC
	int	21h
	jc	tzi1
	mov	ah,DOS_PSP_RETCODE
	int	21h			; AL = exit code, AH = exit type
	test	ax,ax			; did the rest of the chain end well?
	jnz	tzd9			; no
	jmp	ok
tzi1:	cmp	ax,ERR_NOMEMORY		; is this the end of the chain?
	jne	tzd9			; no
	jmp	ok
;
; An LDT grows as needed (past its original 96 descriptors), and the selectors
; that a program already has keep working when it does.
;
tzj:	sub	si,si			; SI = # of blocks
tzj1:	mov	bx,1
	mov	ah,DOS_MEM_ALLOC
	int	21h
	jc	tzj2
	mov	es,ax
	mov	es:[0],ax		; each block holds its own selector
	test	si,si
	jnz	tzj1a
	mov	dx,ax			; DX = the first block
tzj1a:	mov	di,ax			; DI = the last block
	inc	si
	cmp	si,200
	jb	tzj1
tzj2:	cmp	si,96			; did it get past the original limit?
	jbe	tzj9			; no
	mov	es,dx
	cmp	es:[0],dx		; is the first block still there?
	jne	tzj9			; no
	mov	es,di
	cmp	es:[0],di		; and the last?
	jne	tzj9			; no
	jmp	ok
tzj9:	jmp	bad
;
; A block can grow past the end of its LDT (which holds 32 descriptors at a
; time), as its next selector is then a new descriptor.
;
tzk:	mov	bx,1
	mov	ah,DOS_MEM_ALLOC
	int	21h
	jc	tzj9
	mov	es,ax
	mov	dx,ax			; DX = this block
	shr	ax,3
	inc	ax
	test	al,31			; is this the LDT's last descriptor?
	jnz	tzk
	mov	es:[0],dx
	mov	bx,1001h		; (16 bytes more than 64K)
	mov	ah,DOS_MEM_REALLOC
	int	21h
	jc	tzj9
	mov	ax,dx
	add	ax,8			; AX = its next selector
	verw	ax
	jnz	tzj9
	mov	es,ax
	mov	word ptr es:[0],1
	mov	es,dx
	cmp	es:[0],dx		; is the block's start still intact?
	jne	tzj9
	jmp	ok
;
; DOS_UTL_MAPSEG with AL = 1 reads a word below 1Mb, and only below 1Mb,
; without freeing the session's selector, which BASIC's DEF SEG may be using.
; If it did free it, using ES again would fault.
;
tzl:	mov	bx,BIOS_DATA SHR 4
	DOSUTIL	MAPSEG,0		; AX = the session's selector
	jc	tzj9
	mov	es,ax
	sub	bx,bx
	mov	si,BIOS_DATA		; BX:SI -> the same memory
	DOSUTIL	MAPSEG,1		; AX = the word there
	jc	tzj9
	cmp	ax,es:[0]		; the same word (with ES still valid)?
	jne	tzj9
	mov	bx,10h
	sub	si,si			; BX:SI = 1Mb
	DOSUTIL	MAPSEG,1
	jmp	failif

tests	dw	ta,tb,tc,td,te,tf,tg,th,ti,tj,tk,tl,tm
	dw	tn,to,tp,tq,tr,ts,tt,tu,tv,tw,tx,ty,tz,tza,tzb,tzc
	dw	tzd,tze,tzf,tzg,tzh,tzi,tzj,tzk,tzl,0
results	db	0,0,0,0,F,0,0,F,F,F,F,F,0
	db	F,F,F,F,F,F,0,0,0,0,0,0,0,0,F,F
	db	0,F,0,0,F,0,0,0,0

progname db	"A:\TESTS\MISC\R3TESTS.COM",0
tail	db	2," A",13
fcbx	db	14 dup (0)		; (just FCB_RECSIZE matters)
	dw	128
	db	21 dup (0)
epbx	EPB	<>

	COMHEAP	1024		; COMHEAP (heap size) must be the last item

CODE	ends
	end	main
