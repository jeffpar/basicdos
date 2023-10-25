;
; BASIC-DOS Logical (CON) I/O Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	BIOSEQU equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	CON
CON	DDH	<offset DEV:ddcon_end+16,,DDATTR_STDIN+DDATTR_STDOUT+DDATTR_OPEN+DDATTR_CHAR,offset ddcon_init,-1,20202020204E4F43h>

	DEFLBL	CMDTBL,word
	dw	ddcon_none,   ddcon_none,   ddcon_none,   ddcon_ioctl	; 00-03
	dw	ddcon_read,   ddcon_none,   ddcon_none,   ddcon_none	; 04-07
	dw	ddcon_write,  ddcon_none,   ddcon_none,   ddcon_none	; 08-0B
	dw	ddcon_none,   ddcon_open,   ddcon_close			; 0C-0E
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	IOCTBL,word
	dw	ddcon_getdd,  ddcon_none,   ddcon_none,   ddcon_none	; 00-03
	dw	ddcon_none,   ddcon_none,   ddcon_none,   ddcon_none	; 04-07
	dw	ddcon_none,   ddcon_getdim, ddcon_getpos, ddcon_getlen	; C0-C3
	dw	ddcon_movcur, ddcon_setins, ddcon_scroll, ddcon_getclr	; C4-C7
	dw	ddcon_setclr						; C8
	DEFABS	IOCTBL_SIZE,<($ - IOCTBL) SHR 1>

	DEFLBL	CON_PARMS,word
	dw	80,16,80, 25,4,25
	DEFLBL	ZERO,word	; since we have all this constant data, use it
	dw	0,0,79, 0,0,24, 0,0,1, 0,0,1

	DEFLBL	DBL_BORDER,word
	dw	0C9BBh,0BABAh,0C8BCh,0CDCDh

	DEFLBL	SGL_BORDER,word
	dw	0DABFh,0B3B3h,0C0D9h,0C4C4h

	DEFLBL	SCAN_MAP,byte
	db	SCAN_F1,         CHR_CTRLD
	db	SCAN_F3,         CHR_CTRLL
	db	SCAN_HOME,       CHR_CTRLW
	db	SCAN_UP,         CHR_CTRLE
	db	SCAN_LEFT,       CHR_CTRLS
	db	SCAN_RIGHT,      CHR_CTRLD
	db	SCAN_END,        CHR_CTRLR
	db	SCAN_DOWN,       CHR_CTRLX
	db	SCAN_INS,        CHR_CTRLV
	db	SCAN_DEL,        CHR_DEL
	db	SCAN_CTRL_LEFT,  CHR_CTRLA
	db	SCAN_CTRL_RIGHT, CHR_CTRLF
	db	SCAN_CTRL_END,   CHR_CTRLK
	db	0

	DEFWORD	ct_head,0	; head of context chain
	DEFWORD	ct_focus,0	; segment of context with focus
	DEFWORD	frame_seg,0	; frame buffer segment of PRIMARY adapter
	DEFBYTE	max_rows,25	; TODO: use this for something...
	DEFBYTE	max_cols,80	; TODO: set to correct value in ddcon_init
	DEFBYTE	bios_lock,0	; non-zero if BIOS lock in effect
	DEFBYTE	req_switch,0	; non-zero if a context switch is requested

	DEFPTR	kbd_int,0	; original keyboard hardware interrupt handler
	DEFPTR	video_int,0	; original video services interrupt handler
	DEFPTR	wait_ptr,-1	; chain of waiting packets
;
; A context of "80,25,0,0,1" requests a border, so logical cursor positions
; are 1,1 to 78,23.  Physical character and cursor positions will be adjusted
; by the offset address in CT_SCREEN.
;
CONTEXT		struc
CT_NEXT		dw	?	; 00h: segment of next context, 0 if end
CT_REFS		db	?	; 02h: # of references
CT_STATUS	db	?	; 03h: context status bits (CTSTAT_*)
CT_CONDIM	dw	?	; 04h: eg, context dimensions (0-based)
CT_CONPOS	dw	?	; 06h: eg, context position (X,Y) of top left
CT_CURPOS	dw	?	; 08h: eg, cursor X (lo) and Y (hi) position
CT_CURMIN	dw	?	; 0Ah: eg, cursor X (lo) and Y (hi) minimums
CT_CURMAX	dw	?	; 0Ch: eg, cursor X (lo) and Y (hi) maximums
CT_CURDIM	dw	?	; 0Eh: width and height (for cursor movement)
CT_EQUIP	dw	?	; 10h: BIOS equipment flags (snapshot)
CT_PORT		dw	?	; 12h: eg, 3D4h
CT_MODE		db	?	; 14h: active video mode (see MODE_*)
CT_SIG		db	?	; 15h: (holds SIG_CT in DEBUG builds)
CT_COLS		dw	?	; 16h: eg, 80 (50h; ie, column width of screen)
CT_SCROFF	dw	?	; 18h: eg, 2000 (offset of off-screen memory)
CT_SCREEN	dd	?	; 1Ah: eg, B800:00A2h with full-screen border
CT_BUFFER	dd	?	; 1Eh: used only for background contexts
CT_BUFLEN	dw	?	; 22h: eg, 4000 for full-screen 25*80*2 buffer
CT_COLOR	dw	?	; 24h: fill (LO) and border (HI) attributes
CT_CURTYPE	dw	?	; 26h: current cursor type (HI=top, LO=bottom)
CT_DEFTYPE	dw	?	; 28h: default cursor type (HI=top, LO=bottom)
;
; Context save region, used to save critical BIOS data area variables around
; BIOS operations.  TODO: Decide where/how to handle TBD variables.
;
CTS_MODE	db	?	; 2Ah: saves CRT_MODE before writing CT_MODE
CTS_PAGE	db	?	; 2Bh: saves ACTIVE_PAGE before writing TBD
CTS_COLS	dw	?	; 2Ch: saves CRT_COLS before writing CT_COLS
CTS_LEN		dw	?	; 2Eh: saves CRT_LEN before writing TBD
CTS_START	dw	?	; 30h: saves CRT_START before writing TBD
CTS_CURTYPE	dw	?	; 32h: saves CURSOR_MODE before writing CT_CURTYPE
CTS_PORT	dw	?	; 34h: saves ADDR_6845 before writing CT_PORT
CONTEXT		ends
SIG_CT		equ	'C'

CTSTAT_BORDER	equ	01h	; context has border
CTSTAT_ADAPTER	equ	02h	; context is using alternate adapter
CTSTAT_SKIPMODE	equ	04h	; set to skip the mode set for the adapter
CTSTAT_ABORT	equ	08h	; ABORT condition detected
CTSTAT_INPUT	equ	40h	; context is waiting for input
CTSTAT_PAUSED	equ	80h	; context is paused (triggered by CTRLS hotkey)

;
; CRT Controller Registers
;
CRTC_CURTOP	equ	0Ah	; cursor top (mirrored at CURSOR_MODE.HIB)
CRTC_CURBOT	equ	0Bh	; cursor bottom (mirrored at CURSOR_MODE.LOB)
CRTC_CURHI	equ	0Eh	; cursor start address (high)
CRTC_CURLO	equ	0Fh	; cursor start address (low)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;	Varies
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_req,far
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
ENDPROC	ddcon_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_ioctl
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;	Varies
;
; Modifies:
;	AX, BX, CX, DX, DS
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_ioctl
	mov	bl,es:[di].DDP_CODE	; IOCTL code from DDP_CODE
	cmp	bl,IOCTL_OUTSTATUS	; standard sub-function code?
	jbe	dio1			; yes
	sub	bl,IOCTL_CON - 8	; no, BASIC-DOS specific sub-function
dio1:	mov	dx,es:[di].DDP_CONTEXT
	test	dx,dx			; was a context provided?
	jz	dio2			; no, force call to ddcon_none
	mov	ds,dx
	ASSUME	DS:NOTHING
	cmp	bl,IOCTBL_SIZE		; table entry exist?
	jb	dio3			; yes
