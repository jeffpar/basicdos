;
; BASIC-DOS Boot Code
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	BIOSAPI equ 1
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	devapi.inc
	include	version.inc

	IFDEF	FINAL
	TWAIT	equ 1		; FINAL builds use a 5-second prompt
	ENDIF

;
; DISKSECS is non-zero on supported boot volumes, so LARGESECS is unused.
; Its low word is scratch space for the boot loader's data-cluster count.
;
BOOT_CLUSTERS	equ	BPB_LARGESECS

BOOT	segment word public 'CODE'

;
; We "ORG" at BOOT_SECTOR_LO rather than BOOT_SECTOR, because after Part 1
; finishes, we're running at BOOT_SECTOR_LO.
;
	org	BOOT_SECTOR_LO
        ASSUME	CS:BOOT, DS:NOTHING, ES:NOTHING, SS:NOTHING
;
; All we assume on entry is:
;
;	CS = 0
;	IP = 7C00h
;	DL = drive # (eg, 00h or 80h)
;
; The original IBM PC had these additional inputs:
;
;	DS = ES = 0
;	SS:SP = 30h:100h
;
; which apparently didn't become a standard, because if we rely on those
; other assumptions, we can run into boot failures.
;
start:	cld
	jmp	short start1

	DEFLBL	PART1_COPY	; start of PART1 code/data

mybpb:		BPB	<,512,1,1,2,64,320,MEDIA_160K,1,8,1,0,0,0,8,3,7>

;
; CFG_FILE must remain last, because it's the only optional file, and the
; root directory scan ends as soon as any file search reaches the end marker.
;
DEV_FILE	db	"BASDEV  COM"
DOS_FILE	db	"BASDOS  COM"
CFG_FILE	db	"CONFIG  SYS",-1
;
; This intermediate jump could be eliminated if I used a long jump above,
; but I wanted to make this boot sector unique in the annals of "future" boot
; sectors, by using CLD (FCh) as the first opcode.  Will it confuse "future"
; Intel boot sector detection code?  Maybe.  Do I care?  No.
;
start1:	jmp	short part1	; can't quite make it in one jump

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_chs
;
; Get CHS from LBA in AX, using BPB at DS:SI.  The LBA is relative to the
; volume, so we add the BPB's hidden sectors (non-zero only for hard disk
; partitions).  Include both words of BPB_HIDDENSECS and any carry from
; adding the volume-relative sector number.
;
; Inputs:
;	AX = LBA
;	DS:SI -> BPB
;
; Outputs:
;	DH = head #, DL = drive #
;	CH = cylinder #, CL = sector ID
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	get_chs
	sub	dx,dx
	add	ax,[si].BPB_HIDDENSECS.LOW
	adc	dx,[si].BPB_HIDDENSECS.HIW ; DX:AX is LBA
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
; Get LBA from CLN in AX, using BPB at DS:SI.
;
; Inputs:
;	AX = CLN
;	DS:SI -> BPB
;
; Outputs:
;	If successful, carry clear, AX = LBA, CX = sectors per cluster
;	If unsuccessful, carry set
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	get_lba
	sub	ax,2
	jb	gl9
	sub	cx,cx
	mov	cl,[si].BPB_CLUSSECS
	mul	cx
	add	ax,[si].BPB_LBADATA
