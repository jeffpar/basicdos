;
; BASIC-DOS V86 Utility: BIOS Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The machine has no ROM BIOS of its own to call (its code does I/O, which a
; V86 machine can't), so the common video (INT 10h), keyboard (INT 16h), and
; printer (INT 17h) functions that its programs ask for are done here, with
; the console driver's functions (see IOCTL_CON in devapi.inc) and DOS's,
; for the current PSP's STDERR (the screen), STDIN (the keys), and STDPRN,
; and so is the BIOS tick count (INT 1Ah).
; So they work on any console that those functions do (eg, a terminal), and
; only as well: a window is always as wide as the screen, and a character
; that the console acts on (eg, RETURN) can't be drawn.  A mode that the
; console's adapter has but its driver doesn't draw in (an EGA or VGA's
; graphics modes) is for programs that draw for themselves, in the video
; memory that the machine has then (and with the video ports; see CPU_V86).
;
	BIOSAPI equ 1
	include	v86host.inc

CODE    SEGMENT word public 'CODE'

	EXTBYTE	<VARS>
	EXTWORD	<machine>
	EXTNEAR	<run,pft_load,seg_ptr>

	.286c

        ASSUME  CS:CODE, DS:CODE, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; int10
;
; Does the video function that the machine's program asked for (00h-0Fh; the
; ones with no console equivalent do nothing, as do any others), and then
; runs the machine again.
;
	DEFLBL	I10_PROCS,word
	dw	v0,v1,v2,v3,v4,v9,v6,v6,v10,v11,v11,v9,v9,v9,v14,v15
I10_MAX	equ	($ - I10_PROCS) / 2 - 1

DEFPROC	int10
	call	pft_load
	mov	ax,word ptr [VARS+VR_EAX]
	mov	cx,word ptr [VARS+VR_ECX]
	mov	dx,word ptr [VARS+VR_EDX]
	mov	di,ax
	shr	di,8
	cmp	di,I10_MAX		; one of the functions we know?
	ja	dc1			; no
	shl	di,1
	jmp	I10_PROCS[di]
;
; Get the display combination (AX = 1A00h), which only a VGA's BIOS has (and
; is how programs know there's one): AL = 1Ah, and BL = 8 (a VGA with a
; color display), if the machine's BIOS data says so.
;
dc1:	cmp	ax,VIDEO_GETDCC
	jne	dc9
	sub	ax,ax
	mov	di,BIOS_DATA + offset VGA_FLAGS
	call	seg_ptr
	test	byte ptr es:[di],1	; is a VGA active?
	jz	dc9			; no
	mov	byte ptr [VARS+VR_EAX],1Ah
	mov	word ptr [VARS+VR_EBX],0008h
dc9:	jmp	run
;
; Set the mode (AL), the cursor's type (hidden if CH bit 5 is set), or its
; position (DH = row, DL = column).
;
v0:	and	al,7Fh
	xchg	cx,ax			; CL = mode
	mov	al,IOCTL_SETMODE
	jmp	short v8
v1:	and	ch,20h
	cmp	ch,1			; carry set if not hidden
	mov	dx,0
	adc	dl,dl			; DL = 1 to show it, or 0
	mov	cx,-1			; (it stays where it is)
	jmp	short v2a
v2:	mov	cx,dx
	mov	dx,00FFh		; (it stays as visible as it is)
v2a:	mov	al,IOCTL_SETPOS
v8:	call	con_ioctl
v9:	jmp	run
;
; Get the cursor's position (DH = row, DL = column) and type (CX).
;
v3:	mov	al,IOCTL_GETPOS
	call	con_ioctl
	mov	word ptr [VARS+VR_EDX],dx
	mov	word ptr [VARS+VR_ECX],0607h
	jmp	v9
;
; There's no light pen (AH = 0).
;
v4:	mov	byte ptr [VARS+VR_EAX+1],0
	jmp	v9
;
; Scroll rows CH through DH up (06h) or down (07h) by AL rows, or clear them
; if AL is zero, filling with attributes BH: they become the scrolling rows
; while we scroll them, and then the scrolling rows are every row again.
; The cursor and the console's attributes stay as they were (see v12).
;
v6:	call	con_save
	mov	cl,byte ptr [VARS+VR_EBX+1]
	call	set_color
	mov	dl,byte ptr [VARS+VR_ECX+1]
	mov	dh,byte ptr [VARS+VR_EDX+1]
	inc	dh			; DL = first row, DH = last row + 1
	call	set_rows
	mov	ax,word ptr [VARS+VR_EAX]
	mov	cl,al
	mov	ch,0			; CX = rows (up)
	cmp	ah,VIDEO_SCROLL
	je	v6a
	neg	cx			; (down)
v6a:	sub	dx,dx			; (CX = 0 and DX = 0 clears them)
	mov	al,IOCTL_SCROLL
	call	con_ioctl
	mov	al,IOCTL_GETDIM
	call	con_ioctl		; DH = rows
	mov	dl,0
	call	set_rows
	jmp	v12
