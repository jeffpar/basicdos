;
; INT 13h-based Diskette Reader
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
; Usage:   DISKREAD [drive] [filename]
;
; Example: DISKREAD A: DISK1.IMG
;
; This program is going to start out being brain-dead simple: starting
; with curTK, curHD, and curSN (variables representing current track,
; current head, and current sector number), read sectors and write them
; to the specified file.  If an error occurs after MAX_ATTEMPTS, stop.
;
; Those variables are initialized to 0, 0, and 1, respectively.  There are
; also corresponding limit variables (maxTK, maxHD, and maxSN) which are
; all set to predefined maximums, and as soon as an error occurs, they are
; reduced in turn to the presumed limit (ie, 1 greater than the largest
; successful value).
;
; INT 13h Notes (floppy drives only):
;
; To read a sector: AH = 02h, DL = drive #, DH = head #, CH = track #,
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
	je	m6		; process the second argument
	push	ax		;
	lodsb			; make sure next char is a colon
	cmp	al,':'		; is it?
	pop	ax		;
	jne	m8		; no
	call	get_drv		; convert drive letter in AL to drive #
	jc	m8		; failed
	mov	dl,al		; DL = drive #
m5:	lodsb			; read chars until we find more whitespace
	cmp	al,20h		; whitespace?
	ja	m5		; no
	mov	byte ptr [si-1],0
	jmp	m2		; yes
m6:	lea	bx,[si-1]	; BX -> specified file name
	jmp	m5		; skip over the remaining non-whitespace chars

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
	sub	cx,cx		; CX = attributes
	mov	ah,DOS_HDL_CREATE
	int	21h		;
	jnc	m18		;
	mov	ax,offset filerr
	jmp	m9		; print string and return to DOS

m18:	mov	[hFile],ax	; save file handle
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
; Start reading the disk.
;
m20:	mov	si,MAX_ATTEMPTS	; SI = total attempts allowed

m21:	call	pr_parms	; print all the parameters
	mov	ax,word ptr [totSN]
	mov	cx,word ptr [curSN]
	mov	dx,word ptr [curDR]
	mov	bx,offset sector; ES:BX -> sector buffer
	int	13h
	jnc	m30		; presumably worked

	cmp	byte ptr [maxSN],MAX_SECTOR
	jne	m22
	mov	[maxSN],cl
	dec	cx
	mov	[totSN],cl
	jmp	short m40	; advance to next sector

m22:	cmp	byte ptr [maxHD],MAX_HEAD
	jne	m23
	mov	[maxHD],dh
	jmp	short m41	; advance to next track

m23:	cmp	ch,40		; are we likely done?
	je	m50		; yes
	cmp	ch,80
	je	m50

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
	mov	byte ptr [totSN],1
	jmp	m21		; revert to single-sector reads and retry
m24:	jmp	m20		; read next sector(s)
;
; Write the sector(s) we just read.
;
m30:	mov	al,[totSN]
	cbw			; AX = sectors read
	mov	cx,SECTOR_SIZE	; CX = bytes per sector
	mul	cx		; DX:AX = total bytes to write
	xchg	cx,ax		; CX = total bytes
	mov	bx,[hFile]
	mov	dx,offset sector
	mov	ah,DOS_HDL_WRITE
	int	21h
	jc	m50
;
; Advance to the next sector; once we transition to reading tracks,
; this switches to advancing to the next track.
;
m40:	cmp	byte ptr [totSN],1
	ja	m41		; advance to next track
	inc	byte ptr [curSN]
	mov	al,[curSN]
	cmp	al,[maxSN]
	jb	m24
m41:	mov	byte ptr [curSN],1
	inc	byte ptr [curHD]
	mov	al,[curHD]
	cmp	al,[maxHD]
	jb	m24
	mov	byte ptr [curHD],0
	inc	byte ptr [curTK]
	mov	al,[curTK]
	cmp	al,[maxTK]
	jb	m24
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
	mov	al,[totSN]
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

totSN	db	1
dskFN	db	02h
curDR	db	0
curHD	db	0
curSN	db	1
curTK	db	0
maxTK	db	MAX_TRACK
maxHD	db	MAX_HEAD
maxSN	db	MAX_SECTOR

dotmsg	db	"...",'$'
errmsg	db	" error ",'$'
finmsg	db	" done",0Dh,0Ah,'$'
fname	db	"DISK.IMG",0
usage	db	"usage: diskread [drive] [filename]",0Dh,0Ah,'$'
argerr	db	"invalid arguments",0Dh,0Ah,'$'
memerr	db	"insufficient memory",0Dh,0Ah,'$'
filerr	db	"error creating output file"
crlf	db	0Dh,0Ah,'$'

	even
sector	label	byte

CODE	ENDS

	end	main
