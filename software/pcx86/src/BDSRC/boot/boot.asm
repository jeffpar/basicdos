	include	bios.inc

READFAT	equ 1		; 0 to assume contiguous files, 1 to read the FAT

BOOT	segment word public 'CODE'

;
; We "ORG" at BOOT_SECTOR_LO rather than BOOT_SECTOR_HI,
; because as soon as "move" finishes, we're at BOOT_SECTOR_LO.
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
; other assumptions, we have boot failures.
;
start:	cld
	jmp	short move

mybpb:	BPB	<,512,1,1,2,64,320,MEDIA_160K,1,8,1,0,0,0,8,3,7>

move:	push	cs
	pop	es
	ASSUME	ES:BIOS
	lds	si,es:[INT_DPT*4]	; DS:SI -> original table (in ROM)
	mov	cx,size DPT
	mov	di,offset DPT_ACTIVE	; ES:DI -> DPT_ACTIVE
	push	di
	rep	movsb
	pop	si
	push	cs
	pop	ds
	ASSUME	DS:BOOT			; change step rate to 6ms
	mov	[si].DP_SPECIFY1,0DFh
	mov	[si].DP_HEADSETTLE,cl
	mov	ds:[INT_DPT*4],si	; and change head settle time to 0ms
	mov	ds:[INT_DPT*4+2],ds	; update INT_DPT vector
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

;;;;;;;;
;
; If there's a hard disk, display a prompt.
;
; If there's no hard disk (or we were told to bypass it), then look for
; all the the required files in the root directory (starting with DEV_FILE),
; load the first sector of the first file, and continue booting from there.
;
main	proc	far			; now at BOOT_SECTOR_LO
	mov	si,offset product
	call	print
	cmp	[mybpb].BPB_MEDIA,MEDIA_HARD
	je	find			; jump if we're a hard disk
	mov	ah,DISK_GETPARMS	; get hard drive parameters
	mov	dl,80h
	int	INT_DISK		;
	jc	find			; jump if call failed
	test	dl,dl			; any hard disks?
	jz	find			; jump if no hard disks
	mov	si,offset prompt
	call	print
	call	twait			; timed-wait for key
	jcxz	hard			; jump if no key pressed
;
; Find all the files in our file list, starting with DEV_FILE.
;
find:	mov	si,offset mybpb		; SI -> BPB
	mov	dx,[si].BPB_LBAROOT	; DX = root dir LBA
m1:	mov	ax,dx			; AX = LBA
	mov	di,offset DIR_SECTOR	; DI = dir sector
	call	read_sector		; read it
	jc	err			; jump if error
m2:	mov	cx,3			; CX = # files left to find
	mov	bx,offset DEV_FILE	; first file to find
m3:	cmp	byte ptr [bx],ch	; more files to find?
	jl	m7			; no, see if we're done
	jg	m6			; no, this file hasn't been found yet
m4:	dec	cx			; reduce the # files left
m5:	add	bx,11			; partly, skip to next filename
	jmp	m3			; and check again
m6:	call	find_dirent		;
	jc	err			; jump if end of directory entries
	jz	m4			; we found a file
	jmp	m5			; oh well, try the next file
m7:	jcxz	read			; all files found, go read
	inc	dx			; DX = next dir LBA
	cmp	dx,[si].BPB_LBADATA	; exhausted root directory?
	jb	m1			; jump if not exhausted
err:	mov	si,offset errmsg
	call	print
	jmp	$			; "halt"
;
; There's a hard disk and no response, so boot from hard disk instead.
;
hard:	mov	ax,0201h		; AH = 02h (READ), AL = 1 sector
	inc	cx			; CH = CYL 0, CL = SEC 1
	mov	dx,0080h		; DH = HEAD 0, DL = DRIVE 80h
	mov	bx,BOOT_SECTOR_HI	; ES:BX -> BOOT_SECTOR_HI
	int	INT_DISK		; read it
	jc	err
	jmp	bx			; jump to the hard disk boot sector
;
; We found all the required files, so read the first sector of the first file.
;
read:	mov	bx,offset DEV_FILE
	mov	ax,[bx+2]		; AX = CLN
	call	get_lba
	call	read_sector		; DI -> DIR_SECTOR
	jc	err
	jmp	part2			; jump to the next part
main	endp

;;;;;;;;
;
; Find DIRENT in sector at DI using filename at BX
;
; Modifies: AX
;
; Returns: zero flag set if match (in DI), carry set if end of directory
;
find_dirent proc near
	push	cx			; CH is zero on entry
	push	si
	push	di
	mov	ax,[si].BPB_SECBYTES
	add	ax,di			; AX -> end of sector data
	dec	ax			; ensure DI will never equal AX
