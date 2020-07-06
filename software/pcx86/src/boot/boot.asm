;
; BASIC-DOS Boot Code
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

BOOT	segment word public 'CODE'

;
; We "ORG" at BOOT_SECTOR_LO rather than BOOT_SECTOR, because after part1
; finishes, we're runing at BOOT_SECTOR_LO.
;
	org	BOOT_SECTOR_LO
        ASSUME	CS:BOOT, DS:NOTHING, ES:NOTHING, SS:NOTHING
;
; All we assume on entry is:
;
;	CS = 0
;	IP = 7C00h
;
; Although the original IBM PC had these additional inputs:
;
;	DS = ES = 0
;	SS:SP = 30h:100h
;
; that apparently didn't become a standard, because if we rely on any of those
; other assumptions, we can run into boot failures.
;
start:	cld
	jmp	short part1

PART1_COPY	equ	$		; start of PART1 data

mybpb:		BPB	<,512,1,1,2,64,320,MEDIA_160K,1,8,1,0,0,0,8,3,7>

DEV_FILE	db	"IBMBIO  COM"
DOS_FILE	db	"IBMDOS  COM"
CFG_FILE	db	"CONFIG  SYS",-1

PART1_END	equ	$		; end of PART1 data

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; part1
;
; Move the DPT from ROM to RAM so we can tweak a few values, and then move
; ourselves to low memory where we'll be out of the way, should we ever need
; to load more than 32K.
;
part1:	push	cs
	pop	es
	ASSUME	ES:BIOS
	lds	si,dword ptr es:[INT_DPT*4]
	mov	cx,size DPT		; DS:SI -> original table (in ROM)
	mov	di,offset DPT_ACTIVE	; ES:DI -> DPT_ACTIVE
	push	di
	rep	movsb
	pop	si
	push	cs
	pop	ds
	ASSUME	DS:BIOS
	mov	[si].DP_SPECIFY1,0DFh	; change step rate to 6ms
	mov	[si].DP_HEADSETTLE,cl	; and change head settle time to 0ms
	mov	ds:[INT_DPT*4],si
	mov	ds:[INT_DPT*4+2],ds	; update INT_DPT vector
	mov	si,BOOT_SECTOR		; now move boot sector down
	mov	ch,1			; mov cx,512 (aka [mybpb].BPB_SECBYTES)
	mov	di,BOOT_SECTOR_LO
	rep	movsw
	mov	ax,offset main
	jmp	ax

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; main
;
; If there's a hard disk, display a prompt.
;
; If there's no hard disk (or we were told to bypass it), then look for
; all the the required files in the root directory (starting with DEV_FILE),
; load the first sector of the first file, and continue booting from there.
;
DEFPROC	main,far			; now at BOOT_SECTOR_LO
	mov	si,offset product
	call	print
	cmp	ds:[mybpb].BPB_MEDIA,MEDIA_HARD
	je	find			; jump if we're a hard disk
	mov	ah,HDC_GETPARMS		; get hard drive parameters
	mov	dl,80h
	int	INT_FDC			;
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
	jz	m4			; we found a file
	jmp	m5			; no, try the next file
m7:	jcxz	read			; all files found, go read
	inc	dx			; DX = next dir LBA
	cmp	dx,[si].BPB_LBADATA	; exhausted root directory?
	jb	m1			; jump if not exhausted
	dec	cx			; CX == 1?
	jz	read			; yes, it's OK if CFG_FILE is missing
err:	mov	si,offset errmsg1
	call	print
	jmp	$			; "halt"
;
; There's a hard disk and no response, so boot from hard disk instead.
;
hard:	mov	al,[CRT_MODE]
	cbw
	int	10h
	mov	ax,0201h		; AH = 02h (READ), AL = 1 sector
	inc	cx			; CH = CYL 0, CL = SEC 1
	mov	dx,0080h		; DH = HEAD 0, DL = DRIVE 80h
	mov	bx,BOOT_SECTOR		; ES:BX -> BOOT_SECTOR
	int	INT_FDC			; read it
	jc	err
	jmp	bx			; jump to the hard disk boot sector
;
; We found all the required files, so read the first sector of the first file.
;
read:	mov	bx,offset DEV_FILE
	mov	ax,[bx+2]		; AX = CLN
	call	get_lba
	call	read_sector		; DI -> DIR_SECTOR
