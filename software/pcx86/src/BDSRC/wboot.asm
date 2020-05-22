;
; Write BOOT.COM to the boot sector of the diskette in drive A.
;
; NOTE: The arguments to this program should be "WBOOT BOOT.COM A:",
; but we currently ignore any arguments and just assume the above.
;
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
	mov	dx,7C00h		;
	sub	cx,cx			; CX:DX == offset
	int	21h
	mov	cx,512			; CX = number of bytes
	mov	dx,offset buffer	; DS:DX -> buffer
	mov	ah,3Fh			; AH = 3Fh (READ FILE)
	int	21h
	jc	eread
	mov	ah,3Eh			; AH = 3Eh (CLOSE FILE)
	int	21h
	mov	ax,0301h		; AH = 03h (WRITE SECTORS), AL = 1
	mov	cx,0001h		; CH = CYL 0, CL = SEC 1
	mov	bx,dx			; ES:BX -> buffer
	sub	dx,dx			; DH = HEAD 0, DL = DRIVE 0
	int	13h
	jnc	exit
	mov	dx,offset mwrite
	jmp	short msg
eread:	mov	dx,offset mread
	jmp	short msg
eopen:	mov	dx,offset mopen
msg:	mov	ah,9
	int	21h
exit:	int	20h
main	endp

fname	db	"BOOT.COM",0
mopen	db	"Unable to open BOOT.COM",13,10,'$'
mread	db	"Unable to read BOOT.COM",13,10,'$'
mwrite	db	"Unable to write BOOT.COM to boot sector",13,10,'$'
buffer	db	512 DUP (?)

CODE	ENDS

	end	main

