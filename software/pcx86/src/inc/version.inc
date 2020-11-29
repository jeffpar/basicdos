;
; BASIC-DOS Operating System Version
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

VERSION_MAJOR	equ	0
VERSION_MINOR	equ	23
VERSION_REV	equ	0

VERSION_STR	macro
		db	'0' + VERSION_MAJOR
		db	'.'
		db	'0' + VERSION_MINOR / 10
		db	'0' + VERSION_MINOR MOD 10
		IF VERSION_REV
		db	'A' + VERSION_REV - 1
		ENDIF
		endm
