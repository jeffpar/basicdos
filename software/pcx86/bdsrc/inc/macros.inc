;
; BASIC-DOS System Macros and Helper Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	PAGE	,132

REG16	struc
LOB	db	?
HIB	db	?
REG16	ends

REG32	struc
LOW	dw	?
HIW	dw	?
REG32	ends

FARPTR	struc
OFF	dw	?
SEG	dw	?
FARPTR	ends

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

EXTERNS	macro	list,type
	IRP	l,<list>
	extrn	l:type
	ENDM
	endm

EXTABS	macro	names
	EXTERNS	<names>,abs
	endm

EXTNEAR	macro	names
	EXTERNS	<names>,near
	endm

EXTBYTE	macro	names
	EXTERNS	<names>,byte
	endm

EXTWORD	macro	names
	EXTERNS	<names>,word
	endm

EXTLONG	macro	names
	EXTERNS	<names>,dword
	endm

EXTLEN	macro	name
	extrn	name&_LEN:abs
	endm
EXTSTR	macro	names
	IRP	name,<names>
	EXTBYTE	name
	EXTLEN	name
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
	_RETBYTES = 0
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
; RETVAR, ARGVAR, and LOCVAR are used inside DEFPROC, like so:
;
;	DEFPROC	divLong,FAR
;	RETVAR	retDivLong,dword
;	ARGVAR	divA,dword
;	ARGVAR	divB,dword
;	LOCVAR	bitCount,byte
;	LOCVAR	resultType,byte
;	LOCVAR	signDivisor,byte
;	LOCVAR	signDividend,byte
;	ENTER
;	...
;	LEAVE
;	RETURN
;	ENDPROC divLong
;
; List the RETVAR, if any, first, followed by any ARGVARs in the order the
; arguments were pushed.  The actual offset of each ARGVAR will not be known
; until the ENTER macro is called, at which point an adjustment will be
; calculated to "invert" all the offsets, so that the first ARGVAR offset will
; be the "farthest" on the stack (ie, the first argument pushed).
;
; The generated code will look like:
;
;	push	bp
;	mov	bp,sp
;	sub	sp,4
;	...
;	mov	sp,bp	; used instead of "add sp,4" to avoid altering flags
;	pop	bp
;	ret	8
;
; The RETURN macro automatically generates the appropriate RET N instruction,
; where N = _ARGBYTES - _RETBYTES.
;
; If you need the address of any RETVAR, ARGVAR, or LOCVAR variable, use LEA:
;
;	lea	di,resultType
;
; DEFPROC will define a _LOCBYTES variable representing the number of LOCVAR
; bytes that must be allocated on the stack on ENTER and released on LEAVE.
;
; An effort is made to ensure all WORD and DWORD LOCVARs are evenly aligned;
; this is easy to do since the ENTER macro is in complete control of how much
; stack space to allocate.  However, no alignment adjustments can be made for
; ARGVAR definitions, so if you define any BYTE arguments, make sure all bytes
; on the argument side of the stack are accounted for.
;
ARGVAR	macro	name,type,len
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
	DEFARG	name,type,%(_ARGBYTES)
	endm

;
; For functions using a PASCAL-style calling convention that want to return a
; value on the stack, the caller must reserve space for the value on the stack
; *before* pushing any arguments, and the function must use RETVAR to declare
; the return variable *before* declaring any ARGVARs.  The function should also
; use the RETURN macro to pop the ARGVARs; RETVAR will be left on the stack.
;
RETVAR	macro	name,type,len
	ARGVAR	name,type,len
	_RETBYTES = _ARGLEN
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
	ASSERT	Z,<test sp,1>		;; verify stack is evenly aligned
	 ENDIF
	ENDIF
	_ARGINVERT = (2 + _PROCTYPE + _ARGBYTES)
	endm

LEAVE	macro	nocheck
	IF _LOCBYTES GT 0 OR _ARGBYTES GT 0
	 IF _LOCBYTES GT 0
	  IFB <nocheck>			;; some functions will leave data on
	   IFDEF DEBUG			;; the stack, hence the nocheck option
	push	ax
	lea	ax,[bp-_LOCBYTES-4]	;; verify that BP wasn't altered
	ASSERT	Z,<cmp ax,sp>
	pop	ax
	   ENDIF
	  ENDIF
	mov	sp,bp
	 ENDIF
	pop	bp
	ENDIF
	endm

