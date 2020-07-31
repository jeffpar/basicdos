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
CON	DDH	<offset DEV:ddcon_end+16,,DDATTR_STDIN+DDATTR_STDOUT+DDATTR_OPEN+DDATTR_CHAR,offset ddcon_init,-1,20202020204E4F43h>

	DEFLBL	CMDTBL,word
	dw	ddcon_none,   ddcon_none,   ddcon_none,   ddcon_ioctl	; 0-3
	dw	ddcon_read,   ddcon_none,   ddcon_none,   ddcon_none	; 4-7
	dw	ddcon_write,  ddcon_none,   ddcon_none,   ddcon_none	; 8-11
	dw	ddcon_none,   ddcon_open,   ddcon_close			; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	IOCTBL,word
	dw	ddcon_none,   ddcon_getpos, ddcon_getlen,  ddcon_movcur	; 0-3
	dw	ddcon_setins, ddcon_scroll, ddcon_setcolor		; 4-6
	DEFABS	IOCTBL_SIZE,<($ - IOCTBL) SHR 1>

	DEFLBL	CON_PARMS,word
	dw	80,16,80, 25,4,25, 0,0,79, 0,0,24, 0,0,1, 0,0,1

	DEFLBL	DBL_BORDER,word
	dw	0C9BBh,0BABAh,0C8BCh,0CDCDh

	DEFLBL	SGL_BORDER,word
	dw	0DABFh,0B3B3h,0C0D9h,0C4C4h

	DEFLBL	SCAN_MAP,byte
	db	SCAN_F1,CHR_CTRLD,SCAN_RIGHT,CHR_CTRLD
	db	SCAN_F3,CHR_CTRLE,SCAN_UP,CHR_CTRLE
	db	SCAN_LEFT,CHR_CTRLS,SCAN_DEL,CHR_DEL
	db	SCAN_DOWN,CHR_CTRLX,SCAN_INS,CHR_CTRLV
	db	SCAN_HOME,CHR_CTRLA,SCAN_END,CHR_CTRLF
	db	0

	DEFWORD	ct_head,0	; head of context chain
	DEFWORD	ct_focus,0	; segment of context with focus
	DEFWORD	frame_seg,0
	DEFBYTE	max_rows,25	; TODO: use this for something...
	DEFBYTE	max_cols,80	; TODO: set to correct value in ddcon_init

	DEFPTR	kbd_int,0	; original keyboard hardware interrupt handler
	DEFPTR	wait_ptr,-1	; chain of waiting packets
;
; A context of "80,25,0,0,1" requests a border, so logical cursor positions
; are 1,1 to 78,23.  Physical character and cursor positions will be adjusted
; by the offset address in CT_SCREEN.
;
CONTEXT		struc
CT_NEXT		dw	?	; 00h: segment of next context, 0 if end
CT_STATUS	db	?	; 02h: context status bits (CTSTAT_*)
CT_RESERVED	db	?	; 03h: (holds CTSIG in DEBUG builds)
CT_CONDIM	dw	?	; 04h: eg, context dimensions (0-based)
CT_CONPOS	dw	?	; 06h: eg, context position (X,Y) of top left
CT_CURPOS	dw	?	; 08h: eg, cursor X (lo) and Y (hi) position
CT_CURMIN	dw	?	; 0Ah: eg, cursor X (lo) and Y (hi) minimums
CT_CURMAX	dw	?	; 0Ch: eg, cursor X (lo) and Y (hi) maximums
CT_CURDIM	dw	?	; 0Eh: width and height (for cursor movement)
CT_EQUIP	dw	?	; 10h: BIOS equipment flags (snapshot)
CT_PORT		dw	?	; 12h: eg, 3D4h
CT_SCROFF	dw	?	; 14h: eg, 2000 (offset of off-screen memory)
CT_SCREEN	dd	?	; 16h: eg, B800:00A2h
CT_BUFFER	dd	?	; 1Ah: used only for background contexts
CT_BUFLEN	dw	?	; 1Eh: eg, 4000 for a full-screen 25*80*2 buffer
CT_COLOR	dw	?	; 20h: fill (LO) and border (HI) attributes
CONTEXT		ends

