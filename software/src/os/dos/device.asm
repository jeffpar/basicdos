;
; BASIC-DOS Device Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSPSP equ 1
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTNEAR	<copy_name,sfb_from_sfh,sfb_read,sfb_write,strlen>
	EXTNEAR	<scb_release>
	EXTWORD	<scb_active,err_stack>
	EXTBYTE	<err_active,scb_locked>
	EXTLONG	<bpb_table>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_devname
;
; The name is copied to SCB_FILENAME + 1, and the copy ends at its first
; space (if any), so that a padded FCB name (eg, "CON        ") becomes an
; ASCIIZ name that can also be passed to the device's driver (see sfb_open).
;
; Inputs:
;	AH = 10h if DS:SI -> FCB (whose name follows its drive byte)
;	DS:SI -> name
;
; Outputs:
;	On success, ES:DI -> device driver header (DDH)
;	On failure, carry set
;
; Modifies:
;	CX, DI, ES
;
DEFPROC	chk_devname,DOS
	ASSUME	DS:NOTHING,ES:NOTHING
	push	ax
	push	si
	push	ds
	cmp	ah,10h			; FCB?
	jne	cd0a			; no
	inc	si			; yes, so skip FCB_DRIVE

cd0a:	mov	di,[scb_active]
	push	cs
	pop	es
	ASSUME	ES:DOS
	ASSERT	STRUCT,es:[di],SCB
	lea	di,[di].SCB_FILENAME + 1
	push	di
	call	copy_name
	pop	si
	push	es
	pop	ds			; DS:SI -> SCB_FILENAME + 1
	mov	di,si
	mov	al,' '
	mov	cx,size SCB_FILENAME - 1
	repne	scasb			; does the copy contain a space?
	jne	cd0			; no
	mov	byte ptr [di-1],0	; yes, so end the copy there

cd0:	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
	les	di,[DD_LIST]
	ASSUME	ES:NOTHING
cd1:	cmp	di,-1			; end of device list?
	stc
	je	cd9			; yes, search failed
	mov	cx,8
	push	si
	push	di
	add	di,DDH_NAME
	repe	cmpsb			; compare DS:SI to ES:DI
	je	cd3			; match
;
; This could still be a match if DS:[SI-1] is a colon or a null, and
; ES:[DI-1] is a space.
;
	mov	cl,[si-1]
	jcxz	cd2
	cmp	cl,':'
	jne	cd3
cd2:	cmp	byte ptr es:[di-1],' '
cd3:	pop	di
	pop	si
	je	cd9			; jump if all our compares succeeded
	les	di,es:[di]		; otherwise, on to the next device
	jmp	cd1

cd9:	pop	ds
	pop	si
	pop	ax
	ret
ENDPROC	chk_devname

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_console
;
; Checks for a request to open the CON device without a context descriptor
; (ie, "CON" or "CON:", as opposed to "CON:80,25"), which refers to the active
; session's console.  Since a session's console may be another device (eg,
; CONSOLE=COM1 in CONFIG.SYS), we return the session's console SFB, so that
; all operations on "CON" use the session's console device.
;
; Inputs:
;	DS:SI -> name
;	ES:DI -> device driver header (DDH) (from chk_devname)
;
; Outputs:
;	If carry clear, BX -> SFB of the active session's console
;	If carry set, this is not a request for the session's console
;
; Modifies:
;	AX, BX
;
DEFPROC	chk_console,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	cmp	word ptr es:[di].DDH_NAME,4F43h	; "CO"?
	jne	cc8
	cmp	word ptr es:[di].DDH_NAME+2,204Eh	; "N "?
	jne	cc8
	mov	al,[si+3]		; AL = character following "CON"
	test	al,al			; end of name?
	jz	cc1			; yes
	cmp	al,':'			; colon?
	jne	cc8			; no
	cmp	byte ptr [si+4],0	; anything after the colon?
	jne	cc8			; yes, so it's a context descriptor
cc1:	mov	bx,[scb_active]
	test	bx,bx			; is there an active session?
	jz	cc8			; no
	ASSERT	STRUCT,cs:[bx],SCB
	mov	bl,cs:[bx].SCB_SFHOUT	; BL = session console SFH
	cmp	bl,SFH_NONE		; has the console been opened yet?
	je	cc8			; no
	jmp	sfb_from_sfh		; BX -> SFB (carry set if invalid)
