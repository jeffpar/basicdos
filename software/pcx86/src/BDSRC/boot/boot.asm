	include	bios.inc

BOOT	segment

;
; We "ORG" at BOOT_SECTOR_LO rather than BOOT_SECTOR_HI,
; because as soon as "move" finishes, we're running at BOOT_SECTOR_LO.
;
	org	BOOT_SECTOR_LO
        ASSUME	CS:BOOT, DS:NOTHING, ES:NOTHING, SS:NOTHING
;
; All we assume on entry is:
;
;	CS = 0
;	IP = 7C00h
;
; because although the original IBM PC had these additional inputs:
;
;	DS = ES = 0
;	SS:SP = 30h:100h
;
; that apparently didn't become a standard, because if we make any of those
; other assumptions, we have boot failures (eg, VMware machines).
;
	cld
	jmp	short move

mybpb:	BPB	<,512,1,1,2,64,320,MEDIA_160K,1,8,1,0,0,0,3,7>

move:	mov	di,offset DPT_ACTIVE	; ES:DI -> DPT_ACTIVE
	push	cs
	push	di
	push	cs
	pop	es
	ASSUME	ES:BIOS
	lds	si,es:[INT_DPT*4]	; DS:SI -> original table (in ROM)
	mov	cx,size DPT
	rep	movsb
	push	cs
	pop	ds
	ASSUME	DS:BIOS			; change step rate to 6ms
	mov	[DPT_ACTIVE].DP_SPECIFY1,0DFh
	mov	[DPT_ACTIVE].DP_HEADSETTLE,0
	pop	ds:[INT_DPT*4]		; and change head settle time to 0ms
	pop	ds:[INT_DPT*4+2]	; update INT_DPT vector
	mov	si,BOOT_SECTOR_HI	; now move boot sector down
	mov	cx,512
;	mov	di,offset BOOT_SECTOR	; BOOT_SECTOR now follows DPT_ACTIVE
	rep	movsb
	mov	ax,BIOS_END SHR 4
	push	ax
	sub	ax,ax
	push	ax
	mov	ax,offset main
	jmp	ax

main	proc	far			; now running at BOOT_SECTOR_LO
	mov	si,offset product
	call	print
	cmp	[mybpb].BPB_MEDIA,MEDIA_HARD
	je	load			; jump if we're a hard disk (just boot)
	mov	ah,DISK_GETPARMS	; get hard drive parameters
	mov	dl,80h
	int	INT_DISK		;
	jc	load			; jump if call failed (just boot)
	test	dl,dl			; any hard drives?
	jz	load			; jump if not (just boot)
	mov	si,offset prompt
	call	print
	mov	ax,2 * PCJS_MULTIPLIER	; AX = 2 seconds
	call	waitsec			; wait for key
	jcxz	hdboot			; jump if no key pressed

load:	mov	si,offset mybpb		; DS:SI -> BPB
	mov	bx,offset BIO_FILE	; DS:BX -> file name
	mov	dx,[si].BPB_LBAROOT	; DX = root dir LBA
	mov	bp,BIOS_END		; BP = target load address

dir:	mov	ax,dx			; AX = LBA
	mov	cl,1			; read 1 dir sector
	mov	di,offset DIR_SECTOR	;
	call	read_sectors		; return dir sector (ES:DI)
	jc	err

find:	call	find_dirent		; return matching DIRENT (DS:BX)
	jc	err			; jump if end of directory entries
	jz	read			; jump if match
	inc	dx			; DX = next dir LBA
	cmp	dx,[si].BPB_LBADATA	; exhausted root directory?
	jb	dir			; jump if not exhausted
err:	mov	si,offset errmsg
	call	print
	call	wait
	int	INT_REBOOT
;
; There's a hard disk and no response, so boot from hard disk instead.
;
hdboot:	mov	ax,0201h		; AH = 02h (READ), AL = 1 sector
	inc	cx			; CH = CYL 0, CL = SEC 1
	mov	dx,0080h		; DH = HEAD 0, DL = DRIVE 80h
	mov	bx,BOOT_SECTOR_HI	; ES:BX -> BOOT_SECTOR_HI
	int	13h			; read it
	jc	err
	jmp	bx			; jump to the hard disk boot sector
;
; We found the DIRENT (at BX) of the requested file, so load it.
;
read:	mov	di,bp			; DI = target load address
next:	mov	ax,[bx].DIR_CLN		; AX = cluster number
	push	dx			; save DX (trashed by read_cluster)
	call	read_cluster		; read cluster into ES:DI
	jc	err
	mul	[si].BPB_SECBYTES	; DX:AX = number of sectors read
	pop	dx			; restore DX
	add	di,ax			; adjust next read address
	sub	[bx].DIR_SIZE_L,ax	; reduce file size
	jbe	done			; size exhausted
	inc	[bx].DIR_CLN		; otherwise, read next cluster
	jmp	next			; (the clusters must be contiguous)
done:	mov	ax,offset find		; AX = entry point for loading next file
	ret
main	endp

