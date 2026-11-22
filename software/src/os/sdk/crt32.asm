;
; BASIC-DOS SDK: startup code and library for 32-bit C programs
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; CL386 (the Microsoft 386 C Compiler, in TOOLS\BIN) compiles a C program to
; 32-bit code for a flat address space, and LINK386 links it with this file
; (CRT32.OBJ, which must be the first object file) into an LE program, which
; BASIC-DOS runs on an 80386, in protected mode (see MEM32.ASM, and the SDK
; makefile's rule for FIND32.EXE).  The compiler's own library is for OS/2
; 2.0, so the functions here (declared in CRT32.H) are the program's whole
; library: each one is a DOS call.
;
; The compiler's conventions: every segment is in the FLAT group (code in
; _TEXT; data in _DATA, CONST, and _BSS; and variables with no initializer in
; c_common), a function's name starts with an underscore, its parameters are
; pushed right to left, and the function removes them (so main's RET is a
; "ret 8").  A function preserves EBX, ESI, EDI, and EBP, and returns its
; result in EAX; DS, ES, and SS all address the program's memory, and the
; direction flag is clear.
;
	.386p
FLAT	group	_TEXT,_DATA,CONST,_BSS,c_common,STACK

STACK_LEN equ	8192		; size of the stack
ARG_MAX	equ	32		; maximum arguments (including argv[0])
PSP_TAIL equ	80h		; the PSP's command tail, and default DTA
FIND_LEN equ	43		; size of a DOS find block (struct find)

_TEXT	segment dword public use32 'CODE'
_TEXT	ends

_DATA	segment dword public use32 'DATA'
_DATA	ends

CONST	segment dword public use32 'CONST'
CONST	ends

_BSS	segment dword public use32 'BSS'
	public	_doserr
_doserr	dd	?		; error code of the last call that failed
argv	dd	ARG_MAX+1 dup (?)
psp	dw	?		; the PSP's selector
tail	db	128 dup (?)	; a copy of the command tail
_BSS	ends

c_common segment dword public use32 'BSS'
c_common ends

STACK	segment dword stack use32 'STACK'
	db	STACK_LEN dup (?)
STACK	ends

;
; Every object file that the compiler makes refers to __acrtused, to bring
; in the startup code.
;
	public	__acrtused
__acrtused equ	1

_TEXT	segment dword public use32 'CODE'
	assume	cs:FLAT, ds:FLAT, ss:FLAT, es:nothing
	extrn	_main:near

;
; A 32-bit program starts with DS = SS = its memory and ES = its PSP's
; selector (see the BASIC-DOS technical reference).  Copy the command tail
; from the PSP, split it into arguments (at spaces, except in an argument that
; starts with a quote, which ends at the next quote), and call main.
;
start:	mov	[psp],es
	movzx	ecx,byte ptr es:[PSP_TAIL]
	mov	esi,PSP_TAIL+1
	mov	edi,offset FLAT:tail
st1:	jecxz	st2
	mov	al,es:[esi]
	mov	[edi],al
	inc	esi
	inc	edi
	dec	ecx
	jmp	st1
st2:	mov	[edi],cl		; end the tail with a null
	mov	[argv],edi		; and make that the empty argv[0]
	push	ds
	pop	es
	cld
	mov	esi,offset FLAT:tail
	mov	ebx,1			; EBX = # arguments
st3:	lodsb
	cmp	al,' '
	je	st3
	cmp	al,9
	je	st3
	test	al,al			; end of the tail?
	jz	st9			; yes
	cmp	ebx,ARG_MAX		; room for another argument?
	jae	st9			; no
	cmp	al,'"'
	je	st5
	lea	eax,[esi-1]
	mov	[argv+ebx*4],eax
	inc	ebx
st4:	lodsb
	test	al,al
	jz	st9
	cmp	al,' '
	ja	st4
	mov	byte ptr [esi-1],0
	jmp	st3
st5:	mov	[argv+ebx*4],esi
	inc	ebx
st6:	lodsb
	test	al,al
	jz	st9
	cmp	al,'"'
	jne	st6
	mov	byte ptr [esi-1],0
	jmp	st3
st9:	mov	dword ptr [argv+ebx*4],0
	push	offset FLAT:argv
	push	ebx
	call	_main
	push	eax
	call	_exit

;
; void exit(int code)
;
	public	_exit
_exit	proc	near
	mov	eax,[esp+4]
	mov	ah,4Ch
	int	21h
_exit	endp

;
; int open(char *name, int mode)
;
	public	_open
_open	proc	near
	mov	edx,[esp+4]
	mov	eax,[esp+8]
	mov	ah,3Dh
	int	21h			; EAX = handle
	jnc	short op9
	mov	[_doserr],eax
	or	eax,-1
op9:	ret	8
_open	endp

;
; int close(int handle)
;
	public	_close
_close	proc	near
	push	ebx
	mov	ebx,[esp+8]
	mov	ah,3Eh
	int	21h
	pop	ebx
	jc	short cl9
	sub	eax,eax
	ret	4
cl9:	mov	[_doserr],eax
	or	eax,-1
	ret	4
_close	endp

;
; int read(int handle, char *buf, unsigned len)
; int write(int handle, char *buf, unsigned len)
;
	public	_read,_write
_read	proc	near
	mov	ah,3Fh
	jmp	short rw1
_read	endp

_write	proc	near
	mov	ah,40h
rw1:	push	ebx
	mov	ebx,[esp+8]
	mov	edx,[esp+12]
	mov	ecx,[esp+16]
	int	21h			; EAX = # bytes read or written
	pop	ebx
	jc	short rw9
	ret	12
rw9:	mov	[_doserr],eax
	or	eax,-1
	ret	12
_write	endp

;
; int switchar(void)
;
	public	_switchar
_switchar proc	near
	mov	eax,3700h
	int	21h
	movzx	eax,dl
	ret
_switchar endp

;
; int findfirst(char *spec, int attr, struct find *pfind)
; int findnext(struct find *pfind)
;
; DOS's find block is the default DTA, in the PSP, which a 32-bit program
; can't move, so each search's block is copied from there, and findnext
; copies it back first.  Both return 0, or -1 if there are no (more) files.
;
	public	_findfirst,_findnext
_findfirst proc	near
	mov	edx,[esp+4]
	mov	ecx,[esp+8]
	mov	ah,4Eh
	int	21h
	jc	short ff9
	push	esi
	push	edi
	mov	edi,[esp+20]
	call	getdta
	pop	edi
	pop	esi
	sub	eax,eax
	ret	12
ff9:	mov	[_doserr],eax
	or	eax,-1
	ret	12
_findfirst endp

_findnext proc	near
	push	esi
	push	edi
	mov	esi,[esp+12]
	mov	edi,PSP_TAIL
	mov	ecx,FIND_LEN
	mov	es,[psp]
	rep	movsb			; copy the block to the DTA
	push	ds
	pop	es
	mov	ah,4Fh
	int	21h
	jc	short fn9
	mov	edi,[esp+12]
	call	getdta
	sub	eax,eax
	jmp	short fn10
fn9:	mov	[_doserr],eax
	or	eax,-1
fn10:	pop	edi
	pop	esi
	ret	4
_findnext endp

;
; getdta copies the DTA's find block to EDI.
;
getdta	proc	near
	mov	esi,PSP_TAIL
	mov	ecx,FIND_LEN
	push	ds
	mov	ds,[psp]
	rep	movsb
	pop	ds
	ret
getdta	endp

_TEXT	ends

	end	start