CTSIG		equ	'C'

CTSTAT_BORDER	equ	01h	; context has border
CTSTAT_ADAPTER	equ	02h	; alternate adapter selected
CTSTAT_INPUT	equ	40h	; context is waiting for input
CTSTAT_PAUSED	equ	80h	; context is paused (triggered by CTRLS hotkey)

;
; CRT Controller Registers
;
CRTC_CURTOP	equ	0Ah	; cursor top (mirrored at CURSOR_MODE.HI)
CRTC_CURBOT	equ	0Bh	; cursor bottom (mirrored at CURSOR_MODE.LO)
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
	mov	bl,es:[di].DDP_UNIT
	sub	bl,IOCTL_CON
	mov	dx,es:[di].DDP_CONTEXT
	test	dx,dx
	jz	dio0
	mov	ds,dx
	ASSUME	DS:NOTHING
	cmp	bl,IOCTBL_SIZE
	jb	dio1
dio0:	mov	bl,0
dio1:	mov	bh,0
	add	bx,bx
	mov	cx,es:[di].DDPRW_LENGTH
	call	IOCTBL[bx]
	jc	dio9
dio7:	mov	es:[di].DDP_CONTEXT,dx	; return pos or length in packet context
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dio9:	ret
ENDPROC	ddcon_ioctl

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
;	CX = DDPRW_LENGTH (starting cursor position; see IOCTL_GETPOS)
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
	mov	bx,es:[di].DDPRW_LBA	; BX = starting cursor position
	add	bx,ds:[CT_CURMIN]	; zero-based, so adjust to our mins
	sub	dx,dx			; DL = current len, DH = previous len
	mov	ah,ds:[CT_CURMAX].LO	; AH = column max
	mov	bh,ds:[CT_CURMIN].LO	; BH = column min
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
;	CX = DDPRW_LENGTH (+/- columns to move cursor horizontally)
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
; Inputs:
;	ES:DI -> DDPRW
;	CX = DDPRW_LENGTH (0 to clear insert mode, 1 to set)
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
	push	es
	sub	ax,ax
	mov	es,ax
	ASSUME	ES:BIOS
;
; There was a bug in the original IBM PC (5150) BIOS: it stored the cursor's
; top and bottom scan lines in the high and low *nibbles* of CURSOR_MODE.LO,
; respectively, instead of the high and low *bytes* of CURSOR_MODE.
;
;	F177:	C70660006700	MOV	CURSOR_MODE,67H
;
; So, we'll check for that combo (ie, 67h low, 00h high) and compensate.
;
; What's worse is that the same values (6,7) are stored in CURSOR_MODE for the
; MDA as well, even though the MDA's default values are different (11,12);
; and this behavior seems to be true regardless of BIOS revision.  Bummer.
;
	mov	ax,[CURSOR_MODE]
	cmp	ax,0067h		; buggy cursor scanline values?
	jne	dsi0			; no
	mov	ax,0607h		; yes, fix them
dsi0:	cmp	byte ptr ds:[CT_PORT],0B4h
	jne	dsi1			; not an MDA
	cmp	ax,0607h		; bogus values for MDA?
	jne	dsi1			; no
	mov	ax,0B0Ch		; yes, fix them
dsi1:	ror	cl,1			; move CL bit 0 to bit 7 (and carry)
	jnc	dsi2
	and	ah,0E0h
dsi2:	xchg	bx,ax			; BX = new values
	mov	ah,CRTC_CURTOP		; AH = 6845 register #
	call	write_crtc16		; write them
