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
	dw	ddcon_none,  ddcon_none, ddcon_none,  ddcon_ctlin	; 0-3
	dw	ddcon_read,  ddcon_none, ddcon_none,  ddcon_none	; 4-7
	dw	ddcon_write, ddcon_none, ddcon_none,  ddcon_none	; 8-11
	dw	ddcon_none,  ddcon_open, ddcon_close			; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	CON_LIMITS,word
	dw	80,16,80, 25,4,25, 0,0,79, 0,0,24, 0,0,1, 0,0,1

	DEFLBL	DBL_BORDER,word
	dw	0C9BBh,0BABAh,0C8BCh,0CDCDh

	DEFLBL	SGL_BORDER,word
	dw	0DABFh,0B3B3h,0C0D9h,0C4C4h

	DEFLBL	SCAN_MAP,byte
	db	SCAN_F1,CHR_CTRLF,SCAN_F3,CHR_CTRLR,SCAN_UP,CHR_CTRLR
	db	SCAN_RIGHT,CHR_CTRLF,SCAN_LEFT,CHR_CTRLB,SCAN_DEL,CHR_DEL
	db	SCAN_DOWN,CHR_CTRLX
	db	0

	DEFWORD	ct_head,0	; head of context chain
	DEFWORD	ct_focus,0	; segment of context with focus
	DEFWORD	frame_seg,0
	DEFBYTE	max_rows,25	; TODO: use this for something...
	DEFBYTE	max_cols,80	; TODO: set to correct value in ddcon_init

	DEFPTR	kbd_int,0	; keyboard hardware interrupt handler
	DEFPTR	wait_ptr,-1	; chain of waiting packets
;
; A context of "80,25,0,0,1" requests a border, so logical cursor positions
; are 1,1 to 78,23.  Physical character and cursor positions will be adjusted
; by the offset address in CT_SCREEN.
;
CONTEXT		struc
CT_NEXT		dw	?	; 00h: segment of next context, 0 if end
CT_STATUS	db	?	; 02h: context status bits (CTSTAT_*)
CT_RESERVED	db	?	; 03h
CT_CONDIM	dw	?	; 04h: eg, context dimensions (0-based)
CT_CONPOS	dw	?	; 06h: eg, context position (X,Y) of top left
CT_CURPOS	dw	?	; 08h: eg, cursor X (lo) and Y (hi) position
CT_CURMIN	dw	?	; 0Ah: eg, cursor X (lo) and Y (hi) minimums
CT_CURMAX	dw	?	; 0Ch: eg, cursor X (lo) and Y (hi) maximums
CT_CURDIM	dw	?	; 0Eh: width and height (for cursor movement)
CT_EQUIP	dw	?	; 10h: BIOS equipment flags (snapshot)
CT_PORT		dw	?	; 12h: eg, 3D4h
CT_SCROFF	dw	?	; 14h: eg, 2000 (offset of off-screen memory)
CT_SCREEN	dd	?	; 16h: eg, 0B800h:00A2h
CT_BUFFER	dd	?	; 1Ah: used only for background contexts
CT_BUFLEN	dw	?	; 1Eh: eg, 4000 for a full-screen 25*80*2 buffer
CONTEXT		ends

CTSTAT_BORDER	equ	01h	; context has border
CTSTAT_ADAPTER	equ	02h	; alternate adapter selected
CTSTAT_PAUSED	equ	80h	; context is paused (triggered by CTRLS hotkey)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_ctlin
;
; The first two IOCTLs supported here (IOCTL_GETPOS and IOCTL_GETLEN) were
; both required for DOS console I/O support; specifically, the buffered input
; function (AH = 0Ah), which cannot accurately erase TAB characters (or the
; entire buffer) unless it knows the starting position and the displayed length
; of the buffer.  TAB characters complicate matters, since the total number of
; columns in our contexts are not always multiples of 8, and they always wrap
; to column 1 on the following line.
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
DEFPROC	ddcon_ctlin
	mov	al,es:[di].DDP_UNIT
	mov	dx,es:[di].DDP_CONTEXT
	test	dx,dx
	jz	dio9
	mov	ds,dx
	ASSUME	DS:NOTHING

	cmp	al,IOCTL_GETPOS
	jne	dio1
	mov	dx,ds:[CT_CURPOS]	; DX = current cursor position
	jmp	dio7

