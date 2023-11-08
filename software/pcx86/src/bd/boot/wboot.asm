;
; BASIC-DOS Boot Sector Updater
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	devapi.inc
	include	dosapi.inc

CODE    SEGMENT

	org	100h
;
; Removes leading zeroes from BOOT1.COM (or other file specified on the
; command-line) and then writes the next 512 bytes to the boot sector of the
; diskette in drive A (unless /N is specified).  Remaining bytes are written
; to a second file (eg, BOOT2.COM or other specified file) for prepending to
; the first system file.
;
        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	sub	ax,ax			; AH = 0 (unless switch)
	sub	bx,bx			; BX = 0 (unless /N seen)
	mov	dx,offset fname1	; DX -> default first filename
	mov	bp,offset fname2	; BP -> default second filename
	mov	si,80h			; SI -> command-line

	lodsb				; AL = line length
	test	al,al			; zero?
	jz	open			; yes, we're done
m1:	lodsb				; skip leading space(s)
m1a:	cmp	al,CHR_SPACE
	je	m1
	cmp	al,CHR_RETURN
	je	open
	test	ah,ah			; switch character seen?
	jz	m2			; no
	and	ax,not 0FF20h		; clear AH and lower-case bit
	cmp	al,'N'			; is switch character 'N'?
	jne	m1			; no (ignore)
	inc	bx			; set BL to 1 to indicate /N
	jmp	m1
m2:	cmp	al,'/'			; switch character?
	jne	m3			; no
	inc	ah			; yes, flag it
	jmp	m1

m3:	cmp	dx,100h			; has DX already been changed?
	jb	m4			; yes
	lea	dx,[si-1]		; DS:DX -> first filename
	jmp	m5			; continue reading command-line
m4:	cmp	bp,100h			; has BP already been changed?
	jb	m5			; yes
	lea	bp,[si-1]		; DS:BP -> second filename

m5:	lodsb				; skip non-whitespace
	cmp	al,CHR_SPACE
	je	m6
	cmp	al,CHR_RETURN
	jne	m5
m6:	mov	byte ptr [si-1],0	; null-terminate command-line parameter
	jmp	m1a			; re-examine the whitespace

eopen:	mov	dx,offset emopen
	jmp	emsg
eread:	mov	dx,offset emread
	jmp	emsg
ewrite:	mov	dx,offset emwrite
	jmp	emsg
echeck:	mov	dx,offset emcheck
	jmp	emsg

open:	mov	[skipdsk],bl		; set skipdsk to 1 if /N
	mov	ax,DOS_HDL_OPENRW	; AH = 3Dh (OPEN FILE), AL = R/W
	int	21h
	jc	eopen
	xchg	bx,ax			; BX = file handle
;
; Let's get the boot sector length first; if it's only 512 bytes,
; then it's already been truncated, so all we want to do is write it
; to the boot drive.
;
	mov	ax,DOS_HDL_SEEKEND	; AH = 42h (SEEK), AL = 2 (FROM END)
	sub	cx,cx
	sub	dx,dx			; CX:DX == offset (zero)
	int	21h
	cmp	ax,512			; exactly 512?
	mov	dx,BOOT_SECTOR_LO	;
	jne	seek			; no
	sub	dx,dx			; yes, seek back to start

seek:	mov	ax,DOS_HDL_SEEKBEG	; AH = 42h (SEEK), AL = 0 (FROM START)
	int	21h
	mov	cx,514			; CX = number of bytes
	mov	dx,offset buffer	; DS:DX -> buffer
	mov	di,dx			; DS:DI -> buffer
	mov	word ptr [di+512],-1	; set guard word just past sector
	mov	ah,DOS_HDL_READ		; AH = 3Fh (READ FILE)
	int	21h
eread2:	jc	eread

	cmp	ax,512			; read at least 512 bytes?
	jb	echeck			; no
	cmp	[di+510],0AA55h		; correct signature?
	jne	echeck			; no
	mov	ax,0301h		; AH = 03h (WRITE SECTORS), AL = 1
	cmp	[skipdsk],al		; skip boot disk update?
	je	next			; yes
	push	bx
	mov	bx,dx			; ES:BX -> buffer
	mov	cx,0001h		; CH = CYL 0, CL = SEC 1
	sub	dx,dx			; DH = HEAD 0, DL = DRIVE 0
	int	13h			; write to diskette boot sector
	pop	bx
	jc	ewrite
	mov	[message],offset updated
