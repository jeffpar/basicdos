;
; BASIC-DOS Fault Test
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Usage: FAULT vector (-1, 0, 1, 3-6, 12, or 13)
;
; Causes the processor exception with the given (decimal) vector, to see how
; BASIC-DOS responds and recovers, especially in protected mode (eg, FAULT 13
; on the Protected Mode demo):
;
;	-1	a null pointer to a filename, which the kernel faults reading
;		in protected mode (which ends the program at ring 3, and is
;		fatal with RING=0)
;	0	divide error (DIV by zero)
;	1	single-step trap (TF set for one instruction)
;	3	breakpoint (INT 3)
;	4	overflow (INTO with OF set)
;	5	BOUND range exceeded (80186 or later)
;	6	invalid opcode (80186 or later)
;	12	stack fault (a word at SS:FFFFh)
;	13	general protection fault (a write to CS, which only protected
;		mode forbids)
;
; If FAULT resumes (eg, after a trap, or if nothing faulted), it prints
; "FAULT n done" and exits with code 0; a missing or invalid vector prints the
; usage and exits with code 1.
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	dosapi.inc
	include	devapi.inc
	include	8086.inc

FAULT_MAX	equ	13		; the last vector in the faults table

CODE	segment
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:CODE
	org	100h

DEFPROC	main
	mov	si,PSP_CMDTAIL+1
	call	skip_ws
	DOSUTIL	ATOI32D			; DX:AX = vector
	jc	m8			; no digits
	xchg	bx,ax			; BX = vector (low word)
	call	skip_ws			; AL = next character
	cmp	al,CHR_RETURN		; is there anything after the vector?
	jne	m8			; yes
	inc	bx			; (the faults table starts at -1)
	jnz	m1
	inc	dx			; (so -1 becomes 0:0)
m1:	test	dx,dx			; is the vector out of range?
	jnz	m8			; yes
	cmp	bx,FAULT_MAX+1		; is it beyond the table?
	ja	m8			; yes
	mov	al,[faults][bx]		; AL = offset of its code from main
	test	al,al			; is it a vector we can cause?
	jz	m8			; no
	mov	ah,0
	add	ax,offset main
	call	ax			; (each one leaves BX alone)
	dec	bx			; BX = vector
	PRINTF	<"FAULT %d done",13,10>,bx
	int	20h
m8:	PRINTF	<"Usage: FAULT vector (-1, 0, 1, 3-6, 12, or 13)",13,10>
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	main

;
; Each of these causes the exception for its vector, and returns if that
; resumes.
;
; We can load a null selector into DS, but the kernel faults reading a
; filename through it (in real mode, 0:0 is the interrupt vectors, which aren't
; a filename that DOS can find).
;
fm1:	push	ds
	sub	ax,ax
	cwd
	mov	ds,ax			; DS:DX = 0:0
	mov	ax,DOS_DSK_GETATTR
	int	21h
	pop	ds
	ret

f0:	sub	cx,cx
	div	cx			; divide by zero
	ret
;
; Setting TF with POPF traps after the next instruction, which clears TF, so
; there's exactly one trap.
;
f1:	pushf
	pushf
	mov	bp,sp
	or	byte ptr [bp+1],FL_TRAP SHR 8
	popf
	popf
	ret
;
; A NOP before the INT 3 would make it an ASSERT (see dos_brkpt).
;
f3:	int	3
	ret

f4:	mov	al,7Fh
	inc	al			; sets OF
	into
	ret
;
; AX (0) is below the lower bound (20CDh, the PSP's INT 20h).
;
f5:	sub	ax,ax
	.186
	bound	ax,dword ptr ds:[PSP_TERMCALL]
	.8086
	ret
;
; 0Fh 0Bh (UD2 on later processors) is an invalid opcode on an 80186 or
; later (on an 8086, 0Fh is POP CS).
;
f6:	db	0Fh,0Bh
	ret
;
; A word at FFFFh extends past the end of any segment.
;
f12:	mov	bp,0FFFFh
	mov	ax,[bp]
	ret
;
; The PSP's command tail (which we've parsed) is ours to write, but not
; through CS in protected mode, where CS is our block's code alias.
;
f13:	mov	cs:[PSP_CMDTAIL],al
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; skip_ws
;
; Inputs:
;	SI -> characters
;
; Outputs:
;	AL = first character that isn't a space or tab, SI -> it
;
DEFPROC	skip_ws
	lodsb
	cmp	al,CHR_SPACE
	je	skip_ws
	cmp	al,CHR_TAB
	je	skip_ws
	dec	si
	ret
ENDPROC	skip_ws
;
; Each vector's code (from -1 on), as an offset from main (or 0 if we can't
; cause it).
;
faults	db	fm1-main,f0-main,f1-main,0,f3-main,f4-main,f5-main,f6-main
	db	0,0,0,0,0,f12-main,f13-main

	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ends
	end	main