cc8:	stc
	ret
ENDPROC	chk_console

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; flush_console
;
; Called when DOS acts on a CTRLC: sends DDC_INFLUSH to the active session's
; console input (discarding type-ahead, including the CTRLC itself) and, if
; that succeeds, DDC_OUTFLUSH to its console output (ending any pause), so
; that DOS, rather than each console driver, decides what a CTRLC does.  Only
; devices whose context is the session's console context are flushed (eg, not
; a pipe).
;
; Inputs:
;	None
;
; Outputs:
;	Carry set if the session's input isn't its console (eg, a later
;	command in a pipeline, whose input is a pipe)
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	flush_console,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	mov	bx,cs:[scb_active]
	ASSERT	STRUCT,cs:[bx],SCB
	mov	ah,DDC_INFLUSH
	mov	cl,cs:[bx].SCB_SFHIN
	call	fc1			; carry set if not the console
	jc	fc9
;
; Only a session whose input is the console flushes its output; another
; session in the same pipeline (eg, MORE in "TYPE FILE | MORE") may act on
; the CTRLC later, and flushing then would discard the CTRLC echo (and even
; the next prompt).
;
	mov	bx,cs:[scb_active]
	mov	ah,DDC_OUTFLUSH
	mov	cl,cs:[bx].SCB_SFHOUT
	call	fc1
	clc
	ret
;
; Send request AX to the device for SFH CL, if its context is the session's
; console (BX -> SCB).
;
fc1:	mov	dx,cs:[bx].SCB_CONTEXT
	test	dx,dx			; does the session have a console?
	jz	fc8			; no
	cmp	cl,SFH_NONE		; is the SFH valid?
	je	fc8			; no
	push	ax
	mov	bl,cl
	call	sfb_from_sfh		; BX -> SFB
	pop	ax
	jc	fc9
	cmp	cs:[bx].SFB_CONTEXT,dx	; is it the session's console?
	jne	fc8			; no
	les	di,cs:[bx].SFB_DEVICE	; ES:DI -> driver
	sub	cx,cx			; no data
	call	dev_request
	clc
	ret
fc8:	stc
fc9:	ret
ENDPROC	flush_console

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; reset_keys
;
; Called when a program that enabled raw keys (see PSP_RAWKEYS) ends without
; disabling them (eg, after an ABORT): sends IOCTL_SETKEYS with CL = 0 to the
; active session's console input, so the console doesn't stay in raw keys mode.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	reset_keys,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	push	cx
	push	dx
	push	di
	push	es
	mov	bx,cs:[scb_active]
	ASSERT	STRUCT,cs:[bx],SCB
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_SETKEYS
	mov	cl,cs:[bx].SCB_SFHIN
	call	fc1			; (CX is zeroed for the request)
	pop	es
	pop	di
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	reset_keys

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dev_request
;
; Inputs:
;	AH = device driver command (DDC)
;	AL = unit # (block devices only)
;	DX = device driver context, zero if none
;	ES:DI -> device driver header (DDH)
;
; Additionally, for read/write requests:
;	BX = LBA (or other position data if not block device)
;	CX = byte count
;	DX = offset within LBA (or other context data if not block device)
;	DS:SI -> read/write data buffer
;
; For IOCTL requests, AL is the IOCTL code, except for block devices, where
; AL is the unit # and DH is the IOCTL code (see hdl_ioctl).
;
; Outputs:
;	If carry set, then AL contains error code
;	If carry clear, then DX contains context data, if any
;
; Modifies:
;	AX, DX
;
; Notes:
;	One of the main differences between our disk drivers and actual
;	MS-DOS disk drivers is that the latter puts the driver in charge of
;	allocating memory for BPBs.  I didn't feel that was appropriate.
;
;	Here, DOS creates the BPBs and requests the driver to check them
;	and rebuild them as needed; READ and WRITE requests also look up the
;	BPB and pass it to the driver via the DDPRW_BPB field.
;
DEFPROC	dev_request,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	bx
	push	bp
	sub	sp,DDP_MAXSIZE
	mov	bp,sp			; packet created on stack

	DBGINIT	STRUCT,[bp],DDP

	mov	word ptr [bp].DDP_UNIT,ax; set DDP_UNIT (AL) and DDP_CMD (AH)
	mov	[bp].DDP_STATUS,0
	mov	[bp].DDP_CODE,al	; set DDP_CODE for IOCTLs
	mov	[bp].DDP_CONTEXT,dx

	cmp	ah,DDC_OPEN
	jne	dr2
	mov	[bp].DDP_LEN,size DDP
	mov	[bp].DDP_PTR.OFF,si	; use DDP_PTR to pass driver-specific
	mov	[bp].DDP_PTR.SEG,ds	; parameter block, if any
	jmp	short dr5
