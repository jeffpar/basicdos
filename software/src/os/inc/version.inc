;
; BASIC-DOS Operating System Version
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; VERSION_MAJOR and VERSION_MINOR come from the "version" property in the
; repository's package.json (eg, 2.0 of "2.0.0"), which mk.sh and mkdos.sh
; copy here (see tools/release.sh), so change the version there instead.
;

VERSION_MAJOR	equ	2	; eg, MS-DOS 3.20 return 3 (03h)
VERSION_MINOR	equ	1	; eg, MS-DOS 3.20 returns 20 (14h)

VERSION_STR	macro
		db	'0' + VERSION_MAJOR
		db	'.'
		db	'0' + VERSION_MINOR / 10
		db	'0' + VERSION_MINOR MOD 10
		endm
