;
; BASIC-DOS Loadable Serial Debugger Confidence Test
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Run B:\TESTS\DBGTEST on BASICDOS-360K-DEBUG, with BASICDOS-360K-TESTS in
; drive B:.  Resume both traps with G on the debugger terminal.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	dosapi.inc

CHECK	macro	left,right
	local	ok
	cmp	left,right
	je	ok
	jmp	failed
ok:
	endm

CODE	segment
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:CODE
	org	100h

DEFPROC	main
	mov	[original_sp],sp
	mov	dx,offset PORT_NAME
	call	check_port
	mov	dx,offset PORT_PARMS
	call	check_port
;
; These values and flags must be displayed by R and survive G unchanged.
;
	mov	ax,0B800h
	mov	es,ax
	mov	ax,0ED7h
	push	ax
	popf
	mov	ax,1234h
	mov	bx,2345h
	mov	cx,3456h
	mov	dx,4567h
	mov	si,5678h
	mov	di,6789h
	mov	bp,789Ah
	int	3
	pushf
	pop	[saved_flags]
	CHECK	ax,1234h
	CHECK	bx,2345h
	CHECK	cx,3456h
	CHECK	dx,4567h
	CHECK	si,5678h
	CHECK	di,6789h
	CHECK	bp,789Ah
	CHECK	sp,[original_sp]
	mov	ax,es
	CHECK	ax,0B800h
	mov	ax,ds
	mov	bx,cs
	CHECK	ax,bx
	mov	ax,ss
	CHECK	ax,bx
	mov	ax,[saved_flags]
	and	ax,0ED5h
	CHECK	ax,0ED5h
	cld
;
; INT 1 has the same preservation/inspection interface as INT 3.
;
	int	1
	PRINTF	<"DBGTEST passed",13,10>
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
failed:	cld
	PRINTF	<"DBGTEST failed",13,10>
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	main

;
; check_port
;
; The debugger must have COM2 open exclusively; if we can open it, the driver
; isn't loaded, so say so rather than just "failed".
;
DEFPROC	check_port
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jc	cp1
	mov	bx,ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	PRINTF	<"DBGTEST requires DEVICE=DEBUG.COM COM2:... in CONFIG.SYS",13,10>
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
cp1:	CHECK	ax,ERR_SHARE
	ret
ENDPROC	check_port

	DEFWORD	original_sp,0
	DEFWORD	saved_flags,0
PORT_NAME	db	"COM2",0
PORT_PARMS	db	"COM2:9600,N,8,1",0

CODE	ends
	end	main