dio2:	mov	bl,8			; no, use entry for C0h (ddcon_none)
dio3:	mov	bh,0
	add	bx,bx
	mov	cx,es:[di].DDPRW_LENGTH	; CX = IOCTL input value
	mov	dx,es:[di].DDPRW_LBA	; DX = IOCTL input value
	push	di			; some of the IOCTL subfunctions
	push	es			; modify DI and ES, so we save them
	call	IOCTBL[bx]
	pop	es
	pop	di
	jc	dio9
dio7:	mov	es:[di].DDP_CONTEXT,dx	; return pos or length in packet context
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dio9:	ret
ENDPROC	ddcon_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getdd (AL = 00h: Get Device Data)
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = CONSOLE context
;
; Outputs:
;	DX = device data bits
;
; Modifies:
;	DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getdd
;
; This is enough to make PC DOS 2.00 BASICA start successfully on BASIC-DOS.
; I haven't checked but it's probably verifying STDIN/STDOUT wasn't redirected.
;
	; mov	dx,[CON].DDH_ATTR	; TODO: PC DOS 2.00 returns 80D3h
	mov	dx,80D3h
	ret
ENDPROC	ddcon_getdd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getdim
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = CONSOLE context
;
; Outputs:
;	DL = # columns
;	DH = # rows
;
; Modifies:
;	DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getdim
	mov	dx,ds:[CT_CURDIM]
	ret
ENDPROC	ddcon_getdim

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getpos
;
; This IOCTL is used in conjunction with IOCTL_GETLEN to obtain the display
; length of a series of bytes (up to 255).  Generally, all the caller cares
; about is the column, which is then passed to IOCTL_GETLEN.
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = CONSOLE context
;
; Outputs:
;	DX = current cursor position (DL = col, DH = row), zero-based.
;
; Modifies:
;	DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getpos
	mov	dx,ds:[CT_CURPOS]	; DX = current cursor position
	sub	dx,ds:[CT_CURMIN]	; make both row and col zero-based
	ret
ENDPROC	ddcon_getpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getlen
;
; This IOCTL returns the display length of a series of bytes (up to 255).
;
; This assists DOS function DOS_TTY_INPUT (AH = 0Ah), which cannot accurately
; erase TAB characters (or the entire buffer) without knowing both the starting
; position (from IOCTL_GETPOS) and the display length of the buffer.
;
; TAB characters are more complicated than usual, since the total number of
; columns in a context are not always multiples of 8, and tabs must always wrap
; to column 1 on the following line.
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = number of bytes (up to 255)
;	DX = starting cursor position; see IOCTL_GETPOS
;	DS = CONSOLE context
;
; Outputs:
;	DH = total display length, DL = length delta (of the final character)
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getlen
	mov	bx,dx			; BX = starting cursor position
	add	bx,ds:[CT_CURMIN]	; zero-based, so adjust to our mins
	sub	dx,dx			; DL = current len, DH = previous len
	mov	ah,ds:[CT_CURMAX].LOB	; AH = column max
	mov	bh,ds:[CT_CURMIN].LOB	; BH = column min
	lds	si,es:[di].DDPRW_ADDR
	mov	ch,0			; CL = length (255 character maximum)
	jcxz	dgl9			; nothing to do
	ASSUME	DS:NOTHING

dgl2:	lodsb
	mov	dh,dl			; current len -> previous len
	cmp	al,CHR_TAB
	jne	dgl4
	mov	al,bl			; for CHR_TAB
	sub	al,bh			; mimic write_context's TAB logic
	and	al,07h
	neg	al
	add	al,8			; AL = # output chars
dgl3:	inc	bl
	inc	dl
	cmp	bl,ah			; column still below limit?
	jbe	dgl3a			; yes
	mov	bl,bh			; no, so reset column and stop
	jmp	short dgl5
dgl3a:	dec	al
	jnz	dgl3
	jmp	short dgl5

dgl4:	cmp	al,CHR_SPACE		; CONTROL character?
	mov	al,1			; AL = # output chars
	jae	dgl4a			; no
	inc	ax			; add 1 more to output for presumed "^"
dgl4a:	inc	bl			; advance the column
	inc	dl			; advance the length
	cmp	bl,ah			; column still below limit?
	jbe	dgl4b			; yes
	mov	bl,bh			; no, so reset column and keep going
dgl4b:	dec	al
	jnz	dgl4a

dgl5:	loop	dgl2
	sub	dl,dh			; DL = length delta for final character
	add	dh,dl			; DH = total length

dgl9:	ret
ENDPROC	ddcon_getlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_movcur
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = +/- columns to move cursor horizontally
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_movcur
	call	move_cursor
	ret
ENDPROC	ddcon_movcur

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_setins
;
; NOTE: There is no "insert mode" flag; the mode is considered OFF (0)
; if bits 0-4 of CT_CURTYPE.HIB are set, and ON (1) if bits 0-4 are clear.
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = 0 to clear insert mode, 1 to set
;	DS = CONSOLE context
;
; Outputs:
;	DX = previous insert mode (0 if cleared, 1 if set)
;
; Modifies:
;	AX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_setins
	mov	ax,ds:[CT_DEFTYPE]
	ror	cl,1			; move CL bit 0 to bit 7 (and carry)
	jnc	dsi1			; "insert mode" requested?
	and	ah,0E0h			; yes, clear bits 0-4 of CT_CURTYPE.HIB
dsi1:	xchg	ds:[CT_CURTYPE],ax	; AX = previous CT_CURTYPE
	sub	dx,dx
	test	ah,1Fh			; were bits 0-4 clear?
	jnz	dsi2			; no, DX = 0
	inc	dx			; yes, DX = 1
dsi2:	mov	ax,ds
	cmp	ax,[ct_focus]		; does this context have focus?
	jne	dsi9			; no, leave cursor alone
	call	set_curtype		; update CT_CURTYPE
dsi9:	ret
ENDPROC	ddcon_setins

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_scroll
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = +/- lines to scroll, 0 to clear
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_scroll
	test	cx,cx			; clearing the whole interior?
	jnz	dcs1			; no
	call	draw_border		; yes, good idea to redraw border, too
	mov	cl,100
dcs1:	call	scroll
	cmp	cl,100
	jne	dcs9
	mov	dx,ds:[CT_CURMIN]
	call	update_cursor
dcs9:	ret
ENDPROC	ddcon_scroll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getclr
;
; Inputs:
;	ES:DI -> DDPRW
;	DS = CONSOLE context
;
; Outputs:
;	DL = fill attributes
;	DH = border attributes
;
; Modifies:
;	DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_getclr
	mov	dx,ds:[CT_COLOR]
	ret
ENDPROC	ddcon_getclr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_setclr
;
; Inputs:
;	ES:DI -> DDPRW
;	CL = fill attributes
;	CH = border attributes
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_setclr
	mov	ax,cx
	xchg	ds:[CT_COLOR],ax
	cmp	ah,ch			; border color changed?
	je	sc9			; no
	call	draw_border
sc9:	ret
ENDPROC	ddcon_setclr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_read
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_read
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	dcr8
;
; If the current context doesn't have focus, then we're not going to
; bother checking the keyboard buffer.  We still won't block non-blocking
; requests, but no data will be returned as long as we're out-of-focus.
;
	mov	dx,es:[di].DDP_CONTEXT
	cmp	dx,[ct_focus]
	jne	dcr0

	call	pull_kbd
	jnc	dcr8
;
; For READ requests that cannot be satisfied, we add this packet to an
; internal chain of "reading" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
; For character devices, DDP_UNIT contains the I/O mode (IO_RAW, IO_COOKED,
; or IO_DIRECT).
;
dcr0:	cmp	es:[di].DDP_UNIT,0
	jge	dcr1		; normal blocking request (not IO_DIRECT)
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_NOTREADY
	jmp	short dcr9

dcr1:	mov	ds,dx
	ASSUME	DS:NOTHING
	ASSERT	STRUCT,ds:[0],CT
	or	ds:[CT_STATUS],CTSTAT_INPUT
	call	add_packet
	jnc	dcr8
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_RDFAULT
	jmp	short dcr9

