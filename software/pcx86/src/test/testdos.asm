;
; BASIC-DOS Miscellaneous DOS Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	5
	DEFLBL	DOS,near

	org	100h

DEFPROC	main
;
; The following REALLOC is not necessary in BASIC-DOS, because it detects
; our COMHEAP signature and resizes us automatically, but if we want to run
; with the same footprint in PC DOS, then we must still resize ourselves.
;
	mov	bx,offset HEAP + MINHEAP
	or	bl,0Eh		; adjust BX to top word of the paragraph
	mov	word ptr [bx],0	; store a zero there so we can simply return
	mov	sp,bx		; lower the stack
	mov	cl,4
	add	bx,15
	shr	bx,cl
	mov	ah,DOS_MEM_REALLOC
	int	21h
;
; The "list-of-lists" function isn't supported in BASIC-DOS, since we have
; no interest in tying ourselves to internal PC DOS data structures that don't
; exist in the BASIC-DOS timeline, but this call is helpful for examining them
; when we're running under PC DOS.
;
; For example, in PC DOS 2.x, the word at ES:BX-2 contains the first MCB
; segment, and the dword at ES:BX+4 points to the SFT.
;
	mov	ah,52h		; undocumented PC DOS "list-of-lists" function
	int	21h
;
; Test the CALL 5 interface.
;
	mov	dx,offset hello
	mov	cl,DOS_TTY_PRINT
	call	DOS

	IFDEF MAXDEBUG
	push	ds
	pop	es
	mov	dx,offset readfile
	mov	ax,DOS_HDL_OPEN SHL 8
	int	21h		; open a test file
	mov	bx,offset execparms
	mov	[bx].EPB_CMDTAIL.SEG,cs
	mov	[bx].EPB_FCB1.SEG,cs
	mov	[bx].EPB_FCB2.SEG,cs
	mov	ax,DOS_PSP_EXEC
	mov	dx,offset execfile
	int	21h		; exec a test file (ie, ourselves)
	ENDIF

	ret
ENDPROC	main

hello		db		"Hello from CALL 5",13,10,'$'

	IFDEF MAXDEBUG
readfile	db		"config.sys",0
execfile	db		"testdos.com",0
execparms	EPB		<0,PSP_CMDTAIL,PSP_FCB1,PSP_FCB2>
	ENDIF
;
; COMHEAP 0 means we don't need a heap, but BASIC-DOS will still allocate a
; minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
