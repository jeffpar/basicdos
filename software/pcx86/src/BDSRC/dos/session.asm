;
; BASIC-DOS Session Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<scb_locked>,byte
	EXTERNS	<scb_active,psp_active>,word
	EXTERNS	<scb_table>,dword
	EXTERNS	<dos_exit>,near

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_load
;
; Loads a program into the specified SCB
;
; Inputs:
;	CL = SCB #
;	ES:DX -> name of executable
;
; Outputs:
;	Carry set if error, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, DI, DS, ES
;
DEFPROC	scb_load,DOS
	call	scb_lock
	jnc	sl0
	jmp	sl9

sl0:	push	ax			; save previous SCB
	mov	bx,1000h		; alloc 64K
	mov	ah,DOS_MEM_ALLOC
	int	21h			; returns a new segment in AX
	jnc	sl2
	cmp	bx,11h			; is there a usable amount of memory?
	jb	sl1			; no
	mov	ah,DOS_MEM_ALLOC	; try again with max paras in BX
	int	21h
	jnc	sl2			; success
sl1:	jmp	sl8			; abort

sl2:	sub	bx,10h			; subtract paras for the PSP header
	mov	cl,4
	shl	bx,cl			; convert to bytes
	mov	si,bx			; SI = bytes for new PSP
	xchg	di,ax			; DI = segment for new PSP

	xchg	dx,di
	mov	ah,DOS_PSP_CREATE
	int	21h			; create new PSP at DX

	mov	bx,dx
	mov	ah,DOS_PSP_SET
	int	21h			; update current PSP using BX

	xchg	dx,di
	push	es
	pop	ds			; DS:DX -> name of executable
	ASSUME	DS:NOTHING
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h			; open the file
	jc	sle2a

	xchg	bx,ax			; BX = file handle
	sub	cx,cx
	sub	dx,dx
	mov	ax,(DOS_HDL_SEEK SHL 8) OR SEEK_END
	int	21h			; returns new file position in DX:AX
	jc	sle1a

	xchg	cx,ax			; file size now in DX:CX
	mov	ax,ERR_NOMEM
	test	dx,dx			; more than 64K?
	jnz	sle1			; yes
	cmp	cx,si			; larger than the memory we allocated?
	ja	sle1			; yes
	mov	si,cx			; no, SI is the new length

	sub	cx,cx
	sub	dx,dx
	mov	ax,(DOS_HDL_SEEK SHL 8) OR SEEK_BEG
	int	21h			; reset file position to beginning
	jc	sle1

	mov	cx,si			; CX = # bytes to read
	mov	ds,di			; DS = segment of new PSP
	mov	dx,size PSP		; DS:DX -> memory after PSP
	mov	ah,DOS_HDL_READ		; BX = file handle, CX = # bytes
	int	21h
sle1a:	jc	sle1

	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the file
sle2a:	jc	sle2

	mov	bx,cx			; size of program file
	add	bx,15
	mov	cl,4
	shr	bx,cl			; BX = size of program in paras
	add	bx,110h			; add PSP + 4Kb
	push	ds
	pop	es
	ASSUME	ES:NOTHING
	mov	ah,DOS_MEM_REALLOC	; resize the memory block
	int	21h
	jc	sle2
;
; Create an initial REG_FRAME at the top of the segment.
;
	mov	di,bx
	shl	di,cl			; ES:DI -> top of the segment
	dec	di
	dec	di			; ES:DI -> last word at top of segment
	std
	mov	dx,ds
	sub	ax,ax
	stosw				; store a zero at the top of the stack
	mov	ax,FL_INTS
	stosw				; REG_FL (with interrupts enabled)
	mov	ax,dx
	stosw				; REG_CS
	mov	ax,100h
	stosw				; REG_IP
	sub	ax,ax
	stosw				; REG_AX
	stosw				; REG_BX
	stosw				; REG_CX
	stosw				; REG_DX
	xchg	ax,dx
	stosw				; REG_DS
	xchg	ax,dx
	stosw				; REG_SI
	xchg	ax,dx
	stosw				; REG_ES
	xchg	ax,dx
	stosw				; REG_DI
	stosw				; REG_BP
	inc	di
	inc	di			; ES:DI -> REG_BP
	cld

	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	bx,[scb_active]
	ASSERT_STRUC [bx],SCB
	mov	[bx].SCB_STACK.off,di
	mov	[bx].SCB_STACK.seg,dx
	or	[bx].SCB_STATUS,SCSTAT_LOAD
	jmp	short sl8
;
; Error paths (eg, close the file handle, free the memory for the new PSP)
;
sle1:	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	ax
sle2:	push	ax
	mov	es,di
	mov	ah,DOS_MEM_FREE
	int	21h
	pop	ax
	push	cs
	pop	ds
	ASSUME	DS:DOS
	stc

sl8:	pop	bx			; recover previous SCB
	call	scb_unlock		; unlock

sl9:	ret
ENDPROC	scb_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_lock
;
; Activate and lock the specified SCB
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	On success, carry clear, AX -> previous SCB, BX -> current SCB
;	On failure, carry set
;
; Modifies:
;	AX, BX
;
DEFPROC	scb_lock,DOS
	mov	al,size SCB
	mul	cl
	add	ax,[scb_table].off
	cmp	ax,[scb_table].seg
	cmc
	jb	sk9
	mov	bx,ax
	test	[bx].SCB_STATUS,SCSTAT_INIT
	stc
	jz	sk9
	inc	[scb_locked]
	push	dx
	xchg	bx,[scb_active]		; BX -> previous SCB
	test	bx,bx
	jz	sk8
	ASSERT_STRUC [bx],SCB
	mov	dx,[psp_active]
	mov	[bx].SCB_CURPSP,dx
