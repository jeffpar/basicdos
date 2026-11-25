;
; BASIC-DOS COPY Command
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; COPY (cmdCopy) and its helpers, which use the file functions in dir.asm;
; it's separate only because dir.asm has no symbol space for it.
;
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<getFileName,getToken,chkDir,freeEnv,openError,openInput>
	EXTNEAR	<openOutput,closeInput,closeOutput,readInput,writeOutput>
	EXTNEAR	<writeError,noFile,scanSpec,walkFiles>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdCopy
;
; Copy the specified input file to the specified output file, creating the
; output file if it doesn't exist (or truncating it if it does).  Like DOS,
; if the input is a device (eg, "COPY CON TEST.TXT"), CTRLZ ends the copy.
;
; If the output is omitted, it's the input filename (without any drive or
; path) in the current directory; if it's a drive or directory, the input
; filename is copied there.  An input filespec with wildcards copies every
; matching file (see walkFiles), and then the output must be a drive or
; directory (or omitted).  DOS keeps a file from being copied onto itself,
; since it can't be opened for writing while it's open for reading.
;
; Input files separated by '+' (eg, "COPY A+B+C D") are concatenated into the
; output file, which must be specified (see copyCat).  Files are always copied
; whole, as binary data, so /B (see CMD_SWITCHES) has no effect.
;
; cmdType uses cmdCopy with STDOUT as the output (so wildcards work, too),
; and like DOS, CTRLZ ends the output of every file (see copyData).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdType
	ASSERT	STRUCT,[bx],CMD
	mov	[bx].HDL_OUTPUT,STDOUT
	DEFLBL	cmdCopy,near
	push	di
	lea	di,[bx].LINEBUF + 128
	inc	cx
	rep	movsb			; move input filespec out of the way
	pop	di
	mov	dl,[bx].CMD_ARG
	call	getToken		; was an input filespec specified?
	jnc	cp0			; yes
	jmp	noFile
cp0:	lea	si,[bx].LINEBUF + 128	; DS:SI -> input filespec
	mov	cx,si			; CX = non-zero (for TYPE)
	cmp	[bx].HDL_OUTPUT,0	; do we already have an output (TYPE)?
	jge	cp3			; yes
	push	si
;
; The output filespec is the next argument that isn't a switch (eg, the /B in
; "COPY A /B" isn't the output).
;
cp1:	inc	dx			; DL = index of output filespec
	call	getToken
	jc	cp1a			; no more arguments
	mov	al,[si]
	cmp	al,[bx].SWITCH_CHAR
	je	cp1
cp1a:	sub	cx,cx			; (no default)
	call	getFileName		; DS:SI -> output filespec in LINEBUF
	lea	di,[bx].LINEBUF		; DI -> output filename buffer
	jc	cp2			; no output, so use input filename
	call	scanSpec		; any wildcards in the output?
	test	ah,ah
	jnz	cp5			; yes
	lea	di,[bx].LINEBUF
	add	di,cx			; DI -> end of output filespec
	call	chkDir			; is the output a directory?
	jnc	cp2			; yes (DI -> where to append input)
	sub	di,di			; no, so the output is a file
cp2:	mov	cx,di			; CX = output data for copyFile
	pop	si
	push	si
cp2a:	lodsb				; is the input a list of files
	cmp	al,'+'			; to concatenate?
	je	cp4			; yes
	test	al,al
	jnz	cp2a
	pop	si
cp3:	call	scanSpec		; any wildcards in the input?
	test	ah,ah
	jz	copyFile		; no
	jcxz	cp6			; yes, but the output is a single file
	mov	dx,offset copyWild
	call	walkFiles		; copy all the matching files
	jnc	cp9
	test	ax,ax			; was the error already reported?
	jz	cp8			; yes
	jmp	openError		; no, so report it now
cp4:	pop	si
	test	cx,cx			; the output must be a file
	jnz	cp6
	jmp	copyCat
cp5:	pop	si
cp6:	PRINTF	<"Invalid output",13,10>
	jmp	short cp8
