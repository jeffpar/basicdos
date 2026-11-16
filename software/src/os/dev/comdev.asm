;
; BASIC-DOS Physical (COM) Serial Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	CLKTIMER equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	uart.inc
	include	dosapi.inc
	include	comdev.inc

DEV	group	CODE,CODE2,CODE3,CODE4,INIT,DATA

CODE	segment para public 'CODE'

	public	COM1
;
; COM1's length (and the offset of ddcom_init) are link-time values, unlike
; the other ports', because comcon.asm's code follows ours in this segment.
;
COM1	DDH	<offset DEV:COM2,,DDATTR_OPEN+DDATTR_CHAR,offset DEV:ddcom_init,,20202020314D4F43h>
;
; Every COM driver instance must define the next group of variables in
; the same location/order as shown below, followed by its request handler
; (so that ddcom_init can use the same DDH_REQUEST offset for every port).
;
	DEFPTR	ddcom_cmdp	; ddcom_cmd pointer
	DEFPTR	ddcom_intp	; ddcom_int pointer
	DEFWORD	ct_seg,0	; context with focus, if any (see switch_to)
	DEFWORD	card_num,0	; card number
	DEFWORD	ddcom_isr,<offset ddcom_int1>; interrupt entry

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
DEFPROC	ddcom_req,far
	mov	ds,cs:[0].DDH_DATA	; (DOS doesn't need DS preserved)
	ASSUME	DS:CODE
	jmp	[ddcom_cmdp]		; DS = this port's data (see ddcom_cmd)
	ASSUME	DS:NOTHING
ENDPROC	ddcom_req

	DEFPTR	wait_ptr,0FFFFh,0	; chain of waiting packets (none)

	EXTNEAR	<alloc_sys,alloc_plane,free_ctx,get_shadow,paint,con_opt>
	EXTNEAR	<shadow_put,shadow_erase,shadow_scroll,switch_to,switch_now>
	EXTNEAR	<get_len,set_color,set_mode,move_cur,scroll_lines>
	EXTNEAR	<raw_input,push_key>

	DEFLBL	CMDTBL,word
	dw	ddcom_none,   ddcom_none,   ddcom_none,   ddcom_ioctl	; 0-3
	dw	ddcom_read,   ddcom_none,   ddcom_none,   ddcom_inflush	; 4-7
	dw	ddcom_write,  ddcom_none,   ddcom_none,   ddcom_outflush; 8-11
	dw	ddcom_none,   ddcom_open,   ddcom_close			; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	COM_PARMS,word
	dw	9600,110,19200, 8,7,8, 1,1,2, 128,0,4096

;
; Options, which may be specified in any order after the stop bits (eg,
; "COM1:9600,N,8,1,GENERIC,XON"): a terminal type (aka "personality"), where
; the default is ANSI, XON, which enables XON/XOFF flow control, and RTS,
; which enables RTS/CTS flow control.  The terminal types in OPT_NAMES must
; come first, in the order of the TERM_* values, followed by XON and RTS.
;

	DEFLBL	OPT_NAMES,byte
	db	"ANSI",0,"GENERIC",0,"VT100",0,"XON",0,"RTS",0,0

	DEFLBL	GENERIC_CLEAR,byte
	db	CHR_RETURN,CHR_LINEFEED,0
	DEFLBL	ANSI_CSI,byte
	db	CHR_ESCAPE,"[",0	; "control sequence introducer"
	DEFLBL	VT100_INIT,byte
	db	VT100_SI,CHR_ESCAPE,"[m"; G0, and no attributes
	db	CHR_ESCAPE,"[?3l"	; 80 columns (which clears the screen)
	db	CHR_ESCAPE,"[?7h"	; enable auto-wrap (off by default)
	db	CHR_ESCAPE,")0"		; G1 = special graphics (see VT100_GFX)
	db	CHR_ESCAPE,"[c",0	; report device attributes (see rb6)
	DEFLBL	VT100_WIDE,byte
	db	CHR_ESCAPE,"#6",0	; make the cursor's row double-width
;
; The VT100 special graphics characters for the PC's line-drawing characters
; (B0h-DFh): double lines become single lines, and the shaded and solid blocks
; all become the checkerboard.
;

	DEFLBL	VT100_GFX,byte
	db	"aaaxuuukkuxkjjjk"	; B0h-BFh
	db	"mvwtqnttmlvwtqnv"	; C0h-CFh
	db	"vwwmmllnnjlaaaaa"	; D0h-DFh

;
; The key that gives the focus to a port's next console (see push_input),
; unless CONFIG.SYS has a HOTKEY setting (HOT_KEY): CTRL-\ (ASCII FS), since
; a terminal can't tell SHIFT-TAB (the VKD$ driver's key) from TAB.
;
SWITCH_KEY	equ	1Ch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver command handler
;
; Every port's request handler jumps here with its own data segment in DS
; (their variables are at the same offsets), which the handlers get in BP,
; along with the handle's context in CX: its own console's, or else the one
; with focus (eg, for a handle that was opened before the port had one).
;
; Inputs:
;	DS = the port's data segment
;	ES:BX -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_cmd,far
	mov	bp,ds			; BP = the port's data segment
	mov	dx,[card_num]		; DX = card #
	mov	di,bx			; ES:DI -> DDP
	mov	cx,es:[di].DDP_CONTEXT	; CX = the handle's context
	test	cx,cx			; does it have one?
	jnz	ddq0			; yes
	mov	cx,[ct_seg]		; no, so use the one with focus, if any
ddq0:	mov	bl,es:[di].DDP_CMD
	cmp	bl,CMDTBL_SIZE
	jb	ddq1
	mov	bl,0
ddq1:	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
	ret
ENDPROC	ddcom_cmd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_read
;
; Inputs:
;	CX = context, if any
;	DX = card #
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW packet updated
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_read
	push	cx
	xchg	ax,cx			; AX = context, if any
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	dcr9
;
; Use the port's context (and record it in the packet, for wake_packet), even
; if the handle has none, because a handle opened before the port's context
; existed (eg, the STDAUX handle that DOS opens at boot) would otherwise use
; the BIOS, which clears OUT2 and therefore disables the port's interrupts.
;
	mov	es:[di].DDP_CONTEXT,ax
	test	ax,ax
	jnz	dcr1a

	lds	si,es:[di].DDPRW_ADDR
	ASSUME	DS:NOTHING

dcr1:	mov	ah,2			; AH = READ, DX = card #
	int	14h			; call the BIOS to read a char
	; test	ah,ah
	; jnz	err
	mov	[si],al
	inc	si
	loop	dcr1
	jmp	short dcr9

dcr1a:	mov	ds,ax
	ASSUME	DS:NOTHING

	cli
	call	pull_input
	jnc	dcr9
;
; An IO_DIRECT request (eg, a DOS_TTY_IO input check) never waits.
;
	cmp	es:[di].DDP_UNIT,0
	jge	dcr1b
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_NOTREADY
	jmp	short dcr9a
dcr1b:
;
; For READ requests that cannot be satisfied, we add this packet to an
; internal chain of "reading" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
	ASSERT	STRUCT,ds:[0],CT
	or	ds:[CT_STATUS],CTSTAT_INPUT

	call	add_packet
	jnc	dcr9
	and	ds:[CT_STATUS],NOT CTSTAT_INPUT
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_RDFAULT
	jmp	short dcr9a

dcr9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dcr9a:	sti
	pop	cx
	ret
ENDPROC	ddcom_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_write
;
; Inputs:
;	CX = context, if any
;	DX = card #
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW packet updated
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_write
	push	cx
	xchg	ax,cx			; AX = context, if any
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	dcw9

	lds	si,es:[di].DDPRW_ADDR
	ASSUME	DS:NOTHING
	mov	es:[di].DDP_CONTEXT,ax	; use the port's context (see ddcom_read)
	test	ax,ax
	jnz	dcw1a

dcw1:	lodsb
	mov	ah,1			; AH = WRITE, DX = card #
	int	14h			; call the BIOS to write the char
	loop	dcw1
	jmp	short dcw9

dcw1a:	xchg	dx,ax

dcw2:	push	es
	mov	es,dx
dcw3:	test	es:[CT_STATUS],CTSTAT_BUSY
	jz	dcw4
;
; For WRITE requests that cannot be satisfied, we add this packet to an
; internal chain of "writing" packets, and then tell DOS that we're waiting;
; DOS will suspend the current SCB until we notify DOS that this packet's
; conditions are satisfied.
;
dcw3a:	pop	es			; ES:DI -> packet again
	mov	es:[di].DDPRW_LENGTH,cx
	mov	es:[di].DDPRW_ADDR.OFF,si
	call	add_packet
	jc	dcw8			; the wait was interrupted
	jmp	dcw2			; otherwise, try writing again

dcw8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	pop	cx
	ret

dcw4:	mov	al,[si]
;
; Output on the row past the last one (see IOCTL_SETPOS) is ignored, except
; for RETURN, and LINEFEED, which also puts the cursor on the last row again.
;
	mov	ah,es:[CT_ROWS]
	cmp	es:[CT_ROW],ah
	jb	dcw5
	cmp	al,CHR_RETURN
	je	dcw5
	cmp	al,CHR_LINEFEED
	jne	dcw6
	dec	es:[CT_ROW]
dcw5:	call	write_context
	jc	dcw3a
	call	update_col		; update CT_COL for the char in AL
dcw6:	inc	si
	loop	dcw4
	pop	es
;
; DOS reports the number of bytes written as the original length minus
; DDPRW_LENGTH (the number of bytes remaining), so we must zero it.
;
dcw9:	mov	es:[di].DDPRW_LENGTH,cx	; CX is zero
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	pop	cx
	ret
