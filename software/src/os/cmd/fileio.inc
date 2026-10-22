;
; BASIC-DOS File I/O Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Included after cmd.inc by fileio.asm and input.asm.
;
; Each OPEN file (#1 to #FILE_MAX) has a FILE_SLOT-byte slot in FILE_DATA,
; with its handle (0 if the file isn't open), its mode (FM_*; see fileio.asm),
; and for random access, its record length, the last record # used, and a far
; pointer to its FIELD table (see setField); a file opened by a program is
; closed when the command that ran the program ends, along with its handle
; (see syncFiles).
;
FILE_MAX	equ	4		; max OPEN files (#1-#4)
FILE_SLOT	equ	10		; size of each file's slot
FS_RLEN		equ	FILE_DATA+2	; record length (byte)
FS_REC		equ	FILE_DATA+4	; last record # (word)
FS_FIELDS	equ	FILE_DATA+6	; FIELD table (dword; see setField)
FILE_CUR	equ	FILE_DATA+40	; handle for INPUT (see selectInput)
FILE_POS	equ	FILE_DATA+42	; position in the INPUT line (byte)
KBD_HDL		equ	0FFh		; FILE_CUR "handle" for INPUT
