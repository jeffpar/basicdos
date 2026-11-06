;
; BASIC-DOS Protected-Mode Utility Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Only protected mode needs this code, so it follows dos_fault, in the part of
; the kernel's resident code that real mode doesn't keep (see set_fault, which
; installs these functions, and utl_segself, which real mode uses instead).
;
	DOSPSP equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	dos.inc
	include	dosapi.inc
	include	cpu.inc

DOS	segment word public 'CODE'

	EXTWORD	<scb_active>
	EXTBYTE	<scb_locked,pmb_buf>
	EXTNEAR	<mem_alias,psp_owner,scb_release>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_alias (AH = 27h)
;
; Returns the code alias of a memory block (see mem_alias), which a program
; needs to execute code that it writes into the block (eg, COMMAND.COM's code
; blocks), or with REG_AL = 1, the reverse: the block's own selector, with
; the alias's RPL, which a program needs to change code that it runs through
; the alias (eg, DEBUG.COM storing a breakpoint at ring 3, where code isn't
; writable).
;
; Inputs:
;	REG_AL = 0 for a block's code alias, or 1 for a code alias's block
;	REG_BX = block's segment (or selector), or with REG_AL = 1, its alias
;
; Outputs:
;	Carry clear if successful: REG_AX = code segment (or selector), or
;	with REG_AL = 1, the block's segment (or selector)
;	Carry set if error: REG_AX = error code
;
DEFPROC	utl_alias,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ax,[bp].REG_BX
	cmp	byte ptr [bp].REG_AL,1	; a code alias's block instead?
	je	ua1			; yes
	call	mem_alias
	jmp	short ua9
ua1:	LOCK_SCB			; (for pmb_buf)
	push	ds
	pop	es
	mov	di,offset pmb_buf	; ES:DI -> PMB buffer
	push	ax
	call	psp_owner		; the PMB of the block at AX's base
	pop	cx			; CX = the alias
	jc	ua8			; there's none (AX = error code)
	mov	ax,[pmb_buf].PMB_SEL
	and	cl,3
	or	al,cl			; AX = its selector (with alias's RPL)
ua8:	mov	[bp].REG_AX,ax
	UNLOCK_SCB_RET
ua9:	mov	[bp].REG_AX,ax		; (carry is unchanged)
	ret
ENDPROC	utl_alias

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_mapseg (AH = 28h)
;
; Returns a selector for a real-mode segment's 64K, for programs that read
; and write memory by segment (eg, BASIC's DEF SEG, PEEK, and POKE).  The
; session keeps the selector (a later call replaces it), which is writable for
; video memory (A000h through BFFFh), and read-only everywhere else, so that
; programs can read low memory (eg, the BIOS data area) and the ROMs, but not
; change them.
;
; Inputs:
;	REG_BX = real-mode segment
;
; Outputs:
;	Carry clear if successful: REG_AX = selector (or segment)
;	Carry set if error: REG_AX = error code
;
DEFPROC	utl_mapseg,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	bx,[bp].REG_BX		; BX = segment
	mov	ax,bx
	mov	cl,4
	shl	ax,cl
	mov	dx,bx
	mov	cl,12
	shr	dx,cl
	xchg	cx,ax			; DX:CX = the segment's address
	mov	al,MEMF_RDONLY OR MEMF_USER
	cmp	bh,0A0h			; video memory (A000h-BFFFh)?
	jb	ums1			; no
	cmp	bh,0C0h
	jae	ums1			; no
	mov	al,MEMF_USER		; yes, so it's writable
ums1:	mov	si,1
	sub	di,di			; SI:DI = 64K
	mov	ah,CPU_MAP
	call	far ptr DDINT_CPU	; AX = new selector
	jc	ums8
	mov	bx,[scb_active]
	xchg	ax,[bx].SCB_MAPSEL	; AX = the session's previous one
	test	ax,ax			; is there one?
	jz	ums3			; no
;
; Free the previous selector, and like mem_free, make sure the caller doesn't
; get it back in ES or DS.
;
	push	bx
	xchg	bx,ax			; BX = previous selector
	cmp	[bp].REG_ES,bx
	jne	ums2
	mov	[bp].REG_ES,0
ums2:	cmp	[bp].REG_DS,bx
	jne	ums2a
	mov	[bp].REG_DS,0
ums2a:	sub	cx,cx			; CX = 0 (one selector)
	mov	ah,CPU_UNMAP
	call	far ptr DDINT_CPU
	pop	bx
	clc
ums3:	mov	bx,[bx].SCB_MAPSEL
ums9:	mov	[bp].REG_AX,bx		; (carry is clear)
	ret
ums8:	mov	[bp].REG_AX,ax		; (carry is set)
	ret
ENDPROC	utl_mapseg

DOS	ends

	end
