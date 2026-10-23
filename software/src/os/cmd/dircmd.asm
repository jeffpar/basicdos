;
; BASIC-DOS Directory Listing Command
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; DIR (cmdDir) and its helpers; the other directory commands, and the helpers
; that DIR shares with them (eg, chkDir and fileError), are in dir.asm.
;
	DOSFFB equ 1
	DOSFUNC equ 1
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<chkString,chkDir,fileError>
	EXTSTR	<DIR_DEF,PERIOD>
	EXTBYTE	<VERB_FIND>

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDir
;
; Print a directory listing for the specified filespec.  Hidden files are
; listed only with /A (in BASIC-DOS, only the hidden attribute keeps a file
; out of a listing, so system files are listed, too), and with /S, the
; matching files in every subdirectory are listed as well, each directory with
; its own header and totals (see dirTree).
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
DIRF_SUBS	equ	01h		; /S (list subdirectories, too)
DIRF_LISTED	equ	02h		; a directory has been listed
FFB_SAVE	equ	(size FFB + 1) AND NOT 1

DEFPROC	cmdDir
	LOCVAR	dirClus,word		; bytes per cluster
	LOCVAR	dirFree,word		; available clusters
	LOCVAR	dirDrive,word		; drive letter
	LOCVAR	dirAttr,byte		; search attributes
	LOCVAR	dirFlags,byte		; DIRF_* flags
	LOCVAR	dirPat,byte,14		; last component of the filespec
	ENTER
	mov	di,si
	add	di,cx			; DI -> end of filespec
	call	chkDir			; is the filespec a directory?
	jc	di1			; no
	push	si
	mov	cx,DIR_DEF_LEN
	mov	si,offset DIR_DEF
	REPS	MOVS,ES,CS,BYTE		; yes, so append DIR_DEF
	pop	si
;
; Split the filespec into its directory part (which dirTree extends with the
; name of each subdirectory) and its last component (eg, "*.*"), which we
; save in dirPat.
;
di1:	mov	dx,si			; DX -> after the last ':' or path char
di1a:	lodsb
	cmp	al,':'
	je	di1b
	cmp	al,[bx].PATH_CHAR
	jne	di1c
di1b:	mov	dx,si
di1c:	test	al,al
	jnz	di1a
	mov	si,dx
	lea	di,[dirPat]
	mov	cx,13			; (8 + 3 characters, a period, and 0)
	rep	movsb
	mov	[dirPat+13],cl		; (in case the component was longer)
	mov	di,dx			; DI -> end of the directory part
	mov	al,14h			; AL = attributes (DIRATTR_SUBDIR and
	TESTSW	<'A'>			; DIRATTR_SYSTEM); /A?
	jz	di2			; no
	or	al,02h			; yes (add DIRATTR_HIDDEN)
di2:	mov	[dirAttr],al
	sub	ax,ax
	TESTSW	<'S'>			; /S?
	jz	di3			; no
	inc	ax			; AL = DIRF_SUBS
di3:	mov	[dirFlags],al
	call	dirTree
	jc	di8
	test	[dirFlags],DIRF_LISTED	; did anything match?
	jz	di7			; no
	mov	ax,[dirFree]
	mul	[dirClus]		; DX:AX = total # bytes free
	PRINTF	<"%25ld bytes free",13,10>,ax,dx
	clc
	jmp	short di9
di7:	call	dirSpec			; restore the original filespec
	mov	ax,ERR_NOFILE
di8:	lea	si,[bx].LINEBUF		; DS:SI -> filespec
	mov	dx,offset VERB_FIND
	call	fileError
di9:	LEAVE
	ret
ENDPROC	cmdDir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dirTree
;
; List the files in a directory that match dirPat, and then for /S, do the
; same for each of its subdirectories (recursively).  Since every search uses
; the DTA, a directory's FFB is saved on the stack while its subdirectories
; are searched, and then restored to continue its own search.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> end of the directory part of the filespec (in LINEBUF)
;	BP -> cmdDir's frame
;
; Outputs:
;	Carry set on error (AX = error code), but not if nothing matches
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	dirTree
	call	dirSpec			; append dirPat to the directory part
	call	dirFirst		; find the first match
	jnc	dt1
	cmp	ax,ERR_NOFILE		; no matches?
	stc
	jne	dt9			; no, some other error
	jmp	short dt2
dt1:	call	dirList			; list the matches
	jc	dt9
