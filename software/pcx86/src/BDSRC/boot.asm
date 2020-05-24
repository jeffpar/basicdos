	include	bios.inc

CODE    segment

	org	BOOT_SECTOR_LO
;
; Having the stack at 30:100h is weird, but OK, whatever.
;
        ASSUME	CS:CODE, DS:BIOS_DATA, ES:BIOS_DATA, SS:NOTHING

	cld
	jmp	short move

mybpb:	BPB	<,512,1,1,2,64,320,MEDIA_160K,1,8,1,0,0,0,3,7>

move:	mov	di,offset DPT_ACTIVE	; ES:DI -> DPT_ACTIVE
	push	es
	push	di
	push	ds
	lds	si,ds:[INT_DPT*4]	; DS:SI -> original table (in ROM)
	ASSUME	DS:NOTHING
	mov	cx,size DPT
	rep	movsb
	pop	ds
	ASSUME	DS:BIOS_DATA
	mov	[DPT_ACTIVE].DP_SPECIFY1,0DFh	; change step rate to 6ms
	mov	[DPT_ACTIVE].DP_HEADSETTLE,0	; change head settle time to 0ms
	pop	ds:[INT_DPT*4]
	pop	ds:[INT_DPT*4+2]	; update INT_DPT vector

	mov	si,BOOT_SECTOR_HI	; move boot sector down
	mov	cx,512
	mov	di,offset BOOT_SECTOR
	rep	movsb
	mov	ax,offset boot
	jmp	ax

boot	proc	far
	mov	si,offset product
	call	print
	cmp	[mybpb].BPB_MEDIA,MEDIA_HARD
	je	load			; we're a hard disk, so just boot
	mov	ah,DISK_GETPARMS	; get hard drive parameters
	mov	dl,80h
	int	INT_DISK		;
	jc	load			; failed (could be an original PC)
	test	dl,dl			; any hard drives?
	jz	load			; no
	mov	si,offset prompt
	call	print
	mov	ax,2 * PCJS_MULTIPLIER	; AX = 2 seconds
	call	waitsec			; wait for key
	test	al,al			; was a key pressed in time?
	jnz	load			; yes
	mov	ax,0201h		; AH = 02h (READ), AL = 1 sector
	inc	cx			; CH = CYL 0, CL = SEC 1
	mov	dx,0080h		; DH = HEAD 0, DL = DRIVE 80h
	mov	bx,BOOT_SECTOR_HI	; ES:BX -> BOOT_SECTOR_HI
	int	13h			; read it
	jc	hderr
	jmp	bx			; jump to the hard disk boot sector
hderr:	mov	si,offset errmsg
	call	print			; fall into normal diskette boot
load:	mov	si,offset mybpb
	mov	dx,[si].BPB_LBAROOT	; DX = root dir LBA
rdir:	mov	ax,dx			; AX = LBA
	mov	cl,1
	mov	di,offset DIR_SECTOR
	call	read_sectors		; return dir sector (ES:DI)
	mov	bx,offset BIO_FILE	; DS:BX -> file name
	call	find_dirent		; return matching DIRENT (DS:BX)
	jb	err			; end of directory entries
	jz	read			; match!
	inc	dx			; DX = next dir LBA
	cmp	dx,[si].BPB_LBADATA	; exhausted root dir?
	jb	rdir			; not yet
err:	mov	si,offset errmsg
	call	print
	int	INT_REBOOT
read:	mov	di,BIOS_DATA_END
next:	mov	ax,[bx].DIR_CLN		; AX = cluster number
	call	read_cluster		; read cluster into ES:DI
	jc	err
	mul	[si].BPB_SECBYTES	; AX = number of sectors read
	add	di,ax			; adjust next read address
	sub	[bx].DIR_SIZE_L,ax	; reduce file size
	jbe	done			; size exhausted
	inc	[bx].DIR_CLN		; otherwise, read next cluster
	jmp	next			; (the clusters must be contiguous)
done:	mov	ax,BIOS_DATA_END SHR 4
	push	ax
	sub	ax,ax
	push	ax
	ret
boot	endp

;;;;;;;;
;
; Find DIRENT in sector at ES:DI using filename at DS:BX
;
; Modifies: CX, DI
;
; Returns: zero flag set if match (see BX), carry set if end of directory
;
find_dirent proc near
	push	si
	push	di
	xchg	si,bx		; DS:SI -> filename now
	mov	bx,[bx].BPB_SECBYTES
	add	bx,di
	dec	bx		; ES:BX -> end of sector data
f1:	mov	cx,11
;	cmp	byte ptr es:[di],0
;	stc
;	je	f9
	repe	cmpsb
	jz	f9
	add	di,cx
	add	di,size DIRENT - 11
	cmp	di,bx
	jb	f1
f9:	lea	bx,[di-11]	; DI is meaningless if ZF not set
	pop	di
	pop	si
	ret
find_dirent endp

;;;;;;;;
;
; Get CHS from LBA in AX, using BPB in DS:SI
;
; Modifies: AX, CX, DX
;
; Returns: CH = cylinder, CL = sector, DH = head, DL = drive
;
get_chs	proc	near
	xchg	cx,ax
	mov	al,byte ptr [si].BPB_TRACKSECS
	mul	byte ptr [si].BPB_TOTALHEADS
	xchg	cx,ax		; CX = sectors per cylinder
	cwd			; DX:AX is LBA
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
; Modifies: None
;
; Returns: Nothing
;
print	proc	near
	push	ax
	push	bx
	jmp	short pr2
pr1:	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
pr2:	lodsb
	test	al,al
	jnz	pr1
	pop	bx
	pop	ax
	ret
print	endp

;;;;;;;;
;
; Read cluster AX into memory at ES:DI
;
; Modifies: AX
;
; Returns: carry flag set on error (see AH), clear otherwise (AX sectors read)
;
read_cluster proc near
	push	cx
	push	dx
	sub	ax,2
	jb	rc9
	sub	cx,cx
	mov	cl,[si].BPB_CLUSSECS
	mul	cx
	add	ax,[si].BPB_LBADATA
	call	read_sectors
	jc	rc9
	mov	ax,cx
rc9:	pop	dx
	pop	cx
	ret
read_cluster endp

;;;;;;;;
;
; Read CL sectors into ES:DI using LBA in AX and BPB in DS:SI
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
; Returns: AL = key pressed (char code), 0 if none
;
waitsec	proc	near
	mov	dx,182
	mul	dx		; DX:AX = ticks to wait * 10
	mov	cx,10
	div	cx
	push	ax		; AX is corrected ticks to wait
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
	mov	si,offset crlf
	call	print
	ret
w2:	mov	ah,TIME_GETTICKS
	int	INT_TIME	; CX:DX is updated tick count
	pop	ax		; subtract target value on the stack
	sub	dx,ax
	pop	dx
	sbb	cx,dx		; as long as the target value is bigger
	jc	w1		; carry will be set
	mov	al,0		; no key was pressed in time
	ret
waitsec	endp

;
; Strings
;
product		db	"BASIC-DOS 0.01"
crlf		db	13,10,0
errmsg		db	"Unable to boot from disk",13,10,0
prompt		db	"Press any key to boot from diskette...",0
BIO_FILE	db	"IBMBIO  COM",0

CODE	ends

	end
