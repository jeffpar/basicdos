;
; BASIC-DOS Filter Utility Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The filter utilities (FIND, MORE, SED, SORT, TEE, UNIQ, and WC) include this
; file at the top, and utilproc.inc (the shared procedures) after their own
; code.  Their variables live in a UTILVARS structure at the start of the heap,
; which BP always points to (PSP_HEAP); a utility with more variables puts
; them in a structure that starts with UTILVARS (eg, UNIQVARS).  Utilities that
; accept wildcards in file names (FIND and WC) define UTILWALK first, which
; adds eachFile (see utilproc.inc) and the shared walkFiles and scanSpec (see
; util.inc), and utilities that match regular expressions (FIND and SED)
; define UTILRE, which adds reCompile and reSearch (see utilproc.inc), and
; lets their string be unquoted (see getArgs).
;
	DOSFUNC equ 1
	DOSPSP equ 1
	IFDEF	UTILWALK
	DOSFFB equ 1
	ENDIF
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc

MAXFILES	equ	8	; maximum file names on the command line
LINE_MAX	equ	256	; maximum line length (including CR/LF)
INBUF_LEN	equ	512	; input buffer size
STACK_LEN	=	256	; stack space above the variables
	IFDEF	UTILWALK
STACK_LEN	=	STACK_LEN + 256	; more for walkFiles
	ENDIF
	IFDEF	UTILRE
STACK_LEN	=	STACK_LEN + 512	; more for advance (8 bytes per '*')
RE_MAX		equ	512	; room for the REs of a full command tail
;
; reCompile turns an RE into a series of nodes, each an opcode (RE_*) followed
; by its operands, if any.  Every character, '.', and [class] becomes a class,
; with a count and that many (first,last) pairs of characters (eg, 'a' is one
; pair, (a,a), and '.' is a negated class with no pairs).
;
RE_END		equ	0	; end of the RE (it matched)
RE_BOL		equ	1	; beginning of the line
RE_EOL		equ	2	; end of the line
RE_GRP		equ	3	; group mark (followed by offset in UV_GRPS)
RE_NCCL		equ	4	; negated class (followed by # pairs, pairs)
RE_CCL		equ	5	; class (followed by # pairs, and the pairs)
RE_STAR		equ	8	; repeat flag (OR'ed with RE_CCL or RE_NCCL)
	ENDIF

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
UV_COUNT	dw	?	; FIND: # lines; SORT: # lines * 2; WC: # files
UV_LINENO	dw	?	; FIND and SED: current line #
UV_PREFIX	dw	?	; FIND: prefix for line count (": " or "")
UV_CNTS		dd	6 dup (?); WC: line, word, and byte counts, and totals
UV_STR		dw	?	; offset of the string (0 if none)
UV_STRLEN	dw	?	; length of the string
UV_NFILES	dw	?	; # file names * 2
UV_FILES	dw	MAXFILES dup (?); offsets of file names
UV_SW		db	26 dup (?); switches 'A' through 'Z' (non-zero if set)
UV_LINE		db	LINE_MAX dup (?)
UV_INBUF	db	INBUF_LEN dup (?)
UV_LBEG		dw	?	; FIND and SED: offset of the line to match
UV_LEND		dw	?	; FIND and SED: offset of its end (CR or LF)
UV_GRPS		dw	20 dup (?); FIND and SED: start and end of the match
				; (and of each group, 1-9; see RE_GRP)
UV_PCH		db	?	; FIND and WC: path char (see eachFile)
UTILVARS	ends

;
; CHKSW sets ZF if the specified switch letter (eg, 'V') was NOT specified.
;
CHKSW	macro	letter
	cmp	[bp].UV_SW+(letter-'A'),0
	endm
