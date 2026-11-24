;
; BASIC-DOS Pipe Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Every open of "PIPE$" makes a new pipe, which COMMAND shares between the
; programs in a pipeline.  An open of "PIPE$:name" (the name's first 8
; characters, in any case) instead joins the named pipe that every other
; open of that name has joined, so that programs in different sessions can
; talk to each other: each open has its own buffer, a write goes to every
; other open's buffer that has room for all of it (none, if it's the only
; one), and IOCTL_INSTATUS returns the number of bytes waiting (which BASIC's
; EOF and LOC use).  Contexts are owned by the system, since a pipe outlives
; the program that opened it.
;
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	PIPE
PIPE	DDH	<offset DEV:ddpipe_end+16,,DDATTR_CHAR,offset ddpipe_init,-1,2020202445504950h>

	DEFLBL	CMDTBL,word
	dw	ddpipe_none,  ddpipe_none,  ddpipe_none,  ddpipe_ioctl	; 0-3
	dw	ddpipe_read,  ddpipe_none,  ddpipe_none,  ddpipe_none	; 4-7
	dw	ddpipe_write, ddpipe_none,  ddpipe_none,  ddpipe_none	; 8-11
	dw	ddpipe_none,  ddpipe_open,  ddpipe_close		; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFWORD	pipe_list,0	; first named pipe context, if any

CONTEXT		struc
CT_STATUS	db	?	; 00h: context status bits (CTSTAT_*)
CT_SIG		db	?	; 01h: (holds SIG_CT in DEBUG builds)
CT_HEAD		dw	?	; 02h: offset of next byte to read
CT_TAIL		dw	?	; 04h: offset of next byte to write
CT_DATA		db    128 dup(?); 06h: data buffer (a power of two)
CT_NEXT		dw	?	; 86h: next named pipe context, if any
CT_NAME		db	8 dup(?); 88h: name (upper-case, padded with spaces)
CONTEXT		ends
SIG_CT		equ	'P'

CTSTAT_EWAIT	equ	01h	; set on empty-wait condition
CTSTAT_FWAIT	equ	02h	; set on full-wait condition
CTSTAT_TRUNC	equ	04h	; set when pipe is being "truncated"
CTSTAT_DONE	equ	08h	; set when the reader is done (see ddpipe_read)
CTSTAT_NAMED	equ	10h	; set for a named pipe (see ddpipe_open)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_req,far
	mov	di,bx			; ES:DI -> DDP
	mov	bl,es:[di].DDP_CMD
	cmp	bl,CMDTBL_SIZE
	jb	ddq1
	mov	bl,0
ddq1:	mov	bh,0
	add	bx,bx
	mov	ds,es:[di].DDP_CONTEXT	; DS = device context (if any)
	call	CMDTBL[bx]
	ret
ENDPROC	ddpipe_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_read
;
; A zero-length read means that the reader is done (eg, the session reading
; the pipe has ended), so from then on, writes fail instead of waiting for
; room that will never be made (see push_data).
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = device context
;
; Outputs:
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_read
	ASSERT	STRUCT,ds:[0],CT
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	ddr8

	call	pull_data
	jnc	ddpipe_done_jump
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_RDFAULT
	ret

ddr8:	or	ds:[CT_STATUS],CTSTAT_DONE
	test	ds:[CT_STATUS],CTSTAT_FWAIT
	jz	ddpipe_done_jump		; no writer is waiting for room
	and	ds:[CT_STATUS],NOT CTSTAT_FWAIT
	call	endwait_data

	jmp	short ddpipe_done_jump
ENDPROC	ddpipe_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_write
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = device context
;
; Outputs:
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_write
	ASSERT	STRUCT,ds:[0],CT
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	ddw8
	test	ds:[CT_STATUS],CTSTAT_NAMED
	jnz	ddw10

	call	push_data
	jnc	ddpipe_done_jump
ddw7:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	ret

ddw8:	or	ds:[CT_STATUS],CTSTAT_TRUNC

	test	ds:[CT_STATUS],CTSTAT_EWAIT
	jz	ddpipe_done_jump
	and	ds:[CT_STATUS],NOT CTSTAT_EWAIT
	call	endwait_data

	DEFLBL	ddpipe_done_jump,near
	jmp	ddpipe_done
