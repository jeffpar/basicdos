	include	bdio.inc		; BASIC-DOS low memory structures

BOOTORG	equ	7C00h

CODE    segment

	org	BOOTORG
	;
	; Having the stack at 30:100h is weird, but OK, whatever.
	;
        ASSUME	CS:CODE, DS:BIOS, ES:BIOS, SS:NOTHING

boot	proc	near
	cld
	jmp	short start
mybpb:	BPB	<,512,1,1,2,64,320,MEDIA_160K,1,8,1,0>

start:	mov	si,offset product
	call	print
	cmp	mybpb.BPB_MEDIA,MEDIA_HARD
	je	init			; we're a hard disk, so just boot
	mov	ah,DISK_GETPARMS	; get hard drive parameters
	mov	dl,80h
	int	INT_DISK		;
	jc	init			; failed (could be an original PC)
	test	dl,dl			; any hard drives?
	jz	init			; no
	mov	si,offset prompt
	call	print
	mov	ax,2 * PCJS_MULTIPLIER	; AX = 2 seconds
	call	wait			; wait for key
	test	al,al			; was a key pressed in time?
	jnz	init			; yes
mvboot:	mov	si,BOOTORG		; move this boot sector down
	mov	cx,512			;  so that we can read hard disk
	mov	di,si			;  boot sector into the same memory
	sub	di,cx
	rep	movsb
	jmp	hdboot-512		; jump to the moved copy
hdboot:	mov	ax,0201h		; AH = 02h (READ), AL = 1 sector
	inc	cx			; CH = CYL 0, CL = SEC 1
	mov	dx,0080h		; DH = HEAD 0, DL = DRIVE 80h
	mov	bx,di			; ES:BX -> BOOTORG
	int	13h			; read it
	jc	hderr
	jmp	bx			; jump to the hard disk boot sector
hderr:	mov	si,offset hderrmsg
	call	print			; fall into normal diskette boot
;
; Initialize DPT_COPY
;
init:	int 3
	mov	di,offset DPT_COPY	; ES:DI -> DPT_COPY
	push	di
	push	ds
	lds	si,ds:[INT_DPT*4]	; DS:SI -> original table (in ROM)
	ASSUME	DS:NOTHING
	mov	cx,size DPT
	rep	movsb
	pop	ds
	ASSUME	DS:BIOS
;
; Initialize BPB_COPY, which we assume follows DPT_COPY
;
	ASSERTEQ <offset DPT_COPY + size DPT>,<offset BPB_COPY>
	mov	si,offset mybpb
	mov	cl,size BPB
	rep	movsb
;
; Patch DPT_COPY and update the INT_DPT vector
;
	pop	di
	mov	es:[di].DP_SPECIFY1,0DFh; change step rate to 6ms
	mov	es:[di].DP_HEADSETTLE,0	; change head settle time to 0ms
	mov	ds:[INT_DPT*4],di
	mov	ds:[INT_DPT*4+2],es	; update INT_DPT vector
;
; To read IBMBIO.COM, we need to find its DIRENT and get the starting cluster.
;
loop:	jmp	loop

boot	endp

;;;;;;;;
;
; Print the null-terminated string at DS:SI
;
; Returns: nothing
; Modifies: AX
;
print	proc	near
	push	bx
	jmp	short pr2
pr1:	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
pr2:	lodsb
	test	al,al
	jnz	pr1
	pop	bx
	ret
print	endp

;;;;;;;;
;
; Wait the number of seconds in AX, or until a key is pressed.
;
; Returns: AL = key pressed (char code), 0 if none
; Modifies: AX, CX, DX
;
wait	proc	near
	mov	dx,182
	mul	dx			; DX:AX = ticks to wait * 10
	mov	cx,10
	div	cx
	push	ax			; AX is corrected ticks to wait
	mov	ah,TIME_GETTICKS
	int	INT_TIME		; get intial tick count in CX:DX
	pop	ax
	add	ax,dx
	mov	dx,cx
	adc	dx,0			; DX:AX is target tick count
w1:	push	dx
	push	ax
	mov	ah,KBD_CHECK
	int	INT_KBD
	jz	w2
	pop	ax
	pop	dx
	mov	si,offset crlf
	call	print
	mov	ah,KBD_READ
	int	INT_KBD
	jmp	short w9
w2:	mov	ah,TIME_GETTICKS
	int	INT_TIME		; get updated tick count in CX:DX
	pop	ax			; subtract the DX:AX value on the stack
	sub	dx,ax
	pop	dx
	sbb	cx,dx			; as long as the stack value is bigger
	jb	w1			; carry will be set; keep looping
	mov	al,0			; no key was pressed in time
w9:	ret
wait	endp

;
; Messages
;
product		db	"BASIC-DOS 1.00"
crlf		db	13,10,0
prompt		db	"Press any key to boot from diskette...",0
hderrmsg	db	"Hard disk read error",13,10,0

CODE	ends

	end