RETURN	macro
	IF _ARGBYTES GT 0
	ret	_ARGBYTES - _RETBYTES
	ELSE
	ret
	ENDIF
	endm

ENDPROC	macro	name
	_LOCBYTES = 0
name	endp
	endm

;
; This macro displays an error message and attempts to force an assembly
; error by using an invalid MASM keyword (".ERROR").
;
ERROR	macro	msg
	IF1
	%out 	msg
	ENDIF
	.ERROR
	endm

;
; In DEBUG builds only, "DBGINIT STRUCT" initializes a signature byte in the
; specified structure; then you can use the "ASSERT STRUCT" form of the ASSERT
; macro to include assertion checks to verify that the specified pointer
; actually points to a structure of the specified type.
;
; The macros use the word "STRUCT" rather than "STRUC" to avoid confusing MASM.
;
DBGINIT	macro	type,ptr,str
	IFDEF DEBUG
	IFIDN	<type>,<STRUCT>
	mov	ptr&.&str&_SIG,SIG_&str
	ELSE
	%out	Unrecognized INIT parameter: type
	ENDIF
	ENDIF
	endm

;
; ASSERT generates assembly-time assertions when all three parameters
; are used; eg:
;
;	ASSERT	<((SIZE CMDHEAP) AND 1)>,EQ,0
;
; Otherwise, it generates code to perform a run-time assertion, which can
; either be a "STRUCT" pointer verification, as in:
;
;	ASSERT	STRUCT,es:[bx],SCB
;
; or an assertion based on processor flags ("cond") set by an optional
; instruction ("op"); for example:
;
;	ASSERT	Z		; assert that Z is set
;	ASSERT	Z,<test dx,dx>	; assert that DX is zero
;
; Run-time assertions are present only in DEBUG builds, and are wrapped with
; PUSHF/POPF if an optional instruction is used.
;
ASSERT	macro	cond,op,value
	IFNB	<value>
	 IFIDN	<cond>,<STRUCT>	;; must use "STRUCT" instead of "STRUC" here
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
	J&cond	$+5
	  ENDIF
	OPCHECK	OP_ASSERT	;; use INT 06h to signal an assertion failure
	  IFNB	<op>
	popf
	  ENDIF
	 ENDIF
	ENDIF
	endm

;
; DBGBRK generates an INT3 (OP_INT03) that's preceded by INT 06h, so if the
; PCjs debugger isn't present, the built-in INT 06h handler will skip over it.
;
DBGBRK	macro
	IFDEF DEBUG
	OPCHECK	OP_DBGBRK	;; use INT 06h to signal a debugger breakpoint
	ENDIF
	endm

;
; ASSUMES is recommended at the beginning of DOS functions, to ensure the
; the function's entry conditions are 1) documented and 2) verified at runtime
; (DEBUG builds only); eg:
;
;	ASSUMES	<DS,DOS>,<ES,NOTHING>
;
ASSUMES	macro	seg1,seg2
	ASSUME1	seg1
	IFNB	<seg2>
	ASSUME1	seg2
	ENDIF
	endm

ASSUME1	macro	segreg,segment
	ASSUME	segreg:segment
	IFDEF DEBUG
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
; Use this macro (ie, REPS MOVS,ES,CS,BYTE instead of rep movsb cs:...) to
; avoid an errata on the 8086.
;
; See: https://www.pcjs.org/documents/manuals/intel/8086/ for details.
;
; MASM 4.0 appears to know that it must generate the REP prefix before the
; segment prefix, and hopefully all other assemblers do as well.
;
; Fortunately, PCjs simulates the errata, so I was able to catch it.
; TODO: It would be even better if PCjs displayed a warning when it happened.
;
REPS	macro	op,s1,s2,size
	local	rm1,rm2
rm1:	rep	op size ptr s1:[di],size ptr s2:[si]
	jcxz	rm2
	jmp	rm1
rm2:
	endm