fd1:	cmp	byte ptr [di],ch
	stc				; more future-proofing:
	je	fd9			; 0 indicates end of allocated entries
	mov	si,bx
	mov	cl,11
	repe	cmpsb
	jz	fd8
	add	di,cx
	add	di,size DIRENT - 11
	cmp	di,ax
	jb	fd1
	jmp	short fd9
fd8:	mov	[bx],cx
	mov	ax,[di-11].DIR_CLN	; overwrite the filename
	mov	[bx+2],ax		; with cluster number and size,
	mov	ax,[di-11].DIR_SIZE_L	; since we're done with the filename
	mov	[bx+4],ax
	mov	ax,[di-11].DIR_SIZE_H
	mov	[bx+6],ax
fd9:	pop	di
	pop	si
	pop	cx
	ret
find_dirent endp

;;;;;;;;
;
; Get CHS from LBA in AX, using BPB at SI
;
; Modifies: AX, CX, DX
;
; Returns: CH = cylinder #, CL = sector ID, DH = head #, DL = drive #
;
get_chs	proc	near
	sub	dx,dx		; DX:AX is LBA
	div	[si].BPB_CYLSECS; AX = cylinder, DX = remaining sectors
	xchg	al,ah		; AH = cylinder, AL = cylinder bits 8-9
	ror	al,1		; future-proofing: saving cylinder bits 8-9
	ror	al,1
	xchg	cx,ax		; CH = cylinder #
	xchg	ax,dx		; AX = remaining sectors from last divide
	div	byte ptr [si].BPB_TRACKSECS
	mov	dh,al		; DH = head # (quotient of last divide)
	or	cl,ah		; CL = sector # (remainder of last divide)
	inc	cx		; LBA are zero-based, sector IDs are 1-based
	mov	dl,[si].BPB_DRIVE
	ret
get_chs	endp

;;;;;;;;
;
; Get LBA from CLN in AX, using BPB at SI
;
; Modifies: AX, CX, DX
;
; Returns: AX = LBA, CX = sectors per cluster (or carry set if error)
;
get_lba proc near
	sub	ax,2
	jb	err
	sub	cx,cx
	mov	cl,[si].BPB_CLUSSECS
	mul	cx
	add	ax,[si].BPB_LBADATA
	ret
get_lba endp

;;;;;;;;
;
; Read 1 sector into DI using LBA in AX and BPB at SI
;
; Modifies: AX, BX
;
; Returns: carry clear if successful, set if error (see AH for reason)
;
read_sector proc near
	push	cx
	push	dx
	call	get_chs
	mov	al,1		; AL = 1 sector
	mov	ah,DISK_READ
	mov	bx,di		; ES:BX = address
	int	INT_DISK	; AX and carry are whatever the ROM returns
	pop	dx
	pop	cx
	ret
read_sector endp

;;;;;;;;
;
; Wait some number of ticks, or until a key is pressed.
;
; Modifies: AX, CX, DX
;
; Returns: CX = char code (lo), scan code (hi); 0 if no key pressed
;
twait	proc	near
	mov	ah,TIME_GETTICKS
	int	INT_TIME	; CX:DX is initial tick count
	add	ax,91 * PCJS_MULTIPLIER
	mov	dx,cx
	adc	dx,0		; DX:AX is target tick count
ws1:	push	dx
	push	ax
	mov	ah,KBD_CHECK
	int	INT_KBD
	jz	ws2
	pop	ax
	pop	dx
wait	label	near
	mov	ah,KBD_READ
	int	INT_KBD
	xchg	cx,ax		; CL = char code, CH = scan code
	jmp	short ws9
ws2:	mov	ah,TIME_GETTICKS
	int	INT_TIME	; CX:DX is updated tick count
	pop	ax		; subtract target value on the stack
	sub	dx,ax
	pop	dx
	sbb	cx,dx		; as long as the target value is bigger
	jc	ws1		; carry will be set
	sub	cx,cx		; no key was pressed in time
ws9:	mov	si,offset crlf
	call	print
	ret
twait	endp

;;;;;;;;
;
; Print the null-terminated string at SI
;
; Modifies: AX, BX, SI
;
; Returns: Nothing
;
printp	proc	near
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
print	label	near
	lodsb
	test	al,al
	jnz	printp
	ret
printp	endp

;
; Strings
;
product		db	"BASIC-DOS 0.01"
crlf		db	13,10,0
prompt		db	"Press any key to start...",0
PART1_COPY	equ	$
errmsg		db	"Unable to boot, halted",0
DEV_FILE	db	"IBMBIO  COM"
DOS_FILE	db	"IBMDOS  COM"
CFG_FILE	db	"CONFIG  SYS"
		db	-1
