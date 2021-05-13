;
; Reversed-engineered OEM.ASM, courtesy of Michal Necasek 2020-07-13
;
DSEG    SEGMENT PUBLIC 'DATASG'

; Defined elsewhere
EXTRN   CSAVEA:WORD,CSAVEM:WORD

; Data defined by the OEM module

OVMODE  db      0       ; Old video mode
CBKINT  dw      offset  CTLBRK
CBRKSG  dw      0
        dw      offset  TIMISR
TIMRSG  dw      0
CVPAGE  db      0       ; Currently selected video page
var_63a db      0
var_63b db      80      ; Screen width in columns (40/80)
var_63c db      0
VISVPG  db      0       ; Currently visible video page
var_63e db      0       ; Initial/saved number of columns
CVMODE  db      0       ; Currently set video mode
var_640 db      0
var_641 db      0
var_642 db      0
var_643 dw      0707h   ; Cursor shape
var_645 db      7       ; Saved text attributes
var_646 db      7       ; Current text attributes
var_647 dw      0       ; Current video memory offset
var_649 dw      0       ; Screen width in pixels?
var_64b db      0       ; Current character column?
var_64c db      0
var_64d db      0
var_64e dw      0
var_650 db      0
        db      0
var_652 db      6
        db      5
        db      1
var_655 db      6
        db      10
        db      1
        db      0       ; Likely unused
        db      0
        db      0
        db      0
        db      0
        db      0
        db      0
        db      0
var_660 db      3
var_661 dw      0       ; Current offset into screen?
var_663 dw      0       ; Some other offset?
var_665 db      0
var_666 db      0
var_667 dw      0       ; Function pointer
var_669 db      0

DSEG    ENDS

CSEG	SEGMENT PUBLIC 'CODESG'
	ASSUME  CS:CSEG

; GW-BASIC routines that OEM code calls into.

EXTRN   KYBCLR:NEAR
EXTRN   SCNCLR:NEAR
EXTRN   SCNSWI:NEAR
EXTRN   GRPINI:NEAR

EXTRN   SPCTAB:NEAR
EXTRN   SNERR:NEAR

PUBLIC  SEGINI, GETHED, PRTMAP, GETFBC, SETFBC, GRPSIZ, POKFLT, PEKFLT

; =============== S U B	R O U T	I N E =======================================


SEGINI		proc near
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		mov	ax, cs
		mov	ds:6Eh,	ax	; Adjust segment for vector 1Bh
		mov	ds:72h,	ax	; Adjust segment for vector 1Ch
		mov	ds:92h,	ax	; Adjust segment for vector 24h
		mov	ax, es
		mov	ds:510h, ax	; Stash	away BASIC data	segment
		pop	ds
		assume ds:nothing
		ret
SEGINI		endp

; ---------------------------------------------------------------------------
OEMHED		db 0Dh,0Ah
		db 'Microsoft BASIC',0Dh,0Ah
;		db 'OEM.ASM by OS/2 Museum, July 2020',0Dh,0Ah
		db 'https://github.com/microsoft/GW-BASIC'
                db 0

; =============== S U B	R O U T	I N E =======================================


GETHED		proc near
		cmp	al, al
		mov	bx, offset OEMHED
		ret
GETHED		endp


; =============== S U B	R O U T	I N E =======================================

; Map print function/output character codes

PRTMAP		proc near
		cmp	al, 0FFh
		jnz	short loc_5044
		cmp	byte ptr ds:var_63a, 0
		jz	short BADMAP
		mov	al, ' '
loc_5044:
		cmp	al, 7		; BEL
		jz	short BADMAP
		cmp	al, ' '
		jnb	short loc_506E
		cmp	al, 9
		jb	short loc_506E
		jz	short loc_5073
		cmp	al, 0Eh
		jb	short BADMAP
		cmp	al, 1Ch
		jb	short loc_506E
BADMAP:
		mov	ah, 0FFh
		or	al, al
		stc
		ret
; ---------------------------------------------------------------------------

loc_5060:
		mov	al, ' '
		cmp	byte ptr ds:var_63a, 0
		jnz	short loc_506E
		or	al, al
		mov	al, 0
		ret
; ---------------------------------------------------------------------------

loc_506E:
		or	al, al
		jz	short loc_5060
		ret
; ---------------------------------------------------------------------------

loc_5073:
		mov	al, 0Fh
		jmp	short BADMAP
PRTMAP		endp


; =============== S U B	R O U T	I N E =======================================

; Get foreground/background colors
; On entry:
;   CF set  : Graphics
;   CF clear: Text mode

GETFBC		proc near
		jb	short TXTATR
		mov	al, ds:var_646
		mov	bl, al
		shr	bl, 1
		shr	bl, 1
		shr	bl, 1
		shr	bl, 1
		and	ax, 8Fh
		and	bx, 7
		ret
; ---------------------------------------------------------------------------

TXTATR:
		xor	ax, ax
		mov	bx, ax
		mov	al, 3
		ret
GETFBC		endp

; ---------------------------------------------------------------------------
byte_5095	db 0

; =============== S U B	R O U T	I N E =======================================

; Set foreground/background colors

SETFBC		proc near
		push	ax
		push	bx
		cmp	byte ptr ds:var_63a, 0
		jnz	short loc_50CE
		shl	bl, 1
		shl	bl, 1
		shl	bl, 1
		shl	bl, 1
		or	al, bl
		cmp	cs:byte_5095, 0
		mov	cs:byte_5095, 0
		mov	al, ds:var_645
		jnz	short loc_50CB
		mov	cs:byte_5095, 1
		mov	al, 70h	; 'p'
		cmp	byte ptr ds:var_645, 7
		jz	short loc_50CB
		mov	al, 7
loc_50CB:
		mov	ds:var_646, al
loc_50CE:
		pop	bx
		pop	ax
		ret
SETFBC		endp

; ---------------------------------------------------------------------------
		mov	cl, ds:var_63b
		mov	ch, 0
		mov	dx, 25
		ret

; =============== S U B	R O U T	I N E =======================================

; Get screen pixel dimensions

GRPSIZ		proc near
		mov	cx, ds:var_649
		or	cx, cx
		jz	short HEIGHT
		dec	cx		; Decrement unless zero
HEIGHT:
		mov	dx, 199
		ret
GRPSIZ		endp

; ---------------------------------------------------------------------------
PEKPOK		db 0                    ; Is it	a PEEK (0) or POKE (255)?
word_50E9	dw 2Eh
		dw 2Fh
		dw 347h
		dw 348h
		dw 30h
		dw 31h
		dw 358h
		dw 359h
		dw 4Eh
		dw 2Ch
		dw 2Dh
		dw 6Ah
off_5101	dw offset loc_5192
		dw 153h
		dw 152h
		dw 646h         ; var_646 ???
		dw 48Fh
		dw 48Eh
		dw 157h
		dw 156h
		dw 47Eh
		dw 47Dh
		dw 155h
		dw 154h

; =============== S U B	R O U T	I N E =======================================

; Filter PEEKs for "special" addresses

PEKFLT		proc near
		push	ax
		push	cx
		push	bx
		push	dx
		mov	dx, bx
		mov	cs:PEKPOK, 0	; It's a peek
		jmp	short DOPFLT
PEKFLT		endp


; =============== S U B	R O U T	I N E =======================================

; Filter POKEs for "special" addresses
; On entry: Address in ES:DX
; On exit : ZF clear if	poke should be done

POKFLT		proc near
		push	ax
		push	cx
		push	bx
		push	dx
		mov	cs:PEKPOK, -1	; It's a poke
DOPFLT:
		push	di
		push	es
		cld
		mov	ax, ds
		mov	cx, es
		cmp	cx, ax		; Is it	the BASIC data segment?
		jz	short BASDAT
		cmp	cx, 0		; Zero segment?
		jnz	short PFLTX
		cmp	dx, 41Ah	; Is it	the pointer into the keyboard buffer?
		jnz	short PFLTX
		cmp	cs:PEKPOK, -1	; Is it	a POKE?
		jnz	short PFLTX
		call	KYBCLR
		jmp	short PFLTX
; ---------------------------------------------------------------------------

BASDAT:
		mov	di, offset word_50E9
		mov	ax, dx
		mov	cx, 18h
		shr	cx, 1
		push	cs
		pop	es
		assume es:CSEG
		repne scasw
		jnz	short PFLTX
		shl	cx, 1
		mov	bx, offset off_5101
		add	bx, cx
		mov	ax, cs:[bx]
		pop	es
		assume es:nothing
		pop	di
		pop	dx
		pop	bx
		cmp	cx, 2
		jb	short loc_518F
		cmp	cs:PEKPOK, 0	; Is it	a PEEK?
		jz	short loc_5187
		mov	dx, ax
		or	ax, 0FFFFh
		pop	cx
		pop	ax
		ret
; ---------------------------------------------------------------------------

loc_5187:
		mov	bx, ax
		or	ax, 0FFFFh
		pop	cx
		pop	ax
		ret
; ---------------------------------------------------------------------------

loc_518F:
		pop	cx
		jmp	ax
; ---------------------------------------------------------------------------

loc_5192:
		xor	ax, ax
		pop	ax
		ret
; ---------------------------------------------------------------------------

PFLTX:
		pop	es
		pop	di
		pop	dx
		pop	bx
		pop	cx
		pop	ax
		ret
POKFLT		endp

; ---------------------------------------------------------------------------
; Start of another module?
;		align 4

PUBLIC  SETCBF, INICOM, RECCOM, SNDCOM, STACOM, TRMCOM, SNDLPT

BAUDTB  	dw 9600
		dw 4800
		dw 2400
		dw 1800
		dw 1200
		dw 600
		dw 300
		dw 150
		dw 110
		dw 75
		dw 12
		dw 24
		dw 48
		dw 64
		dw 96
		dw 192
		dw 384
		dw 768
		dw 1047
		dw 1536
masks?		db 8
		db 18h
		db 28h
		db 38h
COMTBL		dw offset CM1CTL
		dw offset CM2CTL
CM1CTL		db    0		; Control structure for	first COM port
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		dw offset CM1ISR
CM2CTL		db    0         ; Control structure for	second COM port
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		db    0
		dw offset CM2ISR
CBFSEG		dw 0
CBFSIZ		dw 0
ISRDSP		dw offset ISRFN0
		dw offset ISRFN1
		dw offset ISRFN2
		dw offset ISRFN3
; ---------------------------------------------------------------------------

CM1ISR:
		push	bx
		mov	bx, offset CM1CTL
		jmp	short COMISR

; =============== S U B	R O U T	I N E =======================================


CM2ISR		proc far
		push	bx
		mov	bx, offset CM2CTL

COMISR:
		push	cx
		push	dx
		push	si
		push	di
		push	ds
		push	cs
		pop	ds
		assume ds:CSEG
		push	ax
		mov	byte ptr [bx+1Dh], 0
		mov	dx, [bx]
		inc	dx
		inc	dx
		in	al, dx
loc_523B:
		and	al, 6
		inc	byte ptr [bx+1Dh]
		mov	ah, 0
		mov	si, ax
		jmp	ISRDSP[si]
ISRFN2:
		dec	dx
		dec	dx
		in	al, dx
		mov	si, [bx+0Ah]
		inc	si
		cmp	si, CBFSIZ
		jbe	short loc_5257
		xor	si, si
loc_5257:
		cmp	si, [bx+8]
		jnz	short loc_5262
		or	byte ptr [bx+18h], 1
		jmp	short COMEOI
; ---------------------------------------------------------------------------

loc_5262:
		mov	BYTE PTR ISREVT, 1
		mov	[bx+0Ah], si
		push	ds
		push	bx
		mov	bx, [bx+14h]
		mov	di, CBFSEG
		mov	ds, di
		assume ds:nothing
		mov	[bx+si], al
		pop	bx
		pop	ds
COMEOI:
		mov	al, 20h		; Send EOI
		out	20h, al		; Interrupt controller,	8259A.
		mov	dx, [bx]
		inc	dx
		inc	dx
		in	al, dx
		test	al, 1
		jnz	short ISRX
		cmp	byte ptr [bx+1Dh], 8
		jb	short loc_523B
		or	byte ptr [bx+19h], 1
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		mov	si, cs:[bx+1Eh]	; Messing with the IVT!
		mov	ax, cs:[bx+10h]
		mov	[si], ax
		mov	ax, cs:[bx+12h]
		mov	[si+2],	ax
		xor	ax, ax
		mov	cs:[bx+10h], ax
		mov	cs:[bx+12h], ax
		pop	ds
		assume ds:nothing
		inc	dx
		inc	dx
		mov	al, 0		; Read interrupt mask
		out	dx, al
		in	al, 21h		; Interrupt controller,	8259A.
		or	al, [bx+1Ch]	; Mask this port's IRQ again
		out	21h, al		; Interrupt controller,	8259A.
		mov	al, 20h		; One more EOI for good	measure?
		out	20h, al		; Interrupt controller,	8259A.