ENDPROC	ddcom_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_ioctl
;
; When a serial context is serving as a console (eg, "CON=COM1:9600,N,8,1"
; in CONFIG.SYS), the DOS line editor (see read_line in conio.asm) relies on
; the same IOCTLs that the VKD$ driver provides, in order to redisplay and
; reposition the cursor as characters are inserted, deleted, etc.  We support
; them by tracking the terminal's current column (CT_COL) as data is written,
; so that the editor sees consistent cursor positions and display lengths.
;
; We don't know the terminal's dimensions, so we assume TERM_COLS by TERM_ROWS
; (or for a VT100, whatever IOCTL_SETMODE last set; see CT_COLS and CT_ROWS);
; the column isn't reset when a line wraps, but the row is advanced.
;
; An IOCTL's output is often a sequence, which a focus switch must not cut
; short (or let finish on a screen that's since been repainted), so an IOCTL
; waits for any repaint to end, CT_BUSY makes switch_to wait for the IOCTL to
; end, and then we make any switch that waited.
;
; Inputs:
;	CX = context, if any
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW packet updated (with any result in DDP_CONTEXT)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_ioctl
	jcxz	dio8			; no context
	mov	ds,cx
	ASSUME	DS:NOTHING
	ASSERT	STRUCT,ds:[0],CT
	mov	es:[di].DDP_CONTEXT,cx	; (for wake_packet)
dio0h:	test	ds:[CT_STATUS],CTSTAT_PAINT
	jz	dio0i
	call	add_packet		; wait for the repaint to end
	jnc	dio0h
	jmp	ioctl_fault
dio0i:	inc	ds:[CT_BUSY]
	call	ioctl_cmd
	pushf
	dec	ds:[CT_BUSY]
	push	es
	mov	es,ds:[CT_DRV]
	mov	cx,es:[ct_seg]		; CX = context with focus
	mov	es,cx
	mov	bx,es:[CT_PEND]		; BX = context waiting for it, if any
	test	bx,bx
	jz	dio0j
	push	di
	call	switch_to
	pop	di
dio0j:	pop	es
	popf
	ret
dio8:	jmp	ddcom_none		; unsupported IOCTL
ENDPROC	ddcom_ioctl

DEFPROC	ioctl_cmd
	push	cx
	mov	al,es:[di].DDP_CODE	; AL = IOCTL code
	mov	cx,es:[di].DDPRW_LENGTH	; CX = IOCTL input value
	mov	dx,es:[di].DDPRW_LBA	; DX = IOCTL input value
	cmp	al,IOCTL_INSTATUS
	je	dio0g
	cmp	al,IOCTL_GETDIM
	je	dio0
	cmp	al,IOCTL_GETPOS
	je	dio1
	cmp	al,IOCTL_GETLEN
	je	dio2
	cmp	al,IOCTL_MOVCUR
	je	dio3
	cmp	al,IOCTL_SETINS
	je	dio4
	cmp	al,IOCTL_SCROLL
	je	dio5
	cmp	al,IOCTL_GETCOLOR
	je	dio0a
	cmp	al,IOCTL_SETCOLOR
	je	dio0b
	cmp	al,IOCTL_SETPOS
	je	dio0d
	cmp	al,IOCTL_SETKEYS
	je	dio0e
	cmp	al,IOCTL_GETMODE
	je	dio0k
	cmp	al,IOCTL_SETMODE
	je	dio0l
	cmp	al,IOCTL_COMDEBUG
	jne	dio8a
	jmp	dio0c			; (see below)
dio8a:	pop	cx
	jmp	ddcom_none		; unsupported IOCTL
dio0d:	jmp	dio10
dio0e:	jmp	dio11
dio0k:	jmp	dio13
dio0l:	jmp	dio12
;
; IOCTL_GETDIM: return the (assumed) terminal dimensions.
;
dio0:	mov	dx,word ptr ds:[CT_COLS]
	ASSERT	<CT_ROWS>,EQ,<CT_COLS + 1>
	jmp	short dio7
;
; IOCTL_INSTATUS: return the number of bytes waiting in CT_INPUT (zero if
; none), which BASIC's EOF, LOC, and INPUT$ use for a COM file.
;
dio0g:	mov	si,offset CT_INPUT
	mov	dx,[si].BUFTAIL
	sub	dx,[si].BUFHEAD		; DX = tail - head
	jae	dio7			; (unless the input wrapped around)
	add	dx,[si].BUFEND
	sub	dx,[si].BUFOFF		; plus the size of the buffer
	jmp	short dio7
;
; IOCTL_GETCOLOR: return the fill (DL) and border (DH) attributes.
;
dio0a:	mov	dx,ds:[CT_COLOR]
	jmp	short dio7
;
; IOCTL_SETCOLOR: set the fill (CL) and border (CH) attributes; only the
; bits in DL and DH are set (the other bits keep their current values).
;
dio0b:	mov	ax,ds:[CT_COLOR]
	xor	cx,ax
	and	cx,dx
	xor	cx,ax			; CX = attributes with those bits set
	call	set_color
	jc	dio9			; wait interrupted (DDP_STATUS set)
	jmp	short dio4
;
; IOCTL_GETPOS: return the current column in DL and row in DH.
;
dio1:	mov	dl,ds:[CT_COL]
	mov	dh,ds:[CT_ROW]
	jmp	short dio7
;
; IOCTL_GETLEN: return the display length of CL bytes at DDPRW_ADDR, starting
; at column DL, using the same display rules as VKD$ (and update_col).
;
dio2:	call	get_len
	jmp	short dio7
;
; IOCTL_MOVCUR: move the cursor by CX columns (negative for left).
;
dio3:	call	move_cur
	jc	dio9			; wait interrupted (DDP_STATUS set)
	jmp	short dio7
;
; IOCTL_SETINS: there's no cursor shape to change, so just report that
; insert mode was previously off.
;
dio4:	sub	dx,dx
	jmp	short dio7
;
; IOCTL_SCROLL: CX = 0 clears the scrolling rows (eg, for CLS), or if DX is
; non-zero, sets them instead (see set_rows); ANSI terminals can also scroll
; them by CX lines (see scroll_lines), but GENERIC terminals ignore that.
;
dio5:	jcxz	dio6
	cmp	ds:[CT_TERM],TERM_GENERIC
	je	dio4
	call	scroll_lines
	jmp	short dio6b
dio6:	test	dx,dx			; set the scrolling rows?
	jz	dio6a			; no
	call	set_rows
	jmp	short dio6b
dio6a:	call	clear_screen
dio6b:	jc	dio9			; failed (DDP_STATUS set)
	jmp	short dio4

dio7:	mov	es:[di].DDP_CONTEXT,dx	; return result in packet context
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
dio9:	pop	cx			; CX = context
	ret
;
; IOCTL_SETPOS: ANSI terminals get the "cursor position" sequence (the cursor
; visibility in DL is ignored), followed by "erase in line" if DH = 1, which
; erases from the cursor to the end of the row; GENERIC terminals don't
; support it.  A col (CL) or row (CH) of -1 keeps the current col or row.
; A position that can't be set is a DDERR_SEEK error.
;
; The row past the last one is allowed too, so that a program written for
; 25 rows (eg, LOCATE 25,1) still runs: the cursor waits on the last row, and
; whatever is written before the next move is ignored (see ddcom_write).
;
dio10:	cmp	ds:[CT_TERM],TERM_GENERIC
	je	dio10a
	cmp	cl,-1			; keep the current col?
	jne	dio10d			; no
	mov	cl,ds:[CT_COL]
dio10d:	cmp	ch,-1			; keep the current row?
	jne	dio10e			; no
	mov	ch,ds:[CT_ROW]
dio10e:	cmp	cl,ds:[CT_COLS]		; is the col past the last one?
	jae	dio10a			; yes
	cmp	ch,ds:[CT_ROWS]		; (or below the row past the last one)
	ja	dio10a
	push	cx
	push	dx
	jb	dio10c
	dec	ch			; the cursor waits on the last row
dio10c:	call	set_pos
	jc	dio10f
	call	wide_row		; (so the cursor is where it should be)
dio10f:	pop	dx
	pop	cx
	jc	dio9			; wait interrupted (DDP_STATUS set)
	mov	ds:[CT_ROW],ch
	cmp	ch,ds:[CT_ROWS]		; is there a row to erase?
	je	dio10b			; no
	dec	dh			; erase to the end of the row?
	jnz	dio10b			; no
	mov	al,ch			; (set_pos preserved CX)
	call	erase_shadow		; erase the rest of the shadow's row
	mov	al,'K'
	call	csi_out
	jc	dio9
dio10b:	jmp	dio4
dio10a:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_SEEK
	stc
	jmp	dio9
;
; IOCTL_SETKEYS: in raw keys mode, CTRLC and CTRLS are just keys, rather than
; hotkeys, and an ANSI terminal's keys are translated, too (see push_input).
;
dio11:	and	ds:[CT_STATUS],NOT CTSTAT_RAWKEYS
	call	end_esc			; discard any partial escape sequence
	test	cl,1			; raw keys requested (bit 0)?
	jz	dio11a			; no
	or	ds:[CT_STATUS],CTSTAT_RAWKEYS
dio11a:	jmp	dio4
;
; IOCTL_GETMODE: a VT100 is in "video mode" 3 (80 columns), 1 (40 columns),
; or MODE_WIDE (132 columns; see set_mode).  That's all we report (CL = 0),
; and only for a VT100.
;
dio13:	cmp	ds:[CT_TERM],TERM_VT100
	jne	dio13a
	test	cl,cl			; is it the mode they want?
	jnz	dio13a			; no
	mov	dx,MODE_WIDE
	mov	al,ds:[CT_COLS]
	cmp	al,WIDE_COLS
	je	dio13b
	cmp	al,TERM_COLS
	cmc				; carry set if 80 columns
	mov	dl,0
	adc	dl,dl
	stc
	adc	dl,dl			; DL = 3 if 80 columns, 1 if 40
dio13b:	jmp	dio7
dio13a:	jmp	dio8a
;
; IOCTL_SETMODE: see set_mode, which a machine with 64K or less doesn't keep
; (see con_opt), so it has no modes to set.
;
dio12:	mov	ax,BIOS
	push	es
	mov	es,ax
	ASSUME	ES:BIOS
	cmp	es:[MEMORY_SIZE],64
	ASSUME	ES:NOTHING
	pop	es
	jbe	dio13a
	call	set_mode
	jmp	dio6b
;
; IOCTL_COMDEBUG: the kernel has verified that the caller's handle has
; exclusive access (MODE_DENY_RW), so it's the only reference to this context;
; disable the UART's interrupts (for polling) and return the port plus any
; COMDBG_* bits.  The caller does all its own I/O, so free the context, too
; (it's the port's only one, since the port couldn't be opened that way if it
; were a console); the open handle still reserves the port (see chk_devopen),
; and with no context, our interrupt handler won't touch the port.
;
; First, wait for our interrupt handler to transmit anything still buffered
; (eg, the VT100_INIT sequence that ddcom_open queued); otherwise, the rest of
; a partially sent sequence would be lost, and the caller's first output
; would complete it.
;
dio0c:	sti
	mov	si,offset CT_OUTPUT
dio0f:	call	peek_buffer		; anything left to transmit?
	jnz	dio0f			; yes
	mov	dx,ds:[CT_PORT]
	inc	dx			; DX -> REG_IER (DLAB is clear)
	sub	al,al
	out	dx,al
	dec	dx
	mov	al,ds:[CT_STATUS]
	and	al,CTSTAT_XON OR CTSTAT_RTS
	ASSERT	<COMDBG_XON SHL 1>,EQ,<CTSTAT_XON>
	ASSERT	<COMDBG_RTS SHL 1>,EQ,<CTSTAT_RTS>
	shr	al,1
	or	dl,al
	call	end_esc
	push	dx
	push	es
	call	free_ctx		; (DS = the port's data segment now)
	ASSUME	DS:CODE
	pop	es
	pop	dx
	mov	[ct_seg],0		; the port has no context now
	ASSUME	DS:NOTHING
	mov	es:[di].DDP_CONTEXT,dx	; return result in packet context
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	pop	cx
	pop	ax			; return to ddcom_cmd (not ddcom_ioctl,
	ret				; since the context is gone)
ENDPROC	ioctl_cmd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_rows
;
; Sets an ANSI terminal's scrolling rows (with the "set top and bottom
; margins" sequence, which needs at least two rows), and moves the cursor to
; the first one.  A LINEFEED on the last one then scrolls only those rows.
;
; Inputs:
;	DL = first row (zero-based), DH = last row + 1
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if not (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_rows
	cmp	ds:[CT_TERM],TERM_GENERIC
	je	srw8
	mov	cx,dx
	xchg	cl,ch			; CH = first row, CL = last row + 1
	cmp	cl,ds:[CT_ROWS]		; do the rows end below the terminal?
	ja	srw8			; yes
	sub	cl,1			; CL = last row
	jc	srw8			; (there wasn't one)
	cmp	ch,cl			; at least two rows?
	jae	srw8			; no
	mov	ds:[CT_TOP],ch
	mov	ds:[CT_BOT],cl
	mov	al,'r'
	call	csi_pair		; ESC [ first ; last r
	jc	srw9
	mov	cl,0
	jmp	short set_pos		; (that sequence homes the cursor)
srw8:	call	ddcom_none		; (which also sets carry)
srw9:	ret
ENDPROC	set_rows

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; set_pos
;
; Sends the ANSI "cursor position" sequence (ESC [ row ; col H).
;
; Inputs:
;	CL = col, CH = row (zero-based)
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if interrupted (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	set_pos
	mov	ds:[CT_COL],cl
	mov	ds:[CT_ROW],ch
	mov	al,'H'
	DEFLBL	csi_pair,near		; ESC [ CH+1 ; CL+1 AL
	push	ax
	mov	si,offset ANSI_CSI
	call	ioctl_str
	jc	spo1
	mov	al,ch
	call	ioctl_num
	jc	spo1
	mov	al,';'
	call	ioctl_out
	jc	spo1
	mov	al,cl
	call	ioctl_num
spo1:	pop	ax
	jnc	spo2
	DEFLBL	ioctl_fault,near
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_WRFAULT
	ret
	DEFLBL	csi_out,near		; ESC [ AL
	push	ax
	mov	si,offset ANSI_CSI
	call	ioctl_str
	jmp	spo1
spo2:	call	ioctl_out
	jc	ioctl_fault
	ret
ENDPROC	set_pos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; wide_row
;
; Makes the cursor's row double-width, if it needs to be (see wide_reset), on
; behalf of an IOCTL request (or a repaint).
;
; Inputs:
;	CH = cursor's row
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if interrupted (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	wide_row
	mov	bl,ch
	mov	bh,0
	cmp	ds:[CT_WIDE][bx],bh	; does the row need it?
	jne	wr9			; no (and carry is clear)
	inc	ds:[CT_WIDE][bx]
	mov	si,offset VT100_WIDE
	call	ioctl_str
	jc	ioctl_fault
wr9:	ret
ENDPROC	wide_row

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ioctl_num
;
; Outputs a zero-based row or column as an ANSI (one-based) parameter.
;
; Inputs:
;	AL = row or column (0-254)
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if the wait was interrupted
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ioctl_num
	inc	ax
ion1:	aam				; AH = AL / 10, AL = the last digit
	push	ax
	mov	al,ah
	test	al,al			; any digits before it?
	jz	ion2			; no (and carry is clear)
	call	ion1			; yes, so they go first
ion2:	pop	ax
	jc	ion9
	add	al,'0'
	call	ioctl_out
ion9:	ret
ENDPROC	ioctl_num

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clear_screen
;
; Clears the scrolling rows (the entire screen, unless set_rows changed them).
;
; Inputs:
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if interrupted (DDP_STATUS updated)
;
; Modifies:
;	AX, BX, CX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	clear_screen
	mov	si,offset GENERIC_CLEAR
	cmp	ds:[CT_TERM],TERM_GENERIC
	jne	clr1
	call	ioctl_str
	jc	ioctl_fault
	mov	ds:[CT_COL],0
	jmp	short clr9
;
; Erase the scrolling rows, last to first, which leaves the cursor on the
; first one; if they reach the bottom of the terminal, then one "erase in
; display" from the first row erases them all.
;
clr1:	call	wide_reset		; ("erase in display" does that, too)
	mov	cl,0
	mov	ch,ds:[CT_TOP]
	mov	al,ds:[CT_BOT]
	call	erase_shadow		; erase the shadow's rows, too
	call	bot_last
	je	clr2
	mov	ch,al
clr2:	call	set_pos
	jc	clr8
	mov	al,'J'			; "erase in display" (to its end)
	call	bot_last
	je	clr3
	mov	al,'K'			; "erase in line" (to its end)
clr3:	call	csi_out
	jc	clr8
	dec	ch
	cmp	ch,ds:[CT_TOP]
	jge	clr2
clr9:	mov	ds:[CT_LLEN],0
	clc
clr8:	ret
	DEFLBL	bot_last,near		; (zero set if CT_BOT is the last row)
	mov	ah,ds:[CT_ROWS]
	dec	ah
	cmp	ah,ds:[CT_BOT]
	ret
ENDPROC	clear_screen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ioctl_str
;
; Outputs a null-terminated string on behalf of an IOCTL request.  The string
; contents are not reflected in CT_COL or CT_LINE (the caller must do that).
;
; Inputs:
;	CS:SI -> null-terminated string
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if the wait was interrupted
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ioctl_str
ios1:	mov	al,cs:[si]
	test	al,al			; end of string?
	jz	ios9			; yes (carry clear)
	push	si
	call	ioctl_out
	pop	si
	jc	ios9
	inc	si
	jmp	ios1
ios9:	ret
ENDPROC	ioctl_str

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ioctl_out
;
; Outputs a byte on behalf of an IOCTL request, waiting for room in the
; output buffer if necessary.
;
; Inputs:
;	AL = byte
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	Carry clear if successful, set if the wait was interrupted
;
; Modifies:
;	BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ioctl_out
iot1:	call	push_output
	jnc	iot9
	push	ax
	call	add_packet		; wait for the output buffer to drain
	pop	ax
	jnc	iot1
iot9:	ret
ENDPROC	ioctl_out

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; update_col
;
; Updates the context's current column (CT_COL) and copy of the current line
; (CT_LINE) for a byte just written, using the same display rules as get_len
; (and VKD$).  CR resets the column, BACKSPACE (which is destructive;
; see write_context) erases the previous column, LINEFEED starts a new (empty)
; line without changing the column, and BELL changes nothing.  The row
; (CT_ROW) is advanced by a LINEFEED, and by a character written beyond the
; last column, which is when a terminal wraps (see put_col).
;
; Inputs:
;	AL = byte
;	ES = context
;
; Outputs:
;	None
;
; Modifies:
;	AH
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	update_col
	push	bx
	mov	bl,es:[CT_COL]
	mov	bh,0			; BX = current column
	cmp	al,CHR_RETURN
	jne	uc1
	mov	bl,0
	jmp	short uc8
uc1:	cmp	al,CHR_LINEFEED
	jne	uc2
	mov	es:[CT_LLEN],0		; the new line is empty
	call	next_row
	jmp	short uc9
uc2:	cmp	al,CHR_BACKSPACE
	jne	uc3
	sub	bl,1
	adc	bl,0			; don't go below zero
	mov	ah,CHR_SPACE
	call	put_line		; the previous column is now blank
	call	put_shadow
	jmp	short uc8
uc3:	cmp	al,CHR_CTRLG		; BELL?
	je	uc9
	cmp	al,CHR_TAB
	jne	uc4
	or	bl,07h			; advance to the next multiple of 8
	inc	bx
	jmp	short uc8
uc4:	mov	ah,al
	cmp	al,CHR_SPACE		; CONTROL character?
	jae	uc5			; no
	mov	ah,'^'			; yes, presumably displayed as "^" + char
	call	put_col
	mov	ah,al
	add	ah,'@'
uc5:	call	put_col
uc8:	call	fit_col
	mov	es:[CT_COL],bl
uc9:	pop	bx
	ret
ENDPROC	update_col

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_col
;
; Stores a character in CT_LINE (see put_line) and advances the column.  The
; column isn't reset when a line wraps, so the row is advanced whenever the
; column is a multiple of CT_COLS.
;
; Inputs:
;	AH = character
;	BX = column
;	ES = context
;
; Outputs:
;	BX = next column
;
; Modifies:
;	BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	put_col
	push	ax
	mov	al,bl
pc1:	sub	al,es:[CT_COLS]
	ja	pc1
	pop	ax
	jne	pc2			; it's not a multiple (or it's zero)
	call	next_row
pc2:	call	put_line
	call	put_shadow
	inc	bx
;
; The column isn't reset when a line wraps, so to keep it within a byte on
; a very long line, the 4th row's columns are the 3rd's again (which wrap the
; same way), or in MODE_WIDE, where only one row's columns fit, column 256 is
; the column that many (WIDE_COLS) before it.
;
	DEFLBL	fit_col,near		; BX = column (0-256)
	push	ax
	mov	ah,es:[CT_COLS]
	add	ah,ah
	jc	pc3
	add	ah,es:[CT_COLS]		; AH = the 4th row's first column
	cmp	bl,ah
	jmp	short pc4
pc3:	cmp	bh,1			; carry set unless it's column 256
pc4:	jb	pc5
	sub	bl,es:[CT_COLS]
	mov	bh,0
pc5:	pop	ax
	ret
ENDPROC	put_col

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; next_row
;
; Advances the row, unless it's the last scrolling row (those rows scroll
; instead, and so do the shadow's) or the last row of the terminal.
;
; Inputs:
;	ES = context
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	next_row
	push	ax
	mov	al,es:[CT_ROW]
	cmp	al,es:[CT_BOT]
	je	nr8
	inc	ax
	cmp	al,es:[CT_ROWS]
	je	nr9
	inc	es:[CT_ROW]
nr9:	pop	ax
	ret
nr8:	push	ds
	push	es
	pop	ds			; DS = context
	call	scroll_shadow		; scroll up (the sign is clear)
	pop	ds
	jmp	nr9
ENDPROC	next_row

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_shadow, erase_shadow, scroll_shadow
;
; Call shadow_put (ES = context), shadow_erase, or shadow_scroll (DS =
; context) for a context that has a shadow; without one, their code may not
; even be loaded (see con_opt).  Flags are preserved for shadow_scroll.
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	put_shadow
	cmp	es:[CT_SHADOW],0
	je	psh9
	jmp	shadow_put
	DEFLBL	erase_shadow,near
	cmp	ds:[CT_SHADOW],0
	je	psh9
	jmp	shadow_erase
	DEFLBL	scroll_shadow,near
	pushf
	call	wide_reset		; (the rows are moving, so start over)
	cmp	ds:[CT_SHADOW],0
	je	psh8
	popf
	jmp	shadow_scroll
psh8:	popf
psh9:	ret
ENDPROC	put_shadow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; wide_reset
;
; A VT100 has no 40-column mode, only double-width rows (see VT100_WIDE), and
; a row that scrolls into view or is part of an "erase in display" is always
; single-width.  So in 40-column mode, CT_WIDE has a byte for every row (and
; the row past the last one; see IOCTL_SETPOS) that's zero until the row has
; been made double-width, which happens just before the first write to the
; row (see write_context) or when the cursor is moved to it (see wide_row).
;
; This zeros them all, for any change that makes rows single-width or moves
; them (the terminal ignores a VT100_WIDE that wasn't needed).  In 80-column
; mode, they're all set to 1 instead, so there's nothing to do for any row.
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	None (flags are preserved, too)
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	wide_reset
	pushf
	push	ax
	push	cx
	push	di
	push	es
	push	ds
	pop	es
	mov	di,offset CT_WIDE
	mov	cx,TERM_ROWS+1
	cmp	ds:[CT_COLS],TERM_COLS	; carry set if 40 columns
	sbb	al,al
	inc	ax			; AL = 0 if 40 columns, 1 if 80
	cld
	rep	stosb
	pop	es
	pop	di
	pop	cx
	pop	ax
	popf
	ret
ENDPROC	wide_reset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; put_line
;
; Stores a character in CT_LINE at the specified column (if it's within
; LINE_MAX), filling any gap beyond the current line length with spaces.
;
; Inputs:
;	AH = character
;	BX = column
;	ES = context
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	put_line
	cmp	bx,LINE_MAX
	jae	pt9
	push	cx
	push	si
	mov	cl,es:[CT_LLEN]
	mov	ch,0			; CX = current line length
pt1:	cmp	cx,bx			; is there a gap before the column?
	jae	pt2			; no
	mov	si,cx
	mov	es:[CT_LINE][si],CHR_SPACE
	inc	cx
	jmp	pt1
pt2:	mov	es:[CT_LINE][bx],ah
	cmp	cx,bx			; did the line get longer?
	ja	pt3			; no
	mov	cx,bx
	inc	cx
	mov	es:[CT_LLEN],cl
pt3:	pop	si
	pop	cx
pt9:	ret
ENDPROC	put_line

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_open
;
; The format of the optional context descriptor is:
;
;	[device]:[baud],[parity],[databits],[stopbits],[inbuflen],[outbuflen]
;
; where [device] is "COMn" (otherwise you wouldn't be here), unless it's "CON",
; which DOS sends us when a session whose console is this port opens CON with
; a descriptor (eg, START's "CON:80,25,0,0,1"; see chk_devname).  That makes a
; new console on the port, with a context and shadow of its own, as long as the
; console with focus has a shadow too (see SHADOW_MIN); its settings are that
; console's, and all we use of the descriptor (which is the VKD$ driver's) is
; its 5th value: 1 if the new console takes the focus.
;
; Otherwise, a port that already has a context is simply shared (the context
; with focus gets another reference).
;
; Contexts and shadows are owned by the system, rather than by the program
; that opens one (eg, START), since they outlive it.
;
; Inputs:
;	CX = context with focus, if any
;	DX = card #
;	BP = the port's data segment
;	ES:DI -> DDP
;	[DDP].DDP_PTR -> context descriptor (eg, "COM1:9600,N,8,1")
;
; Outputs:
;	[DDP].DDP_CONTEXT = context (zero if none)
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_open
	push	di
	push	es
	lds	si,es:[di].DDP_PTR
	ASSUME	DS:NOTHING
	mov	al,[si+2]
	and	al,0DFh			; (upper-case)
	cmp	al,'N'			; "CON" (ie, a new console)?
	je	dco10			; yes
	jcxz	dco1			; the port has no context yet
	mov	ds,cx
	inc	ds:[CT_REFS]		; share the context with focus
dco0:	jmp	dco6
;
; DDP_PTR points to the device name (eg, "COM1"), so any parms follow the
; first colon.
;
dco1:	lodsb
	cmp	al,cl			; end of the name (CL is zero)?
	je	dco0			; yes, so there are no parms
	cmp	al,':'			; colon separator?
	jne	dco1			; no, so keep looking
	call	get_parms
	jc	dco7d			; invalid parameter (eg, terminal type)
	sub	di,di			; DI = 0 (no console to copy)
	push	di			; (and no focus to take)
	jmp	short dco2
;
; A new console needs a console with a shadow to copy (and switch from).
;
dco10:	jcxz	dco7a
	mov	es,cx
	cmp	es:[CT_SHADOW],0
	je	dco7a
	mov	ah,4			; the focus is the 5th value
dco11:	lodsb
	test	al,al			; end of the descriptor?
	jz	dco12			; yes
	cmp	al,','
	jne	dco11
	dec	ah
	jnz	dco11
	lodsb				; AL = '1' to take the focus
dco12:	push	ax
	mov	ds,cx			; DS = console to copy
	mov	di,cx
	mov	cx,ds:[CT_BAUD]
	mov	dx,word ptr ds:[CT_DATABITS]
	mov	bh,ds:[CT_PARITY]
	mov	bl,ds:[CT_STATUS]
	and	bl,CTSTAT_XON OR CTSTAT_RTS
	or	bl,ds:[CT_TERM]
	mov	si,ds:[CT_INPUT].BUFEND
	sub	si,ds:[CT_INPUT].BUFOFF
	mov	ax,ds:[CT_OUTPUT].BUFEND
	sub	ax,ds:[CT_OUTPUT].BUFOFF
;
; CX = baud rate, BH = parity, BL = terminal type and options, DL = data
; bits, DH = stop bits, SI and AX = input and output buffer lengths, and
; DI = the console to copy, if any (with the focus value on the stack).
;
dco2:	push	di
	push	ax			; save output buffer length
	push	si
	add	ax,si			; AX = output + input buffer lengths
	add	ax,size CONTEXT
	xchg	di,ax			; DI = required length
	call	alloc_sys		; AX = context
	pop	si
	jnc	dco2a
	add	sp,6
dco7a:	jmp	dco7
dco7d:	jmp	dco7b

dco2a:	push	bx			; save parity and terminal type
	push	cx			; save baud rate
	mov	es,ax
	sub	di,di			; ES:DI -> CONTEXT
	mov	ds,bp
	ASSUME	DS:CODE
	mov	ax,[card_num]
	stosw				; set CT_CARD
	xchg	bx,ax
	add	bx,bx			; BX = card # * 2
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,[RS232_BASE][bx]
	ASSUME	DS:NOTHING
	stosw				; set CT_PORT
	pop	ax			; restore baud rate (originally in CX)
	stosw				; set CT_BAUD
	xchg	ax,dx
	stosw				; set CT_DATABITS and CT_STOPBITS
	pop	ax			; restore parity (BH) and terminal (BL)
	mov	dl,al			; DL = terminal type and options
	mov	al,1
	xchg	al,ah
	stosw				; set CT_PARITY and CT_REFS
	mov	al,dl
	and	ax,CTSTAT_XON OR CTSTAT_RTS	; AL = flow control options
	IFDEF DEBUG
	mov	ah,SIG_CT
	ENDIF
	stosw				; set CT_STATUS and CT_SIG
	mov	al,0
	mov	ah,dl
	and	ah,NOT (CTSTAT_XON OR CTSTAT_RTS)	; AH = terminal type
	stosw				; set CT_COL and CT_TERM
	sub	ax,ax
	stosw				; set CT_LLEN and CT_ESC
	mov	ax,0707h
	stosw				; set CT_COLOR (same default as VKD$)
	mov	word ptr es:[CT_ROW],0	; set CT_ROW and CT_TOP
	ASSERT	<CT_TOP>,EQ,<CT_ROW + 1>
	mov	word ptr es:[CT_BOT],(VT100_SI SHL 8) OR (TERM_ROWS-1)
	ASSERT	<CT_GFX>,EQ,<CT_BOT + 1>
	add	di,LINE_MAX		; skip CT_LINE

	mov	ax,size CONTEXT
	stosw				; set CT_INPUT.BUFOFF
	stosw				; set CT_INPUT.BUFHEAD
	stosw				; set CT_INPUT.BUFTAIL
	add	ax,si
	stosw				; set CT_INPUT.BUFEND

	stosw				; set CT_OUTPUT.BUFOFF
	stosw				; set CT_OUTPUT.BUFHEAD
	stosw				; set CT_OUTPUT.BUFTAIL
	pop	bx			; restore output buffer length
	add	ax,bx
	stosw				; set CT_OUTPUT.BUFEND
;
; It has no shadows yet, no parent, no console waiting for its focus, and the
; focus (CT_BACK and CT_BUSY are zero), and it's the only one in its ring.
;
	sub	ax,ax
	mov	cx,5
	rep	stosw			; CT_SHADOW through CT_BUSY
	ASSERT	<CT_NEXT>,EQ,<CT_SHADOW + 10>
	mov	ax,es
	stosw				; set CT_NEXT
	mov	ax,bp
	stosw				; set CT_DRV

	push	es
	pop	ds			; DS is now the context
	mov	word ptr ds:[CT_COLS],(TERM_ROWS SHL 8) OR TERM_COLS
	mov	ds:[CT_WROWS],TERM_ROWS	; (until the terminal says otherwise)
	call	wide_reset
	pop	cx			; CX = console to copy, if any
	pop	ax			; AL = '1' to take the focus from it
	jcxz	dco2c
;
; A new console: it must have a shadow, since it's repainted whenever it gets
; the focus.  It follows the one it copied in the port's ring.
;
	xchg	dx,ax			; DL = focus value
	mov	al,CHR_SPACE
	call	alloc_plane		; AX = shadow
	jnc	dco2b
	call	free_ctx
	jmp	dco7
dco2b:	mov	ds:[CT_SHADOW],ax
	inc	ds:[CT_BACK]
	mov	es,cx
	mov	al,es:[CT_WROWS]	; (it's the same terminal)
	mov	ds:[CT_WROWS],al
	mov	ax,ds
	xchg	es:[CT_NEXT],ax
	mov	ds:[CT_NEXT],ax
	cmp	dl,'1'			; take the focus?
	jne	dco2e			; no
	mov	ds:[CT_PARENT],cx	; yes, and remember where it came from
	mov	bx,ds
	call	switch_to
dco2e:	jmp	dco5b

dco2c:	mov	ax,ds:[CT_BAUD]
	mov	cl,150
	div	cl
;
; AL is now 64, 32, 16, 8, 4, 2, or 1 for baud rates 9600, 4800, 2400, 1200,
; 600, 300, or 150.
;
	mov	ah,0
dco2d:	test	al,al
	jz	dco3
	shr	al,1
	add	ah,20h
	jnc	dco2d
;
; AH should now contain the correct baud rate selection in bits 7-5.  Next,
; add the appropriate parity, stop length, and data length bits.
;
dco3:	mov	al,ds:[CT_PARITY]
	cmp	al,'O'
	jne	dco3a
	or	ah,08h
dco3a:	cmp	al,'E'
	jne	dco3b
	or	ah,18h
dco3b:	cmp	ds:[CT_STOPBITS],2
	jne	dco3c
	or	ah,04h
dco3c:	or	ah,02h
	cmp	ds:[CT_DATABITS],8
	jne	dco4
	or	ah,03h
;
; Now we can use the BIOS to initialize the card.
;
dco4:	mov	dx,ds:[CT_CARD]
	mov	al,ah
	mov	ah,0
	int	INT_COM

	test	si,si			; verify we have an input buffer
	jnz	dco5			; we do
	call	free_ctx		; no, apparently the caller just
	sub	cx,cx			; used us to initialize the COM port
	jmp	short dco6
;
; There are 3 required steps to enabling COM interrupts.
;
; Step 1: Set the desired bits in the Interrupt Enable Register.
;
;
; The port's context must be in place before its first interrupt (eg, for the
; VT100_INIT output below), or our handler would dismiss that interrupt
; without servicing the UART, which would then never interrupt again.
;
dco5:	mov	ax,ds
	mov	ds,bp
	ASSUME	DS:CODE
	mov	[ct_seg],ax		; the first context has the focus
	mov	ds,ax
	ASSUME	DS:NOTHING
	call	write_ier		; enable THR and RBR interrupts
;
; Step 2: Set the OUT2 bit in the Modem Control Register.
;
	call	write_mcr		; set DTR and OUT2 (and RTS)
	call	check_cts		; record the initial CTS state
;
; Step 3: Unmask the IRQ.  We choose which IRQ based on port #.
;
	mov	al,0
	call	write_irq
;
; A VT100 may still be displaying whatever it was sent before we were booted
; (and in some other state), so start it as CLS would leave it: its "column
; mode" sequence for 80 columns also clears the screen, homes the cursor, and
; makes every row a scrolling row.  Its auto-wrap is off by default, so long
; lines would be truncated at the last column (and MORE would display fewer
; lines than will fit), so turn it on, and assign the special graphics set to
; G1 (see write_context).  The output buffer is empty, so there's no need to
; wait for room.
;
	mov	di,offset VT100_INIT
	cmp	ds:[CT_TERM],TERM_VT100	; VT100 terminal?
	jne	dco5c			; no
dco5a:	mov	al,cs:[di]
	test	al,al			; end of string?
	jz	dco5c			; yes
	call	push_output
	inc	di
	jmp	dco5a
dco5c:	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	cmp	es:[MEMORY_SIZE],64	; more than 64K (see con_opt)?
	ASSUME	ES:NOTHING
	jbe	dco5d			; no
	call	get_shadow		; give it a shadow, if it can have one
dco5d:
;
; All done.  Be sure to return with the context segment in CX.
;
dco5b:	mov	cx,ds
dco6:	pop	es
	pop	di
	mov	es:[di].DDP_CONTEXT,cx
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
;
; An open's error is a DOS error code (see dev_request): not enough memory
; (which includes a new console on a port whose console has no shadow), or
; for an option we don't know, a device that doesn't exist.
;
dco7b:	mov	al,ERR_NOFILE
	jmp	short dco7c
dco7:	mov	al,ERR_NOMEMORY
dco7c:	pop	es
	pop	di
	mov	ah,DDSTAT_ERROR SHR 8
	mov	es:[di].DDP_STATUS,ax
	ret
ENDPROC	ddcom_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_close
;
; When a context's last reference is closed, it leaves the port's ring; any
; console that took the focus from it takes it back from its parent instead
; (eg, if START made B from A and C from B, and B closes first, then C's
; focus goes back to A), and if it has the focus, that goes back to its
; parent, if any (or else the next console).
;
; Inputs:
;	BP = the port's data segment
;	ES:DI -> DDP
;
; Outputs:
;	DDP updated
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_close
	mov	cx,es:[di].DDP_CONTEXT
	jcxz	dcc8			; no context
	mov	ds,cx
	ASSUME	DS:NOTHING
	ASSERT	STRUCT,ds:[0],CT
	dec	ds:[CT_REFS]
	jg	dcc8			; context still in use
	push	di
	push	es
	call	end_esc			; (the timer mustn't touch it, either)
	mov	ax,ds:[CT_PARENT]	; AX = this context's parent, if any
	mov	bx,ds:[CT_NEXT]		; BX = the next context
	mov	dx,ds			; DX = this context
	mov	si,bx
dcc1:	mov	es,si
	cmp	es:[CT_PARENT],dx	; did it take the focus from this one?
	jne	dcc2			; no
	mov	es:[CT_PARENT],ax
dcc2:	cmp	es:[CT_PEND],dx		; is this one waiting for its focus?
	jne	dcc3			; no
	mov	es:[CT_PEND],0
dcc3:	mov	si,es:[CT_NEXT]
	cmp	si,dx			; is ES the context before this one?
	jne	dcc1			; no
	mov	es:[CT_NEXT],bx		; yes, so remove this one from the ring
	cmp	bx,dx			; is it the port's last context?
	jne	dcc4			; no
;
; Mask the IRQ, and with no context, our interrupt handler won't touch the
; port.
;
	mov	al,1
	call	write_irq
	mov	es,bp
	ASSUME	ES:CODE
	mov	es:[ct_seg],0
	ASSUME	ES:NOTHING
	jmp	short dcc7
dcc4:	cmp	ds:[CT_BACK],0		; does it have the focus?
	jne	dcc7			; no
	test	ax,ax			; is there a parent?
	jz	dcc5			; no
	xchg	bx,ax
dcc5:	mov	cx,dx			; CX = this context, BX = the next
	call	switch_now
dcc7:	call	free_ctx
	pop	es
	pop	di
dcc8:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcom_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_none (handler for unimplemented functions)
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	DDPRW packet updated
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_none
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	stc
	ret
ENDPROC	ddcom_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_inflush
;
; Discards any buffered input.
;
; Inputs:
;	CX = context, if any
;	ES:DI -> DDP
;
; Outputs:
;	DDP updated
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_inflush
	jcxz	cif9
	push	ds
	mov	ds,cx
	ASSUME	DS:NOTHING
	cli
	mov	ax,ds:[CT_INPUT].BUFTAIL
	mov	ds:[CT_INPUT].BUFHEAD,ax
	sti
	pop	ds
	ASSUME	DS:CODE
cif9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcom_inflush

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_outflush
;
; Discards any buffered output, and ends any CTRLS pause; however, an XOFF
; pause (with XON/XOFF flow control) belongs to the terminal, so only XON can
; end it, and a CTS hold (with RTS/CTS flow control) ends only when CTS rises.
;
; Inputs:
;	CX = context, if any
;	ES:DI -> DDP
;
; Outputs:
;	DDP updated
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcom_outflush
	jcxz	cof9
	push	ds
	mov	ds,cx
	ASSUME	DS:NOTHING
	cli
	test	ds:[CT_STATUS],CTSTAT_PAINT
	jnz	cof7			; (a repaint's output must all be sent)
	mov	ax,ds:[CT_OUTPUT].BUFTAIL
	mov	ds:[CT_OUTPUT].BUFHEAD,ax
	and	ds:[CT_STATUS],NOT CTSTAT_XMTFULL
cof7:	test	ds:[CT_STATUS],CTSTAT_XON
	jnz	cof8			; only XON can end the pause
	and	ds:[CT_STATUS],NOT CTSTAT_PAUSED
cof8:	sti
	pop	ds
	ASSUME	DS:CODE
cof9:	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcom_outflush

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcom_int
;
; COM hardware interrupt handler.
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
	call	far ptr DDINT_ENTER
	push	ax
	jcxz	ddi2			; no context
;	jc	ddi2			; carry set if DOS not ready

ddi1:	push	bx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	mov	ds,cx
	sti
;
; Check the IIR to see what's changed, until no more interrupts are pending
; (another condition could arise while we're servicing one, eg, a CTS change
; while the transmitter is empty, and the 8250 won't interrupt again).
;
ddi1a:	call	read_iir
	test	al,IIR_NO_INT		; any (more) interrupts pending?
	jnz	ddi4			; no
	cmp	al,IIR_INT_RBR		; data received?
	jne	ddi3			; no
	call	push_input		; (DS = context with focus)
	jmp	ddi1a
;
; Unlike the CONSOLE and CLOCK$ drivers' hardware interrupt handlers,
; which simply piggy-back on existing BIOS hardware interrupt handlers,
; we're on our own here.  So we must make sure our handler always EOIs
; the interrupt, even if the system isn't ready to process interrupts yet.
;
ddi2:	mov	al,20h			; EOI the interrupt to ensure
	out	20h,al			; we don't block other interrupts
	jmp	ddi10

ddi3:	cmp	al,IIR_INT_THR		; transmitter ready?
	jne	ddi3a			; no
	call	pull_output
	jmp	ddi1a
ddi3a:	cmp	al,IIR_INT_MSR		; modem status changed?
	jne	ddi3b			; no
	call	check_cts
	jmp	ddi1a
ddi3b:	call	read_lsr		; line status (reading LSR clears it)
	test	al,LSR_BI		; BREAK received?
	jz	ddi1a			; no
;
; A BREAK (eg, from a VT100's BREAK key) is treated like the VKD$ driver's
; CTRL-BREAK and CTRL-ALT-DEL: it's reported to DOS as an ABORT, which (unlike
; CTRLC) also stops a program that never calls DOS (eg, a BASIC loop).
;
	push	cx
	mov	cx,ds			; CX = context
	mov	dx,CHR_CTRLD		; DL = char code (CTRLD means ABORT)
	mov	ah,DOS_UTL_HOTKEY
	call	far ptr DDINT_UTIL	; notify DOS
	pop	cx
	jmp	ddi1a

ddi4:	mov	al,20h			; EOI the interrupt now
	out	20h,al
	call	wake_packet		; carry set to indicate yield

ddi9:	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	bx

ddi10:	pop	ax
	pop	cx
	jmp	far ptr DDINT_LEAVE
ENDPROC	ddcom_int

DEFPROC	ddcom_int1,far
	push	cx
	mov	cx,[ct_seg]
	jmp	[ddcom_intp]
ENDPROC	ddcom_int1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; add_packet
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	Carry clear if the packet was satisfied, set if the wait was interrupted
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	add_packet
	cli
	push	ds
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:CODE
	mov	ax,di
	xchg	[wait_ptr].OFF,ax
	mov	es:[di].DDP_PTR.OFF,ax
	mov	ax,es
	xchg	[wait_ptr].SEG,ax
	mov	es:[di].DDP_PTR.SEG,ax
	pop	ds
	ASSUME	DS:NOTHING
;
; The WAIT condition will be satisfied when enough data is received
; (for a READ packet) or when the context is ready (for a WRITE packet).
;
	push	dx
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ah,DOS_UTL_WAIT
	call	far ptr DDINT_UTIL	; wait on DX:DI (see int_util)
	jnc	ap9
;
; The wait was interrupted (eg, by ABORT or CTRLC), so the packet must be
; removed from the chain.  However, if it's no longer on the chain, then our
; interrupt handler satisfied it after all, so treat that as success.
;
	call	remove_packet		; carry clear if packet removed
	cmc				; carry set if packet removed
ap9:	pop	dx
	sti
	ret
ENDPROC	add_packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; remove_packet
;
; Removes a packet from the chain of waiting packets, if it's still there.
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	Carry clear if the packet was removed, set if it wasn't found
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	remove_packet
	push	bx
	push	cx
	push	ds
	mov	ds,cs:[0].DDH_DATA
	mov	bx,offset wait_ptr	; DS:BX -> first link
	mov	cx,es			; CX:DI -> packet to remove
	pushf
	cli
rp1:	mov	ax,[bx].OFF
	cmp	ax,-1			; end of chain?
	je	rp8			; yes, packet not found
	cmp	ax,di
	jne	rp2
	cmp	[bx].SEG,cx
	je	rp3
rp2:	lds	bx,dword ptr [bx]	; DS:BX -> next packet
	lea	bx,[bx].DDP_PTR		; DS:BX -> its link
	jmp	rp1
rp3:	mov	ax,es:[di].DDP_PTR.OFF	; unlink the packet
	mov	[bx].OFF,ax
	mov	ax,es:[di].DDP_PTR.SEG
	mov	[bx].SEG,ax
	popf
	clc
	jmp	short rp9
rp8:	popf
	stc
rp9:	pop	ds
	pop	cx
	pop	bx
	ret
ENDPROC	remove_packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_parms
;
; Inputs:
;	DS:SI -> parameter string:
;	[baud],[parity],[databits],[stopbits],[options],[inbuflen],[outbuflen]
;
; where [options] are optional names from OPT_NAMES (see get_option).  Parsing
; stops at the end of the string, and any missing values use their defaults.
;
; Outputs:
;	If carry clear:
;	CX = baud rate
;	BH = parity indicator (unvalidated; should be one of 'N', 'O', or 'E')
;	BL = terminal type (TERM_*), plus CTSTAT_XON and/or CTSTAT_RTS
;	DL = data bits
;	DH = stop bits
;	SI = input buffer length
;	AX = output buffer length
;	If carry set, an option was not recognized
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	get_parms
	push	di
	push	es
	push	cs
	pop	es
	mov	bl,10			; use base 10
	mov	di,offset COM_PARMS	; ES:DI -> parm defaults/limits
	DOSUTIL	ATOI16			; updates SI, DI, and AX
	xchg	cx,ax			; CX = baud rate
	lodsb
	and	al,0DFh			; (upper-case, eg, "COM1:300,e,7")
	mov	bh,al			; BH = parity indicator ('N', 'O', 'E')
	lodsb
	DOSUTIL	ATOI16
	mov	dl,al			; DL = data bits
	DOSUTIL	ATOI16
	mov	dh,al			; DH = stop bits
;
; ATOI16 advances SI past the delimiter following a number, so whenever that
; delimiter wasn't a comma, we've reached the end of the parameters.
;
	mov	ax,TERM_ANSI		; AL = default terminal type, AH = 0
gp0:	cmp	byte ptr [si-1],','	; any more parameters?
	jne	gp1			; no
	call	get_option		; AL = terminal type, AH = options
	jc	gp9			; unrecognized option
	jnz	gp0			; found one, so check for another
gp1:	or	al,ah			; AL = terminal type and options
	push	ax			; save terminal type and options
	mov	ax,es:[di]		; AX = default input buffer length
	cmp	byte ptr [si-1],','	; any more parameters?
	jne	gp2			; no
	DOSUTIL	ATOI16			; AX = input buffer length
	sub	di,6			; use the input limits for output, too
gp2:	push	ax			; save input buffer length
	mov	ax,es:[di]		; AX = default output buffer length
	cmp	byte ptr [si-1],','	; any more parameters?
	jne	gp3			; no
	DOSUTIL	ATOI16			; AX = output buffer length
gp3:	pop	si			; SI = input buffer length
	pop	di			; DI = terminal type
	xchg	ax,di			; AL = terminal type, DI = output length
	mov	bl,al			; BL = terminal type
	xchg	ax,di			; AX = output buffer length
	clc
gp9:	pop	es
	pop	di
	ret
ENDPROC	get_parms

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_option
;
; If the next parameter begins with a letter, it must be one of the names in
; OPT_NAMES (in upper or lower case): a terminal type, XON, or RTS.
;
; Inputs:
;	AL = terminal type
;	AH = options (CTSTAT_XON, CTSTAT_RTS)
;	DS:SI -> next parameter
;
; Outputs:
;	If carry clear and ZF clear, a name was found, so AL or AH is updated,
;	and SI is advanced past the name and its delimiter (like ATOI16);
;	if carry clear and ZF set, there was no name; carry set if the name
;	was not recognized
;
; Modifies:
;	AX, SI
;
DEFPROC	get_option
	push	bx
	push	cx
	push	di
	xchg	cx,ax			; CX = terminal type and options
	mov	al,[si]
	and	al,0DFh			; convert to upper-case
	cmp	al,'A'			; does parameter begin with a letter?
	jb	go8			; no
	cmp	al,'Z'
	ja	go8			; no
	mov	di,offset OPT_NAMES	; CS:DI -> option names
	sub	bx,bx			; BX = option index
go1:	push	si
go2:	mov	al,[si]
	cmp	al,'a'
	jb	go3
	cmp	al,'z'
	ja	go3
	sub	al,20h			; convert to upper-case
go3:	mov	ah,cs:[di]
	inc	di
	test	ah,ah			; end of name?
	jz	go4			; yes
	cmp	al,ah
	jne	go5			; mismatch
	inc	si
	jmp	go2
go4:	cmp	al,','			; name must be followed by a comma
	je	go6
	cmp	al,CHR_SPACE		; or the end of the string (NUL, or any
	jae	go5			; other CONTROL char, eg, CR or LF)
go6:	pop	ax			; discard saved SI
	inc	si			; advance SI past the delimiter
	cmp	bl,TERM_COUNT		; terminal type?
	jae	go7			; no
	mov	cl,bl			; CL = terminal type
	cmp	bl,TERM_VT100		; a VT100 relies on XON/XOFF
	jne	go7a
	or	ch,CTSTAT_XON
	jmp	short go7a
go7:	mov	al,CTSTAT_XON
	je	go7b			; XON (it follows the terminal types)
	mov	al,CTSTAT_RTS		; the only other option is RTS
go7b:	or	ch,al
go7a:	test	sp,sp			; ZF clear (and carry clear)
	jmp	short go9

go5:	pop	si			; restore SI
go5a:	test	ah,ah			; skip remainder of the name
	jz	go5b
	mov	ah,cs:[di]
	inc	di
	jmp	go5a
go5b:	inc	bx			; advance option index
	cmp	byte ptr cs:[di],0	; end of OPT_NAMES?
	jne	go1			; no
	stc				; unrecognized name
	jmp	short go9

go8:	cmp	ax,ax			; no name (ZF set, carry clear)
go9:	xchg	ax,cx			; AX = terminal type and options
	pop	di
	pop	cx
	pop	bx
	ret
ENDPROC	get_option

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peek_buffer
;
; Inputs:
;	SI -> RINGBUF in context
;	DS = context
;
; Outputs:
;	ZF clear if data available, ZF set if empty
;
; Modifies:
;	BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	peek_buffer
	ASSERT	STRUCT,ds:[0],CT
	mov	bx,[si].BUFHEAD
	cmp	bx,[si].BUFTAIL
	ret
ENDPROC	peek_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_buffer
;
; Call with interrupts off when calling from non-interrupt code (eg, when
; pulling bytes for a read request).
;
; Inputs:
;	SI -> RINGBUF in context
;	DS = context
;
; Outputs:
;	CF clear if data available in AL, CF set if empty
;
; Modifies:
;	AX, BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_buffer
	ASSERT	STRUCT,ds:[0],CT
	mov	bx,[si].BUFHEAD
	cmp	bx,[si].BUFTAIL
	stc
	je	pl9			; buffer empty
	mov	al,[bx]
	inc	bx
	cmp	bx,[si].BUFEND
	jb	pl2
	mov	bx,[si].BUFOFF
pl2:	mov	[si].BUFHEAD,bx
	clc
pl9:	ret
ENDPROC	pull_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; push_buffer
;
; Call with interrupts off when calling from non-interrupt code (eg, when
; pushing bytes from a write request).
;
; Inputs:
;	SI -> RINGBUF in context
;	DS = context
;
; Outputs:
;	CF clear if room (BX -> available space), CF set if full
;
; Modifies:
;	BX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_buffer
	ASSERT	STRUCT,ds:[0],CT
	push	ax
	mov	bx,[si].BUFTAIL
	mov	ax,bx			; AX -> potential free space
	inc	bx
	cmp	bx,[si].BUFEND
	jb	ps1
	mov	bx,[si].BUFOFF
ps1:	cmp	bx,[si].BUFHEAD
	stc
	je	ps9
	mov	[si].BUFTAIL,bx
	xchg	bx,ax
	clc
ps9:	pop	ax
	ret
ENDPROC	push_buffer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_input
;
; Remove bytes from CT_INPUT and transfer them to the request buffer.
;
; Inputs:
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	If carry clear, AL = byte; otherwise carry set
;
; Modifies:
;	AX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_input
	push	bx
	mov	si,offset CT_INPUT
pli1:	call	pull_buffer
	jc	pli9
	push	ds
	lds	bx,es:[di].DDPRW_ADDR	; DS:BX -> next read/write address
	mov	[bx],al
	inc	bx
	mov	es:[di].DDPRW_ADDR.OFF,bx
	pop	ds
	dec	es:[di].DDPRW_LENGTH	; have we satisfied the request yet?
	jnz	pli1
	clc
pli9:	pop	bx
	ret
ENDPROC	pull_input

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; push_input
;
; Add a byte from the receiver to CT_INPUT (if there's no more room, it's
; discarded).
;
; If the port has more than one console, the HOTKEY setting (or SWITCH_KEY,
; without one) isn't input: it gives the focus to the next one (see
; switch_to), even in raw keys mode, and the rest of this interrupt's input is
; the new console's.
;
; This is also where we check for hotkeys, similar to check_hotkey in the
; VKD$ driver, since a serial context may be serving as a console (eg, when
; CONFIG.SYS contains "CON=COM1:9600,N,8,1").
;
; CTRLS toggles the context's PAUSED state (unless the context is waiting for
; input, in which case CTRLS is passed through, because the CONIO buffered
; input code uses it for input control), and while paused, any other byte
; (eg, CTRLQ) ends the pause and is consumed.
;
; With XON/XOFF flow control (the XON option, eg, for a VT100 that sends XOFF
; when its buffer fills), XOFF (CTRLS) always pauses, XON (CTRLQ) always ends
; the pause (nothing else does, not even DDC_OUTFLUSH), both are always
; consumed (even when the context is waiting for input), and any other byte is
; data.
;
; CTRLC is buffered like any other byte, and is also reported to DOS as a
; HOTKEY, which is all the VKD$ driver does as well; it's up to DOS to discard
; any type-ahead or end any pause (see DDC_INFLUSH and DDC_OUTFLUSH).
;
; Inputs:
;	DS = context
;
; Outputs:
;	DS = context with focus
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_input
	call	read_rbr		; AL = received byte
	ASSERT	STRUCT,ds:[0],CT
	mov	bx,BIOS
	mov	es,bx
	ASSUME	ES:BIOS
	mov	ah,es:[HOT_KEY]		; AH = the HOTKEY setting, if any
	ASSUME	ES:NOTHING
	test	ah,ah
	jnz	psi0c
	mov	ah,SWITCH_KEY		; AH = our own key
psi0c:	cmp	al,ah			; the key that switches consoles?
	jne	psi0b			; no
	mov	bx,ds:[CT_NEXT]
	mov	cx,ds
	cmp	bx,cx			; is there another console?
	je	psi0b			; no, so it's just a key
	call	switch_to
	mov	es,ds:[CT_DRV]
	ASSUME	ES:CODE
	mov	ds,es:[ct_seg]		; (unless the switch had to wait)
	ASSUME	ES:NOTHING
	ret
psi0b:	cmp	al,CHR_CTRLC		; CTRLC?
	jne	psi0a			; no
	test	ds:[CT_STATUS],CTSTAT_RAWKEYS
	jz	psi6			; yes (unless raw keys)
psi0a:	test	ds:[CT_STATUS],CTSTAT_XON
	jz	psi1			; no XON/XOFF flow control
	cmp	al,CHR_CTRLS		; XOFF?
	jne	psi0			; no
	or	ds:[CT_STATUS],CTSTAT_PAUSED
	jmp	short psi9
psi0:	cmp	al,CHR_CTRLQ		; XON?
	jne	psi3			; no, so it's data
	and	ds:[CT_STATUS],NOT CTSTAT_PAUSED
	jmp	short psi5
psi1:	test	ds:[CT_STATUS],CTSTAT_INPUT OR CTSTAT_RAWKEYS
	jnz	psi3			; input wait or raw keys: no PAUSE
	cmp	al,CHR_CTRLS		; CTRLS?
	jne	psi2			; no (anything else unpauses)
	xor	ds:[CT_STATUS],CTSTAT_PAUSED
	jmp	short psi5
psi2:	test	ds:[CT_STATUS],CTSTAT_PAUSED
	jz	psi3
	and	ds:[CT_STATUS],NOT CTSTAT_PAUSED
	jmp	short psi5

;
; A VT100's keys are always translated (eg, its cursor keys become the PC's;
; see raw_input), as are an ANSI terminal's keys in raw keys mode, but not
; otherwise, since an ANSI port may be a program's data port (eg, COM1 in
; COMM.BAS), where escape sequences are data.
;
psi3:	test	ds:[CT_STATUS],CTSTAT_RAWKEYS
	jnz	psi3a
	cmp	ds:[CT_TERM],TERM_VT100	; VT100 terminal?
	jne	psi3b			; no
psi3a:	call	raw_input		; translate its keys
	jc	psi9			; nothing to buffer (yet)
psi3b:	mov	si,offset CT_INPUT
	call	push_buffer
	jc	psi8
	mov	[bx],al
psi8:	jmp	short psi9
;
; CTRLC detected: buffer it, and notify DOS.
;
psi6:	mov	si,offset CT_INPUT
	call	push_buffer
	jc	psi7
	mov	[bx],al
psi7:	push	cx
	mov	cx,ds			; CX = context
	mov	dx,CHR_CTRLC		; DL = char code, DH = scan code (none)
	mov	ah,DOS_UTL_HOTKEY
	call	far ptr DDINT_UTIL	; notify DOS
	pop	cx
	jmp	short psi9
;
; PAUSE state changed; if we're no longer paused, resume output.
;
psi5:	test	ds:[CT_STATUS],CTSTAT_PAUSED
	jnz	psi9
	call	resume_output
psi9:	ret
ENDPROC	push_input

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; end_esc
;
; Ends any escape sequence (and cancels the timer for a held ESC).
;
; Inputs:
;	DS = context
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	end_esc
	mov	ds:[CT_ESC],0
	push	ax
	sub	ax,ax
	call	esc_timer
	pop	ax
	ret
ENDPROC	end_esc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; esc_timer
;
; Starts (or cancels) the context's timer for a held ESC, using the CLOCK$
; driver's timer function (see CLKX); without CLOCK$, an ESC is held until
; the next byte arrives.
;
; Inputs:
;	AX = milliseconds (0 to cancel)
;	DS = context
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	esc_timer
	push	bx
	push	cx
	push	di
	push	es
	xchg	cx,ax			; CX = milliseconds
	mov	ax,BIOS
	mov	es,ax
	ASSUME	ES:BIOS
	les	bx,[CLOCK_DEVICE]		; ES:BX -> CLOCK$ driver header
	ASSUME	ES:NOTHING
	mov	ax,es
	test	ax,ax			; is there a CLOCK$ driver?
	jz	et9			; no
	push	es
	push	es:[bx + size DDH].CLKX_TIMER
	mov	ds:[CT_TIMER].TMR_FUNC.OFF,offset esc_timeout
	mov	ds:[CT_TIMER].TMR_FUNC.SEG,cs
	push	ds
	pop	es
	mov	di,offset CT_TIMER	; ES:DI -> timer
	mov	bx,sp
	call	dword ptr ss:[bx]
	add	sp,4
et9:	xchg	ax,cx			; restore AX
	pop	es
	pop	di
	pop	cx
	pop	bx
	ret
ENDPROC	esc_timer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; esc_timeout
;
; Called by the CLOCK$ driver when a held ESC's timer expires: no other byte
; arrived, so it was just an ESC; buffer it, and end any read waiting for it.
;
; Inputs:
;	ES:DI -> timer (ES = context)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	esc_timeout,far
	push	ds
	push	es
	pop	ds			; DS = context
	cmp	ds:[CT_ESC],1		; still holding an ESC?
	jne	eto9			; no
	mov	ds:[CT_ESC],0
	mov	al,CHR_ESCAPE
	call	push_key
	call	wake_packet
eto9:	pop	ds
	ret
ENDPROC	esc_timeout

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; wake_packet
;
; Ends the wait of the first packet for the context that can now be
; satisfied: a READ packet whose data has arrived, or a WRITE packet whose
; context is no longer busy (ie, not full, paused, or being repainted).
;
; Inputs:
;	DS = context
;
; Outputs:
;	Carry set if a wait was ended (so an interrupt handler should yield)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	wake_packet
	mov	cx,cs:[0].DDH_DATA
	mov	es,cx
	mov	bx,offset wait_ptr	; CX:BX -> ptr
	les	di,es:[bx]		; ES:DI -> packet, if any
wk1:	cmp	di,-1			; end of chain?
	je	wk9			; yes (with carry clear)

	ASSERT	STRUCT,es:[di],DDP

	mov	ax,ds
	cmp	es:[di].DDP_CONTEXT,ax	; for this context?
	jne	wk8			; no
	cmp	es:[di].DDP_CMD,DDC_READ; READ packet?
	je	wk2			; yes, look for buffered data

	ASSERT	STRUCT,ds:[0],CT

	test	ds:[CT_STATUS],CTSTAT_BUSY
	jz	wk3			; transmitter is no longer busy
	jmp	short wk8		; still busy, check next packet
wk2:	call	pull_input		; pull more input data
	jc	wk8			; not enough data, check next packet
wk3:	and	ds:[CT_STATUS],NOT CTSTAT_INPUT
	mov	dx,es			; DX:DI -> packet (aka "wait ID")
	mov	ah,DOS_UTL_ENDWAIT
	call	far ptr DDINT_UTIL	; end the wait on DX:DI (see int_util)
;
; If ENDWAIT returns an error, it's because the wait was interrupted (eg, by
; ABORT or CTRLC) before we could end it; add_packet will see that the packet
; has been removed and treat the request as satisfied.  In the past, it could
; also mean that we got ahead of the WAIT call, but that race was resolved by
; making the pull_input/add_packet/wait path atomic (ie, no interrupts).
;
; TODO: Consider lighter-weight solutions to this race condition.
;
; In any case, proceed with the packet removal now.
;
	cli
	mov	ax,es:[di].DDP_PTR.OFF
	mov	dx,es:[di].DDP_PTR.SEG
	mov	es,cx
	mov	es:[bx].OFF,ax
	mov	es:[bx].SEG,dx
	sti
	stc
	ret
wk8:	lea	bx,[di].DDP_PTR		; update prev addr ptr in CX:BX
	mov	cx,es
	les	di,es:[di].DDP_PTR
	jmp	wk1
wk9:	ret
ENDPROC	wake_packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pull_output
;
; Remove a byte from CT_OUTPUT and transmit it.  If there are no more bytes,
; then clear CTSTAT_XMTFULL (unless the screen is being repainted; see paint).
;
; If the context is paused (or held because CTS is low), nothing is
; transmitted; resume_output restarts transmission when that ends.
;
; Inputs:
;	DS = context
;	ES:DI -> DDPRW
;
; Outputs:
;	If carry clear, AL = byte; otherwise carry set
;
; Modifies:
;	AX, BX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	pull_output
	test	ds:[CT_STATUS],CTSTAT_PAUSED OR CTSTAT_CTSOFF
	stc
	jnz	plo9			; paused or held, so transmit nothing
	mov	si,offset CT_OUTPUT
	call	pull_buffer
	jc	plo7
	call	write_thr
	jmp	short plo9
;
; The buffer is empty; if the screen is being repainted, add the next part
; (push_output transmits the first byte itself).
;
plo7:	test	ds:[CT_STATUS],CTSTAT_PAINT
	jz	plo8
	jmp	paint
;
; TODO: Think about the best time to clear CTSTAT_XMTFULL.  In theory, I can
; clear it every time we remove a single byte, instead of waiting for the buffer
; to become completely empty, but that could create increased context-switching
; overhead with minimal benefit.
;
plo8:	and	ds:[CT_STATUS],NOT CTSTAT_XMTFULL
plo9:	ret
ENDPROC	pull_output

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; push_output
;
; Add a byte to CT_OUTPUT, unless the context doesn't have the focus, in which
; case there's nothing to do: its shadow is all that changes (see update_col),
; and its screen is repainted from that when it gets the focus.
;
; Inputs:
;	AL = byte
;	DS = context
;
; Outputs:
;	CF clear if successful, CF set if buffer full
;
; Modifies:
;	BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	push_output
	cmp	ds:[CT_BACK],0		; does it have the focus?
	jne	pso9a			; no (and carry is clear)
	cli
	mov	si,offset CT_OUTPUT
	test	ds:[CT_STATUS],CTSTAT_PAUSED OR CTSTAT_CTSOFF
	jnz	pso7			; output is paused or held, so buffer
	call	peek_buffer		; anything in the output buffer?
	jnz	pso7			; yes, so continue to buffer
	push	ax
	call	read_lsr
	test	al,LSR_THRE		; is the transmitter is available?
	pop	ax
	jz	pso7			; no, so once again, we must buffer
	call	write_thr		; prime the pump
	jmp	short pso9
pso7:	call	push_buffer		; is there room in the buffer?
	jc	pso8			; no, mark it full
	mov	[bx],al			; yes, save the data
	jmp	short pso9
pso8:	or	ds:[CT_STATUS],CTSTAT_XMTFULL
	stc
pso9:	sti
pso9a:	ret
ENDPROC	push_output

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resume_output
;
; Called when a pause ends.  Since pull_output transmits nothing while paused,
; any THR interrupt that occurred during the pause was lost, so if the
; transmitter is available, we must "prime the pump" again.
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	resume_output
	cli
	call	read_lsr
	test	al,LSR_THRE		; is the transmitter available?
	jz	rso9			; no, so a THR interrupt is still due
	call	pull_output
rso9:	sti
	ret
ENDPROC	resume_output

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; check_cts
;
; Reads the Modem Status Register (which also clears any MSR interrupt), and
; for RTS/CTS flow control, holds output while CTS is low (CTSTAT_CTSOFF),
; resuming it when CTS rises.
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, DX, SI
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	check_cts
	mov	dx,ds:[CT_PORT]
	add	dx,REG_MSR		; DX -> MSR
	in	al,dx
	test	ds:[CT_STATUS],CTSTAT_RTS
	jz	ck9			; no RTS/CTS flow control
	test	al,MSR_CTS		; is CTS high?
	jz	ck8			; no, so hold output
	test	ds:[CT_STATUS],CTSTAT_CTSOFF
	jz	ck9			; output wasn't held
	and	ds:[CT_STATUS],NOT CTSTAT_CTSOFF
	jmp	resume_output
ck8:	or	ds:[CT_STATUS],CTSTAT_CTSOFF
ck9:	ret
ENDPROC	check_cts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_iir
;
; Inputs:
;	DS = context
;
; Outputs:
;	AL = Interrupt ID Register (IIR)
;
; Modifies:
;	AX, DX
;
DEFPROC	read_iir
	mov	dx,ds:[CT_PORT]
	add	dx,REG_IIR		; DX -> IIR
	in	al,dx
	ret
ENDPROC	read_iir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_lsr
;
; Inputs:
;	DS = context
;
; Outputs:
;	AL = Line Status Register (LSR)
;
; Modifies:
;	AX, DX
;
DEFPROC	read_lsr
	mov	dx,ds:[CT_PORT]
	add	dx,REG_LSR		; DX -> LSR
	in	al,dx
	ret
ENDPROC	read_lsr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_rbr
;
; Inputs:
;	DS = context
;
; Outputs:
;	AL = Receiver Buffer Register (RBR)
;
; Modifies:
;	AX, DX
;
DEFPROC	read_rbr
	mov	dx,ds:[CT_PORT]
	in	al,dx
	ret
ENDPROC	read_rbr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_mcr
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX
;
DEFPROC	write_mcr
	mov	ah,MCR_DTR OR MCR_OUT2	; OUT2 enables interrupts
	test	ds:[CT_STATUS],CTSTAT_RTS
	jz	wm1
	or	ah,MCR_RTS		; RTS tells the other end we're ready
wm1:	mov	dx,ds:[CT_PORT]
	add	dx,REG_MCR		; DX -> MCR
	in	al,dx
	jmp	$+2
	or	al,ah
	out	dx,al
	ret
ENDPROC	write_mcr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_ier
;
; Inputs:
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX
;
DEFPROC	write_ier
	mov	dx,ds:[CT_PORT]
	add	dx,REG_LCR		; DX -> LCR
	in	al,dx
	jmp	$+2
	and	al,not LCR_DLAB		; make sure the DLAB is not set
	out	dx,al			; so that we can set IER
	dec	dx
	dec	dx			; DX -> IER
	jmp	$+2
	mov	al,IER_THR_EMPTY OR IER_RBR_AVAIL OR IER_DELTA	; (see ddi3b)
	test	ds:[CT_STATUS],CTSTAT_RTS
	jz	wi1
	or	al,IER_MSR_DELTA	; CTS changes interrupt, too
wi1:	out	dx,al
	ret
ENDPROC	write_ier

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_irq
;
; This unmasks (on device open) or masks (on device close) the IRQ associated
; with the device.  We simplistically decide that it's IRQ4 if the port address
; is 3F8h and IRQ3 if the port address is 2F8h.
;
; Inputs:
;	AL = 0 to unmask IRQ, non-zero to mask
;	ES = context
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	write_irq
	mov	dx,es:[CT_PORT]
	mov	cl,dh			; DH should be either 2 or 3
	inc	cx
	mov	ah,1
	shl	ah,cl			; shift AL (01h) left 3 or 4 bits
	test	al,al
	in	al,21h			; read the PIC's IMR
	jnz	si8			; jump if masking
	not	ah
	and	al,ah			; unmask it
	jmp	short si9
si8:	or	al,ah			; mask it
si9:	out	21h,al			; update the PIC's IMR
	ret
ENDPROC	write_irq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_thr
;
; Inputs:
;	AL = data for Transmitter Holding Register (THR)
;	DS = context
;
; Outputs:
;	None
;
; Modifies:
;	DX
;
DEFPROC	write_thr
	mov	dx,ds:[CT_PORT]
	out	dx,al
	ret
ENDPROC	write_thr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; write_context
;
; Inputs:
;	AL = character
;	ES = context
;
; Outputs:
;	Carry clear if successful, set unable to buffer
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	write_context
	push	bx
	push	dx
	push	si
	push	ds
	push	es
	pop	ds			; DS is now the context
	mov	bl,ds:[CT_ROW]
	mov	bh,0
	cmp	ds:[CT_WIDE][bx],bh	; does the row need VT100_WIDE first?
	je	wct8			; yes
	DEFLBL	write_cell,near		; (paint_cell's entry; see wide_row)
	cmp	al,CHR_BACKSPACE	; BACKSPACE?
	je	wct2			; yes
	cmp	ds:[CT_TERM],TERM_VT100	; VT100 terminal?
	je	wct4			; yes
	call	push_output
wct1:	pop	ds
	pop	si
	pop	dx
	pop	bx
	ret
;
; Like the VKD$ driver, we treat a BACKSPACE written as data as "destructive"
; (the DOS line editor relies on that to erase characters; see con_erase), so
; it's sent as BACKSPACE, SPACE, BACKSPACE.  To avoid sending a partial sequence
; (which would be repeated when the write is retried), we don't start unless
; there's room for all of it.  Note that IOCTL_MOVCUR sends BACKSPACEs directly
; (see move_cur), since those are only supposed to move the cursor.
;
wct2:	push	ax
	call	output_room		; AX = free bytes in output buffer
	cmp	ax,3
	pop	ax
	jae	wct3
wct2a:	or	ds:[CT_STATUS],CTSTAT_XMTFULL
	stc
	jmp	wct1
wct3:	call	push_output		; BACKSPACE
	mov	al,CHR_SPACE
	call	push_output		; SPACE
	mov	al,CHR_BACKSPACE
	call	push_output		; BACKSPACE
	jmp	wct1
;
; A VT100 has no characters above 7Fh, but its special graphics set (which
; ddcom_open assigned to G1) replaces 5Fh-7Eh with line-drawing characters,
; so the PC's (B0h-DFh) are translated to those (see VT100_GFX): SO selects G1
; before the first one, and SI selects G0 again before the next character
; that isn't the same in both sets.  As with BACKSPACE, we don't start unless
; there's room for both bytes.
;
wct4:	push	ax
	mov	ah,VT100_SI
	cmp	al,5Fh			; same in both sets?
	jb	wct6			; yes
	sub	al,0B0h
	cmp	al,30h			; line-drawing character?
	jae	wct4a			; no
	mov	bx,offset VT100_GFX
	xlat	byte ptr cs:[bx]	; AL = special graphics character
	dec	ah			; AH = VT100_SO
	ASSERT	<VT100_SO>,EQ,<VT100_SI - 1>
	jmp	short wct5
wct4a:	add	al,0B0h
wct5:	cmp	ah,ds:[CT_GFX]		; is the set already selected?
	je	wct6			; yes
	push	ax
	call	output_room
	cmp	ax,2
	pop	ax
	jb	wct7
	mov	ds:[CT_GFX],ah
	xchg	al,ah
	call	push_output		; SO or SI
	mov	al,ah
wct6:	call	push_output
	pop	ax
	jmp	wct1
wct7:	pop	ax
	jmp	wct2a
;
; Make the row double-width (see wide_reset).  If there isn't room for what
; follows, the retry will find that this much is done.
;
wct8:	push	ax
	call	output_room
	cmp	ax,3
	pop	ax
	jb	wct2a
	inc	ds:[CT_WIDE][bx]
	push	ax
	mov	al,CHR_ESCAPE
	call	push_output
	mov	al,'#'
	call	push_output
	mov	al,'6'
	call	push_output
	pop	ax
	jmp	write_cell
ENDPROC	write_context

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; output_room
;
; Inputs:
;	DS = context
;
; Outputs:
;	AX = number of free bytes in CT_OUTPUT
;
; Modifies:
;	AX
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	output_room
	mov	ax,ds:[CT_OUTPUT].BUFHEAD
	sub	ax,ds:[CT_OUTPUT].BUFTAIL
	dec	ax			; AX = HEAD - TAIL - 1
	jge	or9			; no wrap
	add	ax,ds:[CT_OUTPUT].BUFEND
	sub	ax,ds:[CT_OUTPUT].BUFOFF
or9:	ret
ENDPROC	output_room

CODE	ends

CODE2	segment para public 'CODE'

	public	COM2
	DEFLEN	COM2_LEN,<COM2>
	DEFLEN	COM2_INIT,<COM2,COM3,COM4>
COM2	DDH	<COM2_LEN,,DDATTR_CHAR,COM2_INIT,,20202020324D4F43h>
;
; Every COM driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddcom_cmdp2
	DEFPTR	ddcom_intp2
	DEFWORD	ct_seg2,0
	DEFWORD	card_num2,0
	DEFWORD	ddcom_isr2,<offset ddcom_int2>

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
DEFPROC	ddcom_req2,far
	mov	ds,cs:[0].DDH_DATA	; (DOS doesn't need DS preserved)
	ASSUME	DS:CODE2
	jmp	[ddcom_cmdp2]		; DS = this port's data (see ddcom_cmd)
	ASSUME	DS:NOTHING
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
COM3	DDH	<COM3_LEN,,DDATTR_CHAR,COM3_INIT,,20202020334D4F43h>
;
; Every COM driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddcom_cmdp3
	DEFPTR	ddcom_intp3
	DEFWORD	ct_seg3,0
	DEFWORD	card_num3,0
	DEFWORD	ddcom_isr3,<offset ddcom_int3>

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
DEFPROC	ddcom_req3,far
	mov	ds,cs:[0].DDH_DATA	; (DOS doesn't need DS preserved)
	ASSUME	DS:CODE3
	jmp	[ddcom_cmdp3]		; DS = this port's data (see ddcom_cmd)
	ASSUME	DS:NOTHING
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
COM4	DDH	<COM4_LEN,,DDATTR_CHAR,COM4_INIT,,20202020344D4F43h>
;
; Every COM driver instance must define the next group of variables in
; the same location/order as shown below.
;
	DEFPTR	ddcom_cmdp4
	DEFPTR	ddcom_intp4
	DEFWORD	ct_seg4,0
	DEFWORD	card_num4,0
	DEFWORD	ddcom_isr4,<offset ddcom_int4>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	ds,cs:[0].DDH_DATA	; (DOS doesn't need DS preserved)
	ASSUME	DS:CODE4
	jmp	[ddcom_cmdp4]		; DS = this port's data (see ddcom_cmd)
	ASSUME	DS:NOTHING
ENDPROC	ddcom_req4

DEFPROC	ddcom_int4,far
	push	cx
	mov	cx,[ct_seg4]
	jmp	[ddcom_intp4]
ENDPROC	ddcom_int4

	DEFLBL	COM4_END

CODE4	ends

INIT	segment para public 'CODE'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	mov	ax,BIOS
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	si,offset RS232_BASE
	mov	di,bx			; ES:DI -> DDPI
	mov	bl,byte ptr cs:[DDH_NAME+3]
	dec	bx
	and	bx,0003h
	add	si,bx
	mov	dx,[si+bx]		; DX = BIOS RS232 port address
	mov	cx,[MEMORY_SIZE]	; CX = memory size (in K)
	mov	ds,cs:[0].DDH_DATA
	ASSUME	DS:DEV
	test	dx,dx			; exists?
	jz	in9			; no
	mov	[card_num],bx
	mov	ax,ds:[DDH_NEXT_OFF]	; yes, copy over the driver length
;
; With 64K or less, no port can have more than one console (see get_shadow),
; so COM1, whose code every port uses, ends where the code for that begins.
;
	test	bx,bx			; COM1?
	jnz	in0			; no
	cmp	cx,64			; more than 64K?
	ja	in0			; yes
	mov	ax,offset DEV:con_opt
in0:
	cmp	bl,3			; COM4?
	jne	in1			; no
	mov	ax,ds:[DDH_REQUEST]	; use the temporary ddcom_req offset

in1:	mov	es:[di].DDPI_END.OFF,ax
	mov	ds:[DDH_REQUEST],offset DEV:ddcom_req

	mov	[ddcom_cmdp].OFF,offset DEV:ddcom_cmd
	mov	[ddcom_intp].OFF,offset DEV:ddcom_int
in2:	mov	ax,0			; this MOV will be modified
	test	ax,ax			; on the first call to contain the CS
	jnz	in3			; of the first driver (this is the
	mov	ax,cs			; easiest way to communicate between
	mov	word ptr ds:[in2+1],ax	; the otherwise insulated drivers)
in3:	mov	[ddcom_cmdp].SEG,ax
	mov	[ddcom_intp].SEG,ax
;
; Determine the hardware interrupt vector for port DX
;
	mov	al,INT_HW_COM1
	cmp	dh,03h
	je	in4
	dec	ax
in4:	mov	cx,[ddcom_isr]		; CX = this port's interrupt entry
	mov	dx,cs
	call	far ptr DDINT_SETVEC

in9:	ret
ENDPROC	ddcom_init

	DEFLBL	ddcom_init_end

INIT	ends

DATA	segment para public 'DATA'

ddcom_end	db	16 dup(0)

DATA	ends

	end
