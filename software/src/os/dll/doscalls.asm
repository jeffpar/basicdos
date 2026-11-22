;
; BASIC-DOS DOSCALLS Library
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; DOSCALLS.DLL is an NE library (see DOSCALLS.DEF) that gives protected-mode
; NE programs OS/2's DOSCALLS functions, at OS/2's ordinals, as far as
; BASIC-DOS can provide them: each function turns an OS/2 call into DOS
; calls.  The NE loader finds it in the system drive's EXT\DLL directory (or
; the one that a "LIBPATH=" line in CONFIG.SYS names) when a program imports
; from the DOSCALLS module (see ne_lib).
;
; OS/2 functions are far procedures that use the Pascal calling convention:
; the caller pushes the parameters in the order they're listed (a far pointer's
; selector first), the function removes them, and it returns its result (0,
; or an error code) in AX, with every other register preserved.  BASIC-DOS's
; error codes are DOS error codes, as OS/2's are.
;
; The functions here are the ones that LINK386 (the Windows 3.1 DDK's linker,
; an OS/2 1.x program) imports, and the three that search directories (which
; SRC\SDK's FIND16 uses), all of which are also among those that OS/2's Family
; API provides on DOS; each one's parameters are listed in the order that
; OS/2 documents them, with their offsets from BP after api_enter.  The
; library's entry point (os2start) is where an OS/2 program starts.
;
	DOSPSP equ 1
	DOSFFB equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	devapi.inc
	include	dosapi.inc
	include	os2.inc

	.286p
;
; The library's data: every program that loads the library has its own copy
; (see load_ne), so this is the program's signal handler and action.
;
_DATA	segment word public 'DATA'
sigfn	dd	0		; the program's CTRL-C signal handler
sigact	dw	SIGA_KILL	; and what to do with a CTRL-C signal
sigset	db	0		; nonzero once sigproc is the CTRL-C handler
finddta	db	size FFB dup (0); HDIR_SYSTEM's search (see api_find)
_DATA	ends

DGROUP	group	_DATA

CODE	segment word public 'CODE'

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; api_enter
;
; Every function except DosExit and DosSetMaxFH starts with a call here, which
; saves the caller's registers, so that the function's last parameter is at
; [BP+6], and ends at api_exit.
;
; Outputs:
;	BP -> the caller's BP, return address, and parameters
;
; Modifies:
;	AX
;
DEFPROC	api_enter
	pop	ax			; AX = our return address
	push	bp
	mov	bp,sp
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	jmp	ax
ENDPROC	api_enter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosExit (ordinal 5)
;
; Ends the program (BASIC-DOS has no threads, so the action code makes no
; difference).
;
; Inputs:
;	[BP+6] = action code (0 to end the thread, 1 to end the process)
;	[BP+4] = exit code
;
; Outputs:
;	None (it doesn't return)
;
DEFPROC	DOSEXIT,FAR
	mov	bp,sp
	mov	al,[bp+4]		; AL = exit code
	mov	ah,DOS_PSP_RETURN
	int	21h
ENDPROC	DOSEXIT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosSetSigHandler (ordinal 14)
;
; Sets the action for a CTRL-C signal (SIG_CTRLC or SIG_CTRLBREAK, which are
; the same signal here; BASIC-DOS has no others): SIGA_KILL ends the program
; (the default), SIGA_IGNORE ignores the signal, and SIGA_ACCEPT calls the
; handler, which is a far procedure with two word parameters (the signal's
; argument, which is 0, and its number).  SIGA_ACK changes nothing, since
; nothing holds signals back while a handler runs.
;
; Inputs:
;	[BP+18] -> handler (far pointer)
;	[BP+14] -> where to store the previous handler (far pointer, or 0)
;	[BP+10] -> where to store the previous action (far pointer, or 0)
;	[BP+8] = action (SIGA_*)
;	[BP+6] = signal number
;
; Outputs:
;	AX = 0 if successful; otherwise, ERROR_BAD_SIGNAL
;
DEFPROC	DOSSETSIGHANDLER,FAR
	call	api_enter
	mov	ax,DGROUP
	mov	ds,ax
	ASSUME	DS:DGROUP
	mov	ax,ERROR_BAD_SIGNAL
	mov	bx,[bp+6]
	cmp	bx,SIG_CTRLC
	je	ss1
	cmp	bx,SIG_CTRLBREAK
	jne	ss9
ss1:	mov	bx,[bp+8]		; BX = action
	cmp	bx,SIGA_ACK
	je	ss2
	cmp	bx,SIGA_ACCEPT		; SIGA_KILL, IGNORE, or ACCEPT?
	ja	ss9			; no
ss2:	les	di,[bp+14]
	mov	ax,es
	or	ax,di			; does the caller want the handler?
	jz	ss3			; no
	mov	ax,[sigfn]._OFF
	stosw
	mov	ax,[sigfn]._SEG
	stosw
ss3:	les	di,[bp+10]
	mov	ax,es
	or	ax,di			; does the caller want the action?
	jz	ss4			; no
	mov	ax,[sigact]
	stosw
ss4:	cmp	bx,SIGA_ACK
	je	ss8
	mov	[sigact],bx
	mov	ax,[bp+18]
	mov	[sigfn]._OFF,ax
	mov	ax,[bp+20]
	mov	[sigfn]._SEG,ax
	cmp	[sigset],0		; is sigproc the CTRL-C handler yet?
	jne	ss8			; yes
	inc	[sigset]
	push	cs
	pop	ds
	ASSUME	DS:NOTHING
	mov	dx,offset sigproc
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR INT_DOSCTRLC
	int	21h
ss8:	sub	ax,ax
ss9:	mov	si,16
	jmp	api_exit
ENDPROC	DOSSETSIGHANDLER

;
; sigproc is the program's CTRL-C handler (see DosSetSigHandler), which
; returns with carry set to end the program, or clear to continue.
;
DEFPROC	sigproc,FAR
	pusha
	push	ds
	push	es
	mov	ax,DGROUP
	mov	ds,ax
	ASSUME	DS:DGROUP
	mov	ax,[sigact]
	cmp	al,SIGA_ACCEPT
	jne	sp1
	push	0			; the signal's argument
	push	SIG_CTRLC		; and its number
	call	[sigfn]
	mov	al,SIGA_IGNORE		; (the handler returned, so continue)
sp1:	cmp	al,SIGA_IGNORE		; carry set if SIGA_KILL
	pop	es
	pop	ds
	ASSUME	DS:NOTHING
	popa
	ret
ENDPROC	sigproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosAllocSeg (ordinal 34) and DosReallocSeg (ordinal 38)
;
; Inputs (DosAllocSeg):
;	[BP+12] = size in bytes (0 means 64K)
;	[BP+8] -> where to store the selector (far pointer)
;	[BP+6] = flags (ignored: segments aren't shared or discarded)
;
; Inputs (DosReallocSeg):
;	[BP+8] = new size in bytes (0 means 64K)
;	[BP+6] = selector
;
; Outputs:
;	AX = 0 if successful (and for DosAllocSeg, the selector is stored);
;	otherwise, a DOS error code
;
DEFPROC	DOSALLOCSEG,FAR
	call	api_enter
	mov	bx,[bp+12]
	call	api_paras		; BX = paras
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h
	jc	as9
	les	di,[bp+8]
	stosw				; store the selector
	sub	ax,ax
as9:	mov	si,8
	jmp	api_exit
ENDPROC	DOSALLOCSEG

DEFPROC	DOSREALLOCSEG,FAR
	call	api_enter
	mov	bx,[bp+6]
	call	api_sel			; ES = the segment
	jc	rs9
	mov	bx,[bp+8]
	call	api_paras		; BX = paras
	mov	ah,DOS_MEM_REALLOC
	int	21h
	jc	rs9
	sub	ax,ax
rs9:	mov	si,4
	jmp	api_exit
ENDPROC	DOSREALLOCSEG

;
; api_paras converts a size in bytes (BX, where 0 means 64K) to paragraphs.
;
DEFPROC	api_paras
	dec	bx
	shr	bx,4
	inc	bx
	ret
ENDPROC	api_paras

;
; api_sel loads ES with a selector (BX) that a caller says is a segment's,
; or returns carry set and ERR_BADADDR if it isn't one that the caller can
; write (eg, a segment that's been freed), since loading it would fault.
;
DEFPROC	api_sel
	verw	bx			; a writable data segment?
	mov	ax,ERR_BADADDR
	stc
	jnz	sl9			; no
	mov	es,bx
	clc
sl9:	ret
ENDPROC	api_sel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosFreeSeg (ordinal 39)
;
; Inputs:
;	[BP+6] = selector
;
; Outputs:
;	AX = 0 if successful; otherwise, a DOS error code
;
DEFPROC	DOSFREESEG,FAR
	call	api_enter
	mov	bx,[bp+6]
	call	api_sel			; ES = the segment
	jc	fs9
	mov	ah,DOS_MEM_FREE
	int	21h
	jc	fs9
	sub	ax,ax
;
; The selector is gone, so if it's the caller's ES, the caller gets 0 instead
; (as DOS_MEM_FREE's caller does), since restoring it would fault.
;
	cmp	[bp-14],bx
	jne	fs9
	mov	[bp-14],ax
fs9:	mov	si,2
	jmp	api_exit
ENDPROC	DOSFREESEG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosGetMachineMode (ordinal 49)
;
; Stores 1, which is OS/2's value for protected mode (0 is the DOS
; environment).  A program that sees 0 may use DOS calls and real-mode
; habits instead of these functions: LINK386, for one, then frees segments
; that it never allocated when it ends early, which DOS refuses but which
; faults here, since the "segments" aren't selectors.
;
; Inputs:
;	[BP+6] -> where to store the mode byte (far pointer)
;
; Outputs:
;	AX = 0
;
DEFPROC	DOSGETMACHINEMODE,FAR
	call	api_enter
	les	di,[bp+6]
	mov	al,1
	stosb
	sub	ax,ax
	mov	si,4
	jmp	api_exit
ENDPROC	DOSGETMACHINEMODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosDevIOCtl (ordinal 53)
;
; OS/2's device control functions (by category and function number) aren't
; BASIC-DOS's, and none are supported.
;
; Inputs:
;	[BP+16] -> data area (far pointer)
;	[BP+12] -> parameter list (far pointer)
;	[BP+10] = function
;	[BP+8] = category
;	[BP+6] = file handle
;
; Outputs:
;	AX = ERR_INVALID
;
DEFPROC	DOSDEVIOCTL,FAR
	mov	ax,ERR_INVALID
	ret	14
ENDPROC	DOSDEVIOCTL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosChgFilePtr (ordinal 58)
;
; Inputs:
;	[BP+16] = file handle
;	[BP+12] = distance (a dword)
;	[BP+10] = method (0 from the start, 1 the current position, 2 the end)
;	[BP+6] -> where to store the new position (far pointer to a dword)
;
; Outputs:
;	AX = 0 if successful (and the position is stored); otherwise, a DOS
;	error code
;
DEFPROC	DOSCHGFILEPTR,FAR
	call	api_enter
	mov	bx,[bp+16]
	mov	dx,[bp+12]
	mov	cx,[bp+14]
	mov	al,[bp+10]
	mov	ah,DOS_HDL_SEEK
	int	21h
	jc	cp9
	les	di,[bp+6]
	stosw
	xchg	ax,dx
	stosw
	sub	ax,ax
cp9:	mov	si,12
	jmp	api_exit
ENDPROC	DOSCHGFILEPTR

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosClose (ordinal 59)
;
; Inputs:
;	[BP+6] = file handle
;
; Outputs:
;	AX = 0 if successful; otherwise, a DOS error code
;
DEFPROC	DOSCLOSE,FAR
	call	api_enter
	mov	bx,[bp+6]
	mov	ah,DOS_HDL_CLOSE
	int	21h
	jc	cl9
	sub	ax,ax
cl9:	mov	si,2
	jmp	api_exit
ENDPROC	DOSCLOSE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosDelete (ordinal 60)
;
; Inputs:
;	[BP+10] -> file name (far pointer)
;	[BP+6] = 0 (a reserved dword)
;
; Outputs:
;	AX = 0 if successful; otherwise, a DOS error code
;
DEFPROC	DOSDELETE,FAR
	call	api_enter
	lds	dx,[bp+10]
	mov	ah,DOS_DSK_DELETE
	int	21h
	jc	dl9
	sub	ax,ax
dl9:	mov	si,8
	jmp	api_exit
ENDPROC	DOSDELETE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosFindClose (ordinal 63)
;
; Inputs:
;	[BP+6] = directory handle
;
; Outputs:
;	AX = 0 if successful; otherwise, a DOS error code
;
DEFPROC	DOSFINDCLOSE,FAR
	call	api_enter
	mov	bx,[bp+6]
	call	api_fclose
	mov	si,2
	jmp	api_exit
ENDPROC	DOSFINDCLOSE

;
; api_fclose ends the search with directory handle BX: HDIR_SYSTEM has
; nothing to free, and any other handle is its search's segment.
;
DEFPROC	api_fclose
	call	api_hdir		; ES = the handle's segment
	jc	fc9
	cmp	bx,HDIR_SYSTEM
	je	fc8
	mov	ah,DOS_MEM_FREE
	int	21h
	jc	fc9
fc8:	sub	ax,ax
fc9:	ret
ENDPROC	api_fclose

;
; api_hdir returns the address (ES:DX) of the FFB for directory handle BX,
; or carry set and ERR_BADHANDLE if BX isn't a handle.
;
DEFPROC	api_hdir
	mov	dx,DGROUP
	mov	es,dx
	mov	dx,offset DGROUP:finddta
	cmp	bx,HDIR_SYSTEM
	je	hd9
	call	api_sel			; ES = the handle's segment
	mov	al,ERR_BADHANDLE
	mov	dx,0
hd9:	ret
ENDPROC	api_hdir

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosFindFirst (ordinal 64) and DosFindNext (ordinal 65)
;
; A search is a DOS search (DOS_DSK_FFIRST and DOS_DSK_FNEXT) with an FFB of
; its own, so that a program can have several: the directory handle is either
; HDIR_SYSTEM, whose FFB is in our data segment, or -1 (HDIR_CREATE), for
; which DosFindFirst allocates a segment for the FFB and stores its selector
; as the new handle (which DosFindClose frees).  Each call finds one file,
; whatever number the caller asks for, and the file's allocated size is its
; size.
;
; Inputs (DosFindFirst):
;	[BP+26] -> file specification (far pointer)
;	[BP+22] -> directory handle (far pointer to HDIR_SYSTEM or -1)
;	[BP+20] = attributes (as for DOS_DSK_FFIRST)
;	[BP+16] -> FILEFINDBUF (far pointer)
;	[BP+14] = size of that buffer
;	[BP+10] -> # files to find, and where to store the # found (far
;	pointer)
;	[BP+6] = 0 (a reserved dword)
;
; Inputs (DosFindNext):
;	[BP+16] = directory handle
;	[BP+12] -> FILEFINDBUF (far pointer)
;	[BP+10] = size of that buffer
;	[BP+6] -> # files to find, and where to store the # found (far
;	pointer)
;
; Outputs:
;	AX = 0 if successful (and the buffer and the # found, which is 1,
;	are stored); otherwise, a DOS error code, ERROR_NO_MORE_FILES (if
;	there are no files, or no more), or ERROR_BUFFER_OVERFLOW
;
DEFPROC	DOSFINDFIRST,FAR
	call	api_enter
	add	bp,4			; BP as for DosFindNext's parameters
	les	di,[bp+18]
	mov	bx,es:[di]		; BX = directory handle
	cmp	bx,HDIR_SYSTEM
	je	ff1
	mov	bx,(size FFB + 15) SHR 4
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h			; AX = a segment for the search
	jc	ff9
	stosw				; which is the new handle
	xchg	bx,ax
ff1:	mov	cx,[bp+16]
	lds	dx,[bp+22]
	mov	ah,DOS_DSK_FFIRST
	call	api_find
	test	ax,ax			; did it find a file?
	jz	ff9			; yes
	push	ax
	les	di,[bp+18]
	mov	bx,es:[di]
	call	api_fclose		; no, so there's no search to close
	pop	ax
ff9:	sub	bp,4
	mov	si,24
	jmp	api_exit
ENDPROC	DOSFINDFIRST

DEFPROC	DOSFINDNEXT,FAR
	call	api_enter
	mov	bx,[bp+16]
	mov	ah,DOS_DSK_FNEXT
	call	api_find
	mov	si,12
	jmp	api_exit
ENDPROC	DOSFINDNEXT

;
; api_find issues DOS function AH (DOS_DSK_FFIRST, with DS:DX -> file
; specification and CX = attributes, or DOS_DSK_FNEXT) for directory handle
; BX, with the handle's FFB as the DTA (the program's DTA is restored
; afterward), and stores the file it finds in the caller's FILEFINDBUF.  It
; returns AX = 0 or an error code.
;
DEFPROC	api_find
	xchg	si,ax			; SI = function
;
; The caller's buffer must hold a FILEFINDBUF, since we store all of one.
;
	mov	ax,ERROR_BUFFER_OVERFLOW
	cmp	word ptr [bp+10],size FILEFINDBUF
	jb	af1
	mov	di,dx			; DS:DI -> file specification
	call	api_hdir		; ES:DX -> the handle's FFB
	jc	af1
	push	ds
	push	es
	push	dx
	mov	ah,DOS_DSK_GETDTA
	int	21h			; ES:BX -> the program's DTA
	pop	dx
	pop	ds			; DS:DX -> the handle's FFB
	mov	ah,DOS_DSK_SETDTA
	int	21h
	pop	ax			; AX = the specification's segment
	push	ds
	push	dx
	mov	ds,ax
	mov	dx,di			; DS:DX -> file specification
	xchg	ax,si			; AH = function
	int	21h			; find the first or next file
	pop	si
	pop	ds			; DS:SI -> the handle's FFB
	sbb	di,di			; DI = -1 if there's no file
	push	ax
	push	ds
	push	es
	pop	ds
	mov	dx,bx
	mov	ah,DOS_DSK_SETDTA
	int	21h			; restore the program's DTA
	pop	ds
	pop	ax
	inc	di			; was there a file?
	jnz	af2			; yes
;
; OS/2's error for no files (or no more) is ERROR_NO_MORE_FILES.
;
	cmp	ax,ERR_NOFILE
	jne	af1
	mov	al,ERROR_NO_MORE_FILES
af1:	ret
af2:	les	di,[bp+12]		; ES:DI -> FILEFINDBUF
	sub	ax,ax
	stosw				; no creation date or time
	stosw
	stosw				; and no last access date or time
	stosw
	mov	ax,[si].FFB_DATE
	stosw
	mov	ax,[si].FFB_TIME
	stosw
	mov	ax,[si].FFB_SIZE._OFF
	mov	dx,[si].FFB_SIZE._SEG
	stosw				; the file's size
	xchg	ax,dx
	stosw
	xchg	ax,dx
	stosw				; and its allocated size
	xchg	ax,dx
	stosw
	mov	al,[si].FFB_ATTR
	mov	ah,0
	stosw
	lea	si,[si].FFB_NAME
	mov	bx,di			; ES:BX -> the name's length
	inc	di
af3:	lodsb				; copy the name, and its null
	stosb
	test	al,al
	jnz	af3
	lea	ax,[di-2]
	sub	ax,bx			; AX = length of the name
	mov	es:[bx],al
	les	di,[bp+6]
	mov	ax,1
	stosw				; one file found
	dec	ax
	ret
ENDPROC	api_find

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosNewSize (ordinal 68)
;
; Sets a file's size, as DOS does, with a zero-length write at that position;
; the file's position is then restored, since OS/2's function doesn't move it.
;
; Inputs:
;	[BP+10] = file handle
;	[BP+6] = new size (a dword)
;
; Outputs:
;	AX = 0 if successful; otherwise, a DOS error code
;
DEFPROC	DOSNEWSIZE,FAR
	call	api_enter
	mov	bx,[bp+10]
	sub	cx,cx
	sub	dx,dx
	mov	ax,DOS_HDL_SEEKCUR
	int	21h			; DX:AX = the file's position
	jc	ns9
	push	dx
	push	ax
	mov	dx,[bp+6]
	mov	cx,[bp+8]
	mov	ax,DOS_HDL_SEEKBEG
	int	21h			; seek to the new size
	jc	ns1
	sub	cx,cx
	mov	ah,DOS_HDL_WRITE
	int	21h			; and write nothing there
ns1:	sbb	si,si			; SI = -1 if either failed
	xchg	di,ax			; DI = error code, if so
	pop	dx
	pop	cx
	mov	ax,DOS_HDL_SEEKBEG
	int	21h			; restore the file's position
	jc	ns9
	xchg	ax,di
	add	si,1			; carry set if the resize failed
	jc	ns9
	sub	ax,ax
ns9:	mov	si,6
	jmp	api_exit
ENDPROC	DOSNEWSIZE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosOpen (ordinal 70)
;
; The open flags say what to do if the file exists (bits 0-3: 0 to fail, 1
; to open it, 2 to replace it) and if it doesn't (bit 4: set to create it),
; and the action stored is 1 if it existed, 2 if it was created, or 3 if it
; was replaced.  Of the open mode, only the access (bits 0-1, as for
; DOS_HDL_OPEN) is used; a new or replaced file is open for reading and
; writing, and a request to open a drive (bit 15) is refused.  The file's
; initial size is ignored.
;
; Inputs:
;	[BP+28] -> file name (far pointer)
;	[BP+24] -> where to store the file handle (far pointer)
;	[BP+20] -> where to store the action taken (far pointer)
;	[BP+16] = initial size (a dword)
;	[BP+14] = attributes for a new file
;	[BP+12] = open flags
;	[BP+10] = open mode
;	[BP+6] = 0 (a reserved dword)
;
; Outputs:
;	AX = 0 if successful (and the handle and action are stored);
;	otherwise, a DOS error code, or ERROR_OPEN_FAILED
;
DEFPROC	DOSOPEN,FAR
	call	api_enter
	mov	ax,ERR_ACCDENIED
	test	byte ptr [bp+11],80h	; open a drive?
	jnz	op9			; yes
	lds	dx,[bp+28]
	mov	cl,[bp+12]		; CL = open flags
	mov	al,[bp+10]
	and	al,3			; AL = access
	mov	ah,DOS_HDL_OPEN
	int	21h
	jc	op2
	mov	si,1			; the file existed
	and	cl,0Fh
	dec	cl			; open it?
	jz	op4			; yes
	xchg	bx,ax
	mov	ah,DOS_HDL_CLOSE
	int	21h			; no, so close it
	dec	cl
	jnz	op8			; and fail unless it's to be replaced
	mov	si,3			; the file is replaced
	jmp	short op3
op2:	cmp	ax,ERR_NOFILE		; does the file not exist?
	jne	op9			; it's some other error
	mov	si,2			; the file is created
	test	cl,10h			; if that's allowed
	jz	op8
op3:	mov	cx,[bp+14]
	mov	ah,DOS_HDL_CREATE
	int	21h
	jc	op9
op4:	les	di,[bp+24]
	stosw				; store the handle
	les	di,[bp+20]
	xchg	ax,si
	stosw				; and the action
	sub	ax,ax
	jmp	short op9
op8:	mov	ax,ERROR_OPEN_FAILED
op9:	mov	si,26
	jmp	api_exit
ENDPROC	DOSOPEN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosQCurDisk (ordinal 72)
;
; Inputs:
;	[BP+10] -> where to store the current drive (far pointer; 1 is A:)
;	[BP+6] -> where to store a bit for each drive (far pointer to a
;	dword; bit 0 is A:)
;
; Outputs:
;	AX = 0
;
DEFPROC	DOSQCURDISK,FAR
	call	api_enter
	mov	ah,DOS_DSK_GETDRV
	int	21h			; AL = current drive
	mov	dl,al
	cbw
	inc	ax
	les	di,[bp+10]
	stosw
	mov	ah,DOS_DSK_SETDRV
	int	21h			; AL = # of drives (DL is current)
	xchg	cx,ax
	mov	ch,0
	mov	ax,1
	cwd				; DX:AX = 1
	jcxz	qd2
qd1:	shl	ax,1
	rcl	dx,1
	loop	qd1
qd2:	sub	ax,1
	sbb	dx,cx			; DX:AX = a bit for each drive
	les	di,[bp+6]
	stosw
	xchg	ax,dx
	stosw
	xchg	ax,cx			; AX = 0
	mov	si,8
	jmp	api_exit
ENDPROC	DOSQCURDISK

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosQFileMode (ordinal 75)
;
; Inputs:
;	[BP+14] -> file name (far pointer)
;	[BP+10] -> where to store the file's attributes (far pointer)
;	[BP+6] = 0 (a reserved dword)
;
; Outputs:
;	AX = 0 if successful (and the attributes are stored); otherwise, a
;	DOS error code
;
DEFPROC	DOSQFILEMODE,FAR
	call	api_enter
	lds	dx,[bp+14]
	mov	ax,DOS_DSK_GETATTR
	int	21h
	jc	qf9
	les	di,[bp+10]
	xchg	ax,cx
	stosw
	sub	ax,ax
qf9:	mov	si,12
	jmp	api_exit
ENDPROC	DOSQFILEMODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosQHandType (ordinal 77)
;
; Inputs:
;	[BP+14] = file handle
;	[BP+10] -> where to store the type (far pointer; 0 for a file, 1 for
;	a device)
;	[BP+6] -> where to store the device data (far pointer; see
;	IOCTL_GETDATA)
;
; Outputs:
;	AX = 0 if successful (and both are stored); otherwise, a DOS error
;	code
;
DEFPROC	DOSQHANDTYPE,FAR
	call	api_enter
	mov	bx,[bp+14]
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETDATA
	int	21h			; DX = device data (bit 7 if a device)
	jc	qh9
	les	di,[bp+10]
	mov	al,dl
	rol	al,1
	and	ax,1
	stosw
	les	di,[bp+6]
	xchg	ax,dx
	stosw
	sub	ax,ax
qh9:	mov	si,10
	jmp	api_exit
ENDPROC	DOSQHANDTYPE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosSetMaxFH (ordinal 85)
;
; A program's file handles are those in its PSP, so their number can't change.
;
; Inputs:
;	[BP+6] = # of file handles the program needs
;
; Outputs:
;	AX = 0 if it has that many; otherwise, ERR_NOHANDLE
;
DEFPROC	DOSSETMAXFH,FAR
	push	bp
	mov	bp,sp
	sub	ax,ax
	cmp	word ptr [bp+6],size PSP_PFT
	jbe	mf9
	mov	al,ERR_NOHANDLE
mf9:	pop	bp
	ret	2
ENDPROC	DOSSETMAXFH

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosSetVec (ordinal 89)
;
; Sets an exception's handler (eg, 0 for a divide error), which is the
; exception's interrupt vector; a null handler leaves it as it is.
;
; Inputs:
;	[BP+14] = exception number
;	[BP+10] -> new handler (far pointer, or 0)
;	[BP+6] -> where to store the previous handler (far pointer)
;
; Outputs:
;	AX = 0
;
DEFPROC	DOSSETVEC,FAR
	call	api_enter
	mov	al,[bp+14]
	mov	ah,DOS_MSC_GETVEC
	int	21h			; ES:BX = the vector
	lds	di,[bp+6]
	mov	[di]._OFF,bx
	mov	[di]._SEG,es
	lds	dx,[bp+10]
	mov	ax,ds
	or	ax,dx			; is there a new handler?
	jz	sv9			; no
	mov	al,[bp+14]
	mov	ah,DOS_MSC_SETVEC
	int	21h
	sub	ax,ax
sv9:	mov	si,10
	jmp	api_exit
ENDPROC	DOSSETVEC

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosGetVersion (ordinal 92)
;
; Inputs:
;	[BP+6] -> where to store the version (far pointer to a word: the
;	major version in the high byte and the minor in the low byte)
;
; Outputs:
;	AX = 0
;
DEFPROC	DOSGETVERSION,FAR
	call	api_enter
	mov	ah,DOS_MSC_GETVER
	int	21h			; AL = major version, AH = minor
	xchg	al,ah
	les	di,[bp+6]
	stosw
	sub	ax,ax
	mov	si,4
	jmp	api_exit
ENDPROC	DOSGETVERSION

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosGetPid (ordinal 94)
;
; Inputs:
;	[BP+6] -> where to store three words (far pointer): the process ID
;	(the program's PSP), the thread ID (1), and the parent's process ID
;
; Outputs:
;	AX = 0
;
DEFPROC	DOSGETPID,FAR
	call	api_enter
	mov	ah,DOS_PSP_GET
	int	21h			; BX = PSP
	les	di,[bp+6]
	mov	ax,bx
	stosw
	mov	ax,1
	stosw
	mov	ds,bx
	mov	ax,ds:[PSP_PARENT]
	stosw
	sub	ax,ax
	mov	si,4
	jmp	api_exit
ENDPROC	DOSGETPID

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosRead (ordinal 137) and DosWrite (ordinal 138)
;
; Inputs:
;	[BP+16] = file handle
;	[BP+12] -> buffer (far pointer)
;	[BP+10] = # bytes to read or write
;	[BP+6] -> where to store the # bytes read or written (far pointer)
;
; Outputs:
;	AX = 0 if successful (and the # bytes is stored); otherwise, a DOS
;	error code
;
DEFPROC	DOSREAD,FAR
	call	api_enter
	mov	ah,DOS_HDL_READ
	jmp	short dw1
ENDPROC	DOSREAD

DEFPROC	DOSWRITE,FAR
	call	api_enter
	mov	ah,DOS_HDL_WRITE
dw1:	mov	bx,[bp+16]
	mov	cx,[bp+10]
	lds	dx,[bp+12]
	int	21h
	jc	dw9
	les	di,[bp+6]
	stosw
	sub	ax,ax
dw9:	mov	si,12
	jmp	short api_exit
ENDPROC	DOSWRITE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DosExecPgm (ordinal 144)
;
; Runs a program and waits for it to end (flags of 0; no other way of running
; one is supported).  The arguments are two strings, one after the other: the
; program's name, and the command tail to give it.  The program shares our
; environment, as every BASIC-DOS program shares its parent's, so the
; environment parameter is ignored, and so is the buffer for the name of
; whatever kept the program from loading.
;
; Inputs:
;	[BP+26] -> buffer for a failing module's name (far pointer)
;	[BP+24] = size of that buffer
;	[BP+22] = flags (0 to wait for the program)
;	[BP+18] -> arguments (far pointer, or 0)
;	[BP+14] -> environment (far pointer, or 0)
;	[BP+10] -> where to store two words (far pointer): how the program
;	ended (see DOS_PSP_RETCODE's exit type), and its exit code
;	[BP+6] -> program's file name (far pointer)
;
; Outputs:
;	AX = 0 if successful (and the two words are stored); otherwise, a DOS
;	error code
;
DEFPROC	DOSEXECPGM,FAR
	call	api_enter
	mov	ax,ERR_INVALID
	cmp	word ptr [bp+22],0	; wait for the program?
	jne	ep9			; no
;
; Build a command tail (a length byte, the tail, and a carriage return) and
; an EPB on the stack.
;
	sub	sp,128 + size EPB
	mov	di,sp
	push	ss
	pop	es
	mov	bx,di			; ES:BX -> command tail
	inc	di
	sub	cx,cx			; CX = length of the tail
	lds	si,[bp+18]
	mov	ax,ds
	or	ax,si			; any arguments?
	jz	ep3			; no
ep1:	lodsb				; skip the program's name
	test	al,al
	jnz	ep1
ep2:	lodsb
	test	al,al			; end of the tail?
	jz	ep3			; yes
	stosb
	inc	cx
;
; A command tail can't be longer than 126 characters (see PSP_CMDTAIL).
;
	cmp	cl,126
	jbe	ep2
	mov	ax,ERR_BADFORMAT
	jmp	short ep8
ep3:	mov	al,CHR_RETURN
	stosb
	mov	es:[bx],cl
	mov	si,di			; ES:SI -> EPB
	sub	ax,ax
	stosw				; EPB_ENVSEG (ours)
	mov	ax,bx
	stosw
	mov	ax,ss
	stosw				; EPB_CMDTAIL
	mov	ax,-1
	stosw				; EPB_FCB1 (-1: build both FCBs)
	lds	dx,[bp+6]
	mov	bx,si			; ES:BX -> EPB
	mov	ax,DOS_PSP_EXEC
	int	21h
	jc	ep8
	mov	ah,DOS_PSP_RETCODE
	int	21h			; AL = exit code, AH = exit type
	les	di,[bp+10]
	mov	bl,al
	mov	al,ah
	mov	ah,0
	stosw
	mov	al,bl
	stosw
	sub	ax,ax
ep8:	lea	sp,[bp-14]		; discard the tail and EPB
ep9:	mov	si,24
ENDPROC	DOSEXECPGM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; api_exit
;
; Restores the registers that api_enter saved and returns to the function's
; caller, removing the function's parameters.
;
; Inputs:
;	AX = the function's result
;	SI = size of the function's parameters
;	BP and SP as api_enter left them
;
DEFPROC	api_return,FAR
api_exit label near
	mov	cx,[bp+4]
	mov	[bp+si+4],cx
	mov	cx,[bp+2]
	mov	[bp+si+2],cx		; move the return address
	mov	cx,[bp]
	mov	[bp+si],cx		; and the caller's BP above the params
	lea	bp,[bp+si]
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	mov	sp,bp
	pop	bp
	ret
ENDPROC	api_return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; os2start
;
; This is the library's entry point, where the NE loader starts an OS/2
; program (see ne_os2), with the program's own starting address on its stack.
; We give it OS/2's starting registers: DS (and ES) is its automatic data
; segment, which holds its stack; AX is the selector of a new environment
; block, with a copy of the PSP's environment strings; BX is the offset
; there of its command line, which is two strings (the program's name, and
; its command tail) and another null; and CX is its data segment's size.
; BASIC-DOS doesn't give a program its own name, so the name is "C" (as
; Microsoft C's programs called themselves when DOS didn't, either).
;
; Inputs:
;	DS = ES = PSP
;	SS:SP -> a zero, and then the program's starting address
;
; Outputs:
;	AX, BX, CX, DS, and ES as above, and the rest zero
;
DEFPROC	os2start,FAR
	pop	ax			; discard the zero
	sub	di,di			; DI = length of environment strings
	mov	ax,ds:[PSP_ENVSEG]
	test	ax,ax			; is there an environment?
	jz	os2			; no
	mov	es,ax
	sub	ax,ax
	mov	cx,-1
os1:	repne	scasb			; skip a string
	scasb				; is another null next?
	jne	os1			; no
	dec	di
os2:	mov	dx,di
;
; The block needs the strings, up to two nulls, the name's two bytes, the
; tail, and two more nulls.
;
	mov	bl,ds:[PSP_CMDTAIL]
	mov	bh,0
	lea	bx,[bx+di+6+15]
	shr	bx,4			; BX = paras
	mov	ax,DOS_MEM_ALLOC SHL 8
	int	21h
	jc	os9
	mov	es,ax
	push	ds
	mov	ds,ds:[PSP_ENVSEG]
	mov	cx,dx
	sub	si,si
	sub	di,di
	rep	movsb			; copy the strings
	pop	ds
	sub	ax,ax
	stosb				; end them with a null
	test	dx,dx			; were there any?
	jnz	os3			; yes
	stosb				; no, so that's two nulls
os3:	mov	bx,di			; BX = offset of the command line
	mov	al,'C'
	stosw				; the program's name
	mov	si,PSP_CMDTAIL
	lodsb
	mov	cl,al			; CX = length of the tail (CH is zero)
	rep	movsb
	sub	ax,ax
	stosw				; end the tail, and the command line
	mov	ax,es			; AX = environment
	mov	dx,ss
	lsl	cx,dx
	inc	cx			; CX = size of data segment
	mov	ds,dx
	mov	es,dx
	sub	dx,dx
	sub	si,si
	sub	di,di
	sub	bp,bp
	ret				; start the program
os9:	mov	ax,(DOS_PSP_RETURN SHL 8) OR 0FFh
	int	21h
ENDPROC	os2start

CODE	ends

	end	os2start
