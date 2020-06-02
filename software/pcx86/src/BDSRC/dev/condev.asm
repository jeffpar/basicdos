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
CON	DDH	<offset DEV:ddend+16,,DDATTR_STDIN+DDATTR_STDOUT+DDATTR_OPEN+DDATTR_CHAR,offset ddreq,offset ddinit,20202020204E4F43h>

	DEFPTR	ddpkt		; last request packet address
	DEFLBL	CMDTBL,word
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none	; 0-3
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none	; 4-7
	dw	ddcmd_write, ddcmd_none, ddcmd_none, ddcmd_none	; 8-11
	dw	ddcmd_none, ddcmd_open, ddcmd_close, ddcmd_none	; 12-15
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none	; 16-19
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	CON_LIMITS,word
	dw	4,25, 16,80	; mirrors what we put in sysinit's CFG_CONSOLE
	dw	0,24, 0,79

	DEFWORD	frame_seg,0

context		struc
buf_x		db	?
buf_y		db	?
buf_cx		db	?
buf_cy		db	?
buf_addr	dd	?
cur_x		db	?
cur_y		db	?
context		ends

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

DEFPROC	ddreq,far
	mov	[ddpkt].off,bx
	mov	[ddpkt].seg,es
	ret
ENDPROC	ddreq

DEFPROC	ddint,far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	ds
	push	es
	les	di,[ddpkt]
	mov	bl,es:[di].DDP_CMD
	cmp	bl,CMDTBL_SIZE
	jae	ddi8
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
	jmp	short ddi9
ddi8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
ddi9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	ddint

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_write
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
DEFPROC	ddcmd_write
	mov	cx,es:[di].DDPRW_COUNT
	lds	si,es:[di].DDPRW_ADDR
	push	es
	mov	es,es:[di].DDP_CONTEXT
	jcxz	ddw9

ddw1:	lodsb
	;
	; Cheating for now...
	;
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	loop	ddw1

ddw9:	pop	es
	ret
ENDPROC	ddcmd_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_open
;
; Inputs:
;	ES:DI -> DDP
;	[DDP].DDP_PARMS -> context descriptor (eg, "CON:25,80,0,0")
;
; Outputs:
;
DEFPROC	ddcmd_open
	ASSUME	DS:CODE
	push	es
	push	di
	les	di,es:[di].DDP_PARMS
	add	di,4
	mov	si,offset CON_LIMITS
	mov	ax,DOSUTIL_DECIMAL
	int	INT_DOSFUNC		; updates SI, DI, and AX
	mov	ch,al			; CH = rows
	mov	ax,DOSUTIL_DECIMAL
	int	INT_DOSFUNC
	mov	cl,al			; CL = columns
	mov	ax,DOSUTIL_DECIMAL
	int	INT_DOSFUNC
	mov	dh,al			; DH = starting row
	mov	ax,DOSUTIL_DECIMAL
	int	INT_DOSFUNC
	mov	dl,al			; DL = starting column
	pop	di
	pop	es			; ES:DI -> DDP (done with DDP_PARMS)
	mov	bx,(size context + 15) SHR 4
	mov	ah,DOS_ALLOC
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

ddo9:	ret
ENDPROC	ddcmd_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_close
;
; Inputs:
;	DS:DI -> DDP
;
; Outputs:
;
DEFPROC	ddcmd_close
	ASSUME	DS:CODE
	mov	ax,es:[di].DDP_CONTEXT
	test	ax,ax
	jz	ddc9
	push	es
	mov	es,ax
	mov	ah,DOS_FREE
	int	INT_DOSFUNC
	pop	es
ddc9:	ret
ENDPROC	ddcmd_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_none (handler for unimplemented functions)
;
; Inputs:
;	DS:DI -> DDP
;
; Outputs:
;
DEFPROC	ddcmd_none
	ASSUME	DS:CODE
	stc
	ret
ENDPROC	ddcmd_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	[ddpkt] -> DDPI
;	SS = BIOS segment (this is a valid assumption at init time only)
;
; Outputs:
;	DDPI's DDPI_END updated
;
DEFPROC	ddinit,far
	ASSUME	DS:NOTHING,SS:BIOS
	push	di
	push	es
	les	di,[ddpkt]
	mov	es:[di].DDPI_END.off,offset ddinit
	mov	cs:[0].DDH_INTERRUPT,offset DEV:ddint
;
; Determine what kind of video console we're dealing with (MONO or COLOR)
; and what the frame buffer segment is.  Don't forget to save all registers.
;
	push	ax
	push	bx
	mov	bx,0B000h
	mov	ax,[EQUIP_FLAG]
	and	ax,EQ_VIDEO_MODE
	cmp	ax,EQ_VIDEO_MONO
	je	ddin9
	mov	bx,0B800h
ddin9:	mov	[frame_seg],bx
	pop	bx
	pop	ax
	pop	es
	pop	di
	ret
ENDPROC	ddinit

CODE	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
