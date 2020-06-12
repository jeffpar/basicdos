;
; BASIC-DOS Logical (CON) I/O Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	CON
CON	DDH	<offset DEV:ddcon_end+16,,DDATTR_STDIN+DDATTR_STDOUT+DDATTR_OPEN+DDATTR_CHAR,offset ddcon_init,-1,20202020204E4F43h>

	DEFLBL	CMDTBL,word
	dw	ddcon_none,  ddcon_none, ddcon_none,  ddcon_none	; 0-3
	dw	ddcon_none,  ddcon_none, ddcon_none,  ddcon_none	; 4-7
	dw	ddcon_write, ddcon_none, ddcon_none,  ddcon_none	; 8-11
	dw	ddcon_none,  ddcon_open, ddcon_close			; 12-14
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFLBL	CON_LIMITS,word
	dw	16,80,  4,25	; mirrors sysinit's default CFG_CONSOLE
	dw	 0,79,  0,24

	DEFWORD	ct_head,0	; head of context chain
	DEFWORD	ct_focus,0	; segment of context with focus
	DEFWORD	frame_seg,0
	DEFBYTE	max_rows,25	; TODO: use this for something!
	DEFBYTE	max_cols,80	; TODO: set to correct value in ddcon_init
;
; A context of "25,80,0,0" with a border results in an effective WIDTH,HEIGHT
; of 78,23.  Logical cursor positions will be allowed from 0,0 to 77,22.
; Physical character and cursor positions will be adjusted by the offset address
; in CT_BUFFER.
;
CONTEXT		struc
CT_NEXT		dw	?	; 00h: segment of next context, 0 if end
CT_CONW		db	?	; 02h: eg, context width (eg, 80 cols)
CT_CONH		db	?	; 03h: eg, context height (eg, 25 rows)
CT_CONX		db	?	; 04h: eg, content X of top left (eg, 0)
CT_CONY		db	?	; 05h: eg, content Y of top left (eg, 0)
CT_CURX		db	?	; 06h: eg, cursor X within context (eg, 1)
CT_CURY		db	?	; 07h: eg, cursor Y within context (eg, 1)
CT_MAXX		db	?	; 08h; eg, maximum X within context (eg, 79)
CT_MAXY		db	?	; 09h: eg, maximum Y within context (eg, 24)
CT_PORT		dw	?	; 0Ah: eg, 3D4h
CT_BUFFER	dd	?	; 0Ch: eg, 0B800h:00A2h
CONTEXT		ends

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_req,far
	push	ax
	push	bx
	push	cx
	push	dx
	push	bp
	push	si
	push	di
	push	ds
	mov	di,bx			; ES:DI -> DDP
	mov	bl,es:[di].DDP_CMD
	cmp	bl,CMDTBL_SIZE
	jae	ddq9
	push	cs
	pop	ds
	ASSUME	DS:CODE
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
ddq8:	pop	ds
	pop	di
	pop	si
	pop	bp
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ddq9:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	jmp	ddq8
ENDPROC	ddcon_req

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_write
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_write
	mov	cx,es:[di].DDPRW_LENGTH
	jcxz	dcw9
	lds	si,es:[di].DDPRW_ADDR
	mov	dx,es:[di].DDP_CONTEXT
	test	dx,dx
	jnz	dcw2
dcw1:	lodsb
	call	ddcon_writechar
	loop	dcw1
	jmp	short dcw9
dcw2:	push	es
	mov	es,dx
dcw3:	lodsb
	call	ddcon_writecontext
	loop	dcw3
	pop	es
dcw9:	ret
ENDPROC	ddcon_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_open
;
; Inputs:
;	ES:DI -> DDP
;	[DDP].DDP_PARMS -> context descriptor (eg, "CON:25,80,0,0")
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_open
	push	di
	push	es

	push	ds
	lds	si,es:[di].DDP_PARMS
	ASSUME	DS:NOTHING
	add	si,4			; DS:SI -> parms
	push	cs
	pop	es
	mov	di,offset CON_LIMITS	; ES:DI -> limits
	mov	ax,DOS_UTIL_ATOI
	int	21h			; updates SI, DI, and AX
	mov	cl,al			; CL = cols
	mov	ax,DOS_UTIL_ATOI
	int	21h
	mov	ch,al			; CH = rows
	mov	ax,DOS_UTIL_ATOI
	int	21h
	mov	dl,al			; DL = starting col
	mov	ax,DOS_UTIL_ATOI
	int	21h
	mov	dh,al			; DH = starting row
	pop	ds
	ASSUME	DS:CODE

	mov	bx,(size context + 15) SHR 4
	mov	ah,DOS_MEM_ALLOC
	int	INT_DOSFUNC
	jnc	dco1
	jmp	dco7

