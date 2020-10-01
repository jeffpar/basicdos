;
; BASIC-DOS Boot Code
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	disk.inc
	include	devapi.inc
	include	dosapi.inc

	; TWAIT equ 16			; timed wait is now disabled

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

	DEFLBL	PART1_COPY		; start of PART1 code/data

mybpb:		BPB	<,512,1,1,2,64,320,MEDIA_160K,1,8,1,0,0,0,8,3,7>

DEV_FILE	db	"IBMBIO  COM"
DOS_FILE	db	"IBMDOS  COM"
CFG_FILE	db	"CONFIG  SYS",-1

start1:	jmp	short part1		; can't quite make it in one jump

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_chs
;
; Get CHS from LBA in AX, using BPB at DS:SI.
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
; part1
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
	call	wait			; wait for a key
	jcxz	hard			; jump if no key pressed
	mov	[BOOT_KEY],cx		; save boot key
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
	jg	m6			; no, this file hasn't been found yet
m4:	dec	cx			; reduce the # files left
m5:	add	bx,size DIR_NAME	; partly, skip to next filename
	jmp	m3			; and check again
m6:	call	find_dirent		;
	jz	m4			; we found a file
	jmp	m5			; no, try the next file
m7:	jcxz	read			; all files found, go read
	inc	dx			; DX = next dir LBA
	cmp	dx,[si].BPB_LBADATA	; exhausted root directory?
	jb	m1			; jump if not exhausted
	dec	cx			; only 1 file missing?
	jnz	file_error		; no
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
	inc	cx			; CH = CYL 0, CL = SEC 1
	mov	dx,0080h		; DH = HEAD 0, DL = DRIVE 80h
	mov	bx,BOOT_SECTOR		; ES:BX -> BOOT_SECTOR
	int	INT_FDC			; read it
	jc	boot_error
	jmp	bx			; jump to the hard disk boot sector
;
; We found all the required files, so read the first sector of the first file.
;
read:	mov	bx,offset DEV_FILE
	mov	ax,[bx+2]		; AX = CLN
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
fd1:	cmp	byte ptr [di],ch
	je	file_error	; 0 indicates end of allocated entries
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
	mov	ax,[di-11].DIR_CLN
	mov	[bx+2],ax	; with cluster number and size,
	mov	ax,[di-11].DIR_SIZE.OFF
	mov	[bx+4],ax	; since we're done with the filename
	mov	ax,[di-11].DIR_SIZE.SEG
	mov	[bx+6],ax
fd9:	pop	di
	pop	si
	pop	cx
	ret
ENDPROC	find_dirent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; wait (for a key)
;
; Waits some number of ticks, or until a key is pressed.
;
; NOTE: There are now two variations of this function: if TWAIT is defined,
; then we perform the original timed wait (91 ticks or 5 seconds); otherwise,
; we wait indefinitely for a key, and if the key is ESC, then we return 0,
; indicating that our boot code should be bypassed.
;
; There are two main advantages to NOT using TWAIT: 1) faster-than-normal
; PCJS machines generate ticks faster as well, so that the IBM ROM POST tests
; won't fail, which means the delay may be too short; and 2) it makes the boot
; code smaller.
;
; Inputs:
;	None
;
; Outputs:
;	CX = char code (lo), scan code (hi); 0 if no key pressed
;
; Modifies:
;	AX, CX (and DX if TWAIT is defined)
;
DEFPROC	wait
	IFDEF	TWAIT
	mov	ah,TIME_GETTICKS
	int	INT_TIME	; CX:DX is initial tick count
	add	ax,91 * TWAIT
	mov	dx,cx
	adc	dx,0		; DX:AX is target tick count
ws1:	push	dx
	push	ax
	mov	ah,KBD_CHECK
	int	INT_KBD
	jz	ws2
	pop	ax
	pop	dx
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
	ELSE
	mov	ah,KBD_READ
	int	INT_KBD
	cmp	al,CHR_ESCAPE	; escape key?
	xchg	cx,ax		; CL = char code, CH = scan code
	jne	ws9
	sub	cx,cx		; yes, zero CX
	ENDIF
ws9:	mov	si,offset crlf
	call	print
	ret
ENDPROC	wait

product		db	"BASIC-DOS "
		VERSION_STR
