;
; BASIC-DOS Case Utility
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dosapi.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	bx,STDIN
	mov	cx,1
	sub	dx,dx
	push	dx
	mov	dx,sp
	mov	ah,DOS_HDL_READ
	int	21h
	pop	dx		; DX = data (if any)
	jc	m9		; read failed
	cmp	ax,cx		; any data returned?
	jb	m9		; no
;
; Change the case of the data
;
	cmp	dl,'a'
	jb	m1
	cmp	dl,'z'
	ja	m1
	sub	dl,20h
m1:	push	dx
	mov	dx,sp
	mov	bx,STDOUT
	mov	ah,DOS_HDL_WRITE
	int	21h
	pop	dx
	jnc	main
m9:	int	20h
ENDPROC	main
;
; COMHEAP 0 means we don't need a heap, but BASIC-DOS will still allocate a
; minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
