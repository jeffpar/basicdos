;
; Write BOOT.COM to the boot sector of the diskette in drive A.
;
; NOTE: The arguments to this program should be "WBOOT BOOT.COM A:",
; but we currently ignore any arguments and just assume the above.
;
	include	bios.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	100h

main	proc	near
	mov	ax,3D00h		; AH = 3Dh (OPEN FILE)
	mov	dx,offset fname		; DS:DX -> file name
	int	21h
	jc	eopen
	mov	bx,ax			; BX = file handle
	mov	ax,4200h		; AH = 42h (SEEK), AL = 0 (FROM START)
	mov	dx,BOOT_SECTOR_LO	;
	sub	cx,cx			; CX:DX == offset
	int	21h
	mov	cx,512			; CX = number of bytes
	mov	dx,offset buffer	; DS:DX -> buffer
	mov	ah,3Fh			; AH = 3Fh (READ FILE)
	int	21h
	jc	eread
	cmp	ax,510			; boot sector small enough?
	ja	esize
	mov	ah,3Eh			; AH = 3Eh (CLOSE FILE)
	int	21h
	mov	ax,0301h		; AH = 03h (WRITE SECTORS), AL = 1
	mov	cx,0001h		; CH = CYL 0, CL = SEC 1
	mov	bx,dx			; ES:BX -> buffer
	mov	word ptr [bx+510],0AA55h
	sub	dx,dx			; DH = HEAD 0, DL = DRIVE 0
	int	13h
	jnc	exit
	mov	dx,offset emwrite
	jmp	short msg
esize:	mov	dx,offset emsize
	jmp	short msg
eread:	mov	dx,offset emread
	jmp	short msg
eopen:	mov	dx,offset emopen
msg:	mov	ah,9
	int	21h
exit:	int	20h
main	endp

fname	db	"BOOT.COM",0
emopen	db	"Unable to open BOOT.COM",13,10,'$'
emread	db	"Unable to read BOOT.COM",13,10,'$'
emsize	db	"BOOT.COM is too large",13,10,'$'
emwrite	db	"Unable to write BOOT.COM to boot sector",13,10,'$'
buffer	db	512 dup (0)

CODE	ENDS

	end	main
