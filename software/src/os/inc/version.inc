;
; BASIC-DOS Operating System Version
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

VERSION_MAJOR	equ	2	; eg, MS-DOS 3.20 return 3 (03h)
VERSION_MINOR	equ	0	; eg, MS-DOS 3.20 returns 20 (14h)

VERSION_STR	macro
		db	'0' + VERSION_MAJOR
		db	'.'
		db	'0' + VERSION_MINOR / 10
		db	'0' + VERSION_MINOR MOD 10
		endm