dio1:	mov	cx,es:[di].DDPRW_LENGTH
	cmp	al,IOCTL_GETLEN
	jne	dio6
	mov	bx,es:[di].DDPRW_LBA	; BX = starting cursor position
	sub	dx,dx			; DL = current len, DH = previous len
	mov	ah,ds:[CT_CURMAX].LO	; AH = column max
	mov	bh,ds:[CT_CURMIN].LO	; BH = column min
	lds	si,es:[di].DDPRW_ADDR
	mov	ch,0			; CL = length (255 character maximum)
	jcxz	dio7			; nothing to do
	ASSUME	DS:NOTHING

dio2:	lodsb
	mov	dh,dl			; current len -> previous len
	cmp	al,CHR_TAB
	jne	dio4
	mov	al,bl			; for CHR_TAB
	sub	al,bh			; mimic write_context's TAB logic
	and	al,07h
	neg	al
	add	al,8			; AL = # output chars
dio3:	inc	bl
	inc	dl
	cmp	bl,ah			; column still below limit?
	jbe	dio3a			; yes
	mov	bl,bh			; no, so reset column and stop
	jmp	short dio5
dio3a:	dec	al
	jnz	dio3
	jmp	short dio5

dio4:	cmp	al,CHR_SPACE		; CONTROL character?
	mov	al,1			; AL = # output chars
	jae	dio4a			; no
	inc	ax			; add 1 more to output for presumed "^"
dio4a:	inc	bl			; advance the column
	inc	dl			; advance the length
	cmp	bl,ah			; column still below limit?
	jbe	dio4b			; yes
	mov	bl,bh			; no, so reset column and keep going
dio4b:	dec	al
	jnz	dio4a

dio5:	loop	dio2
	sub	dl,dh			; DL = length delta for final character
	add	dh,dl			; DH = total length
	jmp	short dio7

dio6:	cmp	al,IOCTL_MOVHORZ
	jne	dio7
	call	move_cursor

dio7:	mov	es:[di].DDP_CONTEXT,dx	; return pos or length in packet context
dio8:	mov	es:[di].DDP_STATUS,DDSTAT_DONE

dio9:	ret
ENDPROC	ddcon_ctlin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	call	read_kbd
	jnc	dcr9
;
; For READ requests that cannot be satisifed, we add this packet to an
; internal chain of "reading" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	call	add_packet
dcr9:	sti

	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcon_read

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
	test	es:[CT_STATUS],CTSTAT_PAUSED
	jz	dcw3
;
; For WRITE requests that cannot be satisifed, we add this packet to an
; internal chain of "writing" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	pop	es			; ES:DI -> packet again
	call	add_packet
	jmp	dcw2			; when this returns, try writing again

dcw3:	lodsb
	call	write_context
	loop	dcw3
	pop	es

dcw9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcon_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	di,offset CON_LIMITS	; ES:DI -> limits
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
	mov	bx,(size context + 15) SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	INT_DOSFUNC
	pop	bx
	jnc	dco1
	jmp	dco7

dco1:	mov	ds,ax
	ASSUME	DS:NOTHING

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
	mov	ds:[CT_SCROFF],4000	; TODO: fix this hard-coded
					; offset to off-screen memory
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
dco4:	mov	ah,0
	xchg	[EQUIP_FLAG],cx
	int	INT_VIDEO
	xchg	[EQUIP_FLAG],cx
	pop	ax
dco5:	mov	ds:[CT_PORT],dx
	mov	ds:[CT_EQUIP],cx
	mov	ds:[CT_SCREEN].SEG,ax
	call	draw_border		; draw the context's border, if any
	mov	cl,0
	call	scroll			; clear the context's interior
	call	hide_cursor		; important when using an alt adapter
	clc

dco7:	pop	es
	pop	di			; ES:DI -> DDP again
	jc	dco8
	mov	es:[di].DDP_CONTEXT,ds
	jmp	short dco9
;
; What's up with the complete disconnect between device driver error codes
; and DOS error codes?
;
dco8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_GENFAIL
dco9:	ret
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
	mov	cx,es:[di].DDP_CONTEXT
	jcxz	dcc9			; no context
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
	mov	cl,-1			; clear the entire context
	call	scroll
	pop	ds
	ASSUME	DS:CODE
;
; We are now free to free the context segment in ES
;
dcc3:	mov	ah,DOS_MEM_FREE
	int	INT_DOSFUNC
	pop	es
dcc9:	ret
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
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	stc
	ret
ENDPROC	ddcon_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_interrupt (keyboard hardware interrupt handler)
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
DEFPROC	ddcon_interrupt,far
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
	mov	ax,cs
	mov	ds,ax
	ASSUME	DS:CODE

	sti
	call	check_hotkey
	jc	ddi1
	mov	cx,[ct_focus]		; CX = context
	xchg	dx,ax			; DL = char code, DH = scan code
	mov	ax,DOS_UTL_HOTKEY	; notify DOS
	int	21h