;
; For now, we're going to treat all other commands, even MEDIACHK (1)
; and BUILDBPB (2), like READ (4) and WRITE (8); that includes IOCTLIN (3)
; and IOCTLOUT (12).
;
dr2:	mov	[bp].DDP_LEN,size DDPRW
	mov	[bp].DDPRW_ADDR.OFF,si
	mov	[bp].DDPRW_ADDR.SEG,ds
	mov	[bp].DDPRW_LBA,bx
	mov	[bp].DDPRW_OFFSET,dx
	mov	[bp].DDPRW_LENGTH,cx
;
; Even though all the above commands get a DDPRW request packet, only block
; devices get certain fields filled in (eg, the BPB pointer).
;
	test	es:[di].DDH_ATTR,DDATTR_CHAR
	jnz	dr5
;
; A block device IOCTL carries its code in DH (see hdl_ioctl), since AL is
; the unit #.
;
	cmp	[bp].DDP_CMD,DDC_IOCTLIN
	jne	dr4
	mov	[bp].DDP_CODE,dh
dr4:	mov	ah,size BPBEX		; AL still contains the unit #
	mul	ah
	add	ax,[bpb_table].OFF	; AX = BPB address
	mov	[bp].DDPRW_BPB.OFF,ax	; save it in the request packet
	mov	[bp].DDPRW_BPB.SEG,cs

dr5:	push	es			; create far pointer to DDH_REQUEST
	push	es:[di].DDH_REQUEST	; at [bp-4]

	push	ss
	pop	es
	mov	bx,bp			; ES:BX -> packet
;
; To make it easier on drivers, don't force them to preserve all registers;
; there were some they already didn't need to preserve in BASIC-DOS (ie, AX,
; BX, DX, and ES), so by adding 5 more registers, we can simplify the rules.
;
	push	cx
	push	si
	push	di
	push	bp
	push	ds

	ASSERT	NZ,<cmp word ptr [bp-2],0>
	call	dword ptr [bp-4]	; far call to DDH_REQUEST

	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	cx

	pop	ax			; toss DDH_REQUEST pointer offset
	pop	es			; ES restored

	mov	ax,[bp].DDP_STATUS
	test	ax,DDSTAT_ERROR
	jnz	dr8
dr6:	mov	bx,[bp].DDPRW_LENGTH	; BX = # bytes remaining
	mov	dx,[bp].DDP_CONTEXT
	add	sp,DDP_MAXSIZE
	mov	ax,cx			; AX = # bytes originally requested
	sub	ax,bx			; AX = # bytes returned (if read/write)
	clc
	jmp	short dr9
;
; Convert the driver's error code (DDERR_*) to a DOS error code: like DOS 3.x,
; we use the critical error codes (19-31), so that "drive not ready" (21) is
; distinguishable from (for example) "file not found".  Any error that isn't
; in the table is a general failure (31).
;
dr8:	push	si
	mov	si,offset dev_errs
dr8a:	cmp	cs:[si],al		; does the driver error match?
	je	dr8b			; yes
	cmp	byte ptr cs:[si],0	; end of table?
	je	dr8b			; yes
	inc	si
	inc	si
	jmp	dr8a
dr8b:	mov	al,cs:[si+1]
	cbw				; AX = DOS error code
	pop	si
;
; Block device errors are hard errors: report the error to the session's
; ERROR handler (see dev_error) and act on its response.  RETRY reissues the
; request (the packet is still on the stack, and the driver has advanced it
; to the failing sector), IGNORE reports the request as complete, and FAIL
; returns the error.  IOCTL errors (eg, a FORMAT failure) are returned to
; the caller, which is presumably prepared to deal with them.
;
	test	es:[di].DDH_ATTR,DDATTR_CHAR
	jnz	dr8f			; character device errors just fail
	cmp	[bp].DDP_CMD,DDC_IOCTLIN
	je	dr8f			; as do IOCTL errors
	push	ax
	call	dev_error		; AL = response
	mov	dl,al			; DL = response
	pop	ax			; AX = DOS error code again
	cmp	dl,CRERR_RETRY
	jne	dr8c
	mov	[bp].DDP_STATUS,0
	jmp	dr5			; reissue the request
