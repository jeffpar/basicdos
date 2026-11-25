;
; BASIC-DOS System Initialization Helpers
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; These functions are used only by SYSINIT (see sysinit.asm), and since this
; module is linked immediately after it, they are moved and recycled along
; with the rest of the system initialization code (before the SHELLs are
; loaded; see systail.asm).  That includes set_fault and init_sess, which set
; up the kernel's protected-mode exception and ring 3 handling.
;
	BIOSAPI equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dos.inc
	include	dosapi.inc
	include	cpu.inc

DOS	segment word public 'CODE'

	EXTNEAR	<sysinit_error,find_cfg>
	EXTWORD	<dos_seg>
	EXTBYTE	<prog_user,r3_stubs>
	EXTWORD	<dos_code,mcb_limit,sprintf_hook,r3_code,r3_vsel,r3_ksel>
	EXTWORD	<FUNCTBL,UTILTBL>
	EXTLONG	<err_stack>
	EXTABS	<FUNCTBL_SIZE,UTILTBL_SIZE>
	EXTNEAR	<sysinit_start,dos_fault,fcb_code,func_none,chk_devlist>
	EXTNEAR	<ms_parent,utl_alias,utl_mapseg,r3_sprintf>
	EXTNEAR	<r3_free,r3_realloc,r3_term,r3_return,r3_exec,r3_pspset>
	EXTNEAR	<r3_pspcopy,r3_pspnew,r3_read,r3_write,r3_sread,r3_swrite>
	EXTNEAR	<r3_rread,r3_rwrite,r3_rbread,r3_rbwrite,r3_uterm,r3_uload>
	EXTNEAR	<r3_ulock,r3_uunlock,r3_uwait,r3_uendwait,r3_uhotkey>
	EXTNEAR	<r3_uhprintf,r3_ioctl,r3_open,r3_create,r3_close,r3_seek>
	EXTNEAR	<r3_dup,r3_time,r3_sfbfree,init_fpu>
	EXTWORD	<r3_sfbtab,sfb_hook,cfg_counts,r3_stseg>

	DEFWORD	tbl_next		; offset of next table (see init_table)

	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_bpbtime
;
; Set the timestamp of a BPB to the current BIOS tick count (as the FDC and
; HDC drivers do whenever they access the media).
;
; Inputs:
;	DS:DI -> BPB
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	set_bpbtime
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; CX:DX is current tick count
	mov	[di].BPB_TIMESTAMP._OFF,dx
	mov	[di].BPB_TIMESTAMP._SEG,cx
	ret
ENDPROC	set_bpbtime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_table
;
; Initializes a table of AX entries of length DX at tbl_next (an offset in the
; DOS segment), stores the table's offset at [BX] and its limit at [BX+2] (in
; the DOS segment too), and advances tbl_next to the next paragraph.  This
; runs in sysinit's block (SS = its data), where tbl_next is.
;
; Outputs:
;	Nothing
;
; Modifies: CX, DX, DI
;
DEFPROC	init_table
	ASSUME	DS:NOTHING, ES:NOTHING
	push	ax
	push	es
	mov	es,[dos_seg]
	mul	dx			; AX = length of table in bytes
	xchg	cx,ax			; CX = length
	mov	di,ss:[tbl_next]	; ES:DI -> table
	mov	es:[bx]._OFF,di		; save DS-relative offset
	mov	ax,di
	add	ax,cx			; does the table fit in the segment?
	jc	it8			; no
	add	ax,15
	jc	it8
	and	al,0F0h
	mov	ss:[tbl_next],ax
	mov	al,0
	rep	stosb			; zero the table
	mov	es:[bx]._SEG,di		; save DS-relative limit
	pop	es
	pop	ax
	ret