ddi1:	ASSUME	DS:NOTHING
	mov	bx,offset wait_ptr	; CS:BX -> ptr
	les	di,cs:[bx]		; ES:DI -> packet, if any
	ASSUME	DS:NOTHING, ES:NOTHING

ddi2:	cmp	di,-1			; end of chain?
	je	ddi9			; yes

	ASSERT	STRUCT,es:[di],DDP

	mov	ax,[ct_focus]
	cmp	es:[di].DDP_CONTEXT,ax	; packet from console with focus?
	jne	ddi6			; no

	cmp	es:[di].DDP_CMD,DDC_READ; READ packet?
	je	ddi3			; yes, look for keyboard data
;
; For WRITE packets (which we'll assume this is for now), we need to end the
; wait if the context is no longer paused (ie, check_hotkey may have unpaused).
;
	push	es
	mov	es,ax
	test	es:[CT_STATUS],CTSTAT_PAUSED
	pop	es
	jz	ddi4			; yes, we're no longer paused
	jmp	short ddi6		; still paused, check next packet

ddi3:	call	read_kbd		; read keyboard data
	jc	ddi6			; not enough data, check next packet
;
; Notify DOS that this packet is done waiting.
;
ddi4:	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ax,DOS_UTL_ENDWAIT
	int	21h
	ASSERT	NC
;
; If ENDWAIT returns an error, that could be a problem.  In the past, it
; was because we got ahead of the WAIT call.  One thought was to make the
; driver's WAIT code more resilient, and double-check that the request had
; really been satisfied, but I eventually resolved the race by making the
; read_kbd/add_packet/utl_wait path atomic (ie, no interrupts).
;
; TODO: Consider lighter-weight solutions to this race condition.
;
; Anyway, assuming no race conditions, proceed with the packet removal now.
;
	cli
	mov	ax,es:[di].DDP_PTR.OFF
	mov	[bx].OFF,ax
	mov	ax,es:[di].DDP_PTR.SEG
	mov	[bx].SEG,ax
	sti
	stc				; set carry to indicate yield
	jmp	short ddi9

ddi6:	lea	bx,[di].DDP_PTR		; update prev addr ptr in DS:BX
	push	es
	pop	ds

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
ENDPROC	ddcon_interrupt

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
;	None
;
; Outputs:
;	If carry clear, AL = hotkey char code, AH = hotkey scan code
;
; Modifies:
;	AX, DX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	check_hotkey
	push	bx
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
ch1:	mov	dx,[ct_focus]
	test	dx,dx
	jz	ch4
	push	ds
	mov	ds,dx
	ASSUME	DS:NOTHING
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
	mov	[BUFFER_TAIL],bx	; update tail, consuming the character

ch4:	test	ax,ax			; CTRL_BREAK?
	jnz	ch5
	mov	al,CHR_CTRLC		; yes, map it to CTRLC
	mov	[BIOS_DATA][bx],ax	; in the buffer as well

ch5:	cmp	al,CHR_CTRLC		; CTRLC?
	jne	ch6			; no
	mov	[BUFFER_HEAD],bx	; yes, advance the head toward the tail
	jmp	short ch9		; and return carry clear

ch6:	cmp	al,CHR_CTRLP		; CTRLP?
	je	ch9			; yes, return carry clear

ch8:	stc
ch9:	pop	ds
	ASSUME	DS:NOTHING
	pop	bx
	ret
ENDPROC	check_hotkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	call	write_vertpair
	ASSUME	ES:NOTHING
	lods	word ptr cs:[si]
	xchg	cx,ax
db2:	inc	dh			; advance Y, holding X constant
	cmp	dh,bh
	jae	db3
	call	write_vertpair
	jmp	db2
db3:	lods	word ptr cs:[si]
	xchg	cx,ax
	call	write_vertpair
	lods	word ptr cs:[si]
	xchg	cx,ax
db4:	mov	dh,0
	inc	dx			; advance X, holding Y constant
	cmp	dl,bl
	jae	db9
	call	write_horzpair
	jmp	db4
db9:	ret
ENDPROC	draw_border

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	jne	dc8
	dec	ch			; no advance
	mov	cl,CHR_SPACE		; emulate a BACKSPACE
	dec	dl
	cmp	dl,ds:[CT_CURMIN].LO
	jge	dc8
	mov	dl,ds:[CT_CURMAX].LO
	dec	dh
	cmp	dh,ds:[CT_CURMIN].HI
	jge	dc8
	mov	dx,ds:[CT_CURMIN]

dc8:	call	write_curpos		; write CL at (DL,DH)
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	ah,14			; AH = 6845 CURSOR ADDR (HI) register
	call	write_port		; update cursor position using BX
	ret
ENDPROC	draw_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; focus_next
;
; Switch focus to the next console context in our chain.
;
; This is called from check_hotkey, which is called at interrupt time,
; so be careful to not modify more registers than the caller has preserved.
;
; Inputs:
;	None
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
	mov	cx,[ct_focus]
	jcxz	tf9			; nothing to do
	mov	ds,cx
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
;	AX, BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	get_curpos
	mov	al,dh
	mul	[max_cols]
	add	ax,ax			; AX = offset to row
	sub	bx,bx
	mov	bl,dl
	add	bx,bx
	add	bx,ax			; BX = offset to row and col
	ret
ENDPROC	get_curpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
mc9:	ret
ENDPROC	move_cursor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_kbd
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
DEFPROC	read_kbd
	push	bx
	push	ds
	sub	bx,bx
	mov	ds,bx
	ASSUME	DS:BIOS
	mov	bx,[BUFFER_HEAD]
rk2:	cmp	bx,[BUFFER_TAIL]
	stc
	je	rk9			; BIOS buffer empty
	mov	ax,[BIOS_DATA][bx]	; AL = char code, AH = scan code
	add	bx,2
	cmp	bx,offset KB_BUFFER - offset BIOS_DATA + size KB_BUFFER
	jne	rk3
	sub	bx,size KB_BUFFER
rk3:	mov	[BUFFER_HEAD],bx
	push	bx
	push	ds
	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	test	al,al
	jnz	rk3c
;
; Perform some function key to control character mappings now...
;
	push	si
	mov	si,offset SCAN_MAP
rk3a:	lods	byte ptr cs:[si]
	test	al,al
	jz	rk3b
	cmp	ah,al
	lods	byte ptr cs:[si]
	jne	rk3a
rk3b:	pop	si

rk3c:	mov	[bx],al
	IFDEF MAXDEBUG
	test	al,ac
	jnz	rk4
	xchg	al,ah
	PRINTF	<"null character, scan code %#04x",13,10>,ax
	ENDIF
rk4:	inc	bx
	mov	es:[di].DDPRW_ADDR.OFF,bx
	pop	ds
	pop	bx
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	rk2			; no
	clc
rk9:	pop	ds
	ASSUME	DS:NOTHING
	pop	bx
	ret
ENDPROC	read_kbd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scroll
;
; Inputs:
;	CL = # lines (0 to clear ALL lines, -1 to clear entire context)
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
	test	al,al			; negative?
	jge	scr1			; no
	mov	al,0
	add	dx,ds:[CT_CONDIM]	; yes, clear entire context
	jmp	short scr2		; (including borders)
scr1:	add	cx,ds:[CT_CURMIN]	; CH = row, CL = col of upper left
	add	dx,ds:[CT_CURMAX]	; DH = row, DL = col of lower right
scr2:	mov	bh,07h			; BH = fill attribute
	mov	ah,06h			; scroll up # lines in AL
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	pop	bx
	pop	ax
	ret
ENDPROC	write_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_curpos
;
; Inputs:
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
	mov	es:[di+bx],cl		; "write" the character
	sti
	pop	dx
	pop	bx
	ret
ENDPROC	write_curpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_horzpair
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
DEFPROC	write_horzpair
	xchg	cl,ch
	call	write_curpos
	xchg	cl,ch
	xchg	dh,bh
	call	write_curpos
	xchg	dh,bh
	ret
ENDPROC	write_horzpair

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_vertpair
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
DEFPROC	write_vertpair
	xchg	cl,ch
	call	write_curpos
	xchg	dl,bl
	xchg	cl,ch
	call	write_curpos
	xchg	dl,bl
	ret
ENDPROC	write_vertpair

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_port
;
; Inputs:
;	AH = 6845 register #
;	BX = 16-bit value to write
;
; Outputs:
;	None
;
; Modifies:
;	AL
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	write_port
	push	dx
	mov	dx,ds:[CT_PORT]
	ASSERT	Z,<cmp dh,03h>
	mov	al,ah
	cli
	out	dx,al			; select 6845 register
	inc	dx
	mov	al,bh
	out	dx,al			; output BH
	dec	dx
	mov	al,ah
	inc	ax
	out	dx,al			; select 6845 register + 1
	inc	dx
	mov	al,bl
	out	dx,al			; output BL
	sti
	pop	dx
	ret
ENDPROC	write_port

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
; Install an INT 09h hardware interrupt handler, which we will use to detect
; keys added to the BIOS keyboard buffer.
;
	cli
	mov	ax,offset ddcon_interrupt
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