ISRX:
		pop	ax
		pop	ds
		pop	di
		pop	si
		pop	dx
		pop	cx
		pop	bx
		sti
		iret
; ---------------------------------------------------------------------------

ISRFN1:
		dec	dx
		mov	si, [bx+0Ch]
		cmp	si, [bx+0Eh]
		jz	short loc_52F2
		inc	si
		cmp	si, 80h	; '�'
		jbe	short loc_52DC
		xor	si, si
loc_52DC:
		mov	[bx+0Ch], si
		push	bx
		push	ds
		mov	bx, [bx+16h]
		mov	di, ds:CBFSEG
		mov	ds, di
		mov	al, [bx+si]
		pop	ds
		pop	bx
		dec	dx
		out	dx, al
		jmp	short COMEOI
; ---------------------------------------------------------------------------

loc_52F2:
		mov	al, 0Dh
		out	dx, al
		jmp	short COMEOI
; ---------------------------------------------------------------------------

ISRFN3:
		add	dx, 3
		in	al, dx
		and	al, 0Ah
		or	[bx+18h], al
		jmp	COMEOI
; ---------------------------------------------------------------------------

ISRFN0:
		add	dx, 4
		in	al, dx
		sub	dx, 5
		mov	cl, [bx+1Ah]
		not	al
		and	al, cl
		mov	ah, [bx+19h]
		mov	ch, ah
		and	ah, 0F0h
		cmp	ah, al
		jz	short loc_5330
		and	ch, 0Fh
		or	al, ch
		mov	[bx+19h], al
		and	al, cl
		jz	short loc_5333
		or	byte ptr [bx+19h], 2
		mov	al, 0Dh
		out	dx, al
loc_5330:
		jmp	COMEOI
; ---------------------------------------------------------------------------

loc_5333:
		and	byte ptr [bx+19h], 0FDh
		mov	al, 0Fh
		out	dx, al
		jmp	COMEOI
CM2ISR		endp


; =============== S U B	R O U T	I N E =======================================

; Set OEM COM Buffer (size & location)
; On entry: CX = COM buffer segment
;	    DX = COM buffer size if ZF set
;	    ZF set   = use buffer size in DX
;	    ZF clear = use default buffer size
;
; On return: DX	= COM buffer size
;	     CF	set on error

SETCBF		proc near
		push	bx
		push	ax
		push	ds
		push	si
		mov	cs:CBFSEG, cx
		jnz	short HAVBSZ	; ZF set if COM	buffer size was
					; given	on the command line (/C:xxx)
		mov	dx, 256		; Default COM buffer size
HAVBSZ:
		xor	si, si
		or	dx, dx
		jz	short SCBFX	; Bail if zero buffer size
		cmp	dx, 7F70h	; Buffer size too big?
		jbe	short CKCOM1
		mov	dx, 7F70h	; Maximum COM buffer size
CKCOM1:
		mov	cs:CBFSIZ, dx
		inc	dx
		mov	ds, si
		assume ds:nothing
		mov	bx, offset CM1CTL
		mov	ax, ds:400h	; Read COM1 base from BDA
		cmp	ax, 3F8h	; Does it match	the first UART?
		jnz	short CKCOM2
		mov	word ptr cs:[bx+1Eh], 30h ; Address of IRQ4 vector
		mov	byte ptr cs:[bx+1Bh], 0EFh ; IRQ4 mask
		mov	byte ptr cs:[bx+1Ch], 10h ; IRQ4 bit
		mov	cs:[bx], ax
		mov	cs:[bx+16h], si
		add	si, 81h	; '�'
		mov	cs:[bx+14h], si
		add	si, dx
		mov	bx, offset CM2CTL
		mov	ax, ds:402h	; Read COM2 base from BDA
CKCOM2:
		cmp	ax, 2F8h	; Is it	the second UART?
		jnz	short SCBFX
		mov	word ptr cs:[bx+1Eh], 2Ch ; Address of IRQ3 vector
		mov	byte ptr cs:[bx+1Bh], 0F7h ; IRQ3 mask
		mov	byte ptr cs:[bx+1Ch], 8	; IRQ3 bit
		mov	cs:[bx], ax
		mov	cs:[bx+16h], si
		add	si, 81h	; '�'
		mov	cs:[bx+14h], si
		add	si, dx
SCBFX:
		mov	dx, si
		add	dx, 0Fh		; Round	up to next para
		and	dx, 0FFF0h
		pop	si
		pop	ds
		assume ds:nothing
		pop	ax
		pop	bx
		clc
		ret
SETCBF		endp

; ---------------------------------------------------------------------------
; START	OF FUNCTION CHUNK FOR INICOM

BADFNM:
		mov	ah, -1		; Bad file name
		jmp	INICMX
; ---------------------------------------------------------------------------

COMERR:
		mov	ah, -2
		jmp	INICMX
; END OF FUNCTION CHUNK	FOR INICOM

; =============== S U B	R O U T	I N E =======================================

; Machine dependent COM	OPEN routine

INICOM		proc near

		push	si
		push	di
		push	ds
		push	cs
		pop	ds
		assume ds:CSEG
		mov	si, bx
		cld
		lods	byte ptr es:[si]
		mov	ah, al
		call	CMPREP
		or	dx, dx
		jz	short COMERR
		lods	word ptr es:[si]
		mov	di, offset BAUDTB
		mov	cx, 0Ah
		push	es
		push	cs
		pop	es
		assume es:CSEG
		repne scasw
		pop	es
		assume es:nothing
		jnz	short BADFNM
		add	di, 12h
		add	dx, 3
		mov	al, 80h	; '�'
		out	dx, al
		sub	dx, 3
		mov	ax, [di]
		out	dx, al
		inc	dx
		mov	al, ah
		out	dx, al
		add	dx, 2
		lods	byte ptr es:[si]
		sub	al, 4
		mov	ah, al
		jb	short BADFNM
		jz	short loc_5418
		dec	al

loc_5418:
		cmp	al, 3
		ja	short BADFNM
		mov	cl, al
		lods	byte ptr es:[si]
		jnz	short loc_542A
		cmp	al, 2
		jz	short loc_542A
		or	al, al
		jnz	short BADFNM

loc_542A:
		or	ah, al
		jz	short BADFNM
		dec	al
		js	short loc_543D
		mov	ah, 0
		push	bx
		mov	bx, offset masks?
		add	bx, ax
		or	cl, [bx]
		pop	bx

loc_543D:
		lods	byte ptr es:[si]
		or	al, al
		jz	short loc_5446
		or	cl, 4

loc_5446:
		mov	al, cl
		out	dx, al
		lods	word ptr es:[si]
		mov	cl, 0
		mov	[bx+2],	ax
		or	ax, ax
		jz	short loc_5457
		or	cl, 80h

loc_5457:
		lods	word ptr es:[si]
		mov	[bx+4],	ax
		or	ax, ax
		jz	short loc_5463
		or	cl, 10h

loc_5463:
		lods	word ptr es:[si]
		mov	[bx+6],	ax
		or	ax, ax
		jz	short loc_546F
		or	cl, 20h

loc_546F:
		lods	byte ptr es:[si]
		test	al, 2
		mov	al, 3
		jz	short loc_5479
		mov	al, 1

loc_5479:
		inc	dx
		out	dx, al
		xor	al, al
		mov	[bx+1Ah], cl
		mov	[bx+18h], al
		mov	word ptr [bx+8], 0
		mov	word ptr [bx+0Ah], 0
		mov	word ptr [bx+0Ch], 0
		mov	word ptr [bx+0Eh], 0
		cmp	word ptr [bx+10h], 0
		jnz	short loc_54DC
		sub	dx, 4
		push	ds
		xor	ax, ax
		mov	ds, ax
		mov	si, cs:[bx+1Eh]	; IVT manipulation!
		mov	ax, [si]
		mov	cs:[bx+10h], ax
		mov	ax, [si+2]
		mov	cs:[bx+12h], ax
		mov	ax, cs:[bx+20h]
		mov	[si], ax
		mov	ax, cs
		mov	[si+2],	ax
		pop	ds
		assume ds:nothing
		inc	dx
		inc	dx
		in	al, dx
		dec	dx
		dec	dx
		in	al, dx
		add	dx, 5
		in	al, dx
		sub	dx, 4
		mov	al, 0Dh
		out	dx, al
		in	al, 21h		; Interrupt controller,	8259A.
		and	al, [bx+1Bh]	; Unmask IRQ
		out	21h, al		; Interrupt controller,	8259A.
		add	dx, 3

loc_54DC:
		in	al, dx
		or	al, 8
		out	dx, al
		inc	dx
		inc	dx
		cli
		in	al, dx
		not	al
		and	al, cl
		mov	[bx+19h], al
		sti
		call	sub_5665

INICMX:
		pop	ds
		pop	di
		pop	si
		ret
INICOM		endp


; =============== S U B	R O U T	I N E =======================================

; Read Char from COM to	[AL] if	ready

RECCOM		proc near
		push	bx
		push	cx
		push	dx
		push	si
		push	di
		push	ds
		push	cs
		pop	ds
		assume ds:CSEG
		push	ax
		call	CMPREP
		mov	cl, 0
		call	sub_5643
		pop	cx
		mov	al, cl
		jnz	short loc_552C
		cli
		mov	si, [bx+8]
		cmp	si, [bx+0Ah]
		jz	short loc_552C
		inc	si
		cmp	si, CBFSIZ
		jbe	short loc_551B
		xor	si, si

loc_551B:
		mov	[bx+8],	si
		mov	bx, [bx+14h]
		mov	di, CBFSEG
		mov	ds, di
		assume ds:nothing
		mov	al, [bx+si]
		sti
		or	dx, dx

loc_552C:
		pop	ds
		pop	di
		pop	si
		pop	dx
		pop	cx
		pop	bx
		ret
RECCOM		endp


; =============== S U B	R O U T	I N E =======================================

; Send [AL] to COM

SNDCOM		proc near
		push	bx
		push	cx
		push	dx
		push	si
		push	di
		push	ds
		push	cs
		pop	ds
		assume ds:CSEG
		push	ax
		call	CMPREP
		mov	cl, [bx+1Ah]
		call	sub_5643
		pop	cx
		jnz	short SNDCMX

SNDLOP:
		cli
		mov	si, [bx+0Eh]
		inc	si
		cmp	si, 80h	; '�'
		jbe	short loc_5555
		xor	si, si

loc_5555:
		cmp	si, [bx+0Ch]
		jz	short loc_557D
		push	ds
		push	bx
		mov	[bx+0Eh], si
		mov	bx, [bx+16h]
		mov	di, CBFSEG
		mov	ds, di
		assume ds:nothing
		mov	[bx+si], cl
		pop	bx
		pop	ds
		inc	dx
		in	al, dx
		test	al, 2
		jnz	short SNDCMX
		test	byte ptr [bx+19h], 2
		jnz	short SNDCMX
		mov	al, 0Fh
		out	dx, al
		jmp	short SNDCMX
; ---------------------------------------------------------------------------

loc_557D:
		sti
		call	COMDLY
		jz	short SNDLOP	; Next char unless Ctrl+Break pressed
SNDCMX:
		sti
		pop	ds
		pop	di
		pop	si
		pop	dx
		pop	cx
		pop	bx
		ret
SNDCOM		endp


; =============== S U B	R O U T	I N E =======================================

; Get COM bytes	in queue
;	 On entry: AH =	unit number
;	 On return: DX=bytes in	queue
;		    CX=free bytes in queue
;		    AH = non-zero if error

STACOM		proc near
		push	bx
		push	si
		push	di
		push	ds
		push	cs
		pop	ds
		assume ds:CSEG
		call	CMPREP
		xor	ah, ah
		mov	dx, [bx+0Ah]
		cmp	dx, [bx+8]
		jnb	short loc_55A3
		add	dx, CBFSIZ
		inc	dx

loc_55A3:
		sub	dx, [bx+8]
		mov	cx, CBFSIZ
		sub	cx, dx
		cmp	dx, 0FFh
		jbe	short loc_55B5
		mov	dx, 0FFh

loc_55B5:
		pop	ds
		assume ds:nothing
		pop	di
		pop	si
		pop	bx
		ret
STACOM		endp


; =============== S U B	R O U T	I N E =======================================


SNDLPT		proc near
		push	cx
		push	dx
		xor	dx, dx
		xchg	dl, ah
		int	17h
		and	ah, 1
		jz	short loc_55DF
		mov	ah, 2
		int	17h		; PRINTER - GET	STATUS
					; DX = printer port (0-3)
					; Return: AH = status
		cmp	ah, 28h	; '('
		jnz	short loc_55D4
		mov	ah, 3
		jmp	short loc_55DF
; ---------------------------------------------------------------------------

loc_55D4:
		cmp	ah, 8
		jnz	short loc_55DD
		mov	ah, 4
		jmp	short loc_55DF
; ---------------------------------------------------------------------------

loc_55DD:
		mov	ah, 2

loc_55DF:
		pop	dx
		pop	cx
		ret
SNDLPT		endp


; =============== S U B	R O U T	I N E =======================================