it8:	jmp	sysinit_error		; no, sadly
ENDPROC	init_table

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; open_dev
;
; Opens the device in a CONFIG.SYS setting (eg, "PRN=LPT2"), or if there's
; no such setting, the default device.  If the device can't be opened, the
; session has no such device (SFH_NODEV), which is reported for a setting
; but not for a default (eg, LPT1 on a machine without a parallel port).
;
; Inputs:
;	SI -> setting (eg, CFG_PRN)
;	DX -> default device (eg, "LPT1")
;
; Outputs:
;	AL = SFH, or SFH_NODEV
;
; Modifies:
;	AX, DX, SI, DI
;
DEFPROC	open_dev
	call	find_cfg		; look for the setting
	jc	od1			; not found
	mov	dx,di			; DX -> setting
od1:	sbb	si,si			; SI = -1 if not found, 0 if found
	mov	ax,DOS_HDL_OPENRW
	int	21h
	jnc	od9
	inc	si			; was the device from a setting?
	jz	od8			; no
	call	open_warning
od8:	mov	al,SFH_NODEV
od9:	ret
ENDPROC	open_dev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; open_warning
;
; Inputs:
;	AX = error code
;	DX -> device setting (eg, "COM2:9600,N,8,1")
;
; Modifies:
;	AX
;
DEFPROC	open_warning
	EPRINTF	<"Warning: unable to open %s">,<13,10>,ax,dx
	ret
ENDPROC	open_warning

	ASSUME	DS:DOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_fault
;
; In protected mode, has CPU$ give us any exception that it can't handle (see
; dos_fault), before any DEVICE= driver (eg, DEBUG.COM) can take them, so that
; a debugger can pass them on to us.  Otherwise, exceptions go through the
; vectors, so the kernel doesn't need dos_fault or the NE loader that follows
; it (see neload.asm), and its resident code ends at dos_fault.
;
; In protected mode, the hard error stack (see dev_error) follows the
; resident code; in real mode, it's in the vector table (see ERR_STACK_TOP).
;
; Outputs:
;	AX = offset of the end of the kernel's resident code (and stack)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	set_fault
	mov	ah,CPU_GETINFO
	call	far ptr DDINT_CPU	; AH = CPUF_* flags
	test	ah,CPUF_PM		; protected mode?
	mov	ax,offset dos_fault
	jnz	sf0			; yes
;
; A machine with 64K or less can't spare the memory for the FCB functions,
; or for other consoles' sessions (it has only one console; see multi.asm), so
; the resident code ends at fcb_code instead, every function at or after that
; becomes "unsupported", and every jump to multi.asm (each one followed by the
; label it should fall through to) gets a displacement of zero.
;
	cmp	[mcb_limit],1000h	; more than 64K?
	ja	sf0b			; yes
	sub	ax,ax
	mov	word ptr [chk_devlist-2],ax
	mov	word ptr [ms_parent-2],ax
	mov	ax,offset fcb_code
	push	bx
	mov	bx,offset FUNCTBL
	mov	cx,FUNCTBL_SIZE
	add	cx,UTILTBL_SIZE		; (which follows FUNCTBL)
sf0a:	cmp	[bx],ax			; is the function staying?
	jb	sf0c			; yes
	mov	word ptr [bx],offset func_none
sf0c:	inc	bx
	inc	bx
	loop	sf0a
	pop	bx
sf0b:
;
; Fill the real-mode hard error stack with SIG_BASICDOS, so that a dump of
; the vector table shows how much of the stack has ever been used.
;
	push	es
	push	di
	xchg	dx,ax			; save AX
	sub	di,di
	mov	es,di
	mov	di,ERR_STACK_TOP - ERR_STACK_SIZE
	mov	cx,ERR_STACK_SIZE / 2
	mov	ax,SIG_BASICDOS
	rep	stosw
	xchg	ax,dx			; AX = end of the resident code
	pop	di
	pop	es
	ret
sf0:	mov	[UTILTBL + DOS_UTL_ALIAS * 2],offset utl_alias
	mov	[UTILTBL + DOS_UTL_MAPSEG * 2],offset utl_mapseg
	xchg	cx,ax
	mov	dx,cs:[dos_code]	; DX:CX -> dos_fault
	mov	ah,CPU_SETFAULT
	call	far ptr DDINT_CPU