PART1_END	equ	$

	org 	BOOT_SECTOR_LO + 510
	dw	0AA55h
;
; The rest of the boot code will be loaded into DIR_SECTOR.
;
	org 	DIR_SECTOR_OFF

;;;;;;;;
;
; Part 2 of the boot process:
;
;    1) Copy critical data from PART1 to PART1, before FAT reads (if any)
;	overwrite it.
;
;    2) Move the non-boot code from this sector (ie, the first chunk of
;	IBMBIO.COM) into its final resting place (ie, BIOS_END) and save
;	that ending address as the next load address.
;
;    3) Load the rest of IBMBIO.COM; for now, we can just assume contiguity
;	and not bother reading the FAT.  If someday we want to read the FAT,
;	we're ready for that: just read FAT sectors into FAT_SECTOR; but
;	be aware that that will eliminate the first half of our boot code
;	(ie, most of the code above), so any of that code you still want to
;	use will have to be duplicated below.
;
;    4) Locate IBMBIO's "init" code, which resides just beyond all the
;	device drivers, and execute it.  It must return the next available
;	load address.
;
;    5) When it returns, load IBMDOS.COM at the next load address, and then
;	call it.  At that point, we never return to this code.
;
part2	proc	near
	mov	ax,[si].BPB_SECBYTES
	push	si
	mov	si,offset PART1_COPY
	mov	di,offset PART2_COPY
	mov	cx,offset PART1_END - offset PART1_COPY
	rep	movsb
	mov	si,offset PART2_END
	mov	di,BIOS_END
	mov	cx,DIR_SECTOR_OFF
	add	cx,ax
	sub	cx,si
	rep	movsb			; move first bit of IBMBIO
	pop	si
	mov	bx,offset DEV_FILE + (offset PART2_COPY - offset PART1_COPY)
	sub	di,ax			; adjust load addr for read_more
	call	read_more		; read the rest of IBMBIO (see BX)
	jc	err2

init:
	int 3

part2	endp

	IF	READFAT

FATLBA	dw	0			; remembers the last FAT LBA we read

;;;;;;;;
;
; Get CHS from LBA in AX, using BPB at SI
;
; Modifies: AX, CX, DX
;
; Returns: CH = cylinder #, CL = sector ID, DH = head #, DL = drive #
;
get_chs2 proc	near
	sub	dx,dx		; DX:AX is LBA
	div	[si].BPB_CYLSECS; AX = cylinder, DX = remaining sectors
	xchg	al,ah		; AH = cylinder, AL = cylinder bits 8-9
	ror	al,1		; future-proofing: saving cylinder bits 8-9
	ror	al,1
	xchg	cx,ax		; CH = cylinder #
	xchg	ax,dx		; AX = remaining sectors from last divide
	div	byte ptr [si].BPB_TRACKSECS
	mov	dh,al		; DH = head # (quotient of last divide)
	or	cl,ah		; CL = sector # (remainder of last divide)
	inc	cx		; LBA are zero-based, sector IDs are 1-based
	mov	dl,[si].BPB_DRIVE
	ret
get_chs2 endp

;;;;;;;;
;
; Get LBA from CLN in AX, using BPB at SI
;
; Modifies: AX, CX, DX
;
; Returns: AX = LBA, CX = sectors per cluster (or carry set if error)
;
get_lba2 proc near
	sub	ax,2
	jb	err2
	sub	cx,cx
	mov	cl,[si].BPB_CLUSSECS
	mul	cx
	add	ax,[si].BPB_LBADATA
	ret
get_lba2 endp

err2:	mov	si,offset errmsg + (offset PART2_COPY - offset PART1_COPY)

;;;;;;;;
;
; Print the null-terminated string at SI
;
; Modifies: AX, BX, SI
;
; Returns: Nothing
;
print2:	lodsb
	test	al,al
	jz	halt2
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	jmp	print2
halt2:	jmp	$			; "halt"

;;;;;;;;
;
; From the CLN in AX, return the next CLN in DX, using BPB at SI.
;
; We observe that the FAT sector # containing a 12-bit CLN is:
;
;	(CLN * 12) / 4096
;
; assuming a 512-byte sector with 4096 or 2^12 bits.  The expression
; can be simplified to (CLN * 12) SHR 12, or (CLN * 3) SHR 10, or simply
; (CLN + CLN + CLN) SHR 10.
;
; Next, we need the nibble offset within the sector, which is:
;
;	((CLN * 12) % 4096) / 4
;
; TODO: If we're serious about being sector-size-agnostic, our BPB should
; contain a (precalculated) LOG2 of BPB_SECBYTES, to avoid hard-coded shifts.
;
; Modifies: AX, CX, DX, BP
;
; Returns: DX (next CLN)
;
read_fat proc near
	push	bx
	push	di
	mov	bx,ax
	add	ax,ax
	add	ax,bx
	mov	bx,ax
	mov	cl,10
	shr	ax,cl			; AX = FAT sector ((CLN * 3) SHR 10)
	add	ax,[si].BPB_RESSECS	; AX = FAT LBA
	and	bx,03FFh		; nibble offset (assuming 1024 nibbles)
	mov	di,offset FAT_SECTOR
	cmp	ax,[FATLBA]
	je	rf1
	mov	[FATLBA],ax
	mov	cl,1
	call	read_sectors
	jc	err2
