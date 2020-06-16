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
	EXTERNS	<scb_active>,word
	EXTERNS	<scb_table>,dword
	EXTERNS	<dos_exit>,near

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_load
;
; Loads a program into an available SCB
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
	int 3
	call	scb_lock
	jnc	sl1
	jmp	sl9

sl1:	push	ax			; save prev SCB

	mov	bx,1000h		; alloc 64K
	mov	ah,DOS_MEM_ALLOC
	int	21h			; returns a new segment in AX
	jnc	sl2
	mov	ah,DOS_MEM_ALLOC	; try again with whatever the max is
	int	21h
	jc	sl8a			; no luck

sl2:	mov	cl,4
	mov	si,bx
	shl	si,cl			; SI = size of memory in bytes
	xchg	di,ax			; DI = segment

	push	es
	pop	ds			; DS:DX -> name of executable
	ASSUME	DS:NOTHING
	mov	ax,(DOS_HDL_OPEN SHL 8) OR MODE_ACC_BOTH
	int	21h			; returns handle in AX
	jc	sl8a

	xchg	bx,ax			; BX = file handle
	sub	cx,cx
	sub	dx,dx
	mov	ax,(DOS_HDL_SEEK SHL 8) OR SEEK_END
	int	21h			; returns file size in CX:DX
	jc	sl8a

	test	cx,cx			; more than 64K?
	jnz	sl7			; yes
	cmp	dx,si			; larger than the memory we allocated?
	ja	sl7			; yes

	mov	dx,di			; DX = segment for new PSP
	mov	ah,DOS_PSP_CREATE
	int	21h

	mov	ds,dx			; DS = PSP segment
	mov	dx,size PSP		; DS:DX -> memory after PSP
	mov	ah,DOS_HDL_READ		; BX = file handle, CX = # bytes
	int	21h
	jc	sl8a
	cmp	ax,cx			; does # bytes match the file size?
	jne	sl8a			; no

	mov	ah,DOS_HDL_CLOSE
	int	21h			; close the file
	jnc	sl6

sl8a:	mov	es,di
	mov	ah,DOS_MEM_FREE
	int	21h
	jmp	short sl8

sl6:	mov	bx,cx			; size of program file
	add	bx,15
	mov	cl,4
	shr	bx,cl			; BX = size of program in paras
	add	bx,110h			; add PSP + 4Kb
	push	ds
	pop	es
	mov	ah,DOS_MEM_REALLOC	; resize the memory block
	int	21h

	mov	bx,ds			; and of course, this PSP function
	mov	ah,DOS_PSP_SET		; wants the segment in BX, not DX....
	int	21h			; active PSP updated

	push	ds
	pop	es
	ASSUME	ES:NOTHING
;
; Create an initial REG_FRAME, the top of which should be at ES:DI
;
	std
	mov	dx,ds
	sub	ax,ax
	stosw				; store a zero at the top of the stack
	mov	ax,FL_INTS
	stosw				; REG_FL
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
	xchg	ax,dx
	stosw				; REG_BP
	cld

	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	bx,[scb_active]
	mov	[bx].SCB_STACK.off,di
	mov	[bx].SCB_STACK.seg,dx
	or	[bx].SCB_STATUS,SCSTAT_READY
	jmp	short sl8

sl7:	mov	ax,ERR_NOMEM
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
;	On success, carry clear, AX = previous SCB, BX = current SCB
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
	jb	gs9
	mov	bx,ax
	inc	[scb_locked]
	xchg	[scb_active],ax
gs9:	ret
ENDPROC	scb_lock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_unlock
;
; Update current SCB and lock state
;
; Inputs:
;	BX = SCB
;
; Modifies:
;	None
;
DEFPROC	scb_unlock,DOS
	mov	[scb_active],bx
	dec	[scb_locked]
	ret
ENDPROC	scb_unlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_start
;
; Start the specified SCB
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	scb_start,DOS
	int 3
	call	scb_lock
	jc	ss9
	mov	ss,[bx].SCB_STACK.seg
	mov	sp,[bx].SCB_STACK.off
	call	scb_unlock
	jmp	dos_exit
ss9:	ret
ENDPROC	scb_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_stop
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
;
; Looks for an SCB that's ready to run and starts it running.
;
DEFPROC	scb_yield,DOS
sr0:	mov	bx,[scb_table].off
sr1:	cmp	bx,[scb_table].seg
	je	sr9
	test	[bx].SCB_STATUS,SCSTAT_READY
	jz	sr2
;
; The easiest way to switch SCBs is to copy the new SCB's stack frame to the
; current stack frame; then all we do is return exactly the same way we arrived.
;

sr2:	add	bx,size SCB
	jmp	sr1
sr9:	int 3
	hlt
	jmp	sr0
ENDPROC	scb_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_block
;
; Inputs:
;	DX:DI == wait ID
;
; Outputs:
;	None
;
DEFPROC	scb_block,DOS
	mov	bx,[scb_active]
	mov	[bx].SCB_WAITID.off,di
	mov	[bx].SCB_WAITID.seg,dx
	ret
ENDPROC	scb_block

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_unblock
;
; Inputs:
;	DX:DI == wait ID
;
; Outputs:
;	None
;
DEFPROC	scb_unblock,DOS
	mov	bx,[scb_table].off
	ret
ENDPROC	scb_unblock

DOS	ends

	end