; Terminate COM	channel

TRMCOM		proc near
		push	bx
		push	cx
		push	dx
		push	si
		push	di
		push	ds
		push	cs
		pop	ds
		assume ds:CSEG
		call	CMPREP
		or	dx, dx
		jnz	short loc_55F5
		mov	ah, 0FFh
		jmp	short loc_563C
; ---------------------------------------------------------------------------

loc_55F5:
		inc	dx
		mov	cx, 150
loc_55F9:
		in	al, dx
		test	al, 2
		jz	short loc_5606
		call	COMDLY
		jz	short loc_55F9
		jmp	short loc_560D
; ---------------------------------------------------------------------------

loc_5606:
		call	COMDLY
		jnz	short loc_560D
		loop	loc_5606
loc_560D:
		mov	al, 0
		out	dx, al
		add	dx, 3
		out	dx, al
		in	al, 21h		; Interrupt controller,	8259A.
		or	al, [bx+1Ch]
		out	21h, al		; Interrupt controller,	8259A.
		xor	ax, ax
		mov	ds, ax		; IVT manipulation!
		mov	si, cs:[bx+1Eh]
		mov	ax, cs:[bx+10h]
		mov	[si], ax
		mov	ax, cs:[bx+12h]
		mov	[si+2],	ax
		xor	ax, ax
		mov	cs:[bx+10h], ax
		mov	cs:[bx+12h], ax
		mov	ah, 0
loc_563C:
		pop	ds
		assume ds:nothing
		pop	di
		pop	si
		pop	dx
		pop	cx
		pop	bx
		ret
TRMCOM		endp


; =============== S U B	R O U T	I N E =======================================


sub_5643	proc near
		cli
		mov	al, [bx+18h]
		mov	byte ptr [bx+18h], 0
		sti
		or	al, al
		jnz	short loc_5654
		call	sub_5665
		ret
; ---------------------------------------------------------------------------

loc_5654:
		mov	ah, 1
		test	al, 1
		jnz	short loc_5662
		mov	ah, 6
		test	al, 2
		jnz	short loc_5662
		mov	ah, 7
loc_5662:
		or	ah, ah
		ret
sub_5643	endp


; =============== S U B	R O U T	I N E =======================================


sub_5665	proc near
		inc	cl
		push	bp
		mov	si, [bx+4]
		mov	bp, si
		mov	di, [bx+2]
		mov	si, [bx+6]
loc_5673:
		mov	al, [bx+19h]
		xor	ah, ah
		and	al, cl
		jz	short loc_56A6
		test	al, 1
		jz	short loc_5684
		mov	ah, 0FFh
		jmp	short loc_56A6
; ---------------------------------------------------------------------------

loc_5684:
		test	al, 80h
		jz	short loc_568D
		dec	di
		mov	ah, 5
		jz	short loc_56A6
loc_568D:
		test	al, 20h
		jz	short loc_5696
		dec	si
		mov	ah, 4
		jz	short loc_56A6
loc_5696:
		test	al, 10h
		jz	short loc_569F
		dec	bp
		mov	ah, 3
		jz	short loc_56A6
loc_569F:
		call	COMDLY
		jz	short loc_5673
		mov	ah, 0FFh
loc_56A6:
		pop	bp
		or	ah, ah
		ret
sub_5665	endp


; =============== S U B	R O U T	I N E =======================================


COMDLY		proc near
		push	ax
		push	bx
		push	cx
		mov	cx, 242
DELAY:
		loop	DELAY
		pop	cx
		xor	ax, ax
		push	ds
		mov	ds, ax
		assume ds:nothing
		cmp	al, ds:471h	; Check	Ctrl+Break flag
		pop	ds
		assume ds:nothing
		pop	bx
		pop	ax
		ret
COMDLY		endp


; =============== S U B	R O U T	I N E =======================================


CMPREP		proc near
		mov	al, ah
		shl	al, 1
		mov	ah, 0
		push	si
		mov	si, offset COMTBL
		add	si, ax
		mov	bx, [si]
		mov	dx, [bx]
		xor	ax, ax
		push	ds
		mov	ds, ax
		assume ds:nothing
		mov	ds:471h, al	; Zero out Ctrl+Break flag
		pop	ds
		assume ds:nothing
		pop	si
		ret
CMPREP		endp

; ---------------------------------------------------------------------------
; Start of another module?
;		align 8
PUBLIC  SCNRST, GWINI, GWTERM, KEYINP, INKMAP, INFMAP, EDTMAP, MAPSUP
PUBLIC  SCROUT, SCRINP, SCROLL, CLRSCN, CLREOL
PUBLIC  CSRDSP, CSRATR, LCPY, SCRATR, SCRSTT, SETCLR, SWIDTH

EVTSET		db 0
LSTRIG		db 0
BRKFLG		db -1

; =============== S U B	R O U T	I N E =======================================


TIMISR		proc far
		test	cs:EVTSET, 1	; Light	pen enabled?
		jz	short loc_56EE
		call	LPENQR

loc_56EE:
		push	ax
		push	dx
		mov	dx, 201h
		in	al, dx		; Game I/O port
					; bits 0-3: Coordinates	(resistive, time-dependent inputs)
					; bits 4-7: Buttons/Triggers (digital inputs)
		not	al
		or	cs:LSTRIG, al
		and	al, 0F0h
		or	cs:ISREVT, al
		pop	dx
		pop	ax
		iret
TIMISR		endp


; =============== S U B	R O U T	I N E =======================================


CTLBRK		proc far
		mov	cs:BRKFLG, 0	; 0 = Ctrl+Break, -1 = no break
		iret
CTLBRK		endp


; =============== S U B	R O U T	I N E =======================================

; Reset	screen related state

SCNRST		proc near
		mov	ah, 0
		mov	al, ds:var_63b
		mov	cl, 25
		call	SCNSWI
		call	SCNCLR
		call	GRPINI
		ret
SCNRST		endp

; ---------------------------------------------------------------------------
EQUIP		db 0

; =============== S U B	R O U T	I N E =======================================


GWINI		proc near
		call	SCRSAV
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		mov	al, ds:410h	; Read equipment word (low byte)
		mov	cs:EQUIP, al
		pop	ds
		assume ds:nothing
		mov	al, ds:CVMODE
		mov	ds:OVMODE, al
		mov	al, ds:var_63e
		mov	ds:var_63b, al
		cmp	byte ptr ds:CVMODE, 7
		jnz	short VIDPGE
		mov	word ptr ds:var_643, 0C0Dh
VIDPGE:
		mov	ax, 500h
		int	10h		; - VIDEO - SELECT DISPLAY PAGE
					; AL = display page, 0-7  for modes 0 &	1, 0-3	for modes 2 & 3
		xor	dx, dx
INILPT:
		mov	ah, 1
		push	dx
		int	17h		; PRINTER - INITIALIZE
					; DX = printer port (0-3)
					; Return: AH = status
		pop	dx
		inc	dx
		cmp	dx, 3
		jnz	short INILPT
		mov	ax, cs		; Set segments for interrupt vectors
		mov	ds:CBRKSG, ax
		mov	ds:TIMRSG, ax
		call	SWPVEC		; Install INT 1Bh/1Ch vectors
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		pop	ax
		push	ax
		mov	ds:510h, ax     ; Set initial BASIC data segment
		mov	al, ds:300h
		pop	ds
		assume ds:nothing
		cmp	al, 0
		jz	short GWINIX
		mov	bx, offset SPCTAB
		add	bx, 39h		; Offset of PLAYS entry	in STMDSX
		mov	ax, offset SNERR ; Disable PLAY	statement?
		mov	cs:[bx], ax
GWINIX:
		jmp	DOCLRS
GWINI		endp


; =============== S U B	R O U T	I N E =======================================


SWPVEC		proc near
		mov	cx, 4		; 4 words (two vectors)
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		mov	si, 6Ch		; Offset of vector 1Bh (Ctrl+Break)
		mov	di, OFFSET CBKINT
		cli
		cld
DOVEC:
		mov	ax, es:[di]	; Read in new offset
		xchg	ax, [si]	; Swap in new offset
		stosw			; Save old offset
		inc	si		; Skip over segment
		inc	si
		loop	DOVEC
		sti
		pop	ds
		assume ds:nothing
		ret
SWPVEC		endp


; =============== S U B	R O U T	I N E =======================================


GWTERM		proc near
		call	SCRSAV
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		mov	al, cs:EQUIP	; Restore equipment word
		mov	ds:410h, al
		pop	ds
		assume ds:nothing
		mov	al, -1
		call	DONOTE
		mov	cx, 607h	; 8x8 cursor
		cmp	byte ptr ds:CVMODE, 7
		jnz	short SETCSR
		mov	cx, 0C0Dh	; 8x14 cursor
SETCSR:
		mov	ah, 1
		int	10h		; - VIDEO - SET	CURSOR CHARACTERISTICS
					; CH bits 0-4 =	start line for cursor in character cell
					; bits 5-6 = blink attribute
					; CL bits 0-4 =	end line for cursor in character cell
		cmp	byte ptr ds:CVMODE, 7
		jz	short loc_57E9
		xor	ax, ax
		mov	al, ds:OVMODE
		cmp	ah, ds:VISVPG
		jnz	short SETVMD
		cmp	ah, ds:CVPAGE
		jnz	short SETVMD
		cmp	al, ds:CVMODE
		jz	short loc_57E9
SETVMD:
		int	10h		; - VIDEO - SET	VIDEO MODE
					; AL = mode
loc_57E9:
		mov	byte ptr ds:var_646, 7
		mov	byte ptr ds:var_63a, 0
		mov	dx, 1700h
		mov	ds:var_64e, dx
		mov	bh, 0
		mov	ah, 2
		int	10h		; - VIDEO - SET	CURSOR POSITION
					; DH,DL	= row, column (0,0 = upper left)
					; BH = page number
		call	SWPVEC
		jmp	SCRRST
GWTERM		endp


; =============== S U B	R O U T	I N E =======================================

; Keyboard input routine
; On exit:
;   ZF set if key available
;   ZF clear if	no keyboard input
;   CF set if two bytes	available (AX)
;   CF clear if	one byte available (AL)

KEYINP		proc near
		push	es
		push	cs
		pop	es
		assume es:CSEG
		push	bx
		push	cx
		push	di
		cld
		cmp	cs:BRKFLG, 0	; Zero if Ctrl+Break was signaled
		jnz	short NOBRK
		dec	cs:BRKFLG	; Clear	Ctrl+Break flag
		mov	ah, 1
		int	16h		; KEYBOARD - CHECK BUFFER, DO NOT CLEAR
					; Return: ZF clear if character	in buffer
					; AH = scan code, AL = character
					; ZF set if no character in buffer
		jz	short CBREAK
		xor	ah, ah
		int	16h		; KEYBOARD - READ CHAR FROM BUFFER, WAIT IF EMPTY
					; Return: AH = scan code, AL = character
CBREAK:
		mov	ax, 0FF03h	; CTLBRK aka Ctrl+Break
		jmp	short TWOKEY
; ---------------------------------------------------------------------------

NOBRK:
		mov	ah, 1
		int	16h		; KEYBOARD - CHECK BUFFER, DO NOT CLEAR
					; Return: ZF clear if character	in buffer
					; AH = scan code, AL = character
					; ZF set if no character in buffer
		jz	short KEYINX
		xor	ah, ah
		int	16h		; KEYBOARD - READ CHAR FROM BUFFER, WAIT IF EMPTY
					; Return: AH = scan code, AL = character
		or	al, al
		jz	short NONASC
		mov	ah, 0
		cmp	al, 0FEh ; '�'
		jb	short CHKESC
		mov	ah, 0FFh
		jnz	short TWOKEY
		mov	al, 18h
		jmp	short TWOKEY
; ---------------------------------------------------------------------------

CHKESC:
		cmp	al, 1Bh		; ESC key?
		jnz	short ONEKEY
		mov	ax, 0FF15h
		jmp	short TWOKEY
; ---------------------------------------------------------------------------

ONEKEY:
		or	sp, sp
KEYINX:
		pop	di
		pop	cx
		pop	bx
		pop	es
		assume es:nothing
		ret
; ---------------------------------------------------------------------------

NONASC:
		xchg	al, ah
		mov	di, offset SCNXLT
		mov	cx, 57
		cld
		repne scasb
		jnz	short NOTTAB
		sub	di, offset SCNXLT
		mov	ax, di
		cmp	ax, 20h
		mov	ah, 0FFh
		jb	short TWOKEY
		add	al, 21h	; '!'
loc_5871:
		mov	ah, 80h
TWOKEY:
		or	sp, sp
		stc
		jmp	short KEYINX
; ---------------------------------------------------------------------------

NOTTAB:
		cmp	al, 3Bh	; ';'
		jb	short loc_5884
		cmp	al, 45h	; 'E'
		jnb	short loc_5884
		sub	al, 1Bh
		jmp	short loc_5871
; ---------------------------------------------------------------------------

