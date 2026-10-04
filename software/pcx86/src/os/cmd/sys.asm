;
; BASIC-DOS System Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for CHAIN, DEF SEG, PEEK, PLAY, POKE, and SOUND (see
; gensys.asm).
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<callDOS,releaseStr,strIllegal>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

SND_END		equ	PLAY_STATE+4	; BIOS tick count when the SOUND ends
SND_BUSY	equ	PLAY_STATE+6	; non-zero if SND_END is valid (byte)
BIOS_TICKS	equ	46Ch		; BIOS tick count (in segment 0)

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
	push	bx
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


CODE	ENDS

	end
