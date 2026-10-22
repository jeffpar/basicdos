;
; BASIC-DOS System Macros and Helper Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
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

REG64	struc
W1	dw	?
W2	dw	?
W3	dw	?
W4	dw	?
REG64	ends

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
	IFB	<name>
	 IRP	value,<values>
	  IFDEF value
	size	value
	  ELSE
	size	0
	  ENDIF
	 ENDM
	ELSE
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

DEFQUAD macro	name,values,repeat
	DEFDATA name,dq,qword,<values>,repeat
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

EXTQUAD	macro	names
	EXTERNS	<names>,qword
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
	DEFARG	name,type,%_ARGBYTES
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
	DEFVAR	name,type,%_LOCBYTES
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
; specified structure; eg:
;
;	DBGINIT	STRUCT,es:[bx],SCB
;
; then you can use the "ASSERT STRUCT" form of the ASSERT macro to include
; assertion checks to verify that the specified pointer actually points to a
; structure of the specified type.
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
; are used (and the first parameter is not "STRUCT"); eg:
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
; Run-time assertions are present only in DEBUG builds, and any optional
; instruction is wrapped with PUSHF/POPF.  A failed assertion executes an
; INT 3, which DEBUG.COM stops on (see DBGBRK); otherwise, the INT 03h
; handler (dos_brkpt) reports it.
;
; NEVER and FALSE are conditions that always fail; use NEVER for code that
; should never be reached, and FALSE for code that isn't finished yet.
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
	   IFDIF <cond>,<FALSE>
	J&cond	$+3		;; skip the INT 3
	   ENDIF
	  ENDIF
	int	3		;; signal an assertion failure
	  IFNB	<op>
	popf
	  ENDIF
	 ENDIF
	ENDIF
	endm
;
; DBGBRK generates an INT 3 in DEBUG builds.  DEBUG.COM (as a driver, or as
; a program while it's running) stops there; otherwise, the INT 03h handler
; (dos_brkpt) ignores it, since it's preceded by a NOP (unlike an ASSERT's).
; The PCjs debugger also stops on an INT 3 when its INT and HALT messages are
; on ("m int on" and "m halt on").
;
DBGBRK	macro
	IFDEF DEBUG
	nop			;; tells dos_brkpt this isn't an ASSERT
	int	3
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
; Use the EPRINTF macro to display an error message whose error number is
; displayed in parentheses (eg, "Unable to open X.TXT (5)") in DEBUG builds
; only.  The message (msg) and any trailing characters (tail; eg, 13,10) are
; given separately, followed by the error number (err) and any arguments that
; the message requires; eg:
;
;	EPRINTF	<"Unable to open %s">,<13,10>,ax,si
;
; ECCALL does the same for other CCALL functions (eg, DOS_UTL_HPRINTF).
;
EPRINTF	macro	msg,tail,err,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10
	ECCALL	DOS_UTL_PRINTF,<msg>,<tail>,err,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10
	endm

ECCALL	macro	func,msg,tail,err,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10
	IFDEF DEBUG
	 IFNB <tail>
	CCALL	func,<msg," (%d)",tail>,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,err
	 ELSE
	CCALL	func,<msg," (%d)">,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,err
	 ENDIF
	ELSE
	 IFNB <tail>
	CCALL	func,<msg,tail>,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10
	 ELSE
	CCALL	func,<msg>,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10
	 ENDIF
	ENDIF
	endm

;
; Use the DPRINTF macro to simplify calls to the DOS_UTL_DPRINTF function
; (and to ensure they are generated only in DEBUG builds), which prints to the
; DEBUG$ device (ie, the DEBUG.COM driver's port), if it's installed.
;
DPRINTF	macro	format,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	IFDEF DEBUG		;; (see ASSERT)
	pushf			;; CCALL may alter flags
	push	ax		;; DOS_UTL_DPRINTF alters AX
	CCALL	DOS_UTL_DPRINTF,<format>,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12
	pop	ax
	popf
	ENDIF
	endm

;
; Pushes the given argument onto the stack, using the given size in words;
; default is 1.
;
; NOTE: There is deliberately no 4-word (64-bit) option: doubles must always
; be passed by reference (ie, as far pointers), never by value.
;
PUSHARG	macro	a,w
	IF w EQ 2
	push	a.HIW
	push	a.LOW
	ELSE
	push	a
	ENDIF
	endm

;
; CCALL simulates a C-style (aka CDECL) calling convention, with the macro
; pushing the parameters right-to-left and cleaning up the stack afterward.
;
; One downside to this convention is that it can't be used with functions
; returning values in flags, like CF or ZF, due to the "add sp" instruction.
;
; NOTE: When passing a 32-bit "long" value or "far" pointer stored in memory to
; CCALL, follow it with the dummy parameter ":2".  This tells CCALL that the
; argument requires 2 pushes; the default is 1.  I originally tried to have
; PUSHARG determine the argument size itself, using MASM 4.0 operators like
; "TYPE", but it was unreliable (perhaps even, dare I say, buggy).
;
; You can pass individual words of a 32-bit value separately, but be sure to
; list the lowest word first, so that it gets pushed last.  64-bit doubles are
; never passed by value; pass a far pointer instead (eg, offset and segment).
;
CCALL	macro	func,format,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15
	argc = 0
	argw = 1
	IRP	arg,<a15,a14,a13,a12,a11,a10,a9,a8,a7,a6,a5,a4,a3,a2,a1>
	 IFNB <arg>
	  IFIDN <arg>,<:2>
	argw = 2
	  ELSE
	PUSHARG	arg,argw
	argc = argc + argw
	argw = 1
	  ENDIF
	 ENDIF
	ENDM
	DOSUTIL	func
	IFNB <format>
	db	format,0
	ENDIF
	IF argc NE 0
	add	sp,argc * 2
	ENDIF
	endm