dcr8:	mov	es:[di].DDP_STATUS,DDSTAT_DONE

dcr9:	sti
	ret
ENDPROC	ddcon_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	jcxz	dcw8

	lds	si,es:[di].DDPRW_ADDR
	ASSUME	DS:NOTHING
	mov	dx,es:[di].DDP_CONTEXT
	test	dx,dx
	jnz	dcw2

dcw1:	lodsb
	call	write_char
	loop	dcw1
	jmp	short dcw8

dcw2:	push	es
	mov	es,dx
dcw3:	test	es:[CT_STATUS],CTSTAT_PAUSED
	jz	dcw4
;
; For WRITE requests that cannot be satisfied, we add this packet to an
; internal chain of "writing" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	pop	es			; ES:DI -> packet again
	mov	es:[di].DDPRW_LENGTH,cx
	mov	es:[di].DDPRW_ADDR.OFF,si
	call	add_packet
	jnc	dcw2			; if return is OK, try writing again
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	jmp	short dcw9

dcw4:	lodsb
	call	write_context
	loop	dcw3
	pop	es

dcw8:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dcw9:	ret
ENDPROC	ddcon_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_open
;
; The format of the optional context descriptor is:
;
;	[device]:[cols],[rows],[x],[y],[border],[adapter]
;
; where [device] is "CON" (otherwise you wouldn't be here), [cols] is number
; of columns (up to 80), [rows] is number of rows (up to 25), [x] and [y] are
; the top-left row and col of the context, [border] is 1 for a border or 0 for
; none, and [adapter] is the adapter #, in case there is more than one video
; adapter (adapter 0 is the default).
;
; Obviously future hardware (imagine an ENHANCED Graphics Adapter, for example)
; will be able to support more rows and other features, but we're designing
; exclusively for the MDA and CGA for now.
;
; Inputs:
;	ES:DI -> DDP
;	[DDP].DDP_PTR -> context descriptor (eg, "CON:80,25")
;
; Outputs:
;	[DDP].DDP_CONTEXT set with
;
; Notes:
;	We presume that the current SCB is locked for duration of this call;
;	if that presumption ever proves false, then use the DOSUTIL LOCK API.
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_open
	push	di
	push	es

	push	ds
	lds	si,es:[di].DDP_PTR
	ASSUME	DS:NOTHING
;
; We know that DDP_PTR must point to a string containing "CON" at the
; very least, so we skip those 3 bytes.
;
	add	si,3			; DS:SI -> descriptor, if any
	lodsb				; AL = 1st character of descriptor
	cmp	al,':'			; is it a colon?
	jne	dco0			; no
	cmp	byte ptr [si],0		; anything after the colon?
	jne	dco1			; yes
dco0:	pop	ds
	DOSUTIL	LOCK			; get the current context in AX
	mov	ds,ax
	ASSERT	STRUCT,ds:[0],CT
	inc	ds:[CT_REFS]
	DOSUTIL	UNLOCK
	clc
	jmp	dco7
;
; The device name consists of "CON:...."  We're not sure what "...." is yet,
; but hopefully it conforms to the context descriptor format described above.
;
dco1:	push	cs
	pop	es
	mov	bl,10			; use base 10
	mov	di,offset CON_PARMS	; ES:DI -> parm defaults/limits
	DOSUTIL	ATOI16			; updates SI, DI, and AX
	mov	cl,al			; CL = cols
	DOSUTIL	ATOI16
	mov	ch,al			; CH = rows
	DOSUTIL	ATOI16
	mov	dl,al			; DL = starting col
	DOSUTIL	ATOI16
	mov	dh,al			; DH = starting row
	DOSUTIL	ATOI16
	mov	bh,al			; BH = border (0 for none)
	ASSERT	CTSTAT_BORDER,EQ,01h
	DOSUTIL	ATOI16
	shl	al,1
	or	bh,al			; BH includes adapter bit, too
	ASSERT	CTSTAT_ADAPTER,EQ,02h
	pop	ds
	ASSUME	DS:CODE

	push	bx
	mov	bx,(size CONTEXT + 15) SHR 4
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	INT_DOSFUNC
	pop	bx
	jnc	dco1a
	jmp	dco7

dco1a:	mov	ds,ax
	ASSUME	DS:NOTHING
	DBGINIT	STRUCT,ds:[0],CT

	cmp	[ct_focus],0
	jne	dco2
	mov	[ct_focus],ax
;
; Inserting the new context at the head of the chain (ct_head) is the
; simplest way to update the chain, but we prefer to chain the contexts
; in the order they were created, to provide more natural focus cycling.
;
;	xchg	[ct_head],ax
;	mov	ds:[CT_NEXT],ax
;
dco2:	mov	ds:[CT_NEXT],0
	mov	bl,1			; set CT_REFS to 1 and CT_STATUS to BH
	mov	word ptr ds:[CT_REFS],bx
	sub	si,si			; no CURTYPE yet
	mov	di,offset ct_head
	push	cs
	pop	es
dco2a:	mov	ax,es:[di]		; ES:DI -> next context segment
	test	ax,ax
	jz	dco2b
	mov	es,ax
	mov	di,offset CT_NEXT
;
; Since we're stepping through every context, this is a good opportunity
; to see if any of them were for a second adapter; if so, then set the
; SKIPMODE bit (in BH only) to try to avoid another (unnecessary) mode set.
;
	test	es:[di].CT_STATUS,CTSTAT_ADAPTER
	jz	dco2a
	or	bh,CTSTAT_SKIPMODE
	mov	si,es:[CT_DEFTYPE]	; grab the default CURTYPE as well
	jmp	dco2a
dco2b:	mov	es:[di],ds
;
; Set context dimensions (CL,CH) and position (DL,DH), and then determine
; cursor minimums and maximums from the context size.
;
	mov	ax,0101h
	push	cx
	sub	cx,ax
	mov	ds:[CT_CONDIM],cx	; set CT_CONDIM (CL,CH)
	mov	ds:[CT_CONPOS],dx	; set CT_CONPOS (DL,DH)
	mov	al,bh
	and	al,CTSTAT_BORDER
	mov	ah,al			; AX = 0101h for border, 0000h for none
	mov	ds:[CT_CURMIN],ax	; set CT_CURMIN (AL,AH)
	sub	cx,ax
	mov	ds:[CT_CURMAX],cx	; set CT_CURMAX (CL,CH)
	pop	cx
	sub	cx,ax
	sub	cx,ax
	mov	ds:[CT_CURDIM],cx	; set CT_CURDIM (width and height)
	mov	al,dh
	mul	[max_cols]
	add	ax,ax
	mov	dh,0
	add	dx,dx
	add	ax,dx
	mov	ds:[CT_SCREEN].OFF,ax
	mov	ds:[CT_SCROFF],4000	; TODO: fix this hard-coded offset
	mov	ds:[CT_COLOR],0707h	; default fill and border attributes
;
; Importing the BIOS CURSOR_POSN into CURPOS seemed like a nice idea initially,
; but now that we're clearing interior below, it seems best to use a default.
;
	sub	ax,ax
	mov	es,ax
	ASSUME	ES:BIOS
	; mov	ax,[CURSOR_POSN]
	mov	ax,ds:[CT_CURMIN]	; get CT_CURMIN
	mov	ds:[CT_CURPOS],ax	; set CT_CURPOS (X and Y)
;
; WARNING: The following code to support alternate adapters is very fragile;
; it assumes we're dealing EXCLUSIVELY with MDA and CGA adapters, and that the
; monitor bits in the equipment flags are always set to either EQ_VIDEO_MONO
; (30h) or EQ_VIDEO_CO80 (20h), and therefore by toggling EQ_VIDEO_CO40 (10h)
; prior to INT 10h initialization of the adapter, the correct "equipment" will
; be enabled.
;
	mov	ax,[frame_seg]
	mov	bl,[CRT_MODE]
	mov	cx,[EQUIP_FLAG]		; snapshot the equipment flags
	mov	dx,[ADDR_6845]		; get the adapter's port address
	push	[CRT_COLS]

	test	bh,CTSTAT_ADAPTER
	jz	dco4
	xor	dl,60h			; convert 3D4h to 3B4h (or vice versa)
	xor	ah,08h			; convert B800h to B000h (or vice versa)
	push	ax
	xor	cl,EQ_VIDEO_CO40
	mov	al,MODE_MONO		; default
	cmp	dl,0B4h
	je	dco3
	mov	al,MODE_CO80
dco3:	mov	bl,al			; BL = new video mode
	test	bh,CTSTAT_SKIPMODE	; do we really need to set the mode?
	jnz	dco3a			; no
	xchg	[EQUIP_FLAG],cx
	mov	ah,VIDEO_SETMODE
	int	INT_VIDEO
	xchg	[EQUIP_FLAG],cx
dco3a:	pop	ax

dco4:	pop	ds:[CT_COLS]
	mov	ds:[CT_PORT],dx
	mov	ds:[CT_EQUIP],cx
	mov	ds:[CT_MODE],bl
	mov	ds:[CT_SCREEN].SEG,ax
	xchg	ax,si
	test	ax,ax
	jnz	dco4a
	call	update_curtype
dco4a:	mov	ds:[CT_CURTYPE],ax
	mov	ds:[CT_DEFTYPE],ax
;
; If we're creating a session on a secondary adapter, then like the mode
; change above, we must temporarily change EQUIP_FLAG, because until we finish
; this open call, the DOSUTIL LOCK function will be unable to tell our INT 10h
; hook what the correct context is.
;
	xchg	[EQUIP_FLAG],cx
	push	cx
	mov	cl,100
	call	scroll			; clear the context's interior
	pop	[EQUIP_FLAG]

	call	draw_border		; draw the context's border, if any

	mov	ax,ds
	cmp	ax,[ct_focus]		; does new context have focus?
	je	dco6			; yes
	call	hide_cursor		; no, so hide cursor
	push	ds			; and restore BIOS with data from focus
	mov	ds,[ct_focus]
	call	update_biosdata
	pop	ds
dco6:	clc
;
; At the moment, the only possible error is a failure to allocate memory.
;
dco7:	pop	es
	pop	di			; ES:DI -> DDP again
	jnc	dco8
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_GENFAIL
	jmp	short dco9

dco8:	mov	es:[di].DDP_CONTEXT,ds
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dco9:	ret
ENDPROC	ddcon_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	cx,es:[di].DDP_CONTEXT
	jcxz	dcc8			; no context

	push	es
	mov	es,cx
	dec	es:[CT_REFS]
	jnz	dcc7

dcc1:	cmp	[ct_focus],cx
	jne	dcc2
	call	switch_focus
	ASSERT	NZ,<cmp [ct_focus],cx>
;
; Remove the context from our chain.
;
dcc2:	push	ds
	xchg	ax,cx			; AX = context to free
	mov	bx,offset ct_head	; DS:BX -> 1st context
dcc3:	mov	cx,[bx].CT_NEXT
	ASSERT	NZ,<test cx,cx>
	jcxz	dcc4			; context not found
	cmp	cx,ax
	je	dcc4
	mov	ds,cx
	ASSUME	DS:NOTHING
	sub	bx,bx			; DS:BX -> next context
	jmp	dcc3			; keep looking
dcc4:	mov	cx,es:[CT_NEXT]		; move this context's CT_NEXT
	mov	[bx].CT_NEXT,cx		; to the previous context's CT_NEXT
	mov	ds,ax
	mov	cl,0			; clear the entire context
	call	scroll
	pop	ds
	ASSUME	DS:CODE
;
; We are now free to free the context segment in ES.
;
	mov	ah,DOS_MEM_FREE
	int	INT_DOSFUNC

dcc7:	pop	es

dcc8:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcon_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	stc
	ret
ENDPROC	ddcon_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_int09 (keyboard hardware interrupt handler)
;
; When keys appear in the BIOS keyboard buffer, deliver them to whichever
; context 1) has focus, and 2) has a pending read request.  Otherwise, let
; them stay in the BIOS buffer.
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
DEFPROC	ddcon_int09,far
	call	far ptr DDINT_ENTER
	jc	i09c

	push	ax
	in	al,60h			; peek at the scan code
	cmp	al,SCAN_DEL		; DEL key pressed?
	jne	i09b			; no
	push	ds
	sub	ax,ax
	mov	ds,ax
	mov	al,ds:[KB_FLAG]		; CTRL and ALT pressed as well?
	and	al,CTL_SHIFT OR ALT_SHIFT
	cmp	al,CTL_SHIFT OR ALT_SHIFT
	jne	i09a			; no