dr8c:	cmp	dl,CRERR_IGNORE
	jne	dr8f
	mov	[bp].DDPRW_LENGTH,0	; nothing remains (all "transferred")
	jmp	short dr6
dr8f:	add	sp,DDP_MAXSIZE
	stc

dr9:	pop	bp
	pop	bx
	ret
ENDPROC	dev_request

dev_errs	db	DDERR_WP,19, DDERR_UNKUNIT,20, DDERR_NOTREADY,21
		db	DDERR_UNKCMD,22, DDERR_CRC,23, DDERR_SEEK,25
		db	DDERR_UNKMEDIA,26, DDERR_NOSECTOR,27, DDERR_WRFAULT,29
		db	DDERR_RDFAULT,30, 0,31

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dev_error
;
; Hard (critical) error service, called by dev_request when a block device
; request fails.  The session's ERROR handler (INT 24h; see SCB_ERROR) is
; called with the PC DOS inputs:
;
;	AH = CRERR_WRITE if the request was a write; CRERR_AREA bits = disk
;	     area of the failing sector (0 reserved, 2 FAT, 4 directory, 6
;	     data); CRERR_FAILOK, CRERR_RETRYOK, and CRERR_IGNOREOK = allowed
;	     responses (IGNORE is allowed only for READ and WRITE requests)
;	AL = drive #
;	DI = error code (0-12; ie, the DOS error code minus 19)
;	BP:SI -> device driver header (DDH)
;
; and returns AL = response (CRERR_*), which we return to dev_request.
;
; The handler runs on the hard error stack (see err_stack), since the stack
; of the program that made the DOS call may have little room to spare, with
; the SCB locked, so that no other session can run (and no other hard error
; can occur) until the handler returns.  A hard error inside the handler
; itself (which PC DOS forbids as well) fails immediately (see err_active),
; and a CTRLC signal inside the handler ends it with an ABORT response (see
; msc_sigctrlc and err_jump).
;
; ABORT becomes a FAIL response, plus a pending session ABORT of type
; EXTYPE_ERROR, so that every function on the way back out of DOS unwinds
; (and unlocks) normally, and then dos_leave terminates the program (see
; psp_termcode); any pending CTRLC (eg, typed at the prompt) is consumed.
; IGNORE becomes FAIL if it wasn't allowed, as does any unknown response.
;
; Inputs:
;	AX = DOS error code (19-31)
;	BP -> request packet (DDP)
;	ES:DI -> device driver header (DDH)
;
; Outputs:
;	AL = response (CRERR_IGNORE, CRERR_RETRY, or CRERR_FAIL)
;
; Modifies:
;	AX
;
DEFPROC	dev_error,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	LOCK_SCB
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	push	ds
	push	es
	cmp	[err_active],0		; already handling a hard error?
	je	he0			; no
	jmp	he7			; yes, so fail this one, too
he0:	mov	si,di			; SI = DDH offset (for BP:SI)
	xchg	ax,di
	sub	di,19			; DI = INT 24h error code (0-12)
	mov	ax,word ptr [bp].DDP_UNIT; AL = drive #, AH = command
	mov	cl,CRERR_FAILOK OR CRERR_RETRYOK
	cmp	ah,DDC_READ		; READ request?
	je	he1			; yes
	cmp	ah,DDC_WRITE		; WRITE (or WRITEV) request?
	jb	he2			; no (eg, MEDIACHK or BUILDBPB)
	cmp	ah,DDC_WRITEV
	ja	he2			; no
	or	cl,CRERR_WRITE
