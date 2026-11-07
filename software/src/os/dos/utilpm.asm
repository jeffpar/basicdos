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
	DISKIOCTL equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc
	include	cpu.inc

DOS	segment word public 'CODE'

	EXTWORD	<scb_active,r3_stseg,r3_sfbtab>
	EXTLONG	<sfb_table>
	EXTBYTE	<scb_locked,pmb_buf>
	EXTNEAR	<mem_alias,psp_owner,scb_release,r3_chkblk>
	EXTNEAR	<utl_lock,utl_unlock,utl_wait,utl_endwait,utl_hotkey>
	EXTNEAR	<utl_hprintf,hdl_ioctl,r3_chkstk,r3_chkrd,r3_gpcall>
	EXTNEAR	<hdl_open,hdl_create,hdl_close,hdl_seek,hdl_time,get_psp>

	.286p

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
;
; A ring 3 caller's selector is in a register, so the processor hasn't checked
; it, and the only alias that CPU$ keeps track of (and frees) is one for a
; block's own selector; so it has to be that, for a block that the caller owns.
; Otherwise, a program could use up the descriptors that the kernel needs.
;
	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	ua0			; no
	mov	bx,-1			; (its length isn't changing)
	xchg	cx,ax			; CX = block
	call	r3_chkblk		; CX = its first selector
	jc	ua9			; (AX = error code)
	mov	ax,[bp].REG_BX
	mov	dx,ax
	and	dl,NOT 3
	cmp	cx,dx			; is it the block's own selector?
	je	ua0			; yes
	mov	ax,ERR_BADADDR
	stc
	jmp	short ua9
ua0:	call	mem_alias
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_ulock, r3_uunlock, r3_uwait, r3_uendwait, r3_uhotkey, and r3_uhprintf
;
; With ring 3 programs, set_fault puts these in UTILTBL, in place of the
; functions they name, which are for drivers and the kernel: a lock stops every
; other session, an end of wait or hotkey affects them, and an SFH could be any
; session's file.  So a ring 3 caller gets ERR_ACCDENIED.
;
; Inputs and outputs:
;	See the functions named
;
	ASSUME	DS:DOS
DEFPROC	r3_ulock,DOS
	mov	si,offset utl_lock
	jmp	short ud1
	DEFLBL	r3_uunlock,near
	mov	si,offset utl_unlock
	jmp	short ud1
	DEFLBL	r3_uwait,near
	mov	si,offset utl_wait
	jmp	short ud1
	DEFLBL	r3_uendwait,near
	mov	si,offset utl_endwait
	jmp	short ud1
	DEFLBL	r3_uhotkey,near
	mov	si,offset utl_hotkey
	jmp	short ud1
	DEFLBL	r3_uhprintf,near
	mov	si,offset utl_hprintf
ud1:	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jnz	ud8			; yes
	jmp	si
ud8:	and	[bp].REG_FL,NOT FL_CARRY
	mov	ax,ERR_ACCDENIED
	mov	[bp].REG_AX,ax
	stc
	ret
ENDPROC	r3_ulock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_ioctl (REG_AH = 44h)
;
; With ring 3 programs, set_fault puts this in FUNCTBL, in place of hdl_ioctl:
; a driver uses the data at REG_DS:REG_SI directly, and a fault in a driver is
; fatal, so before a ring 3 caller's IOCTL reaches one, all of the data that
; the driver could use has to be in the caller's memory (see r3_read).  A
; length of zero still counts as one byte, since a driver may store a result
; regardless.
;
; Inputs and outputs:
;	See hdl_ioctl
;
	ASSUME	DS:DOS
DEFPROC	r3_ioctl,DOS
	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	ri9			; no
	pusha
	mov	bx,[bp].REG_BX
	call	r3_pfhok		; may it use the handle?
	jnc	ri1			; yes
	popa
	jmp	short rh7
ri1:	mov	cx,[bp].REG_CX		; CX = # of bytes, for most of them
	sub	bx,bx			; BX = 0 (it will write the data)
	cmp	al,IOCTL_GETPART
	je	ri2
	cmp	al,IOCTL_GETFPU
	jne	ri0
	mov	cx,4			; (a far pointer)
	jmp	short ri2
ri0:	inc	bx			; BX = 1 (it will read the data)
	cmp	al,IOCTL_SETPARMS
	je	ri2
	cmp	al,IOCTL_SETPART
	je	ri2
	cmp	al,IOCTL_GETLEN
	jne	ri8			; it doesn't use the data
	mov	ch,0			; (just CL)
ri2:	cmp	cx,1
	adc	cx,0			; (0 becomes 1)
	mov	dx,[bp].REG_DS
	mov	di,[bp].REG_SI		; DX:DI -> data
	test	bx,bx			; will it read the data?
	jnz	ri3			; yes
	call	r3_chkstk		; can it write the data?
	jmp	short ri4
ri3:	call	r3_chkrd		; can it read the data?
ri4:	jnc	ri8			; yes
	jmp	r3_gpcall
ri8:	popa
ri9:	jmp	hdl_ioctl
ENDPROC	r3_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_close (REG_AH = 3Eh), r3_seek (REG_AH = 42h), and r3_time (REG_AH = 57h)
;
; With ring 3 programs, set_fault puts these in FUNCTBL, in place of the
; functions they name: a program can write anything in its PSP_PFT, so a ring 3
; caller's handle has to lead to an SFB that its session may use (see
; r3_sfhok).
;
; Inputs and outputs:
;	See the functions named
;
	ASSUME	DS:DOS