;
; After notifying DOS of the "CTRL-ALT-DEL" hotkey, we're going to
; clear the CTL_SHIFT flag in order to let the BIOS process the interrupt
; without rebooting the machine.
;
	push	cx
	mov	cx,[ct_focus]		; CX = context
	jcxz	i09
	push	dx
	mov	dx,CHR_CTRLD		; DL = char code, DH = scan code
	DOSUTIL	HOTKEY			; notify DOS
	and	ds:[KB_FLAG],NOT CTL_SHIFT
	mov	ds,cx
	ASSERT	STRUCT,ds:[0],CT
	or	ds:[CT_STATUS],CTSTAT_ABORT
	pop	dx
i09:	pop	cx
i09a:	pop	ds
i09b:	pop	ax
	clc

i09c:	pushf
	call	[kbd_int]
	jnc	i09d			; carry set if DOS isn't ready
	jmp	i09z

i09d:	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	push	ds
	push	es

	sti
	mov	cx,[ct_focus]		; CX = context
	call	check_hotkey
	jc	i09e
	xchg	dx,ax			; DL = char code, DH = scan code
	DOSUTIL	HOTKEY			; notify DOS

i09e:	mov	ds,cx			; DS = context
	mov	cx,cs
	mov	es,cx
	mov	bx,offset wait_ptr	; CX:BX -> ptr
	les	di,es:[bx]		; ES:DI -> packet, if any
	ASSUME	ES:NOTHING

i09f:	cmp	di,-1			; end of chain?
	je	i09w			; yes

	ASSERT	STRUCT,es:[di],DDP

	mov	dx,ds
	cmp	es:[di].DDP_CONTEXT,dx	; packet from console with focus?
	jne	i09i			; no

	cmp	es:[di].DDP_CMD,DDC_READ; READ packet?
	je	i09g			; yes, look for keyboard data
;
; For WRITE packets (which we'll assume this is for now), we need to end the
; wait if the context is no longer paused (ie, if check_hotkey cleared PAUSED).
;
	ASSERT	STRUCT,ds:[0],CT
	test	ds:[CT_STATUS],CTSTAT_PAUSED
	jz	i09h			; yes, we're no longer paused
	jmp	short i09i		; still paused, check next packet

i09g:	call	pull_kbd		; pull keyboard data
	jnc	i09h
	test	ds:[CT_STATUS],CTSTAT_ABORT
	jz	i09i			; not enough data, and no ABORT pending
;
; Notify DOS that this packet is done waiting.
;
i09h:	and	ds:[CT_STATUS],NOT CTSTAT_INPUT
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	DOSUTIL	ENDWAIT
;
; If carry is set, ENDWAIT failed.  There are two cases: 1) the WAIT request
; hasn't been set yet (eg, a race condition), and 2) the WAIT request was
; aborted (nothing we can do about that).
;
; TODO: To avoid the potential race condition, the entire pull_kbd + add_packet
; path disables interrupts.  Consider lighter-weight solutions.
;
; In any case, proceed with packet removal now.
;
	cli
	mov	ax,es:[di].DDP_PTR.OFF
	mov	dx,es:[di].DDP_PTR.SEG
	mov	es,cx
	mov	es:[bx].OFF,ax
	mov	es:[bx].SEG,dx
	or	ds:[CT_STATUS],CTSTAT_ABORT
	jmp	short i09w