dco1:	mov	ds,ax
	ASSUME	DS:NOTHING

	cmp	[ct_focus],0
	jne	dco1a
	mov	[ct_focus],ax
dco1a:	xchg	[ct_head],ax
	mov	ds:[CT_NEXT],ax
;
; Set context screen size (CONW,CONH) and position (CONX,CONY) based on
; (CL,CH) and (DL,DH), and then set context cursor maximums (MAXX,MAXY) from
; the context size.
;
	mov	word ptr ds:[CT_CONW],cx; set CT_CONW (CL) and CT_CONH (CH)
	mov	word ptr ds:[CT_CONX],dx; set CT_CONX (DL) and CT_CONY (DH)
	sub	cx,0101h
	mov	word ptr ds:[CT_MAXX],cx; set CT_MAXX (CL) and CT_MAXY (CH)
	mov	al,dh
	mul	[max_cols]
	add	ax,ax
	mov	dh,0
	add	dx,dx
	add	ax,dx
	mov	ds:[CT_BUFFER].off,ax
	mov	ax,[frame_seg]
	mov	ds:[CT_BUFFER].seg,ax
	sub	ax,ax
	mov	es,ax
	ASSUME	ES:BIOS
	mov	ax,[CURSOR_POSN]
	mov	word ptr ds:[CT_CURX],ax; set CT_CURX (AL) and CT_CURY (AH)
;
; TODO: Verify that the CURX and CURY positions we're importing are valid for
; this context.
;
	mov	ax,[ADDR_6845]
	mov	ds:[CT_PORT],ax
;
; OK, so if this context is supposed to have a border, draw all 4 sides now.
;
	sub	dx,dx			; eg, get top left X (DL), Y (DH)
	mov	bx,word ptr ds:[CT_MAXX]; eg, get bottom right X (BL), Y (BH)
	mov	cx,0C9BBh
	call	ddcon_writevertpair
	ASSUME	ES:NOTHING
	mov	cx,0BABAh
dco2:	inc	dh			; advance Y, holding X constant
	cmp	dh,bh
	jae	dco3
	call	ddcon_writevertpair
	jmp	dco2
dco3:	mov	cx,0C8BCh
	call	ddcon_writevertpair
	mov	cx,0CDCDh
dco4:	mov	dh,0
	inc	dx			; advance X, holding Y constant
	cmp	dl,bl
	jae	dco6
	call	ddcon_writehorzpair
	jmp	dco4

dco6:	mov	al,0
	call	ddcon_scroll		; clear the interior
	clc

dco7:	pop	es
	pop	di			; ES:DI -> DDP again
	jc	dco8
	mov	es:[di].DDP_CONTEXT,ds
	jmp	short dco9
;
; What's up with the complete disconnect between device driver error codes
; and DOS error codes?
;
dco8:	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_GENFAIL
dco9:	ret
ENDPROC	ddcon_open

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_writehorzpair
;
; Inputs:
;	CH = top char
;	CL = bottom char
;	DL,DH = top X,Y
;	BL,BH = bottom X,Y
;	DS -> CONSOLE context
;
; Modifies:
;	DI, ES
;
DEFPROC	ddcon_writehorzpair
	mov	di,ds
	cmp	di,[ct_focus]
	jne	whp1
	cmp	dl,14			; skip over 14 chars at the top
	jbe	whp2
whp1:	xchg	cl,ch
	call	ddcon_writecurpos
	xchg	cl,ch
whp2:	xchg	dh,bh
	call	ddcon_writecurpos
	xchg	dh,bh
	ret