;
; Get the character (AL) and attributes (AH) at the cursor.
;
v10:	mov	al,IOCTL_GETPOS
	call	con_ioctl
	mov	cx,dx
	mov	al,IOCTL_GETCHAR
	call	con_ioctl		; DL = character, DH = attributes
	jnc	v10a
	mov	dx,0720h		; (the console can't say, so a space)
v10a:	mov	word ptr [VARS+VR_EAX],dx
	jmp	v9
;
; Write CX copies of the character AL at the cursor, which doesn't move, with
; attributes BL (09h) or the ones in use (0Ah).
;
v11:	call	con_save
	mov	ax,word ptr [VARS+VR_EAX]
	cmp	ah,VIDEO_WRITECA
	jne	v11a
	mov	cl,byte ptr [VARS+VR_EBX]
	call	set_color
v11a:	mov	cx,word ptr [VARS+VR_ECX]
	cmp	cx,BUF_LEN		; more than V_BUF holds?
	jbe	v11b			; no
	mov	cx,BUF_LEN
v11b:	mov	di,offset VARS + V_BUF
	push	ds
	pop	es
	push	cx
	mov	al,byte ptr [VARS+VR_EAX]
	rep	stosb
	pop	cx
;
; The console wraps (and scrolls) after a write that reaches the end of its
; last row, which the BIOS doesn't do, so for one of those, the last row
; isn't a scrolling row meanwhile.
;
	mov	bp,sp
	push	cx
	mov	al,IOCTL_GETDIM
	call	con_ioctl		; DL = columns, DH = rows
	pop	cx
	sub	di,di			; DI = 0 unless it's one of those
	mov	bx,[bp+2]		; BL = column, BH = row
	dec	dh
	cmp	bh,dh			; on the last row?
	jne	v11c			; no
	mov	al,bl
	mov	ah,0
	add	ax,cx
	mov	bl,dl
	mov	bh,0
	cmp	ax,bx			; and reaching its last column?
	jb	v11c			; no
	push	cx
	mov	dl,0			; DL = first row, DH = last row
	mov	di,dx
	call	set_rows		; (which moves the cursor)
	mov	cx,[bp+2]
	mov	dx,00FFh
	mov	al,IOCTL_SETPOS
	call	con_ioctl
	pop	cx
v11c:	mov	dx,offset VARS + V_BUF
	call	con_write
	test	di,di
	jz	v12
	mov	dx,di
	inc	dh			; every row is a scrolling row again
	call	set_rows
;
; Restore the console's attributes and the cursor (see con_save).
;
v12:	pop	cx			; CL = attributes
	call	set_color
	pop	dx			; DL = column, DH = row
	jmp	v2
;
; Write the character AL, as a terminal would.
;
v14:	mov	dx,offset VARS + VR_EAX
	mov	cx,1
	call	con_write
	jmp	v9
;
; Get the mode (AL) and the number of columns (AH); the page (BH) is zero.
;
v15:	mov	cl,0
	mov	al,IOCTL_GETMODE
	call	con_ioctl		; DL = mode
	jnc	v15a
	mov	dl,MODE_CO80		; (the console has no modes)
v15a:	push	dx
	mov	al,IOCTL_GETDIM
	call	con_ioctl		; DL = columns
	pop	ax
	mov	ah,dl
	mov	word ptr [VARS+VR_EAX],ax
	mov	byte ptr [VARS+VR_EBX+1],0
	jmp	v9
ENDPROC	int10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; con_ioctl, con_write, con_save, set_color, and set_rows
;
; con_ioctl does the console function AL (IOCTL_*) with CX and DX, con_write
; writes CX bytes at DX, set_color sets the console's attributes to CL, and
; set_rows sets its scrolling rows (DL = first row, DH = last row + 1), which
; moves the cursor.  con_save leaves the cursor's position and the console's
; attributes on the stack, for v12.
;
; Modifies:
;	AX, BX, CX, DX (and SI, for con_save)
;
DEFPROC	con_save
	pop	si			; (our return address)
	mov	al,IOCTL_GETPOS
	call	con_ioctl
	push	dx			; DL = column, DH = row
	mov	al,IOCTL_GETCOLOR
	call	con_ioctl
	push	dx			; DL = attributes
	jmp	si
ENDPROC	con_save

DEFPROC	set_rows
	sub	cx,cx
	mov	al,IOCTL_SCROLL
	jmp	short con_ioctl
ENDPROC	set_rows

DEFPROC	set_color
	mov	dx,00FFh		; (all of them, and not the border's)
	mov	al,IOCTL_SETCOLOR
ENDPROC	set_color			; fall into con_ioctl

DEFPROC	con_ioctl
	mov	ah,DOS_HDL_IOCTL
	DEFLBL	con_dos,near
	mov	bx,STDERR
	int	21h
	ret
ENDPROC	con_ioctl

DEFPROC	con_write
	mov	ah,DOS_HDL_WRITE
	jmp	con_dos
ENDPROC	con_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; int16
;
; Does the keyboard function that the machine's program asked for, and then
; runs the machine again: 00h waits for a key (AL = character, or zero and
; AH = scan code), 01h returns the next key without removing it (or the zero
; flag set if there's none), and 02h has no shift states to return; 10h-12h
; are the same.
;
DEFPROC	int16
	call	pft_load
	mov	ax,word ptr [VARS+VR_EAX]
	and	ah,NOT 10h
	cmp	ah,KBD_CHECK
	ja	k2
	mov	si,ax			; SI = 0 for KBD_CHECK
	xor	si,KBD_CHECK SHL 8
	and	si,0FF00h
	call	key_get			; AX = key (zero flag set if none)
	jz	k3
	and	byte ptr [VARS+VR_EFL],NOT FL_ZERO
	test	si,si			; KBD_READ?
	jz	k1			; no
	mov	[key_have],0
k1:	mov	word ptr [VARS+VR_EAX],ax
k9:	jmp	run
k2:	cmp	ah,KBD_CHECK + 1
	jne	k9
	mov	byte ptr [VARS+VR_EAX],0
	jmp	k9
k3:	or	byte ptr [VARS+VR_EFL],FL_ZERO
	jmp	k9
ENDPROC	int16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; key_get
;
; Returns the next key, which stays in key_ax until KBD_READ takes it.  We
; read it in raw keys mode (see set_keys), so that CTRL-C is a key, as
; it is for the BIOS, and every other key is as DOS returns it: a character,
; or a zero and then a scan code.
;
; Inputs:
;	SI = 0 to return at once if there's no key, or nonzero to wait
;
; Outputs:
;	Zero flag clear: AX = key (AL = character, or zero and AH = scan code)
;	Zero flag set if there's no key
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	key_get
	mov	ax,[key_ax]
	cmp	[key_have],0		; do we have one already?
	jne	kg9			; yes
	mov	cl,3
	call	set_keys
	test	si,si			; waiting for one?
	jnz	kg1			; yes
	mov	dl,0FFh
	mov	ah,DOS_TTY_IO
	int	21h			; is there one?
	jz	kg8			; no
	jmp	short kg1a
kg1:	mov	ah,DOS_TTY_IN
	int	21h
kg1a:	mov	ah,0
	test	al,al			; a scan code next?
	jnz	kg2			; no
	mov	ah,DOS_TTY_IN
	int	21h
	mov	ah,al
	mov	al,0
kg2:	mov	[key_ax],ax
	inc	[key_have]		; (which clears the zero flag)
kg8:	pushf
	push	ax
	mov	cl,2
	call	set_keys
	pop	ax
	popf
kg9:	ret
ENDPROC	key_get

;
; set_keys sets the console's raw keys mode (CL bit 0), and tells it where
; the machine's BIOS data is (CL bit 1, and the machine's first selector), so
; that it keeps the keyboard data there current (see IOCTL_SETKEYS): some
; programs call INT 16h only when the BIOS's keyboard buffer isn't empty (eg,
; BASIC compares BUFFER_HEAD and BUFFER_TAIL).  CL = 0 ends that.
;
DEFPROC	set_keys
	mov	dx,[machine]
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SETKEYS
	mov	bx,STDIN
	int	21h
	ret
ENDPROC	set_keys

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; int17
;
; Does the printer function that the machine's program asked for: 00h prints
; the character AL, by writing it to the current PSP's STDPRN, and returns
; the status that 01h (initialize) and 02h (get status) always return, which
; is selected and not busy (90h), or if the write failed, a time-out (01h).
;
DEFPROC	int17
	call	pft_load
	cmp	byte ptr [VARS+VR_EAX+1],0
	jne	p8
	mov	dx,offset VARS + VR_EAX
	mov	cx,1
	mov	bx,STDPRN
	mov	ah,DOS_HDL_WRITE
	int	21h
	mov	al,01h
	jc	p9
p8:	mov	al,90h
p9:	mov	byte ptr [VARS+VR_EAX+1],al
	jmp	run
ENDPROC	int17

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; int1a
;
; Does the time function that the machine's program asked for: 00h returns
; the BIOS tick count in CX:DX (eg, for a C program's startup code), with AL
; zero, since midnight is DOS's to see; any other returns with carry set, as
; the real-time clock functions do when there's no clock.
;
DEFPROC	int1a
	cmp	byte ptr [VARS+VR_EAX+1],TIME_GETTICKS
	jne	t8
	DOSUTIL	GETTIME,1		; DX:AX = BIOS tick count
	mov	word ptr [VARS+VR_EDX],ax
	mov	word ptr [VARS+VR_ECX],dx
	mov	byte ptr [VARS+VR_EAX],0
	jmp	short t9
t8:	or	byte ptr [VARS+VR_EFL],FL_CARRY
t9:	jmp	run
ENDPROC	int1a

	DEFWORD	key_ax,0		; the next key (see key_get)
	DEFBYTE	key_have,0		; nonzero if key_ax has one

CODE	ENDS

	end
