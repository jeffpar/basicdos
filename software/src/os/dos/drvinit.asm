;
; BASIC-DOS Installable Device Driver Initialization
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	dev.inc
	include	devapi.inc
	include	dosapi.inc
	include	dosfunc.inc

DOS	segment word public 'CODE'

	EXTNEAR	<find_cfg>
	EXTWORD	<dos_seg>
	EXTLONG	<dev_head>

	ASSUME	CS:DOS, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_devices
;
; Load the driver in every "DEVICE=" setting, in CONFIG.SYS order.  Unlike
; the BASDEV drivers, these are single-header character device files (with
; no relocations), starting with a DDH whose REQUEST handler also handles
; DDC_INIT; DDH_NEXT_OFF must be FFFFh, or a JMP SHORT in a dual-mode .COM
; file.  DDPI_BUFPTR points to the ASCIIZ arguments after the filename, and
; if INIT fails, it must leave no hooks behind.  Each driver is added to the
; head of the driver list, and any failure is reported.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, DX, SI, DI
;
DEFPROC	load_devices
	push	bx
	push	cx
	push	bp
	push	ds
	push	es
	push	cs
	pop	ds
	ASSUME	DS:DOS
	jmp	short ld1

ld9:	pop	es
	pop	ds
	ASSUME	DS:NOTHING
	pop	bp
	pop	cx
	pop	bx
	ret

	ASSUME	DS:DOS
ld1:	mov	si,offset CFG_DEVICE
	call	find_cfg		; look for "DEVICE="
	jc	ld9			; no more
;
; Null-terminate the filename at DI, and set SI to its arguments, if any.
;
	mov	si,di
ld2:	lodsb
	cmp	al,' '			; space, tab, or null?
	ja	ld2			; no
	dec	si
	test	al,al
	jz	ld3a			; no arguments
	mov	byte ptr [si],0
ld3:	inc	si
	cmp	byte ptr [si],' '
	je	ld3
	cmp	byte ptr [si],CHR_TAB
	je	ld3
ld3a:
;
; Open the file, and allocate enough memory to read all of it.
;
	mov	dx,di
	mov	ax,DOS_HDL_OPENRO
	int	21h
	jnc	ld3b
	jmp	ld8
ld3b:	xchg	bx,ax			; BX = handle
	sub	cx,cx
	sub	dx,dx
	mov	ax,DOS_HDL_SEEKEND
	int	21h			; DX:AX = file size
	jc	ld7
	test	dx,dx
	jnz	ld6
	cmp	ax,size DDH
	jb	ld6
	mov	cx,ax			; CX = file size
	add	ax,15
	rcr	ax,1			; (including any carry)
	shr	ax,1
	shr	ax,1
	shr	ax,1
	push	bx
	xchg	bx,ax			; BX = paras
	mov	ah,DOS_MEM_ALLOC
	int	21h
	pop	bx
	jc	ld7
	mov	es,ax			; ES = driver segment
	push	cx
	sub	cx,cx
	sub	dx,dx
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	pop	cx
	jc	ld4
	push	ds
	push	es
	pop	ds
	ASSUME	DS:NOTHING
	mov	ah,DOS_HDL_READ
	int	21h			; read CX bytes into ES:0
	pop	ds
	ASSUME	DS:DOS
ld4:	pushf
	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	ax
	popf
	jc	ld5
	cmp	ax,cx			; did we read the entire file?
	jne	ld4a			; no
	cmp	es:[DDH_NEXT_OFF],-1	; a single header?
	je	ld4b			; yes
	cmp	byte ptr es:[DDH_NEXT_OFF],0EBh	; or a .COM's JMP SHORT?
	jne	ld4a			; no
ld4b:	test	es:[DDH_ATTR],DDATTR_CHAR
	jz	ld4a			; not a character device
	cmp	es:[DDH_REQUEST],cx	; request handler inside the file?
	jb	ld10			; yes
ld4a:	mov	ax,ERR_BADFORMAT
ld5:	push	ax
	mov	ah,DOS_MEM_FREE
	int	21h
	pop	ax
	jmp	short ld8
ld6:	mov	ax,ERR_BADFORMAT
ld7:	push	ax
	mov	ah,DOS_HDL_CLOSE
	int	21h
	pop	ax
ld8:	PRINTF	<"Warning: unable to load device %s (%d)",13,10>,di,ax
	jmp	ld1
;
; Initialize the driver, with a DDPI on the stack.  DDPI_END defaults to the
; end of the file, in case the driver doesn't set it.
;
ld10:	sub	sp,size DDPI
	mov	bp,sp			; SS:BP -> DDPI
	DBGINIT	STRUCT,[bp],DDP
	mov	[bp].DDP_LEN,size DDPI
	mov	[bp].DDP_CMD,DDC_INIT
	mov	[bp].DDP_STATUS,0
	mov	[bp].DDPI_END.OFF,cx
	mov	[bp].DDPI_BUFPTR.OFF,si
	mov	[bp].DDPI_BUFPTR.SEG,cs
	push	es			; create far pointer to DDH_REQUEST
	push	es:[DDH_REQUEST]	; at [bp-4]
	push	ss
	pop	es
	mov	bx,bp			; ES:BX -> DDPI
	push	bp
	push	di
	push	ds
	call	dword ptr [bp-4]
	pop	ds
	pop	di
	pop	bp
	pop	ax			; toss DDH_REQUEST offset
	pop	es			; ES = driver segment
	mov	ax,[bp].DDP_STATUS
	mov	bx,[bp].DDPI_END.OFF
	add	sp,size DDPI
	test	ax,DDSTAT_ERROR
	jz	ld10a
	mov	ax,ERR_GENFAIL
	jmp	ld5
;
; Release any memory beyond the driver's end, and add it to the driver list.
;
ld10a:	cmp	bx,cx
	jae	ld11
	add	bx,15
	mov	cl,4
	shr	bx,cl
	mov	ah,DOS_MEM_REALLOC
	int	21h
;
; Name the driver's memory block after the device, and have the block own
; itself (like a resident program), so that MEM lists it by name.
;
ld11:	push	ds
	push	es
	pop	ds
	ASSUME	DS:NOTHING		; DS = driver segment
	mov	ax,ds
	dec	ax
	mov	es,ax			; ES:0 -> MCB
	mov	es:[MCB_OWNER],ds
	mov	si,DDH_NAME
	mov	di,MCB_NAME
	mov	cx,size MCB_NAME
	rep	movsb
	push	ds
	pop	es			; ES = driver segment again
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,es
	xchg	ax,[DD_LIST].SEG
	mov	es:[DDH_NEXT_SEG],ax
	sub	ax,ax
	xchg	ax,[DD_LIST].OFF
	mov	es:[DDH_NEXT_OFF],ax
	pop	ds
	ASSUME	DS:DOS
	mov	ax,es
	mov	es,[dos_seg]
	ASSUME	ES:DOS
	mov	es:[dev_head].OFF,0	; keep dev_head in sync with DD_LIST
	mov	es:[dev_head].SEG,ax
	ASSUME	ES:NOTHING
	jmp	ld1
ENDPROC	load_devices

CFG_DEVICE	db	7,"DEVICE="

	DEFLBL	sysinit_end

DOS	ends

	end
