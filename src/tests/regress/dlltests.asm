;
; BASIC-DOS NE Library Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; DLLTESTS.EXE is an NE program (see DLLTESTS.DEF) that imports DOSCALLS.DLL's
; functions by ordinal, so it tests the NE loader's library support (see
; load_ne) and the functions themselves: it calls DosWrite directly (calls
; that share one relocation record) and through a far pointer in its data
; segment (another record, in another segment), then every other function
; except DosExecPgm, checking each result against the DOS call it stands for,
; and ends with DosExit.  A failure names the check that failed (they're
; numbered in order).  In real mode, where the kernel doesn't load NE
; programs, its stub (this file assembled with STUB defined) just says that
; the tests were skipped.
;
	DOSFUNC equ 1
	include	macros.inc
	include	dosapi.inc
	include	os2.inc

	IFNDEF	STUB
	.286c
	extrn	DOSEXIT:far,DOSSETSIGHANDLER:far,DOSALLOCSEG:far
	extrn	DOSREALLOCSEG:far,DOSFREESEG:far,DOSGETMACHINEMODE:far
	extrn	DOSDEVIOCTL:far,DOSCHGFILEPTR:far,DOSCLOSE:far,DOSDELETE:far
	extrn	DOSNEWSIZE:far,DOSOPEN:far,DOSQCURDISK:far,DOSQFILEMODE:far
	extrn	DOSQHANDTYPE:far,DOSSETMAXFH:far,DOSSETVEC:far
	extrn	DOSGETVERSION:far,DOSGETPID:far,DOSREAD:far,DOSWRITE:far
	extrn	DOSFINDCLOSE:far,DOSFINDFIRST:far,DOSFINDNEXT:far
;
; PUSHP pushes a far pointer to one of our variables.
;
PUSHP	macro	var
	push	ds
	push	offset DGROUP:var
	endm

;
; LINK4 needs an automatic data segment (DGROUP), which holds our data and
; stack; the stub has only a stack, which follows its code.
;
_DATA	segment word public 'DATA'
pWrite	dd	DOSWRITE
written	dw	-1
step	dw	0
sp0	dw	0
hf	dw	0
action	dw	0
pos	dd	0
value	dw	0
drive	dw	0
drives	dd	0
pidinfo	dw	3 dup (0)
htype	dw	0
hflags	dw	0
sel	dw	0
prev	dd	0
hdir	dw	HDIR_CREATE
nfound	dw	1
ffbuf	FILEFINDBUF <>
buf	db	16 dup (0)
fname	db	"DLLTESTS.TMP",0
msg1	db	"DOSCALLS "
MSG1_LEN equ	$ - msg1
msg2	db	"calls "
MSG2_LEN equ	$ - msg2
msg3	db	"returned",13,10
MSG3_LEN equ	$ - msg3
passed	db	"DLLTESTS passed",13,10,'$'
failed	db	13,10,"DLLTESTS failed (check "
failnum	db	"00)",13,10,'$'
_DATA	ends

STACK	segment	stack
	dw	512 dup (?)
STACK	ends

DGROUP	group	_DATA,STACK
	ENDIF

CODE	segment word public 'CODE'

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

	IFDEF	STUB

DEFPROC	main
	push	cs
	pop	ds
	mov	dx,offset skipped
	mov	ah,DOS_TTY_PRINT
	int	21h
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
ENDPROC	main

skipped	db	"DLLTESTS skipped",13,10,'$'

	ELSE

DEFPROC	main
	mov	ax,DGROUP
	mov	ds,ax
	ASSUME	DS:DGROUP
	mov	[sp0],sp
;
; DosWrite, to the standard output handle.
;
	mov	dx,1
	mov	si,offset DGROUP:msg1
	mov	cx,MSG1_LEN
	call	pushArgs
	call	DOSWRITE		; write "DOSCALLS "
	call	chkw
	mov	si,offset DGROUP:msg2
	mov	cx,MSG2_LEN
	call	pushArgs
	call	[pWrite]		; write "calls "
	call	chkw
	mov	si,offset DGROUP:msg3
	mov	cx,MSG3_LEN
	call	pushArgs
	call	DOSWRITE		; write "returned"
	call	chkw