dt2:	test	[dirFlags],DIRF_SUBS	; /S?
	jz	dt9			; no (carry clear)
	push	di
	mov	ax,'*' OR ('.' SHL 8)
	stosw
	mov	ax,'*'
	stosw				; search "*.*" (all the entries)
	pop	di
	call	dirFirst
dt3:	jc	dt8			; no (more) entries
	test	ds:[PSP_DTA].FFB_ATTR,10h ; DIRATTR_SUBDIR?
	jz	dt7			; no
	cmp	ds:[PSP_DTA].FFB_NAME,'.'
	je	dt7			; it's "." or ".."
	push	di
	sub	sp,FFB_SAVE
	mov	si,PSP_DTA
	mov	di,sp
	mov	cx,FFB_SAVE SHR 1
	rep	movsw			; save the FFB
	mov	di,[di]			; DI -> end of the directory part
	lea	si,ds:[PSP_DTA].FFB_NAME
dt4:	lodsb
	test	al,al
	jz	dt5
	stosb
	jmp	dt4
dt5:	mov	al,[bx].PATH_CHAR
	stosb				; append the subdirectory and path char
	call	dirTree
	mov	si,sp
	mov	di,PSP_DTA
	mov	cx,FFB_SAVE SHR 1
	rep	movsw			; restore the FFB (carry unchanged)
	mov	sp,si
	pop	di
	jc	dt9
dt7:	mov	ah,DOS_DSK_FNEXT
	int	21h
	jmp	dt3
dt8:	clc
dt9:	ret
ENDPROC	dirTree

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dirSpec
;
; Append dirPat to the directory part of the filespec, and (dirFirst) find the
; first match in the DTA.
;
; Inputs:
;	DI -> end of the directory part of the filespec (in LINEBUF)
;	BP -> cmdDir's frame
;
; Outputs:
;	For dirFirst, carry set on error (AX = error code)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	dirSpec
	push	di
	lea	si,[dirPat]
ds1:	lodsb
	stosb
	test	al,al
	jnz	ds1
	pop	di
	ret
	DEFLBL	dirFirst,near
	mov	cl,[dirAttr]
	mov	ch,0			; CX = search attributes
	lea	dx,[bx].LINEBUF		; DX -> filespec
	mov	ah,DOS_DSK_FFIRST
	int	21h
	ret
ENDPROC	dirSpec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dirList
;
; List the matches of a search (the first of which is in the DTA), after the
; directory's header (see dirHeader), followed by their totals.
;
; Inputs:
;	BX -> CMDHEAP
;	BP -> cmdDir's frame
;
; Outputs:
;	Carry set on error (AX = error code)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	dirList
	call	dirHeader
	jnc	dl1
	ret
dl1:	push	bx
	push	di
	mov	bx,[dirClus]		; BX = bytes per cluster
;
; Use DX to maintain the total number of clusters, and CX to maintain
; the total number of files.
;
	sub	dx,dx
	sub	cx,cx
dl4:	push	cx
	push	dx
	call	splitName		; AX = name length, SI, DI
	mov	dx,' '			; (a hidden file gets '*' instead)
	test	ds:[PSP_DTA].FFB_ATTR,02h ; DIRATTR_HIDDEN?
	jz	dl5
	mov	dl,'*'
dl5:	PRINTF	<"%-8.*s %-3s%c">,ax,si,di,dx
	mov	dx,ds:[PSP_DTA].FFB_DATE
	mov	cx,ds:[PSP_DTA].FFB_TIME
	test	ds:[PSP_DTA].FFB_ATTR,10h ; DIRATTR_SUBDIR?
	jnz	dl6a
	PRINTF	<"%7ld">,ds:[PSP_DTA].FFB_SIZE,:2
	jmp	short dl6b
dl6a:	PRINTF	<"  ",3Ch,"DIR",3Eh>
dl6b:	PRINTF	<" %2M-%02D-%02X %2G:%02N%A",13,10>,dx,dx,dx,cx,cx,cx
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
	jc	dl7
	jmp	dl4

dl7:	xchg	ax,dx			; AX = total # of clusters used
	mul	bx			; DX:AX = total # bytes
	PRINTF	<"%8d file(s) %8ld bytes",13,10>,cx,ax,dx
	pop	di
	pop	bx
	clc
	ret