loc_5884:
		cmp	al, 53h	; 'S'
		mov	dx, ax
		mov	al, 0FEh
		jnz	short ONEKEY
		mov	ax, 0FF7Fh
		jmp	short TWOKEY
KEYINP		endp

; ---------------------------------------------------------------------------
SCNXLT		db 0FAh, 73h, 2	dup(0FAh), 75h,	74h, 4 dup(0F9h), 47h
		db 77h,	0F9h, 4Fh, 0F9h, 2 dup(0FAh), 52h, 2 dup(0FAh)
		db 0F9h, 2 dup(0FAh), 0FEh, 3 dup(0FAh), 4Dh, 4Bh, 48h
		db 50h,	1Eh, 30h, 2Eh, 20h, 12h, 21h, 22h, 23h,	17h, 24h
		db 25h,	26h, 32h, 31h, 18h, 19h, 10h, 13h, 1Fh,	14h, 16h
		db 2Fh,	11h, 2Dh, 15h, 2Ch

; =============== S U B	R O U T	I N E =======================================

; OEM map routine for INKEY$

INKMAP		proc near
		push	bx
		jb	short loc_58DE
		cmp	al, 0FEh ; '�'
		jnz	short loc_58DA
		mov	ax, dx
loc_58D3:
		mov	ah, 0
		or	sp, sp
		stc
		pop	bx
		ret
; ---------------------------------------------------------------------------

loc_58DA:
		or	sp, sp
loc_58DC:
		pop	bx
		ret
; ---------------------------------------------------------------------------

loc_58DE:
		cmp	al, 0FFh
		jz	short loc_58DA
		cmp	al, 15h
		jnz	short loc_58EA
		mov	al, 1Bh
		jmp	short loc_58DA
; ---------------------------------------------------------------------------

loc_58EA:
		cmp	al, 7Fh	; ''
		jnz	short loc_58F2
		mov	al, 53h	; 'S'
		jmp	short loc_58D3
; ---------------------------------------------------------------------------

loc_58F2:
		cmp	al, 20h	; ' '
		jnb	short loc_590A
		mov	bx, offset SCNXLT-1
		mov	ah, 0
		add	bx, ax
		mov	al, cs:[bx]
		cmp	al, 0FAh ; '�'
		jz	short loc_58DC
		cmp	al, 0FEh ; '�'
		jb	short loc_58D3
		jmp	short loc_58DA
; ---------------------------------------------------------------------------

loc_590A:
		cmp	al, 2Ah	; '*'
		jnb	short loc_5912
		add	al, 1Bh
		jmp	short loc_58D3
; ---------------------------------------------------------------------------

loc_5912:
		cmp	al, 'A'
		jb	short loc_5928
		cmp	al, 5Bh	; '['
		jnb	short loc_5928
		sub	al, 'A'
		mov	ah, 0
		mov	bx, (offset SCNXLT+1Fh)
		add	bx, ax
		mov	al, cs:[bx]
		jmp	short loc_58D3
; ---------------------------------------------------------------------------

loc_5928:
		cmp	al, al
		jmp	short loc_58DC
INKMAP		endp


; =============== S U B	R O U T	I N E =======================================

; OEM fixed length input map routine

INFMAP		proc near
		call	INKMAP
		jnb	short INMAPX
		mov	al, 0
INMAPX:
		clc
		ret
INFMAP		endp


; =============== S U B	R O U T	I N E =======================================

; Map edit function/output character code

EDTMAP		proc near
		mov	byte ptr ds:var_641, 0
		cmp	ax, 3
		jz	short loc_5983
		cmp	ah, 0FFh
		jnz	short loc_595D
		cmp	al, 18h
		jnz	short loc_594D
		mov	ax, 0FEh
		jmp	short loc_5989
; ---------------------------------------------------------------------------

loc_594D:
		cmp	al, 0FFh
		jnz	short loc_5983
		cmp	byte ptr ds:var_63a, 0
		jz	short loc_5983
		mov	ax, ' '
		jmp	short loc_5989
; ---------------------------------------------------------------------------

loc_595D:
		cmp	al, 1Bh
		jnz	short loc_5965
		mov	al, 15h
		jmp	short loc_5983
; ---------------------------------------------------------------------------

loc_5965:
		cmp	al, 0FFh
		jz	short loc_5983
		cmp	al, 7Fh
		jz	short loc_5983
		cmp	al, ' '
		jnb	short loc_5989
		push	ax
		push	bx
		mov	ah, 0
		mov	bx, offset SCNXLT-1
		add	bx, ax
		mov	al, cs:[bx]
		cmp	al, 0FAh
		pop	bx
		pop	ax
		jz	short loc_598B
loc_5983:
		mov	ah, 0FFh
		or	sp, sp
		stc
		ret
; ---------------------------------------------------------------------------

loc_5989:
		or	sp, sp
loc_598B:
		clc
		ret
EDTMAP		endp

; ---------------------------------------------------------------------------
		ret

; =============== S U B	R O U T	I N E =======================================

; Map super shift key to letter	in [AL]	and count in [CH]

MAPSUP		proc near
		mov	ch, 1
		ret
MAPSUP		endp


; =============== S U B	R O U T	I N E =======================================

; Write	the character in [AL] at (DH,DL)

SCROUT		proc near
		push	ax
		push	bx
		push	cx
		push	dx
		sub	dx, 101h
		xchg	dl, dh
		push	ax
		mov	ds:var_64e, dx
		mov	bh, ds:CVPAGE
		mov	ah, 2
		int	10h		; - VIDEO - SET	CURSOR POSITION
					; DH,DL	= row, column (0,0 = upper left)
					; BH = page number
		pop	ax
		mov	cx, 1
		mov	bl, ds:var_646
		mov	ah, 9
		int	10h		; - VIDEO - WRITE ATTRIBUTES/CHARACTERS	AT CURSOR POSITION
					; AL = character, BH = display page
					; BL = attributes of character (alpha modes) or	color (graphics	modes)
					; CX = number of times to write	character
		clc
		pop	dx
		pop	cx
		pop	bx
		pop	ax
		ret
SCROUT		endp


; =============== S U B	R O U T	I N E =======================================


SCRSV2		proc near
		pop	word ptr ds:var_650
		push	dx
		push	cx
		push	bx
		push	ax
		pushf
		cmp	byte ptr ds:var_63a, 0
		jz	short loc_59DB
		cmp	byte ptr ds:var_640, 1
		jz	short loc_59D8
		cmp	byte ptr ds:var_640, 2
		jnz	short loc_59DB
loc_59D8:
		call	sub_5BF8
loc_59DB:
		push	ax
		sub	dx, 101h
		xchg	dl, dh
		mov	ds:var_64e, dx
		mov	bh, ds:CVPAGE
		mov	ah, 2
		int	10h		; - VIDEO - SET	CURSOR POSITION
					; DH,DL	= row, column (0,0 = upper left)
					; BH = page number
		pop	ax
		popf
		push	word ptr ds:var_650
		ret
SCRSV2		endp


; =============== S U B	R O U T	I N E =======================================


SCRINP		proc near
					; SCNMRK:loc_987Dp ...
		call	SCRSV2
		pushf
		mov	ah, 8
		int	10h		; - VIDEO - READ ATTRIBUTES/CHARACTER AT CURSOR	POSITION
					; BH = display page
					; Return: AL = character
					; AH = attribute of character (alpha modes)
		popf
		jb	short loc_5A06
		or	al, al
		jnz	short loc_5A06
		mov	al, ' '
loc_5A06:
		xor	ah, ah
		pop	dx
		push	ax
		jmp	short SCRRST
SCRINP		endp


; =============== S U B	R O U T	I N E =======================================


SCROLL		proc near
		call	SCRSAV
		xchg	al, ah
		xchg	bl, bh
		xchg	cl, ch
		mov	dx, 101h
		sub	ax, dx
		sub	bx, dx
		sub	cx, dx
		cmp	ah, bh
		jnz	short loc_5A57
		cmp	bl, al
		mov	byte ptr ds:var_63c, 1
		jb	short loc_5A35
		mov	byte ptr ds:var_63c, 0FFh
		add	al, cl
		add	bl, cl
loc_5A35:
		call	DOSCRL
SCRRST:
		pushf
		cmp	byte ptr ds:var_63a, 0
		jz	short loc_5A51
		cmp	byte ptr ds:var_640, 1
		jz	short loc_5A4E
		cmp	byte ptr ds:var_640, 2
		jnz	short loc_5A51
loc_5A4E:
		call	sub_5BF8
loc_5A51:
		popf
		pop	ax		; Restores registers that SCRSAV saved
		pop	bx
		pop	cx
		pop	dx
		ret
; ---------------------------------------------------------------------------

loc_5A57:
		cmp	al, bl
		jnz	short loc_5A89
		call	SETVPG
		cmp	bh, ah
		jnb	short loc_5A6A
		add	ax, cx
		mov	cx, bx
		mov	bl, 6
		jmp	short loc_5A6F
; ---------------------------------------------------------------------------

loc_5A6A:
		xchg	ax, cx
		add	ax, bx
		mov	bl, 7
loc_5A6F:
		mov	dx, ax
		mov	ah, bl
		mov	al, 1
		mov	bh, ds:var_646
		cmp	byte ptr ds:var_63a, 0
		jz	short loc_5A82
		mov	bh, 0
loc_5A82:
		int	10h		; - VIDEO - SCROLL PAGE	DOWN
					; AL = number of lines to scroll window	(0 = blank whole window)
					; BH = attributes to be	used on	blanked	lines
					; CH,CL	= row,column of	upper left corner of window to scroll
					; DH,DL	= row,column of	lower right corner of window
		call	SETVPG
		jmp	short SCRRST
; ---------------------------------------------------------------------------

loc_5A89:
		mov	byte ptr ds:var_63a, 1
		cmp	bl, al
		jb	short loc_5A9D
		add	ax, cx
		add	bx, cx
		mov	byte ptr ds:var_63c, 0FFh
		inc	ch
loc_5A9D:
		call	DOSCRL
		dec	ch
		jz	short SCRRST
		add	ah, ds:var_63c
		add	bh, ds:var_63c
		jmp	short loc_5A9D
SCROLL		endp


; =============== S U B	R O U T	I N E =======================================

; Set display page

SETVPG		proc near
		push	ax
		mov	al, ds:VISVPG
		cmp	al, ds:CVPAGE   ; Selected page equals visible?
		jz	short SETVPX    ; If so, we're done
		xchg	al, ds:CVPAGE
		mov	ds:VISVPG, al
		mov	ah, 5
		int	10h		; - VIDEO - SELECT DISPLAY PAGE
					; AL = display page, 0-7  for modes 0 &	1, 0-3	for modes 2 & 3
SETVPX:
		pop	ax
		ret
SETVPG		endp


; =============== S U B	R O U T	I N E =======================================


DOSCRL		proc near
		push	ax
		push	bx
		push	cx
		mov	dx, ax
		mov	ch, 0
		inc	cl
		jz	short DOSCRX
NXTCHR:
		call	SCRRDC
		add	dl, ds:var_63c
		xchg	dx, bx
		call	SCRWRC
		add	dl, ds:var_63c
		xchg	dx, bx
		loop	NXTCHR
DOSCRX:
		pop	cx
		pop	bx
		pop	ax
		ret
DOSCRL		endp


; =============== S U B	R O U T	I N E =======================================


SCRRDC		proc near
		push	bx
		mov	bh, ds:CVPAGE
		mov	ah, 2
		int	10h		; - VIDEO - SET	CURSOR POSITION
					; DH,DL	= row, column (0,0 = upper left)
					; BH = page number
		mov	ah, 8
		int	10h		; - VIDEO - READ ATTRIBUTES/CHARACTER AT CURSOR	POSITION
					; BH = display page
					; Return: AL = character
					; AH = attribute of character (alpha modes)
		pop	bx
		ret
SCRRDC		endp


; =============== S U B	R O U T	I N E =======================================


SCRWRC		proc near
		push	bx
		push	cx
		push	ax
		mov	bh, ds:CVPAGE
		mov	ah, 2
		int	10h		; - VIDEO - SET	CURSOR POSITION
					; DH,DL	= row, column (0,0 = upper left)
					; BH = page number
		pop	ax
		mov	cx, 1
		mov	bl, ds:var_646
		mov	ah, 9
		int	10h		; - VIDEO - WRITE ATTRIBUTES/CHARACTERS	AT CURSOR POSITION
					; AL = character, BH = display page
					; BL = attributes of character (alpha modes) or	color (graphics	modes)
					; CX = number of times to write	character
		pop	cx
		pop	bx
		ret
SCRWRC		endp


; =============== S U B	R O U T	I N E =======================================


SCRSAV		proc near
		pop	word ptr ds:var_650
		push	dx
		push	cx
		push	bx
		push	ax
		push	ax
		push	bx
		push	cx
		push	dx
		pushf
		mov	ah, 0Fh
		int	10h		; - VIDEO - GET	CURRENT	VIDEO MODE
					; Return: AH = number of columns on screen
					; AL = current video mode
					; BH = current active display page
		mov	ds:VISVPG, bh
		mov	ds:var_63e, ah
		mov	ds:CVMODE, al
		cmp	byte ptr ds:var_63a, 0
		jz	short loc_5B45
		cmp	byte ptr ds:var_640, 1
		jz	short loc_5B42
		cmp	byte ptr ds:var_640, 2
		jnz	short loc_5B45
