;
; BASIC-DOS Startup Code for Microsoft 386 C Programs
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; CL386 (the Microsoft 386 C Compiler) comes with a C library for OS/2 2.0
; (LIBC.LIB, in TOOLS\LIB\386), whose startup module (crt0) expects OS/2's
; entry state, and whose other modules call a handful of OS/2 2.0 functions.
; This module replaces crt0, and provides those functions (with DOS calls),
; so LINK386 can build LE programs, which BASIC-DOS runs on an 80386 in
; protected mode, with the rest of the library unchanged.  It must be the
; first object file, so the library's crt0 is never linked (eg, in a folder
; of TOOLS\DEMOS):
;
;	CL386 /c /I..\..\INCLUDE\386 PROG.C
;	LINK386 /NOE ..\..\LIB\386\BDCRT386 PROG,,NUL,..\..\LIB\386\,PROG.DEF;
;
; /NOE keeps LINK386 from loading the modules that the library's extended
; dictionary says go with the ones it needs, which include its crt0.
;
; Assemble it with MASM5 (BDCRT386.OBJ in TOOLS\LIB\386 was made that way):
;
;	MASM5 /MX BDCRT386.ASM,BDCRT386.OBJ,NUL;
;
; The OS/2 functions are the ones that the library's stdio, heap, and
; startup functions need (see DOS32READ and the others below); a program that
; calls a library function needing any other (eg, fopen, which calls
; DOS32OPEN) has unresolved externals when it's linked.  The library has no
; getch, so this module has one.
;
; The segments are declared here in the order the library needs (the first
; module's order is the program's), since Microsoft's crt0 orders them by
; marking its object file DOSSEG, which also defines _end, and the library's
; modules use an empty FLAT group, which MASM5 can't make, so this module's
; FLAT group lists every segment, and it defines _end (the bottom of the
; stack, where __chkstk's checks stop) itself.
;
	.386

STACK_LEN equ	8192		; size of the stack (the library's default)
REGION_LEN equ	10000h		; size of each heap region (see DOS32ALLOCMEM)
PSP_ENVSEG equ	2Ch		; the PSP's environment selector
PSP_TAIL equ	80h		; the PSP's command tail
PAG_COMMIT equ	10h		; DOS32ALLOCMEM and DOS32SETMEM's commit flag
ERROR_NOT_ENOUGH_MEMORY equ 8

_TEXT	segment dword public use32 'CODE'
	extrn	_main:near,_exit:near,__exit:near,__heapinit:near
	extrn	__setargv:near,__setenvp:near,__cinit:near
	extrn	__NMSG_WRITE:near,__FF_MSGBANNER:near
_TEXT	ends
NULL	segment para public use32 'BEGDATA'
NULL	ends
_DATA	segment dword public use32 'DATA'
_DATA	ends
CDATA	segment dword common use32 'DATA'
CDATA	ends
XIB	segment dword public use32 'DATA'
XIB	ends
XI	segment dword public use32 'DATA'
XI	ends
XIE	segment dword public use32 'DATA'
XIE	ends
XPB	segment dword public use32 'DATA'
XPB	ends
XP	segment dword public use32 'DATA'
XP	ends
XPE	segment dword public use32 'DATA'
XPE	ends
XCB	segment dword public use32 'DATA'
XCB	ends
XC	segment dword public use32 'DATA'
XC	ends
XCE	segment dword public use32 'DATA'
XCE	ends
HDR	segment byte public use32 'MSG'
HDR	ends
MSG	segment byte public use32 'MSG'
MSG	ends
PAD	segment byte common use32 'MSG'
PAD	ends
EPAD	segment byte common use32 'MSG'
EPAD	ends
CONST	segment dword public use32 'CONST'
CONST	ends
_BSS	segment dword public use32 'BSS'
_BSS	ends
XOB	segment dword public use32 'BSS'
XOB	ends
XO	segment dword public use32 'BSS'
XO	ends
XOE	segment dword public use32 'BSS'
XOE	ends
c_common segment dword public use32 'BSS'
c_common ends
STACK	segment para stack use32 'STACK'
	public	_end
_end	label	byte
	db	STACK_LEN dup (?)
STACK	ends

FLAT	group	_TEXT,NULL,_DATA,CDATA,XIB,XI,XIE,XPB,XP,XPE,XCB,XC,XCE
FLAT	group	HDR,MSG,PAD,EPAD,CONST,_BSS,XOB,XO,XOE,c_common,STACK

	assume	cs:FLAT, ds:FLAT, ss:FLAT, es:nothing
	extrn	_environ:dword,___argv:dword,___argc:dword
	extrn	__osmajor:dword,__osminor:dword,__heap_regionsize:dword

	public	__acrtused
__acrtused equ	9876h		; (every compiled object file needs it)

_DATA	segment
	public	__acmdln,__aenvptr,__atopsp,__aexit_rtn,__acfinfo
__acmdln dd	0		; the command line (argv[0], then the tail)
__aenvptr dd	0		; the environment strings
__atopsp dd	0		; the top of the stack
__aexit_rtn dd	offset FLAT:__exit	; how __amsg_exit exits
__acfinfo db	"_C_FILE_INFO=",0	; (the variable that stdenvp skips)
brk	dd	0		; the next address DOS32ALLOCMEM gives out
lim	dd	0		; the end of the program's memory
_DATA	ends

_TEXT	segment

;
; __astart
;
; A 32-bit program starts with DS = SS = its memory, ES = its PSP's selector,
; EBX = the address after its image, and ECX = how much memory follows that
; (see the BASIC-DOS technical reference).  The library expects OS/2's
; environment block, which is the environment strings, followed by the
; command line as two strings, the program's name and the command tail, so
; make that from copies of the PSP's environment and tail, and then do what
; crt0 does.  BASIC-DOS doesn't give a program its name, so the name is "C",
; as it is for an OS/2 program (the library ignores the tail if the name is
; empty).
;
	public	__astart
__astart:
	cld
	mov	[__atopsp],esp
	mov	[brk],ebx
	add	ecx,ebx
	mov	[lim],ecx
	mov	ax,es
	mov	fs,ax			; FS = PSP
	mov	es,es:[PSP_ENVSEG]
	sub	eax,eax
	sub	edi,edi
	or	ecx,-1
st1:	scasb				; at the empty string that ends them?
	je	short st2		; yes
	repne	scasb			; no, so skip a string
	jmp	st1
;
; R6009 is "not enough space for environment".
;
st9:	mov	eax,9
	jmp	__amsg_exit
st2:	mov	esi,edi			; ESI = the strings' length
	push	ds
	pop	es
	movzx	ebx,byte ptr fs:[PSP_TAIL]
	mov	edi,[brk]
	lea	edx,[edi+esi+4]
	add	edx,ebx			; EDX = the end of the copies
	call	grow
	jc	st9
	mov	[brk],edx
	mov	byte ptr [edi],0	; (stdargv looks for a name before it)
	inc	edi
	mov	[__aenvptr],edi
	lea	eax,[edi+esi]
	mov	[__acmdln],eax
	mov	ecx,esi
	sub	esi,esi
	mov	ds,fs:[PSP_ENVSEG]
	rep	movsb			; copy the environment strings
	mov	ax,'C'
	stosw				; the program's name
	mov	ecx,ebx
	mov	esi,PSP_TAIL+1
	push	fs
	pop	ds
	rep	movsb			; copy the command tail
	mov	es:[edi],ah
	push	es
	pop	ds
	mov	ah,30h
	int	21h			; AL = DOS's major version, AH = minor
	movzx	ecx,ah
	mov	[__osminor],ecx
	movzx	eax,al
	mov	[__osmajor],eax
	mov	[__heap_regionsize],REGION_LEN
	call	__heapinit
	call	__setargv
	call	__setenvp
	call	__cinit
	push	[_environ]
	push	[___argv]
	push	[___argc]
	call	_main
	add	esp,12
	push	eax
	call	_exit

;
; __cintDIV (R6003, "integer divide by 0") and __amsg_exit, which displays
; the message for the run-time error in EAX and ends the program.
;
	public	__cintDIV,__amsg_exit
__cintDIV:
	mov	eax,3
	mov	[__aexit_rtn],offset FLAT:_exit
__amsg_exit:
	push	eax
	call	__FF_MSGBANNER
	call	__NMSG_WRITE
	push	0FFh
	call	[__aexit_rtn]

;
; The OS/2 2.0 functions, which take their parameters on the stack (pushed
; right to left, and removed by the caller), and return 0 or an error code in
; EAX; like C functions, they preserve EBX, ESI, EDI, and EBP.
;
; APIRET DOS32ALLOCMEM(PVOID *ppb, ULONG cb, ULONG flags)
; APIRET DOS32SETMEM(PVOID pb, ULONG cb, ULONG flags)
; APIRET DOS32FREEMEM(PVOID pb)
;
; A program's memory can grow only at its end (DOS_MEM_ALLOC adds to it), so
; DOS32ALLOCMEM gives out addresses from there, a page at a time, and memory
; is added when it's committed.  The heap reserves a region (up to 16 of
; them) and commits a piece at a time, from its start, so any memory given
; out after a region is reserved needs the whole region first, which is why
; __astart makes each one 64K instead of the library's 4Mb (a bigger block
; gets a region of its own size).  Nothing is ever freed.
;
	public	DOS32ALLOCMEM,DOS32SETMEM,DOS32FREEMEM
