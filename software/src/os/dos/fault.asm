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

	EXTNEAR	<get_psp,psp_owner,dos_abort>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_fault (see CPU_SETFAULT)
;
; In protected mode, CPU$ gives us any exception that it can't handle (unless
; it occurred in CPU$ or in DOS), and a debugger passes on the ones it doesn't
; trap (eg, DEBUG.COM, unless its VT command traps the vector).  If it
; occurred in the current program's own code (including any block of code
; that it owns), we report it and end the program, as dos_dverr does (or for
; a session's last program, such as its shell, signal a CTRLC; see psp_term);
; otherwise, we decline it by returning, so that the debugger (if any) can
; stop for it, or CPU$ reports it and stops the machine (and CPU$'s offer of
; the halt, with FAULT_HALTED, is declined, too, since we found it fatal).
;
; Only protected mode needs this and the NE loader that follows it (see
; neload.asm), so in real mode, sysinit's tables start here (see set_fault).
;
; Inputs:
;	SS:SP -> return address, vector, error code, and the faulting
;	instruction's IP, CS, and FLAGS
;
DEFPROC	dos_fault,DOSFAR
	push	ax
	push	bx
	push	es
	mov	bx,sp
	call	get_psp			; AX = current PSP (ZF set if none)
	jnz	df0a			; (df9 is here, in reach of every jump)
df9:	pop	es
	pop	bx
	pop	ax
	ret
df0a:	mov	es,ax
	mov	ax,ss:[bx+16]		; AX = faulting CS
	cmp	es:[PSP_START].SEG,ax	; is it the program's code?
	je	df1			; yes
;
; It's also the program's own code if it's in a block that the program owns
; (eg, one of COMMAND's code blocks), which CPU$ finds from the selector (a
; program that shares another copy's code has it in PSP_START, although the
; other copy owns it; see load_program); the block's owner is compared with
; the program's owner ID (see psp_owner), which at ring 3 isn't its PSP.
;
	push	bx
	push	cx
	push	dx
	push	di
	sub	sp,size PMB
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> PMB buffer
	xchg	cx,ax			; CX = faulting CS
	mov	bx,-1
	mov	dx,bx			; DX = -1 (CX is a selector)
	mov	ah,CPU_QUERY
	call	far ptr DDINT_CPU	; PMB of the block at CX
	jc	df0			; there's none (AX = a nonzero error)
	push	es:[di].PMB_OWNER	; save the block's owner
	call	get_psp			; AX = current PSP
	call	psp_owner		; AX = its owner ID
	pop	cx			; CX = the block's owner
	jc	df0			; no PSP block (AX = a nonzero error)
	sub	ax,cx			; AX = 0 if the program owns the block
df0:	add	sp,size PMB
	pop	di
	pop	dx
	pop	cx
	pop	bx
	test	ax,ax			; is it the program's own code?
	jnz	df9			; no
;
; As in dos_dverr, the values to print (the vector, error code, and address)
; are already on the stack, once CS precedes IP.
;
df1:	mov	ax,ss:[bx+14]
	xchg	ax,ss:[bx+16]
	mov	ss:[bx+14],ax
	pop	es
	pop	bx
	pop	ax
	add	sp,4			; discard the return address
	PRINTF	<"CPU fault %02x (EC=%04x) at %04x:%04x",13,10>
	mov	ah,EXTYPE_FAULT
	jmp	dos_abort
ENDPROC	dos_fault

DOS	ends

	end
