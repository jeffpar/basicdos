;
; BASIC-DOS SDK: MEM32, a 32-bit flat-model (LE) program
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Build it on BASIC-DOS (in protected mode, where LINK386 runs) with the
; tools in TOOLS\BIN, by running MAKE in this directory:
;
;	MAKE MAKEFILE
;
; which assembles it with MASM 5.10B and links it with LINK386 (see
; MEM32.DEF).  The program runs on an 80386, in protected mode with programs
; at ring 3 (the default).
;
; MEM32 [F, I, L, B, D, or A] tests its memory and files (it writes and
; deletes a 70,000-byte file, MEM32.TMP), or causes a page fault (F), issues
; an INT 10h (I), loops until CTRL-C (L), also allocates 4.5Mb (B), or first
; issues an INT 3 (D), which does nothing unless DEBUG.COM is loaded as a
; driver with /H, which stops there, or an INT 3 that follows a NOP (A), as a
; failed ASSERT does, which ends the program (as a fault with vector 03h)
; unless DEBUG.COM is loaded as a driver, which stops there (G continues).
;
; The system's macros (in SRC\INC) work here, too: "MAKE REL=DEBUG MAKEFILE"
; defines DEBUG, as a DEBUG build of BASIC-DOS does, so that DBGBRK is an INT
; 3 and ASSERT is a test followed by a NOP and an INT 3, and otherwise they
; assemble nothing.
;
	include	macros.inc

	.386p
FLAT	group	_TEXT,_DATA,_BSS,STACK

BUFLEN	equ	70000
MORE	equ	20000h
BIG	equ	480000h

_TEXT	segment dword public use32 'CODE'
	assume	cs:FLAT, ds:FLAT, ss:FLAT, es:nothing
start:	mov	[heap],ebx
	mov	[heaplen],ecx
	mov	[base],edx
	mov	edx,offset FLAT:msg1
	call	puts
;
; Print the command tail (ES = PSP).
;
	movzx	ecx,byte ptr es:[80h]
	mov	esi,81h
	mov	edi,offset FLAT:tail
t1:	jecxz	t2
	mov	al,es:[esi]
	mov	[edi],al
	inc	esi
	inc	edi
	dec	ecx
	jmp	t1
t2:	mov	dword ptr [edi],240A0Dh	; CR, LF, '$'
	mov	edx,offset FLAT:msg2
	call	puts
	mov	edx,offset FLAT:tail
	call	puts
	push	ds
	pop	es
	cmp	byte ptr [tail+1],'F'	; fault test?
	jne	t3
	xor	ebx,ebx
	mov	eax,[ebx]		; (page fault at address 0)
t3:	cmp	byte ptr [tail+1],'L'	; loop test (until CTRL-C)?
	jne	t3a
	mov	edx,offset FLAT:loopmsg
	call	puts
	jmp	$
t3a:	cmp	byte ptr [tail+1],'I'	; INT test?
	jne	t3b
	int	10h
t3b:	cmp	byte ptr [tail+1],'D'	; debugger test?
	jne	t3c
	int	3			; (as DBGBRK is, in a DEBUG build)
t3c:	cmp	byte ptr [tail+1],'A'	; assertion test?
	jne	t4
	nop				; (as a failed ASSERT is, likewise)
	int	3
t4:	inc	[stage]			; stage 1: registers
	mov	eax,[base]
	cmp	eax,offset FLAT:start
	jne	fail
	mov	eax,[heap]
	cmp	eax,offset FLAT:stktop
	jb	fail
	inc	[stage]			; stage 2: BSS is zero, and writable
	mov	edi,offset FLAT:buf2
	mov	ecx,BUFLEN
	xor	eax,eax
	cld
	repe	scasb
	jne	fail
	mov	edi,offset FLAT:buf1
	mov	ecx,BUFLEN
	mov	eax,12345h