ENDPROC	ddcon_writehorzpair

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_writevertpair
;
; Inputs:
;	CH = left char
;	CL = right char
;	DL,DH = left X,Y
;	BL,BH = right X,Y
;	DS -> CONSOLE context
;
; Modifies:
;	DI, ES
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_writevertpair
	xchg	cl,ch
	call	ddcon_writecurpos
	xchg	dl,bl
	xchg	cl,ch
	call	ddcon_writecurpos
	xchg	dl,bl
	ret
ENDPROC	ddcon_writevertpair

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_close
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_close
	mov	ax,es:[di].DDP_CONTEXT
	test	ax,ax
	jz	dcc9			; no context
	cmp	[ct_focus],ax
	jne	dcc0
	mov	[ct_focus],0
;
; Remove the context from our chain
;
dcc0:	int 3
	push	es
	push	ds
	mov	bx,offset ct_head	; DS:BX -> 1st context
dcc1:	mov	cx,[bx].CT_NEXT
	ASSERTNZ <test cx,cx>
	jcxz	dcc2			; context not found
	cmp	cx,ax
	je	dcc2
	mov	ds,cx
	ASSUME	DS:NOTHING
	sub	bx,bx			; DS:BX -> next context
	jmp	dcc1			; keep looking
dcc2:	mov	es,ax
	mov	cx,es:[CT_NEXT]		; move this context's CT_NEXT
	mov	[bx].CT_NEXT,cx		; to the previous context's CT_NEXT
	pop	ds
	ASSUME	DS:CODE
;
; We are now free to free the context segment in ES
;
dcc3:	mov	ah,DOS_MEM_FREE
	int	INT_DOSFUNC
	pop	es
dcc9:	ret
ENDPROC	ddcon_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_none (handler for unimplemented functions)
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;
	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_none
	stc
	ret
ENDPROC	ddcon_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_int29 (handler for INT_FASTCON: fast console I/O)
;
; Inputs:
;	AL = character to display
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_int29,far
	push	dx
	mov	dx,[ct_focus]		; for now, use the context with focus
	test	dx,dx
	jnz	dci1
	call	ddcon_writechar
	jmp	short dci9
dci1:	push	es
	mov	es,dx
	call	ddcon_writecontext
	pop	es
dci9:	pop	dx
	iret
ENDPROC	ddcon_int29

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_writechar
;
; Inputs:
;	AL = character to display
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_writechar
	push	ax
	push	bx
	mov	ah,VIDEO_TTYOUT
	mov	bh,0
	int	INT_VIDEO
	pop	bx
	pop	ax
	ret
ENDPROC	ddcon_writechar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_writecontext
;
; Inputs:
;	AL = character
;	ES -> CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	None
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_writecontext
	push	ax
	push	bx
	push	cx
	push	dx
	push	ds
	push	es
	push	es
	pop	ds			; DS is now the context
;
; Check for special characters that we don't actually have to write...
;
	xchg	cx,ax			; CL = char
	mov	dx,word ptr ds:[CT_CURX]
	cmp	cl,0Dh			; return?
	jne	wc0
	mov	dl,1			; emulate a RETURN (CURX = 1)
	jmp	wc3
wc0:	cmp	cl,0Ah
	je	wclf			; emulate a LINEFEED

	call	ddcon_writecurpos	; write CL at (DL,DH)
;
; Load CURX,CURY into DX, advance it, update it, and then update the cursor
; IFF this context currently has focus.
;
	mov	dx,word ptr ds:[CT_CURX]
	inc	dx
	cmp	dl,ds:[CT_MAXX]
	jb	wc3
	mov	dl,1
wclf:	inc	dh
	cmp	dh,ds:[CT_MAXY]
	jb	wc3
	dec	dh
	mov	al,1
	call	ddcon_scroll		; scroll up 1 line

wc3:	mov	word ptr ds:[CT_CURX],dx
	mov	ax,ds
	cmp	ax,[ct_focus]		; does this context have focus?
	jne	wc9			; no, leave cursor alone
	call	ddcon_getcurpos		; BX = screen offset for CURX,CURY
	shr	bx,1			; screen offset to cell offset
	mov	ah,14			; AH = 6845 CURSOR ADDR (HI) register
	call	ddcon_writeport		; update cursor position using BX