DOS32ALLOCMEM:
	mov	eax,[brk]
	add	eax,0FFFh
	and	ax,0F000h		; EAX = the next page
	mov	edx,eax
	add	edx,[esp+8]		; EDX = the end of the memory
	test	byte ptr [esp+12],PAG_COMMIT
	jz	short am1
	call	grow
	jc	short ok3
am1:	mov	[brk],edx
	mov	ecx,[esp+4]
	jmp	short ok1

DOS32SETMEM:
	test	byte ptr [esp+12],PAG_COMMIT
	jz	short ok2
	mov	edx,[esp+4]
	add	edx,[esp+8]
	call	grow
	jc	short ok3
	jmp	short ok2

;
; APIRET DOS32READ(HFILE h, PVOID pb, ULONG cb, PULONG pcbActual)
; APIRET DOS32WRITE(HFILE h, PVOID pb, ULONG cb, PULONG pcbActual)
;
	public	DOS32READ,DOS32WRITE
DOS32READ:
	mov	ah,3Fh
	jmp	short rw1
DOS32WRITE:
	mov	ah,40h
rw1:	push	ebx
	mov	ebx,[esp+8]
	mov	edx,[esp+12]
	mov	ecx,[esp+16]
	int	21h			; EAX = # bytes read or written
	pop	ebx
	jc	short ok3
	mov	ecx,[esp+16]
