;
; BASIC-DOS Logical (CON) I/O Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	CON
CON	DDH	<offset DEV:ddend+16,,DDATTR_STDIN+DDATTR_STDOUT+DDATTR_OPEN+DDATTR_CHAR,offset ddinit,-1,20202020204E4F43h>

	DEFLBL	CMDTBL,word
	dw	ddcon_none, ddcon_none, ddcon_none, ddcon_none	; 0-3
	dw	ddcon_none, ddcon_none, ddcon_none, ddcon_none	; 4-7
	dw	ddcon_write, ddcon_none, ddcon_none, ddcon_none	; 8-11
	dw	ddcon_none, ddcon_open, ddcon_close		; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	CON_LIMITS,word
	dw	4,25, 16,80	; mirrors sysinit's CFG_CONSOLE
	dw	0,24, 0,79

	DEFWORD	frame_seg,0
	DEFWORD	syscon,0	; initialized to the system CONSOLE context

context		struc
buf_x		db	?
buf_y		db	?
buf_cx		db	?
buf_cy		db	?
buf_addr	dd	?
cur_x		db	?
cur_y		db	?
context		ends

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddreq,far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	ds
	mov	di,bx			; ES:DI -> DDP
	mov	bl,es:[di].DDP_CMD
	cmp	bl,CMDTBL_SIZE
	jae	ddi9
	push	cs
	pop	ds
	ASSUME	DS:CODE
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
ddi8:	pop	ds
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ddi9:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	jmp	ddi8
ENDPROC	ddreq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_write
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_write
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	ddw9
	lds	si,es:[di].DDPRW_ADDR
	mov	dx,es:[di].DDP_CONTEXT
	test	dx,dx
	jnz	ddw2
ddw1:	lodsb
	call	ddcon_writechar
	loop	ddw1
	jmp	short ddw9
ddw2:	push	es
	mov	es,dx
dw2a:	lodsb
	call	ddcon_writecontext
	loop	dw2a
	pop	es
ddw9:	ret
ENDPROC	ddcon_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_open
;
; Inputs:
;	ES:DI -> DDP
;	[DDP].DDP_PARMS -> context descriptor (eg, "CON:25,80,0,0")
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_open
	push	di
	push	es
	push	ds
	lds	si,es:[di].DDP_PARMS
	ASSUME	DS:NOTHING
	add	si,4			; DS:SI -> parms
	push	cs
	pop	es
	mov	di,offset CON_LIMITS	; ES:DI -> limits
	mov	ax,DOS_UTIL_ATOI
	int	21h			; updates SI, DI, and AX
	mov	ch,al			; CH = rows
	mov	ax,DOS_UTIL_ATOI
	int	21h
	mov	cl,al			; CL = columns
	mov	ax,DOS_UTIL_ATOI
	int	21h
	mov	dh,al			; DH = starting row
	mov	ax,DOS_UTIL_ATOI
	int	21h
	mov	dl,al			; DL = starting column
	pop	ds
	ASSUME	DS:CODE
	pop	es
	pop	di			; ES:DI -> DDP (done with DDP_PARMS)
	mov	bx,(size context + 15) SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	INT_DOSFUNC
	jnc	ddo8
;
; What's up with the complete disconnect between device driver error codes
; and DOS error codes?
;
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_GENFAIL
	jmp	short ddo9

ddo8:	mov	ds,ax
	ASSUME	DS:NOTHING
	mov	word ptr ds:[buf_x],dx
	mov	word ptr ds:[buf_cx],cx
	mov	word ptr ds:[buf_addr].off,0
	mov	ax,[frame_seg]
	mov	word ptr ds:[buf_addr].seg,ax
	push	es
	sub	ax,ax
	mov	es,ax
	ASSUME	ES:BIOS
	mov	ax,[CURSOR_POSN]
	mov	word ptr ds:[cur_x],ax
	pop	es
	ASSUME	ES:NOTHING
	mov	es:[di].DDP_CONTEXT,ds
	cmp	[syscon],0		; do we have a system CONSOLE yet?
	jne	ddo9			; yes
	mov	[syscon],ds		; no, update the system CONSOLE context
ddo9:	ret
ENDPROC	ddcon_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_close
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_close
	mov	ax,es:[di].DDP_CONTEXT
	test	ax,ax
	jz	ddc9
	cmp	ax,[syscon]		; is this the system CONSOLE context?
	jne	ddc1			; no
	mov	[syscon],0		; yes, so zap that as well
ddc1:	push	es
	mov	es,ax
	mov	ah,DOS_MEM_FREE
	int	INT_DOSFUNC
	pop	es
ddc9:	ret
ENDPROC	ddcon_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_none (handler for unimplemented functions)
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_none
	stc
	ret
ENDPROC	ddcon_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_int29 (handler for INT_FASTCON: fast console I/O)
;
; Inputs:
;	AL = character to display
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_int29,far
	push	dx
	mov	dx,[syscon]
	test	dx,dx
	jnz	ddfc1
	call	ddcon_writechar
	jmp	short ddfc9
ddfc1:	push	es
	mov	es,dx
	call	ddcon_writecontext
	pop	es
ddfc9:	pop	dx
	iret
ENDPROC	ddcon_int29

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_writechar
;
; Inputs:
;	AL = character to display
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_writechar
	push	ax
	push	bx
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	pop	bx
	pop	ax
	ret
ENDPROC	ddcon_writechar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_writecontext
;
; Inputs:
;	AL = character to display
;	ES -> CONSOLE context structure
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	ddcon_writecontext
	jmp	ddcon_writechar		; cheating for now
ENDPROC	ddcon_writecontext

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
DEFPROC	ddinit,far
	push	ax
	push	dx
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS

	mov	ax,[EQUIP_FLAG]		; AX = EQUIP_FLAG
	mov	es:[bx].DDPI_END.off,offset ddinit
	mov	cs:[0].DDH_REQUEST,offset DEV:ddreq
;
; Determine what kind of video console we're dealing with (MONO or COLOR)
; and what the frame buffer segment is.
;
	mov	dx,0B000h
	and	ax,EQ_VIDEO_MODE
	cmp	ax,EQ_VIDEO_MONO
	je	ddin1
	mov	dx,0B800h
ddin1:	mov	[frame_seg],dx
;
; Install an INT 29h ("FAST PUTCHAR") handler; I think traditionally DOS
; installed its own handler, but that's really our responsibility, especially
; since we eventually want all INT 29h I/O to go through our system console.
;
	mov	ds:[INT_FASTCON * 4].off,offset ddcon_int29
	mov	ds:[INT_FASTCON * 4].seg,cs

	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	ax
	ret
ENDPROC	ddinit

CODE	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