next:	cmp	word ptr [di+512],-1	; anything past the signature?
	je	done			; no, assume we're done
;
; Read the 2nd half of the boot code into buffer + 512
;
	mov	ax,DOS_HDL_SEEKBEG	; AH = 42h (SEEK), AL = 0 (FROM START)
	mov	dx,offset DIR_SECTOR	;
	sub	cx,cx			; CX:DX = offset
	int	21h
	mov	cx,1024			; CX = number of bytes
	mov	dx,offset buffer + 512	; DS:DX -> buffer + 512
	mov	ah,DOS_HDL_READ		; AH = 3Fh (READ FILE)
	int	21h
	jc	eread2
	mov	di,dx			; DI -> buffer
	add	di,ax			; DI -> just past bytes read
	dec	di			; DI -> last byte read
	xchg	cx,ax			; CX = # bytes read
	mov	al,0
	std
	repe	scasb			; scan backward for 1st non-null
	cld
	jz	echk2			; must have been all nulls?
	add	di,3
	sub	di,dx
	xchg	ax,di			; AX = # of VALID bytes read
	cmp	ax,512			; 2nd half small enough?
	jb	trunc			; yes
echk2:	jmp	echeck			; no
;
; Before we close the original file (eg, BOOT1.COM), let's write the 1st half
; of the boot sector back to it, and then truncate it at 512 bytes.
;
trunc:	push	ax			; save # bytes to write
	mov	ax,DOS_HDL_SEEKBEG	; AH = 42h (SEEK), AL = 0 (FROM START)
	sub	cx,cx
	sub	dx,dx
	int	21h
	mov	dx,offset buffer
	mov	cx,512
	mov	ah,DOS_HDL_WRITE
	int	21h
	mov	ah,DOS_HDL_WRITE	; write zero bytes to truncate here
	sub	cx,cx
	int	21h
	mov	ah,DOS_HDL_CLOSE	; AH = 3Eh (CLOSE FILE)
	int	21h
	mov	[message],offset resized
	jmp	short create

ecreat:	mov	dx,offset emcreat
emsg:	mov	al,0FFh
	jmp	short msg

create:	mov	ah,DOS_HDL_CREATE
	sub	cx,cx
	mov	dx,bp			; DS:DX -> second filename
	int	21h
	pop	cx			; CX = number of bytes to write
	jc	ecreat
	xchg	bx,ax			; BX = handle
	mov	dx,offset buffer + 512	; DS:DX -> buffer + 512
	mov	ah,DOS_HDL_WRITE	; AH = 40h (WRITE FILE)
	int	21h
	jc	ecreat
	mov	ah,DOS_HDL_CLOSE	; AH = 3Eh (CLOSE FILE)
	int	21h

done:	mov	al,0			; exit with zero return code
	mov	dx,[message]

msg:	push	ax
	mov	ah,DOS_TTY_PRINT
	int	21h
	pop	ax
exit:	mov	ah,DOS_PSP_RETURN	; return to caller with exit code in AL
	int	21h
ENDPROC	main

fname1	db	"BOOT1.COM",0
fname2	db	"BOOT2.COM",0

emopen	db	"Unable to open boot file",13,10,'$'
emread	db	"Unable to read boot file",13,10,'$'
emcheck	db	"Boot sector check failure",13,10,'$'
emwrite	db	"Unable to write to boot sector",13,10,'$'
emcreat	db	"Unable to create second boot file",13,10,'$'

updated	db	"Boot sector on drive A: updated",13,10,'$'
resized	db	"Boot sector updated",13,10,'$'
nothing	db	"Boot sector unchanged",13,10,'$'

skipdsk	db	0			; non-zero to skip boot disk update

	even
message	dw	offset nothing

buffer	label	byte

CODE	ENDS

	end	main
