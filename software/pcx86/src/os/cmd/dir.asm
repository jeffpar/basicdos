;
; BASIC-DOS Directory Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<countLine,chkString,getFileName,noFile>
	EXTSTR	<DIR_DEF,PERIOD>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdChdir
;
; Change the current directory of a drive (eg, "CD SUBDIR"), or if nothing
; (or only a drive) is specified, display the drive's current directory.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdChdir
	mov	dl,[bx].CMD_ARG
	sub	cx,cx			; no default
	call	getFileName		; DS:SI -> directory, CX = length
	jc	ch2			; nothing specified
	cmp	cx,2			; only a drive?
	jne	ch1			; no
	cmp	byte ptr [si+1],':'
	je	ch3			; yes
ch1:	mov	dx,si
	mov	ah,DOS_DSK_CHDIR
	int	21h
	jc	ch1a
	ret
ch1a:	PRINTF	<"Unable to change to %s (%d)",13,10,13,10>,si,ax
	ret

ch2:	mov	ah,DOS_DSK_GETDRV
	int	21h			; AL = current drive #
	add	al,'A'			; AL = drive letter
	jmp	short ch4
ch3:	lodsb				; AL = drive letter
ch4:	call	getCwd			; DS:SI -> path
	jc	ch8
	PRINTF	<"%c:%c%s",13,10,13,10>,cx,dx,si
	ret
ch8:	PRINTF	<"Unable to find %c: (%d)",13,10,13,10>,cx,ax
	ret
ENDPROC	cmdChdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDir
;
; Print a directory listing for the specified filespec.
;
; Inputs:
;	BX -> CMDHEAP
;	DS:SI -> filespec (with length CX)
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDir
;
; If filespec begins with ":", extract drive letter, and if it ends
; with ":" as well, append DIR_DEF ("*.*").
;
	push	bp
	mov	dl,0			; DL = default drive #
	mov	di,cx			; DI = length of filespec
	cmp	cx,2
	jb	di2
	cmp	byte ptr [si+1],':'
	jne	di2
	mov	al,[si]
	sub	al,'A'-1
	jb	dix
	mov	dl,al			; DL = specific drive # (1-based)
di2:	mov	ah,DOS_DSK_GETINFO
	int	21h			; get disk info for drive
	jnc	di3
dix:	jmp	di8
;
; We primarily want the cluster size, in bytes, which this call doesn't
; provide directly; we must multiply bytes per sector (CX) by sectors per
; cluster (AX).
;
di3:	mov	bp,bx			; BP = available clusters
	mul	cx			; DX:AX = bytes per cluster
	xchg	bx,ax			; BX = bytes per cluster

	add	di,si			; DI -> end of filespec
	mov	ax,DOS_MSC_GETPCH
	int	21h			; DL = path char
	mov	dh,0			; DH = 0 (not a trial)
	mov	al,[di-1]
	cmp	al,':'			; does filespec end with ":"
	je	di3c			; or the path char?
	cmp	al,dl
	je	di3c			; yes, so just append DIR_DEF
;
; Otherwise, if filespec is a directory, then "filespec\*.*" will either
; succeed or fail with ERR_NOFILE; if it fails with ERR_NOPATH, then remove
; the path char and DIR_DEF, and try filespec on its own.
;
	mov	[di],dl			; append the path char
	inc	di
	inc	dh			; DH = 1 (trial)
di3c:	push	si
	push	di
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	REPS	MOVS,ES,CS,BYTE		; append DIR_DEF
	pop	di
	pop	si

di3a:	mov	cx,10h			; CX = attributes (DIRATTR_SUBDIR)
	push	dx
	mov	dx,si			; DX -> filespec
	mov	ah,DOS_DSK_FFIRST
	int	21h
	pop	dx
	jnc	di3b
	dec	dh			; was this a trial?
	jnz	dix			; no
	cmp	ax,ERR_NOPATH		; was filespec a directory?
	jne	dix			; yes
	mov	byte ptr [di-1],0	; no, so remove the path char, etc
	jmp	di3a
di3b:
;
; Use DX to maintain the total number of clusters, and CX to maintain
; the total number of files.
;
	sub	dx,dx
	sub	cx,cx
di4:	lea	si,ds:[PSP_DTA].FFB_NAME
;
; Beginning of "stupid" code to separate filename into name and extension.
;
	push	cx
	push	dx
	DOSUTIL	STRLEN
	xchg	cx,ax			; CX = total length
	cmp	byte ptr [si],'.'	; is it "." or ".."?
	je	di5			; yes, so there's no extension
	mov	dx,offset PERIOD
	call	chkString		; does the filename contain a period?
	jc	di5			; no
	mov	ax,di
	sub	ax,si			; AX = partial filename length
	inc	di			; DI -> character after period
	jmp	short di6
di5:	mov	ax,cx			; AX = complete filename length
	mov	di,si
	add	di,ax
