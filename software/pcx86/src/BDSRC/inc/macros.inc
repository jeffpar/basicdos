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

DEFDATA	macro	names,size,value
	even
	IRP	name,<names>
	public	name
	IFB	<value>
name	size	?
	ELSE
name	size	value
	ENDIF
	ENDM
	endm

DEFBYTE	macro	names,value
	DEFDATA <names>,db,value
	endm

DEFWORD	macro	names,value
	DEFDATA <names>,dw,value
	endm

DEFPTR	macro	names,value
	DEFDATA <names>,dd,value
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

DEFARR	macro	name,entries
	even
	public	name
name	label	word
	IRP	entry,<entries>
	dw	entry
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