loc_5B42:
		call	sub_5BF8
loc_5B45:
		popf
		pop	dx
		pop	cx
		pop	bx
		pop	ax
		push	word ptr ds:var_650
		ret
SCRSAV		endp


; =============== S U B	R O U T	I N E =======================================


CLRSCN		proc near
		call	SCRSAV

DOCLRS:
		push	ax
		call	SETVPG
		xor	cx, cx		; Start	at 0,0
		mov	dl, ds:var_63b
		dec	dl
		mov	dh, 24		; End at 24, width
		mov	ax, 600h
		mov	bh, ds:var_646
		cmp	byte ptr ds:var_63a, 0
		jz	short SCROL
		mov	bh, 0
SCROL:
		int	10h		; - VIDEO - SCROLL PAGE	UP
					; AL = number of lines to scroll window	(0 = blank whole window)
					; BH = attributes to be	used on	blanked	lines
					; CH,CL	= row,column of	upper left corner of window to scroll
					; DH,DL	= row,column of	lower right corner of window
		call	SETVPG
		pop	ax
		call	SCNRST
		jmp	SCNOK
CLRSCN		endp


; =============== S U B	R O U T	I N E =======================================


CLREOL		proc near
		push	ax
		push	bx
		push	cx
		push	dx
		sub	dx, 101h
		mov	al, ds:var_63b
		sub	al, dh
		jbe	short CLREOX
		mov	cl, al
		mov	ch, 0
		xchg	dl, dh
		mov	bh, ds:CVPAGE
		mov	ah, 2
		int	10h		; - VIDEO - SET	CURSOR POSITION
					; DH,DL	= row, column (0,0 = upper left)
					; BH = page number
		mov	al, ' '
		mov	bl, ds:var_646
		mov	ah, 9
		int	10h		; - VIDEO - WRITE ATTRIBUTES/CHARACTERS	AT CURSOR POSITION
					; AL = character, BH = display page
					; BL = attributes of character (alpha modes) or	color (graphics	modes)
					; CX = number of times to write	character
CLREOX:
		pop	dx
		pop	cx
		pop	bx
		pop	ax
		ret
CLREOL		endp


; =============== S U B	R O U T	I N E =======================================


CSRDSP		proc near
		call	SCRSV2
		cmp	ds:var_640, al
		jz	short loc_5BC6
		mov	ds:var_640, al
		cmp	al, 0
		jnz	short loc_5BC9
		mov	cx, ds:var_643
		or	ch, 20h
SETCUR:
		mov	ds:var_642, al
		mov	ah, 1
		int	10h		; - VIDEO - SET	CURSOR CHARACTERISTICS
					; CH bits 0-4 =	start line for cursor in character cell
					; bits 5-6 = blink attribute
					; CL bits 0-4 =	end line for cursor in character cell
loc_5BC6:
		jmp	SCNOK
; ---------------------------------------------------------------------------

loc_5BC9:
		cmp	al, 1
		jnz	short loc_5BDB
		mov	cx, 407h
		cmp	byte ptr ds:CVMODE, 7
		jnz	short SETCUR
		mov	cl, 0Dh
		jmp	short SETCUR
; ---------------------------------------------------------------------------

loc_5BDB:
		cmp	al, 2
		jnz	short GOSCUR
		mov	cx, ds:var_643
		and	ch, 0DFh
		jmp	short SETCUR
; ---------------------------------------------------------------------------

GOSCUR:
		mov	cx, ds:var_643
		mov	al, ds:var_641
		or	al, al
		jnz	short SETCUR
		or	ch, 20h
		jmp	short SETCUR
CSRDSP		endp


; =============== S U B	R O U T	I N E =======================================


sub_5BF8	proc near
		push	ax
		push	bx
		push	cx
		push	dx
		mov	bx, ds:var_64e
		mov	ax, 320
		xor	cx, cx
		xchg	bh, cl
		mul	cx
		mov	dl, ds:var_63a
		cmp	dl, 1
		jnz	short loc_5C14
		shl	bx, 1
loc_5C14:
		add	bx, ax
		add	bx, 0F0h ; '�'
		mov	cx, 4
		cmp	byte ptr ds:var_640, 1
		jnz	short loc_5C26
		dec	cx
		dec	cx
loc_5C26:
		mov	ax, 0B800h
		push	ds
		mov	ds, ax
		assume ds:nothing
		mov	ax, 0FFFFh
		cmp	dl, 1
		mov	dx, 2000h
		jnz	short loc_5C46
loc_5C37:
		add	bx, dx
		xor	[bx], ax
		sub	bx, dx
		xor	[bx], ax
		sub	bx, 80
		loop	loc_5C37
		jmp	short loc_5C53
; ---------------------------------------------------------------------------

loc_5C46:
		add	bx, dx
		xor	[bx], al
		sub	bx, dx
		xor	[bx], al
		sub	bx, 80
		loop	loc_5C46
loc_5C53:
		pop	ds
		assume ds:nothing
		pop	dx
		pop	cx
		pop	bx
		pop	ax
		ret
sub_5BF8	endp


; =============== S U B	R O U T	I N E =======================================


CSRATR		proc near
		call	SCRSAV
		or	ah, ah
		jnz	short loc_5C63
		mov	al, ds:var_641
loc_5C63:
		mov	ds:var_641, al
		or	bh, bh
		jnz	short loc_5C6F
		mov	ax, ds:var_643
		mov	bl, ah
loc_5C6F:
		or	ch, ch
		jnz	short loc_5C79
		or	bh, bh
		jz	short GSTCUR
		mov	cl, bl
loc_5C79:
		mov	bh, bl
		mov	bl, cl
		test	bx, 0E0E0h
		jnz	short CSRERR
		mov	ds:var_643, bx
GSTCUR:
		jmp	GOSCUR
; ---------------------------------------------------------------------------

CSRERR:
		jmp	SCNERR
CSRATR		endp


; =============== S U B	R O U T	I N E =======================================


LCPY		proc near
		call	SCRSAV
		int	5		;  - PRINT-SCREEN KEY
					; automatically	called by keyboard scanner when	print-screen key is pressed
		call	SCRRST
LCPY		endp


; =============== S U B	R O U T	I N E =======================================


SCRATR		proc near
		push	ax
		push	cx
		push	dx
		mov	dl, al
		mov	dh, bl
		sub	dx, 101h
		mov	ds:var_64e, dx
		mov	bh, ds:CVPAGE
		mov	ah, 2
		int	10h		; - VIDEO - SET	CURSOR POSITION
					; DH,DL	= row, column (0,0 = upper left)
					; BH = page number
		mov	ah, 8
		int	10h		; - VIDEO - READ ATTRIBUTES/CHARACTER AT CURSOR	POSITION
					; BH = display page
					; Return: AL = character
					; AH = attribute of character (alpha modes)
		mov	bh, 0
		mov	bl, ah
		pop	dx
		pop	cx
		pop	ax
		ret
SCRATR		endp


; =============== S U B	R O U T	I N E =======================================


SCRSTT		proc near
		call	SCRSAV
		mov	cl, [bx]
		cmp	cl, 5
		jnb	short loc_5CD8
		inc	bx
		inc	cl
		push	bx
		push	cx
		mov	dl, ds:var_63a
		call	sub_5E5A
		jbe	short loc_5CDB
		mov	dl, al
		cmp	al, 3
		jb	short loc_5CDB
		pop	ax
		pop	ax
loc_5CD8:
		jmp	SCNERR
; ---------------------------------------------------------------------------

loc_5CDB:
		call	sub_5E5A
		call	sub_5E5A
		jbe	short loc_5CE6
		call	sub_5D8A
loc_5CE6:
		call	sub_5E5A
		jbe	short loc_5CEE
		call	sub_5D8A
loc_5CEE:
		pop	cx
		pop	bx
		mov	ch, ds:CVMODE
		call	sub_5E5A
		jbe	short loc_5D45
		mov	ds:var_63a, al
		mov	byte ptr ds:var_646, 7
		mov	byte ptr ds:var_645, 7
		cmp	al, 0
		jnz	short loc_5D1D
		xor	dx, dx
		mov	word ptr ds:var_64c, dx
		mov	ch, 2
		cmp	byte ptr ds:var_63b, 80
		jz	short loc_5D41
		mov	ch, 0
		jmp	short loc_5D41
; ---------------------------------------------------------------------------

loc_5D1D:
		mov	ch, 4
		mov	byte ptr ds:var_63b, 40
		mov	dx, 320
		mov	word ptr ds:var_64c, 3F02h
		cmp	al, 1
		jz	short loc_5D41
		mov	ch, 6
		mov	byte ptr ds:var_63b, 80
		mov	dx, 640
		mov	word ptr ds:var_64c, 7F01h
loc_5D41:
		mov	ds:var_649, dx
loc_5D45:
		call	sub_5E5A
		jbe	short loc_5D59
		and	ch, 0FEh
		cmp	al, 0
		jz	short loc_5D59
		cmp	ch, 6
		jnb	short loc_5D59
		or	ch, 1
loc_5D59:
		mov	al, ch
		cmp	al, ds:CVMODE
		jz	short loc_5D71
		mov	ah, 0
		int	10h		; - VIDEO - SET	VIDEO MODE
					; AL = mode
		push	bx
		push	cx
		call	SCNRST
		pop	cx
		pop	bx
		mov	byte ptr ds:CVPAGE, 0
loc_5D71:
		call	sub_5E5A
		jbe	short loc_5D79
		mov	ds:CVPAGE, al
loc_5D79:
		call	sub_5E5A
		jz	short loc_5D80
		jnb	short loc_5D83
loc_5D80:
		mov	al, ds:CVPAGE
loc_5D83:
		mov	ah, 5
		int	10h		; - VIDEO - SELECT DISPLAY PAGE
					; AL = display page, 0-7  for modes 0 &	1, 0-3	for modes 2 & 3
		jmp	SCNOK
SCRSTT		endp


; =============== S U B	R O U T	I N E =======================================


sub_5D8A	proc near
		or	dl, dl
		jnz	short loc_5D9E
		mov	ah, 4
		cmp	byte ptr ds:var_63b, 80
		jz	short loc_5D99
		mov	ah, 8
loc_5D99:
		cmp	al, ah
		jnb	short loc_5DA3
		ret
; ---------------------------------------------------------------------------

loc_5D9E:
		cmp	al, 0
		jnz	short loc_5DA3
		ret
; ---------------------------------------------------------------------------

loc_5DA3:
		pop	ax
		pop	ax
		pop	ax
		jmp	SCNERR
sub_5D8A	endp


; =============== S U B	R O U T	I N E =======================================


SETCLR		proc near
		call	SCRSAV
		mov	cl, [bx]
		inc	bx
		inc	cl
		mov	ch, ds:var_646
		mov	al, ds:var_63a
		cmp	al, 0
		jz	short loc_5E08
		cmp	al, 1
		jz	short loc_5DC3
loc_5DC0:
		jmp	SCNERR
; ---------------------------------------------------------------------------

loc_5DC3:
		cmp	cl, 6
		jnb	short loc_5DC0
		call	sub_5E5A
		jbe	short loc_5DDF
		push	bx
		cmp	al, 10h
		jb	short loc_5DD6
		and	al, 0Fh
		or	al, 10h
loc_5DD6:
		mov	bl, al
		mov	bh, 0
		mov	ah, 0Bh
		int	10h		; - VIDEO - SET	COLOR PALETTE
					; BH = 00h, BL = border	color
					; BH = 01h, BL = palette (0-3)
		pop	bx
loc_5DDF:
		xor	dx, dx
		call	sub_5E5A
		jbe	short loc_5DEA
		mov	dl, al
		mov	dh, 1
loc_5DEA:
		call	sub_5E5A
		jbe	short loc_5DF3
		mov	dl, al
		mov	dh, 1
loc_5DF3:
		call	sub_5E5A
		jbe	short loc_5DFC
		mov	dl, al
		mov	dh, 1
loc_5DFC:
		or	dh, dh
		jz	short loc_5E4C
		mov	al, dl
		and	al, 1
		mov	bh, 1
		jmp	short loc_5E46
; ---------------------------------------------------------------------------

loc_5E08:
		cmp	cl, 5
		jnb	short SETERR
		call	sub_5E5A
		jbe	short loc_5E23
		cmp	al, 20h	; ' '
		jnb	short SETERR
		test	al, 10h
		jz	short loc_5E1E
		and	al, 0Fh
		or	al, 80h
loc_5E1E:
		and	ch, 70h
		or	ch, al
loc_5E23:
		call	sub_5E5A
		jbe	short loc_5E3B
		cmp	al, 10h
		jnb	short SETERR
		and	al, 7
		shl	al, 1
		shl	al, 1
		shl	al, 1
		shl	al, 1
		and	ch, 8Fh
		or	ch, al
