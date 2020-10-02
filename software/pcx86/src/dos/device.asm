;
; BASIC-DOS Device Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	dev.inc
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<bpb_table>,dword
	IF REG_CHECK
	EXTERNS	<dos_check>,near
	ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chk_devname
;
; Inputs:
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
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	sub	di,di
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
cd9:	ret
ENDPROC	chk_devname

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

	mov	word ptr [bp].DDP_UNIT,ax; sets DDP_UNIT (AL) and DDP_CMD (AH)
	mov	[bp].DDP_STATUS,0
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

	call	dword ptr [bp-4]	; far call to DDH_REQUEST

	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	cx

	pop	ax			; toss DDH_REQUEST pointer offset
	pop	es			; ES restored

	mov	ax,[bp].DDP_STATUS
	mov	dx,[bp].DDP_CONTEXT
	add	sp,DDP_MAXSIZE
	test	ax,DDSTAT_ERROR
	jz	dr9
	stc				; AL contains device error code

dr9:	pop	bp
	pop	bx
	ret
ENDPROC	dev_request

DOS	ends

	end