crlf		db	13,10,0
prompt		db	"Press any key to start...",0
errmsg1		db	"System boot error, halted",0
	IFDEF LATER
errmsg2		db	"System file(s) missing, halted",0
	ENDIF

	DEFLBL	PART1_END

	ASSERT 	<offset PART1_END - offset start>,LE,510

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
;    2) Load the rest of DEV_FILE; the file need not be first, nor
;	contiguous, since we read the FAT to process the cluster chain;
;	the downside is that any FAT sectors read will overwrite the first
;	half of the boot code, so any code/data that must be copied between
;	the halves should be copied above (see step 1).
;
;    3) Locate DEV_FILE's "init" code, which resides just beyond all the
;	device drivers, and call it.  It must return the next available
;	load address.
;
DEFPROC	part2,far
	int	20h		; fake DOS terminate call

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
	test	ax,0Fh		; paragraph boundary?
	jnz	i2		; no
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
	mov	bx,offset DOS_FILE2
	call	read_file	; load DOS_FILE
	push	di
	mov	bx,offset CFG_FILE2
	sub	dx,dx		; default CFG_FILE size is zero
	cmp	[bx],dl		; did we find CFG_FILE?
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
;
; Sysinit will initialize the buffer chain, but it still assumes that any
; buffer we used (ie, FAT_BUF) will contain valid BUF_DRIVE and BUF_LBA values,
; so that we don't needlessly throw good disk data away.  This code was loaded
; into DIR_BUF, so DIR_BUF is already toast, which is why we already zeroed
; DIR_BUFHDR.
;
	mov	al,[si].BPB_DRIVE
	mov	[FAT_BUFHDR].BUF_DRIVE,al

	mov	dx,1		; DX = sectors already read
rd1:	cmp	word ptr [bx+4],0
	jne	rd2
	cmp	word ptr [bx+6],0
	je	rd3		; file size is zero, carry clear
rd2:	mov	ax,[bx+2]	; AX = CLN
	cmp	ax,2		; too low?
	jc	read_error	; yes
	cmp	ax,CLN_END	; too high?
	jae	read_error	; yes
	call	read_cluster	; read cluster into DI
	jc	read_error	; error
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
; That'll be tough to do without wasting buffer memory though, since sectors
; can be as large as 1K.
;
	mov	bx,ax
	add	ax,ax
	add	ax,bx
	mov	bx,ax
	mov	cl,10
	shr	ax,cl		; AX = FAT sector ((CLN * 3) SHR 10)
	add	ax,[si].BPB_RESSECS
;
; Next, we need the nibble offset within the sector, which is:
;
;	((CLN * 12) % 4096) / 4
;
	and	bx,3FFh		; nibble offset (assuming 1024 nibbles)
	mov	di,offset FAT_SECTOR
	cmp	ax,[FAT_BUFHDR].BUF_LBA
	je	rf1
	mov	[FAT_BUFHDR].BUF_LBA,ax
	call	read_sector2
	jc	read_error

rf1:	mov	bp,bx		; save nibble offset in BP
	shr	bx,1		; BX -> byte, carry set if odd nibble
	mov	dl,[di+bx]
	inc	bx
	cmp	bp,03FFh	; at the sector boundary?
	jb	rf2		; no
	inc	[FAT_BUFHDR].BUF_LBA
	mov	ax,[FAT_BUFHDR].BUF_LBA
	call	read_sector2	; read next FAT LBA
	jc	read_error
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
; read_cluster
;
; Read cluster AX into memory at ES:DI, using BPB at DS:SI.
;
; Inputs:
;	AX = CLN
;	DX = # sectors already read from cluster (usually 0)
;	DS:SI -> BPB
;	ES:DI -> buffer
;
; Output:
;	If successful, carry clear, AX = # sectors read
;	If unsuccessful, carry set, AH = BIOS error code
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	read_cluster
	push	dx		; DX = sectors already read
	call	get_lba2	; AX = LBA, CX = sectors/cluster
	pop	dx
	jc	rc9
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
	jc	rc9
;
; The ROM claims that, on success, AL will (normally) contain the number of
; sectors actually read, but I'm not seeing that, so I'll just move CL to AL.
;
rc8:	xchg	ax,cx
rc9:	ret
ENDPROC	read_cluster

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

errmsg3		db	"System load error, halted",0

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

BOOT	ends

	end
