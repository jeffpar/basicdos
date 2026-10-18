;
; BASIC-DOS Visual Editor Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Included by every VI module (see vi.asm).
;
BIOSKEY equ	1
	include	macros.inc
	include	bios.inc
	include	devapi.inc
	include	dosapi.inc

MAXCOLS		equ	80	; maximum screen columns
MAXROWS		equ	25	; maximum screen rows
MAXNAME		equ	64	; maximum file name length (including null)
MAXTEXT		equ	0FF00h	; maximum file size
GROW		equ	1024	; extra bytes allocated when the text grows
OBUF_LEN	equ	256	; output buffer size (for writing files)
STACK_LEN	equ	512	; stack space above VIVARS

MODE_INS	equ	01h	; V_MODE: insert mode
F_MOD		equ	01h	; V_FLAGS: text modified
F_KEEPW		equ	02h	; V_FLAGS: keep V_WANT (after vertical motions)
F_BIG		equ	04h	; V_FLAGS: big word motion (W, B, or E)
M_LINE		equ	01h	; motion flags: linewise
M_INCL		equ	02h	; motion flags: inclusive
M_VERT		equ	04h	; motion flags: vertical (keep V_WANT)

VIVARS		struc
V_TSEG		dw	?	; text segment
V_GS		dw	?	; gap start (logical offset)
V_GL		dw	?	; gap length
V_LEN		dw	?	; text length
V_CUR		dw	?	; cursor offset
V_TOP		dw	?	; offset of the top line
V_DTOP		dw	?	; offset of the top line displayed
V_LEFT		dw	?	; first column displayed
V_WANT		dw	?	; desired column for vertical motions
V_COUNT		dw	?	; command count (0 if none)
V_ISTART	dw	?	; offset where insert mode began
V_UOFF		dw	?	; undo: offset of the last change (-1 if none)
V_ULEN		dw	?	; undo: length of the text it deleted
V_UINS		dw	?	; undo: length of the text it inserted
V_USEG		dw	?	; undo: segment of the deleted text (0 if none)
V_YSEG		dw	?	; yank: segment of the yanked text (0 if none)
V_YLEN		dw	?	; yank: length of the yanked text
V_PEND		dw	?	; pending key (0 if none)
V_PATLEN	dw	?	; length of the search pattern
V_RLIM		dw	?	; end of V_ROWBUF for text rows
V_HDL		dw	?	; file handle (for writing)
V_CROW		db	?	; cursor's screen row
V_COLS		db	?	; screen columns
V_ROWS		db	?	; screen rows
V_TROWS		db	?	; text rows (V_ROWS - 1)
V_MODE		db	?	; MODE_*
V_FLAGS		db	?	; F_*
V_YLINE		db	?	; non-zero if the yanked text is linewise
V_OP		db	?	; operator (d, c, or y)
V_MKEY		db	?	; operator's motion key
V_FCMD		db	?	; last f, F, t, or T command
V_FCHR		db	?	; last f, F, t, or T character
V_SDIR		db	?	; last search direction (1 if backward)
V_SUBG		db	?	; substitute: zero to replace every match
V_SUBN		db	?	; substitute: non-zero if anything replaced
V_MSGLEN	db	?	; length of V_MSG
V_RLEN		db	MAXROWS dup (?)	; length of each row on the screen
V_RDIRTY	db	MAXROWS dup (?)	; non-zero if a row must be redrawn
V_FNAME		db	MAXNAME dup (?)
V_PAT		db	MAXCOLS dup (?)
V_MSG		db	MAXCOLS+MAXNAME dup (?)
V_LINE		db	MAXCOLS dup (?)
V_ROWBUF	db	MAXCOLS dup (?)
V_OBUF		db	OBUF_LEN dup (?)
VIVARS		ends

