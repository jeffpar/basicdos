;
; BASIC-DOS Physical (LPT) Parallel Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; There's one driver instance (LPT1, LPT2, and LPT3) for each parallel port
; that the BIOS found (see PRINTER_BASE), and all their requests go to the
; same command handler (ddlpt_cmd), which writes with the BIOS (INT 17h);
; every other request does nothing.  PRN is LPT1 unless CONFIG.SYS has a
; PRN= setting.
;
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc

DEV	group	CODE1,CODE2,CODE3,INIT,DATA

CODE1	segment para public 'CODE'

	public	LPT1
	DEFLEN	LPT1_LEN,<LPT1>
	DEFLEN	LPT1_INIT,<LPT1,LPT2,LPT3>
LPT1	DDH	<LPT1_LEN,,DDATTR_OPEN+DDATTR_CHAR,LPT1_INIT,-1,202020203154504Ch>
;
; Every LPT driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddlpt_cmdp		; ddlpt_cmd pointer
	DEFWORD	lpt_num,0		; printer # (0-2) for INT 17h
	DEFWORD	lpt_err,0		; last write error (see ddlpt_cmd)
	DEFWORD	lpt_col,0		; current column (see ddlpt_cmd)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE1, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddlpt_req,far
	mov	dx,[lpt_num]
	mov	bp,cs			; BP = this instance (see ddlpt_cmd)
	jmp	[ddlpt_cmdp]
ENDPROC	ddlpt_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver command handler
;
; WRITE requests print each byte with INT 17h, and stop at the first byte
; that the BIOS reports an error for (a time-out is "not ready", like DOS),
; which is also recorded in the instance's lpt_err (until the next WRITE), so
; that a program that ignores write errors can check later (eg, LPRINT; see
; chkOut in libc.asm): an IOCTL_OUTSTATUS request fails with that error (and
; clears it).  We also track the column (lpt_col) that the printer is at:
; a CR returns it to 0, a BS backs it up, and any other character below a
; space leaves it alone; IOCTL_GETPOS returns it in DL (see LPOS).  All other
; requests succeed without doing anything (so a READ returns no data).
;
; Inputs:
;	DX = printer #
;	BP = segment of the instance
;	ES:BX -> DDP
;
; Outputs:
;	DDP updated
;
DEFPROC	ddlpt_cmd,far
	mov	ax,DDSTAT_DONE		; AX = status (assume success)
	mov	cl,es:[bx].DDP_CMD
	cmp	cl,DDC_IOCTLIN
	jne	dlc0
	mov	ds,bp
	ASSUME	DS:NOTHING
	cmp	es:[bx].DDP_CODE,IOCTL_GETPOS
	jne	dlc0a
	mov	cx,ds:[lpt_col]
	mov	es:[bx].DDP_CONTEXT,cx	; DL = column, DH = row (zero)
	jmp	short dlc9
dlc0a:	cmp	es:[bx].DDP_CODE,IOCTL_OUTSTATUS
	jne	dlc9			; no other IOCTL does anything
	sub	cx,cx
	xchg	cl,byte ptr ds:[lpt_err]; CX = last write error (if any)
	jcxz	dlc9			; none
	mov	ax,DDSTAT_ERROR
	or	al,cl			; AX = error status
	jmp	short dlc9
dlc0:	cmp	cl,DDC_WRITE
	jne	dlc9			; no other request does anything
	mov	ds,bp
	mov	byte ptr ds:[lpt_err],0	; no error yet
	mov	di,ds:[lpt_col]		; DI = column
	mov	cx,es:[bx].DDPRW_LENGTH
	jcxz	dlc9
	lds	si,es:[bx].DDPRW_ADDR
	ASSUME	DS:NOTHING
dlc1:	lodsb
	mov	ah,0			; AH = PRINT CHARACTER, DX = printer #
	int	17h			; AH = printer status
	test	ah,29h			; time-out, I/O error, or out of paper?
	jnz	dlc2			; yes
	mov	al,[si-1]
	cmp	al,CHR_RETURN		; CR?
	jne	dlc1a			; no
	sub	di,di			; yes, so back to column 0
dlc1a:	cmp	al,CHR_BACKSPACE	; BS?
	jne	dlc1b			; no
	dec	di			; yes, so back up (but not past 0)
	jns	dlc1b
	inc	di
dlc1b:	cmp	al,' '			; printable?
	jb	dlc1c			; no
	inc	di			; yes, so advance
