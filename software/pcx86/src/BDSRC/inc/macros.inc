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
	ASSUME	CS:DOS, DS:DOS, ES:BIOS, SS:NOTHING
name	proc	near
	  ELSE
name	proc	type
	  ENDIF
	ENDIF
	endm

ENDPROC	macro	name
name	endp
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