cp8:	stc
cp9:	ret
ENDPROC	cmdType

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copyFile
;
; Copy one input file (or device) to an output file (or device): open the
; input, open the output, copy the data, and then close them both.  If the
; output is already open (eg, STDOUT for TYPE), it's used and left open.
; Like DOS, the output gets the input file's date and time (a concatenated
; copy keeps the current date and time; see copyCat).  copyWild (for
; walkFiles) prints the input filename first.
;
; Inputs:
;	BX -> CMDHEAP
;	SS:SI -> input filename
;	CX = 0 if LINEBUF contains the output filename; otherwise, CX -> where
;	to append the input filename (without any drive or path) in LINEBUF
;
; Outputs:
;	Carry clear if successful; otherwise, carry set and AX = 0 (the error
;	was reported)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	copyWild
	PRINTF	<"%s",13,10>,si
	DEFLBL	copyFile,near
	call	openInput		; open the input file
	jc	cf8
	cmp	[bx].HDL_OUTPUT,0	; do we already have an output?
	jge	cf3			; yes
	jcxz	cf2			; LINEBUF contains the output filename
	call	scanSpec		; DI -> input name (sans drive/path)
	xchg	si,di
	mov	di,cx
cf1:	lodsb				; append it to the output
	stosb
	test	al,al
	jnz	cf1
cf2:	lea	si,[bx].LINEBUF		; SI -> output filename
	call	openOutput		; open the output file
	jnc	cf3
	cmp	ax,ERR_SHARE		; is the output the input file?
	jne	cf8			; no
	PRINTF	<"File cannot be copied onto itself",13,10>
	jmp	short cf9
