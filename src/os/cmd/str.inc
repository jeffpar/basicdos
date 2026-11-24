;
; BASIC-DOS String Pool Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Included after cmd.inc by str.asm and upmisc.asm.
;
; Every string pool entry begins with one of these types (see str.asm).
;
STR_PAD		equ	0
STR_FREE	equ	1
STR_TEMP	equ	2
STR_HELD	equ	3
STR_OWNED	equ	4
STR_HDR		equ	5		; # header bytes preceding length byte
