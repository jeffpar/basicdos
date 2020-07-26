;
; BASIC-DOS Physical (COM) Serial Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DEV	group	CODE,CODE2,CODE3,CODE4,INIT,DATA

CODE	segment para public 'CODE'

	public	COM1
	DEFLEN	COM1_LEN,<COM1>
	DEFLEN	COM1_INIT,<COM1,COM2,COM3,COM4>
COM1	DDH	<COM1_LEN,,DDATTR_OPEN+DDATTR_CHAR,COM1_INIT,ddcom_int1,20202020314D4F43h>

	DEFPTR	ddcom_cmdp	; ddcom_cmd pointer
	DEFPTR	ddcom_intp	; ddcom_int pointer
	DEFWORD	ct_seg,0	; active context, if any
	DEFWORD	port_base,0	; port base

	DEFLBL	CMDTBL,word
	dw	ddcom_none,   ddcom_none,   ddcom_none,   ddcom_none	; 0-3
	dw	ddcom_none,   ddcom_none,   ddcom_none,   ddcom_none	; 4-7
	dw	ddcom_write,  ddcom_none,   ddcom_none,   ddcom_none	; 8-11
	dw	ddcom_none,   ddcom_open,   ddcom_close			; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	COM_PARMS,word
	dw	9600,110,19200, 8,7,8, 1,1,2
;
; A serial context contains two buffers (input and output), along with
; head and tail pointers for each.
;
CONTEXT		struc
CT_PORT		dw	?	; 00h: base port address
CT_BAUD		dw	?	; 02h: current baud rate
CT_DATABITS	db	?	; 04h
CT_STOPBITS	db	?	; 05h
CT_PARITY	db	?	; 06h
CT_REFS		db	?	; 07h
CT_INLEN	dw	?	; 08h: size of input buffer
CT_INBUF	dw	?	; 0Ah: offset within segment of input buffer
CT_INHEAD	dw	?	; 0Ch: head of input (next offset to read)
CT_INTAIL	dw	?	; 0Eh: tail of input (next offset to write)
CT_OUTLEN	dw	?	; 10h: size of output buffer
CT_OUTBUF	dw	?	; 12h: offset within segment of output buffer
CT_OUTHEAD	dw	?	; 14h: head of output (next offset to read)
CT_OUTTAIL	dw	?	; 16h: tail of output (next offset to write)
CT_RESERVED	db	?	; 18h
CONTEXT		ends

CTSIG		equ	'O'

DEF_INLEN	equ	128
DEF_OUTLEN	equ	128

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
DEFPROC	ddcom_req,far
	mov	cx,[ct_seg]
	mov	dx,[port_base]
	call	[ddcom_cmdp]
	mov	[ct_seg],cx
	ret
ENDPROC	ddcom_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver command handler
;
; Inputs:
;	DX = port
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddcom_cmd,far
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
	call	CMDTBL[bx]
	ret
ENDPROC	ddcom_cmd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_write
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_write
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	dcw9

	lds	si,es:[di].DDPRW_ADDR
	ASSUME	DS:NOTHING
	; mov	dx,es:[di].DDP_CONTEXT
	; test	dx,dx
	; jnz	dcw2

dcw1:	lodsb
	mov	ah,1
	mov	dx,0
	int	14h
	loop	dcw1
	jmp	short dcw9

; dcw2:	push	es
; 	mov	es,dx
; 	test	es:[CT_STATUS],CTSTAT_PAUSED
; 	jz	dcw3
; ;
; ; For WRITE requests that cannot be satisifed, we add this packet to an
; ; internal chain of "writing" packets, and then tell DOS that we're waiting;
; ; DOS will suspend the current SCB until we notify DOS that this packet's
; ; conditions are satisfied.
; ;
; 	pop	es			; ES:DI -> packet again
; 	call	add_packet
; 	jmp	dcw2			; when this returns, try writing again

; dcw3:	lodsb
; 	call	write_context
; 	loop	dcw3
; 	pop	es