cf3:	push	bx
	mov	bx,[bx].HDL_INPUT
	mov	ax,DOS_HDL_GETTIME
	int	21h			; CX = time, DX = date (0 for a device)
	pop	bx
	push	cx
	push	dx
	call	copyData		; copy (and close) the input
	pop	dx
	pop	cx
	jc	cf9
	test	dx,dx			; does the input have a date?
	jz	cf3c			; no (it's a device)
	push	bx
	mov	bx,[bx].HDL_OUTPUT
	mov	ax,DOS_HDL_SETTIME
	int	21h			; give the output the input's date and time
	pop	bx
cf3c:	call	closeOutput		; close the output (if we opened it)
	jnc	cf9a
cf7a:	call	writeError		; report a failure to update the file
	jmp	short cf9
cf8:	call	openError		; report error (AX) opening file (SI)
cf9:	sub	ax,ax			; AX = 0 (the error was reported)
	stc
cf9a:	ret
ENDPROC	copyWild

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copyCat
;
; Concatenate input files separated by '+' (eg, "A+B+C") into the output file
; (in LINEBUF), which is created first (or truncated if it exists).
;
; Inputs:
;	BX -> CMDHEAP
;	SS:SI -> input filenames
;
; Outputs:
;	Carry clear if successful; otherwise, carry set (the error was reported)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	copyCat
	push	si
	lea	si,[bx].LINEBUF		; SI -> output filename
	call	openOutput		; open the output file
	pop	si
	jnc	cc1
	lea	si,[bx].LINEBUF
	jmp	short cc8
cc1:	mov	di,si			; DI -> next input filename
cc2:	lodsb
	cmp	al,'+'			; end of this filename?
	je	cc3			; yes
	test	al,al			; end of all the filenames?
	jnz	cc2			; no
cc3:	mov	byte ptr [si-1],0	; null-terminate this filename
	push	ax			; AL = '+' if more filenames follow
	push	si			; SI -> next filename (if any)
	mov	si,di
	call	openInput		; open this input file
	jc	cc7
	call	copyData		; copy (and close) it
	pop	si
	pop	ax
	jc	cc9
	cmp	al,'+'			; more filenames?
	je	cc1			; yes
	call	closeOutput		; no, so close the output
	jnc	cc9a
	call	writeError		; report a failure to update the file
	jmp	short cc9
cc7:	pop	cx
	pop	cx
cc8:	call	openError		; report error (AX) opening file (SI)
cc9:	stc
cc9a:	ret
ENDPROC	copyCat

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; copyData
;
; Copy the data from the input file (or device) to the output file (or
; device), and then close the input.  Like DOS, CTRLZ ends the data from a
; device, and for TYPE (ie, when the output is STDOUT), from a file, too.
;
; Unless the input is a device (or memory is short), the data goes through a
; temporary block instead of the DTA, since reading or writing part of a sector
; goes through the disk driver's one-sector buffer, and when the input and
; output are on the same drive, they keep replacing each other there.  The
; block's segment goes in EPB_ENVSEG (no program is running), so that freeEnv
; frees it, even if a CTRLC ends the copy (see ctrlc).  Output to a device is
; still written in small pieces, since DOS checks for CTRLC between writes.
;
; Inputs:
;	BX -> CMDHEAP
;	HDL_INPUT and HDL_OUTPUT are open
;
; Outputs:
;	Carry clear if successful; otherwise, carry set (the error was reported)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
COPY_BUFLEN	equ	8000h		; largest temporary block

DEFPROC	copyData
	push	bp
	mov	si,[bx].HDL_INPUT
	call	chkDevice		; DX = 80h if the input is a device
	cmp	[bx].HDL_OUTPUT,STDOUT	; is this TYPE?
	jne	cf3b			; no
	inc	dx			; yes, so CTRLZ ends a file, too
cf3b:	mov	di,dx			; DI bits 0 and 7 are set if CTRLZ does
	mov	si,[bx].HDL_OUTPUT
	call	chkDevice		; DX = 80h if the output is a device
	shr	dx,1
	or	di,dx			; DI bit 6 is set if it's a device
	mov	si,PSP_DTA		; SI -> DTA (used as a read buffer)
	mov	bp,size PSP_DTA		; BP = number of bytes to read
	test	di,80h			; is the input a device?
	jnz	cf4			; yes, so the DTA will do
	push	bx
	mov	bx,COPY_BUFLEN SHR 4	; BX = # paragraphs
cd1:	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h			; AX = segment of the block
	jnc	cd2
	shr	bx,1			; BX = half of the largest block
	cmp	bx,512 SHR 4		; does that hold a sector?
	jae	cd1			; yes
	pop	bx			; no, so the DTA will have to do
	jmp	short cf4
cd2:	mov	cl,4
	shl	bx,cl
	mov	bp,bx			; BP = number of bytes to read
	pop	bx
	mov	[bx].EXECDATA.EPB_ENVSEG,ax
	mov	ds,ax
	mov	es,ax
	sub	si,si			; DS:SI -> block
cf4:	mov	cx,bp			; CX = number of bytes to read
	call	readInput
	jc	cy7
	test	ax,ax			; anything read?
	jz	cy7			; no (and carry is clear)
	xchg	cx,ax			; CX = number of bytes to write
	test	di,81h			; does CTRLZ end the data?
	jz	cf6			; no
	push	di
	mov	di,si
	mov	dx,cx			; DX = number of bytes read
	mov	al,CHR_CTRLZ
	repne	scasb			; any CTRLZ?
	pop	di
	xchg	cx,dx			; CX = number of bytes read
	jne	cf6			; no
	sub	cx,dx			; yes, so write only bytes before it
	dec	cx
	mov	di,-1			; and then stop
cf6:	push	si
cf6a:	push	cx			; save number of bytes left
	test	di,40h			; is the output a device?
	jz	cf6b			; no
	cmp	cx,size PSP_DTA		; yes, so is this more than a piece?
	jbe	cf6b			; no
	mov	cx,size PSP_DTA		; yes
cf6b:	call	writeOutput
	pop	dx			; DX = number of bytes left
	jc	cf6c
	add	si,cx
	sub	dx,cx			; (carry is clear)
	mov	cx,dx
	jnz	cf6a			; write the next piece
cf6c:	pop	si
	jc	cy7
	test	di,di			; did input end with CTRLZ?
	jns	cf4			; no (and carry is clear)
cy7:	push	ss
	pop	ds
	push	ss
	pop	es			; (they can't hold a freed segment)
	pushf
	mov	bp,bx
	call	freeEnv			; free the block, if any
	popf
	pop	bp
	jc	cy9
	call	closeInput		; close the input
	clc
cy9:	ret
ENDPROC	copyData

;
; chkDevice returns DX = 80h if the handle in SI is a device, otherwise zero.
;
DEFPROC	chkDevice
	push	bx
	mov	bx,si
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDATA
	int	21h			; DX bit 7 set if it's a device
	pop	bx
	jnc	$+4
	sub	dx,dx
	and	dx,80h
	ret
ENDPROC	chkDevice

CODE	ENDS

	end