sk8:	xchg	bx,ax			; BX -> current SCB, AX -> previous SCB
	ASSERT_STRUC [bx],SCB
	mov	dx,[bx].SCB_CURPSP
	mov	[psp_active],dx
	pop	dx
sk9:	ret
ENDPROC	scb_lock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_unlock
;
; Restore the previous SCB and lock state
;
; Inputs:
;	BX -> previous SCB
;
; Modifies:
;	BX, DX
;
DEFPROC	scb_unlock,DOS
	push	bx
	xchg	bx,[scb_active]		; BX -> current SCB
	ASSERT_STRUC [bx],SCB
	mov	dx,[psp_active]
	mov	[bx].SCB_CURPSP,dx
	pop	bx			; BX -> previous SCB
	test	bx,bx
	jz	su9
	ASSERT_STRUC [bx],SCB
	mov	dx,[bx].SCB_CURPSP
	mov	[psp_active],dx
su9:	dec	[scb_locked]		; NOTE: does not affect carry
	ret
ENDPROC	scb_unlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_start
; util_start (AX = 1807h)
;
; Start the specified SCB
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on successc
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	scb_start,DOS
	call	scb_lock
	jc	sa9
	ASSERT_STRUC [bx],SCB
	mov	ss,[bx].SCB_STACK.seg
	mov	sp,[bx].SCB_STACK.off
	dec	[scb_locked]
	jmp	dos_exit
sa9:	ret
ENDPROC	scb_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_stop
; util_stop (AX = 1808h)
;
; Stop the specified SCB
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	scb_stop,DOS
	int 3
	ret
ENDPROC	scb_stop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_unload
; util_unload (AX = 1809h)
;
; Unload the specified SCB
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	scb_unload,DOS
	int 3
	ret
ENDPROC	scb_unload

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_yield
; util_yield (AX = 180Ah)
;
; Asynchronous interface to decide which SCB should run next.
;
; There are currently two conditions to consider:
;
;	1) A DOS_UTIL_YIELD request
;	2) A DOS_UTIL_WAIT request
;
; In the first case, we want to return if no other SCB is ready; this
; is important when we're called from an interrupt handler with the intention
; of switching, but there's nothing else to switch to yet.
;
; In the second case, we never return; at best, we will simply switch to the
; current SCB when its wait condition is satisified.
;
; Inputs:
;	AX = scb_active when called from DOS_UTIL_YIELD, zero otherwise
;
; Modifies:
;	BX, DX
;
DEFPROC	scb_yield,DOS
	test	ax,ax
	mov	bx,ax
	jnz	sy1
	mov	bx,[scb_active]
sy1:	add	bx,size SCB
	cmp	bx,[scb_table].seg
	jb	sy2
	mov	bx,[scb_table].off
sy2:	cmp	bx,ax			; have we looped back around to AX?
	je	sy9			; yes
	test	[bx].SCB_STATUS,SCSTAT_LOAD
	jz	sy1			; ignore SCB, nothing loaded in it
	ASSERT_STRUC [bx],SCB
	mov	dx,[bx].SCB_WAITID.off
	or	dx,[bx].SCB_WAITID.seg
	jnz	sy1
	jmp	scb_switch
sy9:	ret
ENDPROC	scb_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_switch
;
; Switch the specified SCB.
;
; Inputs:
;	BX -> SCB
;
DEFPROC	scb_switch,DOS
	cmp	bx,[scb_active]		; is this SCB already active?
	je	sw9			; yes
	mov	ax,bx
	xchg	bx,[scb_active]		; BX -> previous SCB
	test	bx,bx
	jz	sw8
	ASSERT_STRUC [bx],SCB
	mov	dx,[psp_active]
	mov	[bx].SCB_CURPSP,dx
sw8:	xchg	bx,ax			; BX -> current SCB, AX -> previous SCB
	ASSERT_STRUC [bx],SCB
	mov	dx,[bx].SCB_CURPSP
	mov	[psp_active],dx
	mov	ss,[bx].SCB_STACK.seg
	mov	sp,[bx].SCB_STACK.off
	jmp	dos_exit
sw9:	ret
ENDPROC	scb_switch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_wait
; util_wait (AX = 180Ch)
;
; Synchronous interface to mark current SCB as waiting for the specified ID.
;
; Inputs:
;	DX:DI == wait ID
;
; Outputs:
;	None
;
DEFPROC	scb_wait,DOS
	cli
	mov	bx,[scb_active]
	ASSERT_STRUC [bx],SCB
	mov	[bx].SCB_WAITID.off,di
	mov	[bx].SCB_WAITID.seg,dx
	sti
	sub	ax,ax
	jmp	scb_yield
ENDPROC	scb_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_endwait
; util_endwait (AX = 180Dh)
;
; Asynchronous interface to examine all SCBs for the specified ID and clear it.
;
; Inputs:
;	DX:DI == wait ID
;
; Outputs:
;	Carry clear if found, set if not
;
DEFPROC	scb_endwait,DOS
	cli
	mov	bx,[scb_table].off
se1:	ASSERT_STRUC [bx],SCB
	cmp	[bx].SCB_WAITID.off,di
	jne	se2
	cmp	[bx].SCB_WAITID.seg,dx
	jne	se2
	mov	[bx].SCB_WAITID.off,0
	mov	[bx].SCB_WAITID.seg,0
	jmp	short se9
se2:	add	bx,size SCB
	cmp	bx,[scb_table].seg
	jb	se1
	stc
se9:	sti
	ret
ENDPROC	scb_endwait

DOS	ends

	end
