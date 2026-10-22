;
; BASIC-DOS INPUT and WRITE Runtime Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Runtime functions for INPUT and LINE INPUT (from the keyboard, or from a
; file selected by selectInput) and WRITE (to the screen, or to a file made
; STDOUT by fileOut), which are part of COMMAND's core, unlike the rest of the
; file I/O functions (see fileio.asm), along with syncFiles, which cleanUpTo
; calls after every command.
;
; Nothing is buffered between statements: INPUT # and LINE INPUT # read a
; chunk of the file into LINEBUF, take the next item (or line) from it, and
; seek back to the end of that item.  INPUT and LINE INPUT (from the keyboard)
; read a line into LINEBUF and take items from it, much like INPUT # (see
; inputLine).
;
	DOSFUNC equ 1
	include	cmd.inc
	include	fileio.inc

CODE    SEGMENT

	EXTNEAR	<rtError,allocStr,releaseStr>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; inputLine
;
; Used by "INPUT [prompt;|,]var[,var]..." and "LINE INPUT [prompt;]var$" to
; display the prompt (followed by "? " if requested) and read a line from the
; keyboard into LINEBUF, where fileItem then finds the items for each var.
; Unlike MSBASIC, missing items are simply empty (or zero), and extra items
; are ignored, rather than asking the user to "Redo from start".
;
; Inputs:
;	prompt string (popped)
;	16-bit flags (popped): bit 0 to display "? ", bit 1 for LINE INPUT
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	inputLine,FAR
	ARGVAR	pPrompt,dword
	ARGVAR	wInFlags,word
	ENTER
	push	ds
	lds	si,[pPrompt]		; DS:SI -> prompt
	sub	cx,cx
	test	si,si			; is there one?
	jz	il1			; no
	lodsb
	mov	cl,al
	PRINTF	<"%.*ls">,cx,si,ds
	les	di,[pPrompt]
	call	releaseStr
il1:	mov	ax,[wInFlags]
	test	al,1			; display "? "?
	jz	il2			; no
	PRINTF	<"? ">
il2:	push	ss
	pop	ds
	mov	bx,ds:[PSP_HEAP]
	lea	dx,[bx].LINEBUF		; DS:DX -> LINEBUF
	mov	word ptr [bx].LINEBUF,254; (INP_MAX = 254, INP_CNT = 0)
	mov	ah,DOS_TTY_INPUT
	int	21h
	PRINTF	<13,10>
	mov	ax,[wInFlags]
	shr	al,1
	mov	ah,al			; AH = 1 for LINE INPUT
	mov	al,KBD_HDL
	mov	word ptr [bx].FILE_CUR,ax
	mov	byte ptr [bx].FILE_POS,0	; start of the line
	pop	ds
	LEAVE
	RETURN