loc_5E3B:
		call	sub_5E5A
		jbe	short loc_5E4C
		cmp	al, 10h
		jnb	short SETERR
		mov	bh, 0
loc_5E46:
		mov	bl, al
		mov	ah, 0Bh
		int	10h		; - VIDEO - SET	COLOR PALETTE
					; BH = 00h, BL = border	color
					; BH = 01h, BL = palette (0-3)
loc_5E4C:
		mov	ds:var_646, ch
		mov	ds:var_645, ch
		jmp	SCNOK
; ---------------------------------------------------------------------------

SETERR:
		jmp	SCNERR
SETCLR		endp


; =============== S U B	R O U T	I N E =======================================


sub_5E5A	proc near
		dec	cl
		jz	short loc_5E67
		mov	ax, [bx]
		inc	bx
		inc	bx
		or	al, al
		xchg	ah, al
		ret
; ---------------------------------------------------------------------------

loc_5E67:
		inc	cl
		stc
		ret
sub_5E5A	endp


; =============== S U B	R O U T	I N E =======================================

; Machine specific routine to set screen width
; Height in [AL], width	in [CL]

SWIDTH		proc near
		call	SCRSAV
		mov	bx, offset MODES40
		cmp	al, 40		; Is the mode 40 characters wide?
		jz	short WIDE40
		cmp	al, 80		; Or is	it 80 wide?
		mov	bx, offset MODES80
		jnz	short SETERR	; If not 40 or 80 columns, error
		mov	ds:var_63b, al
		mov	dx, 640
		mov	al, 2
		mov	word ptr ds:var_64c, 7F01h
		jmp	short loc_5EA1
; ---------------------------------------------------------------------------

WIDE40:
		cmp	byte ptr ds:CVMODE, 7
		jz	short SCNOK
		mov	ds:var_63b, al
		mov	dx, 320
		mov	al, 1
		mov	word ptr ds:var_64c, 3F02h
loc_5EA1:
		cmp	byte ptr ds:var_63a, 0
		jz	short loc_5EAF
		mov	ds:var_63a, al
		mov	ds:var_649, dx
loc_5EAF:
		mov	al, ds:CVMODE
		mov	ah, 0
		add	bx, ax
		mov	al, cs:[bx]
		mov	ah, 0
		cmp	al, ds:CVMODE
		jz	short SCNOK
		int	10h		; - VIDEO - SET	VIDEO MODE
					; AL = mode
		call	SCNRST
		xor	ax, ax
		mov	ds:CVPAGE, al
		cmp	byte ptr ds:var_63a, 2
		jz	short SCNOK
		mov	ah, 0Bh
		xor	bx, bx
		int	10h		; - VIDEO - SET	COLOR PALETTE
					; BH = 00h, BL = border	color
					; BH = 01h, BL = palette (0-3)

SCNOK:
		clc
GOSRST:
		jmp	SCRRST
SWIDTH		endp

; ---------------------------------------------------------------------------
; START	OF FUNCTION CHUNK FOR sub_5D8A

SCNERR:
		stc
		jmp	short GOSRST
; END OF FUNCTION CHUNK	FOR sub_5D8A
; ---------------------------------------------------------------------------

PUBLIC  FKYFMT, FKYADV, STOREC, FETCHC
PUBLIC  RIGHTC, LEFTC, UPC, DOWNC
PUBLIC  SCALXY, MAPXYC, SETATR, READC, SETC, NSETCX
PUBLIC  GTASPC, PIXSIZ
PUBLIC  TUPC, TDOWNC, PGINIT, NREAD, NWRITE
PUBLIC  PNTINI, SCANR, SCANL

MODES40		db    0
		db    1
		db    0
		db    1
		db    4
		db    5
		db    5
		db    7
MODES80		db    2
		db    3
		db    2
		db    3
		db    6
		db    6
		db    6
		db    7

; =============== S U B	R O U T	I N E =======================================


FKYFMT		proc near
		mov	bx, offset var_652
		cmp	byte ptr ds:var_63b, 40 ; 40 wide?
		jz	short FKYFMX
		mov	bx, offset var_655
FKYFMX:
		ret
FKYFMT		endp


; =============== S U B	R O U T	I N E =======================================


FKYADV		proc near
		or	sp, sp
		ret
FKYADV		endp


; =============== S U B	R O U T	I N E =======================================


STOREC		proc near
		mov	ds:var_64b, al
		mov	ds:var_647, bx
		ret
STOREC		endp


; =============== S U B	R O U T	I N E =======================================


FETCHC		proc near
		mov	al, ds:var_64b
		mov	bx, ds:var_647
		ret
FETCHC		endp


; =============== S U B	R O U T	I N E =======================================


RIGHTC		proc near
		push	cx
		mov	cl, ds:var_64c
		ror	byte ptr ds:var_64b, cl
		jb	short RGHTCX
		inc	word ptr ds:var_647
RGHTCX:
		pop	cx
		ret
RIGHTC		endp


; =============== S U B	R O U T	I N E =======================================


LEFTC		proc near
		push	cx
		mov	cl, ds:var_64c
		rol	byte ptr ds:var_64b, cl
		jb	short LEFTCX
		dec	word ptr ds:var_647
LEFTCX:
		pop	cx
		ret
LEFTC		endp

; ---------------------------------------------------------------------------
; START	OF FUNCTION CHUNK FOR TUPC

UPC:
		mov	ax, 2000h
		cmp	ax, ds:var_647
		jbe	short loc_5F43
		sub	ax, 80
		add	ds:var_647, ax
		ret
; ---------------------------------------------------------------------------

loc_5F43:
		sub	ds:var_647, ax
		ret
; END OF FUNCTION CHUNK	FOR TUPC

; =============== S U B	R O U T	I N E =======================================


DOWNC		proc near
		mov	ax, 2000h
		cmp	ax, ds:var_647
		jbe	short DOWNCX
		add	ds:var_647, ax
		ret
; ---------------------------------------------------------------------------

DOWNCX:
		sub	ax, 80
		sub	ds:var_647, ax
		ret
DOWNC		endp


; =============== S U B	R O U T	I N E =======================================


SCALXY		proc near
		or	ch, ch
		js	short loc_5F7D
		mov	bx, ds:var_649
		cmp	cx, bx
		lahf
		jb	short loc_5F6E
		mov	cx, bx
		dec	cx
loc_5F6E:
		or	dh, dh
		js	short loc_5F82
		mov	bx, 200
		cmp	dx, bx
		jb	short loc_5F85
		mov	dx, bx
		dec	dx
		ret
; ---------------------------------------------------------------------------

loc_5F7D:
		xor	cx, cx
		lahf
		jmp	short loc_5F6E
; ---------------------------------------------------------------------------

loc_5F82:
		xor	dx, dx
		ret
; ---------------------------------------------------------------------------

loc_5F85:
		sahf
		ret
SCALXY		endp


; =============== S U B	R O U T	I N E =======================================


MAPXYC		proc near
		mov	ax, cx
		mov	cl, ds:var_63a
		inc	cl
		ror	ax, cl
		push	ax
		rol	ah, cl
		mov	ch, ah
		xor	si, si
		mov	ax, dx
		shr	ax, 1
		jnb	short loc_5FA1
		mov	si, 2000h
loc_5FA1:
		mov	cl, 80
		mul	cl
		pop	dx
		mov	dh, 0
		add	ax, dx
		add	si, ax
		mov	ds:var_647, si
		mov	cl, ds:var_64c
		dec	cl
		shl	ch, cl
		mov	cl, ch
		mov	al, ds:var_64d
		ror	al, cl
		mov	ds:var_64b, al
		ret
MAPXYC		endp


; =============== S U B	R O U T	I N E =======================================


SETATR		proc near
		cmp	al, 4
		jnb	short STATRX
		mov	ds:var_660, al
STATRX:
		clc
		ret
SETATR		endp


; =============== S U B	R O U T	I N E =======================================


READC		proc near
		mov	si, ds:var_647
		push	ds
		mov	ax, 0B800h
		mov	ds, ax
		assume ds:nothing
		mov	al, [si]
		pop	ds
		assume ds:nothing
		mov	ah, ds:var_64b
		not	ah
		and	al, ah
		mov	cl, ds:var_64c
RDCLOP:
		rol	ax, cl
		jnb	short RDCLOP
		mov	al, ah
		ret
READC		endp


; =============== S U B	R O U T	I N E =======================================


SETC		proc near
		push	cx
		push	ds
		call	SETPTR
		and	[si], ch
		or	[si], al
		pop	ds
		pop	cx
		ret
SETC		endp


; =============== S U B	R O U T	I N E =======================================

; Set DS:SI to point at	current	"C"

SETPTR		proc near
		mov	ah, ds:var_64b
		mov	ch, ah
		mov	al, ds:var_660
		cmp	byte ptr ds:var_63a, 1
		jz	short loc_600A
		and	al, 1
loc_600A:
		mov	cl, ds:var_64c
loc_600E:
		ror	al, cl
		rol	ah, cl
		jb	short loc_600E
		mov	si, 0B800h
		push	si
		mov	si, ds:var_647
		pop	ds
		ret
SETPTR		endp


; =============== S U B	R O U T	I N E =======================================


NSETCX		proc near
		push	ds
		call	SETPTR
		test	ch, 80h
		jz	short loc_6035
loc_6027:
		dec	bx
		js	short loc_606B
		and	[si], ch
		or	[si], al
		ror	al, cl
		ror	ch, cl
		jb	short loc_6027
		inc	si
loc_6035:
		push	cx
		push	ax
		mov	dx, 7
		mov	ah, al
loc_603C:
		ror	al, cl
		or	ah, al
		dec	dx
		jnz	short loc_603C
		mov	al, ah
		mov	cl, es:var_63a
		ror	bx, cl
		ror	bx, 1
		ror	bx, 1
		jmp	short loc_6056
; ---------------------------------------------------------------------------

loc_6052:
		mov	[si], ax
		inc	si
		inc	si
loc_6056:
		dec	bl
		jns	short loc_6052
		shl	bh, 1
		jnb	short loc_6061
		mov	[si], al
		inc	si
loc_6061:
		mov	bl, 0
		rol	bx, cl
		rol	bx, 1
		pop	ax
		pop	cx
		jmp	short loc_6027
; ---------------------------------------------------------------------------

loc_606B:
		pop	ds
		ret
NSETCX		endp


; =============== S U B	R O U T	I N E =======================================

; Get screen aspect ratio

GTASPC		proc near
		mov	bx, 213		; FP number!
		mov	dx, 307
		cmp	byte ptr ds:var_63a, 1
		jz	short GTASPX
		mov	bx, 107		; FP number!
		mov	dx, 615
GTASPX:
		ret
GTASPC		endp


; =============== S U B	R O U T	I N E =======================================


PIXSIZ		proc near
		mov	al, ds:var_64c
		ret
PIXSIZ		endp


; =============== S U B	R O U T	I N E =======================================


TUPC		proc near
		cmp	word ptr ds:var_647, 4Fh
		jbe	short TUPCX
		jmp	UPC
; ---------------------------------------------------------------------------

TUPCX:
		stc
		ret
TUPC		endp


; =============== S U B	R O U T	I N E =======================================


TDOWNC		proc near
		cmp	word ptr ds:var_647, 3EF0h
		jnb	short TUPCX
		jmp	DOWNC
TDOWNC		endp

; ---------------------------------------------------------------------------
PGDISP		dw offset FNOR
		dw offset FNAND
		dw offset FNINV
		dw offset FNSET
		dw offset FNXOR

; =============== S U B	R O U T	I N E =======================================


PGINIT		proc near
		lahf
		mov	ds:var_661, bx
		push	cx
		shr	cx, 1
		shr	cx, 1
		shr	cx, 1
		mov	ds:var_663, cx
		pop	cx
		and	cl, 7
		mov	ch, 8
		sub	ch, cl
		and	ch, 7
		mov	WORD PTR ds:var_665, cx
		sahf
		jnb	short PGINIX
		cmp	al, 5
		jnb	short PGINIX
		mov	bx, offset PGDISP
		mov	ah, 0
		shl	al, 1
		add	bx, ax
		mov	ax, cs:[bx]
		mov	ds:var_667, ax
PGINIX:
		ret
PGINIT		endp


; =============== S U B	R O U T	I N E =======================================


NREAD		proc near
		push	ds
		mov	di, ds:var_661
		mov	bx, ds:var_663
		call	SETPTR
		mov	dh, [si]
		mov	ah, 0
loc_60EC:
		test	ch, 80h
		jz	short loc_60F9
		rol	ch, cl
		shl	dh, cl
		add	ah, cl
		jmp	short loc_60EC
; ---------------------------------------------------------------------------

loc_60F9:
		mov	cl, ah
		jmp	short loc_6103
; ---------------------------------------------------------------------------

loc_60FD:
		mov	es:[di], dh
		inc	di
		mov	dh, al
