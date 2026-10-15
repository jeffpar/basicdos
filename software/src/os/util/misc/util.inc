;
; BASIC-DOS Filter Utility Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The filter utilities (FIND, MORE, and SORT) include this file at the top,
; and utilproc.inc (the shared procedures) after their own code.  Their
; variables live in a UTILVARS structure at the start of the heap, which BP
; always points to (PSP_HEAP).
;
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc

MAXFILES	equ	8	; maximum file names on the command line
LINE_MAX	equ	256	; maximum line length (including CR/LF)
INBUF_LEN	equ	512	; input buffer size
STACK_LEN	equ	256	; stack space above UTILVARS

UTILVARS	struc
UV_HIN		dw	?	; input handle (initially STDIN)
UV_INPOS	dw	?	; offset of next byte in UV_INBUF
UV_INEND	dw	?	; offset of end of data in UV_INBUF
UV_ERR		db	?	; exit code
UV_COLS		db	?	; MORE: # columns in console
UV_ROWS		db	?	; MORE: # rows in console
UV_USED		db	?	; MORE: # rows used on the current page
UV_COL		dw	?	; SORT: column # (from a +n switch)
UV_SEG		dw	?	; SORT: segment of line storage
UV_TEXT		dw	?	; SORT: offset of next line in storage
UV_PTRS		dw	?	; SORT: offset of next line pointer
UV_GAP		dw	?	; SORT: Shell sort gap, in bytes
UV_COUNT	dw	?	; FIND: # lines found; SORT: # lines * 2
UV_LINENO	dw	?	; FIND: current line #
UV_PREFIX	dw	?	; FIND: prefix for line count (": " or "")
UV_STR		dw	?	; offset of quoted string (0 if none)
UV_STRLEN	dw	?	; length of quoted string
UV_NFILES	dw	?	; # file names * 2
UV_FILES	dw	MAXFILES dup (?); offsets of file names
UV_SW		db	26 dup (?); switches 'A' through 'Z' (non-zero if set)
UV_LINE		db	LINE_MAX dup (?)
UV_INBUF	db	INBUF_LEN dup (?)
UTILVARS	ends

;
; CHKSW sets ZF if the specified switch letter (eg, 'V') was NOT specified.
;
CHKSW	macro	letter
	cmp	[bp].UV_SW+(letter-'A'),0
	endm
