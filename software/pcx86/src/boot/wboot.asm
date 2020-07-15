;
; BASIC-DOS Boot Sector Updater
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	bios.inc

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
	cmp	al,' '
	je	m1
	cmp	al,0Dh
	je	open
	lea	dx,[si-1]		; DS:DX -> first filename
m2:	lodsb
	cmp	al,' '
	je	m3
	cmp	al,0Dh
	je	m3
	jmp	m2
m3:	mov	byte ptr [si-1],0	; null-terminate the first filename
	cmp	al,' '
	jne	open
m4:	lodsb
	cmp	al,' '
	je	m4
	cmp	al,0Dh
	je	open
	lea	bp,[si-1]		; DS:BP -> second filename
m5:	lodsb
	cmp	al,' '
	je	m6
	cmp	al,0Dh
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

open:	mov	ax,3D02h		; AH = 3Dh (OPEN FILE), AL = R/W
	int	21h
	jc	eopen
	xchg	bx,ax			; BX = file handle
	mov	ax,4200h		; AH = 42h (SEEK), AL = 0 (FROM START)
	mov	dx,BOOT_SECTOR_LO	;
	sub	cx,cx			; CX:DX == offset
	int	21h
	mov	cx,514			; CX = number of bytes
	mov	dx,offset buffer	; DS:DX -> buffer
	mov	ah,3Fh			; AH = 3Fh (READ FILE)
	int	21h
	jc	eread
	cmp	ax,512			; read at least 512 bytes?
	jb	echeck			; no
	mov	di,dx			; DS:DI -> buffer
	cmp	[di+510],0AA55h		; correct signature?
	jne	echeck			; no
	cmp	word ptr [di+512],0000h	; nothing past the signature?
	jne	echeck			; no
	push	bx
	mov	ax,0301h		; AH = 03h (WRITE SECTORS), AL = 1
	mov	bx,dx			; ES:BX -> buffer
	mov	cx,0001h		; CH = CYL 0, CL = SEC 1
	sub	dx,dx			; DH = HEAD 0, DL = DRIVE 0
	int	13h
	pop	bx
	jc	ewrite
	mov	ax,4200h		; AH = 42h (SEEK), AL = 0 (FROM START)
	mov	dx,offset DIR_SECTOR	;
	sub	cx,cx			; CX:DX = offset
	int	21h
	mov	cx,514			; CX = number of bytes
	mov	dx,offset buffer + 512	; DS:DX -> buffer + 512
	mov	ah,3Fh			; AH = 3Fh (READ FILE)
	int	21h
	jc	eread
	cmp	ax,512			; 2nd half small enough?
	ja	echeck			; no
	push	ax			; AX = number of bytes read
;
; Before we close the original file (BOOT.COM), let's write the 1st half of
; the boot sector back to it, and then truncate it at 512 bytes.
;
	mov	ax,4200h		; AH = 42h (SEEK), AL = 0 (FROM START)
	sub	cx,cx
	sub	dx,dx
	int	21h
	mov	dx,offset buffer
	mov	cx,512
	mov	ah,40h
	int	21h
	mov	ah,40h			; write zero bytes to truncate here
	sub	cx,cx
	int	21h
	mov	ah,3Eh			; AH = 3Eh (CLOSE FILE)
	int	21h
	jmp	short create

ecreat:	mov	dx,offset emcreat
emsg:	mov	al,0FFh
	jmp	short msg

create:	mov	ah,3Ch
	sub	cx,cx
	mov	dx,bp			; DS:DX -> second filename
	int	21h
	pop	cx			; CX = number of bytes to write
	jc	ecreat
	xchg	bx,ax			; BX = handle
	mov	dx,offset buffer + 512	; DS:DX -> buffer + 512
	mov	ah,40h			; AH = 40h (WRITE FILE)
	int	21h
	jc	ecreat
	mov	ah,3Eh			; AH = 3Eh (CLOSE FILE)
	int	21h
	mov	al,0			; exit with zero return code
	mov	dx,offset success

msg:	push	ax
	mov	ah,9
	int	21h
	pop	ax
exit:	mov	ah,4Ch			; exit with return code in AL
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
