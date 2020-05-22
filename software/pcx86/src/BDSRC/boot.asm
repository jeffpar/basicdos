	include	bdio.inc		; BASIC-DOS low memory structures

BOOTORG	equ	7C00h

CODE    SEGMENT

	org	BOOTORG

        ASSUME  CS:CODE, DS:BIOS, ES:BIOS, SS:NOTHING
;
; Having the stack at 30:100h is weird, but OK, whatever.
;
	cld
	jmp	short start
mybpb:	BPB	<,512,1,1,2,64,320,PC160K,1,8,1,0>
start:
;
; Temporary development code: if no SHIFT key is down, boot from the hard disk;
; unfortunately, that means moving ourselves out of the way first.
;
	test	[KB_FLAG],LEFT_SHIFT OR RIGHT_SHIFT
	jnz	init
	mov	si,BOOTORG
	mov	cx,512
	mov	di,si
	sub	di,cx
	rep	movsb
	jmp	hdboot-512
hdboot:	mov	ax,0201h		; AH = 02h (READ), AL = 1 sector
	inc	cx			; CH = CYL 0, CL = SEC 1
	mov	dx,0080h		; DH = HEAD 0, DL = DRIVE 80h
	mov	bx,di			; ES:BX -> BOOTORG
	int	13h			; read it
	jc	init			; on error, pretend nothing happened
	jmp	bx			; jump to new boot sector
;
; Initialize DPT_COPY
;
init:	mov	di,offset DPT_COPY	; ES:DI -> DPT_COPY
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

CODE	ENDS

	end