;
; A write to a named pipe goes to the buffer of every other context with
; the same name (ES) that has room for all of it.  Hold the session lock
; through each copy and wakeup so no recipient can close and have its
; context reused before ENDWAIT.  A write no buffer could ever hold fails.
;
ddw10:	cmp	cx,size CT_DATA		; can a buffer hold the write?
	jae	ddw7			; no
	push	es
	push	di
	mov	bp,ds			; BP = our context
	lds	si,es:[di].DDPRW_ADDR	; DS:SI -> data
	DOSUTIL	LOCK
	mov	ax,cs:[pipe_list]
ddw11:	test	ax,ax			; any more contexts?
	jz	ddw14			; no
	mov	es,ax			; ES = next context
	cmp	ax,bp			; is it ours?
	je	ddw13			; yes
	push	cx
	push	si
	push	ds
	mov	ds,bp
	mov	si,offset CT_NAME
	mov	di,si
	mov	cl,size CT_NAME SHR 1	; CH is zero for an accepted length
	repe	cmpsw			; does its name match?
	pop	ds
	pop	si
	pop	cx
	jne	ddw13			; no
	mov	ax,es:[CT_HEAD]
	mov	bx,es:[CT_TAIL]
	sub	ax,bx
	dec	ax
	and	al,size CT_DATA - 1	; AL = room in its buffer
	cmp	al,cl			; is there room for the write?
	jb	ddw13			; no
	push	cx
	push	si
ddw12:	lodsb
	mov	es:[CT_DATA][bx],al
	inc	bx
	and	bx,size CT_DATA - 1
	loop	ddw12
	pop	si
	pop	cx
	mov	es:[CT_TAIL],bx
	test	es:[CT_STATUS],CTSTAT_EWAIT
	jz	ddw13
	and	es:[CT_STATUS],NOT CTSTAT_EWAIT
	mov	dx,es			; DX = recipient's wait ID
	mov	ah,DOS_UTL_ENDWAIT
	call	wait_id
ddw13:	mov	ax,es:[CT_NEXT]
	jmp	ddw11
ddw14:	DOSUTIL	UNLOCK
	pop	di
	pop	es
	mov	es:[di].DDPRW_LENGTH,0	; it's all written
	jmp	ddpipe_done		; DEBUG adds code in ddpipe_open
ENDPROC	ddpipe_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_open
;
; Inputs:
;	ES:DI -> DDP
;	[DDP].DDP_PTR -> context descriptor (eg, "PIPE$" or "PIPE$:name")
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_open
	push	di
	mov	di,size CONTEXT
	sub	si,si			; SI:DI = length
	mov	bx,MCBOWNER_SYSTEM
	mov	ax,CPU_ALLOC SHL 8	; AL = 0 (a GDT data selector)
	call	far ptr DDINT_CPU	; AX = context
	pop	di
	jnc	ddo1			; allocation succeeded
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + ERR_NOMEMORY
	ret

ddo1:	push	es
	push	di
	lds	si,es:[di].DDP_PTR	; DS:SI -> descriptor
	mov	es,ax
	ASSUME	ES:NOTHING
	DBGINIT	STRUCT,es:[0],CT

	sub	ax,ax
	mov	es:[CT_STATUS],al
	mov	es:[CT_HEAD],ax
	mov	es:[CT_TAIL],ax
;
; If a name follows "PIPE$:", copy it to CT_NAME, and add the context to
; the list of named pipes.
;
	cmp	byte ptr [si+5],':'	; a colon after "PIPE$"?
	jne	ddo7			; no
	cmp	[si+6],al		; and a name after the colon?
	je	ddo7			; no
	add	si,6
	or	es:[CT_STATUS],CTSTAT_NAMED
	mov	di,offset CT_NAME
	mov	cx,size CT_NAME
ddo2:	lodsb
	test	al,al			; end of the name?
	jz	ddo4			; yes
	cmp	al,'a'			; lower-case letter?
	jb	ddo3			; no
	cmp	al,'z'
	ja	ddo3			; no
	sub	al,'a'-'A'