;
; We don't mirror the cursor scanline changes in CURSOR_MODE, because we
; want to restore the original values when insert mode ends.  We do, however,
; toggle INS_STATE (80h) in KB_FLAG, to avoid any unanticipated keyboard BIOS
; side-effects; we rely almost entirely on the BIOS for keyboard processing,
; whereas we rely very little on the BIOS for screen updates (scroll calls and
; dual monitor mode sets are the main exceptions).
;
	mov	dl,[KB_FLAG]
	mov	al,dl
	and	al,7Fh
	or	al,cl
	mov	[KB_FLAG],al		; update keyboard insert mode
	rol	dl,1
	and	dx,1
	pop	es
	ret
ENDPROC	ddcon_setins

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_scroll
;
; Inputs:
;	ES:DI -> DDPRW
;	CX = DDPRW_LENGTH (+/- lines to scroll, 0 to clear)
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_scroll
	test	cx,cx
	jnz	dcs1
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
; ddcon_setcolor
;
; Inputs:
;	ES:DI -> DDPRW
;	CL = fill attributes (from DDPRW_LENGTH.LO)
;	CH = border attributes (from DDPRW_LENGTH.HI)
;	DS = CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_setcolor
	mov	ds:[CT_COLOR],cx
	ret
ENDPROC	ddcon_setcolor

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
	jcxz	dcr9

	cli
	call	pull_kbd
	jnc	dcr9
;
; For READ requests that cannot be satisifed, we add this packet to an
; internal chain of "reading" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	mov	ds,es:[di].DDP_CONTEXT
	ASSUME	DS:NOTHING
	ASSERT	STRUCT,ds:[0],CT
	or	ds:[CT_STATUS],CTSTAT_INPUT

	call	add_packet
dcr9:	sti

	mov	es:[di].DDP_STATUS,DDSTAT_DONE
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
	jcxz	dcw9

	lds	si,es:[di].DDPRW_ADDR
	ASSUME	DS:NOTHING
	mov	dx,es:[di].DDP_CONTEXT
	test	dx,dx
	jnz	dcw2

dcw1:	lodsb
	call	write_char
	loop	dcw1
	jmp	short dcw9

dcw2:	push	es
	mov	es,dx
dcw3:	test	es:[CT_STATUS],CTSTAT_PAUSED
	jz	dcw4
;
; For WRITE requests that cannot be satisifed, we add this packet to an
; internal chain of "writing" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	pop	es			; ES:DI -> packet again
	mov	es:[di].DDPRW_LENGTH,cx
	mov	es:[di].DDPRW_ADDR.OFF,si
	call	add_packet
	jmp	dcw2			; when this returns, try writing again

dcw4:	lodsb
	call	write_context
	loop	dcw3
	pop	es

