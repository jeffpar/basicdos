;
; BASIC-DOS Startup Code for Microsoft C 4.00 Programs
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This replaces the startup module (crt0) in Microsoft's C libraries, for
; programs that LINK4 builds as NE programs, which BASIC-DOS loads in either
; mode.  Microsoft's startup sizes DGROUP with segment arithmetic, shrinks the
; program's memory block to fit, and disables interrupts, none of which a
; protected-mode program can do.
;
; Assemble it with /MX, and /DMEM_S, /DMEM_M, /DMEM_C, or /DMEM_L for the
; small, medium, compact, or large memory model.  Like Microsoft's, the object
; file then needs a DOSSEG record, which MASM 4.00 can't produce (it tells the
; linker to use Microsoft's segment order, and to define _edata and _end), so
; add one with the C compiler's DOSSEG.EXE, and replace the library's module:
;
;	MASM /MX /DMEM_S BDCRT0.ASM,CRT0.OBJ;
;	DOSSEG CRT0.OBJ
;	LIB SLIBC -+CRT0;
;
; The libraries in TOOLS\LIB were made that way (see TOOLS\README.TXT).
;
; The program's module definition (DEF) file needs PROTMODE, CODE FIXED, DATA
; FIXED, and STACKSIZE and HEAPSIZE statements.  There is no stack segment:
; the loader adds the STACKSIZE and HEAPSIZE to DGROUP, and starts the program
; with SP at the top of it.  The stack is the top STACKLEN bytes, and the
; heap is everything from the end of the program's data to the stack, so
; STACKSIZE and HEAPSIZE matter only as a sum (STACKSIZE must be at least
; STACKLEN).  The registers on entry are those of any BASIC-DOS NE program:
; DS = ES = PSP, and SS:SP = the top of DGROUP.
;
IFDEF	MEM_M
sizeC	equ	1
sizeD	equ	0
ENDIF
IFDEF	MEM_C
sizeC	equ	0
sizeD	equ	1
ENDIF
IFDEF	MEM_L
sizeC	equ	1
sizeD	equ	1
ENDIF
IFNDEF	sizeC
sizeC	equ	0
sizeD	equ	0
ENDIF

STACKLEN	equ	2048		; stack size (the libraries' default)
STACKSLOP	equ	256		; what __chkstk leaves for interrupts

_TEXT	segment	byte public 'CODE'
_TEXT	ends
_DATA	segment	word public 'DATA'
_DATA	ends
;
; The linker defines _end (the end of DGROUP's data) only if there's a segment
; in the STACK class, so here's an empty one.  It isn't a stack segment, so
; the program's initial SP is still 0 (the top of DGROUP).
;
EEND	segment	word public 'STACK'
EEND	ends

DGROUP	group	_DATA,EEND

	public	__acrtused
__acrtused	equ	9876h		; (referenced by every C module)
	extrn	__acrtmsg:abs		; (includes the startup messages)

MAXSEG	equ	20			; # of brkctl segments (see _abrktb)

_DATA	segment
	extrn	__psp:word,___argc:word,_environ:word,___argv:word
	extrn	STKHQQ:word
	extrn	_edata:byte		; start of the uninitialized data
	extrn	_end:byte		; and the end of it
	public	__asizds,__atopsp,__abrktb,__abrktbe,__abrkp
__asizds	dw	0		; offset of the heap's last byte
__atopsp	dw	0		; offset of the heap's first byte
;
; brkctl's table of segments (a size and a segment for each): the first is
; DGROUP, whose size is the end of the heap that's in use.
;
__abrktb	dw	?,DGROUP
		db	(MAXSEG-1)*4 dup (?)
__abrktbe	label	word
__abrkp		dw	offset DGROUP:__abrktb
_DATA	ends

IF	sizeC
	extrn	__cinit:far,__setargv:far,__setenvp:far,_main:far
	extrn	_exit:far,__exit:far,__NMSG_WRITE:far
ELSE
	extrn	__cinit:near,__setargv:near,__setenvp:near,_main:near
	extrn	_exit:near,__exit:near,__NMSG_WRITE:near
ENDIF

_TEXT	segment
	assume	cs:_TEXT,ds:DGROUP,ss:DGROUP

	public	__astart
__astart:
	mov	bx,ds			; BX = PSP
	mov	ax,DGROUP
	mov	ds,ax
	mov	[__psp],bx
;
; SP is the size of DGROUP (0 if it's 64K).  The stack is at the top, and
; the heap is between the program's data and the stack.
;
	mov	ax,sp
	dec	ax			; AX = offset of DGROUP's last byte
	sub	ax,STACKLEN
	mov	[__asizds],ax
	add	ax,STACKSLOP+1		; the lowest SP that __chkstk allows
	mov	[STKHQQ],ax
	mov	ax,offset DGROUP:_end
	mov	[__atopsp],ax
	mov	[__abrktb],ax
;
; Zero the uninitialized data, as Microsoft's startup does, and set up the
; conventions of C code: DS = ES = SS, with the direction flag clear.
;
	push	ds
	pop	es
	cld
	mov	di,offset DGROUP:_edata
	mov	cx,offset DGROUP:_end
	sub	cx,di
	xor	ax,ax
	rep	stosb

	call	__cinit			; initialize the run-time library
	push	ss
	pop	ds
	call	__setargv		; build argv from the command line
	call	__setenvp		; and environ from the environment

	xor	bp,bp			; (marks the top stack frame)
IF	sizeD
	push	ds
ENDIF
	push	[_environ]
IF	sizeD
	push	ds
ENDIF
	push	[___argv]
	push	[___argc]
	call	_main			; main(argc, argv, envp)
	push	ax
	call	_exit			; exit(AX), which doesn't return

;
; The library's divide error handler, and its exit for fatal errors: AX is
; the number of the message to display before the program ends, with an exit
; code of 255.
;
	public	__cintDIV,__amsg_exit
__cintDIV:
	mov	ax,3			; "Integer divide by 0"
__amsg_exit:
	push	ax
	call	__NMSG_WRITE
	mov	ax,255
	push	ax
	call	__exit

_TEXT	ends

	end	__astart
