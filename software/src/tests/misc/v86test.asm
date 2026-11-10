;
; BASIC-DOS V86 Machine Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: V86 V86TEST
;
; A real-mode program that checks, from inside a V86 machine (see V86.COM),
; that the machine works as real mode would: CLI, STI, PUSHF, and POPF (with
; the machine's own IF), INTs to its vectors (reflected, with IF clear in the
; handler) and their IRETs, INT3, a divide error, the upper half of a 32-bit
; register across a DOS call, PUSHF with the direction flag set, and a hook of
; INT 21h that passes calls on to the default handler.  It prints "V86TEST
; passed", or "V86TEST failed (n)" for test n (and exits with 1).
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	dosapi.inc

INT_TEST	equ	60h	; (the first user vector)

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	dx,offset STARTING
	call	print
;
; 1: In V86 mode, the MSW says protected mode.
;
	db	0Fh,01h,0E0h		; SMSW AX
	test	al,1			; PE?
	jz	fail
;
; 2: CLI, STI, PUSHF, and POPF use the machine's IF.
;
	inc	[test]
	pushf
	pop	ax
	test	ah,FL_INTS SHR 8	; on to begin with?
	jz	fail
	cli
	pushf
	pop	ax
	test	ah,FL_INTS SHR 8	; off after CLI?
	jnz	fail
	push	ax
	sti
	popf				; POPF turns it off again
	pushf
	pop	ax
	test	ah,FL_INTS SHR 8
	jnz	fail
	sti
	pushf
	pop	ax
	test	ah,FL_INTS SHR 8	; on after STI?
	jz	fail
;
; 3: An INT goes to the machine's vector, with IF clear, and IRET returns.
;
	inc	[test]
	mov	dx,offset count_int
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_TEST
	int	21h
	int	INT_TEST
	int	INT_TEST
	int	INT_TEST
	cmp	[count],3
	jne	fail
	cmp	[ints],0		; was IF clear in the handler?
	jne	fail
	pushf
	pop	ax
	test	ah,FL_INTS SHR 8	; and on again after the IRET?
	jz	fail
	jmp	short t4
;
; The failures are here, in the middle, so that every test can reach them.
;
fail:	mov	al,[test]
	add	al,'0'
	mov	[FAILNUM],al
	mov	dx,offset FAILED
	call	print
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
;
; 4: INT3 goes to vector 03h.
;
t4:
	inc	[test]
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_BP
	int	21h			; (DX -> count_int still)
	int	3
	cmp	[count],4
	jne	fail
;
; 5: A divide error goes to vector 00h, which returns past the DIV.
;
	inc	[test]
	mov	dx,offset div_err
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_DV
	int	21h
	mov	bl,0
	mov	ax,1
	DEFLBL	div_op,near
	div	bl
	cmp	[count],5
	jne	fail
;
; 6: The upper half of a 32-bit register survives a DOS call.
;
	inc	[test]
	db	66h,0BBh		; MOV EBX,12345678h
	dd	12345678h
	mov	ah,DOS_MSC_GETVER
	int	21h
	db	66h,0C1h,0EBh,10h	; SHR EBX,16
	cmp	bx,1234h
	jne	fail
;
; 7: An instruction that CPU$ does for the machine (eg, PUSHF) works with the
; direction flag set (which would otherwise loop here, or worse).
;
	inc	[test]
	std
	pushf
	cld
	pop	ax
	test	ah,FL_DOWN SHR 8	; was DF in the FLAGS?
	jz	f7			; no
;
; 8: A hook of INT 21h can pass calls on to the previous handler (which
; exits the machine at its HLT), and gets their results.
;
	inc	[test]
	mov	ah,DOS_MSC_GETVER
	int	21h
	push	ax			; the version
	mov	ax,(DOS_MSC_GETVEC SHL 8) OR INT_DOSFUNC
	int	21h
	mov	[prev21].OFF,bx
	mov	[prev21].SEG,es
	mov	dx,offset hook21
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_DOSFUNC
	int	21h
	mov	ah,DOS_MSC_GETVER
	int	21h			; (through the hook)
	pop	cx
	cmp	ax,cx			; the same version?
	jne	f7
	cmp	[count],6		; and the hook saw it?
	jne	f7
	push	ds
	lds	dx,[prev21]
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_DOSFUNC
	int	21h			; (through the hook, too)
	pop	ds
	cmp	[count],7
	jne	f7
	mov	dx,offset PASSED
	call	print
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
f7:	jmp	fail
ENDPROC	main

DEFPROC	print
	mov	ah,DOS_TTY_PRINT
	int	21h
	ret
ENDPROC	print
;
; Counts an interrupt, and records whether IF was on.
;
DEFPROC	count_int
	push	ax
	pushf
	pop	ax
	and	ah,FL_INTS SHR 8
	or	cs:[ints],ah
	inc	cs:[count]
	pop	ax
	iret
ENDPROC	count_int
;
; Counts the divide error, and returns past the DIV (2 bytes).
;
DEFPROC	div_err
	push	bp
	mov	bp,sp
	cmp	word ptr [bp+2],offset div_op	; at the DIV?
	jne	de9				; no (so test 5 fails)
	add	word ptr [bp+2],2
	inc	cs:[count]
de9:	pop	bp
	iret
ENDPROC	div_err
;
; Counts a DOS call, and passes it on.
;
DEFPROC	hook21
	inc	cs:[count]
	jmp	dword ptr cs:[prev21]
ENDPROC	hook21

	DEFBYTE	test,1
	DEFBYTE	count,0
	DEFBYTE	ints,0
	DEFLONG	prev21,0
	DEFSTR	STARTING,<"V86TEST starting",13,10,"$">
	DEFSTR	PASSED,<"V86TEST passed",13,10,"$">
	DEFSTR	FAILED,<"V86TEST failed (">
	DEFSTR	FAILNUM,<"0)",13,10,"$">

	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