;
; DOS "utility" functions should always be called with this macro, so that
; we can easily change the implementation.  They were originally implemented
; with an unused INT 21h function # in AH and the utility function # in AL,
; but utility functions like DOS_UTL_PRINTF that expect data bytes to follow
; the INT instruction will not work with code that "hooks" INT 21h.  So we now
; use a dedicated interrupt that expects the utility function # in AH.
;
DOSUTIL	macro	func,option
	IFNB 	<option>
	mov	ax,(DOS_UTL_&func SHL 8) OR (option)
	ELSE
	 IFDIF	<func>,<ah>
	  IFNDEF	DOS_UTL_&func
	mov	ah,func
	  ELSE
	mov	ah,DOS_UTL_&func
	  ENDIF
	 ENDIF
	ENDIF
	int	INT_DOSUTIL
	endm
;
; Use the PRINTF macro to simplify calls to the DOS_UTL_PRINTF function.
;
; There's no SPRINTF macro, but you can use CCALL to call DOS_UTL_SPRINTF;
; pass your format string in DS:BX (don't use the macro's format parameter),
; and set ES:DI and CX to the address and length of your output buffer.
;
;	CCALL	DOS_UTL_SPRINTF,,arg1,arg2,...
;
PRINTF	macro	format,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	CCALL	DOS_UTL_PRINTF,<format>,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	endm

;
; Use the DPRINTF macro to simplify calls to the DOS_UTL_DPRINTF function
; (and to ensure they are generated only in DEBUG builds).
;
DPRINTF	macro	letter,format,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	LOCAL	D1,D2
	IFDEF DEBUG
	pushf			;; CCALL may alter flags
	push	ax		;; DOS_UTL_DPRINTF alters AX
	CCALL	DOS_UTL_DPRINTF,<letter,format>,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	test	al,al		;; if DOS_UTL_DPRINTF returns non-zero in AL
	pop	ax		;; jump to the DBGBRK
	jnz	D1
	popf
	jmp	short D2
D1:	popf
	DBGBRK
D2:
	ENDIF
	endm

;
; CCALL simulates a C-style (aka CDECL) calling convention, with the macro
; pushing the parameters right-to-left and cleaning up the stack afterward.
;
; One downside to this convention is that it can't be used with functions that
; return information in flags, like CF or ZF, due to the "add sp" instruction.
;
; NOTE: When passing 32-bit ("long") values to these macros, pass the low word
; first, then the high word, so that the high word is pushed first.  Similarly,
; when passing 32-bit ("far") pointers, pass the offset first, then segment.
;
CCALL	macro	func,format,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	argc = 0
	IRP	arg,<a12,a11,a10,a9,a8,a7,a6,a5,a4,a3,a2,a1>
	IFNB	<arg>
	argc = argc + 1
	push	arg
	ENDIF
	ENDM
	DOSUTIL	func
	IFNB	<format>
	db	format,0
	ENDIF
	IF	argc NE 0
	add	sp,argc * 2
	ENDIF
	endm

;
; Operation checks are sprinkled throughout DEBUG BASIC-DOS binaries to
; signal assertion failures and internal breakpoints, and also to perform
; arithmetic validation tests in the PCjs emulator.  They invoke INT_UD
; (INT 06h) to trigger the operation, since that interrupt had no defined
; purpose on 8086/8088 processors (every opcode did something).  The concept
; of invalid opcodes came later, with the introduction of the 80186.
;
; With the exception of OP_ASSERT, these operations should have no effect
; in a non-PCjs environment (or on a real machine), since BASIC-DOS system
; initialization installs an INT_UD handler to deal with them.  And if you
; somehow run a DEBUG binary on a non-DEBUG system, INT_UD will still be
; set to an IRET, so the binaries should still run, albeit with side-effects.
;
OP_DBGBRK	equ	0CCh		; signal an internal breakpoint
OP_ASSERT	equ	0F9h		; signal an assertion failure
OP_MUL32	equ	0FBh		; verify 32-bit multiplication result
OP_DIV32	equ	0FCh		; verify 32-bit division result

OPCHECK	macro	op
	IFDEF DEBUG
	int	06h			;; INT INT_UD
	db	op			;; next byte indicates the operation
	ENDIF
	endm
