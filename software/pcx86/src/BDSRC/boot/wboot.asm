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
; maximum will be written to a separate file (BOOT2.COM) for inclusion in the
; first boot file.
;
        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	dx,offset fname
	mov	si,80h			; check the command-line
	lodsb
	test	al,al
	jz	open			; open the default filename
	mov	bl,al
	mov	bh,0
	mov	byte ptr [si+bx],0	; null-terminate file name
	inc	si
	mov	dx,si			; DS:DX -> file name
open:	mov	ax,3D00h		; AH = 3Dh (OPEN FILE)
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
	mov	dx,offset buffer	; DS:DX -> buffer
	mov	ah,3Fh			; AH = 3Fh (READ FILE)
	int	21h
	jc	eread
	cmp	ax,512			; 2nd half small enough?
	ja	echeck			; no
	push	ax			; AX = number of bytes read
	mov	ah,3Eh			; AH = 3Eh (CLOSE FILE)
	int	21h
	mov	ah,3Ch
	sub	cx,cx
	mov	dx,offset fname2
	int	21h
	pop	cx			; CX = number of bytes to write
	jc	ecreat
	xchg	bx,ax			; BX = handle
	mov	dx,offset buffer	; DS:DX -> buffer
	mov	ah,40h			; AH = 40h (WRITE FILE)
	int	21h
	jc	ecreat
	mov	ah,3Eh			; AH = 3Eh (CLOSE FILE)
	int	21h
	mov	al,0			; exit with zero return code
	mov	dx,offset success
	jmp	short msg
eopen:	mov	dx,offset emopen
	jmp	short emsg
ecreat:	mov	dx,offset emcreat
	jmp	short emsg
ewrite:	mov	dx,offset emwrite
	jmp	short emsg
echeck:	mov	dx,offset emcheck
	jmp	short emsg
eread:	mov	dx,offset emread
emsg:	mov	al,0FFh
msg:	push	ax
	mov	ah,9
	int	21h
	pop	ax
exit:	mov	ah,4Ch			; exit with return code in AL
	int	21h
ENDPROC	main

fname	db	"BOOT\BOOT.COM",0
fname2	db	"BOOT\BOOT2.COM",0
emopen	db	"Unable to open BOOT.COM",13,10,'$'
emread	db	"Unable to read BOOT.COM",13,10,'$'
emcheck	db	"BOOT.COM check failure",13,10,'$'
emwrite	db	"Unable to write BOOT.COM to boot sector",13,10,'$'
emcreat	db	"Unable to create BOOT2.COM",13,10,'$'
success	db	"Boot sector on drive A: updated",13,10,'$'
buffer	db	514 dup (0)

CODE	ENDS

	end	main