i09i:	lea	bx,[di].DDP_PTR		; update prev addr ptr in CX:BX
	mov	cx,es

	les	di,es:[di].DDP_PTR
	jmp	i09f

i09w:	ASSERT	STRUCT,ds:[0],CT
	test	ds:[CT_STATUS],CTSTAT_ABORT
	jz	i09x
	and	ds:[CT_STATUS],NOT CTSTAT_ABORT
	stc
i09x:	pop	es
	pop	ds
	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
i09z:	jmp	far ptr DDINT_LEAVE
ENDPROC	ddcon_int09

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_int10 (BIOS video services)
;
; Originally, the plan was to ignore apps that issue INT 10h and support only
; "well-behaved" apps that use DOS/CONSOLE interfaces, but we can't ignore the
; INT 10h functions we issue ourselves (like mode changes and scrolls), so we
; now perform BIOS data context switching on all INT 10h calls.
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
DEFPROC	ddcon_int10,far
;
; We preserve the original AX for inspection after the call (but we still
; return the updated AX), and we preserve BP, which has the added benefit of
; fixing an INT 10h "bug" where certain functions would trash BP, and makes
; it easier for this code to access data on the stack.
;
; The BIOS says for INT 10h:
;
;	CS,SS,DS,ES,BX,CX,DX PRESERVED DURING CALL
;	ALL OTHERS DESTROYED
;
; but in fact, SI, DI, and flags are explicitly preserved as well, BP is
; trashed by only a few functions (scroll and graphics read), and virtually
; no other BIOS services alter BP.  So rather than let this odd behavior
; expose us to potential bugs downstream, we preserve BP, too.
;
	push	bp
	push	ax
;
; BIOS locking prevents focus switches and DOS locking prevents session
; switches, both of which are problematic in the middle of certain INT 10h
; operations, especially mode changes and scrolls.  Originally, the scroll
; function issued its own locks, but locking at this level makes that
; unnecessary now.
;
	inc	[bios_lock]
;
; DOSUTIL LOCK has been updated to return the active session's CONSOLE
; context in AX.  However, during system initialization, that context may
; not exist yet.
;
	DOSUTIL	LOCK			; ensure EQUIP_FLAG remains stable
	push	ax			; save the context segment
	test	ax,ax			; is it valid?
	jz	i10a			; no
	push	ds			; yes
	mov	ds,ax			; load it
	call	update_biosdata		; returns current EQUIP_FLAG
	pop	ds

i10a:	push	ax			; save EQUIP_FLAG
	mov	bp,sp
	mov	ax,[bp+4]		; AX = caller's AX
	mov	bp,[bp+6]		; BP = caller's BP

	pushf
	call	[video_int]		; issue the original INT 10h

	mov	bp,sp
	mov	[bp+4],ax		; update AX return value on stack
	mov	ax,[bp+2]		; get the context segment
	test	ax,ax			; is it valid?
	jz	i10x			; no
	push	ds			; yes
	mov	ds,ax			; load it
	mov	ax,[bp]			; AX = EQUIP_FLAG from update_biosdata
	call	update_context
	pop	ds

i10x:	pop	ax			; clean up the stack
	pop	ax			; (eg, ADD SP,4)
	DOSUTIL	UNLOCK
	call	unlock_bios

	pop	ax
	pop	bp
	iret
ENDPROC	ddcon_int10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	dx,[ct_focus]		; for now, use the context with focus
	test	dx,dx
	jnz	i29a
	call	write_char
	jmp	short i29b
i29a:	push	es
	mov	es,dx
	call	write_context
	pop	es
i29b:	pop	dx
	iret
ENDPROC	ddcon_int29

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_packet
;
; Inputs:
;	ES:DI -> DDP
;b4
; Outputs:
;	Carry clear UNLESS the wait has been ABORT'ed
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	add_packet
	cli
	mov	ax,di
	xchg	[wait_ptr].OFF,ax
	mov	es:[di].DDP_PTR.OFF,ax
	mov	ax,es
	xchg	[wait_ptr].SEG,ax
	mov	es:[di].DDP_PTR.SEG,ax
;
; The WAIT condition will be satisfied when enough data is received
; (for a READ packet) or when the context is unpaused (for a WRITE packet).
;
	push	dx
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	DOSUTIL	WAIT
	pop	dx
	sti
	ret
ENDPROC	add_packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; check_hotkey
;
; Check for key combinations considered "hotkeys" by BASIC-DOS; if a hotkey
; is detected, carry is cleared, indicating that a DOSUTIL HOTKEY notification
; should be issued.
;
; For example, CTRLC (and CTRL_BREAK, which we convert to CTRLC) are considered
; hotkeys, so that DOS functions need not "poll" the console to determine if a
; CTRLC has been typed.  Ditto for CTRLP, which DOS likes to use for turning
; "printer echo" on and off.
;
; Another advantage to using HOTKEY notifications is the hotkeys don't get
; buried in the input stream; as soon as they're typed, notification occurs.
;
; This function also includes some internal hotkey checks; eg, CTRLS for
; toggling the console's PAUSE state, and SHIFT-TAB for toggling focus between
; consoles; internal hotkeys do not generate system HOTKEY notifications.
;
; TODO: CTRLC can still get "buried" in a sense: if you fill up the ROM's
; keyboard buffer, the ROM will never add CTRLC, so it's CTRL_BREAK to the
; rescue again.  One alternative is to maintain our own (per console) buffer
; and always suck the ROM's buffer dry; that's better for session focus, but
; there are ripple effects: for example, we would be forced to simulate at
; least some of the ROM BIOS keyboard services then.  An intermediate hack
; would be to always toss the last key whenever the buffer has reached
; capacity, so that there's always room for one more key....
;
; Inputs:
;	CX = focus context, if any
;
; Outputs:
;	If carry clear, AL = hotkey char code, AH = hotkey scan code
;
; Modifies:
;	AX, BX, CX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	check_hotkey
	push	ds
	sub	bx,bx
	mov	ds,bx
	ASSUME	DS:BIOS

	mov	bx,[BUFFER_TAIL]
	cmp	bx,[BUFFER_HEAD]
	je	ch8			; BIOS buffer empty
	sub	bx,2			; rewind the tail
	cmp	bx,offset KB_BUFFER - offset BIOS_DATA
	jae	ch0
	add	bx,size KB_BUFFER
ch0:	mov	ax,[BIOS_DATA][bx]	; AL = char code, AH = scan code
;
; Let's take care of internal hotkeys first (in part because it seems
; unlikely we would want them to affect things like a console's PAUSE state).
;
	cmp	ax,(SCAN_TAB SHL 8)
	jne	ch1
	mov	[BUFFER_TAIL],bx	; update tail, consuming the character
	call	switch_focus
	jmp	short ch8
;
; Do PAUSE checks next, because only CTRLS toggles PAUSE, and everything else
; disables it.
;
ch1:	jcxz	ch4
	push	ds
	mov	ds,cx
	ASSUME	DS:NOTHING
	ASSERT	STRUCT,ds:[0],CT
;
; This is currently the sole use of CTSTAT_INPUT: to avoid treating CTRLS as
; a pause key if the context is waiting for input.  This makes it possible for
; the CONIO buffered input code to use CTRLS for input control as well.
;
	test	ds:[CT_STATUS],CTSTAT_INPUT
	stc
	jnz	ch3
	cmp	al,CHR_CTRLS		; CTRLS?
	jne	ch2			; no (anything else unpauses)
	xor	ds:[CT_STATUS],CTSTAT_PAUSED
	jmp	short ch3
ch2:	test	ds:[CT_STATUS],CTSTAT_PAUSED
	stc
	jz	ch3
	and	ds:[CT_STATUS],NOT CTSTAT_PAUSED
ch3:	pop	ds
	ASSUME	DS:BIOS
	jc	ch4
	cmp	al,CHR_CTRLC
	je	ch5a
	mov	[BUFFER_TAIL],bx	; update tail, consuming the character