ENDPROC	dirList

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; dirHeader
;
; Print the DOS 2.x-style header of a directory listing: a blank line, the
; path of the directory being listed (which the kernel derives from the FFB of
; the filespec's first match), and a blank line.  Before the first listing,
; the drive's volume label is printed, too, and the drive's cluster size and
; available clusters are saved for the totals; searching for the volume label
; replaces the FFB, so the first match is found again.
;
; Inputs:
;	BX -> CMDHEAP
;	BP -> cmdDir's frame
;	DTA -> FFB of the first match
;
; Outputs:
;	If carry clear, the DTA contains the first match; otherwise,
;	AX = error code
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	dirHeader
	mov	al,ds:[PSP_DTA].FFB_DRIVE
	push	ax
	add	al,'A'
	cbw
	mov	[dirDrive],ax		; drive letter
	pop	dx
	test	[dirFlags],DIRF_LISTED	; was the volume label printed?
	jz	dh0			; no
	PRINTF	<13,10>
	jmp	dh4
dh0:	or	[dirFlags],DIRF_LISTED
	inc	dx			; DL = 1-based drive #
	mov	ah,DOS_DSK_GETINFO
	int	21h			; get disk info for drive
	jnc	dh0a
	ret
;
; We primarily want the cluster size, in bytes, which this call doesn't
; provide directly; we must multiply bytes per sector (CX) by sectors per
; cluster (AX).
;
dh0a:	mov	[dirFree],bx		; available clusters
	mul	cx
	mov	bx,ds:[PSP_HEAP]	; BX -> CMDHEAP again
	mov	[dirClus],ax		; bytes per cluster
	push	di
	lea	di,[bx].LINEBUF+176	; (past the filespec in LINEBUF)
	mov	dx,di			; DX -> volume label filespec
	mov	ax,[dirDrive]
	mov	ah,':'
	stosw				; "d:"
	mov	al,[bx].PATH_CHAR
	stosb				; path char
	mov	si,offset DIR_DEF
	mov	cx,DIR_DEF_LEN
	REPS	MOVS,ES,CS,BYTE		; and DIR_DEF
	pop	di
	mov	cl,08h			; CX = attributes (DIRATTR_VOLUME)
	mov	ah,DOS_DSK_FFIRST
	int	21h
	jnc	dh1
	cmp	ax,ERR_NOFILE		; is there no volume label?
	stc
	je	dh1			; right (and carry is set)
	ret				; no, some other error
dh1:	pushf
	PRINTF	<13,10," Volume in drive %c ">,[dirDrive]
	popf
	jnc	dh2
	PRINTF	<"has no label",13,10>
	jmp	short dh2a
dh2:	push	di
	call	splitName		; AX = name length, SI, DI
	PRINTF	<"is %-8.*s%s",13,10>,ax,si,di
	pop	di
dh2a:	call	dirFirst		; find the first match again
	jc	dh9
dh4:	lea	si,[bx].LINEBUF+192	; DS:SI -> 64-byte path buffer
	mov	dl,0FFh			; DL = 0FFh (the FFB's directory)
	mov	ah,DOS_DSK_GETCWD
	int	21h
	jc	dh9
	mov	dl,[bx].PATH_CHAR
	PRINTF	<" Directory of %c:%c%s",13,10,13,10>,[dirDrive],dx,si
	clc
dh9:	ret
ENDPROC	dirHeader

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; splitName
;
; Separate the name in the DTA's FFB into a name and an extension (eg, for
; DIR's columns, or a volume label without its period).
;
; Inputs:
;	DTA -> FFB
;
; Outputs:
;	AX = name length, SI -> name, DI -> extension (null-terminated)
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	splitName
	lea	si,ds:[PSP_DTA].FFB_NAME
;
; Beginning of "stupid" code to separate filename into name and extension.
;
	DOSUTIL	STRLEN
	xchg	cx,ax			; CX = total length
	cmp	byte ptr [si],'.'	; is it "." or ".."?
	je	sn1			; yes, so there's no extension
	mov	dx,offset PERIOD
	call	chkString		; does the filename contain a period?
	jc	sn1			; no
	mov	ax,di
	sub	ax,si			; AX = partial filename length
	inc	di			; DI -> character after period
	ret
sn1:	mov	ax,cx			; AX = complete filename length
	mov	di,si
	add	di,ax
;
; End of "stupid" code (which I'm tempted to eliminate, but since it's done...)
;
	ret
ENDPROC	splitName

CODE	ENDS

	end
