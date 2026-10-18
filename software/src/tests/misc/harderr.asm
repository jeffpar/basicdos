;
; BASIC-DOS Hard Error (INT 24h) Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dosapi.inc
	include	dosfunc.inc
	include	devapi.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	100h
;
; These tests use drive B:, which must be empty, so that every request fails
; with "not ready" (BIOS error 80h); each failure takes a few seconds, since
; the BIOS retries the request before giving up.
;
; After installing an INT 24h handler that records its inputs and returns the
; responses in a list, we open a file on B:, which fails as soon as the drive's
; BPB can't be built, and verify that:
;
;   1) RETRY reissues the request (so the handler is called again), FAIL then
;      returns error 21 (ERR_NOTREADY), and the handler saw AH = 18h (a read
;      of the reserved area, with RETRY and FAIL allowed), AL = 1 (drive B),
;      DI = 2 (not ready), BP:SI -> the FDC$ device header, and a stack other
;      than our own;
;
;   2) IGNORE is converted to FAIL when it isn't allowed (eg, while building
;      the BPB);
;
;   3) ABORT terminates the program (with exit code 255); if it doesn't, the
;      program prints "HARDERR abort failed" and returns 1.
;
; "HARDERR passed" is printed before the ABORT test, so a BAT file (or script)
; should check for both that message and ERRORLEVEL 255.
;
DEFPROC	main
	cld
	mov	dx,offset handler
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_DOSERROR
	int	21h
	mov	ax,(DOS_MSC_GETVEC SHL 8) OR INT_DOSERROR
	int	21h			; ES:BX = INT 24h handler address
	cmp	bx,offset handler
	jne	m8
	mov	ax,es
	mov	bx,cs
	cmp	ax,bx
	jne	m8
	push	cs
	pop	es
;
; Test 1: RETRY, then FAIL
;
	mov	si,offset test1
	call	trigger			; AX = error code, carry set
	jnc	m8			; the open should have failed
	cmp	ax,ERR_NOTREADY
	jne	m8
	cmp	[count],2
	jne	m8
	cmp	[regAX],((CRERR_RETRYOK OR CRERR_FAILOK) SHL 8) OR 1
	jne	m8
	cmp	[regDI],ERR_NOTREADY - 19
	jne	m8
	mov	ax,[regSS]
	cmp	ax,bx			; was the handler called on our stack?
	je	m8			; yes (it should have been DOS's)
	les	di,[regDDH]		; ES:DI -> DDH, hopefully
	cmp	word ptr es:[di].DDH_NAME,'DF'
	jne	m8
	cmp	word ptr es:[di].DDH_NAME+2,'$C'
	jne	m8
	push	cs
	pop	es
;
; Test 2: IGNORE (not allowed here, so it should be converted to FAIL)
;
	mov	si,offset test2
	call	trigger
	jnc	m8
	cmp	ax,ERR_NOTREADY
	jne	m8
	cmp	[count],1
	jne	m8
	mov	dx,offset passed
	call	print
;
; Test 3: ABORT (the program should be terminated; if we return, it failed)
;
	mov	si,offset test3
	call	trigger
	mov	dx,offset abortfail
m8a:	call	print
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
m8:	mov	dx,offset failed
	jmp	m8a
ENDPROC	main

;
; trigger
;
; Resets the handler's call count, gives it a new list of responses, and
; opens a file on drive B:.
;
; Inputs:
;	SI -> list of responses
;
; Outputs:
;	Carry set if the open failed, AX = error code
;
DEFPROC	trigger
	mov	[responses],si
	mov	[count],0
	mov	dx,offset filename
	mov	ax,DOS_HDL_OPENRO
	int	21h
	ret
ENDPROC	trigger

;
; handler (INT 24h)
;
; Records the registers DOS passed, counts the call, and returns the next
; response from the list.
;
DEFPROC	handler,far
	push	ds
	push	cs
	pop	ds
	mov	[regAX],ax
	mov	[regDI],di
	mov	[regDDH].OFF,si
	mov	[regDDH].SEG,bp
	mov	[regSS],ss
	inc	[count]
	push	si
	mov	si,[responses]
	lodsb
	mov	[responses],si
	pop	si
	pop	ds
	iret
ENDPROC	handler

DEFPROC	print
	mov	ah,DOS_TTY_PRINT
	int	21h
	ret
ENDPROC	print

count		db	0
responses	dw	0
regAX		dw	0
regDI		dw	0
regDDH		dd	0		; BP:SI
regSS		dw	0
test1		db	CRERR_RETRY,CRERR_FAIL
test2		db	CRERR_IGNORE,CRERR_FAIL
test3		db	CRERR_ABORT,CRERR_FAIL
filename	db	"B:HARDERR.TMP",0
passed		db	"HARDERR passed",13,10,'$'
failed		db	"HARDERR failed",13,10,'$'
abortfail	db	"HARDERR abort failed",13,10,'$'

CODE	ENDS

	end	main
