;
; BASIC-DOS Command Processor Heap Template
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This must be the last module linked (see CMD.LRF): COMMAND's per-process
; heap begins here, at the end of the image, with the heap template (see
; HEAPDEF in cmd.inc), which ends with the COMDATA that the loader reads from
; the end of the file.  The core (every module through CONST.ASM) ends with
; the same template, so that when memory is too tight for the entire image,
; the loader can load the core alone (see CD_CORESIZE), and the heap begins
; there instead; the modules in between (currently graphics, sound, and the
; tokenized file loader) are then absent, which COMMAND detects by comparing
; their addresses with PSP_CODESIZE (see genCommands).
;
	HEAPDEFS equ 1			; (see HEAPDEF in cmd.inc)
	include	cmd.inc

CODE	SEGMENT

	EXTBYTE	<RES_HEAP>
	EXTWORD	<CORE_END>

	HEAPDEF	BEG_HEAP,<offset DGROUP:CORE_END>

CODE	ENDS

	end