dcw9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcom_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_open
;
; The format of the optional context descriptor is:
;
;	[device]:[baud],[parity],[databits],[stopbits]
;
; where [device] is "COMn" (otherwise you wouldn't be here).
;
; Inputs:
;	CX = context (zero if none)
;	DX = port base
;	ES:DI -> DDP
;	[DDP].DDP_PTR -> context descriptor (eg, "COM1:9600,N,8,1")
;
; Outputs:
;	CX = context (zero if none)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_open
;
; If there's already a context for this device, increment the refs.
;
	jcxz	dco1
	mov	ds,cx
	ASSUME	DS:NOTHING
	inc	ds:[CT_REFS]
dco0:	jmp	short dco8

dco1:	lds	si,es:[di].DDP_PTR
	ASSUME	DS:NOTHING
;
; We know that DDP_PTR must point to a string containing "COMn:" at the
; very least, so we skip those 5 bytes.
;
	add	si,5			; DS:SI -> parms
	cmp	[si],cl			; any parms?
	je	dco0			; no

	mov	bx,(size CONTEXT + DEF_INLEN + DEF_OUTLEN + 15) SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	INT_DOSFUNC
	jc	dco7

	push	di
	push	es
	mov	es,ax
	sub	di,di
	xchg	ax,dx			; AX = port address
	stosw				; set CT_PORT
	call	get_parms
	xchg	ax,cx
	stosw				; set CT_BAUD
	xchg	ax,dx
	stosw				; set CT_DATABITS, CT_STOPBITS
	mov	al,bl
	mov	ah,1
	stosw				; set CT_PARITY and CT_REFS
	mov	ax,DEF_INLEN
	stosw				; set CT_INLEN
	mov	ax,size CONTEXT
	stosw				; set CT_INBUF
	stosw				; set CT_INHEAD
	stosw				; set CT_INTAIL
	mov	ax,DEF_OUTLEN
	stosw				; set CT_INLEN
	mov	ax,size CONTEXT + DEF_INLEN
	stosw				; set CT_OUTBUF
	stosw				; set CT_OUTHEAD
	stosw				; set CT_OUTTAIL
	IFDEF DEBUG
	mov	al,CTSIG
	stosb
	ENDIF
	mov	cx,es
	pop	es
	pop	di
	jmp	short dco8
;
; At the moment, the only possible error is a failure to allocate memory.
;
dco7:	sub	cx,cx
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_GENFAIL
	jmp	short dco9

dco8:	mov	es:[di].DDP_CONTEXT,cx
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dco9:	ret
ENDPROC	ddcom_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_close
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_close
	int 3
	mov	cx,es:[di].DDP_CONTEXT
	jcxz	dcc8			; no context

	push	es
	mov	es,cx
	ASSERT	STRUCT,es:[0],CT
	dec	es:[CT_REFS]
	jg	dcc8
;
; We are now free to free the context segment in ES
;
	mov	ah,DOS_MEM_FREE
	int	INT_DOSFUNC
	pop	es
	sub	cx,cx

dcc8:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcom_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_none (handler for unimplemented functions)
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_none
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	stc
	ret
ENDPROC	ddcom_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_parms
;
; Inputs:
;	DS:SI -> parameter string
;
; Outputs:
;	CX = baud rate
;	DL = parity indicator
;	DH = data bits
;	AL = stop bits
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	get_parms
	push	di
	push	es
	push	cs
	pop	es
	mov	bl,10			; use base 10
	mov	di,offset COM_PARMS	; ES:DI -> parm defaults/limits
	mov	ax,DOS_UTL_ATOI16
	int	21h			; updates SI, DI, and AX
	xchg	cx,ax			; CX = baud rate
	lodsb
	mov	bl,al			; BL = parity indicator
	lodsb
	mov	ax,DOS_UTL_ATOI16
	int	21h
	mov	dl,al			; DL = data bits
	mov	ax,DOS_UTL_ATOI16
	int	21h
	mov	dh,al			; DH = stop bits
	pop	es
	pop	di
	ret
ENDPROC	get_parms

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_int (serial hardware interrupt handler)
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_int,far
	int 3
	call	far ptr DDINT_ENTER
	push	ax
	jcxz	ddi0			; no context
	jnc	ddi1			; carry clear if DOS ready
ddi0:	jmp	ddi9x

ddi1:	push	bx
	push	dx
	push	di
	push	ds
	push	es

	sti

ddi9:	pop	es
	pop	ds
	pop	di
	pop	dx
	pop	bx

ddi9x:	mov	al,20h			; EOI the interrupt
	out	20h,al
	pop	ax
	pop	cx
	jmp	far ptr DDINT_LEAVE
ENDPROC	ddcom_int

DEFPROC	ddcom_int1,far
	push	cx
	mov	cx,[ct_seg]
	jmp	[ddcom_intp]
ENDPROC	ddcom_int1

	DEFLBL	COM1_END

CODE	ends

CODE2	segment para public 'CODE'

	public	COM2
	DEFLEN	COM2_LEN,<COM2>
	DEFLEN	COM2_INIT,<COM2,COM3,COM4>
COM2	DDH	<COM2_LEN,,DDATTR_CHAR,COM2_INIT,ddcom_int2,20202020324D4F43h>

	DEFPTR	ddcom_cmdp2		; ddcom_cmd pointer
	DEFPTR	ddcom_intp2		; ddcom_int pointer
	DEFWORD	ct_seg2,0
	DEFWORD	port_base2,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE2, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req2,far
	mov	cx,[ct_seg2]
	mov	dx,[port_base2]
	call	[ddcom_cmdp2]
	mov	[ct_seg2],cx
	ret
ENDPROC	ddcom_req2

DEFPROC	ddcom_int2,far
	push	cx
	mov	cx,[ct_seg2]
	jmp	[ddcom_intp2]
ENDPROC	ddcom_int2

	DEFLBL	COM2_END

CODE2	ends

CODE3	segment para public 'CODE'

	public	COM3
	DEFLEN	COM3_LEN,<COM3>
	DEFLEN	COM3_INIT,<COM3,COM4>
COM3	DDH	<COM3_LEN,,DDATTR_CHAR,COM3_INIT,ddcom_int3,20202020334D4F43h>

	DEFPTR	ddcom_cmdp3		; ddcom_cmd pointer
	DEFPTR	ddcom_intp3		; ddcom_int pointer
	DEFWORD	ct_seg3,0
	DEFWORD	port_base3,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE3, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req3,far
	mov	cx,[ct_seg3]
	mov	dx,[port_base3]
	call	[ddcom_cmdp3]
	mov	[ct_seg3],cx
	ret
ENDPROC	ddcom_req3

DEFPROC	ddcom_int3,far
	push	cx
	mov	cx,[ct_seg3]
	jmp	[ddcom_intp3]
ENDPROC	ddcom_int3

	DEFLBL	COM3_END

CODE3	ends

CODE4	segment para public 'CODE'

	public	COM4
	DEFLEN	COM4_LEN,<COM4,ddcom_init>,16
	DEFLEN	COM4_INIT,<COM4>
COM4	DDH	<COM4_LEN,,DDATTR_CHAR,COM4_INIT,ddcom_int4,20202020344D4F43h>

	DEFPTR	ddcom_cmdp4		; ddcom_cmd pointer
	DEFPTR	ddcom_intp4		; ddcom_int pointer
	DEFWORD	ct_seg4,0
	DEFWORD	port_base4,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE4, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_req4,far
	mov	cx,[ct_seg4]
	mov	dx,[port_base4]
	call	[ddcom_cmdp4]
	mov	[ct_seg4],cx
	ret
ENDPROC	ddcom_req4

DEFPROC	ddcom_int4,far
	push	cx
	mov	cx,[ct_seg4]
	jmp	[ddcom_intp4]
ENDPROC	ddcom_int4

	DEFLBL	COM4_END

CODE4	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If there are no COM ports, then the offset portion of DDPI_END will be zero.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_init,far
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	si,offset RS232_BASE
	mov	di,bx			; ES:DI -> DDPI
	mov	bl,byte ptr cs:[DDH_NAME+3]
	dec	bx
	and	bx,0003h
	add	si,bx
	mov	dx,[si+bx]		; DX = BIOS RS232 port address
	test	dx,dx			; exists?
	jz	in9			; no
	mov	[port_base],dx
	mov	ax,cs:[DDH_NEXT_OFF]	; yes, copy over the driver length
	cmp	bl,3			; COM4?
	jne	in1			; no
	mov	ax,cs:[DDH_REQUEST]	; use the temporary ddcom_req offset

in1:	mov	es:[di].DDPI_END.OFF,ax
	mov	cs:[DDH_REQUEST],offset DEV:ddcom_req

	mov	[ddcom_cmdp].OFF,offset DEV:ddcom_cmd
	mov	[ddcom_intp].OFF,offset DEV:ddcom_int
in2:	mov	ax,0			; this MOV will be modified
	test	ax,ax			; on the first call to contain the CS
	jnz	in3			; of the first driver (this is the
	mov	ax,cs			; easiest way to communicate between
	mov	word ptr cs:[in2+1],ax	; the otherwise fully insulated drivers)
in3:	mov	[ddcom_cmdp].SEG,ax
	mov	[ddcom_intp].SEG,ax
;
; Determine the hardware interrupt vector for port DX
;
	mov	di,INT_HW_COM1
	cmp	dh,03h
	je	in4
	dec	di
in4:	add	di,di
	add	di,di
	cli
	mov	ax,cs:[DDH_INTERRUPT]
	mov	[di].OFF,ax
	mov	[di].SEG,cs
	sti

in9:	ret
ENDPROC	ddcom_init

	DEFLBL	ddcom_init_end

INIT	ends

DATA	segment para public 'DATA'

ddcom_end	db	16 dup(0)

DATA	ends

	end