DEFPROC	r3_close,DOS
	mov	si,offset hdl_close
	jmp	short rh1
	DEFLBL	r3_seek,near
	mov	si,offset hdl_seek
	jmp	short rh1
	DEFLBL	r3_time,near
	mov	si,offset hdl_time
rh1:	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jz	rh8			; no
	mov	bx,[bp].REG_BX
	call	r3_pfhok		; may it use the handle?
	jnc	rh8			; yes
	DEFLBL	rh7,near
	mov	ax,ERR_BADHANDLE
	mov	[bp].REG_AX,ax
	stc
	ret
rh8:	jmp	si
ENDPROC	r3_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_open (REG_AH = 3Dh) and r3_create (REG_AH = 3Ch)
;
; With ring 3 programs, set_fault puts these in FUNCTBL, in place of hdl_open
; and hdl_create, to record that a ring 3 caller's session may use the SFB that
; it just opened (see r3_sfhok).
;
; Inputs and outputs:
;	See hdl_open and hdl_create
;
	ASSUME	DS:DOS
DEFPROC	r3_open,DOS
	mov	si,offset hdl_open
	jmp	short ro1
	DEFLBL	r3_create,near
	mov	si,offset hdl_create
ro1:	test	byte ptr [bp].REG_CS,3	; a ring 3 caller?
	jnz	ro2			; yes
	jmp	si
ro2:	call	si
	ASSUME	DS:NOTHING
	jc	ro9
	call	get_psp
	mov	es,ax
	mov	bx,[bp].REG_AX		; BX = its handle
	mov	al,es:[PSP_PFT][bx]	; AL = its SFH
	call	r3_sfhbit
	or	es:[di+bx],ah		; (and clears carry)
ro9:	ret
ENDPROC	r3_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_sfhbit
;
; Finds a session's bit in the table that says who may use an SFB (see
; init_sess), for the current session.
;
; Inputs:
;	AL = SFH (which must be valid)
;
; Outputs:
;	ES:DI+BX -> the byte, AH = the bit
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	r3_sfhbit,DOS
	ASSUME	DS:NOTHING
	mov	es,cs:[r3_stseg]
	mov	ah,0
	shl	ax,2
	add	ax,cs:[r3_sfbtab]
	xchg	di,ax			; ES:DI -> the SFB's doubleword
	mov	bx,cs:[scb_active]
	mov	al,cs:[bx].SCB_NUM
	mov	cl,al
	and	cl,7
	mov	ah,1
	shl	ah,cl			; AH = the session's bit
	shr	al,3
	mov	bl,al
	mov	bh,0			; BX = the session's byte
	ret
