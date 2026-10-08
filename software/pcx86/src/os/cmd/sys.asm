;
; BASIC-DOS System Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for CHAIN, DEF SEG, MOUSE, PEEK, PLAY, POKE, and SOUND
; (see gensys.asm), and for READ and RESTORE (see gendef.asm).
;
	include	cmd.inc
	include	fpu.inc

CODE    SEGMENT

	EXTNEAR	<callDOS,releaseStr,strIllegal,allocStr,rtError,findVar>
	EXTLONG	<FPU_TABLE>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

SND_END		equ	PLAY_STATE+4	; BIOS tick count when the SOUND ends
SND_BUSY	equ	PLAY_STATE+6	; non-zero if SND_END is valid (byte)
BIOS_TICKS	equ	46Ch		; BIOS tick count (in segment 0)

DATA_OFF	equ	DATA_STATE+0	; offset of the next character to scan
DATA_SEG	equ	DATA_STATE+2	; its text block (0 to start over)
DATA_END	equ	DATA_STATE+4	; end of its line (0 if at a line)
DATA_ITEM	equ	DATA_STATE+6	; non-zero if in a DATA statement

MOUSE_X		equ	GFX_DATA+8	; position of the last MOUSE(0) event
MOUSE_Y		equ	GFX_DATA+10
MOUSE_STATE	equ	GFX_DATA+12	; MS_* bits (byte)
MS_ON		equ	01h		; set by MOUSE ON
MS_GFX		equ	02h		; pointer hidden (see mouseGfx)

INT_MOUSE	equ	33h		; MOUSE$ services (see moudev.asm)
MOUSE_EVENT	equ	0BDh		; get the next button event

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doChain
;
; Used by "CHAIN file", which runs the file like any other command.
;
; Inputs:
;	string value (popped)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	doChain,FAR
	ARGVAR	pChainStr,dword
	ENTER
	les	di,[pChainStr]
	mov	ax,es
	test	ax,ax			; empty string?
	jz	dcX			; yes
	sub	ax,ax
	push	ax			; no handler
	push	ax			; no keyword ID
	mov	al,es:[di]
	push	ax			; length of command line
	push	es
	inc	di
	push	di			; pointer to command line
	dec	di
	call	releaseStr		; (callDOS copies it before using it)
	push	cs
	call	callDOS
	LEAVE
	RETURN
dcX:	jmp	strIllegal
ENDPROC	doChain

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; defSeg
;
; Used by "DEF SEG=segment" (and, via defSegBasic, by "DEF SEG", which selects
; BASIC's own data segment; ie, our heap).  We store the segment XOR SS, so
; that the zero-initialized default is the heap.
;
; Inputs:
;	1 32-bit arg on stack (-32768 to 65535)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	defSegBasic,FAR
	mov	ax,ss
	jmp	short dfs1
ENDPROC	defSegBasic

DEFPROC	defSeg,FAR
	pop	cx
	pop	dx			; DX:CX = return address
	pop	ax
	pop	bx			; BX:AX = segment
	push	dx
	push	cx
	call	chkWord
dfs1:	mov	bx,ss
	xor	ax,bx
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].PEEK_SEG,ax
	ret
ENDPROC	defSeg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; peekByte (PEEK)
;
; Inputs:
;	32-bit return value
;	32-bit offset (popped)
;
; Outputs:
;	32-bit return value updated with the byte at DEF SEG:offset
;
; Modifies:
;	AX, BX, DX, ES
;
DEFPROC	peekByte,FAR
	RETVAR	retPeek,dword
	ARGVAR	peekOff,dword
	ENTER
	mov	ax,[peekOff].LOW
	mov	bx,[peekOff].HIW
	call	chkWord
	call	getSeg
	xchg	bx,ax
	mov	al,es:[bx]
	mov	ah,0
	mov	[retPeek].LOW,ax
	mov	[retPeek].HIW,0
	LEAVE
	RETURN
ENDPROC	peekByte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pokeByte
;
; Used by "POKE offset,value" to store value (0-255) at DEF SEG:offset.
;
; Inputs:
;	2 32-bit args on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	pokeByte,FAR
	pop	si
	pop	di			; DI:SI = return address
	pop	cx
	pop	dx			; DX:CX = value
	pop	ax
	pop	bx			; BX:AX = offset
	push	di
	push	si
	call	chkWord
	test	dx,dx
	jnz	cw8
	test	ch,ch
	jnz	cw8
	call	getSeg
	xchg	bx,ax
	mov	es:[bx],cl
	ret