err1:	jc	err
	jmp	near ptr part2 + 2	; jump to the next part
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_dirent
;
; Find DIRENT in sector at DI using filename at BX
;
; Returns: zero flag set if match (in DI), carry set if end of directory
;
; Modifies: AX
;
DEFPROC	find_dirent
	push	cx			; CH is zero on entry
	push	si
	push	di
	mov	ax,[si].BPB_SECBYTES
	add	ax,di			; AX -> end of sector data
	dec	ax			; ensure DI will never equal AX
fd1:	cmp	byte ptr [di],ch
	je	err			; 0 indicates end of allocated entries
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
	mov	ax,[di-11].DIR_SIZE.OFF	; since we're done with the filename
	mov	[bx+4],ax
	mov	ax,[di-11].DIR_SIZE.SEG
	mov	[bx+6],ax
fd9:	pop	di
	pop	si
	pop	cx
	ret
ENDPROC	find_dirent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_chs
;
; Get CHS from LBA in AX, using BPB at SI
;
; Returns: CH = cylinder #, CL = sector ID, DH = head #, DL = drive #
;
; Modifies: AX, CX, DX
;
DEFPROC	get_chs
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
ENDPROC	get_chs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_lba
;
; Get LBA from CLN in AX, using BPB at SI
;
; Returns: AX = LBA, CX = sectors per cluster (or carry set if error)
;
; Modifies: AX, CX, DX
;
DEFPROC	get_lba
	sub	ax,2
	jb	err1
	sub	cx,cx
	mov	cl,[si].BPB_CLUSSECS
	mul	cx
	add	ax,[si].BPB_LBADATA
	ret
ENDPROC	get_lba

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_sector
;
; Read 1 sector into DI using LBA in AX and BPB at SI
;
; Returns: carry clear if successful, set if error (see AH for reason)
;
; Modifies: AX, BX
;
DEFPROC	read_sector
	push	cx
	push	dx
	call	get_chs
	mov	al,1		; AL = 1 sector
	mov	ah,FDC_READ
	mov	bx,di		; ES:BX = address
	int	INT_FDC		; AX and carry are whatever the ROM returns
	pop	dx
	pop	cx
	ret
ENDPROC	read_sector

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; twait (timed wait)
;
; Wait some number of ticks, or until a key is pressed.
;
; Returns: CX = char code (lo), scan code (hi); 0 if no key pressed
;
; Modifies: AX, CX, DX
;
DEFPROC	twait
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
ENDPROC	twait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; print (prints the null-terminated string at SI)
;
; Returns: Nothing
;
; Modifies: AX, BX, SI
;
DEFPROC	printp
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
print	label	near
	lodsb
	test	al,al
	jnz	printp
	ret
ENDPROC	printp

;
; Strings
;
product		db	" BASIC-DOS "
		VERSION_STR
crlf		db	13,10,' ',0
prompt		db	"Press any key to start...",0
errmsg1		db	" Missing system files, halted",0

	org 	BOOT_SECTOR_LO + 510
	dw	0AA55h
;
; The rest of the boot code will be loaded into DIR_SECTOR.
;
	org 	DIR_SECTOR_OFF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Part 2 of the boot process:
;
;    1) Copy critical data from PART1 to PART2, before FAT reads (if any)
;	overwrite it.
;
;    2) Move the non-boot code from this sector (ie, the first chunk of
;	DEV_FILE) into its final resting place (ie, BIOS_END) and save that
;	ending address as the next load address.
;
;    3) Load the rest of DEV_FILE; the file need not be first, nor
;	contiguous, since we read the FAT to process the cluster chain;
;	the downside is that any FAT sectors read will overwrite the first
;	half of the boot code, so any code/data that must be copied between
;	the halves should be copied above (see step 1).
;
;    4) Locate DEV_FILE's "init" code, which resides just beyond all the
;	device drivers, and call it.  It must return the next available
;	load address.
;
; NOTE: We currently don't include any code in the PART1-to-PART2 copy step,
; but we could.  We could move some of the duplicated functions like get_chs,
; get_lba, and print, for example.  However, that would make calling the code
; a bit more complicated, and fragile, so as long we don't need the extra
; space in the "part2" sector, there's not much point.
;
DEFPROC	part2,far
	int	20h			; fake DOS terminate call
	mov	ax,[si].BPB_SECBYTES
	mov	si,offset PART1_COPY	; copy PART1 data to PART2
	mov	di,offset PART2_COPY
	mov	cx,offset PART1_END - offset PART1_COPY
	rep	movsb

	mov	di,offset FAT_BUFHDR
	mov	cx,offset DIR_SECTOR	; now we can zero the area
	sub	cx,di			; from FAT_BUFHDR to DIR_SECTOR
	rep	stosb			; (AL should be zero)

	mov	si,offset PART2_END
	mov	di,BIOS_END
	mov	cx,offset DIR_SECTOR
	add	cx,ax
	sub	cx,si
	rep	movsb			; move first bit of DEV_FILE

	mov	bx,offset DEV_FILE + (offset PART2_COPY - offset PART1_COPY)
	sub	di,ax			; adjust load addr for read_data
	mov	si,offset PART2_COPY
	call	read_data		; read the rest of DEV_FILE (see BX)
	jc	i2			; load_error
