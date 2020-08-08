;
; BASIC-DOS System Macros and Helper Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
EXTERNS	macro	list,type
	IRP	l,<list>
	extrn	l:type
	ENDM
	endm

DEFABS	macro	name,value
	public	name
name	equ	value
	endm

DEFLBL	macro	name,type
	public	name
	IFB	<type>
name	equ	$
	ELSE
name	label	type
	ENDIF
	endm

DEFPTR	macro	name,off,seg
	even
	public	name
	IFB	<off>
name	dd	0
	ELSE
	 IFB	<seg>
name	dd	off
	 ELSE
name	dd	(seg SHL 16) OR (off)
	 ENDIF
	ENDIF
	endm

DEFDATA	macro	name,size,type,values,repeat
	IFDIF	<type>,<byte>
	even
	ENDIF
	public	name
	IFB	<values>
name	size	0
	ELSE
	 IFB	<repeat>
name	label	type
	IRP	value,<values>
	size	value
	ENDM
	 ELSE
name	size	repeat dup (values)
	 ENDIF
	ENDIF
	endm

DEFBYTE	macro	name,values,repeat
	DEFDATA name,db,byte,<values>,repeat
	endm

DEFWORD	macro	name,values,repeat
	DEFDATA name,dw,word,<values>,repeat
	endm

DEFLONG macro	name,values,repeat
	DEFDATA name,dd,dword,<values>,repeat
	endm

DEFSTR	macro	name,value
	public	name
	public	name&_LEN
	name	db	value
	name&_LEN equ ($ - name)
	endm

EXTABS	macro	name
	extrn	name&_LEN:abs
	endm

EXTSTR	macro	names
	IRP	name,<names>
	extrn	name:byte
	EXTABS	name
	ENDM
	endm

;
; Tables are like pointers, where .OFF is the offset but .SEG is the limit.
; We don't need to record the segment, because offset is always DS-relative.
;
DEFTBL	macro	names
	even
	IRP	name,<names>
	public	name
name	dd	0
	ENDM
	endm

DEFPROC	macro	name,type
	public	name
	_ARGBYTES = 0
	_LOCBYTES = 0
	_PROCTYPE = 0
	IFIDN	<type>,<DOS>
	 IFDEF	DEBUG
	db	"&name",0
	 ENDIF
	ENDIF
	IFB	<type>
name	proc	near
	ELSE
	 IFIDN <type>,<DOS>
	ASSUME	CS:DOS, DS:DOS, ES:DOS, SS:NOTHING
name	proc	near
	 ELSE
	  IFIDN <type>,<DOSFAR>
	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING
name	proc	far
	_PROCTYPE = 2
	  ELSE
	   IFIDN <type>,<FAR>
	_PROCTYPE = 2
	   ENDIF
name	proc	type	;; we'll leave whatever ASSUMEs are active in place
	  ENDIF
	 ENDIF
	ENDIF
	endm

ARGLONG	macro	name
	DEFARG	name,dword,%(4+_PROCTYPE+_ARGBYTES)
	_ARGBYTES = _ARGBYTES + 4
	endm

DEFARG	macro	name,type,offset
name	equ	type ptr [bp + offset]
	endm

;
; LOCVAR is used inside DEFPROC, like so:
;
;	DEFPROC function,DOS
;	LOCVAR	fileName,byte,11
;	LOCVAR	dirEntry,dword
;	ENTER
;	...
;	LEAVE
;	RET
;	ENDPROC function
;
; which will generate equates/code that look like:
;
;	fileName equ byte ptr [bp-12]
;	dirEntry equ dword ptr [bp-16]
;	push	bp
;	mov	bp,sp
;	sub	sp,16
;
;	...
;	mov	sp,bp
;	pop	bp
;
; If you need the address of a LOCVAR variable, use LEA, as in:
;
;	lea	di,fileName
;
; DEFPROC will define a _LOCBYTES variable representing the number of LOCVAR
; bytes that must be allocated on the stack on ENTER and then released on LEAVE.
;
LOCVAR	macro	name,type,len
	IFB <len>
	_LOCLEN = 1
	ELSE
	_LOCLEN = len
	ENDIF
	IFIDN	<type>,<byte>
	_LOCBYTES = _LOCBYTES + _LOCLEN
	ELSE
	 IFIDN	<type>,<word>
	_LOCBYTES = _LOCBYTES + (_LOCLEN * 2)
	 ELSE
	  IFIDN	<type>,<dword>
	_LOCBYTES = _LOCBYTES + (_LOCLEN * 4)
	  ELSE
	%out	Unrecognized LOCVAR parameter: type
	  ENDIF
	 ENDIF
	ENDIF
	_LOCBYTES = _LOCBYTES + (_LOCBYTES AND 1)
	DEFVAR	name,type,%(_LOCBYTES)
	endm