;
; DosGetMachineMode, DosGetVersion, DosGetPid, and DosQCurDisk.
;
	dec	[value]
	PUSHP	value
	call	DOSGETMACHINEMODE
	call	chk0
	cmp	byte ptr [value],1	; protected mode?
	call	chkz
	PUSHP	value
	call	DOSGETVERSION
	call	chk0
	mov	ah,DOS_MSC_GETVER
	int	21h
	xchg	al,ah
	cmp	ax,[value]
	call	chkz
	PUSHP	pidinfo
	call	DOSGETPID
	call	chk0
	mov	ah,DOS_PSP_GET
	int	21h
	cmp	bx,[pidinfo]
	call	chkz
	cmp	[pidinfo+2],1
	call	chkz
	PUSHP	drive
	PUSHP	drives
	call	DOSQCURDISK
	call	chk0
	mov	ah,DOS_DSK_GETDRV
	int	21h
	cbw
	xchg	cx,ax			; CX = current drive
	mov	ax,1
	shl	ax,cl
	test	word ptr [drives],ax	; is its bit set?
	call	chknz
	inc	cx
	cmp	cx,[drive]
	call	chkz
;
; DosSetMaxFH (a PSP has 20 handles) and DosQHandType.
;
	push	20
	call	DOSSETMAXFH
	call	chk0
	push	21
	call	DOSSETMAXFH
	call	chkerr
	push	1
	PUSHP	htype
	PUSHP	hflags
	call	DOSQHANDTYPE
	call	chk0
;
; DosOpen (create or replace), DosWrite, DosChgFilePtr, DosNewSize,
; DosRead, and DosClose.
;
	mov	ax,12h
	call	open
	call	chk0
	cmp	[action],1		; created (2) or replaced (3)?
	call	chknz
	push	[hf]
	PUSHP	htype
	PUSHP	hflags
	call	DOSQHANDTYPE
	call	chk0
	cmp	[htype],0		; a file?
	call	chkz
	mov	dx,[hf]
	mov	si,offset DGROUP:msg1
	mov	cx,MSG1_LEN
	call	pushArgs
	call	DOSWRITE
	call	chkw
	mov	ax,2
	call	seek			; the end is the file's size
	cmp	word ptr [pos],MSG1_LEN
	call	chkz
	push	[hf]
	push	0
	push	4
	call	DOSNEWSIZE		; set the file's size to 4
	call	chk0
	mov	ax,1
	call	seek			; which doesn't move its position
	cmp	word ptr [pos],MSG1_LEN
	call	chkz
	mov	ax,2
	call	seek
	cmp	word ptr [pos],4
	call	chkz
	mov	ax,0
	call	seek
	push	[hf]
	PUSHP	buf
	push	size buf
	PUSHP	written
	call	DOSREAD
	call	chk0
	cmp	[written],4
	call	chkz
	cmp	word ptr [buf],'OD'	; the first two bytes of msg1?
	call	chkz
	call	close
;
; DosFindFirst (with a new directory handle), DosFindNext (there's only one
; such file), DosFindClose (twice, since the handle is then invalid), and
; DosFindFirst with the system's handle and a buffer that's too small.
;
	mov	ax,size ffbuf
	call	find
	call	chk0
	cmp	[nfound],1
	call	chkz
	cmp	word ptr [ffbuf].FF_SIZE,4
	call	chkz
	cmp	[ffbuf].FF_NAMELEN,12	; the length of fname?
	call	chkz
	push	[hdir]
	PUSHP	ffbuf
	push	size ffbuf
	PUSHP	nfound
	call	DOSFINDNEXT
	cmp	ax,ERROR_NO_MORE_FILES
	call	chkz
	push	[hdir]
	call	DOSFINDCLOSE
	call	chk0
	push	[hdir]
	call	DOSFINDCLOSE
	call	chkerr
	mov	[hdir],HDIR_SYSTEM
	mov	ax,size ffbuf - 1
	call	find
	call	chkerr
;
; DosOpen (an existing file, and a new file only), DosQFileMode, and
; DosDelete.
;
	mov	ax,01h
	call	open
	call	chk0
	cmp	[action],1		; existed?
	call	chkz
	call	close
	mov	ax,10h
	call	open			; it exists, so this fails
	call	chkerr
	call	qmode
	call	chk0
	PUSHP	fname
	push	0
	push	0
	call	DOSDELETE
	call	chk0
	call	qmode
	call	chkerr
	mov	ax,01h
	call	open			; it doesn't exist, so this fails
	call	chkerr
;
; DosAllocSeg, DosReallocSeg, and DosFreeSeg (which zeroes our ES, since ES
; is the segment).
;
	push	100
	PUSHP	sel
	push	0
	call	DOSALLOCSEG
	call	chk0
	mov	es,[sel]
	mov	word ptr es:[98],1234h
	push	2000
	push	[sel]
	call	DOSREALLOCSEG
	call	chk0
	mov	es,[sel]
	cmp	word ptr es:[98],1234h
	call	chkz
	mov	word ptr es:[1998],5678h
	push	[sel]
	call	DOSFREESEG
	call	chk0
	mov	ax,es
	test	ax,ax
	call	chkz
	push	[sel]
	call	DOSFREESEG		; it's already free, so this fails
	call	chkerr