ENDPROC	r3_sfhbit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_sfhok
;
; Checks that the current session may use an SFB: it's one of the session's
; own SFHs (from its SCB), or the session opened it while it's been open.  A
; session that shares an SFB (eg, a pipe) can still close its references to it,
; but no other session's file or device can be reached.  Anything that isn't an
; SFB is fine here, since the kernel rejects it.
;
; Inputs:
;	AL = SFH
;
; Outputs:
;	Carry clear if so
;
; Modifies:
;	None
;
DEFPROC	r3_sfhok,DOS
	ASSUME	DS:NOTHING
	pusha
	push	es
	mov	dl,al			; DL = SFH
	mov	ah,size SFB
	mul	ah
	add	ax,cs:[sfb_table].OFF
	cmp	ax,cs:[sfb_table].SEG	; is it an SFB?
	jae	so8			; no
	mov	bx,cs:[scb_active]
	lea	si,[bx].SCB_SFHIN
	mov	cx,5
so1:	cmp	cs:[si],dl		; one of the session's own?
	je	so8			; yes
	inc	si
	loop	so1
	mov	al,dl
	call	r3_sfhbit
	test	es:[di+bx],ah		; has the session opened it?
	jnz	so8			; yes
	stc
	jmp	short so9
so8:	clc
so9:	pop	es
	popa
	ret
ENDPROC	r3_sfhok

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_pfhok
;
; Inputs:
;	BX = handle (PFH)
;
; Outputs:
;	Carry clear if the current session may use its SFB (see r3_sfhok)
;
; Modifies:
;	None
;
DEFPROC	r3_pfhok,DOS
	ASSUME	DS:NOTHING
	push	ax
	push	ds
	call	get_psp
	jz	ph8			; (the kernel will reject it)
	cmp	bx,size PSP_PFT
	jae	ph8			; (and this, too)
	mov	ds,ax
	mov	al,ds:[PSP_PFT][bx]
	call	r3_sfhok
	jmp	short ph9
ph8:	clc
ph9:	pop	ds
	pop	ax
	ret
ENDPROC	r3_pfhok

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_pftfix
;
; Removes any handle from a PSP's PSP_PFT whose SFB the current session may not
; use (see r3_sfhok), before the kernel copies or closes them.
;
; Inputs:
;	AX = PSP
;
; Modifies:
;	None
;
DEFPROC	r3_pftfix,DOS
	ASSUME	DS:NOTHING
	pusha
	push	es
	mov	es,ax
	mov	di,offset PSP_PFT
	mov	cx,size PSP_PFT
pf1:	mov	al,es:[di]
	call	r3_sfhok
	jnc	pf2
	mov	byte ptr es:[di],SFH_NONE
pf2:	inc	di
	loop	pf1
	pop	es
	popa
	ret
ENDPROC	r3_pftfix

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; r3_sfbfree
;
; With ring 3 programs, sfb_close calls this (through sfb_hook) when an SFB
; closes, since no session may use the next file that it holds, until it opens
; that file itself.
;
; Inputs:
;	BX -> SFB
;
; Modifies:
;	None
;
DEFPROC	r3_sfbfree,DOS
	ASSUME	DS:NOTHING
	pusha
	push	es
	xchg	ax,bx
	sub	ax,cs:[sfb_table].OFF
	mov	cl,size SFB
	div	cl			; AL = its SFH
	mov	ah,0
	shl	ax,2
	add	ax,cs:[r3_sfbtab]
	xchg	di,ax			; DI -> its doubleword
	mov	es,cs:[r3_stseg]
	sub	ax,ax
	cld
	stosw
	stosw
	pop	es
	popa
	ret
ENDPROC	r3_sfbfree

DOS	ends

	end