gl9:	ret
ENDPROC	get_lba

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_sector
;
; Read 1 sector into ES:DI using LBA in AX and BPB at DS:SI.
;
; Inputs:
;	AX = LBA
;	DS:SI -> BPB
;	ES:DI -> buffer
;
; Output:
;	Carry clear if successful, set if error (see AH for reason)
;
; Modifies:
;	AX
;
DEFPROC	read_sector
	push	bx
	push	cx
	push	dx
	call	get_chs
	mov	ax,(FDC_READ SHL 8) OR 1
	mov	bx,di		; ES:BX = address
	int	INT_FDC		; AX and carry are whatever the ROM returns
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	read_sector

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; print
;
; Print the null-terminated string at DS:SI.
;
; Inputs:
;	DS:SI -> string
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, SI
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

	DEFLBL	PART1_COPY_END		; end of PART1 code/data to copy

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Part 1 of the boot process:
;
; Move the DPT from ROM to RAM so we can tweak a few values, and then move
; ourselves to low memory where we'll be out of the way, should we ever need
; to load more than 32K.
;
	DEFLBL	PART1

	push	cs
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
; If there's a hard disk, but we didn't boot from it, display a prompt.
;
; If there's no hard disk (or we were told to bypass it), then look for
; all the the required files in the root directory (starting with DEV_FILE),
; load the first sector of the first file, and continue booting from there.
;
DEFPROC	main,far			; now at BOOT_SECTOR_LO
	mov	ds:[mybpb].BPB_DRIVE,dl	; save boot drive (DL) in BPB
	IFDEF DEBUG
	cmp	ds:[BOOT_KEY].LOB,cl	; boot key zero?
	jne	m0			; no, force a boot prompt
	ENDIF
	test	dl,dl			; hard drive?
	jl	find			; yes
	mov	ah,HDC_GETPARMS		; get hard drive parameters
	mov	dl,80h			;
	int	INT_FDC			;
	jc	find			; jump if call failed
	test	dl,dl			; any hard disks?
	jz	find			; jump if no hard disks
m0:	mov	si,offset product
	call	print			; print the product name
	call	print			; then the prompt