dlc1c:	loop	dlc1
	mov	ax,DDSTAT_DONE
	jmp	short dlc8
dlc2:	mov	al,DDERR_NOPAPER
	test	ah,20h			; out of paper?
	jnz	dlc2a			; yes
	mov	al,DDERR_NOTREADY
	test	ah,01h			; time-out?
	jnz	dlc2a			; yes
	mov	al,DDERR_WRFAULT	; no, so it's an I/O error
dlc2a:	mov	ds,bp
	mov	byte ptr ds:[lpt_err],al; record the error
	mov	ah,DDSTAT_ERROR SHR 8
dlc8:	mov	es:[bx].DDPRW_LENGTH,cx	; CX = # bytes not printed
	mov	ds,bp
	mov	ds:[lpt_col],di		; update the column
dlc9:	mov	es:[bx].DDP_STATUS,ax
	ret
ENDPROC	ddlpt_cmd

	DEFLBL	LPT1_END

CODE1	ends

CODE2	segment para public 'CODE'

	DEFLEN	LPT2_LEN,<LPT2>
	DEFLEN	LPT2_INIT,<LPT2,LPT3>
LPT2	DDH	<LPT2_LEN,,DDATTR_CHAR,LPT2_INIT,-1,202020203254504Ch>
;
; Every LPT driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddlpt_cmdp2		; ddlpt_cmd pointer
	DEFWORD	lpt_num2,0		; printer # (0-2) for INT 17h
	DEFWORD	lpt_err2,0		; last write error (see ddlpt_cmd)
	DEFWORD	lpt_col2,0		; current column (see ddlpt_cmd)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE2, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddlpt_req2,far
	mov	dx,[lpt_num2]
	mov	bp,cs			; BP = this instance (see ddlpt_cmd)
	jmp	[ddlpt_cmdp2]
ENDPROC	ddlpt_req2

	DEFLBL	LPT2_END

CODE2	ends

CODE3	segment para public 'CODE'

	DEFLEN	LPT3_LEN,<LPT3,ddlpt_init>,16
	DEFLEN	LPT3_INIT,<LPT3>
LPT3	DDH	<LPT3_LEN,,DDATTR_CHAR,LPT3_INIT,-1,202020203354504Ch>
;
; Every LPT driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddlpt_cmdp3		; ddlpt_cmd pointer
	DEFWORD	lpt_num3,0		; printer # (0-2) for INT 17h
	DEFWORD	lpt_err3,0		; last write error (see ddlpt_cmd)
	DEFWORD	lpt_col3,0		; current column (see ddlpt_cmd)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE3, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddlpt_req3,far
	mov	dx,[lpt_num3]
	mov	bp,cs			; BP = this instance (see ddlpt_cmd)
	jmp	[ddlpt_cmdp3]
ENDPROC	ddlpt_req3

	DEFLBL	LPT3_END

CODE3	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; If there are no LPT ports, then the offset portion of DDPI_END will be zero.
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddlpt_init,far
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	si,offset PRINTER_BASE
	mov	di,bx			; ES:DI -> DDPI
	mov	bl,byte ptr cs:[0].DDH_NAME+3
	dec	bx
	and	bx,0003h		; BX = printer # (0-2)
	add	si,bx
	mov	ax,[si+bx]		; get BIOS PRINTER port address
	test	ax,ax			; exists?
	jz	in9			; no
	mov	[lpt_num],bx
	mov	ax,cs:[0].DDH_NEXT_OFF	; yes, copy over the driver length
	cmp	bl,2			; LPT3?
	jne	in1			; no
	mov	ax,cs:[0].DDH_REQUEST	; use the temporary ddlpt_req offset

in1:	mov	es:[di].DDPI_END.OFF,ax
	mov	cs:[0].DDH_REQUEST,offset DEV:ddlpt_req

	mov	[ddlpt_cmdp].OFF,offset DEV:ddlpt_cmd
in2:	mov	ax,0			; this MOV will be modified
	test	ax,ax			; on the first call to contain the CS
	jnz	in3			; of the first driver (this is the
	mov	ax,cs			; easiest way to communicate between
	mov	word ptr cs:[in2+1],ax	; the otherwise fully insulated drivers)
in3:	mov	[ddlpt_cmdp].SEG,ax

in9:	ret
ENDPROC	ddlpt_init

	DEFLBL	ddlpt_init_end

INIT	ends

DATA	segment para public 'DATA'

ddlpt_end	db	16 dup(0)

DATA	ends

	end
