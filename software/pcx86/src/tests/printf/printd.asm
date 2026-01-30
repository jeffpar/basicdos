;
; BASIC-DOS Print Test Data
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	public	CR,LF,PI,ONE
CR	dw	13
LF	dw	10
PI	dq	3.14159
ONE	dq	1.0

DOS	ends

	end
