;
; BASIC-DOS Device Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	devapi.inc
	include	dos.inc

DOS	segment word public 'CODE'

	EXTNEAR	<copy_name,sfb_from_sfh>
	EXTWORD	<scb_active>
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
	mov	ah,size BPBEX		; AL still contains the unit #
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
	mov	bx,[bp].DDPRW_LENGTH	; BX = # bytes remaining
	mov	dx,[bp].DDP_CONTEXT
	add	sp,DDP_MAXSIZE
	test	ax,DDSTAT_ERROR
	jnz	dr8
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
	stc

dr9:	pop	bp
	pop	bx
	ret
ENDPROC	dev_request

dev_errs	db	DDERR_WP,19, DDERR_UNKUNIT,20, DDERR_NOTREADY,21
		db	DDERR_UNKCMD,22, DDERR_CRC,23, DDERR_SEEK,25
		db	DDERR_UNKMEDIA,26, DDERR_NOSECTOR,27, DDERR_WRFAULT,29
		db	DDERR_RDFAULT,30, 0,31

DOS	ends

	end
