;
; BASIC-DOS Boot Sector Updater
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
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
; Writes BOOT.COM (or other file specified on the command-line) to the boot
; sector of the diskette in drive A.  Any portion that exceeds the 512-byte
; maximum will be written to a second file (eg, BOOT2.COM) for inclusion in the
; first boot file.
;
        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	dx,offset fname
	mov	bp,offset fname2

	mov	si,80h			; check the command-line
	lodsb
	test	al,al
	jz	open			; open the default filename
m1:	lodsb
	cmp	al,CHR_SPACE
	je	m1
	cmp	al,CHR_RETURN
	je	open
	lea	dx,[si-1]		; DS:DX -> first filename
m2:	lodsb
	cmp	al,CHR_SPACE
	je	m3
	cmp	al,CHR_RETURN
	je	m3
	jmp	m2
m3:	mov	byte ptr [si-1],0	; null-terminate the first filename
	cmp	al,CHR_SPACE
	jne	open
m4:	lodsb
	cmp	al,CHR_SPACE
	je	m4
	cmp	al,CHR_RETURN
	je	open
	lea	bp,[si-1]		; DS:BP -> second filename
m5:	lodsb
	cmp	al,CHR_SPACE
	je	m6
	cmp	al,CHR_RETURN
	jne	m5
m6:	mov	byte ptr [si-1],0	; null-terminate the second filename
	jmp	short open

eopen:	mov	dx,offset emopen
	jmp	emsg
eread:	mov	dx,offset emread
	jmp	emsg
ewrite:	mov	dx,offset emwrite
	jmp	emsg
echeck:	mov	dx,offset emcheck
	jmp	emsg

open:	mov	ax,DOS_HDL_OPENRW	; AH = 3Dh (OPEN FILE), AL = R/W
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
	push	bx
	mov	ax,0301h		; AH = 03h (WRITE SECTORS), AL = 1
	mov	bx,dx			; ES:BX -> buffer
	mov	cx,0001h		; CH = CYL 0, CL = SEC 1
	sub	dx,dx			; DH = HEAD 0, DL = DRIVE 0
	int	13h
	pop	bx
	jc	ewrite
	cmp	word ptr [di+512],-1	; anything past the signature?
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
; Before we close the original file (BOOT.COM), let's write the 1st half of
; the boot sector back to it, and then truncate it at 512 bytes.
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
	mov	dx,offset success

msg:	push	ax
	mov	ah,DOS_TTY_PRINT
	int	21h
	pop	ax
exit:	mov	ah,DOS_PSP_EXIT		; exit with return code in AL
	int	21h
ENDPROC	main

fname	db	"BOOT.COM",0
fname2	db	"BOOT2.COM",0
emopen	db	"Unable to open BOOT.COM",13,10,'$'
emread	db	"Unable to read BOOT.COM",13,10,'$'
emcheck	db	"BOOT.COM check failure",13,10,'$'
emwrite	db	"Unable to write BOOT.COM to boot sector",13,10,'$'
emcreat	db	"Unable to create BOOT2.COM",13,10,'$'
success	db	"Boot sector on drive A: updated",13,10,'$'
buffer	label	byte

CODE	ENDS

	end	main