ENDPROC	pokeByte

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkWord
;
; Inputs:
;	BX:AX = 32-bit value
;
; Outputs:
;	None (an "Illegal function call" error occurs if BX:AX isn't
;	-32768 to 65535, the range of segments and offsets in MSBASIC)
;
; Modifies:
;	BX
;
DEFPROC	chkWord
	test	bx,bx
	jz	cw9
	inc	bx
	jnz	cw8
	test	ax,ax
	js	cw9
cw8:	jmp	strIllegal
cw9:	ret
ENDPROC	chkWord

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getSeg
;
; Inputs:
;	None
;
; Outputs:
;	ES = DEF SEG segment
;
; Modifies:
;	BX, DX, ES
;
DEFPROC	getSeg
	mov	dx,ss
	mov	bx,ss:[PSP_HEAP]
	xor	dx,ss:[bx].PEEK_SEG
	mov	es,dx
	ret
ENDPROC	getSeg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doPlay
;
; Used by "PLAY string", which supports these commands from MSBASIC's music
; language (in upper or lower case, with spaces ignored):
;
;	A-G[#|+|-][len][.]	note (# or + for sharp, - for flat)
;	Nn[.]			note n (1-84), or a rest if n is 0
;	On, <, >		octave (0-6; default 4), down 1, or up 1
;	Ln			length (1-64; default 4, a quarter note)
;	Pn[.]			pause (rest) of length n (1-64)
;	Tn			tempo (32-255 quarter notes per minute;
;				default 120)
;	MN, ML, MS		normal (7/8), legato (full), or staccato (3/4)
;	MF, MB			ignored (music always plays in the foreground)
;
; The octave, length, tempo, and mode persist from one PLAY to the next, in
; the first 4 bytes of PLAY_STATE: the octave XOR 4, length XOR 4, tempo XOR
; 120, and mode (0 for MN, 1 for ML, or 2 for MS), so that zero bytes (the
; initial state of the heap) are the defaults.  The rest of PLAY_STATE is
; used by SOUND (see SND_END and SND_BUSY).
;
; Inputs:
;	string value (popped)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	doPlay,FAR
	ARGVAR	pPlayStr,dword
	ENTER
	call	sndWait			; let any SOUND finish first
	push	ds
	lds	si,[pPlayStr]
	mov	cx,ds
	jcxz	dp9			; empty string
	lodsb
	mov	cl,al
	mov	ch,0			; CX = length, DS:SI -> characters
	mov	bx,ss:[PSP_HEAP]
	jmp	short dp1

dp8:	les	di,[pPlayStr]
	call	releaseStr
dp9:	pop	ds
	LEAVE
	RETURN

dp1:	call	playChar		; AL = next command
	jc	dp8			; none
	cmp	al,'A'
	jb	dp3
	cmp	al,'G'
	ja	dp3
;
; Process a note (A-G), with an optional sharp or flat, and optional length.
;
	sub	al,'A'
	cbw
	xchg	di,ax
	mov	dl,cs:NOTE_MAP[di]
	mov	dh,0			; DX = semitone (0-11)
	jcxz	dp2a
	mov	al,[si]
	cmp	al,'#'
	je	dp2
	cmp	al,'+'
	je	dp2
	cmp	al,'-'
	jne	dp2a
	dec	dx			; flat
	dec	dx
dp2:	inc	dx			; sharp
	inc	si
	dec	cx
dp2a:	mov	al,byte ptr ss:[bx].PLAY_STATE+0
	xor	al,4
	mov	ah,12
	mul	ah
	add	dx,ax			; DX = note # (0-83, if valid)
	push	dx
	call	playNum
	jnc	dp2b
	call	getLen
dp2b:	pop	dx
dp2c:	call	playNote
	jmp	dp1

dp3:	cmp	al,'N'
	jne	dp4
	call	needNum
	xchg	dx,ax
	dec	dx			; DX = note #, or -1 for a rest
	call	getLen
	jmp	dp2c

dp4:	cmp	al,'P'
	jne	dp5
	call	needNum
	mov	dx,-1			; DX = rest
	jmp	dp2c

dp5:	cmp	al,'O'
	jne	dp6
	call	needNum
	cmp	ax,6
	ja	dpX
dp5a:	xor	al,4
	mov	byte ptr ss:[bx].PLAY_STATE+0,al
	jmp	dp1
dpX:	jmp	strIllegal
dpN:	jmp	dp1

dp6:	mov	ah,-1
	cmp	al,'<'
	je	dp6a
	mov	ah,1
	cmp	al,'>'
	jne	dp7
dp6a:	mov	al,byte ptr ss:[bx].PLAY_STATE+0
	xor	al,4
	add	al,ah
	cmp	al,6			; still in range?
	ja	dpN			; no, so ignore it
	jmp	dp5a

dp7:	cmp	al,'L'
	jne	dp7a
	call	needNum
	call	chkLen
	xor	al,4
	mov	byte ptr ss:[bx].PLAY_STATE+1,al
	jmp	dp1

dp7a:	cmp	al,'T'
	jne	dp7b
	call	needNum
	cmp	ax,32
	jb	dpX
	cmp	ax,255
	ja	dpX
	xor	al,120
	mov	byte ptr ss:[bx].PLAY_STATE+2,al
	jmp	dp1

dp7b:	cmp	al,'M'
	jne	dpX
	call	playChar
	jc	dpX
	mov	ah,0
	cmp	al,'N'
	je	dp7c
	inc	ah
	cmp	al,'L'
	je	dp7c
	inc	ah
	cmp	al,'S'
	je	dp7c
	cmp	al,'F'
	je	dpN
	cmp	al,'B'
	je	dpN
	jmp	short dpX
dp7c:	mov	byte ptr ss:[bx].PLAY_STATE+3,ah
	jmp	dp1

ENDPROC	doPlay

NOTE_MAP	db	9,11,0,2,4,5,7		; A-G semitones
;
; PIT divisors for the notes of octave 0 (C through B, where A is 110Hz);
; each octave above that halves them.
;
DIV_TBL		dw	18243,17219,16252,15340,14479,13667
		dw	12899,12175,11492,10847,10238,9664

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getLen
;
; Inputs:
;	BX -> heap
;
; Outputs:
;	AX = current PLAY length
;
; Modifies:
;	AX
;
DEFPROC	getLen
	mov	al,byte ptr ss:[bx].PLAY_STATE+1
	xor	al,4
	mov	ah,0
	ret
ENDPROC	getLen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkLen
;
; Inputs:
;	AX = length
;
; Outputs:
;	None (an "Illegal function call" error occurs if AX isn't 1-64)
;
; Modifies:
;	None
;
DEFPROC	chkLen
	dec	ax
	cmp	ax,64
	inc	ax
	jae	cl9
	ret
cl9:	jmp	strIllegal
ENDPROC	chkLen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; playChar
;
; Inputs:
;	DS:SI -> PLAY characters (CX remaining)
;
; Outputs:
;	Carry clear if AL = next character (upper-cased), set if none
;
; Modifies:
;	AL, CX, SI
;
DEFPROC	playChar
	stc
	jcxz	pc9
	lodsb
	dec	cx
	cmp	al,' '
	je	playChar
	cmp	al,'a'
	jb	pc8
	sub	al,20h
pc8:	clc
pc9:	ret
ENDPROC	playChar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; playNum
;
; Inputs:
;	DS:SI -> PLAY characters (CX remaining)
;
; Outputs:
;	Carry clear if AX = decimal number, set if there are no digits
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	playNum
	jcxz	pn0
	cmp	byte ptr [si],'='	; variable (eg, "O=J;")?
	jne	pn0			; no
	inc	si
	dec	cx
	jmp	getStrVar		; yes (and it clears carry)
pn0:	push	bx
	sub	bx,bx			; BX = value
	sub	di,di			; DI = # digits
pn1:	jcxz	pn8
	mov	al,[si]
	sub	al,'0'
	cmp	al,9
	ja	pn8
	inc	si
	dec	cx
	inc	di
	cbw
	push	ax
	mov	ax,10
	mul	bx
	pop	bx
	add	bx,ax			; BX = BX * 10 + digit
	jmp	pn1
pn8:	xchg	ax,bx
	pop	bx
	cmp	di,1			; carry set if no digits
	ret
ENDPROC	playNum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; needNum
;
; Like playNum, but the number is required.
;
; Inputs:
;	DS:SI -> PLAY characters (CX remaining)
;
; Outputs:
;	AX = decimal number (an "Illegal function call" error occurs if
;	there are no digits)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	needNum
	call	playNum
	jc	cl9
	ret
ENDPROC	needNum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; playNote
;
; Plays a note (or rest) of the given length at the current tempo, followed
; by any dots (each of which increases the duration by half), using the
; current mode (MN, ML, or MS).
;
; Inputs:
;	AX = length (1-64)
;	DX = note # (0-83, where 0 is C in octave 0), or -1 for a rest
;	BX -> heap
;	DS:SI -> PLAY characters (CX remaining)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	playNote
	call	chkLen
	push	dx
	mov	dl,byte ptr ss:[bx].PLAY_STATE+2
	xor	dl,120
	mov	dh,0
	mul	dx			; AX = tempo * length
	xchg	di,ax
	mov	dx,3
	mov	ax,0A980h		; DX:AX = 240000
	div	di			; AX = duration (ms)
pln1:	jcxz	pln2
	cmp	byte ptr [si],'.'
	jne	pln2
	inc	si
	dec	cx
	mov	dx,ax
	shr	dx,1
	add	ax,dx			; increase the duration by half
	jmp	pln1
pln2:	pop	dx
	test	dx,dx			; rest?
	js	pln8			; yes
	cmp	dx,84
	jae	cl9
	push	cx
	push	ax
	xchg	ax,dx
	mov	dl,12
	div	dl			; AL = octave, AH = semitone
	mov	cl,al
	mov	al,ah
	cbw
	xchg	di,ax
	shl	di,1
	mov	ax,cs:DIV_TBL[di]
	shr	ax,cl			; AX = PIT divisor
	call	speakerOn
	pop	ax			; AX = duration
	mov	di,ax
	shr	di,1
	shr	di,1			; DI = duration / 4 (for MS)
	mov	cl,byte ptr ss:[bx].PLAY_STATE+3
	cmp	cl,1
	ja	pln3			; MS
	jb	pln2a			; MN
	sub	di,di			; ML
pln2a:	shr	di,1			; DI = duration / 8 (for MN)
pln3:	sub	ax,di			; AX = duration on
	call	sleepMs
	call	speakerOff
	xchg	ax,di			; AX = duration off
	pop	cx
pln8:	jmp	sleepMs
ENDPROC	playNote

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; doSound
;
; Used by "SOUND frequency,duration", where frequency is 37-32767 Hz and
; duration is in clock ticks (18.2 per second).
;
; Like MSBASIC, SOUND starts the sound and returns immediately, so the program
; keeps running while the sound plays (the CLOCK$ driver turns it off; see
; IOCTL_SOUND); however, the next SOUND waits for the current one to finish,
; unless its duration is zero, which turns off the current sound.
;
; Inputs:
;	2 32-bit args on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	doSound,FAR
	ARGVAR	sndFreq,dword
	ARGVAR	sndTicks,dword
	ENTER
	cmp	[sndTicks].HIW,0
	jne	dsX
	mov	cx,[sndTicks].LOW	; CX = duration
	sub	dx,dx			; DX = 0 (turn the sound off)
	jcxz	ds8
	mov	bx,[sndFreq].LOW
	cmp	[sndFreq].HIW,0
	jne	dsX
	cmp	bx,37
	jb	dsX
	cmp	bx,32767
	ja	dsX
	mov	dx,12h
	mov	ax,34DEh		; DX:AX = 1193182 (PIT frequency)
	div	bx			; AX = PIT divisor
	call	sndWait
	push	ax
	push	es
	sub	ax,ax
	mov	es,ax
	mov	ax,es:[BIOS_TICKS]
	pop	es
	add	ax,cx
	mov	bx,ss:[PSP_HEAP]
	mov	ss:[bx].SND_END,ax
	mov	byte ptr ss:[bx].SND_BUSY,1
	pop	dx			; DX = PIT divisor
ds8:	DOSUTIL	SOUND			; start (or stop) the sound
	LEAVE
	RETURN
dsX:	jmp	strIllegal
ENDPROC	doSound

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sndWait
;
; Waits for the current SOUND (if any) to finish, yielding to other sessions
; while we wait.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	sndWait
	push	ax
	push	bx
	push	es
	mov	bx,ss:[PSP_HEAP]
	cmp	byte ptr ss:[bx].SND_BUSY,0
	je	sw9
	sub	ax,ax
	mov	es,ax
sw1:	mov	ax,es:[BIOS_TICKS]
	sub	ax,ss:[bx].SND_END	; has the end tick been reached?
	jns	sw8			; yes
	DOSUTIL	YIELD
	jmp	sw1
sw8:	mov	byte ptr ss:[bx].SND_BUSY,0
sw9:	pop	es
	pop	bx
	pop	ax
	ret
ENDPROC	sndWait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; speakerOn
;
; Inputs:
;	AX = PIT divisor
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	speakerOn
	push	ax
	mov	al,0B6h			; PIT channel 2, mode 3, LSB then MSB
	out	43h,al
	pop	ax
	out	42h,al
	mov	al,ah
	out	42h,al
	in	al,61h
	or	al,03h			; enable the speaker
	out	61h,al
	ret
ENDPROC	speakerOn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; speakerOff
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	speakerOff
	push	ax
	in	al,61h
	and	al,0FCh			; disable the speaker
	out	61h,al
	pop	ax
	ret
ENDPROC	speakerOff

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sleepMs
;
; Inputs:
;	AX = # milliseconds
;
; Outputs:
;	None
;
; Modifies:
;	DX
;
DEFPROC	sleepMs
	test	ax,ax
	jz	sm9
	push	ax
	push	cx
	xchg	dx,ax
	sub	cx,cx			; CX:DX = # milliseconds
	DOSUTIL	SLEEP
	pop	cx
	pop	ax
sm9:	ret
ENDPROC	sleepMs


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; readData
;
; Used by "READ var[,var]...", which calls us for each var, to get the next
; DATA item as a string.  Rather than collecting DATA items when the program
; is generated, we scan the program's text for them as needed, keeping track
; of where we are in DATA_STATE (see genCode, runCode, and freeCache, which
; reset it).  A quoted item may contain commas and colons (but not quotes),
; and an unquoted item ends at a comma, colon, or the end of the line, with
; leading and trailing whitespace removed.
;
; Inputs:
;	32-bit return value
;
; Outputs:
;	32-bit return value updated (the item's string value)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	readData,FAR
	RETVAR	retItem,dword
	ENTER
	push	ds
	mov	di,ss:[PSP_HEAP]
	mov	si,ss:[di].DATA_OFF
	mov	dx,ss:[di].DATA_END
	mov	cx,ss:[di].DATA_SEG
	jcxz	rdt0			; start at the first line
	mov	ds,cx
	test	dx,dx			; at the start of a line?
	jz	rdt1			; yes
	cmp	byte ptr ss:[di].DATA_ITEM,0
	je	rdt3			; look for another DATA statement
	jmp	rdt6			; get the next DATA item

rdtX:	mov	al,4			; "Out of DATA"
	jmp	rtError

rdt0:	mov	cx,ss:[di].TBLKDEF.BLK_NEXT
	jcxz	rdtX			; there's no program text
	mov	ds,cx
	mov	si,size TBLK
rdt1:	cmp	si,ds:[BLK_FREE]	; any more lines in this block?
	jb	rdt2			; yes
	mov	cx,ds:[BLK_NEXT]	; no, so go to the next block
	jcxz	rdtX			; there are no more
	mov	ds,cx
	mov	si,size TBLK
	jmp	rdt1
rdt2:	lodsw				; skip the line's label #
	lodsb
	mov	ah,0
	mov	dx,si
	add	dx,ax			; DX = end of the line
;
; Check the statement at DS:SI for DATA (or REM, which ends the line).
;
rdt3:	call	dataSkip		; skip whitespace
	mov	cx,dx
	sub	cx,si			; CX = # chars left on the line
	jbe	rdtN			; none
	cmp	byte ptr [si],"'"	; remark?
	je	rdtN			; yes
	mov	ax,[si]
	and	ax,0DFDFh		; (upper-case letters)
	cmp	cx,3
	jb	rdt4
	cmp	ax,'ER'			; "RE"?
	jne	rdt3a
	mov	al,[si+2]
	and	al,0DFh
	cmp	al,'M'			; "REM"?
	je	rdtN			; yes, so skip the line
rdt3a:	cmp	cx,4
	jb	rdt4
	cmp	ax,'AD'			; "DA"?
	jne	rdt4
	mov	ax,[si+2]
	and	ax,0DFDFh
	cmp	ax,'AT'			; "DATA"?
	jne	rdt4
	cmp	cx,4			; anything after it?
	je	rdt3b			; no
	mov	al,[si+4]
	and	al,0DFh
	sub	al,'A'
	cmp	al,26			; another letter (eg, "DATAX")?
	jb	rdt4			; yes
rdt3b:	add	si,4			; DS:SI -> 1st DATA item
	jmp	short rdt6
;
; Skip the statement (ie, up to a colon outside of quotes, or a remark).
;
rdt4:	cmp	si,dx
	jae	rdtN
	lodsb
	cmp	al,'"'
	je	rdt5
	cmp	al,"'"
	je	rdtN
	cmp	al,':'
	je	rdt3
	jmp	rdt4
rdt5:	cmp	si,dx
	jae	rdtN
	lodsb
	cmp	al,'"'
	jne	rdt5
	jmp	rdt4
rdtN:	mov	si,dx			; go to the next line
	jmp	rdt1
;
; Get the DATA item at DS:SI (from CX to BX).
;
rdt6:	call	dataSkip		; skip whitespace
	mov	cx,si			; CX -> start of item
	mov	bx,si			; BX -> end of item
	cmp	si,dx
	jae	rdt9			; the item is empty
	cmp	byte ptr [si],'"'	; quoted item?
	jne	rdt7			; no
	inc	si
	mov	cx,si
rdt6a:	cmp	si,dx
	jae	rdt6b
	lodsb
	cmp	al,'"'
	jne	rdt6a
	dec	si			; SI -> closing quote
rdt6b:	mov	bx,si
	jmp	short rdt9

rdt7:	cmp	si,dx
	jae	rdt8
	mov	al,[si]
	cmp	al,','
	je	rdt8
	cmp	al,':'
	je	rdt8
	inc	si
	jmp	rdt7
rdt8:	mov	bx,si			; remove trailing whitespace
rdt8a:	cmp	bx,cx
	jbe	rdt9
	mov	al,[bx-1]
	cmp	al,' '
	je	rdt8b
	cmp	al,CHR_TAB
	jne	rdt9
rdt8b:	dec	bx
	jmp	rdt8a
;
; Find the delimiter that follows the item: a comma means there are more
; items, whereas a colon (or the end of the line) ends the DATA statement.
;
rdt9:	mov	ah,1			; AH = 1 (more items)
rdt9a:	cmp	si,dx
	jae	rdt9b
	lodsb
	cmp	al,','
	je	rdt9c
	cmp	al,':'
	jne	rdt9a
rdt9b:	mov	ah,0			; AH = 0 (no more items)
rdt9c:	mov	di,ss:[PSP_HEAP]
	mov	ss:[di].DATA_OFF,si
	mov	ss:[di].DATA_SEG,ds
	mov	ss:[di].DATA_END,dx
	mov	byte ptr ss:[di].DATA_ITEM,ah
	mov	si,cx
	mov	cx,bx
	sub	cx,si			; CX = length of item
	sub	ax,ax
	cwd				; DX:AX = empty string
	jcxz	rdt10
	call	allocStr		; ES:DI -> new string
	mov	ax,di
	mov	dx,es			; DX:AX = string value
	inc	di
	rep	movsb			; copy the item to it
rdt10:	mov	[retItem].OFF,ax
	mov	[retItem].SEG,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	readData

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dataSkip
;
; Inputs:
;	DS:SI -> text
;	DX = end of text
;
; Outputs:
;	DS:SI -> first character that isn't a space or tab (or DX)
;
; Modifies:
;	AL, SI
;
DEFPROC	dataSkip
dsk1:	cmp	si,dx
	jae	dsk9
	mov	al,[si]
	cmp	al,' '
	je	dsk2
	cmp	al,CHR_TAB
	jne	dsk9
dsk2:	inc	si
	jmp	dsk1
dsk9:	ret
ENDPROC	dataSkip

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; restoreData
;
; Used by "RESTORE [line]": with no line # (zero), the next READ starts over
; with the first DATA item; otherwise, it starts with the first DATA item at
; or after the specified line (which must exist).
;
; Inputs:
;	32-bit line # (popped)
;
; Outputs:
;	None
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	restoreData,FAR
	ARGVAR	dataLine,dword
	ENTER
	push	ds
	mov	di,ss:[PSP_HEAP]
	sub	ax,ax
	mov	ss:[di].DATA_SEG,ax	; start over
	mov	dx,[dataLine].LOW
	test	dx,dx			; line # specified?
	jz	rst9			; no
	mov	cx,ss:[di].TBLKDEF.BLK_NEXT
rst1:	jcxz	rst8			; no more blocks
	mov	ds,cx
	mov	si,size TBLK
rst2:	cmp	si,ds:[BLK_FREE]	; any more lines in this block?
	jae	rst3			; no
	cmp	[si],dx			; is this the line?
	je	rst4			; yes
	mov	al,[si+2]
	mov	ah,0
	add	si,ax
	add	si,3			; skip the label #, length, and text
	jmp	rst2
rst3:	mov	cx,ds:[BLK_NEXT]
	jmp	rst1
rst4:	mov	ss:[di].DATA_OFF,si
	mov	ss:[di].DATA_SEG,ds
	mov	word ptr ss:[di].DATA_END,0
rst9:	pop	ds
	LEAVE
	RETURN
rst8:	mov	al,8			; "Undefined line number"
	jmp	rtError
ENDPROC	restoreData

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strToLong
;
; Converts a string value to a long, for READ when there's no FPU$ driver
; (and therefore no doubles, which VAL requires).
;
; Inputs:
;	32-bit return value
;	string value (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strToLong,FAR
	RETVAR	retLong,dword
	ARGVAR	pLongStr,dword
	ENTER
	push	ds
	sub	ax,ax
	cwd				; DX:AX = 0
	lds	si,[pLongStr]
	test	si,si			; empty string?
	jz	stl9			; yes
	lodsb
	mov	cl,al
	mov	ch,0			; DS:SI -> string, CX = length
	mov	bl,10
	DOSUTIL	ATOI32			; DX:AX = value
	les	di,[pLongStr]
	call	releaseStr
stl9:	mov	[retLong].LOW,ax
	mov	[retLong].HIW,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	strToLong

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getStrVar
;
; Used for "=variable;" in PLAY and DRAW strings (eg, PLAY "O=J;"), which
; uses the value of the named numeric variable.  The name ends at a semicolon
; (or the end of the string), and the variable's type comes from its suffix,
; if any (eg, "J%"), or else from the default type of its first letter (eg,
; DEFINT I-N).  A double is rounded to a long, and as in MSBASIC, a variable
; that doesn't exist yet has a value of zero.
;
; Inputs:
;	DS:SI -> name (CX = # characters left in the string)
;
; Outputs:
;	AX = value (carry clear), DS:SI and CX advanced past the name and ';'
;	(an "Illegal function call" error occurs if the name is invalid)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	getStrVar
	push	bx
	push	es
	push	bp
	mov	bp,sp
	sub	sp,VAR_NAMELEN+1	; (room for the name)
	mov	di,sp
	push	ss
	pop	es			; ES:DI -> name buffer
	sub	bx,bx			; BX = length of name
gsv1:	jcxz	gsv2
	lodsb
	dec	cx
	cmp	al,';'			; end of name?
	je	gsv2			; yes
	cmp	al,'a'
	jb	gsv1a
	cmp	al,'z'
	ja	gsv1a
	sub	al,20h			; (upper-case it)
gsv1a:	cmp	bl,VAR_NAMELEN		; room for another character?
	jae	gsvX			; no
	stosb
	inc	bx
	jmp	gsv1
gsv2:	test	bx,bx			; any name?
	jz	gsvX			; no
	mov	ah,VAR_LONG
	mov	al,es:[di-1]		; AL = last character of name
	cmp	al,'%'
	je	gsv3
	mov	ah,VAR_DOUBLE
	cmp	al,'!'
	je	gsv3
	cmp	al,'#'
	je	gsv3
	mov	al,es:[bp-(VAR_NAMELEN+1)]
	sub	al,'A'			; AL = index of 1st letter
	cmp	al,26
	jae	gsvX
	cbw
	mov	di,ss:[PSP_HEAP]
	add	di,ax
	mov	ah,ss:[di].DEFVARS	; AH = default type for that letter
	test	ah,ah			; set?
	jnz	gsv4			; yes
	mov	ah,VAR_LONG		; no, so it's VAR_LONG without an FPU$
	cmp	word ptr cs:[FPU_TABLE].SEG,0
	je	gsv4			; driver, and VAR_DOUBLE otherwise
	mov	ah,VAR_DOUBLE
	jmp	short gsv4
gsvX:	jmp	strIllegal
gsv3:	dec	bx			; (the suffix isn't part of the name)
gsv4:	push	cx
	push	si
	push	ds
	push	ss
	pop	ds			; (findVar requires DS = heap)
	lea	si,[bp-(VAR_NAMELEN+1)]
	mov	cx,bx			; DS:SI -> name, CX = length
	call	findVar			; DX:SI -> var data
	jnc	gsv4a
	sub	ax,ax			; no such var, so its value is zero
	jmp	short gsv8
gsv4a:	mov	es,dx
	cmp	ah,VAR_LONG
	jne	gsv5
	mov	ax,es:[si]		; AX = value
	jmp	short gsv8
gsv5:	cmp	ah,VAR_DOUBLE
	jne	gsvX
	lds	di,cs:[FPU_TABLE]	; DS:DI -> FPUTBL
	mov	ax,ds
	test	ax,ax
	jz	gsvX
	push	ax
	push	[di].FPU_CVT1DL		; push the conversion function address
	mov	di,sp
	push	es
	push	si			; push a pointer to the double
	call	dword ptr ss:[di]	; and replace it with a long
	pop	ax			; AX = value
	add	sp,6			; (discard the high word, address)
gsv8:	pop	ds
	pop	si
	pop	cx
	mov	sp,bp
	pop	bp
	pop	es
	pop	bx
	clc
	ret
ENDPROC	getStrVar

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseOn
;
; Used by "MOUSE ON", which resets the mouse (emptying its event queue) and
; shows the pointer.  Like MSBASIC's PEN ON, nothing happens if there's no
; mouse (and the MOUSE function then returns only zeros).
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	mouseOn,FAR
	call	mouseReset		; AX = -1 if there's a mouse
	inc	ax
	jnz	mn9
	inc	ax			; AX = 1 (show the pointer)
	call	mouseCall
	or	byte ptr ss:[bx].MOUSE_STATE,MS_ON
mn9:	ret
ENDPROC	mouseOn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseOff
;
; Used by "MOUSE OFF", which resets the mouse (hiding the pointer and emptying
; its event queue).  Nothing happens if there's no mouse.
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	mouseOff,FAR
	call	mouseReset
	ret
ENDPROC	mouseOff

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseReset
;
; Resets the mouse, if any (which hides the pointer), and clears MOUSE_STATE.
; restoreMode also calls this when a BAS program ends.
;
; Inputs:
;	None
;
; Outputs:
;	AX = -1 if there's a mouse
;	BX -> CMDHEAP
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	mouseReset
	sub	ax,ax
	call	mouseCall
	mov	bx,ss:[PSP_HEAP]
	mov	byte ptr ss:[bx].MOUSE_STATE,0
	ret
ENDPROC	mouseReset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getMouse (MOUSE)
;
; Like MSBASIC's PEN function, MOUSE(n) returns:
;
;	0: the next button event (0 if none, 1 = left button pressed,
;	   2 = left released, 3 = right pressed, 4 = right released)
;	1: x of the event last returned by MOUSE(0)
;	2: y of the event last returned by MOUSE(0)
;	3: current x
;	4: current y
;	5: current buttons (1 = left, 2 = right, 3 = both)
;
; where positions are pixels in graphics modes, or a column and row (starting
; at 1) in text modes.  Every value is zero if there's no mouse.  If gfxInit
; hid the pointer, it's shown again.
;
; Inputs:
;	32-bit return value
;	32-bit n (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	getMouse,FAR
	RETVAR	retMouse,dword
	ARGVAR	mouseNum,dword
	ENTER
	mov	si,ss:[PSP_HEAP]
	test	byte ptr ss:[si].MOUSE_STATE,MS_GFX
	jz	gm1
	and	byte ptr ss:[si].MOUSE_STATE,NOT MS_GFX
	mov	ax,1			; show the pointer again
	call	mouseCall
gm1:	mov	di,[mouseNum].LOW
	cmp	[mouseNum].HIW,0
	jne	gmX
	cmp	di,5
	ja	gmX
	mov	ax,ss:[si].MOUSE_X
	cmp	di,1
	je	gm8
	mov	ax,ss:[si].MOUSE_Y
	cmp	di,2
	je	gm8
	mov	bx,di			; BX = 0 for an event, else the state
	mov	ax,MOUSE_EVENT
	call	mouseCall		; AX = event, BX = buttons, CX,DX = pos
	test	di,di
	jnz	gm3
	mov	ss:[si].MOUSE_X,cx
	mov	ss:[si].MOUSE_Y,dx
	jmp	short gm8
gm3:	xchg	ax,cx			; AX = x
	cmp	di,3
	je	gm8
	xchg	ax,dx			; AX = y
	cmp	di,4
	je	gm8
	xchg	ax,bx			; AX = buttons
gm8:	mov	[retMouse].LOW,ax
	mov	[retMouse].HIW,0
	LEAVE
	RETURN
gmX:	jmp	strIllegal
ENDPROC	getMouse

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseGfx
;
; Called by gfxInit, so that if MOUSE ON is in effect, graphics statements
; (eg, GET and PAINT) never see the pointer; the pointer stays hidden until
; the next MOUSE function (see getMouse).
;
; Inputs:
;	BX -> CMDHEAP
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	mouseGfx
	mov	al,byte ptr ss:[bx].MOUSE_STATE
	and	al,MS_ON OR MS_GFX
	cmp	al,MS_ON		; MOUSE ON, and not hidden yet?
	jne	mg9			; no
	or	byte ptr ss:[bx].MOUSE_STATE,MS_GFX
	mov	ax,2			; hide the pointer
	call	mouseCall
mg9:	ret
ENDPROC	mouseGfx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseCall
;
; Issues an INT 33h function, if the MOUSE$ driver (or any other mouse
; driver) is installed.
;
; Inputs:
;	AX = function (and BX, CX, DX as required)
;
; Outputs:
;	Same as the function; if there's no mouse, carry is set and AX, BX,
;	CX, and DX are zero
;
DEFPROC	mouseCall
	push	ds
	push	bx
	sub	bx,bx
	mov	ds,bx
	cmp	ds:[INT_MOUSE * 4].SEG,bx
	pop	bx
	pop	ds
	je	mc8
	int	INT_MOUSE
	clc
	ret
mc8:	sub	ax,ax
	cwd
	mov	bx,ax
	mov	cx,ax
	stc
	ret
ENDPROC	mouseCall

CODE	ENDS

	end