DEFVAR	macro	name,type,offset
name	equ	type ptr [bp - offset]
	endm

ENTER	macro
	IF _LOCBYTES GT 0 OR _ARGBYTES GT 0
	push	bp
	mov	bp,sp
	 IF _LOCBYTES GT 0
	sub	sp,_LOCBYTES
	 ENDIF
	ENDIF
	endm

LEAVE	macro
	IF _LOCBYTES GT 0 OR _ARGBYTES GT 0
	mov	sp,bp
	pop	bp
	ENDIF
	endm

ENDPROC	macro	name
	_LOCBYTES = 0
name	endp
	endm

ERROR	macro	msg
	IF1
	%out 	msg
	ENDIF
	.ERROR
	endm

ASSERT	macro	cond,op,value
	IFNB	<value>
	 IFIDN	<cond>,<STRUCT>	;; must use "STRUCT" instead of "STRUC" here...
	ASSERT	Z,<cmp op&.&value&_RESERVED,value&SIG>
	 ELSE
	  IFE	cond op value
	ERROR	<Assertion failed: cond op value>
	  ENDIF
	 ENDIF
	ELSE
	 IFDEF DEBUG
	  IFNB	<op>
	pushf
	op
	  ENDIF
	  IFDIF	<cond>,<NEVER>
	J&cond	$+4
	  ENDIF
	int	1		;; use INT 01h to signal an assertion failure
	  IFNB	<op>
	popf
	  ENDIF
	 ENDIF
	ENDIF
	endm

DBGBRK	macro
	IFDEF DEBUG
	int	3		;; use INT 03h to signal a debugger breakpoint
	ENDIF
	endm

DBGINIT	macro	type,ptr,str
	IFDEF DEBUG
	IFIDN	<type>,<STRUCT>
	mov	ptr&.&str&_RESERVED,str&SIG
	ELSE
	%out	Unrecognized INIT parameter: type
	ENDIF
	ENDIF
	endm

ASSUMES	macro	seg1,seg2
	ASSUME1	seg1
	IFNB	<seg2>
	ASSUME1	seg2
	ENDIF
	endm

ASSUME1	macro	segreg,segment
	ASSUME	segreg:segment
	IFDIF	<segment>,<NOTHING>
	push	ax
	push	dx
	push	segreg
	pop	ax
	 IFIDN	<segment>,<BIOS>
	ASSERT	Z,<test ax,ax>
	 ELSE
	  IFIDN	<segment>,<DOS>
	push	cs
	pop	dx
	ASSERT	Z,<cmp ax,dx>
	  ENDIF
	 ENDIF
	pop	dx
	pop	ax
	ENDIF
	endm

PRINTF	macro	format,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	FPRINTF	DOS_UTL_PRINTF,<format>,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	endm

DPRINTF	macro	format,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	IFDEF DEBUG
	push	ax
	FPRINTF	DOS_UTL_DPRINTF,<format>,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	pop	ax
	ENDIF
	endm

FPRINTF	macro	func,format,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	argc = 0
	IRP	arg,<a12,a11,a10,a9,a8,a7,a6,a5,a4,a3,a2,a1>
	IFNB	<arg>
	argc = argc + 1
	push	arg
	ENDIF
	ENDM
	mov	ax,func
	int	INT_DOSFUNC
	db	format,0
	IF	argc NE 0
	add	sp,argc * 2
	ENDIF
	endm
;
; MINHEAP is the minimum number of bytes we allocate for a .COM binary, on
; top of the actual file size.  This is important, because unlike "REAL DOS",
; we don't allocate all available memory to a program when it's loaded and
; then hope the program will shrink its footprint later.
;
; In addition, if a .COM binary uses the COMHEAP macro at the end of its image,
; it can specify its own minimum heap size.  Currently, any value smaller than
; MINHEAP is ignored.
;
; The program's initial stack will always be at the top of "heap", or at the
; top of the program's first 64Kb, whichever is lower.
;
MINHEAP	equ	1024

COMHEAP	macro	bytes
	even
	public	heap
heap	dw	(bytes + 15) SHR 4,BASICDOS_SIG
	endm