ENDPROC	inputLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fileItem
;
; Used by "INPUT" and "LINE INPUT" (and their # forms) for each variable, to
; get the next item (or line) of the keyboard line read by inputLine, or of
; the file selected by selectInput, as a string; genReadVars then converts it
; to the variable's type, as READ does with DATA items.
;
; As in MSBASIC, leading spaces, tabs, CRs, and LFs are skipped, and an item
; ends at a comma, CR, or LF, or for a numeric variable, a space or tab, too;
; a quoted item ends at its closing quote, and may contain commas.  A line
; (for LINE INPUT #) ends at a CR or LF.  CRLF counts as one delimiter, and
; a CTRLZ marks the end of the file.  Reading past the end of the file is an
; "Input past end" error.
;
; Inputs:
;	32-bit return value
;	16-bit variable type (popped)
;
; Outputs:
;	32-bit return value updated (the item's string value)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	fileItem,FAR
	RETVAR	retFI,dword
	ARGVAR	wFIType,word
	LOCVAR	fiEnd,word		; end of the data read
	LOCVAR	fiFile,word		; handle and LINE flag
	ENTER
	push	ds
	push	ss
	pop	ds
	push	ss
	pop	es
	mov	bx,ds:[PSP_HEAP]
	mov	ax,word ptr [bx].FILE_CUR
	mov	[fiFile],ax
;
;
; Read as much of the file as LINEBUF will hold, up to any CTRLZ, unless
; it's INPUT (from the keyboard), which already read a line into LINEBUF.
;
fi0:	mov	bx,ds:[PSP_HEAP]
	cmp	al,KBD_HDL		; keyboard?
	jne	fi0a			; no
	lea	si,[bx].LINEBUF+1
	lodsb				; AL = # characters
	mov	ah,0
	mov	di,si
	add	di,ax			; DI -> end of the line
	mov	[fiEnd],di
	mov	al,[bx].FILE_POS
	add	si,ax			; SI -> next character
	jmp	short fi2
fi0a:	lea	dx,[bx].LINEBUF		; DS:DX -> LINEBUF
	mov	bx,[fiFile]
	mov	bh,0			; BX = handle
	mov	cx,255
	mov	ah,DOS_HDL_READ
	int	21h			; AX = # bytes read
	jnc	fi1
	sub	ax,ax			; (treat an error like the end)
fi1:	mov	si,dx			; SI -> data
	xchg	cx,ax			; CX = # bytes read
	mov	di,si
	add	di,cx
	mov	[fiEnd],di		; save the end of the data
	mov	di,si
	jcxz	fi2
	mov	al,CHR_CTRLZ
	repne	scasb			; any CTRLZ?
	jne	fi2			; no (DI -> end of data)
	dec	di			; yes (DI -> CTRLZ)
fi2:	mov	dx,[wFIType]		; DL = variable type
	mov	ax,[fiFile]
	test	ah,ah			; LINE INPUT?
	jz	fi3			; no
	jmp	fi7			; yes
;
; Skip leading whitespace, and then find the end of the item.
;
fi3:	cmp	si,di
	jae	fiEOF
	lodsb
	cmp	al,' '
	je	fi3
	cmp	al,CHR_TAB
	je	fi3
	cmp	al,CHR_RETURN
	je	fi3
	cmp	al,CHR_LINEFEED
	je	fi3
	dec	si
	mov	cx,si			; CX -> start of item
	cmp	al,'"'			; quoted item?
	jne	fi5			; no
	inc	si
	inc	cx
fi4:	cmp	si,di			; find the closing quote
	jae	fi4a
	lodsb
	cmp	al,'"'
	jne	fi4
	dec	si
fi4a:	mov	bx,si			; BX -> end of item
	cmp	si,di
	jae	fi4c
	inc	si			; skip the closing quote
fi4b:	cmp	si,di			; and anything up to the delimiter
	jae	fi4c
	lodsb
	cmp	al,','
	je	fi4c
	cmp	al,CHR_RETURN
	je	fi4d
	cmp	al,CHR_LINEFEED
	jne	fi4b
fi4c:	jmp	fi9
fi4d:	jmp	fi8a
;
; If we ran out of data, but LINEBUF was full (eg, of blank lines), there
; may be more, so read again; otherwise, we're at the end of the file.
;
fiEOF:	mov	cx,si
	mov	bx,si			; (an empty item)
	mov	ax,[fiFile]
	cmp	al,KBD_HDL		; keyboard?
	je	fi4c			; yes, so the item is empty
	cmp	di,[fiEnd]		; did a CTRLZ end the data?
	jne	fiX			; yes
	mov	bx,ds:[PSP_HEAP]
	lea	ax,[bx].LINEBUF + 255
	cmp	ax,di			; was LINEBUF full?
	jne	fiX			; no
	mov	ax,[fiFile]
	jmp	fi0			; yes, so read more
fiX:	mov	al,62			; "Input past end"
	jmp	rtError

fi5:	cmp	si,di			; find the end of the unquoted item
	jae	fi6
	mov	al,[si]
	cmp	al,','
	je	fi6
	cmp	al,CHR_RETURN
	je	fi6
	cmp	al,CHR_LINEFEED
	je	fi6
	cmp	dl,VAR_STR		; string variable?
	je	fi5a			; yes (spaces don't end the item)
	cmp	al,' '
	je	fi6
	cmp	al,CHR_TAB
	je	fi6
fi5a:	inc	si
	jmp	fi5
fi6:	mov	bx,si			; BX -> end of item
fi6a:	cmp	bx,cx			; remove trailing whitespace
	jbe	fi8
	mov	al,[bx-1]
	cmp	al,' '
	je	fi6b
	cmp	al,CHR_TAB
	jne	fi8
fi6b:	dec	bx
	jmp	fi6a
;
; LINE INPUT # takes everything up to the end of the line.
;
fi7:	cmp	si,di
	jae	fiEOF
	mov	cx,si			; CX -> start of line
fi7a:	cmp	si,di
	jae	fi7b
	mov	al,[si]
	cmp	al,CHR_RETURN
	je	fi7b
	cmp	al,CHR_LINEFEED
	je	fi7b
	inc	si
	jmp	fi7a
fi7b:	mov	bx,si			; BX -> end of line
;
; Consume the delimiter at SI (if any), and if it's a CR, a following LF.
; At the read boundary, use the spare room after the data to read one more
; byte; fi9 seeks it back unless it's the LF that completes the delimiter.
;
fi8:	cmp	si,di
	jae	fi9
	lodsb
	cmp	al,CHR_RETURN
	jne	fi9
fi8a:	cmp	si,di
	jb	fi8b
	cmp	si,[fiEnd]		; did CR consume all the bytes read?
	jne	fi9
	mov	ax,[fiFile]		; (keyboard data has no CR)
	push	bx
	push	cx
	xchg	ax,bx
	mov	bh,0			; BX = handle
	mov	dx,si			; DS:DX -> byte after the buffered CR
	mov	cx,1
	mov	ah,DOS_HDL_READ
	int	21h
	pop	cx
	pop	bx
	jc	fi9
	dec	ax			; was a byte actually read?
	jnz	fi9
	inc	word ptr [fiEnd]	; count it in the seek back
fi8b:	cmp	byte ptr [si],CHR_LINEFEED
	jne	fi9
	inc	si
;
; The item is from CX to BX, and SI is the end of what we used, so seek back
; over the rest of the data, and then return the item as a string.
;
fi9:	push	cx
	push	bx
	mov	ax,[fiFile]
	cmp	al,KBD_HDL		; keyboard?
	jne	fi9b			; no
	mov	bx,ds:[PSP_HEAP]
	lea	ax,[bx].LINEBUF+2
	sub	ax,si
	neg	ax
	mov	[bx].FILE_POS,al	; save the position in the line
	jmp	short fi9a
fi9b:	mov	dx,[fiEnd]
	sub	dx,si			; DX = # bytes not used
	jz	fi9a
	neg	dx
	mov	cx,-1			; CX:DX = -DX
	mov	bx,[fiFile]
	mov	bh,0			; BX = handle
	mov	ax,DOS_HDL_SEEKCUR
	int	21h
fi9a:	pop	cx
	pop	si			; SI -> start of item
	sub	cx,si			; CX = length of item
	sub	ax,ax
	cwd				; DX:AX = empty string
	jcxz	fi10
	call	allocStr		; ES:DI -> new string
	mov	ax,di
	mov	dx,es			; DX:AX = string value
	inc	di
	rep	movsb			; copy the item to it
fi10:	mov	[retFI].OFF,ax
	mov	[retFI].SEG,dx
	pop	ds
	LEAVE
	RETURN
ENDPROC	fileItem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeValue
;
; Used by "WRITE [#n,]" for each value: numbers are written without leading
; or trailing spaces, strings are written in quotes, and the values are
; separated by commas, ending with CRLF after the last one.
;
; Inputs:
;	value (popped): 32-bit VAR_LONG, or a far pointer to a VAR_STR
;	or VAR_DOUBLE
;	16-bit type of the value (popped)
;	16-bit flag (popped): zero if more values follow
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	writeValue,FAR
	ARGVAR	wvValue,dword
	ARGVAR	wvType,word
	ARGVAR	wvLast,word
	ENTER
	push	ds
	mov	ax,[wvValue].OFF
	mov	dx,[wvValue].SEG
	mov	cx,[wvType]		; CL = type
	cmp	cl,VAR_LONG
	jne	wv1
	PRINTF	<"%ld">,ax,dx		; DX:AX = 32-bit value
	jmp	short wv8
wv1:	cmp	cl,VAR_DOUBLE
	jne	wv2
	PRINTF	<"%f">,ax,dx		; DX:AX -> double
	jmp	short wv8
wv2:	xchg	si,ax
	mov	ds,dx			; DS:SI -> string
	sub	cx,cx
	test	si,si			; empty string?
	jz	wv3			; yes
	lodsb
	mov	cl,al			; CX = length
wv3:	PRINTF	<34,"%.*ls",34>,cx,si,ds
	les	di,[wvValue]
	call	releaseStr
wv8:	mov	ax,[wvLast]
	test	al,al			; more values?
	jnz	wv9			; no
	PRINTF	<",">
	jmp	short wv10
wv9:	PRINTF	<13,10>
wv10:	pop	ds
	LEAVE
	RETURN
ENDPROC	writeValue

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; syncFiles
;
; Called by cleanUpTo after it closes the handles that a command opened, so
; that any OPEN file whose handle was closed is marked closed, too.
;
; Inputs:
;	SS:BX -> CMDHEAP
;
; Outputs:
;	None
;
; Modifies:
;	CX, SI, DI
;
DEFPROC	syncFiles
	lea	si,[bx].FILE_DATA
	mov	cx,FILE_MAX
sf1:	mov	di,ss:[si]
	and	di,0FFh			; DI = handle (0 if none)
	cmp	byte ptr ss:[PSP_PFT][di],SFH_NONE
	jne	sf2
	mov	ss:[si],ch		; zero the handle (CH is zero)
sf2:	add	si,FILE_SLOT
	loop	sf1
	ret
ENDPROC	syncFiles

CODE	ENDS

	end