dcw9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcon_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_open
;
; The format of the optional context descriptor is:
;
;	[device]:[cols],[rows],[x],[y],[border],[adapter]
;
; where [device] is "CON" (otherwise you wouldn't be here), [cols] is number of
; columns (up to 80), [rows] is number of rows (up to 25), [x] and [y] are the
; top-left row and col of the context, [border] is 1 for a border or 0 for none,
; and [adapter] is the adapter #, in case there is more than one video adapter
; (adapter 0 is the default).
;
; Obviously, future hardware (imagine an ENHANCED Graphics Adapter, for example)
; will be able to support more rows and other features, but we're designing
; exclusively for the MDA and CGA for now.
;
; Inputs:
;	ES:DI -> DDP
;	[DDP].DDP_PTR -> context descriptor (eg, "CON:80,25")
;
; Outputs:
;
; Notes:
;	We presume that the current SCB is locked for duration of this call;
;	if that presumption ever proves false, then use the DOS_UTL_LOCK API.
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_open
	push	di
	push	es

	push	ds
	lds	si,es:[di].DDP_PTR
	ASSUME	DS:NOTHING
;
; We know that DDP_PTR must point to a string containing "CON:" at the
; very least, so we skip those 4 bytes.
;
	add	si,4			; DS:SI -> parms
	push	cs
	pop	es
	mov	bl,10			; use base 10
	mov	di,offset CON_PARMS	; ES:DI -> parm defaults/limits
	mov	ax,DOS_UTL_ATOI16
	int	21h			; updates SI, DI, and AX
	mov	cl,al			; CL = cols
	mov	ax,DOS_UTL_ATOI16
	int	21h
	mov	ch,al			; CH = rows
	mov	ax,DOS_UTL_ATOI16
	int	21h
	mov	dl,al			; DL = starting col
	mov	ax,DOS_UTL_ATOI16
	int	21h
	mov	dh,al			; DH = starting row
	mov	ax,DOS_UTL_ATOI16
	int	21h
	mov	bh,al			; BH = border (0 for none)
	ASSERT	CTSTAT_BORDER,EQ,01h
	mov	ax,DOS_UTL_ATOI16
	int	21h
	shl	al,1
	or	bh,al			; BH includes adapter bit, too
	ASSERT	CTSTAT_ADAPTER,EQ,02h
	pop	ds
	ASSUME	DS:CODE

	push	bx
	mov	bx,(size CONTEXT + 15) SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	INT_DOSFUNC
	pop	bx
	jnc	dco1
	jmp	dco7

dco1:	mov	ds,ax
	ASSUME	DS:NOTHING
	DBGINIT	STRUCT,ds:[0],CT

	cmp	[ct_focus],0
	jne	dco1a
	mov	[ct_focus],ax

dco1a:	xchg	[ct_head],ax
	mov	ds:[CT_NEXT],ax
	mov	ds:[CT_STATUS],bh
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
; but now that we're clearing interior below, seems best to use a default.
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
	mov	cx,[EQUIP_FLAG]		; snapshot the equipment flags
	mov	dx,[ADDR_6845]		; get the adapter's port address
	test	bh,CTSTAT_ADAPTER
	jz	dco5
	xor	dx,0060h		; convert 3D4h to 3B4h (or vice versa)
	xor	ax,0800h		; convert B800h to B000h (or vice versa)
	push	ax
	xor	cl,EQ_VIDEO_CO40
	mov	al,07h
	cmp	dl,0B4h
	je	dco4
	mov	al,03h
dco4:	xchg	[EQUIP_FLAG],cx
	mov	ah,VIDEO_SETMODE
	int	INT_VIDEO
	xchg	[EQUIP_FLAG],cx
	pop	ax
dco5:	mov	ds:[CT_PORT],dx
	mov	ds:[CT_EQUIP],cx
	mov	ds:[CT_SCREEN].SEG,ax
	call	draw_border		; draw the context's border, if any
	mov	cl,100
	call	scroll			; clear the context's interior
	call	hide_cursor		; important when using an alt adapter
	clc
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
	cmp	[ct_focus],cx
	jne	dcc0
	call	focus_next
	ASSERT	NZ,<cmp [ct_focus],cx>
;
; Remove the context from our chain
;
dcc0:	xchg	ax,cx			; AX = context to free
	push	es
	push	ds
	mov	bx,offset ct_head	; DS:BX -> 1st context
dcc1:	mov	cx,[bx].CT_NEXT
	ASSERT	NZ,<test cx,cx>
	jcxz	dcc2			; context not found
	cmp	cx,ax
	je	dcc2
	mov	ds,cx
	ASSUME	DS:NOTHING
	sub	bx,bx			; DS:BX -> next context
	jmp	dcc1			; keep looking
dcc2:	mov	es,ax
	mov	cx,es:[CT_NEXT]		; move this context's CT_NEXT
	mov	[bx].CT_NEXT,cx		; to the previous context's CT_NEXT
	mov	ds,ax
	mov	cl,0			; clear the entire context
	call	scroll
	pop	ds
	ASSUME	DS:CODE
;
; We are now free to free the context segment in ES
;
dcc3:	mov	ah,DOS_MEM_FREE
	int	INT_DOSFUNC
	pop	es

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
	pushf
	call	[kbd_int]
	jnc	ddi0			; carry set if DOS isn't ready
	jmp	ddi9x

ddi0:	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	push	ds
	push	es

	sti
	mov	cx,[ct_focus]		; CX = context
	call	check_hotkey
	jc	ddi1
	xchg	dx,ax			; DL = char code, DH = scan code
	mov	ax,DOS_UTL_HOTKEY	; notify DOS
	int	21h

ddi1:	mov	ds,cx			; DS = context
	mov	cx,cs
	mov	es,cx
	mov	bx,offset wait_ptr	; CX:BX -> ptr
	les	di,es:[bx]		; ES:DI -> packet, if any
	ASSUME	ES:NOTHING

ddi2:	cmp	di,-1			; end of chain?
	je	ddi9			; yes

	ASSERT	STRUCT,es:[di],DDP

	mov	dx,ds
	cmp	es:[di].DDP_CONTEXT,dx	; packet from console with focus?
	jne	ddi6			; no

	cmp	es:[di].DDP_CMD,DDC_READ; READ packet?
	je	ddi3			; yes, look for keyboard data
;
; For WRITE packets (which we'll assume this is for now), we need to end the
; wait if the context is no longer paused (ie, check_hotkey may have unpaused).
;
	ASSERT	STRUCT,ds:[0],CT
	test	ds:[CT_STATUS],CTSTAT_PAUSED
	jz	ddi4			; yes, we're no longer paused
	jmp	short ddi6		; still paused, check next packet

ddi3:	call	pull_kbd		; pull keyboard data
	jc	ddi6			; not enough data, check next packet
;
; Notify DOS that this packet is done waiting.
;
ddi4:	and	ds:[CT_STATUS],NOT CTSTAT_INPUT
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ax,DOS_UTL_ENDWAIT
	int	21h
	ASSERT	NC
;
; If ENDWAIT returns an error, that could be a problem.  In the past, it
; was because we got ahead of the WAIT call.  One thought was to make the
; driver's WAIT code more resilient, and double-check that the request had
; really been satisfied, but I eventually resolved the race by making the
; pull_kbd/add_packet/utl_wait path atomic (ie, no interrupts).
;
; TODO: Consider lighter-weight solutions to this race condition.
;
; Anyway, assuming no race conditions, proceed with the packet removal now.
;
	cli
	mov	ax,es:[di].DDP_PTR.OFF
	mov	dx,es:[di].DDP_PTR.SEG
	mov	es,cx
	mov	es:[bx].OFF,ax
	mov	es:[bx].SEG,dx
	sti
	stc				; set carry to indicate yield
	jmp	short ddi9

ddi6:	lea	bx,[di].DDP_PTR		; update prev addr ptr in CX:BX
	mov	cx,es

	les	di,es:[di].DDP_PTR
	jmp	ddi2

ddi9:	pop	es
	pop	ds
	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
ddi9x:	jmp	far ptr DDINT_LEAVE
ENDPROC	ddcon_int09

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
	jnz	dci1
	call	write_char
	jmp	short dci9
dci1:	push	es
	mov	es,dx
	call	write_context
	pop	es
dci9:	pop	dx
	iret
ENDPROC	ddcon_int29

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_packet
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	None
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
	mov	ax,DOS_UTL_WAIT
	int	21h
	pop	dx
	sti
	ret
ENDPROC	add_packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; check_hotkey
;
; Check for key combinations considered "hotkeys" by BASIC-DOS; if a hotkey
; is detected, carry is cleared, indicating that a DOS_UTL_HOTKEY notification
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
	call	focus_next
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
	cmp	dl,ds:[CT_CURMIN].LO
	jge	dc1
	mov	dl,ds:[CT_CURMAX].LO
	dec	dh
	cmp	dh,ds:[CT_CURMIN].HI
	jge	dc1
	mov	dx,ds:[CT_CURMIN]

dc1:	mov	ah,ds:[CT_COLOR].LO	; AH = attributes
	call	write_curpos		; write CL at (DL,DH)
;
; Advance DL, advance DH as needed, and scroll the context as needed.
;
	add	dl,ch			; advance DL
	pop	cx

	cmp	dl,ds:[CT_CURMAX].LO
	jle	dc9
	mov	dl,ds:[CT_CURMIN].LO

	DEFLBL	draw_linefeed,near
	inc	dh
	cmp	dh,ds:[CT_CURMAX].HI
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
	mov	ah,ds:[CT_COLOR].HI
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
	mov	ah,ds:[CT_COLOR].HI
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
; focus_next
;
; Switch focus to the next console context in our chain.
;
; This is called from check_hotkey, which is called at interrupt time,
; so be careful to not modify more registers than the caller has preserved.
;
; Inputs:
;	CX = focus context, if any
;
; Modifies:
;	AX, BX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	focus_next
	push	cx
	push	si
	push	di
	push	ds
;
; Not sure that calling DOS_UTL_LOCK is strictly necessary, but it feels
; like a good idea while we're 1) switching which context has focus, and 2)
; redrawing the borders of the outgoing and incoming contexts.
;
; And it gives us an excuse to test the new LOCK/UNLOCK APIs.
;
	mov	ax,DOS_UTL_LOCK
	int	21h
	push	es
	jcxz	tf9			; nothing to do
	mov	ds,cx
	ASSERT	STRUCT,ds:[0],CT
	mov	cx,ds:[CT_NEXT]
	jcxz	tf1
	jmp	short tf2
tf1:	mov	cx,[ct_head]
	cmp	cx,[ct_focus]
	je	tf9			; nothing to do
tf2:	xchg	cx,[ct_focus]
	mov	ds,cx
	call	draw_border		; redraw the border and hide
	call	hide_cursor		; the cursor of the outgoing context
	mov	ds,[ct_focus]
	call	draw_border		; redraw the broder and show
	call	draw_cursor		; the cursor of the incoming context
tf9:	pop	es
	mov	ax,DOS_UTL_UNLOCK
	int	21h
	pop	ds
	pop	di
	pop	si
	pop	cx
	ret
ENDPROC	focus_next

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
;	CX = +/- position delta (255 max)
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
	idiv	ds:[CT_CURDIM].LO	; AL = # lines, AH = # columns (signed)

mc1:	add	dh,al
	cmp	dh,ds:[CT_CURMIN].HI
	jge	mc1a
	mov	dh,ds:[CT_CURMIN].HI
mc1a:	cmp	dh,ds:[CT_CURMAX].HI
	jle	mc2
	mov	dh,ds:[CT_CURMAX].HI

mc2:	add	dl,ah
	cmp	dl,ds:[CT_CURMIN].LO
	jge	mc2a
	add	dl,ds:[CT_CURMAX].LO
	inc	dl
	sub	dl,ds:[CT_CURMIN].LO
	cmp	dh,ds:[CT_CURMIN].HI
	jle	mc2a
	dec	dh

mc2a:	cmp	dl,ds:[CT_CURMAX].LO
	jle	mc8
	sub	dl,ds:[CT_CURMAX].LO
	dec	dl
	add	dl,ds:[CT_CURMIN].LO
	cmp	dh,ds:[CT_CURMAX].HI
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
	sub	bx,bx
	mov	ds,bx
	ASSUME	DS:BIOS
	mov	bx,[BUFFER_HEAD]
pl2:	cmp	bx,[BUFFER_TAIL]
	stc
	je	pl9			; BIOS buffer empty
	mov	ax,[BIOS_DATA][bx]	; AL = char code, AH = scan code
	add	bx,2
	cmp	bx,offset KB_BUFFER - offset BIOS_DATA + size KB_BUFFER
	jne	pl3
	sub	bx,size KB_BUFFER
pl3:	mov	[BUFFER_HEAD],bx

	push	bx
	push	ds
	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	test	al,al
	jnz	pl3c
;
; Perform some function key to control character mappings now.
;
	push	si
	mov	si,offset SCAN_MAP
pl3a:	lods	byte ptr cs:[si]
	test	al,al
	jz	pl3b
	cmp	ah,al
	lods	byte ptr cs:[si]
	jne	pl3a
pl3b:	pop	si

pl3c:	mov	[bx],al
	IFDEF MAXDEBUG
	test	al,ac
	jnz	pl4
	xchg	al,ah
	PRINTF	<"null character, scan code %#04x",13,10>,ax
	ENDIF
pl4:	inc	bx
	mov	es:[di].DDPRW_ADDR.OFF,bx
	pop	ds
	pop	bx
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	pl2			; no
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
	mov	ax,DOS_UTL_LOCK		; we must lock to ensure EQUIP_FLAG
	int	21h			; remains stable for the duration
	push	bx
	push	cx
	push	dx
	push	bp			; WARNING: INT 10h scrolls trash BP
	push	es
	sub	ax,ax
	mov	es,ax
	ASSUME	ES:BIOS
	mov	ax,ds:[CT_EQUIP]
	xchg	es:[EQUIP_FLAG],ax	; swap EQUIP_FLAG
	push	ax
	xchg	ax,cx			; AL = # lines now
	mov	cx,ds:[CT_CONPOS]
	mov	dx,cx
	test	al,al			; zero?
	jnz	scr0			; no
	add	dx,ds:[CT_CONDIM]	; yes, clear entire context
	jmp	short scr2		; (including border, if any)
scr0:	cmp	al,ds:[CT_CONDIM].HI
	jl	scr1
	mov	al,0			; zero tells BIOS to clear all lines
scr1:	add	cx,ds:[CT_CURMIN]	; CH = row, CL = col of upper left
	add	dx,ds:[CT_CURMAX]	; DH = row, DL = col of lower right
scr2:	mov	bh,ds:[CT_COLOR].LO	; BH = fill attributes
	mov	ah,VIDEO_SCROLL		; scroll up # lines in AL
	int	INT_VIDEO
	pop	ax
	mov	es:[EQUIP_FLAG],ax	; restore EQUIP_FLAG
	pop	es
	pop	bp
	pop	dx
	pop	cx
	pop	bx
	mov	ax,DOS_UTL_UNLOCK
	int	21h
	ret
ENDPROC	scroll

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
	mov	dl,ds:[CT_CURMIN].LO	; yes
	jmp	short wc8

wc1:	cmp	al,CHR_LINEFEED		; LINEFEED?
	je	wclf			; yes

	cmp	al,CHR_TAB		; TAB?
	je	wcht			; yes

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

wcht:	mov	bl,dl			; emulate a (horizontal) TAB
	sub	bl,ds:[CT_CURMIN].LO
	and	bl,07h
	neg	bl
	add	bl,8
	mov	cl,CHR_SPACE
wcsp:	call	draw_char
	cmp	dl,ds:[CT_CURMIN].LO	; did the column wrap back around?
	jle	wc8			; yes, stop
	dec	bl
	jnz	wcsp
	jmp	short wc8

wclf:	call	draw_linefeed		; emulate a LINEFEED
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
	add	dl,6			; DX = status port
wcp1:	in	al,dx
	test	al,01h
	jnz	wcp1			; loop until we're OUTSIDE horz retrace
	cli
wcp2:	in	al,dx
	test	al,01h
	jz	wcp2			; loop until we're INSIDE horz retrace
	mov	al,cl
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