;
; End of "stupid" code (which I'm tempted to eliminate, but since it's done...)
;
di6:	mov	dx,ds:[PSP_DTA].FFB_DATE
	mov	cx,ds:[PSP_DTA].FFB_TIME
	ASSERT	Z,<cmp ds:[PSP_DTA].FFB_SIZE.HIW,0>
	PRINTF	<"%-8.*s %-3s ">,ax,si,di
	test	ds:[PSP_DTA].FFB_ATTR,10h	; DIRATTR_SUBDIR?
	jnz	di6a
	PRINTF	<"%7ld">,ds:[PSP_DTA].FFB_SIZE,:2
	jmp	short di6b
di6a:	PRINTF	<"  ",3Ch,"DIR",3Eh>
di6b:	PRINTF	<" %2M-%02D-%02X %2G:%02N%A",13,10>,dx,dx,dx,cx,cx,cx
	call	countLine
;
; Update our totals
;
	mov	ax,ds:[PSP_DTA].FFB_SIZE.LOW
	mov	dx,ds:[PSP_DTA].FFB_SIZE.HIW
	lea	cx,[bx-1]
	add	ax,cx			; add cluster size - 1 to file size
	adc	dx,0
	div	bx			; # clusters = file size/cluster size
	pop	dx
	pop	cx
	add	dx,ax			; update our cluster total
	inc	cx			; and increment our file total

	mov	ah,DOS_DSK_FNEXT
	int	21h
	jc	di7
	jmp	di4

di7:	xchg	ax,dx			; AX = total # of clusters used
	mul	bx			; DX:AX = total # bytes
	PRINTF	<"%8d file(s) %8ld bytes",13,10>,cx,ax,dx
	call	countLine
	xchg	ax,bp			; AX = total # of clusters free
	mul	bx			; DX:AX = total # bytes free
	PRINTF	<"%25ld bytes free",13,10>,ax,dx
	pop	bp
	ret

di8:	PRINTF	<"Unable to find %s (%d)",13,10,13,10>,si,ax
	pop	bp
	ret
ENDPROC	cmdDir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getCwd
;
; Get the current directory of a drive (eg, for CD and the prompt).
;
; Inputs:
;	AL = drive letter (upper-case)
;	BX -> CMDHEAP
;
; Outputs:
;	CL = drive letter, DL = path char, DS:SI -> LINEBUF
;	If carry clear, LINEBUF contains the path (without the drive or
;	leading path char); otherwise, AX = error code
;
; Modifies:
;	AX, CX, DX, SI, DS
;
DEFPROC	getCwd
	push	ax
	mov	ax,DOS_MSC_GETPCH
	int	21h			; DL = path char
	pop	cx			; CL = drive letter
	push	dx
	mov	dl,cl
	sub	dl,'A'-1		; DL = 1-based drive #
	lea	si,[bx].LINEBUF
	push	ss
	pop	ds			; DS:SI -> buffer
	mov	ah,DOS_DSK_GETCWD
	int	21h
	pop	dx			; DL = path char
	ret
ENDPROC	getCwd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdMkdir
;
; Create a directory (MD or MKDIR), or with cmdRmdir, remove a directory
; (RD or RMDIR).
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdMkdir
	mov	al,DOS_DSK_MKDIR
	jmp	short md1
	DEFLBL	cmdRmdir,near
	mov	al,DOS_DSK_RMDIR
md1:	push	ax
	mov	dl,[bx].CMD_ARG
	sub	cx,cx			; no default
	call	getFileName		; DS:SI -> directory
	pop	ax
	jc	md8
	mov	ah,al
	mov	dx,si
	push	ax
	int	21h
	pop	dx			; DH = function
	jnc	md9
	cmp	dh,DOS_DSK_MKDIR
	jne	md2
	PRINTF	<"Unable to create %s (%d)",13,10,13,10>,si,ax
	ret
md2:	PRINTF	<"Unable to remove %s (%d)",13,10,13,10>,si,ax
	ret
md8:	jmp	noFile			; report a missing name
md9:	ret
ENDPROC	cmdMkdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkExt
;
; Check the last component of a path (DS:SI) for a period, so that periods
; in directory names (eg, "..") aren't mistaken for an extension.
;
; Inputs:
;	DS:SI -> null-terminated path
;
; Outputs:
;	If carry clear, DI points to the period; otherwise, DI = SI
;
; Modifies:
;	DI
;
DEFPROC	chkExt
	push	ax
	push	bx
	push	dx
	push	si
	mov	ax,DOS_MSC_GETPCH
	int	21h			; DL = path char
	mov	bx,si			; BX = DI if there's no period
	mov	di,bx
ce1:	lodsb
	cmp	al,'.'
	jne	ce2
	lea	di,[si-1]		; DI -> period
ce2:	cmp	al,dl			; path char?
	jne	ce3			; no
	mov	di,bx			; yes, so forget any earlier period
ce3:	test	al,al
	jnz	ce1
	cmp	bx,di
	cmc				; carry set if DI = BX (no period)
	pop	si
	pop	dx
	pop	bx
	pop	ax
	ret
ENDPROC	chkExt

CODE	ENDS

	end