loc_6103:
		inc	si
		mov	al, [si]
		mov	ah, bh
		shl	ax, cl
		or	dh, ah
		dec	bl
		jns	short loc_60FD
		mov	cl, es:var_666
		or	cl, cl
		jz	short NREADX
		shr	dh, cl
		shl	dh, cl
		mov	es:[di], dh
		inc	di
NREADX:
		pop	ds
		mov	ds:var_661, di
		ret
NREAD		endp


; =============== S U B	R O U T	I N E =======================================


NWRITE		proc near
		push	ds
		mov	di, ds:var_661
		mov	bx, ds:var_663
		call	SETPTR
		mov	dx, [si]
		mov	ah, 0

loc_6137:
		test	ch, 80h
		jz	short loc_6144
		rol	ch, cl
		rol	dx, cl
		add	ah, cl
		jmp	short loc_6137
; ---------------------------------------------------------------------------

loc_6144:
		mov	cl, ah
		jmp	short loc_6153
; ---------------------------------------------------------------------------

loc_6148:
		mov	[si], dl
		inc	si
		mov	dl, dh
		inc	si
		mov	dh, [si]
		dec	si
		rol	dx, cl
loc_6153:
		mov	al, es:[di]
		inc	di
		call	word ptr es:var_667
		ror	dx, cl
		dec	bl
		jns	short loc_6148
		mov	bl, es:var_665
		or	bl, bl
		jnz	short loc_6172
		dec	di
		or	cl, cl
		jz	short loc_6199
		jmp	short loc_6183
; ---------------------------------------------------------------------------

loc_6172:
		add	cl, bl
		cmp	cl, 8
		jb	short loc_6183
		mov	[si], dl
		jz	short loc_6199
		inc	si
		mov	dl, dh
		sub	cl, 8
loc_6183:
		mov	al, [si]
		shl	al, cl
		shr	al, cl
		mov	dh, al
		mov	ch, 8
		sub	ch, cl
		mov	cl, ch
		shr	dl, cl
		shl	dl, cl
		or	dh, dl
		mov	[si], dh
loc_6199:
		pop	ds
		mov	ds:var_661, di
		ret
NWRITE		endp

; ---------------------------------------------------------------------------

FNOR:
		or	dl, al
		ret
; ---------------------------------------------------------------------------

FNAND:
		and	dl, al
		ret
; ---------------------------------------------------------------------------

FNINV:
		xor	al, 0FFh

FNSET:
		mov	dl, al
		ret
; ---------------------------------------------------------------------------

FNXOR:
		xor	dl, al
		ret

; =============== S U B	R O U T	I N E =======================================


PNTINI		proc near
		cmp	al, 4
		jb	short PNTINX
		mov	al, 0
PNTINX:
		mov	ds:var_669, al
		clc
		ret
PNTINI		endp


; =============== S U B	R O U T	I N E =======================================


SCANR		proc near
		push	ds
		mov	di, dx
		call	SETPTR
		call	sub_6262
		sub	bl, ah
		mov	dl, bl
		mov	ah, [si]
		push	cx
loc_61C8:
		ror	ah, cl
		ror	ch, cl
		jb	short loc_61C8
		pop	cx
		mov	bl, 0
		mov	bh, es:var_669
		cmp	byte ptr es:var_63a, 1
		jz	short loc_61E1
		and	bh, 1
loc_61E1:
		mov	al, bl
		rol	ax, cl
		cmp	al, bh
		jnz	short loc_61FF
		dec	di
		jz	short loc_61F7
		ror	ch, cl
		jb	short loc_61E1
		inc	si
		mov	ah, [si]
		dec	dl
		jnz	short loc_61E1
loc_61F7:
		xor	bx, bx
		mov	dx, bx
		mov	cl, dl
		pop	ds
		ret
; ---------------------------------------------------------------------------

loc_61FF:
		mov	es:CSAVEA, si
		mov	BYTE PTR es:CSAVEM, ch
		push	di
		mov	dh, es:var_660
		mov	bl, dh
		push	cx
		cmp	byte ptr es:var_63a, 1
		jz	short loc_6223
		and	dh, 1
		mov	bl, dh
		jmp	short loc_6223
; ---------------------------------------------------------------------------

loc_6221:
		rol	dh, cl
loc_6223:
		ror	ch, cl
		jb	short loc_6221
		pop	cx
		xor	di, di
		jmp	short loc_6234
; ---------------------------------------------------------------------------

loc_622C:
		mov	al, 0
		rol	ax, cl
		cmp	al, bh
		jz	short loc_624F
loc_6234:
		cmp	al, bl
		jz	short loc_623E
		and	[si], ch
		or	[si], dh
		mov	bl, 0FFh
loc_623E:
		inc	di
		ror	dh, cl
		ror	ch, cl
		jb	short loc_622C
		inc	si
		mov	ah, [si]
		dec	dl
		jnz	short loc_622C
		rol	ch, cl
		dec	si
loc_624F:
		pop	dx
		inc	bl
		jz	short loc_6256
		mov	cl, 0
loc_6256:
		mov	bx, di
		pop	ds
		mov	ds:var_647, si
		mov	ds:var_64b, ch
		ret
SCANR		endp


; =============== S U B	R O U T	I N E =======================================


sub_6262	proc near
		mov	ax, si
		mov	bx, 2000h
		cmp	ax, bx
		jb	short loc_626D
		sub	ax, bx
loc_626D:
		mov	bl, 80
		div	bl
		ret
sub_6262	endp


; =============== S U B	R O U T	I N E =======================================


SCANL		proc near
		push	ds
		call	SETPTR
		mov	dh, al
		call	sub_6262
		mov	dl, ah
		mov	ah, [si]
		push	cx
loc_6280:
		ror	ah, cl
		ror	ch, cl
		jb	short loc_6280
		pop	cx
		mov	bl, es:var_660
		mov	bh, es:var_669
		cmp	byte ptr es:var_63a, 1
		jz	short loc_629D
		and	bx, 101h
loc_629D:
		ror	bh, cl
		ror	bl, cl
		xor	di, di
		jmp	short loc_62B8
; ---------------------------------------------------------------------------

loc_62A5:
		mov	al, 0
		ror	ax, cl
		cmp	al, bh
		jz	short loc_62C5
		cmp	al, bl
		jz	short loc_62B7
		and	[si], ch
		or	[si], dh
		mov	bl, -1
loc_62B7:
		inc	di
loc_62B8:
		rol	dh, cl
		rol	ch, cl
		jb	short loc_62A5
		dec	si
		mov	ah, [si]
		dec	dl
		jns	short loc_62A5
loc_62C5:
		mov	al, bl
		mov	bx, di
		or	bx, bx
		jnz	short loc_62D1
		mov	cl, 0
		pop	ds
		ret
; ---------------------------------------------------------------------------

loc_62D1:
		ror	ch, cl
		jb	short loc_62D6
		inc	si
loc_62D6:
		inc	al
		jz	short loc_62DC
		mov	cl, 0
loc_62DC:
		pop	ds
		mov	ds:var_64b, ch
		mov	ds:var_647, si
		ret
SCANL		endp

; ---------------------------------------------------------------------------
; Start of another module?
;		align 10h

PUBLIC  RDPEN, RDTRIG, RDSTIK, POLLEV

ISREVT		db 0
LPWSDN		dw 0
LPLGX		dw 0
LPLGY		dw 0
LPDOWN		dw 0                    ; -1 if	currently down,	0 if up
LPGX		dw 0
LPGY		dw 0
LPROW		dw 1
LPCOL		dw 1
LPLROW		dw 1
LPLCOL		dw 1

; =============== S U B	R O U T	I N E =======================================


LPENQR		proc near
		push	ds
		push	cs
		pop	ds
		assume ds:CSEG
		push	ax
		push	bx
		push	cx
		push	dx
		mov	ah, 4
		int	10h		; - VIDEO - READ LIGHT PEN POSITION (all but PS)
					; Return: AH = 00h light pen switch not	activated
					; AH = 01h light pen values in registers
					; DH,DL	= row,columnCH = raster	line (0-199) (EGA) old graphics	modes
					; CX = (EGA) raster line
					; BX = pixel column
		or	ah, ah
		jz	short NOSWIT
		mov	LPGX, bx
		inc	dh
		mov	byte ptr LPLROW, dh
		inc	dl
		mov	byte ptr LPLCOL, dl
		mov	byte ptr LPGY, ch
		cmp	LPDOWN,	-1
		jz	short LPENQX
		mov	ISREVT,	1
		mov	ax, -1
		mov	LPDOWN,	ax
		mov	LPWSDN,	ax
		mov	LPLGX, bx
		mov	byte ptr LPLGY,	ch
		mov	byte ptr LPROW,	dh
		mov	byte ptr LPCOL,	dl
LPENQX:
		pop	dx
		pop	cx
		pop	bx
		pop	ax
		pop	ds
		assume ds:nothing
		ret
; ---------------------------------------------------------------------------

NOSWIT:
		mov	ds:LPDOWN, 0
		jmp	short LPENQX
LPENQR		endp


; =============== S U B	R O U T	I N E =======================================

; Light	pen control via	[AL]
;  -2: Pen ON
;  -1: Pen OFF
;   0: Return -1 if pen	was down since last poll, else 0.
;   1: Return X	Graphics Coordinate where pen was last activated.
;   2: Return Y	Graphics Coordinate where pen was last activated.
;   3: Return -1 if pen	is currently down, 0 if	currently up.
;   4: Return last known valid X Graphics Coordinate.
;   5: Return last known valid Y Graphics Coordinate.
;   6: Return character	row where pen was last activated.
;   7: Return character	column where pen was last activated.
;   8: Return last known character row.
;   9: Return last known character column.

RDPEN		proc near
		push	ds
		push	cs
		pop	ds
		assume ds:CSEG
		or	al, al
		js	short LPNOFF
		push	si
		shl	al, 1
		mov	ah, 0
		mov	si, offset LPWSDN
		add	si, ax
		mov	bx, cs:[si]
		or	ax, ax
		jnz	short RDPENX
		mov	LPWSDN,	ax	; Not down since last poll
RDPENX:
		pop	si
		pop	ds
		assume ds:nothing
		ret
; ---------------------------------------------------------------------------

LPNOFF:
		cmp	al, -2		; Or should it be ON?
		jz	short LPNON
		and	ds:EVTSET, 0FEh	; Disable light	pen reading
		pop	ds
		ret
; ---------------------------------------------------------------------------

LPNON:
		or	ds:EVTSET, 1	; Enable light pen reading
		xor	ax, ax
		mov	ds:LPDOWN, ax
		mov	ds:LPWSDN, ax	; Not down since last poll
		pop	ds
		ret
RDPEN		endp


; =============== S U B	R O U T	I N E =======================================


RDTRIG		proc near
		push	dx
		push	cx
		xor	cx, cx
		mov	cl, al
		cmp	al, 1
		jnz	short loc_639F
		mov	cl, 2
loc_639F:
		cmp	al, 2
		jnz	short loc_63A5
		mov	cl, 1
loc_63A5:
		add	cl, 4
		mov	dx, 201h
		in	al, dx		; Game I/O port
					; bits 0-3: Coordinates	(resistive, time-dependent inputs)
					; bits 4-7: Buttons/Triggers (digital inputs)
		not	al
		ror	al, cl
		and	al, 1
		or	ah, ah
		jz	short RDTRGX
		sti
		mov	al, cs:LSTRIG
		ror	al, cl
		mov	ch, al
		and	al, 0FEh
		rol	al, cl
		mov	cs:LSTRIG, al
		mov	al, ch
		and	al, 1
		cli
RDTRGX:
		pop	cx
		pop	dx
		ret
RDTRIG		endp


; =============== S U B	R O U T	I N E =======================================


RDSTIK		proc near
		push	ax
		push	cx
		push	dx
		cmp	al, 4
		cmc
		jb	short RDSTKX
		mov	cl, al
		mov	al, 1
		shl	al, cl
		mov	cl, al
		xor	bx, bx
		mov	dx, 201h
		in	al, dx		; Game I/O port
					; bits 0-3: Coordinates	(resistive, time-dependent inputs)
					; bits 4-7: Buttons/Triggers (digital inputs)
		and	al, cl
		jnz	short RDSTKX
		dec	bx
		dec	bx
		cli
		out	dx, al		; Game I/O port
					; bits 0-3: Coordinates	(resistive, time-dependent inputs)
					; bits 4-7: Buttons/Triggers (digital inputs)
RDSTLP:
		inc	bx
		in	al, dx		; Game I/O port
					; bits 0-3: Coordinates	(resistive, time-dependent inputs)
					; bits 4-7: Buttons/Triggers (digital inputs)
		and	al, cl
		jnz	short RDSTLP
		sti
RDSTKX:
		pop	dx
		pop	cx
		pop	ax
		ret
RDSTIK		endp


; =============== S U B	R O U T	I N E =======================================