;
; DosSetSigHandler (accept CTRL-C signals, then back to the default, and an
; unsupported signal), DosSetVec (get a vector), and DosDevIOCtl.
;
	push	cs
	push	offset sighand
	PUSHP	prev
	PUSHP	value
	push	2
	push	1
	call	DOSSETSIGHANDLER
	call	chk0
	cmp	[value],0		; was the action the default?
	call	chkz
	push	0
	push	0
	PUSHP	prev
	PUSHP	value
	push	0
	push	1
	call	DOSSETSIGHANDLER
	call	chk0
	cmp	[value],2		; was the action ours?
	call	chkz
	cmp	[prev]._OFF,offset sighand
	call	chkz
	push	0
	push	0
	push	0
	push	0
	push	0
	push	0
	push	0
	push	3
	call	DOSSETSIGHANDLER
	call	chkerr
	push	0
	push	0
	push	0
	PUSHP	prev
	call	DOSSETVEC
	call	chk0
	push	0
	push	0
	push	0
	push	0
	push	20h
	push	8
	push	1
	call	DOSDEVIOCTL
	call	chkerr
;
; Every function must have removed its parameters.
;
	cmp	sp,[sp0]
	call	chkz
	mov	dx,offset DGROUP:passed
	mov	ah,DOS_TTY_PRINT
	int	21h
	push	1			; end the process
	push	0			; with exit code 0
	call	DOSEXIT
	sub	ax,ax
	inc	ax			; DosExit returned
	call	chk0
ENDPROC	main

;
; pushArgs pushes DosRead's and DosWrite's parameters, for CX bytes at DS:SI
; and handle DX.
;
DEFPROC	pushArgs
	pop	bx			; BX = return address
	push	dx			; file handle
	push	ds
	push	si			; buffer
	push	cx			; # bytes
	PUSHP	written			; where to store the # written
	jmp	bx
ENDPROC	pushArgs

;
; find calls DosFindFirst for our file, with a buffer of AX bytes.
;
DEFPROC	find
	PUSHP	fname
	PUSHP	hdir
	push	0			; attributes
	PUSHP	ffbuf
	push	ax			; size of the buffer
	PUSHP	nfound
	push	0
	push	0
	call	DOSFINDFIRST
	ret
ENDPROC	find

;
; open calls DosOpen for our file, with open flags AX, to read and write;
; seek calls DosChgFilePtr for it with method AX and no distance, and checks
; the result; close calls DosClose for it and checks the result; and qmode
; calls DosQFileMode for it.
;
DEFPROC	open
	PUSHP	fname
	PUSHP	hf
	PUSHP	action
	push	0
	push	0			; initial size
	push	0			; attributes
	push	ax			; open flags
	push	2			; open mode
	push	0
	push	0
	call	DOSOPEN
	ret
ENDPROC	open

DEFPROC	seek
	push	[hf]
	push	0
	push	0
	push	ax
	PUSHP	pos
	call	DOSCHGFILEPTR
	jmp	short chk0
ENDPROC	seek

DEFPROC	close
	push	[hf]
	call	DOSCLOSE
	jmp	short chk0
ENDPROC	close

DEFPROC	qmode
	PUSHP	fname
	PUSHP	value
	push	0
	push	0
	call	DOSQFILEMODE
	ret
ENDPROC	qmode

;
; Each check counts itself and ends the program if it fails: chk0 requires AX
; to be zero (a function's success), chkw requires that and CX bytes written,
; chkerr requires AX not to be zero, and chkz and chknz require the zero flag
; to be set and clear.
;
DEFPROC	chkw
	test	ax,ax
	jnz	chkz
	cmp	[written],cx
	jmp	short chkz
ENDPROC	chkw

DEFPROC	chkerr
	test	ax,ax
	jmp	short chknz
ENDPROC	chkerr

DEFPROC	chk0
	test	ax,ax
chkz	label	near
	lahf
	xor	ah,40h			; reverse the zero flag
	sahf
chknz	label	near
	lahf
	inc	[step]
	sahf
	jz	fail
	ret
fail:	mov	ax,[step]
	aam				; AH = tens, AL = ones
	xchg	al,ah
	or	ax,'00'
	mov	word ptr [failnum],ax
	mov	dx,offset DGROUP:failed
	mov	ah,DOS_TTY_PRINT
	int	21h
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	chk0

;
; sighand is the signal handler that we give DosSetSigHandler; nothing
; signals it.
;
DEFPROC	sighand,FAR
	ret	4
ENDPROC	sighand

	ENDIF

CODE	ends

	IFDEF	STUB
STACK	segment	stack
	dw	512 dup (?)
STACK	ends
	ENDIF

	end	main
