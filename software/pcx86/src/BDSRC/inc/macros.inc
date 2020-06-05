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
; Tables are like pointers, where .off is the offset but .seg is the limit.
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
;	LOCVAR	lFileName,byte,11
;	LOCVAR	lDirEntry,dword,1
;	ENTER
;	...
;	LEAVE
;	ENDPROC function
;
; will generate equates/code that look like this:
;
;	lFileName equ (byte ptr [bp-13])
;	lDirEntry equ (dword ptr [bp-17])
;	sub	sp,16
;	...
;	add	sp,16
;
; If you need the address of a LOCVAR variable, use LEA, as in:
;
;	lea	di,lFileName
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
