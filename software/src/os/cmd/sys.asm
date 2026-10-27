;
; BASIC-DOS System Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for DEF SEG, PEEK, and POKE (see gensys.asm), and for
; READ and RESTORE (see gendef.asm); CHAIN is in chain.asm, and PLAY and SOUND
; are in snd.asm.  The MOUSE runtime functions are in gfx.asm, except for
; mouseReset and mouseCall, which stay in COMMAND's core for SCREEN and
; restoreMode (see libc.asm).
;
	DOSFUNC equ 1
	GFXDEFS equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<releaseStr,strIllegal,allocStr,rtError>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE


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
; readData
;
; Used by "READ var[,var]...", which calls us for each var, to get the next
; DATA item as a string.  Rather than collecting DATA items when the program
; is generated, we scan the program's text for them as needed, keeping track
; of where we are in DATA_STATE (see genInit and freeCache, which reset it).
; A quoted item may contain commas and colons (but not quotes), and an
; unquoted item ends at a comma, colon, or the end of the line, with leading
; and trailing whitespace removed.
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
	mov	si,ss:[di].DATA_STATE.DATA_OFF
	mov	dx,ss:[di].DATA_STATE.DATA_END
	mov	cx,ss:[di].DATA_STATE.DATA_SEG
	jcxz	rdt0			; start at the first line
	mov	ds,cx
	test	dx,dx			; at the start of a line?
	jz	rdt1			; yes
	cmp	byte ptr ss:[di].DATA_STATE.DATA_ITEM,0
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
	mov	ss:[di].DATA_STATE.DATA_OFF,si
	mov	ss:[di].DATA_STATE.DATA_SEG,ds
	mov	ss:[di].DATA_STATE.DATA_END,dx
	mov	byte ptr ss:[di].DATA_STATE.DATA_ITEM,ah
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
	mov	ss:[di].DATA_STATE.DATA_SEG,ax	; start over
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
rst4:	mov	ss:[di].DATA_STATE.DATA_OFF,si
	mov	ss:[di].DATA_STATE.DATA_SEG,ds
	mov	word ptr ss:[di].DATA_STATE.DATA_END,0
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
; mouseReset
;
; Resets the mouse, if any (which hides the pointer), and clears MOUSE_STATE.
; restoreMode also calls this when a BAS program ends.  It issues INT 33h
; directly, since that's how we find a mouse (if there's no mouse driver,
; DOS points INT 33h at an IRET, which leaves AX zero).
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
	int	INT_MOUSE
	mov	bx,ss:[PSP_HEAP]
	mov	byte ptr ss:[bx].GFX_DATA.MOUSE_STATE,0
	ret
ENDPROC	mouseReset

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mouseCall
;
; Issues an INT 33h function, if MOUSE ON found a mouse (see mouseOn).
;
; Inputs:
;	AX = function (and BX, CX, DX as required)
;
; Outputs:
;	Same as the function; if the mouse isn't on, carry is set and AX, BX,
;	CX, and DX are zero
;
DEFPROC	mouseCall
	push	bx
	mov	bx,ss:[PSP_HEAP]
	test	byte ptr ss:[bx].GFX_DATA.MOUSE_STATE,MS_ON
	pop	bx
	jz	mc8
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