;;;;;;;;
;
; Find DIRENT in sector at ES:DI using filename at DS:BX
;
; Modifies: AX, BX, CX
;
; Returns: zero flag set if match (see BX), carry set if end of directory
;
find_dirent proc near
	push	si
	push	di
	mov	ax,[si].BPB_SECBYTES
	add	ax,di		; AX -> end of sector data
f1:	cmp	byte ptr [di],0
	stc			; more future-proofing:
	je	f9		; 0 indicates end of allocated entries
	mov	si,bx
	mov	cx,11
	repe	cmpsb
	jz	f8
	add	di,cx
	add	di,size DIRENT - 11
	cmp	di,ax
	jb	f1
	jmp	short f9
f8:	lea	bx,[di-11]
f9:	pop	di
	pop	si
	ret
find_dirent endp

;;;;;;;;
;
; Get CHS from LBA in AX, using BPB at DS:SI
;
; Modifies: AX, CX, DX
;
; Returns: CH := cylinder, CL := sector, DH := head, DL := drive
;
get_chs	proc	near
;
; If our BPB had a pre-computed BPB_CYLSECS, we could avoid the CX calculation.
;
	xchg	cx,ax
	mov	al,byte ptr [si].BPB_TRACKSECS
	mul	byte ptr [si].BPB_DRIVEHEADS
	xchg	cx,ax		; CX = sectors per cylinder
	sub	dx,dx		; DX:AX is LBA
	div	cx		; AX = cylinder, DX = remaining sectors
	xchg	al,ah		; AH = cylinder, AL = cylinder bits 8-9
	ror	al,1		; future-proofing: saving cylinder bits 8-9
	ror	al,1
	xchg	cx,ax		; CH = cylinder
	xchg	ax,dx		; AX = remaining sectors from last divide
	div	byte ptr [si].BPB_TRACKSECS
	mov	dh,al		; DH = head (quotient of last divide)
	or	cl,ah		; CL = sector (remainder of last divide)
	inc	cx		; LBA are zero-based, sector IDs are 1-based
	mov	dl,[si].BPB_DRIVE
	ret
get_chs	endp

;;;;;;;;
;
; Print the null-terminated string at DS:SI
;
; Modifies: AX, BX, SI
;
; Returns: Nothing
;
printl	proc	near
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
print	label	near
	lodsb
	test	al,al
	jnz	printl
	ret
printl	endp

;;;;;;;;
;
; Read cluster AX into memory at ES:DI, using BPB at DS:SI
;
; Modifies: AX, CX, DX
;
; Returns: carry flag set on error (see AH), clear otherwise (AX sectors read)
;
read_cluster proc near
	sub	ax,2
	jb	rc9
	sub	cx,cx
	mov	cl,[si].BPB_CLUSSECS
	mul	cx
	add	ax,[si].BPB_LBADATA
	call	read_sectors
	jc	rc9
;
; The ROM claims that, on success, AL will (normally) contain the number of
; sectors actually read, but I'm not seeing that, so I'll just move CL to AL.
;
	xchg	ax,cx
rc9:	ret
read_cluster endp

;;;;;;;;
;
; Read CL sectors into ES:DI using LBA in AX and BPB at DS:SI
;
; Modifies: AX
;
; Returns: carry clear if successful, set if error (see AH for reason)
;
read_sectors proc near
	push	bx
	push	cx
	push	dx
	mov	bl,cl
	call	get_chs
	mov	al,bl
	mov	ah,DISK_READ
	mov	bx,di
	int	INT_DISK
	pop	dx
	pop	cx
	pop	bx
	ret
read_sectors endp

;;;;;;;;
;
; Wait the number of seconds in AX, or until a key is pressed.
;
; Modifies: AX, CX, DX
;
; Returns: CX := char code (lo), scan code (hi); 0 if no key pressed
;
waitsec	proc	near
	mov	dx,182		; 18.2 ticks per second
	mul	dx		; DX:AX = ticks to wait * 10
	mov	cx,10
	div	cx
	push	ax		; AX is ticks to wait
	mov	ah,TIME_GETTICKS
	int	INT_TIME	; CX:DX is initial tick count
	pop	ax
	add	ax,dx		; add AX
	mov	dx,cx
	adc	dx,0		; DX:AX is target tick count
w1:	push	dx
	push	ax
	mov	ah,KBD_CHECK
	int	INT_KBD
	jz	w2
	pop	ax
	pop	dx
wait	label	near
	mov	ah,KBD_READ
	int	INT_KBD
	xchg	cx,ax		; CL = char code, CH = scan code
	jmp	short w9
w2:	mov	ah,TIME_GETTICKS
	int	INT_TIME	; CX:DX is updated tick count
	pop	ax		; subtract target value on the stack
	sub	dx,ax
	pop	dx
	sbb	cx,dx		; as long as the target value is bigger
	jc	w1		; carry will be set
	sub	cx,cx		; no key was pressed in time
w9:	mov	si,offset crlf
	call	print
	ret
waitsec	endp

;
; Strings
;
product		db	"BASIC-DOS 0.01"
crlf		db	13,10,0
errmsg		db	"Unable to boot from disk",13,10,0
prompt		db	"Press any key to boot from diskette",0
BIO_FILE	db	"IBMBIO  COM",0

BOOT	ends

	end
