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
	and	bl,0F0h
	or	bl,0Eh		; BX adjusted to top word of top paragraph
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

	IFDEF MAXDEBUG
	ASSERT	NC		; test the ASSERT macro
	DBGBRK			; test the DBGBRK macro
	ENDIF
;
; Test the CALL 5 interface.
;
	mov	dx,offset call5test
	call	print
;
; Make a series of increasingly large memory allocations.
;
	mov	dx,offset alloctest
	call	print

	mov	cx,10		; perform the series CX times
m1:	sub	bx,bx		; start with a zero paragraph request
m2:	mov	ah,DOS_MEM_ALLOC
	int	21h
	jc	m3
	mov	es,ax		; ES = new segment
	mov	ah,DOS_MEM_FREE
	int	21h
	ASSERT	NC
	inc	bx		; ask for more one paragraph
	jmp	m2
m3:	mov	dx,offset progress
	call	print
	loop	m1

	mov	dx,offset passed
	call	print

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

DEFPROC	print
	push	cx
	mov	cl,DOS_TTY_PRINT
	call	DOS
	pop	cx
	ret
ENDPROC	print

call5test	db		"CALL 5 test "
passed		db		"passed",13,10,'$'
progress	db		".$"
alloctest	db		"memory test$"

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