ddo3:	stosb
	loop	ddo2
	jmp	short ddo5
ddo4:	mov	al,' '
	rep	stosb			; pad the name with spaces
ddo5:	mov	ds,cs:[0].DDH_DATA
	cli
	mov	ax,es
	xchg	ax,ds:[pipe_list]
	mov	es:[CT_NEXT],ax
	sti
ddo7:	mov	ax,es			; AX = context
	pop	di
	pop	es
	mov	es:[di].DDP_CONTEXT,ax
	DEFLBL	ddpipe_done,near
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddpipe_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_close
;
; A named pipe's context is removed from the list first.  CPU$ reloads DS
; and ES, so neither can hold the context when it's freed.
;
; Inputs:
;	ES:DI -> DDP
;	DS = device context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, DS
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_close
	mov	cx,ds
	jcxz	ddc9			; no context
	push	es
	test	ds:[CT_STATUS],CTSTAT_NAMED
	mov	dx,ds:[CT_NEXT]		; DX = next context (if named)
	mov	ax,cs:[0].DDH_DATA
	mov	ds,ax
	mov	es,ax
	jz	ddc3			; not named
	mov	bx,offset pipe_list	; DS:BX -> first link
	cli
ddc1:	cmp	[bx],cx			; does it link to our context?
	je	ddc2			; yes
	mov	ds,[bx]
	mov	bx,offset CT_NEXT
	jmp	ddc1
ddc2:	mov	[bx],dx			; unlink our context
	sti
	mov	ds,ax
ddc3:	mov	dx,-1			; DX = -1 means CX is a segment
	mov	ah,CPU_FREE
	call	far ptr DDINT_CPU	; free the context
	pop	es
