;
; BASIC-DOS System Macros and Helper Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	PAGE	,132

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
	_ARGLEN = 0
	_ARGBYTES = 0
	_LOCBYTES = 0
	_PROCTYPE = 2
	IFIDN	<type>,<DOS>
	 IFDEF	MAXDEBUG
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
	_PROCTYPE = 4
	  ELSE
	   IFIDN <type>,<FAR>
	_PROCTYPE = 4
	   ENDIF
name	proc	type	;; we'll leave whatever ASSUMEs are active in place
	  ENDIF
	 ENDIF
	ENDIF
	endm

;
; ARGVAR and LOCVAR are used inside DEFPROC, like so:
;
;	DEFPROC	evalDivLong,FAR
;	ARGVAR	divA,dword
;	ARGVAR	divB,dword
;	LOCVAR	bitCount,byte
;	LOCVAR	resultType,byte
;	LOCVAR	signDivisor,byte
;	LOCVAR	signDividend,byte
;	ENTER
;	...
;	LEAVE
;	RET	4
;	ENDPROC evalDivLong
;
; List any ARGVARs in the order the arguments were pushed.  The actual offset
; of each ARGVAR will not be known until the ENTER macro is called, at which
; point an _ARGINVERT value will be calculated to "invert" all the offsets,
; so that the first ARGVAR offset will be the "farthest" on the stack (ie, the
; first argument pushed).
;
; The generated code will look like:
;
;	push	bp
;	mov	bp,sp
;	sub	sp,4
;	...
;	add	sp,4	; used instead of "mov sp,bp" in case BP is reused
;	pop	bp
;	ret	4
;
; There's also a RETURN macro that will automatically generate the RET N
; instruction with N = _ARGBYTES, but if a function must leave a result on
; the stack (like the evalDivLong example above), you must write the RET N.
;
; If you need the address of an ARGVAR or LOCVAR variable, use LEA:
;
;	lea	di,resultType
;
; DEFPROC will define a _LOCBYTES variable representing the number of LOCVAR
; bytes that must be allocated on the stack on ENTER and released on LEAVE.
;
; An effort is made to ensure all WORD and DWORD LOCVARs are evenly aligned;
; this is easy to do since the ENTER macro is in complete control of how much
; stack space to allocate.  However, no alignment adjustments are made for
; ARGVAR definitions, so if you define any BYTE arguments, make sure ALL bytes
; on the argument side of the stack are accounted for.
;
ARGVAR	macro	name,type,len
	DEFARG	name,type,%(2 + _PROCTYPE + _ARGBYTES)
	IFB <len>
	_ARGLEN = 1
	ELSE
	_ARGLEN = len
	ENDIF
	IFIDN	<type>,<byte>
	ELSE
	 IFIDN	<type>,<word>
	_ARGLEN = _ARGLEN * 2
	 ELSE
	  IFIDN	<type>,<dword>
	_ARGLEN = _ARGLEN * 4
	  ELSE
	%out	Unrecognized ARGVAR parameter: type
	  ENDIF
	 ENDIF
	ENDIF
	_ARGBYTES = _ARGBYTES + _ARGLEN
	endm

DEFARG	macro	name,type,offset
name	equ	type ptr [bp + (_ARGINVERT - offset)]
	endm

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
	_LOCBYTES = _LOCBYTES + (_LOCLEN * 2) + (_LOCBYTES AND 1)
	 ELSE
	  IFIDN	<type>,<dword>
	_LOCBYTES = _LOCBYTES + (_LOCLEN * 4) + (_LOCBYTES AND 1)
	  ELSE
	%out	Unrecognized LOCVAR parameter: type
	  ENDIF
	 ENDIF
	ENDIF
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
	_ARGINVERT = ((2 + _PROCTYPE) * 2) + (_ARGBYTES - _ARGLEN)
	endm

LEAVE	macro
	IF _LOCBYTES GT 0 OR _ARGBYTES GT 0
	 IF _LOCBYTES GT 0
	add	sp,_LOCBYTES
	 ENDIF
	pop	bp
	ENDIF
	endm

RETURN	macro
	IF _ARGBYTES GT 0
	ret	_ARGBYTES
	ELSE
	ret
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
	ASSERT	Z,<cmp op&.&value&_SIG,SIG_&value>
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
	mov	ptr&.&str&_SIG,SIG_&str
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
	IFDEF	DEBUG
	 IFDIF <segment>,<NOTHING>
	push	ax
	push	dx
	push	segreg
	pop	ax
	  IFIDN <segment>,<BIOS>
	ASSERT	Z,<test ax,ax>
	  ELSE
	   IFIDN <segment>,<DOS>
	push	cs
	pop	dx
	ASSERT	Z,<cmp ax,dx>
	   ENDIF
	  ENDIF
	pop	dx
	pop	ax
	 ENDIF
	ENDIF
	endm

;
; Use this macro (ie, REPMOV byte,CS instead of rep movsb cs:...) to avoid
; an errata on the 8086.
;
; See: https://www.pcjs.org/documents/manuals/intel/8086/ for details.
;
; MASM 4.0 appears to know that it must generate the REP prefix before the
; segment prefix, and hopefully all other assemblers do as well.
;
; Fortunately, PCjs simulates the errata, so I was able to catch it.
; TODO: It would be even better if PCjs displayed a warning when it happened.
;
REPMOV	macro	msize,mseg
	local	rmb1,rmb2
rmb1:	rep	movs msize ptr es:[di],msize ptr mseg:[si]
	jcxz	rmb2
	jmp	rmb1
rmb2:
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
