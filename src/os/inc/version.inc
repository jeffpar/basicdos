;
; BASIC-DOS Operating System Version
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; VERSION_MAJOR, VERSION_MINOR, and VERSION_REV come from the "version"
; property in the repository's package.json (eg, 2, 10, and 1 of "2.10.1"),
; which mk.sh and mkdos.sh copy here (see tools/release.sh), so change the
; version there instead.  A nonzero VERSION_REV is displayed as a letter
; after the version (eg, 1 is A, so 2.10.1 is 2.10A).
;

VERSION_MAJOR	equ	2	; eg, MS-DOS 3.20 return 3 (03h)
VERSION_MINOR	equ	10	; eg, MS-DOS 3.20 returns 20 (14h)
VERSION_REV	equ	7	; 0 (none) or 1-26 (A-Z)

	IF VERSION_REV
VERSION_LTR	equ	'@' + VERSION_REV
	ELSE
VERSION_LTR	equ	0	; no revision letter
	ENDIF

VERSION_STR	macro
		db	'0' + VERSION_MAJOR
		db	'.'
		db	'0' + VERSION_MINOR / 10
		db	'0' + VERSION_MINOR MOD 10
	IF VERSION_LTR
		db	VERSION_LTR
	ENDIF
		endm