;
; Programs run at ring 3 (see r3supp.asm), unless a "RING=0" line keeps them
; at ring 0.
;
	push	si
	push	di
	mov	si,offset CFG_RING
	call	find_cfg		; look for "RING="
	jc	sf7			; none, so ring 3
	cmp	byte ptr ss:[di],'0'	; RING=0? (find_cfg's data is in SS)
	jne	sf7			; no
	jmp	sf8			; yes
sf7:	mov	[prog_user],MEMF_USER
	mov	[sprintf_hook],offset r3_sprintf
	mov	si,offset r3_funcs
sf7c:	lods	word ptr cs:[si]
	xchg	di,ax			; DI -> a function's table entry
	lods	word ptr cs:[si]
	mov	[di],ax			; (its ring 3 version)
	cmp	si,offset r3_fend
	jb	sf7c
	push	bx
	mov	bx,cs:[dos_code]
	mov	[r3_ksel],bx
	mov	ax,(CPU_ALIAS SHL 8) OR MEMF_CODE OR MEMF_RDONLY OR MEMF_USER
	call	far ptr DDINT_CPU
	or	al,3
	mov	[r3_code],ax		; (see r3_stub)
;
; So that a fault in the kernel reaches dos_fault (see r3_end), dos_fault gets
; a code selector of its own, since CPU$ won't call a fault handler for a
; fault in the handler's own code segment; a fault in dos_fault itself is
; still fatal.
;
	mov	ax,(CPU_ALIAS SHL 8) OR MEMF_CODE
	call	far ptr DDINT_CPU	; AX = another selector for the kernel
	pop	bx
	jc	sf7a			; (none, so kernel faults stay fatal)
	xchg	dx,ax
	mov	cx,offset dos_fault	; DX:CX -> dos_fault
	mov	ah,CPU_SETFAULT
	call	far ptr DDINT_CPU
sf7a:
;
; The vector stubs (see RVEC) get a readable code selector of their own, since
; a ring 3 program gets their address in ES:BX, and r3_code (execute-only, for
; the whole kernel) can't be loaded into ES.
;
	push	bx
	mov	bx,cs:[dos_code]
	mov	ax,(CPU_SEGINFO SHL 8) OR ADDR_SEL
	call	far ptr DDINT_CPU	; DX:CX = the kernel's base
	pop	bx
	add	cx,offset r3_stubs
	adc	dx,0			; DX:CX -> r3_stubs
	sub	si,si
	mov	di,R3_RVECS * 2		; SI:DI = their length
	mov	ax,(CPU_MAP SHL 8) OR MEMF_CODE OR MEMF_USER
	call	far ptr DDINT_CPU	; AX = their selector
	jc	sf8			; (none, so no stubs)
	or	al,3
	mov	[r3_vsel],ax
sf8:	pop	di
	pop	si
	mov	ax,offset sysinit_start + ERR_STACK_SIZE + 1
	and	al,0FEh			; AX = top of the stack (word-aligned)
	mov	[err_stack]._OFF,ax
	mov	[err_stack]._SEG,ds
	ret
ENDPROC	set_fault
;
; The DOS functions that have versions for ring 3 programs (see r3prog.asm), as
; the address of each one's table entry and its ring 3 version.
;
	DEFLBL	r3_funcs,word
	dw	FUNCTBL + DOS_MEM_FREE * 2,r3_free
	dw	FUNCTBL + DOS_MEM_REALLOC * 2,r3_realloc
	dw	FUNCTBL + DOS_PSP_TERM * 2,r3_term
	dw	FUNCTBL + DOS_PSP_RETURN * 2,r3_return
	dw	FUNCTBL + (DOS_PSP_EXEC SHR 8) * 2,r3_exec
	dw	FUNCTBL + DOS_PSP_SET * 2,r3_pspset
	dw	FUNCTBL + DOS_PSP_COPY * 2,r3_pspcopy
	dw	FUNCTBL + DOS_PSP_CREATE * 2,r3_pspnew
	dw	FUNCTBL + DOS_HDL_READ * 2,r3_read
	dw	FUNCTBL + DOS_HDL_WRITE * 2,r3_write
	dw	FUNCTBL + DOS_FCB_SREAD * 2,r3_sread
	dw	FUNCTBL + DOS_FCB_SWRITE * 2,r3_swrite
	dw	FUNCTBL + DOS_FCB_RREAD * 2,r3_rread
	dw	FUNCTBL + DOS_FCB_RWRITE * 2,r3_rwrite
	dw	FUNCTBL + DOS_FCB_RBREAD * 2,r3_rbread
	dw	FUNCTBL + DOS_FCB_RBWRITE * 2,r3_rbwrite
	dw	UTILTBL + DOS_UTL_TERM * 2,r3_uterm
	dw	UTILTBL + DOS_UTL_LOAD * 2,r3_uload
	dw	UTILTBL + DOS_UTL_LOCK * 2,r3_ulock
	dw	UTILTBL + DOS_UTL_UNLOCK * 2,r3_uunlock
	dw	UTILTBL + DOS_UTL_WAIT * 2,r3_uwait
	dw	UTILTBL + DOS_UTL_ENDWAIT * 2,r3_uendwait
	dw	UTILTBL + DOS_UTL_HOTKEY * 2,r3_uhotkey
	dw	UTILTBL + DOS_UTL_HPRINTF * 2,r3_uhprintf
	dw	FUNCTBL + DOS_HDL_IOCTL * 2,r3_ioctl
	dw	FUNCTBL + DOS_HDL_OPEN * 2,r3_open
	dw	FUNCTBL + DOS_HDL_CREATE * 2,r3_create
	dw	FUNCTBL + DOS_HDL_CLOSE * 2,r3_close
	dw	FUNCTBL + DOS_HDL_SEEK * 2,r3_seek
	dw	FUNCTBL + DOS_HDL_DUP * 2,r3_dup
	dw	FUNCTBL + (DOS_HDL_GETTIME SHR 8) * 2,r3_time
	DEFLBL	r3_fend,word

CFG_RING	db	5,"RING="

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_sess
;
; Allocates what every session needs one of: with programs at ring 3 (see
; set_fault), a ring 0 stack (see r3_top), and then an FPU state (see
; init_fpu).  If there's no room for the stacks, programs run at ring 0.
;
; Inputs:
;	AL = # of sessions, DH = FPU type (FPUTYPE_*, from IOCTL_GETFPU)
;	ES = DOS
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
	ASSUME	ES:DOS
DEFPROC	init_sess
	cmp	es:[prog_user],0	; ring 3 programs?
	je	is9			; no
	push	ax
	push	dx
	mov	ah,R3_STACK_SIZE SHR 8
	mul	ah
	mov	ah,al
	mov	al,0
	xchg	di,ax			; DI = sessions * R3_STACK_SIZE
;
; The block also holds a doubleword for each SFB, which only the kernel can
; reach, with a bit for each session that may use it (see r3_sfhok).
;
	mov	es:[r3_sfbtab],di
	mov	ax,es:[cfg_counts+2]	; AX = # of SFBs
	shl	ax,1
	shl	ax,1			; AX = their doublewords' length
	push	ax
	add	di,ax
	sub	si,si			; SI:DI = the block's length
	mov	bx,MCBOWNER_SYSTEM
	mov	ax,CPU_ALLOC SHL 8	; AL = 0 (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = selector
	pop	cx			; CX = their doublewords' length
	jnc	is0
	sub	ax,ax
	mov	es:[prog_user],al	; no room, so programs run at ring 0
	jmp	short is1
is0:	mov	es:[sfb_hook],offset r3_sfbfree
	mov	di,es:[r3_sfbtab]
	push	ax
	push	es
	mov	es,ax
	ASSUME	ES:NOTHING
	shr	cx,1
	sub	ax,ax
	cld
	rep	stosw			; no session has any SFB yet
	pop	es
	ASSUME	ES:DOS
	pop	ax
is1:	mov	es:[r3_stseg],ax
	pop	dx
	pop	ax
is9:	jmp	init_fpu
ENDPROC	init_sess
	ASSUME	ES:NOTHING

	ASSUME	DS:NOTHING

DOS	ends

	end