;
; Wait for a key; ESC boots from the hard disk, and any other key continues
; booting from this disk.  If TWAIT is defined (as it is in FINAL builds), then
; we wait at most TWAIT * 91 ticks (about 5 seconds each, and TWAIT must be 2
; or less), and a timeout also continues booting from this disk.  In PCjs
; machines running faster than normal, the ticks run faster too (so the ROM
; POST tests don't fail), so the timeout will be shorter.
;
	IFDEF	TWAIT
	mov	dl,91 * TWAIT
	add	dl,byte ptr [TIMER_LOW]	; DL = target tick count (low byte)
m8:	mov	ah,KBD_CHECK
	int	INT_KBD
	jnz	m9			; a key is available
	cmp	dl,byte ptr [TIMER_LOW]	; target tick count reached?
	jne	m8			; no
	jmp	short m10		; yes, continue booting from this disk
	ENDIF
m9:	mov	ah,KBD_READ
	int	INT_KBD			; AL = char code, AH = scan code
	cmp	al,CHR_ESCAPE		; escape key?
	je	hard			; yes, boot from the hard disk
	mov	[BOOT_KEY],ax		; save boot key
m10:	mov	si,offset crlf
	call	print
;
; Find all the files in our file list, starting with DEV_FILE.
;
find:	mov	si,offset mybpb		; SI -> BPB
	mov	dx,[si].BPB_LBAROOT	; DX = root dir LBA
m1:	mov	ax,dx			; AX = LBA
	mov	di,offset DIR_SECTOR	; DI = dir sector
	call	read_sector		; read it
	jc	boot_error		; jump if error
m2:	mov	cx,3			; CX = # files left to find
	mov	bx,offset DEV_FILE	; first file to find
m3:	cmp	byte ptr [bx],ch	; more files to find?
	jl	m7			; no, see if we're done
	jle	m4			; yes, but this file was already found
	call	find_dirent		; CF set at end of directory
	jc	m6			; no more root sectors to read
	jnz	m5			; not found, try the next file
m4:	dec	cx			; reduce the # files left
m5:	add	bx,size DIR_NAME	; partly, skip to next filename
	jmp	m3			; and check again
m7:	jcxz	read			; all files found, go read
	inc	dx			; DX = next dir LBA
	cmp	dx,[si].BPB_LBADATA	; exhausted root directory?
	jb	m1			; jump if not exhausted
m6:	loop	file_error		; only one file may remain
	cmp	[CFG_FILE],ch		; was the missing file CFG_FILE?
	jnz	read			; yes, that's OK

file_error label near
	IFDEF LATER
	mov	si,offset errmsg2
	jmp	short hltmsg
	ENDIF

boot_error label near
	mov	si,offset errmsg1
hltmsg:	call	print
	jmp	$			; "halt"
;
; There's a hard disk and no response, so boot from hard disk instead.
;
hard:	mov	al,[CRT_MODE]
	cbw				; AH = 00h (SET MODE)
	int	INT_VIDEO
	mov	ax,0201h		; AH = 02h (READ), AL = 1 sector
	mov	cx,1			; CH = CYL 0, CL = SEC 1
	mov	dx,0080h		; DH = HEAD 0, DL = DRIVE 80h
	mov	bx,BOOT_SECTOR		; ES:BX -> BOOT_SECTOR
	int	INT_FDC			; read it
	jc	boot_error
	jmp	bx			; jump to the hard disk boot sector
;
; We found all the required files, so read the first sector of the first file.
;
read:	mov	ax,word ptr [DEV_FILE+2]; AX = CLN
	call	get_lba
	jc	boot_error
	call	read_sector		; DI -> DIR_SECTOR
	jc	boot_error
;
; Move the non-boot code from this sector (ie, the first chunk of DEV_FILE)
; into its final resting place (ie, BIOS_END) and save that ending address as
; the next load address.
;
move:	mov	ax,[si].BPB_SECBYTES
	mov	si,offset PART2_COPY
	mov	di,offset BIOS_END
	mov	cx,offset DIR_SECTOR
	add	cx,ax
	sub	cx,si
	rep	movsb			; move first bit of DEV_FILE

	jmp	near ptr part2 + 2	; jump to next part (skip fake INT 20h)
ENDPROC	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; find_dirent
;
; Find DIRENT in sector at ES:DI using filename at DS:BX.
;
; Inputs:
;	DS:BX -> filename
;	ES:DI -> directory sector
;
; Outputs:
;	Zero flag set if match (in DI), carry set if end of directory
;
; Modifies:
;	AX
;
DEFPROC	find_dirent
	push	cx		; CH is zero on entry
	push	si
	push	di
	mov	ax,[si].BPB_SECBYTES
	add	ax,di		; AX -> end of sector data
	dec	ax		; ensure DI will never equal AX
fd1:	cmp	byte ptr [di],1	; 00h marks end; return NZ and carry set
	jb	fd9
	mov	si,bx
	mov	cl,size DIR_NAME
	repe	cmpsb
	jz	fd8
	add	di,cx
	add	di,size DIRENT - 11
	cmp	di,ax
	jb	fd1
	jmp	short fd9
fd8:	mov	[bx],cl		; zero the first byte of the filename
	lea	si,[di-11].DIR_CLN
	lea	di,[bx+2]	; and follow it with cluster number and size,
	mov	cl,3		; since we're done with the filename
	rep	movsw
fd9:	pop	di
	pop	si
	pop	cx
	ret
ENDPROC	find_dirent

product		db	"BASIC-DOS "
		VERSION_STR
crlf		db	13,10,0
prompt		db	"Press a key to start...",0
errmsg1		db	"System boot error, halted",0
	IFDEF LATER
errmsg2		db	"System file(s) missing, halted",0
	ENDIF

	DEFLBL	PART1_END

	ASSERT 	<offset PART1_END - offset start>,LE,510
	ASSERT	<offset CFG_FILE - offset PART1_COPY>,EQ,BOOT_CFGFILE

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
;   (1) Copy critical data from PART1 to PART2, before FAT reads (if any)
;	overwrite it.
;
;   (2) Load the rest of DEV_FILE; the file need not be first, nor
;	contiguous, since we read the FAT to process the cluster chain;
;	the downside is that any FAT sectors read will overwrite the first
;	half of the boot code, so any code/data that must be copied between
;	the halves should be copied above (see step 1).
;
;   (3) Locate DEV_FILE's "init" code, which resides just beyond all the
;	device drivers, and call it.  It must return the next available
;	load address.
;
DEFPROC	part2,far
	int	20h		; fake DOS terminate call
;
; When booting from a hard disk, the MBR's stack (eg, 0:7C00h) may be where
; the rest of our files will be loaded, so use the same stack that the BIOS
; uses to boot from a diskette (30h:100h).
;
	cli
	push	cs
	pop	ss
	mov	sp,400h		; same physical stack top as 30h:100h
	sti

	push	di		; copy PART1 data to PART2
	mov	si,offset PART1_COPY
	mov	di,offset PART2_COPY
	mov	cx,offset PART1_COPY_END - offset PART1_COPY
	rep	movsb

	mov	di,offset FAT_BUFHDR
	mov	cx,offset DIR_SECTOR
	sub	cx,di		; now we can zero the area
	rep	stosb		; from FAT_BUFHDR to DIR_SECTOR
	pop	di		; restore DEV_FILE read address

	mov	bx,offset DEV_FILE2
	sub	[bx+4],ax	; reduce DEV_FILE file size by AX
	sbb	[bx+6],cx	; (CX is zero)

	mov	si,offset PART2_COPY
	mov	ax,[si].BPB_DISKSECS
	sub	ax,[si].BPB_LBADATA
	sub	dx,dx
	mov	cl,[si].BPB_CLUSSECS	; CH is still zero
	div	cx
	mov	word ptr [si].BOOT_CLUSTERS,ax
	call	read_data	; read the rest of DEV_FILE (see BX) into DI
;
; To find the entry point of DEV_FILE's init code, we must walk the
; driver headers.  And since they haven't been chained together yet (that's
; the DEV_FILE init code's job), we do this by simply "hopping" over all
; the headers.
;
	mov	di,offset BIOS_END; BIOS's end is DEV_FILE's beginning
	mov	cx,100		; put a limit on this loop
i1:	mov	ax,[di]		; AX = current driver's total size
	cmp	ax,-1		; have we reached end of drivers?
	je	i3		; yes
	add	di,ax
	loop	i1
i2:	jmp	load_error
;
; Prepare to "call" the DEV_FILE entry point, with DI -> end of drivers.
;
i3:	mov	[DD_LIST].OFF,ax; initialize driver list head (to -1)
	mov	ax,di
	push	cs
	mov	cx,offset part3
	push	cx		; far return address -> part3
	mov	cx,4
	shr	ax,cl
	push	ax
	push	cx		; far "call" address -> CS:0004h
	ret			; "call"
ENDPROC	part2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Part 3 of the boot process:
;
;   (1) When DEV_FILE returns, load DOS_FILE at the next load address,
;	and then jump to it.  At that point, we never return to this code.
;
;   (2) DEV_FILE's init code loads CFG_FILE (using read_file), so that it
;	can process "SKIP=", and before returning, it moves CFG_FILE above
;	where DOS_FILE will be loaded, and replaces the CLN and size in
;	CFG_FILE's DIR info with its offset (relative to DOS_FILE) and size.
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
	mov	bx,offset DOS_FILE2
	call	read_file	; load DOS_FILE
	mov	bx,offset CFG_FILE2
	mov	dx,[bx+4]	; DX = CFG_FILE size
	mov	bx,[bx+2]	; BX = CFG_FILE offset
	push	es
	mov	ax,2		; skip the fake INT 20h in DOS_FILE
	push	ax		; far "jmp" address -> CS:0002h
	mov	ax,offset PART2_COPY
	ret			; AX = offset of BPB
ENDPROC	part3

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; read_data
;
; Read file data into ES:DI using directory info at BX and BPB at DS:SI.
;
; Inputs:
;	BX -> DIR info
;	DS:SI -> BPB
;	ES:DI -> buffer
;
; Output:
;	ES:DI updated to next available address
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	read_data
	mov	dx,1		; DX = sectors already read
rd1:	mov	ax,[bx+4]
	or	ax,[bx+6]
	je	rd3		; file size is zero, carry clear
rd2:	mov	ax,[bx+2]	; AX = CLN
	sub	ax,2
	cmp	ax,word ptr [si].BOOT_CLUSTERS ; CLN outside this volume?
	jae	read_error	; yes
	add	ax,2
	push	dx		; DX = sectors already read
	call	get_lba2	; AX = LBA, CX = sectors/cluster
	pop	dx
	jc	read_error
	add	ax,dx		; adjust LBA by sectors already read
	sub	cx,dx		; sectors remaining?
	jbe	rc8		; no

	push	cx
	push	di
rc1:	push	ax		; save LBA
	call	read_sector2
	pop	dx		; DX = previous LBA
	jc	rc2
	add	di,[si].BPB_SECBYTES
	inc	dx		; advance LBA
	xchg	ax,dx		; and move to AX
	loop	rc1		; keep looping until cluster is fully read
rc2:	pop	di
	pop	cx
	jc	read_error
;
; The ROM claims that, on success, AL will (normally) contain the number of
; sectors actually read, but I'm not seeing that, so I'll just move CL to AL.
;
rc8:	xchg	ax,cx
	mul	[si].BPB_SECBYTES; DX:AX = number of sectors read
	add	di,ax		; adjust next read address
	sub	[bx+4],ax	; reduce file size
	sbb	[bx+6],dx	; (DX is zero)
	jnc	rd5		; jump if file size still positive
	add	di,[bx+4]	; rewind next load address by
rd3:	ret			; the amount of file size underflow

read_error label near
	jmp	load_error

rd5:	mov	ax,[bx+2]	; AX = CLN
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
; read_fat (see also: get_cln in disk.asm)
;
; For the CLN in AX, get the next CLN in DX, using the BPB at DS:SI.
;
; Inputs:
;	AX = CLN
;	DS:SI -> BPB
;
; Outputs:
;	DX (next CLN)
;
; Modifies:
;	AX, CX, DX, BP
;
DEFPROC	read_fat
	push	bx
	push	di
	mov	bp,ax		; save cluster parity for FAT12 decoding
	mov	bx,ax
	cmp	word ptr [si].BOOT_CLUSTERS,CLN_FAT12 ; FAT16 (4085+ clusters)?
	jae	rf16
;
; FAT12 byte offset = CLN + CLN/2; FAT16 sector = CLN/256.
;
	shr	ax,1
	add	bx,ax
	mov	ax,bx
	mov	cl,9
	shr	ax,cl
	and	bx,511
	jmp	short rf0
rf16:	mov	al,ah
	mov	ah,0
	mov	bh,0
	shl	bx,1
rf0:	add	ax,[si].BPB_RESSECS
	mov	di,offset FAT_SECTOR
	cmp	ax,[FAT_BUFHDR].BUF_LBA
	je	rf1
	mov	[FAT_BUFHDR].BUF_LBA,ax
	call	read_sector2
	jc	read_error

rf1:
	mov	dl,[di+bx]
	inc	bx
	cmp	bx,512		; at the sector boundary?
	jb	rf2		; no
	inc	[FAT_BUFHDR].BUF_LBA
	mov	ax,[FAT_BUFHDR].BUF_LBA
	call	read_sector2	; read next FAT LBA
	jc	read_error
	sub	bx,bx
rf2:	mov	dh,[di+bx]
	cmp	word ptr [si].BOOT_CLUSTERS,CLN_FAT12 ; FAT16 uses all 16 bits
	jae	rf9
	shr	bp,1		; was that an odd nibble again?
	jnc	rf8		; even entries need only masking
	mov	cl,4
	shr	dx,cl
rf8:	and	dx,0FFFh

rf9:	pop	di
	pop	bx
	ret
ENDPROC	read_fat



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
	mov	si,offset errmsg3
	call	print2
	jmp	$		; "halt"
ENDPROC	load_error

errmsg3		db	"Load error",0

;
; Code and data copied from PART1 (BPB, file data, and shared functions)
;
	DEFLBL	PART2_COPY

	org	$ + (offset DEV_FILE - offset PART1_COPY)
DEV_FILE2	label	byte
	org	$ + (offset DOS_FILE - offset DEV_FILE)
DOS_FILE2	label	byte
	org	$ + (offset CFG_FILE - offset DOS_FILE)
CFG_FILE2	label	byte
	org	$ + (offset get_lba - offset CFG_FILE)
get_lba2	label	near
	org	$ + (offset read_sector - offset get_lba)
read_sector2	label	near
	org	$ + (offset print - offset read_sector)
print2		label	near
	org	$ + (offset PART1_COPY_END - offset print)

	DEFLBL	PART2_END

	ASSERT 	<offset PART2_END - offset part2>,LE,512
	ASSERT	<offset read_file - offset part3>,EQ,BOOT_RDFILE

BOOT	ends

	end
