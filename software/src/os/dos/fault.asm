;
; BASIC-DOS Protected-Mode Fault Handler
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dos.inc
	include	dosapi.inc
	include	cpu.inc

DOS	segment word public 'CODE'

	EXTNEAR	<get_psp,dos_abort>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_fault (see CPU_SETFAULT)
;
; In protected mode, CPU$ gives us any exception that it can't handle (unless
; it occurred in CPU$ or in DOS), and a debugger passes on the ones it doesn't
; trap (eg, DEBUG.COM, unless its VT command traps the vector).  If it
; occurred in the current program's own code, we report it and end the
; program, as dos_dverr does; otherwise, we stop giving exceptions to any
; handler and retry the instruction, so that CPU$ reports the exception and
; stops the machine.
;
; This is the last of the kernel's resident code, since only protected mode
; needs it: otherwise, sysinit's tables start here (see set_fault).
;
; Inputs:
;	SS:SP -> vector, error code, and the faulting instruction's IP, CS,
;	and FLAGS
;
DEFPROC	dos_fault,DOSFAR
	push	ax
	push	bx
	push	es
	mov	bx,sp
	call	get_psp			; AX = current PSP (ZF set if none)
	jz	df8
	mov	es,ax
	mov	ax,ss:[bx+12]		; AX = faulting CS
	cmp	es:[PSP_START].SEG,ax	; is it the program's own code?
	jne	df8			; no
	pop	es
	pop	bx
	pop	ax
	IFNDEF	DEBUG
	PRINTF	<"CPU fault %02x",13,10>
	ELSE
;
; As in dos_dverr, the values to print (the vector, error code, and address)
; are already on the stack.
;
	PRINTF	<"CPU fault %02x (EC=%04x) @%08lx",13,10>
	ENDIF
	mov	ah,EXTYPE_FAULT
	jmp	dos_abort
df8:	push	cx
	push	dx
	sub	cx,cx
	sub	dx,dx			; DX:CX = no handler
	mov	ah,CPU_SETFAULT
	call	far ptr DDINT_CPU
	pop	dx
	pop	cx
	pop	es
	pop	bx
	pop	ax
	add	sp,4			; discard the vector and error code
	iret
ENDPROC	dos_fault

DOS	ends

	end