rf1:	mov	bp,bx			; save nibble offset in BP
	shr	bx,1			; BX -> byte, carry set if odd nibble
	mov	dl,[di+bx]
	inc	bx
	cmp	bp,03FFh		; at the sector boundary?
	jb	rf2			; no
	inc	[FATLBA]
	mov	ax,[FATLBA]
	call	read_sectors		; read next FAT LBA
	jc	err2
	sub	bx,bx
rf2:	mov	dh,[di+bx]
	shr	bp,1			; was that an odd nibble again?
	jc	rf8			; yes
	and	dx,0FFFh		; no, so make sure top 4 bits clear
	jmp	short rf9
rf8:	mov	cl,4			;
	shr	dx,cl			; otherwise, shift all 12 bits down
rf9:	pop	di
	pop	bx
	ret
read_fat endp

	ELSE

err2:	jmp	err
get_chs2 equ	get_chs
get_lba2 equ	get_lba
print2	 equ	print

	ENDIF

;;;;;;;;
;
; Read file using directory info at BX and BPB at SI.
;
; Modifies: AX, CX, DX
;
; Returns: carry set on error (see AH), clear otherwise (AX sectors read)
;
read_more proc near
	mov	dx,1			; DX = sectors already read
rm1:	cmp	word ptr [bx+4],0
	jne	rm2
	cmp	word ptr [bx+6],0
	je	rc9			; file size is zero, carry clear
rm2:	mov	ax,[bx+2]		; AX = CLN
	cmp	ax,2			; too low?
	jc	rc9			; yes
	cmp	ax,CLN_END		; too high?
	cmc
	jc	rc9			; yes
	call	read_cluster		; read cluster into DI
	jc	rc9			; error
	mul	[si].BPB_SECBYTES	; DX:AX = number of sectors read
	add	di,ax			; adjust next read address
	sub	[bx+4],ax		; reduce file size
	sbb	[bx+6],dx		; (DX is zero)
	jnc	rm3			; jump if file size still positive
	add	di,[bx+4]		; rewind next load address by
	clc				; the amount of file size underflow
	jmp	rc9			; and return success
rm3:
	IF	READFAT
	mov	ax,[bx+2]		; AX = CLN
	call	read_fat		; DX = next CLN
	mov	[bx+2],dx		; update CLN
	ELSE
	inc	word ptr [bx+2]		; simply increment CLN
	ENDIF

read_file label near
	sub	dx,dx			; tell all subsequent read_cluster
	jmp	rm1			; calls to read all sectors
read_more endp

;;;;;;;;
;
; Read cluster AX into memory at DI, using BPB at SI.
;
; Modifies: AX, CX
;
; Returns: carry set on error (see AH), clear otherwise (AX sectors read)
;
read_cluster proc near
	push	dx		; DX = sectors this cluster already read
	call	get_lba2	; AX = LBA, CX = sectors per cluster
	pop	dx
	add	ax,dx		; adjust LBA by sectors already read
	sub	cx,dx		; sectors remaining?
	jbe	rc8		; no
	call	read_sectors
	jc	rc9
rc8:	add	cx,dx		; adjust total sectors read so far
;
; The ROM claims that, on success, AL will (normally) contain the number of
; sectors actually read, but I'm not seeing that, so I'll just move CL to AL.
;
	xchg	ax,cx
rc9:	ret
read_cluster endp

;;;;;;;;
;
; Read CL sectors into DI using LBA in AX and BPB at SI
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
	call	get_chs2
	mov	al,bl		; AL = # sectors (from original CL)
	mov	ah,DISK_READ
	mov	bx,di		; ES:BX = address
	int	INT_DISK	; AX and carry are whatever the ROM returns
	pop	dx
	pop	cx
	pop	bx
	ret
read_sectors endp

;
; Data copied from PART1
;
PART2_COPY	db	(23 + 34) dup (?)
	even
PART2_END	equ	$

;	ASSERT	<offset PART1_END - offset PART1_COPY>,EQ,<offset PART2_END - offset PART2_COPY>

BOOT	ends

	end