ok1:	mov	[ecx],eax
DOS32FREEMEM:
ok2:	sub	eax,eax
ok3:	ret

;
; APIRET DOS32SETFILEPTR(HFILE h, LONG ib, ULONG method, PULONG pibActual)
;
	public	DOS32SETFILEPTR
DOS32SETFILEPTR:
	push	ebx
	mov	ebx,[esp+8]
	mov	edx,[esp+12]
	shld	ecx,edx,16		; CX:DX = the offset
	mov	al,[esp+16]
	mov	ah,42h
	int	21h			; DX:AX = the new position
	pop	ebx
	jc	short ok3
	shl	edx,16
	mov	dx,ax
	xchg	eax,edx
	mov	ecx,[esp+16]
	jmp	short ok1

;
; APIRET DOS32QUERYHTYPE(HFILE h, PULONG pType, PULONG pAttr)
;
; The type is 1 for a device (which includes a pipe, since PIPE$ is one) and
; 0 for a file, and there are no attributes.
;
	public	DOS32QUERYHTYPE
DOS32QUERYHTYPE:
	push	ebx
	mov	ebx,[esp+8]
	mov	ax,4400h
	int	21h			; DL bit 7 set if it's a device
	pop	ebx
	jc	short ok3
	sub	eax,eax
	mov	ecx,[esp+12]
	mov	[ecx],eax
	shl	dl,1
	adc	eax,eax
	mov	ecx,[esp+8]
	jmp	short ok1

;
; VOID DOS32EXIT(ULONG action, ULONG result)
;
	public	DOS32EXIT
DOS32EXIT:
	mov	al,[esp+8]
	mov	ah,4Ch
	int	21h

;
; int getch(void)
;
; Reads a key without echoing it (a function key is a 0, followed by its
; scan code).
;
	public	_getch
_getch:
	mov	ah,08h
	int	21h
	movzx	eax,al
	ret

;
; grow
;
; Makes the program's memory reach EDX, adding to it if necessary.
;
; Returns carry set and EAX = ERROR_NOT_ENOUGH_MEMORY if it can't, and
; preserves EAX otherwise.
;
grow:	cmp	[lim],edx
	jae	short gr9
	push	eax
	push	ebx
	mov	ebx,edx
	sub	ebx,[lim]		; EBX = # bytes to add
	mov	ah,48h
	int	21h
	pop	ebx
	pop	eax
	jc	short gr8
	mov	[lim],edx
gr9:	ret
gr8:	mov	eax,ERROR_NOT_ENOUGH_MEMORY
	ret

_TEXT	ends

	end	__astart
