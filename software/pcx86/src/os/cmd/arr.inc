;
; BASIC-DOS Array Block Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Included after cmd.inc by the modules that access array blocks (eg, arr.asm
; and gfx.asm).
;
; An array is a VAR_ARRAY variable whose name is the array name followed by
; a type character ('%', '#', or '$'), so that A, A(), and A$() are all
; different variables.  The variable's data is a far pointer to the array's
; block (ABLK), which is zero until the array is dimensioned (by DIM, or
; automatically, with an upper bound of 10, when an element is first used).
;
; Each array has its own ABLK in the ABLKDEF chain, which contains this
; header, followed by the number of elements in each dimension (a word per
; dimension), followed by the elements themselves (4 bytes for VAR_LONG and
; VAR_STR, and 8 bytes for VAR_DOUBLE), all of which are initially zero.
;
; The elements of a string array own their strings (see str.asm), so the
; string pool updates them whenever it moves their strings.
;
ABLK		struc
ABLK_HDR	db size	BLKHDR dup (?)	; 00h
ABLK_TYPE	db	?		; 08h: element type (VAR_*)
ABLK_DIMS	db	?		; 09h: # of dimensions
ABLK_BASE	dw	?		; 0Ah: lower bound (OPTION BASE)
ABLK_SIZE	dw	?		; 0Ch: element size
ABLK_DATA	dw	?		; 0Eh: offset of first element
ABLK		ends
ABLK_SIG	equ	BLK_SIG