ddc9:	jmp	short ddpipe_done
ENDPROC	ddpipe_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_ioctl
;
; Only named pipes support IOCTL_INSTATUS, which returns the number of bytes
; waiting; when there are none, give other sessions a turn and count again,
; since the caller is likely waiting (eg, BASIC's EOF or LOC in a loop).
; Other pipes don't, so that EOF still reads a pipeline's input.
;
; Inputs:
;	ES:DI -> DDP
;	DS = device context
;
; Outputs:
;	DDP_CONTEXT = # bytes waiting
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_ioctl
	test	ds:[CT_STATUS],CTSTAT_NAMED
	jz	ddpipe_none
	cmp	es:[di].DDP_CODE,IOCTL_INSTATUS
	jne	ddpipe_none
	call	pipe_count
	jnz	ddi9
	DOSUTIL	YIELD
	call	pipe_count
ddi9:	mov	es:[di].DDP_CONTEXT,ax
	jmp	short ddpipe_done
ENDPROC	ddpipe_ioctl

;
; Return the number of bytes waiting in AX, with ZF set if empty.
;
DEFPROC	pipe_count
	mov	ax,ds:[CT_TAIL]
	sub	ax,ds:[CT_HEAD]
	and	ax,size CT_DATA - 1
	ret
ENDPROC	pipe_count

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_none (handler for unimplemented functions)
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_none
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	stc
	ret
ENDPROC	ddpipe_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_data
;
; Like a pipe read on UNIX, a read waits only until some data is available,
; and then returns as much as the request can hold; otherwise, a reader such
; as MORE, which requests a buffer at a time, would display nothing until the
; writer had filled that entire buffer.
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = original request length
;	DS = device context
;
; Outputs:
;	Returns after some data has been read, or the pipe has been truncated
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_data
	cli
pl0:	mov	bx,ds:[CT_HEAD]
	cmp	bx,ds:[CT_TAIL]
	jne	pl1
;
; There's no data, so if we've already read some, return it; otherwise,
; issue WAIT and try again when it returns.
;
	cmp	cx,es:[di].DDPRW_LENGTH	; have we read anything yet?
	ja	pl8			; yes (and carry is clear)
	test	ds:[CT_STATUS],CTSTAT_TRUNC
	jnz	pl9
	ASSERT	Z,<test ds:[CT_STATUS],CTSTAT_EWAIT OR CTSTAT_FWAIT>
	or	ds:[CT_STATUS],CTSTAT_EWAIT
	call	wait_data
;
; If the WAIT was ABORT'ed (eg, CTRL-ALT-DEL), the writer never cleared our
; wait flag, so we clear it ourselves; and if the WAIT failed, bail.
;
	pushf
	and	ds:[CT_STATUS],NOT CTSTAT_EWAIT
	popf
	jnc	pl0
pl8:	sti
	ret

pl1:	mov	al,ds:[CT_DATA][bx]	; AL = data byte
	inc	bx
	and	bx,size CT_DATA - 1	; wrap the head at the end of the ring
	mov	ds:[CT_HEAD],bx
;
; We just made some room.  If CTSTAT_FWAIT is set, clear it and issue ENDWAIT.
;
	test	ds:[CT_STATUS],CTSTAT_FWAIT
	jz	pl3
	and	ds:[CT_STATUS],NOT CTSTAT_FWAIT
	call	endwait_data
pl3:	sti
	push	ds
	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	mov	[bx],al
	inc	bx
	mov	es:[di].DDPRW_ADDR._OFF,bx
	pop	ds
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	pull_data		; no
	clc
pl9:	ret
ENDPROC	pull_data

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; push_data
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = device context
;
; Outputs:
;	Carry clear if request satisfied, set if not (eg, the reader is done)
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_data
	cli
ps0:	test	ds:[CT_STATUS],CTSTAT_DONE
	stc
	jnz	ps9			; the reader is done
	mov	bx,ds:[CT_TAIL]
	mov	dx,bx
	inc	dx
	and	dx,size CT_DATA - 1	; wrap the tail at the end of the ring
	cmp	dx,ds:[CT_HEAD]
	jne	ps2
;
; The buffer is full, so issue WAIT and try again when it returns.
;
	ASSERT	Z,<test ds:[CT_STATUS],CTSTAT_EWAIT OR CTSTAT_FWAIT>
	or	ds:[CT_STATUS],CTSTAT_FWAIT
	call	wait_data
;
; If the WAIT was ABORT'ed (eg, CTRL-ALT-DEL), the reader never cleared our
; wait flag, so we clear it ourselves; and if the WAIT failed, bail.
;
	pushf
	and	ds:[CT_STATUS],NOT CTSTAT_FWAIT
	popf
	jnc	ps0
ps9:	sti
	ret
ps2:	mov	ds:[CT_TAIL],dx
	push	ds
	push	bx
	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	mov	al,[bx]
	inc	bx
	mov	es:[di].DDPRW_ADDR._OFF,bx
	pop	bx
	pop	ds
	mov	ds:[CT_DATA][bx],al	; AL = data byte
;
; We just added some data.  If CTSTAT_EWAIT is set, clear it and issue ENDWAIT.
;
	test	ds:[CT_STATUS],CTSTAT_EWAIT
	jz	ps3
	and	ds:[CT_STATUS],NOT CTSTAT_EWAIT
	call	endwait_data
ps3:	sti
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	push_data		; no
	clc
	ret
ENDPROC	push_data

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; wait_data
;
; Inputs:
;	DS = device context
;
; Outputs:
;	Carry set if the wait failed (eg, ABORT or CTRLC)
;
; Modifies:
;	AX, DX
;
DEFPROC	wait_data
	mov	ah,DOS_UTL_WAIT
	DEFLBL	wait_call,near
	mov	dx,ds
	DEFLBL	wait_id,near		; (DX = ID; see ddpipe_write)
	push	di
	sub	di,di
	DOSUTIL	ah
	pop	di
	ret
ENDPROC	wait_data

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; endwait_data
;
; Inputs:
;	DS = device context
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX
;
DEFPROC	endwait_data
	mov	ah,DOS_UTL_ENDWAIT
	jmp	wait_call
ENDPROC	endwait_data

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddpipe_init,far
	mov	es:[bx].DDPI_END._OFF,offset ddpipe_init
	mov	ds,cs:[0].DDH_DATA
	mov	ds:[0].DDH_REQUEST,offset DEV:ddpipe_req
	ret
ENDPROC	ddpipe_init

CODE	ends

DATA	segment para public 'DATA'

ddpipe_end	db	16 dup(0)

DATA	ends

	end