ch4:	test	ax,ax			; CTRL_BREAK?
	jnz	ch5
	mov	al,CHR_CTRLC		; yes, map it to CTRLC
	mov	[BIOS_DATA][bx],ax	; in the buffer as well

ch5:	cmp	al,CHR_CTRLC		; CTRLC?
	jne	ch6			; no
ch5a:	mov	[BUFFER_HEAD],bx	; yes, advance the head toward the tail
	jmp	short ch9		; and return carry clear

ch6:	cmp	al,CHR_CTRLP		; CTRLP?
	je	ch9			; yes, return carry clear

ch8:	stc
ch9:	pop	ds
	ret
ENDPROC	check_hotkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_border
;
; Inputs:
;	DS = CONSOLE context
;	If DS matches ct_focus, then a double-wide border will be drawn
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	draw_border
	test	ds:[CT_STATUS],CTSTAT_BORDER
	jz	db9
	mov	ax,ds
	mov	si,offset DBL_BORDER
	cmp	ax,[ct_focus]
	je	db1
	mov	si,offset SGL_BORDER
db1:	sub	dx,dx			; get top left X,Y (DL,DH)
	mov	bx,ds:[CT_CONDIM]	; get bottom right X,Y (BL,BH)
	lods	word ptr cs:[si]
	xchg	cx,ax
	call	draw_vertpair
	ASSUME	ES:NOTHING
	lods	word ptr cs:[si]
	xchg	cx,ax
db2:	inc	dh			; advance Y, holding X constant
	cmp	dh,bh
	jae	db3
	call	draw_vertpair
	jmp	db2
db3:	lods	word ptr cs:[si]
	xchg	cx,ax
	call	draw_vertpair
	lods	word ptr cs:[si]
	xchg	cx,ax
db4:	mov	dh,0
	inc	dx			; advance X, holding Y constant
	cmp	dl,bl
	jae	db9
	call	draw_horzpair
	jmp	db4
db9:	ret
ENDPROC	draw_border

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_char
;
; Inputs:
;	CL = character
;	DX = CURPOS (DL,DH)
;	DS = CONSOLE context
;
; Outputs:
;	Updates cursor position in (DL,DH)
;
; Modifies:
;	AX, DX, DI, ES
;
DEFPROC	draw_char
	push	cx
	mov	ch,1			; CH = amount to advance DL
	cmp	cl,CHR_BACKSPACE
	jne	dc1
;
; This code treats CHR_BACKSPACE as a "destructive" backspace (ie, erasing
; the character underneath the cursor first), which means changing CL to
; CHR_SPACE and not advancing DL afterward.  That is done primarily as an
; optimization for the DOS CONIO functions, which would otherwise have to
; output 3 characters (backspace, space, backspace again) to do the same thing.
;
	mov	cl,CHR_SPACE		; make this "destructive"
	dec	ch			; no advance for backspace
	dec	dl
	cmp	dl,ds:[CT_CURMIN].LOB
	jge	dc1
	mov	dl,ds:[CT_CURMAX].LOB
	dec	dh
	cmp	dh,ds:[CT_CURMIN].HIB
	jge	dc1
	mov	dx,ds:[CT_CURMIN]

dc1:	mov	ah,ds:[CT_COLOR].LOB	; AH = attributes
	call	write_curpos		; write CL at (DL,DH)
;
; Advance DL, advance DH as needed, and scroll the context as needed.
;
	add	dl,ch			; advance DL
	pop	cx

	cmp	dl,ds:[CT_CURMAX].LOB
	jle	dc9
	mov	dl,ds:[CT_CURMIN].LOB

	DEFLBL	draw_linefeed,near
	inc	dh
	cmp	dh,ds:[CT_CURMAX].HIB
	jle	dc9
	dec	dh
	push	cx
	mov	cl,1
	call	scroll			; scroll the context up 1 line
	pop	cx
dc9:	ret
ENDPROC	draw_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_cursor
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	draw_cursor
	mov	dx,ds:[CT_CURPOS]
	call	get_curpos		; BX = screen offset for CURPOS
	add	bx,ds:[CT_SCREEN].OFF	; add the context's buffer offset

	DEFLBL	set_cursor,near
	shr	bx,1			; screen offset to cell offset
	mov	ah,CRTC_CURHI		; AH = 6845 CURSOR ADDR (HI) register
	call	write_crtc16		; update cursor position using BX
	ret
ENDPROC	draw_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_horzpair
;
; Inputs:
;	CH = top char
;	CL = bottom char
;	DL,DH = top X,Y
;	BL,BH = bottom X,Y
;	DS = CONSOLE context
;
; Modifies:
;	DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	draw_horzpair
	mov	ah,ds:[CT_COLOR].HIB
	xchg	cl,ch
	call	write_curpos
	xchg	cl,ch
	xchg	dh,bh
	call	write_curpos
	xchg	dh,bh
	ret
ENDPROC	draw_horzpair

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; draw_vertpair
;
; Inputs:
;	CH = left char
;	CL = right char
;	DL,DH = left X,Y
;	BL,BH = right X,Y
;	DS = CONSOLE context
;
; Modifies:
;	DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	draw_vertpair
	mov	ah,ds:[CT_COLOR].HIB
	xchg	cl,ch
	call	write_curpos
	xchg	dl,bl
	xchg	cl,ch
	call	write_curpos
	xchg	dl,bl
	ret
ENDPROC	draw_vertpair

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_curpos
;
; Inputs:
;	DX = CURPOS (DL,DH)
;
; Outputs:
;	BX -> screen buffer offset
;
; Modifies:
;	BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_curpos
	push	ax
	mov	al,dh
	mul	[max_cols]
	add	ax,ax			; AX = offset to row
	sub	bx,bx
	mov	bl,dl
	add	bx,bx
	add	bx,ax			; BX = offset to row and col
	pop	ax
	ret
ENDPROC	get_curpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hide_cursor
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	hide_cursor
	mov	bx,ds:[CT_SCROFF]
	jmp	set_cursor
ENDPROC	hide_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; move_cursor
;
; Inputs:
;	DS = CONSOLE context
;	CX = +/- position delta
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	move_cursor
	mov	dx,ds:[CT_CURPOS]	; DX = current cursor position
	xchg	ax,cx
	idiv	ds:[CT_CURDIM].LOB	; AL = # lines, AH = # columns (signed)

mc1:	add	dh,al
	cmp	dh,ds:[CT_CURMIN].HIB
	jge	mc1a
	mov	dh,ds:[CT_CURMIN].HIB
mc1a:	cmp	dh,ds:[CT_CURMAX].HIB
	jle	mc2
	mov	dh,ds:[CT_CURMAX].HIB

mc2:	add	dl,ah
	cmp	dl,ds:[CT_CURMIN].LOB
	jge	mc2a
	add	dl,ds:[CT_CURMAX].LOB
	inc	dl
	sub	dl,ds:[CT_CURMIN].LOB
	cmp	dh,ds:[CT_CURMIN].HIB
	jle	mc2a
	dec	dh

mc2a:	cmp	dl,ds:[CT_CURMAX].LOB
	jle	mc8
	sub	dl,ds:[CT_CURMAX].LOB
	dec	dl
	add	dl,ds:[CT_CURMIN].LOB
	cmp	dh,ds:[CT_CURMAX].HIB
	jge	mc8
	inc	dh

	DEFLBL	update_cursor,near
mc8:	mov	ds:[CT_CURPOS],dx
	mov	ax,ds
	cmp	ax,[ct_focus]		; does this context have focus?
	jne	mc9			; no, leave cursor alone
	call	draw_cursor
mc9:	clc
	ret
ENDPROC	move_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_kbd
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if request satisfied, set if not
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_kbd
	push	bx
	push	ds

pl1:	sub	bx,bx
	mov	ds,bx
	ASSUME	DS:BIOS
	cli
	mov	bx,[BUFFER_HEAD]
	cmp	bx,[BUFFER_TAIL]
	stc
	je	pl3			; BIOS buffer empty
	mov	ax,[BIOS_DATA][bx]	; AL = char code, AH = scan code
	add	bx,2
	cmp	bx,offset KB_BUFFER - offset BIOS_DATA + size KB_BUFFER
	jne	pl2
	sub	bx,size KB_BUFFER
