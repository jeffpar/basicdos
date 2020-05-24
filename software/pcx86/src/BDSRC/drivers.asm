;
; Initialize DPT_ACTIVE
;
init:	sub	ax,ax
	mov	di,offset DPT_ACTIVE	; ES:DI -> DPT_ACTIVE
	push	es
	push	di
	push	ds
	lds	si,ds:[INT_DPT*4]	; DS:SI -> original table (in ROM)
	ASSUME	DS:NOTHING
	mov	cx,size DPT
	rep	movsb
	pop	ds
	ASSUME	DS:BIOS
	mov	[DPT_ACTIVE].DP_SPECIFY1,0DFh	; change step rate to 6ms
	mov	[DPT_ACTIVE].DP_HEADSETTLE,0	; change head settle time to 0ms
	pop	ds:[INT_DPT*4]
	pop	ds:[INT_DPT*4+2]	; update INT_DPT vector
;
; Initialize BPB_ACTIVE, which we assume follows DPT_ACTIVE
;
	ASSERTEQ <offset DPT_ACTIVE + size DPT>,<offset BPB_ACTIVE>
	mov	si,offset mybpb
	mov	cl,size BPB
	push	di
	rep	movsb
	pop	si			; DS:SI -> BPB_ACTIVE
; ...
	mov	si,offset mybpb
	lea	di,[si].BPB_DRIVE
	sub	ax,ax
	stosb				; set BPB_DRIVE
	mov	al,[si].BPB_FATS	; AX = # FATs
	mul	[si].BPB_FATSECS	; DX:AX = BPB_FATS * BPB_FATSECS
	add	ax,[si].BPB_RESSECS	;
	stosw				; set BPB_LBAROOT
	mov	ax,size DIRENT		;
	mul	[si].BPB_DIRENTS	; DX:AX size of root dir in bytes
	add	ax,[si].BPB_SECBYTES	;
	dec	ax			; add SECBYTES-1
	div	[si].BPB_SECBYTES	; and then divide by SECBYTES
	add	ax,[si].BPB_LBAROOT	;
	stosw				; set BPB_LBADATA