t5:	mov	[edi],al
	xor	[edi],ah
	inc	edi
	add	eax,01030507h
	rol	eax,3
	dec	ecx
	jnz	t5
	inc	[stage]			; stage 3: create and write
	mov	edx,offset FLAT:fname
	xor	ecx,ecx
	mov	ah,3Ch
	int	21h
	jc	fail
	mov	ebx,eax
	mov	edx,offset FLAT:buf1
	mov	ecx,BUFLEN
	mov	ah,40h
	int	21h
	jc	fail
	cmp	eax,BUFLEN
	jne	fail
	mov	ah,3Eh
	int	21h
	jc	fail
	inc	[stage]			; stage 4: open and read
	mov	edx,offset FLAT:fname
	mov	ax,3D00h
	int	21h
	jc	fail
	mov	ebx,eax
	mov	edx,offset FLAT:buf2
	mov	ecx,BUFLEN+100
	mov	ah,3Fh
	int	21h
	jc	fail
	cmp	eax,BUFLEN
	jne	fail
	mov	ah,3Eh
	int	21h
	jc	fail
	inc	[stage]			; stage 5: compare
	mov	esi,offset FLAT:buf1
	mov	edi,offset FLAT:buf2
	mov	ecx,BUFLEN
	repe	cmpsb
	jne	fail
	inc	[stage]			; stage 6: delete
	mov	edx,offset FLAT:fname
	mov	ah,41h
	int	21h
	jc	fail
	mov	edx,offset FLAT:fname
	mov	ax,3D00h
	int	21h
	jnc	fail			; (it should be gone)
	inc	[stage]			; stage 7: more memory
	mov	ebx,MORE
	mov	ah,48h
	int	21h
	jc	fail
	mov	edx,[heap]
	add	edx,[heaplen]
	cmp	eax,edx			; at the end of what we had?
	jne	fail
	mov	edi,eax
	mov	ecx,MORE/4
	xor	eax,eax
	repe	scasd			; is it zeroed?
	jne	fail
	sub	edi,MORE
	mov	ecx,MORE/4
	mov	eax,12345678h
	rep	stosd
	cmp	dword ptr [edi-4],12345678h
	jne	fail
	cmp	byte ptr [tail+1],'B'	; big allocation test?
	jne	t6
	mov	ebx,BIG
	mov	ah,48h
	int	21h
	jc	fail
	mov	edi,eax
	mov	dword ptr [edi],11111111h
	mov	dword ptr [edi+BIG-4],22222222h
	mov	dword ptr [edi+400000h],33333333h
	mov	ebx,10000h
	mov	ah,48h
	int	21h			; (another, after the big one)
	jc	fail
	mov	dword ptr [eax+0FFFCh],44444444h
	cmp	dword ptr [edi],11111111h
	jne	fail
	cmp	dword ptr [edi+BIG-4],22222222h
	jne	fail
	cmp	dword ptr [edi+400000h],33333333h
	jne	fail
	mov	edx,offset FLAT:bigmsg
	call	puts
t6:	inc	[stage]			; stage 8: an unsupported function
	mov	ah,35h
	int	21h
	jnc	fail
	inc	[stage]			; stage 9: a call in a far-away place
	mov	ah,30h
	int	21h
	cmp	al,2
	jb	fail
	mov	edx,offset FLAT:okmsg
	call	puts
	mov	ax,4C00h
	int	21h
fail:	mov	al,[stage]
	add	[badnum],al
	mov	edx,offset FLAT:badmsg
	call	puts
	mov	ax,4C01h
	int	21h
puts	proc	near
	mov	ah,9
	int	21h
	ret
puts	endp
_TEXT	ends

_DATA	segment dword public use32 'DATA'
msg1	db	'MEM32: 32-bit code running',13,10,'$'
msg2	db	'MEM32 tail:$'
okmsg	db	'MEM32 passed',13,10,'$'
loopmsg	db	'MEM32 looping',13,10,'$'
bigmsg	db	'MEM32 big allocation passed',13,10,'$'
badmsg	db	'MEM32 failed at stage '
badnum	db	'0',13,10,'$'
fname	db	'MEM32.TMP',0
stage	db	0
	align	4
heap	dd	0
heaplen	dd	0
base	dd	0
_DATA	ends

_BSS	segment dword public use32 'BSS'
tail	db	132 dup(?)
buf1	db	BUFLEN dup(?)
buf2	db	BUFLEN+100 dup(?)
_BSS	ends

STACK	segment dword stack use32 'STACK'
	db	4096 dup(?)
stktop	label	byte
STACK	ends

	end	start