;
; Only READ and WRITE requests allow IGNORE (eg, there's no ignoring a BPB
; the driver couldn't build), and only they have a meaningful disk area.
;
he1:	or	cl,CRERR_IGNOREOK OR CRERR_AREA
	mov	bx,[bp].DDPRW_BPB.OFF	; BX -> BPB (in the DOS segment)
	mov	dx,[bp].DDPRW_LBA	; DX = LBA of the failing sector
	cmp	dx,cs:[bx].BPB_LBADATA	; data area?
	jae	he2			; yes
	sub	cl,2			; no, directory?
	cmp	dx,cs:[bx].BPB_LBAROOT
	jae	he2			; yes
	sub	cl,2			; no, FAT?
	cmp	dx,cs:[bx].BPB_RESSECS
	jae	he2			; yes
	sub	cl,2			; no, reserved area
he2:	mov	ah,cl			; AH = flags
;
; Switch to the hard error stack, saving the caller's stack, the flags, and
; SCB_INDOS (in case a CTRLC inside the handler ends it early; see err_jump)
; on it.
;
	mov	dx,ss
	mov	cx,sp
	cli
	push	cs
	pop	ss
	mov	sp,[err_stack]
	sti
	push	cs
	pop	ds			; DS = DOS (for the handler as well)
	mov	bx,[scb_active]
	push	dx
	push	cx			; caller's SS:SP
	push	ax			; AH = flags
	push	word ptr [bx].SCB_INDOS
	ASSERT	ERR_FRAME,EQ,8
	inc	[err_active]
	mov	bp,es			; BP:SI -> DDH
	pushf
	call	[bx].SCB_ERROR		; call the session's ERROR handler
	DEFLBL	err_jump,near		; (AL = CRERR_ABORT via msc_sigctrlc)
	push	cs
	pop	ds
	mov	bx,[scb_active]
	mov	[err_active],0
	pop	word ptr [bx].SCB_INDOS
	pop	dx			; DH = flags
	pop	cx
	pop	bx			; BX:CX = caller's SS:SP
	cli
	mov	ss,bx
	mov	sp,cx
	sti
	mov	bx,[scb_active]
	cmp	al,CRERR_RETRY
	je	he8
	cmp	al,CRERR_IGNORE
	jne	he3
	test	dh,CRERR_IGNOREOK	; was IGNORE allowed?
	jnz	he8			; yes
	jmp	short he7		; no
he3:	cmp	al,CRERR_ABORT
	jne	he7
	or	[bx].SCB_STATUS,SCSTAT_ABORT
	mov	[bx].SCB_ABTYPE,EXTYPE_ERROR
	mov	[bx].SCB_CTRLC_ACT,0
he7:	mov	al,CRERR_FAIL
he8:	pop	es
	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	UNLOCK_SCB_RET		; unlock the SCB and return
ENDPROC	dev_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dos_error (default INT 24h handler)
;
; Displays the traditional PC DOS message on the session's console (eg, "Not
; ready error reading drive A"), followed by "Abort, Retry, Fail? " (or
; "Abort, Retry, Ignore, Fail? " if IGNORE is allowed), and reads the
; response, repeating the prompt until a valid one is typed.  CTRLC (or a
; console read failure, eg, due to a pending ABORT) is treated as ABORT.
; A session whose input isn't its console (eg, a command reading from a pipe)
; can't be prompted, so after the message, its response is FAIL.
;
; Inputs:
;	See dev_error
;
; Outputs:
;	AL = response (CRERR_*)
;
DEFPROC	dos_error,DOSFAR
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	dx,ax			; DH = flags, DL = drive #
	mov	cx,di			; CX = error code
	mov	si,offset ERR_CRLF
	call	err_print
	mov	si,offset ERR_MSGS
	jcxz	ee1
ee0:	call	err_skip		; skip CX messages
	loop	ee0
ee1:	call	err_print		; eg, "Not ready"
	mov	si,offset ERR_ERROR
	call	err_print		; " error "
	test	dh,CRERR_WRITE		; was the request a write?
	jz	ee2			; no
	call	err_skip		; yes, skip "reading"
ee2:	call	err_print		; "reading" or "writing"
	mov	si,offset ERR_DRIVE
	call	err_print		; " drive "
	mov	al,dl
	add	al,'A'
	call	err_char		; drive letter
	mov	bx,[scb_active]
	mov	al,[bx].SCB_SFHIN
	cmp	al,[bx].SCB_SFHERR	; is the session's input its console?
	jne	ee8			; no, so FAIL
ee4:	mov	si,offset ERR_PROMPT
	call	err_print		; "Abort, Retry, "
	test	dh,CRERR_IGNOREOK	; is IGNORE allowed?
	jz	ee5			; no
	mov	si,offset ERR_IGNORE
	call	err_print		; "Ignore, "
	mov	si,offset ERR_FAIL
