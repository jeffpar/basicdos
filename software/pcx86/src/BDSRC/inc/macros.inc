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
	even
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
	IFDEF	DEBUG
	IFIDN	<type>,<DOS>
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
	ELSE
name	proc	type	;; we'll leave whatever ASSUMEs are active in place
	ENDIF
	ENDIF
	ENDIF
	LOCBYTES = 0
	endm

;
; For functions called from dos_func, where BP -> REG_FRAME and BP-2 -> return
; address, a set of macro invocations like this:
;
;	DEFPROC function,DOS
;	LOCVAR	fileName,byte,11
;	LOCVAR	dirEntry,dword,1
;	ENTER
;	...
;	LEAVE
;	ENDPROC function
;
; will generate equates/code that look like this:
;
;	fileName equ (byte ptr [bp-13])
;	dirEntry equ (dword ptr [bp-17])
;	sub	sp,16
;	...
;	add	sp,16
;
; If you need the address of a LOCVAR variable, use LEA, as in:
;
;	lea	di,fileName
;
; DEFPROC will define a LOCBYTES variable representing the number of LOCVAR
; bytes that must be allocated on the stack on ENTER and then released on LEAVE.
;
LOCVAR	macro	name,type,len
	IFIDN	<type>,<byte>
	LOCBYTES = LOCBYTES + len
	ELSE
	IFIDN	<type>,<word>
	LOCBYTES = LOCBYTES + (len * 2)
	ELSE
	IFIDN	<type>,<dword>
	LOCBYTES = LOCBYTES + (len * 4)
	ELSE
	%out	Unrecognized LOCVAR parameter: type
	ENDIF
	ENDIF
	ENDIF
name	equ	type ptr [bp - LOCBYTES - 2]
	endm

ENTER	macro
	IF LOCBYTES GT 0
	sub	sp,LOCBYTES + (LOCBYTES AND 1)
	ENDIF
	endm

LEAVE	macro
	IF LOCBYTES GT 0
	add	sp,LOCBYTES + (LOCBYTES AND 1)
	ENDIF
	endm

ENDPROC	macro	name
name	endp
	LOCBYTES = 0
	endm

ERROR	macro	msg
	IF1
	%out 	msg
	ENDIF
	.ERROR
	endm

ASSERT	macro	v1,op,v2
	IFE	v1 op v2
	ERROR	<Assertion failed: v1 op v2>
	IF1
	%out
	ENDIF
	ENDIF
	endm

ASSERTZ	macro	op
	IFDEF DEBUG
	IFNB	<op>
	op
	ENDIF
	jz	$+4
	int 1
	ENDIF
	endm

ASSERTNC macro	op
	IFDEF DEBUG
	IFNB	<op>
	op
	ENDIF
	jnc	$+4
	int 1
	ENDIF
	endm

ASSERTNZ macro	op
	IFDEF DEBUG
	IFNB	<op>
	op
	ENDIF
	jnz	$+4
	int 1
	ENDIF
	endm

INIT_STRUC macro ptr,str
	IFDEF DEBUG
	mov	ptr&.&str&_RESERVED,str&SIG
	ENDIF
	endm

ASSERT_STRUC macro ptr,str
	ASSERTZ <cmp ptr&.&str&_RESERVED,str&SIG>
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
	ASSERTZ <test ax,ax>
	ELSE
	IFIDN	<segment>,<DOS>
	push	cs
	pop	dx
	ASSERTZ <cmp ax,dx>
	ENDIF
	ENDIF
	pop	dx
	pop	ax
	ENDIF
	endm

PRINTF	macro	format,a1,a2,a3,a4,a5,a6,a7,a8,a9
	argc = 0
	IFNB	<a9>
	argc = argc + 1
	push	a9
	ENDIF
	IFNB	<a8>
	argc = argc + 1
	push	a8
	ENDIF
	IFNB	<a7>
	argc = argc + 1
	push	a7
	ENDIF
	IFNB	<a6>
	argc = argc + 1
	push	a6
	ENDIF
	IFNB	<a5>
	argc = argc + 1
	push	a5
	ENDIF
	IFNB	<a4>
	argc = argc + 1
	push	a4
	ENDIF
	IFNB	<a3>
	argc = argc + 1
	push	a3
	ENDIF
	IFNB	<a2>
	argc = argc + 1
	push	a2
	ENDIF
	IFNB	<a1>
	argc = argc + 1
	push	a1
	ENDIF
	mov	ax,DOS_UTIL_PRINTF
	int	INT_DOSFUNC
	db	format,0
	IF	argc NE 0
	add	sp,argc * 2
	ENDIF
	endm
