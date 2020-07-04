;
; BASIC-DOS Exec Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	ah,52h
	int	21h
	les	di,es:[bx+4]	; ES:DI -> SFTs (in DOS 2.x)
	int 3
	push	ds
	pop	es
	mov	dx,offset readfile
	mov	ax,3D00h
	int	21h		; open a test file
	mov	bx,offset execparms
	mov	[bx].EPB_CMDTAIL.SEG,cs
	mov	[bx].EPB_FCB1.SEG,cs
	mov	[bx].EPB_FCB2.SEG,cs
	mov	ax,4B00h
	mov	dx,offset execfile
	int	21h
	int	20h
ENDPROC	main

readfile	db		"CONFIG.SYS",0
execfile	db		"EXEC.COM",0
execparms	EPB		<0,PSP_CMDTAIL,PSP_FCB1,PSP_FCB2>

;
; COMHEAP 0 means we don't need a heap, but the system will still allocate
; a minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