pl2:	mov	[BUFFER_HEAD],bx
	clc
pl3:	sti
	jc	pl9

	test	al,al			; ASCII zero?
	jz	pl4			; yes, must be a special-function key
	cmp	al,0E0h			; ditto for E0h, which future keyboards
	jne	pl7			; may generate....
;
; Perform our own non-ASCII special-function key to control-character mappings
; now, using the scan code in AH.  If there's no mapping, we end up returning
; a zero ASCII code.
;
; TODO: Add support for reading "raw" keys.  For now, if a non-ASCII key has
; no mapping, it can't be detected.
;
pl4:	push	si
	mov	si,offset SCAN_MAP
pl5:	lods	byte ptr cs:[si]
	test	al,al			; end of SCAN_MAP?
	jz	pl6			; yes
	cmp	ah,al			; scan code match?
	lods	byte ptr cs:[si]
	jne	pl5			; no
pl6:	pop	si

pl7:	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	ASSUME	DS:NOTHING
	mov	[bx],al
	IFDEF MAXDEBUG
	test	al,al
	jnz	pl8
	xchg	al,ah
	DPRINTF	'k',<"null character, scan code %#04x\r\n">,ax
	ENDIF
pl8:	inc	bx
	mov	es:[di].DDPRW_ADDR.OFF,bx
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	pl1			; no
	clc

pl9:	pop	ds
	ASSUME	DS:NOTHING
	pop	bx
	ret
ENDPROC	pull_kbd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scroll
;
; Set CL to +/- lines to scroll.  To clear the entire interior, set
; CL >= # lines (eg, 100).  To clear the entire context, including any
; border, set CL to zero (typically only done when destroying a context).
;
; Inputs:
;	CL = # lines
;	DS = CONSOLE context
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	scroll
	push	bx
	push	cx
	push	dx
	xchg	ax,cx			; AL = # lines now
	mov	cx,ds:[CT_CONPOS]
	mov	dx,cx
	test	al,al			; zero?
	jnz	scr0			; no
	add	dx,ds:[CT_CONDIM]	; yes, clear entire context
	jmp	short scr2		; (including border, if any)
scr0:	cmp	al,ds:[CT_CONDIM].HIB
	jl	scr1
	mov	al,0			; zero tells BIOS to clear all lines
scr1:	add	cx,ds:[CT_CURMIN]	; CH = row, CL = col of upper left
	add	dx,ds:[CT_CURMAX]	; DH = row, DL = col of lower right
scr2:	mov	bh,ds:[CT_COLOR].LOB	; BH = fill attributes
	mov	ah,VIDEO_SCROLL		; scroll up # lines in AL
	int	INT_VIDEO
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	scroll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_curtype
;
; Sets the hardware cursor to the current type (ie, shape).
;
; Inputs:
;	DS = CONSOLE context
;
; Modifies:
;	AX, CX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_curtype
;
; While the following code works just fine (aside from modifying slightly
; different registers), it's better to use the BIOS, because it turns out
; later BIOSes will perform cursor emulation, which automatically converts
; CGA-based cursor sizes (0-7) to higher-res values.
;
	; mov	bx,ds:[CT_CURTYPE]	; BX = new values
	; mov	ah,CRTC_CURTOP		; AH = 6845 register #
	; jmp	write_crtc16		; write them
;
; Unfortunately, when we call the BIOS here, we are NOT necessarily running
; in the session for which the call is intended.  When we're called from
; ddcon_setins, we are, but when we're called from show_cursor, which is
; called from switch_focus, we may not be.
;
; The simplest solution is to call update_biosdata and then invoke the
; original INT 10h code, bypassing ddcon_int10.  Be aware that this will be
; required for any video BIOS call made on behalf of a context that is not
; ALSO the running context.
;
	call	update_biosdata
	mov	cx,ds:[CT_CURTYPE]
	mov	ah,VIDEO_SETCTYPE
	pushf
	call	[video_int]
	ret
ENDPROC	set_curtype

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; show_cursor
;
; Wrapper for draw_cursor and set_curtype (used when switching focus).
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	show_cursor
	call	draw_cursor
	jmp	set_curtype
ENDPROC	show_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; switch_focus
;
; Switch focus to the next console context in our chain.
;
; This is called from check_hotkey, which is called at interrupt time, as
; well as whenever the bios_lock is released with a switch request pending.
;
; Inputs:
;	CX = focus context, if any
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	switch_focus
;
; If bios_lock is set, then the switch must be deferred until the lock
; is released.  It may well be that there's no context to switch TO, but
; it's cheaper to defer now and ask questions later.
;
	cmp	[bios_lock],0
	je	switch_now
	inc	[req_switch]
	jmp	short sf9

	DEFLBL	switch_now,near
	push	cx
	push	si
	push	di
	push	ds
	DOSUTIL	LOCK			; lock the current session
	push	es
	jcxz	sf8			; nothing to do
	mov	ds,cx
	ASSERT	STRUCT,ds:[0],CT
	mov	cx,ds:[CT_NEXT]
	jcxz	sf1
	jmp	short sf2
sf1:	mov	cx,[ct_head]
	cmp	cx,[ct_focus]
	je	sf8			; nothing to do
sf2:	xchg	cx,[ct_focus]
	mov	ds,cx
	call	draw_border		; redraw the border and hide
	call	hide_cursor		; the cursor of the outgoing context
	mov	ds,[ct_focus]
	call	draw_border		; redraw the border and show
	call	show_cursor		; the cursor of the incoming context
sf8:	pop	es
	DOSUTIL	UNLOCK
	pop	ds
	pop	di
	pop	si
	pop	cx
sf9:	ret
ENDPROC	switch_focus

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; unlock_bios
;
; While locking is as simple as incrementing bios_lock, unlocking requires
; decrementing, checking for an unlocked (zero) state, and then checking for
; any pending switch requests.
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	unlock_bios
	dec	[bios_lock]		; BIOS unlocked now?
	jnz	ub9			; no
	mov	al,0
	xchg	[req_switch],al
	test	al,al			; pending switch request?
	jz	ub9			; no
	push	bx
	push	cx
	push	dx
	mov	cx,[ct_focus]		; CX = context
	call	switch_now		; perform the requested switch now
	pop	dx
	pop	cx
	pop	bx
ub9:	ret
ENDPROC	unlock_bios

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_biosdata
;
; Called whenever the BIOS data should be updated to reflect current context
; state.  The main benefit is improved compatibility with apps that bypass our
; services (ie, access the BIOS directly).
;
; Inputs:
;	DS = CONSOLE context
;
; Outputs:
;	AX = previous EQUIP_FLAG
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	update_biosdata
	push	es
	sub	ax,ax
	mov	es,ax
	ASSUME	ES:BIOS
	ASSERT	STRUCT,ds:[0],CT

	mov	al,ds:[CT_MODE]
	xchg	[CRT_MODE],al
	mov	ds:[CTS_MODE],al

	mov	ax,ds:[CT_COLS]
	xchg	[CRT_COLS],ax
	mov	ds:[CTS_COLS],ax

	mov	ax,ds:[CT_PORT]
	xchg	[ADDR_6845],ax
	mov	ds:[CTS_PORT],ax

	mov	ax,ds:[CT_CURTYPE]
	xchg	[CURSOR_MODE],ax
	mov	ds:[CTS_CURTYPE],ax

	mov	ax,ds:[CT_CURPOS]	; AX = cursor pos within context
	add	ax,ds:[CT_CONPOS]	; add context pos to get screen pos
	mov	[CURSOR_POSN],ax

	mov	ax,ds:[CT_EQUIP]
	xchg	[EQUIP_FLAG],ax
	pop	es
	ret
