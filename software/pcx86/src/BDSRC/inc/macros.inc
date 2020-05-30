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

DEFWORD	macro	name,value
	even
	public	name
name	dw	value
	endm

DEFTBL	macro	name,entries
	even
	public	name
name	label	word
	IRP	entry,<entries>
	dw	entry
	ENDM
	endm

DEFPROC	macro	name,type
	db	"&name",0
	public	name
	IFB	<type>
name	proc	near
	ELSE
name	proc	type
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
