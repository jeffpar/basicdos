;
; INT 13h-based Diskette Writer
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2022 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dosapi.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	100h
;
; Usage:   DISKWRIT [filename] [drive]
;
; Example: DISKWRIT DISK1.IMG A:
;
; Unlike DISKREAD, which figures out the disk geometry by trial-and-error,
; we use a specific geometry based on IMG size.
;
; INT 13h Notes (floppy drives only):
;
; To write a sector: AH = 03h, DL = drive #, DH = head #, CH = track #,
; CL = sector #, AL = # sectors, ES:BX = addr (must not cross 64K boundary).
;
; If successful, carry is clear and AL *may* be number of sectors read
; (you can't rely on AL); otherwise, carry is set and AH is an error code.
;

SECTOR_SIZE	equ	512
K		equ	1024
MAX_DRIVE	equ	4
MAX_TRACK	equ	80
MAX_HEAD	equ	4
MAX_SECTOR	equ	20
MAX_BUFFER	equ	(MAX_SECTOR * SECTOR_SIZE)
MAX_ATTEMPTS 	equ	3

DSIZE		struc
kBytes		dw	?
nTracks		db	?
nHeads		db	?
nSectors	db	?
nReserved	db	?
DSIZE		ends

DEFPROC	main
	cld
	mov	dl,0		; DL = default drive
	mov	bx,offset fname	; BX -> default output file name
	sub	cx,cx		; CX = argument count
	mov	si,PSP_CMDTAIL+1
m1:	lodsb			; AL = char from PSP command tail
m2:	cmp	al,0Dh		; CR?
	je	m10		; yes, we're done with the command tail
	cmp	al,20h		; space?
	jne	m4		; no
m3:	lodsb			; check for more spaces
	cmp	al,20h		;
	je	m3		;
	inc	cx		; advance argument count
	jmp	m2		;
m4:	cmp	cx,2		; do we have the first argument yet?
	ja	m8		; too many arguments
	je	m5		; process the second argument
	lea	bx,[si-1]	; BX -> specified file name
	jmp	m6		; skip over the remaining non-whitespace chars
m5:	push	ax		;
	lodsb			; make sure next char is a colon
	cmp	al,':'		; is it?
	pop	ax		;
	jne	m8		; no
	call	get_drv		; convert drive letter in AL to drive #
	jc	m8		; failed
	mov	dl,al		; DL = drive #
m6:	lodsb			; read chars until we find more whitespace
	cmp	al,20h		; whitespace?
	ja	m6		; no
	mov	byte ptr [si-1],0
	jmp	m2		; yes

m7:	mov	ax,offset usage
	jmp	short m9
m8:	mov	ax,offset argerr
m9:	jmp	pr_str		; print string and return to DOS
;
; We've finished examining the command line, so update our defaults
; and create the output file.
;
; There's also a check for a minimum number of arguments (ie, drive letter),
; but that can be commented out to allow defaults for everything.
;
m10:	cmp	cx,1		; enough arguments?
	jb	m7		; no
	mov	[curDR],dl
	mov	dx,bx		; DS:DX -> file name
	mov	ax,DOS_HDL_OPENRO
	int	21h		;
	jnc	m15		;
m11:	mov	ax,offset filerr
	jmp	m9		; print string and return to DOS

m15:	mov	[hFile],ax	; save file handle
;
; Get the size of the image file by seeking to the end.
;
	xchg	bx,ax		; BX = file handle
	sub	cx,cx
	sub	dx,dx		; CX:DX = offset
	mov	ax,DOS_HDL_SEEKEND
	int	21h
	jc	m11
;
; Search the dSizes table for a matching image file size,
; by converting the file size in DX:AX to kBytes
;
	mov	cx,1024
	div	cx		; AX = kBytes, DX = remainder
	mov	si,offset dSizes
m16:	mov	dx,[si].kBytes
	test	dx,dx
	js	m11		; we've reached the -1 table terminator
	cmp	ax,dx
	jne	m17
	mov	al,[si].nTracks
	mov	[maxTK],al
	mov	al,[si].nHeads
	mov	[maxHD],al
	mov	al,[si].nSectors
	mov	[maxSN],al
	jmp	short m18
m17:	add	si,size DSIZE
	jmp	m16

m18:	sub	cx,cx
	sub	dx,dx		; CX:DX = seek offset
	mov	ax,DOS_HDL_SEEKBEG
	int	21h		; return to beginning of file
;
; Make sure our sector buffer doesn't cross a 64K boundary.
;
	mov	ax,ds
	mov	cl,4
	shl	ax,cl
	add	ax,[buffer]	; AX = offset within current 64K
	add	ax,MAX_BUFFER	; add a worst-case number of bytes
	jnc	m19		; if there's no carry, we should be OK
	add	[buffer],MAX_BUFFER
m19:	mov	ax,[buffer]
	add	ax,MAX_BUFFER
	cmp	ax,sp
	jb	m20
	mov	ax,offset memerr
	jmp	m9
;
; Start reading the disk image file.
;
m20:	mov	al,[maxSN]
	cbw			; AX = sectors read
	mov	cx,SECTOR_SIZE	; CX = bytes per sector
	mul	cx		; DX:AX = total bytes to read
	xchg	cx,ax		; CX = total bytes
	mov	bx,[hFile]
	mov	dx,offset sector
	mov	ah,DOS_HDL_READ
	int	21h
	jc	m50

m30:	mov	si,MAX_ATTEMPTS	; SI = total attempts allowed

m31:	call	pr_parms	; print all the parameters
	mov	ax,word ptr [maxSN]
	mov	cx,word ptr [curSN]
	mov	dx,word ptr [curDR]
	mov	bx,offset sector; ES:BX -> sector buffer
	int	13h
	jnc	m40		; presumably worked

	push	ax		; save the error (in AH)
	mov	ax,offset errmsg
	call	pr_str
	pop	ax		; recover the error
	mov	al,ah		; AL = error from AH
	call	pr_byte		; print the error number
	call	rd_char		; read a char
	mov	ax,offset crlf	; followed by CR/LF
	call	pr_str

	dec	si
	jz	m50		; no more attempts allowed
	mov	ah,0
	int	13h		; perform a disk reset
	jmp	m31		; revert to single-sector reads and retry
;
; Advance to the next track.
;
m40:	inc	byte ptr [curHD]
	mov	al,[curHD]
	cmp	al,[maxHD]
	jb	m20
	mov	byte ptr [curHD],0
	inc	byte ptr [curTK]
	mov	al,[curTK]
	cmp	al,[maxTK]
	jb	m20
;
; Close output file and return to DOS.
;
m50:	mov	ax,offset finmsg
	call	pr_str
	mov	bx,[hFile]
	mov	ah,DOS_HDL_CLOSE
	int	21h
	ret			; return to DOS
ENDPROC	main

;
; FUNCTION: get_drv
;
; INPUTS: AL = drive letter ('A', 'b', etc)
;
; OUTPUTS: AL = INT 13h drive number if carry clear; carry set if error
;
; USES: AL only
;
DEFPROC	get_drv
	cmp	al,'a'		; lower case?
	jb	gd1		; no
	sub	al,20h		; convert to upper case
gd1:	sub	al,'A'		;
	jb	gd9		; error (carry set)
	cmp	al,MAX_DRIVE	; valid drive?
	cmc			; carry will be set if valid, so flip it
gd9:	ret			;
ENDPROC	get_drv

;
; FUNCTION: pr_parms
;
; INPUTS: None
;
; OUTPUTS: Prints all the current disk read parameters
;
; USES: AX only
;
DEFPROC	pr_parms
	mov	al,0Dh
	call	pr_char
	mov	al,[curTK]
	call	pr_byte
	mov	al,':'
	call	pr_char
	mov	al,[curHD]
	call	pr_byte
	mov	al,':'
	call	pr_char
	mov	al,[curSN]
	call	pr_byte
	mov	ax,offset dotmsg
	call	pr_str
	mov	al,[maxSN]
	call	pr_byte
	ret
ENDPROC	pr_parms

;
; FUNCTION: pr_byte (pr_word)
;
; INPUTS: AL = byte (AX = word)
;
; OUTPUTS: Prints the specified number in decimal
;
; USES: AX only
;
DEFPROC	pr_byte			; print the byte in AL
	mov	ah,0		;
pr_word	label	near		; print the word in AX
	push	cx
	push	dx
	mov	dx,-1
	push	dx		; push terminator (-1)
	inc	dx		; DX:AX is dividend
	mov	cx,10		; CX = divisor
pw1:	div	cx		; AX = quotient, DX = remainder
	push	dx		; push remainder
	cwd			; 0:AX is the new dividend
	test	ax,ax		; all done?
	jnz	pw1		; no
pw2:	pop	ax		; pop remainder (0-9, or -1 if done)
	test	ax,ax
	js	pw9		; all done
	add	al,'0'
	call	pr_char
	jmp	pw2
pw9:	pop	dx
	pop	cx
	ret
ENDPROC	pr_byte

;
; FUNCTION: pr_char
;
; INPUTS: AL = character
;
; OUTPUTS: Prints the specified character
;
; USES: AX only
;
DEFPROC	pr_char			; print the char in AL
	push	dx
	xchg	dx,ax		; DL = char in AL
	mov	ah,DOS_TTY_WRITE
	int	21h
	pop	dx
	ret
ENDPROC	pr_char

;
; FUNCTION: pr_str
;
; INPUTS: AX -> '$'-terminated string
;
; OUTPUTS: Prints the specified string
;
; USES: AX only
;
DEFPROC	pr_str			; print the string at offset AX
	push	dx
	xchg	dx,ax		; DX -> string
	mov	ah,DOS_TTY_PRINT
	int	21h
	pop	dx
	ret
ENDPROC	pr_str

;
; FUNCTION: rd_char
;
; INPUTS: None
;
; OUTPUTS: AL = character
;
; USES: AX only
;
DEFPROC	rd_char
	mov	ah,DOS_TTY_READ
	int	21h
	ret
ENDPROC	rd_char

	even
hFile	dw	0
buffer	dw	offset sector

curDR	db	0
curHD	db	0
curSN	db	1
curTK	db	0
maxTK	db	MAX_TRACK
maxHD	db	MAX_HEAD
maxSN	db	MAX_SECTOR
dskFN	db	03h

;
; Table for mapping known disk image sizes to disk geometry
;
dSizes	label	dword
	DSIZE	<160,40,1,8>
	DSIZE	<180,40,1,9>
	DSIZE	<320,40,2,8>
	DSIZE	<360,40,2,9>
	DSIZE	<720,80,2,9>
	DSIZE	<1200,80,2,15>
	DSIZE	<1440,80,2,18>
	DSIZE	<-1>

dotmsg	db	"...",'$'
errmsg	db	" error ",'$'
finmsg	db	" done",0Dh,0Ah,'$'
fname	db	"DISK.IMG",0
usage	db	"usage: diskwrit [filename] [drive]",0Dh,0Ah,'$'
argerr	db	"invalid arguments",0Dh,0Ah,'$'
memerr	db	"insufficient memory",0Dh,0Ah,'$'
filerr	db	"error creating output file"
crlf	db	0Dh,0Ah,'$'

	even
sector	label	byte

CODE	ENDS

	end	main