ENDPROC	update_biosdata

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_context
;
; This is the reverse of update_biosdata.
;
; Inputs:
;	DS = CONSOLE context
;	AX = previous EQUIP_FLAG
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	update_context
	push	es
	mov	es,[ZERO]
	ASSUME	ES:BIOS
	mov	[EQUIP_FLAG],ax

	mov	al,ds:[CTS_MODE]
	xchg	[CRT_MODE],al
	mov	ds:[CT_MODE],al

	mov	ax,ds:[CTS_COLS]
	xchg	[CRT_COLS],ax
	mov	ds:[CT_COLS],ax

	mov	ax,ds:[CTS_PORT]
	mov	[ADDR_6845],ax

	; mov	ax,[CURSOR_MODE]	; we don't trust CURSOR_MODE
	; mov	ds:[CT_CURTYPE],ax	; update_curtype explains why

	mov	ax,[CURSOR_POSN]
	sub	ax,ds:[CT_CONPOS]
	mov	ds:[CT_CURPOS],ax
	pop	es
	ret
ENDPROC	update_context

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_curtype
;
; Due to a bug in the original IBM PC (5150) BIOS, the initial cursor top and
; bottom scan lines are stored in the high and low *nibbles* of CURSOR_MODE.LOB
; instead of the high and low *bytes* of CURSOR_MODE.  Here's the buggy code:
;
;	F177:	C70660006700	MOV	CURSOR_MODE,67H
;
; So, we'll check for that combo (ie, 67h low, 00h high) and compensate.
;
; What's worse is that the same initial values (6,7) are stored in CURSOR_MODE
; for the MDA as well, even though the MDA's defaults are different (11,12),
; and this behavior seems to be true regardless of BIOS revision.  Bummer.
;
; Inputs:
;	ES = BIOS
;
; Outputs:
;	AX = cursor type (AH = top scanline, AL = bottom scanline)
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:BIOS, SS:NOTHING
DEFPROC	update_curtype
	mov	ax,[CURSOR_MODE]
	cmp	ax,0067h		; buggy cursor scanline values?
	jne	uct1			; no
	mov	ax,0607h		; yes, fix them
uct1:	cmp	[ADDR_6845].LOB,0B4h	; MDA?
	jne	uct2			; no
	cmp	ax,0607h		; bogus values for MDA?
	jne	uct2			; no
	mov	ax,0B0Ch		; yes, fix them
uct2:	mov	[CURSOR_MODE],ax
	ret
ENDPROC	update_curtype

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_char
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
DEFPROC	write_char
	push	ax
	push	bx
	mov	bh,0
	mov	ah,VIDEO_TTYOUT
	int	INT_VIDEO
	pop	bx
	pop	ax
	ret
ENDPROC	write_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_context
;
; Inputs:
;	AL = character
;	ES = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	write_context
	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	push	ds
	push	es
	push	es
	pop	ds			; DS is now the context
;
; Check for special characters first.
;
	mov	cx,ax			; CL = character
	mov	dx,ds:[CT_CURPOS]

	cmp	al,CHR_RETURN		; RETURN?
	jne	wc1			; no
	mov	dl,ds:[CT_CURMIN].LOB	; yes
	jmp	short wc8

wc1:	cmp	al,CHR_LINEFEED		; LINEFEED?
	je	wc6			; yes

	cmp	al,CHR_TAB		; TAB?
	je	wc4			; yes

	cmp	al,CHR_BACKSPACE	; BACKSPACE?
	je	wc7			; yes

	cmp	al,CHR_SPACE		; CONTROL character?
	jae	wc7			; no

	push	cx			; yes
	mov	cl,'^'
	call	draw_char
	pop	cx
	add	cl,'A'-1
	jmp	short wc7

wc4:	mov	bl,dl			; emulate a (horizontal) TAB
	sub	bl,ds:[CT_CURMIN].LOB
	and	bl,07h
	neg	bl
	add	bl,8
	mov	cl,CHR_SPACE
wc5:	call	draw_char
	cmp	dl,ds:[CT_CURMIN].LOB	; did the column wrap back around?
	jle	wc8			; yes, stop
	dec	bl
	jnz	wc5
	jmp	short wc8

wc6:	call	draw_linefeed		; emulate a LINEFEED
	jmp	short wc8

wc7:	call	draw_char		; draw character (CL) at CURPOS (DL,DH)

wc8:	call	update_cursor		; set CURPOS to (DL,DH)

wc9:	pop	es
	pop	ds
	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	write_context

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_curpos
;
; Inputs:
;	AH = attributes
;	CL = character
;	DX = CURPOS (DL,DH)
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AL, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	write_curpos
	push	bx
	push	dx
	les	di,ds:[CT_SCREEN]	; ES:DI -> screen location
	call	get_curpos		; BX = screen offset for CURPOS
	mov	dx,ds:[CT_PORT]
	ASSERT	Z,<cmp dh,03h>
	cmp	dl,0B4h			; monochrome adapter?
	je	wcp3			; yes, don't worry about horz retrace
	add	dl,6			; DX = status port
wcp1:	in	al,dx
	test	al,01h
	jnz	wcp1			; loop until we're OUTSIDE horz retrace
	cli
wcp2:	in	al,dx
	test	al,01h
	jz	wcp2			; loop until we're INSIDE horz retrace
wcp3:	mov	al,cl
	mov	es:[di+bx],ax		; "write" the character and attributes
	sti
	pop	dx
	pop	bx
	ret
ENDPROC	write_curpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_crtc16
;
; Inputs:
;	AH = 6845 register #
;	BX = 16-bit value to write
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	write_crtc16
	cli
	mov	al,bh
	call	write_crtc8
	inc	ah
	mov	al,bl
	call	write_crtc8
	sti
	ret
ENDPROC	write_crtc16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_crtc8
;
; Inputs:
;	AH = 6845 register #
;	AL = 8-bit value to write
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	DX
;
DEFPROC	write_crtc8
	mov	dx,ds:[CT_PORT]
	ASSERT	Z,<cmp dh,03h>
	xchg	al,ah
	out	dx,al			; select 6845 register
	inc	dx
	xchg	al,ah
	out	dx,al			; output AL
	ret
ENDPROC	write_crtc8

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
DEFPROC	ddcon_init,far
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS

	mov	ax,[EQUIP_FLAG]		; AX = EQUIP_FLAG
	mov	es:[bx].DDPI_END.OFF,offset ddcon_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddcon_req
;
; Determine what kind of video console we're dealing with (MONO or COLOR)
; and what the frame buffer segment is.
;
	mov	dx,0B000h
	and	ax,EQ_VIDEO_MODE
	cmp	ax,EQ_VIDEO_MONO
	je	ddn1
	mov	dx,0B800h
ddn1:	mov	[frame_seg],dx
;
; Install an INT 09h hardware interrupt handler, which we'll use to detect
; keys added to the BIOS keyboard buffer.
;
	cli
	mov	ax,offset ddcon_int09
	xchg	ds:[INT_HW_KBD * 4].OFF,ax
	mov	[kbd_int].OFF,ax
	mov	ax,cs
	xchg	ds:[INT_HW_KBD * 4].SEG,ax
	mov	[kbd_int].SEG,ax
	sti
;
; Install an INT 10h services handler to reflect context data into BIOS data.
;
	mov	ax,offset ddcon_int10
	xchg	ds:[INT_VIDEO * 4].OFF,ax
	mov	[video_int].OFF,ax
	mov	ax,cs
	xchg	ds:[INT_VIDEO * 4].SEG,ax
	mov	[video_int].SEG,ax
;
; Install an INT 29h ("FAST PUTCHAR") handler; I think traditionally DOS
; installed its own handler, but that's really our responsibility, especially
; if we want all INT 29h I/O to go through the "system console" -- which for
; now is nothing more than whichever console was opened first.
;
	mov	ds:[INT_FASTCON * 4].OFF,offset ddcon_int29
	mov	ds:[INT_FASTCON * 4].SEG,cs
	ret
ENDPROC	ddcon_init

CODE	ends

DATA	segment para public 'DATA'

ddcon_end	db	16 dup(0)

DATA	ends

	end