POLLEV		proc near
		cld
		cli
		cmp	cs:ISREVT, 0	; Light	pen event?
		mov	cs:ISREVT, 0
		sti
		jnz	short POLEVX
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		mov	ax, ds:41Ah	; Next keyboard	buffer item
		cmp	ax, ds:41Ch	; Last keyboard	buffer item
		pop	ds
		assume ds:nothing
POLEVX:
		ret
POLLEV		endp

; ---------------------------------------------------------------------------
; Start of another module?
;		align 10h

PUBLIC  DONOTE

NTARRY		db 84h dup(0)
CURNOT		dw 0
NOTPTR		dw 0
		db 0            ; Unused?
		db 0
byte_64AA	db 0
word_64AB	dw 0

byte_64AD	db 0
ISRCNT		db 0            ; Timer	ISR entry counter. Because the timer ticks
				; faster, only chain to	the previous handler when
				; the counter goes to zero.
OLDTMI		dd 0            ; Previous timer interrupt vector

; =============== S U B	R O U T	I N E =======================================


TMRISR		proc far
		push	ax
		push	bx
		push	dx
		push	si
		push	ds
		push	cs
		pop	ds
		assume ds:CSEG
		test	EVTSET,	2	; Speaker on?
		jnz	short TMRIS1	; If not, turn it off now
		in	al, 61h		; PC/XT	PPI port B bits:
					; 0: Tmr 2 gate	��� OR	03H=spkr ON
					; 1: Tmr 2 data	ͼ  AND	0fcH=spkr OFF
					; 3: 1=read high switches
					; 4: 0=enable RAM parity checking
					; 5: 0=enable I/O channel check
					; 6: 0=hold keyboard clock low
					; 7: 0=enable kbrd
		and	al, 0FDh
		out	61h, al		; PC/XT	PPI port B bits:
					; 0: Tmr 2 gate	��� OR	03H=spkr ON
					; 1: Tmr 2 data	ͼ  AND	0fcH=spkr OFF
					; 3: 1=read high switches
					; 4: 0=enable RAM parity checking
					; 5: 0=enable I/O channel check
					; 6: 0=hold keyboard clock low
					; 7: 0=enable kbrd
TMRIS1:
		sti
		test	EVTSET,	2	; Speaker on?
		jz	short loc_64EC
		mov	byte_64AD, 2
		cmp	word_64AB, 0
		jnz	short loc_64EF
		cmp	byte_64AA, 0
		jnz	short loc_64EF
		mov	si, CURNOT
		cmp	si, NOTPTR
		jnz	short loc_6514
loc_64EC:
		jmp	short loc_6564
loc_64EF:
		dec	word_64AB
		jnz	short loc_6564
		dec	byte_64AA
		jns	short loc_6564
		mov	si, CURNOT
		cmp	si, NOTPTR
		jnz	short loc_6518
		and	EVTSET,	0FDh	; Clear	speaker	event bit
		cli
		in	al, 61h		; PC/XT	PPI port B bits:
					; 0: Tmr 2 gate	��� OR	03H=spkr ON
					; 1: Tmr 2 data	ͼ  AND	0fcH=spkr OFF
					; 3: 1=read high switches
					; 4: 0=enable RAM parity checking
					; 5: 0=enable I/O channel check
					; 6: 0=hold keyboard clock low
					; 7: 0=enable kbrd
		and	al, 0FDh
		out	61h, al		; PC/XT	PPI port B bits:
					; 0: Tmr 2 gate	��� OR	03H=spkr ON
					; 1: Tmr 2 data	ͼ  AND	0fcH=spkr OFF
					; 3: 1=read high switches
					; 4: 0=enable RAM parity checking
					; 5: 0=enable I/O channel check
					; 6: 0=hold keyboard clock low
					; 7: 0=enable kbrd
		sti
		jmp	short loc_6564
; ---------------------------------------------------------------------------

loc_6514:
		mov	al, 0B6h
		out	43h, al		; Timer	8253-5 (AT: 8254.2).
loc_6518:
		mov	bx, offset NTARRY
		mov	ax, [bx+si]
		or	ax, ax
		jnz	short loc_6528
		cli
		in	al, 61h		; PC/XT	PPI port B bits:
					; 0: Tmr 2 gate	��� OR	03H=spkr ON
					; 1: Tmr 2 data	ͼ  AND	0fcH=spkr OFF
					; 3: 1=read high switches
					; 4: 0=enable RAM parity checking
					; 5: 0=enable I/O channel check
					; 6: 0=hold keyboard clock low
					; 7: 0=enable kbrd
		and	al, 0FDh
		jmp	short loc_6533
; ---------------------------------------------------------------------------

loc_6528:
		out	42h, al		; Timer	8253-5 (AT: 8254.2).
		mov	al, ah
		out	42h, al		; Timer	8253-5 (AT: 8254.2).
		cli
		in	al, 61h		; PC/XT	PPI port B bits:
					; 0: Tmr 2 gate	��� OR	03H=spkr ON
					; 1: Tmr 2 data	ͼ  AND	0fcH=spkr OFF
					; 3: 1=read high switches
					; 4: 0=enable RAM parity checking
					; 5: 0=enable I/O channel check
					; 6: 0=hold keyboard clock low
					; 7: 0=enable kbrd
		or	al, 3
loc_6533:
		out	61h, al		; PC/XT	PPI port B bits:
					; 0: Tmr 2 gate	��� OR	03H=spkr ON
					; 1: Tmr 2 data	ͼ  AND	0fcH=spkr OFF
					; 3: 1=read high switches
					; 4: 0=enable RAM parity checking
					; 5: 0=enable I/O channel check
					; 6: 0=hold keyboard clock low
					; 7: 0=enable kbrd
		sti
		inc	si
		inc	si
		mov	ax, [bx+si]
		inc	si
		inc	si
		call	NXTNOT
		mov	CURNOT,	si
		mov	bx, 5958
		mul	bx
		mov	bl, 0
		shl	ax, 1
		rcl	dx, 1
		shl	ax, 1
		rcl	dx, 1
		shl	ax, 1
		rcl	dx, 1
		shl	ax, 1
		rcl	dx, 1
		rcl	bx, 1
		mov	byte_64AA, bl
		mov	word_64AB, dx
loc_6564:
		dec	ISRCNT
		jns	short CHKSTP
		mov	ax, 2048	; 65536/32
		out	40h, al		; Timer	8253-5 (AT: 8254.2).
		mov	al, ah
		out	40h, al		; Timer	8253-5 (AT: 8254.2).
		jmp	short TMRRST
; ---------------------------------------------------------------------------

CHKSTP:
		jnz	short TMRISX
		test	EVTSET,	2	; Speaker still	on?
		jnz	short TMRRST	; If so, keep going.
		dec	byte_64AD
		jnz	short TMRRST
		xor	ax, ax		; Reset	timer interval to normal
		out	40h, al		; Timer	8253-5 (AT: 8254.2).
		out	40h, al		; Timer	8253-5 (AT: 8254.2).
		lds	dx, OLDTMI	; Restore old interrupt	vector
		assume ds:nothing
		push	ds
		mov	ds, ax
		assume ds:nothing
		mov	ds:20h,	dx
		pop	ax
		mov	ds:22h,	ax
		jmp	short TMRCHN
; ---------------------------------------------------------------------------

TMRRST:
		mov	ds:ISRCNT, 32	; Timer	ticks 32x faster; restart period.
TMRCHN:
		pop	ds
		assume ds:nothing
		pop	si
		pop	dx
		pop	bx
		pop	ax
		jmp	cs:OLDTMI	; Chain	to previous timer ISR
; ---------------------------------------------------------------------------

TMRISX:
		pop	ds
		pop	si
		pop	dx
		pop	bx
		mov	al, 20h		; Send EOI
		out	20h, al		; Interrupt controller,	8259A.
		pop	ax
		iret
TMRISR		endp


; =============== S U B	R O U T	I N E =======================================

; Queues note for execution, saves all regs.
; On entry:
;   AL = voice (0=foreground, 1=back, -1=off)
;   CX = frequency
;   DX = duration (1=18.7ms)
;

DONOTE		proc near
		push	ds
		push	bx
		push	si
		push	cs
		pop	ds
		assume ds:CSEG
		cmp	al, -1		; Note off?
		jnz	short DOPLAY
		test	EVTSET,	2	; Speaker on?
		jz	short DONOTX
		cli
		mov	bx, NOTPTR
		mov	CURNOT,	bx
		and	EVTSET,	0FDh	; Clear	event bit
		in	al, 61h		; PC/XT	PPI port B bits:
					; 0: Tmr 2 gate	��� OR	03H=spkr ON
					; 1: Tmr 2 data	ͼ  AND	0fcH=spkr OFF
					; 3: 1=read high switches
					; 4: 0=enable RAM parity checking
					; 5: 0=enable I/O channel check
					; 6: 0=hold keyboard clock low
					; 7: 0=enable kbrd
		and	al, 0FDh
		out	61h, al		; PC/XT	PPI port B bits:
					; 0: Tmr 2 gate	��� OR	03H=spkr ON
					; 1: Tmr 2 data	ͼ  AND	0fcH=spkr OFF
					; 3: 1=read high switches
					; 4: 0=enable RAM parity checking
					; 5: 0=enable I/O channel check
					; 6: 0=hold keyboard clock low
					; 7: 0=enable kbrd
		sti
DONOTX:
		clc
		pop	si
		pop	bx
		pop	ds
		assume ds:nothing
		ret
; ---------------------------------------------------------------------------

DOPLAY:
		push	ax
		push	dx
		mov	ax, 19
		cmp	ax, cx
		jb	short DODIV
		xor	ax, ax
		jmp	short NXNOTE
; ---------------------------------------------------------------------------

DODIV:
		mov	dx, 12h
		mov	ax, 34DCh
		div	cx		; Divide 1,193,180 by CX
NXNOTE:
		push	ax
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		mov	bx, 471h	; Ctrl+Break flag
		mov	[bx], al	; Zero out the flag
		pop	ds
		assume ds:nothing
		mov	si, ds:NOTPTR
		push	si
		add	si, 4
		call	NXTNOT
WAITLP:
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		mov	bx, 471h	; Ctrl+Break flag
		cmp	al, [bx]	; Break	flag set?
		pop	ds
		assume ds:nothing
		jnz	short WTDONE
		cmp	si, ds:CURNOT
		jz	short WAITLP
WTDONE:
		pop	si
		pop	ax
		mov	bx, offset NTARRY
		mov	[bx+si], ax
		inc	si
		inc	si
		pop	ax
		mov	[bx+si], ax
		inc	si
		inc	si
		call	NXTNOT
		mov	ds:NOTPTR, si
		mov	si, ax
		cli
		test	ds:EVTSET, 2	; Speaker on?
		jnz	short TMISON
		mov	ax, 1
		mov	ds:word_64AB, ax
		dec	ax
		mov	ds:byte_64AA, al
		cmp	al, ds:ISRCNT	; Is the timer ISR still going?
		jnz	short TMISON	; If yes, no need to install ISR
		dec	ds:ISRCNT	; ISRCNT was 0,	now -1
		push	es
		push	ds
		mov	ds, ax
		assume ds:nothing
		les	ax, DWORD PTR DS:[20h]	; Install timer	ISR (IRQ0, vector 08h)
		mov	dx, offset TMRISR
		mov	ds:20h,	dx
		push	cs
		pop	dx
		mov	ds:22h,	dx
		pop	ds
		assume ds:nothing
		mov	word ptr ds:OLDTMI, ax
		mov	ax, es
		mov	word ptr ds:OLDTMI+2, ax
		pop	es
		mov	al, 0B6h
		out	43h, al		; Timer	8253-5 (AT: 8254.2).
TMISON:
		or	ds:EVTSET, 2	; Speaker on!
		sti
		pop	ax
		cmp	al, 0		; Play in the foreground?
		jnz	short GONOTX
FGNDLP:
		push	ds
		xor	ax, ax
		mov	ds, ax
		assume ds:nothing
		mov	bx, 471h	; Ctrl+Break flag
		cmp	al, [bx]	; Break	flag set?
		pop	ds
		assume ds:nothing
		jnz	short GONOTX
		mov	ax, ds:CURNOT
		cmp	ax, ds:NOTPTR
		jz	short GONOTX
		or	si, si
		jz	short FGNDLP
		add	ax, 4		; Advance pointer
		cmp	ax, 84h		; Wrapping around?
		jnz	short HAVPTR
		xor	ax, ax		; If yes, pointer wraps	to zero
HAVPTR:
		cmp	ax, ds:NOTPTR
		jnz	short FGNDLP
		cmp	ds:byte_64AA, 0
		jnz	short FGNDLP
		cmp	ds:word_64AB, 6
		jnb	short FGNDLP
GONOTX:
		jmp	DONOTX
DONOTE		endp


; =============== S U B	R O U T	I N E =======================================


NXTNOT		proc near
		cmp	si, 84h
		jz	short WRAP
		ret
; ---------------------------------------------------------------------------

WRAP:
		mov	si, 0
		ret
NXTNOT		endp

CSEG    ENDS
        END
