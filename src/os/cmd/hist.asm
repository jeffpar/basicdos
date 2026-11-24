;
; BASIC-DOS Command History
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; readCmd, which the main loop calls to read a command, and HISTORY$.  The
; history is a block of HIST_SIZE bytes (see HIST_SEG), allocated when the
; first command is read, with the commands entered at the prompt stored as
; length-prefixed strings, newest first, followed by a zero length; the oldest
; commands are dropped to make room for new ones.
;
; This module is not part of COMMAND's core (see CMD.LRF and HEAP.ASM): when
; only the core is loaded, the main loop calls DOS_TTY_INPUT instead, and
; genFuncExpr refuses HISTORY$ with "Not enough memory".
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<allocStr,strIllegal>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

HIST_SIZE	equ	1024		; size of the history block, in bytes

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; readCmd
;
; Reads a command into INPUTBUF with DOS_UTL_EDITLN, which returns UP and
; DOWN to us (after erasing the line), so that we can display the next older
; or newer command in the history that begins with the characters typed (any
; command, if none were typed).  The typed line is saved in LINEBUF, as entry
; 0 (see getHist), so that DOWN can return to it.  An entered command is added
; to the history, unless it's empty or the same as the newest one.  If there's
; no memory for the history, this is the same as DOS_TTY_INPUT.
;
; Inputs:
;	BX -> CMDHEAP
;	DX -> INPUTBUF
;	DS = ES = SS
;
; Outputs:
;	INPUTBUF filled in, as for DOS_TTY_INPUT
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	readCmd
	mov	ax,[bx].HIST_SEG
	test	ax,ax			; is there a history block yet?
	jnz	gl1			; yes
	push	bx
	mov	bx,HIST_SIZE / 16
	mov	ax,(DOS_MEM_ALLOC SHL 8) OR MCBTYPE_HIGH
	int	21h
	pop	bx
	jnc	gl0
	mov	ah,DOS_TTY_INPUT	; no memory, so no history
	int	21h
	ret
gl0:	mov	[bx].HIST_SEG,ax
	mov	es,ax
	mov	byte ptr es:[0],0	; no commands yet
	push	ss
	pop	es

gl1:	sub	cx,cx			; CX = entry # (0 for the typed line)
	mov	al,1			; AL = 1 for editing notifications
gl2:	lea	dx,[bx].INPUTBUF
	DOSUTIL	EDITLN			; AX = key, unless the line was entered
	cmp	al,CHR_CTRLE		; UP?
	je	gl3			; yes
	cmp	al,CHR_CTRLX		; DOWN?
	jne	gl8			; no, so the line was entered

gl3:	test	cx,cx			; is the typed line displayed?
	jnz	gl4			; no
	lea	si,[bx].INPUTBUF.INP_CNT
	lea	di,[bx].LINEBUF
	mov	cl,[si]
	inc	cx			; CX = length byte and characters
	rep	movsb			; save the typed line as entry 0

gl4:	mov	dx,cx			; DX = entry # to check
gl5:	inc	dx			; UP checks the next older entry
	cmp	al,CHR_CTRLE		; UP?
	je	gl6			; yes
	dec	dx
	dec	dx			; DOWN checks the next newer entry
	js	gl7			; none is newer than the typed line
gl6:	call	getHist			; ES:SI -> entry DX
	jc	gl7			; there's none older than the oldest
	call	chkPrefix		; does it begin with the typed line?
	jne	gl5			; no
	mov	cx,dx			; CX = entry # to display
;
; Display entry CX: either the one we found, or if there was none, the one
; that was displayed before (which the line editor erased).
;
gl7:	mov	dx,cx
	call	getHist			; ES:SI -> entry CX
	push	cx
	push	ds
	push	es
	pop	ds			; DS:SI -> entry
	ASSUME	DS:NOTHING
	push	ss
	pop	es
	lea	di,[bx].INPUTBUF.INP_CNT
	mov	cl,[si]
	mov	ch,0
	inc	cx			; CX = length byte and characters
	rep	movsb			; copy the entry to INPUTBUF
	pop	ds
	ASSUME	DS:DATA
	pop	cx
	mov	al,3			; AL = 3 to display the entry, too
	jmp	gl2
;
; The line was entered, so add it to the history, unless it's empty or the
; same as the newest command.
;
gl8:	mov	es,[bx].HIST_SEG
	lea	si,[bx].INPUTBUF.INP_CNT
	mov	cl,[si]
	mov	ch,0			; CX = # characters
	jcxz	gl9			; none
	inc	cx			; CX = size of the new entry
	sub	di,di			; ES:DI -> newest entry
	push	cx
	push	si
	repe	cmpsb			; is it the same as the newest?
	pop	si
	pop	cx
	je	gl9			; yes
