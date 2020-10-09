;
; BASIC-DOS Pipe Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dev.inc
	include	dosapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	PIPE
PIPE	DDH	<offset DEV:ddpipe_end+16,,DDATTR_CHAR,offset ddpipe_init,-1,2020202445504950h>

	DEFLBL	CMDTBL,word
	dw	ddpipe_none,  ddpipe_none,  ddpipe_none,  ddpipe_none	; 0-3
	dw	ddpipe_read,  ddpipe_none,  ddpipe_none,  ddpipe_none	; 4-7
	dw	ddpipe_write, ddpipe_none,  ddpipe_none,  ddpipe_none	; 8-11
	dw	ddpipe_none,  ddpipe_open,  ddpipe_close		; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

CONTEXT		struc
CT_STATUS	db	?	; 00h: context status bits (CTSTAT_*)
CT_SIG		db	?	; 01h: (holds SIG_CT in DEBUG builds)
CT_HEAD		dw	?	; 02h: offset of next byte to read
CT_TAIL		dw	?	; 04h: offset of next byte to write
CT_DATA		db    128 dup(?); 06h: data buffer
CONTEXT		ends
SIG_CT		equ	'P'

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
ddq1:	push	cs
	pop	ds
	ASSUME	DS:CODE
	mov	bh,0
	add	bx,bx
	mov	ds,es:[di].DDP_CONTEXT	; DS = device context
	call	CMDTBL[bx]
	ret
ENDPROC	ddpipe_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_read
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
	jcxz	ddr9

ddr2:	call	pull_data
	jnc	ddr9
;
; For READ requests that cannot be satisifed, we add this packet to an
; internal chain of "reading" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	call	add_packet
	jmp	ddr2			; when this returns, try reading again

ddr9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
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
	jcxz	ddw9

ddw2:	call	push_data
	jnc	ddw9
;
; For WRITE requests that cannot be satisifed, we add this packet to an
; internal chain of "writing" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	call	add_packet
	jmp	ddw2			; when this returns, try writing again

ddw9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddpipe_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_open
;
; Inputs:
;	ES:DI -> DDP
;	[DDP].DDP_PTR -> context descriptor (eg, "PIPE$")
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_open
	mov	bx,(size CONTEXT + 15) SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	INT_DOSFUNC
	jc	ddo8

	mov	ds,ax
	ASSUME	DS:NOTHING
	DBGINIT	STRUCT,ds:[0],CT

	sub	ax,ax
	mov	ds:[CT_HEAD],ax
	mov	ds:[CT_TAIL],ax
	jmp	short ddo9
;
; At the moment, the only possible error is a failure to allocate memory.
;
ddo8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_GENFAIL
	ret

ddo9:	mov	es:[di].DDP_CONTEXT,ds
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddpipe_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_close
;
; Inputs:
;	ES:DI -> DDP
;	DS = device context
;
; Outputs:
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_close
	mov	cx,ds
	jcxz	ddc9			; no context
	push	es
	mov	es,cx
	mov	ah,DOS_MEM_FREE
	int	INT_DOSFUNC
	pop	es
ddc9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddpipe_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddpipe_none (handler for unimplemented functions)
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddpipe_none
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	stc
	ret
ENDPROC	ddpipe_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_packet
;
; The WAIT condition will be satisfied when enough data is received (for
; a READ packet) or when the buffer is no longer full (for a WRITE packet).
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	add_packet
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	DOSUTIL	WAIT
	ret
ENDPROC	add_packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_data
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = device context
;
; Outputs:
;	Carry clear if request satisfied, set if not
;
; Modifies:
;	AX, BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_data
pl1:	mov	bx,ds:[CT_HEAD]
	cmp	bx,ds:[CT_TAIL]
	stc
	je	pl9			; buffer empty
	mov	al,ds:[CT_DATA][bx]	; AL = data byte
	inc	bx
	cmp	bx,size CT_DATA
	jne	pl2
	sub	bx,bx
pl2:	mov	ds:[CT_HEAD],bx
	push	ds
	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	mov	[bx],al
	inc	bx
	mov	es:[di].DDPRW_ADDR.OFF,bx
	pop	ds
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	pl1			; no
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
;	Carry clear if request satisfied, set if not
;
; Modifies:
;	AX, BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_data
ps1:	mov	bx,ds:[CT_TAIL]
	mov	dx,bx
	inc	dx
	cmp	dx,size CT_DATA
	jne	ps2
	sub	dx,dx
ps2:	cmp	dx,ds:[CT_HEAD]
	stc
	je	ps9			; buffer full
	mov	ds:[CT_TAIL],dx
	push	ds
	push	bx
	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	mov	al,[bx]
	inc	bx
	mov	es:[di].DDPRW_ADDR.OFF,bx
	pop	bx
	pop	ds
	mov	ds:[CT_DATA][bx],al	; AL = data byte
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	ps1			; no
	clc
ps9:	ret
ENDPROC	push_data

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
	mov	es:[bx].DDPI_END.OFF,offset ddpipe_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddpipe_req
	ret
ENDPROC	ddpipe_init

CODE	ends

DATA	segment para public 'DATA'

ddpipe_end	db	16 dup(0)

DATA	ends

	end