ee5:	call	err_print		; "Fail? "
	mov	bx,[scb_active]
	mov	bl,[bx].SCB_SFHIN
	call	sfb_from_sfh		; BX -> SFB for the console
	push	dx
	push	ax			; make room for the response
	mov	dx,sp
	push	ss
	pop	es			; ES:DX -> response
	mov	cx,1
	mov	al,IO_RAW
	call	sfb_read		; read one character (no CTRLC checks)
	pop	ax			; AL = response
	pop	dx
	jc	ee7			; read failure (eg, ABORT pending)
	and	al,0DFh			; upper-case the response
	cmp	al,CHR_CTRLC
	je	ee7			; CTRLC means ABORT
	mov	dl,al			; DL = response character
	call	err_char		; echo it
	mov	si,offset ERR_KEYS
ee6:	lodsw				; AL = key, AH = response
	test	al,al			; end of table?
	jz	ee4			; yes, so repeat the prompt
	cmp	al,dl			; match?
	jne	ee6			; no
	mov	dl,ah			; DL = response
	jmp	short ee9

ee7:	mov	dl,CRERR_ABORT
	jmp	short ee9
ee8:	mov	dl,CRERR_FAIL
ee9:	mov	si,offset ERR_CRLF
	call	err_print
	mov	al,dl			; AL = response
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	iret
ENDPROC	dos_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; err_char
;
; Prints the character in AL on the session's console (see err_print).
;
; Inputs:
;	AL = character
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	err_char,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	si
	push	ds
	mov	ah,0
	push	ax			; AX = one-character string
	mov	si,sp
	push	ss
	pop	ds			; DS:SI -> string
	call	err_print
	pop	ax
	pop	ds
	pop	si
	ret
ENDPROC	err_char

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; err_print
;
; Prints the null-terminated string at DS:SI on the session's console (via
; its STDERR SFB, with a raw write, so there are no CTRLC checks), and
; advances SI past the string, so that consecutive strings can be printed
; with consecutive calls.
;
; Inputs:
;	DS:SI -> string
;
; Outputs:
;	SI -> byte after the string's terminator
;
; Modifies:
;	AX, BX, CX, DI, ES
;
DEFPROC	err_print,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	dx
	mov	al,0
	call	strlen			; AX = length of string at DS:SI
	xchg	cx,ax			; CX = length
	mov	bx,[scb_active]
	mov	bl,cs:[bx].SCB_SFHERR
	call	sfb_from_sfh		; BX -> SFB for the console
	mov	al,IO_RAW
	call	sfb_write
	add	si,cx
	inc	si			; SI -> next string
	pop	dx
	ret
ENDPROC	err_print

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; err_skip
;
; Advances SI past the null-terminated string at DS:SI.
;
; Inputs:
;	DS:SI -> string
;
; Outputs:
;	SI -> byte after the string's terminator
;
; Modifies:
;	AL
;
DEFPROC	err_skip,DOS
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
sk1:	lodsb
	test	al,al			; end of string?
	jnz	sk1			; no
	ret
ENDPROC	err_skip

;
; Messages for INT 24h error codes 0-12 (codes 5 and 9 are never produced by
; dev_request, so their messages are empty), followed by the other strings
; that dos_error prints, in the order it prints them (see err_print).
;
ERR_MSGS	db	"Write protect",0
		db	"Unknown unit",0
		db	"Not ready",0
		db	"Unknown command",0
		db	"Data",0
		db	0
		db	"Seek",0
		db	"Unknown media",0
		db	"Sector not found",0
		db	0
		db	"Write fault",0
		db	"Read fault",0
		db	"General failure",0
ERR_ERROR	db	" error ",0
		db	"reading",0
		db	"writing",0
ERR_DRIVE	db	" drive ",0
ERR_PROMPT	db	13,10,"Abort, Retry, ",0
ERR_FAIL	db	"Fail? ",0
ERR_IGNORE	db	"Ignore, ",0
ERR_CRLF	db	13,10,0
ERR_KEYS	db	'A',CRERR_ABORT,'R',CRERR_RETRY,'I',CRERR_IGNORE
		db	'F',CRERR_FAIL,0,0

DOS	ends

	end