;
; To find the entry point of DEV_FILE's init code, we must walk the
; driver headers.  And since they haven't been chained together yet (that's
; the DEV_FILE init code's job), we do this by simply "hopping" over all
; the headers.
;
	mov	di,BIOS_END		; BIOS's end is DEV_FILE's beginning
	mov	cx,100			; put a limit on this loop
i1:	mov	ax,[di]			; AX = current driver's total size
	cmp	ax,-1			; have we reached end of drivers?
	je	i3			; yes
	add	di,ax
	loop	i1
i2:	jmp	load_error
;
; Prepare to "call" the DEV_FILE entry point, with DI -> end of drivers.
;
i3:	mov	[DD_LIST].OFF,ax	; initialize driver list head (to -1)
	mov	ax,di
	test	ax,0Fh			; paragraph boundary?
	jnz	i2			; no
	push	cs
	mov	cx,offset part3
	push	cx			; far return address -> part3
	mov	cx,4
	shr	ax,cl
	push	ax
	push	cx			; far "call" address -> CS:0004h
	ret				; "call"
ENDPROC	part2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Part 3 of the boot process:
;
;    1) When DEV_FILE returns, load DOS_FILE at the next load address,
;	and then jump to it.  At that point, we never return to this code.
;
DEFPROC	part3,far
	mov	si,offset PART2_COPY
;
; Convert ES:DI to SEG:0, and then load ES with the new segment
;
	add	di,15
	mov	cl,4
	shr	di,cl
	mov	es,di
	ASSUME	ES:NOTHING
	sub	di,di		; ES:DI now converted
	mov	bx,offset DOS_FILE + (offset PART2_COPY - offset PART1_COPY)
	call	read_file	; load DOS_FILE
	push	di
	mov	bx,offset CFG_FILE + (offset PART2_COPY - offset PART1_COPY)
	sub	dx,dx		; default CFG_FILE size is zero
	cmp	[bx],dx		; did we find CFG_FILE?
	jne	i9		; no
	push	[bx+4]		; push CFG_FILE size (assume < 64K)
	call	read_file	; load CFG_FILE above DOS_FILE
	pop	dx		; DX = CFG_FILE size
i9:	pop	bx		; BX = CFG_FILE data address
	push	es
	mov	ax,2		; skip the fake INT 20h in DOS_FILE
	push	ax		; far "jmp" address -> CS:0002h
	mov	ax,offset PART2_COPY
	ret			; AX = offset of BPB
ENDPROC	part3

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_chs2
;
; Get CHS from LBA in AX, using BPB at SI
;
; Returns: CH = cylinder #, CL = sector ID, DH = head #, DL = drive #
;
; Modifies: AX, CX, DX
;
DEFPROC	get_chs2
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
ENDPROC	get_chs2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_lba2
;
; Get LBA from CLN in AX, using BPB at SI
;
; Returns: AX = LBA, CX = sectors per cluster (or carry set if error)
;
; Modifies: AX, CX, DX
;
DEFPROC	get_lba2
	sub	ax,2
	jb	load_error
	sub	cx,cx
	mov	cl,[si].BPB_CLUSSECS
	mul	cx
	add	ax,[si].BPB_LBADATA
	ret