wc9:	pop	es
	pop	ds
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	ddcon_writecontext

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_getcurpos
;
; Inputs:
;	DX = CURX (DL), CURY (DH)
;
; Outputs:
;	BX -> screen buffer offset
;
; Modifies:
;	AX, BX
;
DEFPROC	ddcon_getcurpos
	mov	al,dh
	mul	[max_cols]
	add	ax,ax			; AX = offset to row
	sub	bx,bx
	mov	bl,dl
	add	bx,bx
	add	bx,ax			; BX = offset to row and col
	ret
ENDPROC	ddcon_getcurpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_scroll
;
; Inputs:
;	AL = # lines (0 to clear ALL lines)
;	DS -> CONSOLE context
;
; Modifies:
;	AX, BX, CX
;
DEFPROC	ddcon_scroll
;
; We use INT 10h to do this, for now....
;
	push	dx
	push	bp			; WARNING: INT 10h scrolls trash BP
	mov	cx,word ptr ds:[CT_CONX]; CH = row, CL = col of upper left
	mov	dx,cx
	add	cx,0101h
	add	dx,word ptr ds:[CT_MAXX]; DH = row, DL = col of lower right
	sub	dx,0101h
	mov	bh,07h			; BH = fill attribute
	mov	ah,06h			; scroll up # lines in AL
	int	10h
	pop	bp
	pop	dx
	ret
ENDPROC	ddcon_scroll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_writecurpos
;
; Inputs:
;	CL = character
;	DX = CURX (DL), CURY (DH)
;	DS -> CONSOLE context
;
; Outputs:
;	None
;
; Modifies:
;	AL, DI, ES
;
DEFPROC	ddcon_writecurpos
	push	bx
	push	dx
	les	di,ds:[CT_BUFFER]	; ES:DI -> the frame buffer
	call	ddcon_getcurpos		; BX = screen offset for CURX,CURY
	mov	dx,ds:[CT_PORT]
	add	dl,6			; DX = status port
wc1:	in	al,dx
	test	al,01h
	jnz	wc1			; loop until we're OUTSIDE horz retrace
	cli
wc2:	in	al,dx
	test	al,01h
	jz	wc2			; loop until we're INSIDE horz retrace
	mov	es:[di+bx],cl		; "write" the character
	sti
	pop	dx
	pop	bx
	ret
ENDPROC	ddcon_writecurpos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcon_writeport
;
; Inputs:
;	AH = 6845 register #
;	BX = 16-bit value to write
;
; Outputs:
;	None
;
; Modifies:
;	AL, DX
;
DEFPROC	ddcon_writeport
	mov	dx,ds:[CT_PORT]
	mov	al,ah
	out	dx,al			; select 6845 register
	inc	dx
	mov	al,bh
	out	dx,al			; output BH
	dec	dx
	mov	al,ah
	inc	ax
	out	dx,al			; select 6845 register + 1
	inc	dx
	mov	al,bl
	out	dx,al			; output BL
	dec	dx
	ret
ENDPROC	ddcon_writeport

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_END updated
;
	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING
DEFPROC	ddcon_init,far
	push	ax
	push	dx
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS

	mov	ax,[EQUIP_FLAG]		; AX = EQUIP_FLAG
	mov	es:[bx].DDPI_END.off,offset ddcon_init
	mov	cs:[0].DDH_REQUEST,offset DEV:ddcon_req
;
; Determine what kind of video console we're dealing with (MONO or COLOR)
; and what the frame buffer segment is.
;
	mov	dx,0B000h
	and	ax,EQ_VIDEO_MODE
	cmp	ax,EQ_VIDEO_MONO
	je	ddi1
	mov	dx,0B800h
ddi1:	mov	[frame_seg],dx
;
; Install an INT 29h ("FAST PUTCHAR") handler; I think traditionally DOS
; installed its own handler, but that's really our responsibility, especially
; since we eventually want all INT 29h I/O to go through our system console.
;
	mov	ds:[INT_FASTCON * 4].off,offset ddcon_int29
	mov	ds:[INT_FASTCON * 4].seg,cs

	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	ax
	ret
ENDPROC	ddcon_init

CODE	ends

DATA	segment para public 'DATA'

ddcon_end	db	16 dup(0)

DATA	ends

	end