;
; Find how many bytes of older entries we can keep, along with the new entry
; and a zero length.
;
	mov	dx,HIST_SIZE
	sub	dx,cx			; DX = room for older entries + a zero
	sub	di,di
gl8a:	mov	al,es:[di]
	mov	ah,0
	test	al,al			; end of the entries?
	jz	gl8b			; yes
	inc	ax
	add	ax,di			; AX -> next entry
	cmp	ax,dx			; does this entry fit?
	jae	gl8b			; no, so drop it (and the rest)
	xchg	di,ax
	jmp	gl8a
gl8b:	push	ds
	push	es
	pop	ds			; DS = history block
	ASSUME	DS:NOTHING
	mov	si,di			; SI = # bytes to keep
	add	di,cx
	mov	byte ptr [di],0		; store the new zero length
	push	cx
	mov	cx,si
	dec	si			; SI -> last byte to keep
	dec	di			; DI -> its new position
	std
	rep	movsb			; make room for the new entry
	cld
	pop	cx
	pop	ds
	ASSUME	DS:DATA
	sub	di,di
	lea	si,[bx].INPUTBUF.INP_CNT
	rep	movsb			; and store it
gl9:	push	ss
	pop	es
	ret
ENDPROC	readCmd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getHist
;
; Inputs:
;	BX -> CMDHEAP
;	DX = entry # (1 for the newest command, or 0 for LINEBUF; see readCmd)
;
; Outputs:
;	Carry clear if the entry exists, and ES:SI -> its length byte
;
; Modifies:
;	SI, DI, ES
;
DEFPROC	getHist
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	push	ax
	push	ss
	pop	es
	lea	si,[bx].LINEBUF		; ES:SI -> entry 0
	mov	di,dx
	test	di,di			; entry 0?
	jz	gh9			; yes (carry clear)
	mov	es,ss:[bx].HIST_SEG
	sub	si,si
gh1:	mov	al,es:[si]
	cmp	al,1			; end of the entries?
	jb	gh9			; yes (carry set)
	dec	di			; is this the entry?
	jz	gh9			; yes (carry clear)
	mov	ah,0
	inc	ax
	add	si,ax			; SI -> next entry
	jmp	gh1
gh9:	pop	ax
	ret
ENDPROC	getHist

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkPrefix
;
; Inputs:
;	BX -> CMDHEAP
;	ES:SI -> history entry
;
; Outputs:
;	ZF set if the entry begins with the typed line (in LINEBUF)
;
; Modifies:
;	SI, DI
;
DEFPROC	chkPrefix
	push	cx
	mov	di,si			; ES:DI -> entry
	lea	si,[bx].LINEBUF		; DS:SI -> typed line
	mov	cl,[si]
	mov	ch,0			; CX = # characters typed
	cmpsb				; is the entry at least as long?
	ja	cp9			; no (ZF clear)
	cmp	ax,ax			; (ZF set, in case CX is zero)
	repe	cmpsb
cp9:	pop	cx
	ret
ENDPROC	chkPrefix

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strHistory (HISTORY$)
;
; Returns history entry n (1 for the newest command), or an empty string if
; there's no such entry.
;
; Inputs:
;	32-bit return value
;	32-bit entry # (popped)
;
; Outputs:
;	32-bit return value updated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	strHistory,FAR
	ASSUMES	<DS,NOTHING>,<ES,NOTHING>
	RETVAR	retHist,dword
	ARGVAR	histNum,dword
	ENTER
	sub	cx,cx			; CX = length (none yet)
	mov	dx,[histNum].LW		; DX = entry #
	mov	ax,[histNum].HW
	test	ax,ax			; is the entry # negative?
	js	sh8			; yes
	jnz	sh1			; no, but there's no such entry
	mov	bx,ss:[PSP_HEAP]	; BX -> CMDHEAP
	cmp	ss:[bx].HIST_SEG,cx	; is there any history?
	je	sh1			; no
	test	dx,dx			; entry 0?
	jz	sh1			; yes (which is always empty)
	call	getHist			; ES:SI -> entry, if any
	jc	sh1
	lods	byte ptr es:[si]
	mov	cl,al			; CX = length
sh1:	push	ds
	push	es
	pop	ds			; DS:SI -> characters
	sub	ax,ax
	cwd				; DX:AX = empty string
	jcxz	sh2
	call	allocStr		; ES:DI -> new string
	mov	ax,di
	mov	dx,es
	inc	di
	rep	movsb
sh2:	pop	ds
	mov	[retHist]._OFF,ax
	mov	[retHist]._SEG,dx
	LEAVE
	RETURN
sh8:	jmp	strIllegal
ENDPROC	strHistory

CODE	ENDS

	end