ENDPROC	get_lba2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; load_error
;
; Print load error message and "halt"
;
; Returns: Nothing
;
; Modifies: AX, BX, SI
;
DEFPROC	load_error
	mov	si,offset errmsg2
	lodsb
	test	al,al
	jz	$			; "halt"
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	jmp	load_error
ENDPROC	load_error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_fat
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
; Returns: DX (next CLN)
;
; Modifies: AX, CX, DX, BP
;
DEFPROC	read_fat
	push	bx
	push	di
	mov	bx,ax
	add	ax,ax
	add	ax,bx
	mov	bx,ax
	mov	cl,10
	shr	ax,cl		; AX = FAT sector ((CLN * 3) SHR 10)
	add	ax,[si].BPB_RESSECS
	and	bx,3FFh		; nibble offset (assuming 1024 nibbles)
	mov	di,offset FAT_SECTOR
	cmp	ax,[FAT_BUFHDR].BUF_LBA
	je	rf1
	mov	[FAT_BUFHDR].BUF_LBA,ax
	mov	cl,1
	call	read_sectors
	jc	load_error
rf1:	mov	bp,bx		; save nibble offset in BP
	shr	bx,1		; BX -> byte, carry set if odd nibble
	mov	dl,[di+bx]
	inc	bx
	cmp	bp,03FFh	; at the sector boundary?
	jb	rf2		; no
	inc	[FAT_BUFHDR].BUF_LBA
	mov	ax,[FAT_BUFHDR].BUF_LBA
	call	read_sectors	; read next FAT LBA
	jc	load_error
	sub	bx,bx
rf2:	mov	dh,[di+bx]
	shr	bp,1		; was that an odd nibble again?
	jc	rf8		; yes
	and	dx,0FFFh	; no, so make sure top 4 bits clear
	jmp	short rf9
rf8:	mov	cl,4
	shr	dx,cl		; otherwise, shift all 12 bits down
rf9:	pop	di
	pop	bx
	ret
ENDPROC	read_fat

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_data
;
; Read file data into ES:DI using directory info at BX and BPB at SI.
;
; Returns: carry set on error (see AH), clear otherwise (AX sectors read)
;
; Modifies: AX, CX, DX
;
DEFPROC	read_data
	mov	dx,1		; DX = sectors already read
rd1:	cmp	word ptr [bx+4],0
	jne	rd2
	cmp	word ptr [bx+6],0
	je	rd3		; file size is zero, carry clear
rd2:	mov	ax,[bx+2]	; AX = CLN
	cmp	ax,2		; too low?
	jc	rd3		; yes
	cmp	ax,CLN_END	; too high?
	cmc
	jc	rd3		; yes
	call	read_cluster	; read cluster into DI
	jc	rd3		; error
	mul	[si].BPB_SECBYTES; DX:AX = number of sectors read
	add	di,ax		; adjust next read address
	sub	[bx+4],ax	; reduce file size
	sbb	[bx+6],dx	; (DX is zero)
	jnc	rd4		; jump if file size still positive
	add	di,[bx+4]	; rewind next load address by
	clc			; the amount of file size underflow
rd3:	ret			; and return success
rd4:	mov	ax,[bx+2]	; AX = CLN
	push	es
	mov	es,dx		; relies on DX still being zero
	ASSUME	ES:BIOS
	call	read_fat	; DX = next CLN
	pop	es
	ASSUME	ES:NOTHING
	mov	[bx+2],dx	; update CLN

read_file label near
	sub	dx,dx		; normal case: read all cluster sectors
	jmp	rd1
ENDPROC	read_data

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_cluster
;
; Read cluster AX into memory at DI, using BPB at SI.
;
; Returns: carry set on error (see AH), clear otherwise (AX sectors read)
;
; Modifies: AX, CX
;
DEFPROC	read_cluster
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
ENDPROC	read_cluster

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_sectors
;
; Read CL sectors into DI using LBA in AX and BPB at SI
;
; Returns: carry clear if successful, set if error (see AH for reason)
;
; Modifies: AX
;
DEFPROC	read_sectors
	push	bx
	push	cx
	push	dx
	mov	bl,cl
	call	get_chs2
	mov	al,bl		; AL = # sectors (from original CL)
	mov	ah,FDC_READ
	mov	bx,di		; ES:BX = address
	int	INT_FDC		; AX and carry are whatever the ROM returns
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	read_sectors

errmsg2		db	" Error loading system files, halted",0

;
; Data copied from PART1 (BPB and file data)
;
PART2_COPY	db	(offset PART1_END - offset PART1_COPY) dup (?)
		even
PART2_END	equ	$

BOOT	ends

	end
