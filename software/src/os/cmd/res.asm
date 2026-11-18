;
; BASIC-DOS Command Processor: Resident Portion
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; This must be the first module linked, since it begins with the program's
; entry point, followed by everything that must remain in memory while an
; external program is running, including the heap (and stack) of the copy of
; COMMAND.COM that owns the shared code (see COMHEAP and main).
;
; Everything after RES_END is the "transient" portion, which runTransient
; discards before loading an external program (by shrinking our memory block),
; so that programs can use that memory, too.  It first copies the transient
; portion to the top of free memory (see resSave), and when the program ends,
; if that copy is still intact, it's copied back down; otherwise, the
; transient portion is reloaded from COMMAND.COM.  Since it may be reloaded
; from the file, it must not contain any data that changes; TRANS_SUM, for
; example, is kept here instead.
;
;
; The transient portion ends at PSP_CODESIZE: BEG_HEAP (see heap.asm) when
; the entire image was loaded, or CORE_HEAP (see const.asm) when the loader
; loaded only COMMAND's core (see CD_CORESIZE in dosapi.inc).
;
	DOSFUNC equ 1
	include	cmd.inc
	include	8086.inc

CODE    SEGMENT
	org	100h

	EXTNEAR	<main,ctrlc,rtError>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

	DEFLBL	entry,near
	jmp	main
;
; Only the copy that owns the shared code writes these (other copies bump
; CMD_REFS, through CODE_DS); at ring 3, no copy does, since none can write
; the code (see main), so CODE_DS stays zero.
;
	DEFWORD	CMD_REFS,0		; # of copies using the shared code
	DEFWORD	CODE_DS,0		; data segment for the shared code
	DEFWORD	TRANS_SUM,0		; checksum of the transient portion
	DEFWORD	TRANS_HI,0		; nonzero if it has a copy (resSave)
	DEFLBL	CMD_PATH,byte		; (main updates the drive and path char)
	db	"A:\COMMAND.COM",0
MSG_RELOAD	db	13,10,"Insert disk with COMMAND.COM in drive "
	DEFLBL	MSG_DRIVE,byte
	db	"A and press any key",13,10,'$'
MSG_NOMEM	db	13,10,"Can't reload COMMAND, press any key",13,10,'$'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; runTransient
;
; Loads and runs an external program with the transient portion discarded
; (see above), and reloads the transient portion when the program ends.
;
; Inputs:
;	DS:DX -> program filename
;	ES:BX -> EPB (for DOS_PSP_EXEC1 and DOS_PSP_EXEC2)
;	DS = ES = SS = our PSP (ie, the copy that owns the shared code, whose
;	CS is the same segment, or in protected mode, its code alias)
;
; Outputs:
;	Carry clear if the program ran, set if it couldn't be loaded (AX)
;
; Modifies:
;	AX, BX, CX, SI, DI
;
DEFPROC	runTransient
	push	dx
	mov	dx,offset resCtrlC	; while the program runs, CTRLC must
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	int	21h			; not use the transient ctrlc handler
	push	bx
	call	resSave			; save a copy of the transient portion
	push	ss
	pop	es			; (ES = our PSP again)
	mov	bx,offset DGROUP:RES_END
	call	toParas
	mov	ah,DOS_MEM_REALLOC
	int	21h			; discard the transient portion
	pop	bx
	pop	dx
	mov	ax,DOS_PSP_EXEC1
	int	21h			; load the program at DS:DX
	jc	rt1
	sub	dx,dx			; DX = 0 (not a debugger single-step)
	mov	ax,DOS_PSP_EXEC2
	int	21h			; and run it
	clc
rt1:	pushf
	push	ax
	push	dx			; preserve DX for caller's error path
	mov	dx,offset rcIgnore	; CTRLC must not terminate us, either,
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	int	21h			; until the transient portion is back
	push	ss
	pop	es			; (our PSP, where CS is its code alias)
rt2:	call	resParas		; BX = paras for the transient, too
	mov	ah,DOS_MEM_REALLOC
	int	21h			; restore our memory block
	jnc	rt2a
	mov	dx,offset MSG_NOMEM	; that should only fail if something
	call	resPrompt		; (eg, a TSR) is still using the memory
	jmp	rt2
;
; If the copy of the transient portion that resSave made at the top of free
; memory is still intact (ie, its checksum matches), copy it back down;
; otherwise, reload it from COMMAND.COM.
;
; The copy is in free memory, so we allocate it first, which keeps another
; session from allocating and modifying it from the checksum through the copy.
;
	ASSUME	DS:CODE			; (DS = CS, since we own the code)
rt2a:	cmp	[TRANS_HI],0		; was a copy made?
	ASSUME	DS:DATA
	je	rt2b			; no
	call	resAllocHi		; ES = the copy's block again
	jc	rt2b
	call	resSumHi		; AX = checksum of the copy
	cmp	ax,[TRANS_SUM]		; does it match?
	jne	rt2c			; no
	push	ds
	push	es
	pop	ds
	sub	si,si			; DS:SI -> copy
	push	ss
	pop	es
	mov	di,offset DGROUP:RES_END; ES:DI -> transient portion
	call	resCopy
	push	ds
	pop	es			; ES = the copy's block
	pop	ds
	call	resFree			; free it
	jmp	short rt5
rt2c:	mov	ah,DOS_MEM_FREE
	int	21h			; free the copy's block
rt2b:
rt3:	mov	dx,offset CMD_PATH
	mov	ax,DOS_HDL_OPENRO
	int	21h			; open COMMAND.COM
	jc	rt4
	xchg	bx,ax			; BX = handle
	mov	dx,offset DGROUP:RES_END - 100h
	sub	cx,cx			; CX:DX = file offset of RES_END
	mov	ax,DOS_HDL_SEEKBEG
	int	21h
	mov	dx,offset DGROUP:RES_END
	mov	cx,ss:[PSP_CODESIZE]
	sub	cx,dx			; CX = size of the transient portion
	mov	ah,DOS_HDL_READ
	int	21h			; read the transient portion
	pushf
	mov	ah,DOS_HDL_CLOSE
	int	21h
	popf
	jc	rt4
	call	resSum			; AX = checksum
	cmp	ax,[TRANS_SUM]		; does it match?
	je	rt5			; yes
rt4:	mov	dx,offset MSG_RELOAD	; no, so ask for the right disk
	call	resPrompt
	jmp	rt3
rt5:	mov	dx,offset ctrlc
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	int	21h			; restore our CTRLC handler
	pop	dx
	pop	ax
	popf
	ret
ENDPROC	runTransient

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resPrompt
;
; Inputs:
;	DS:DX -> message (terminated with '$')
;
; Outputs:
;	None (waits for a key)
;
; Modifies:
;	AX
;
DEFPROC	resPrompt
	mov	ah,DOS_TTY_PRINT
	int	21h
rp1:	mov	ah,DOS_TTY_IN
	int	21h
	test	al,al			; non-ASCII key (null + scan code)?
	jz	rp1			; yes, so read its scan code, too
	ret
ENDPROC	resPrompt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; transParas
;
; Returns the # of paras that runTransient can free (by discarding the
; transient portion), which is zero unless we're the copy that owns the shared
; code and there are no other copies using it.
;
; Inputs:
;	None
;
; Outputs:
;	AX = # paras
;
; Modifies:
;	AX
;
DEFPROC	transParas
	push	bx
	push	cx
	sub	ax,ax
	cmp	word ptr ss:[PSP_HEAP],size PSP
	je	tp9			; we don't own the code (see main)
	cmp	cs:[CMD_REFS],1		; and is no other copy using it?
	jne	tp9			; no
	call	resParas		; BX = paras with the transient portion
	xchg	ax,bx
	mov	bx,offset DGROUP:RES_END
	call	toParas			; BX = paras without it
	sub	ax,bx			; AX = paras in the transient portion
tp9:	pop	cx
	pop	bx
	ret
ENDPROC	transParas

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resParas
;
; Inputs:
;	None
;
; Outputs:
;	BX = # paras in our memory block with the transient portion (ie, the
;	PSP and all the shared code, but not the original heap; see main)
;
; Modifies:
;	BX, CX
;
DEFPROC	resParas
	mov	bx,ss:[PSP_CODESIZE]
	DEFLBL	toParas,near		; converts the offset in BX to paras
	add	bx,15
	mov	cl,4
	shr	bx,cl
	ret
ENDPROC	resParas

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resSum, resSumHi
;
; Inputs:
;	None for resSum; ES:0 -> copy of the transient portion for resSumHi
;
; Outputs:
;	AX = checksum of the transient portion (the sum of its words)
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	resSum
	push	es
	push	cs
	pop	es
	mov	si,offset DGROUP:RES_END
	call	rsSum
	pop	es
	ret
	DEFLBL	resSumHi,near		; ES:0 -> a copy (see resSave)
	sub	si,si
rsSum:	mov	cx,ss:[PSP_CODESIZE]
	sub	cx,offset DGROUP:RES_END
	shr	cx,1			; CX = # words in the transient portion
	sub	ax,ax
rs1:	add	ax,es:[si]
	inc	si
	inc	si
	loop	rs1
	ret
ENDPROC	resSum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resSave
;
; Before the transient portion is discarded, we copy it into a block that we
; allocate at the top of free memory and then free again, so the program is
; free to use that memory; but since most programs don't use all
; available memory, the copy is likely to be intact when the program ends,
; saving us from reloading it from COMMAND.COM (see runTransient).
;
; A freed block's segment isn't valid in protected mode, so we don't keep
; it: runTransient allocates the same size at the top of free memory again,
; which is the same memory unless something else has allocated memory there
; (and either way, the copy's checksum tells it whether the copy is intact).
;
; Outputs:
;	TRANS_HI = nonzero if there's a copy (zero if there wasn't room)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	resSave
	ASSUME	DS:CODE			; (DS = CS, since we own the code)
	mov	[TRANS_HI],0
	call	resAllocHi		; (no other session can have it now)
	jc	rsv9			; there's no room
	mov	[TRANS_HI],ax
	ASSUME	DS:DATA
	sub	di,di			; ES:DI -> copy
	mov	si,offset DGROUP:RES_END; DS:SI -> transient portion
	call	resCopy
;
; Free the block (in ES) again, so that the program can have it; the copy
; stays intact unless the program uses that memory.
;
	DEFLBL	resFree,near
	mov	ah,DOS_MEM_FREE
	int	21h
rsv9:	ret
ENDPROC	resSave

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resAllocHi
;
; Allocates a block for the transient portion's copy at the top of free
; memory (see resSave).
;
; Outputs:
;	Carry clear if successful: AX and ES = block
;	Carry set if there's no room
;
; Modifies:
;	AX, BX, ES
;
DEFPROC	resAllocHi
	mov	bx,ss:[PSP_CODESIZE]
	sub	bx,offset DGROUP:RES_END
	call	toParas			; BX = paras in the transient portion
	mov	ax,(DOS_MEM_ALLOC SHL 8) OR MCBTYPE_HIGH
	int	21h			; AX = block at the top of free memory
	jc	rah9			; there's no room
	mov	es,ax
rah9:	ret
ENDPROC	resAllocHi

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resCopy
;
; Copies the transient portion (or its copy) from DS:SI to ES:DI.
;
; Modifies:
;	CX, SI, DI
;
DEFPROC	resCopy
	mov	cx,ss:[PSP_CODESIZE]
	sub	cx,offset DGROUP:RES_END
	inc	cx
	shr	cx,1			; CX = # words
	cld
	rep	movsw
	ret
ENDPROC	resCopy

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resCtrlC
;
; CTRLC handler while an external program is running (see runTransient),
; which, like DOS's default handler, terminates the program, and the handler
; while the transient portion is being reloaded (rcIgnore), which doesn't.
;
DEFPROC	resCtrlC,FAR
	stc
	ret
rcIgnore:
	clc
	ret
ENDPROC	resCtrlC

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; hookFPU
;
; If there's an FPU$ driver, main calls this to hook INT 00h and INT 04h,
; which FPU$ raises for a division by zero and an overflow (or an invalid
; result), so that fpuTrap can make them runtime errors.  A copy that finds
; our handler already installed (by another copy that shares this code) leaves
; it alone, so its FPU_VECS stay zero.
;
; Inputs:
;	DS = SS = our PSP
;	BX -> our heap
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	hookFPU
	lea	di,[bx].FPU_VECS
	mov	al,INT_DV
	mov	dx,offset fpuTrap0
	call	hf1
	mov	al,INT_OF
	mov	dx,offset fpuTrap4
hf1:	push	bx
	push	es
	mov	ah,DOS_MSC_GETVEC
	int	21h			; ES:BX = current handler
	mov	cx,es
	mov	si,cs
	cmp	cx,si			; is it ours?
	jne	hf2			; no
	cmp	bx,dx
	je	hf3			; yes
hf2:	mov	[di]._OFF,bx
	mov	[di]._SEG,cx		; save the handler we're replacing
	push	ds
	push	cs
	pop	ds
	mov	ah,DOS_MSC_SETVEC
	int	21h			; DS:DX -> our handler
	pop	ds
hf3:	add	di,4
	pop	es
	pop	bx
	ret
ENDPROC	hookFPU

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; fpuTrap0 (INT 00h) and fpuTrap4 (INT 04h)
;
; If the current program is a copy of COMMAND (its code is ours), FPU$ raised
; the error for a BASIC program's floating-point operation (see hwDone and
; swRaise; FPU$'s decimal conversions, which the kernel's sprintf also uses,
; don't raise errors), so it becomes a runtime error ("Division by zero" or
; "Overflow"), which ON ERROR can trap, like the long operations' errors.
;
; Otherwise, the error belongs to another program, so we pass it to the
; handler that we replaced: the one saved by the nearest ancestor that hooked
; the vector (at ring 3, where every session has its own vectors, and a copy
; doesn't hook them again in a session where an ancestor did), or else by the
; copy that owns the shared code (where every session shares the vectors, so
; only the first copy hooks them).
;
DEFPROC	fpuTrap0,FAR
	push	ax
	mov	ax,BERR_DIVZERO		; AH = offset of INT 00h's FPU_VECS
	jmp	short ft1
	DEFLBL	fpuTrap4,far
	push	ax
	mov	ax,(4 SHL 8) OR BERR_OVERFLOW
ft1:	push	bx
	push	es
	push	ax
	mov	ah,DOS_PSP_GET
	int	21h			; BX = current PSP
	pop	ax
	mov	es,bx
	mov	bx,cs
	cmp	es:[PSP_START]._SEG,bx	; is it a copy of COMMAND?
	jne	ft3			; no
;
; Discard the registers we saved and the interrupt's return address, and
; restore the interrupted code's flags, which turns interrupts back on in
; real mode (ring 3 can't change IF, so it can't use STI).
;
	add	sp,10
	popf
	jmp	rtError			; AL = error # (rtError never returns)
ft3:	push	si
	push	bp
	mov	bp,sp			; BP+6 -> BX, BP+8 -> AX
	mov	al,ah
	cbw				; AX = offset of the vector's FPU_VECS
ft4:	mov	si,es:[PSP_PARENT]
	test	si,si			; any more ancestors?
	jz	ft6			; no
	mov	es,si
	cmp	es:[PSP_START]._SEG,bx	; is it a copy of COMMAND?
	jne	ft4			; no
	mov	si,es:[PSP_HEAP]
	add	si,ax
	cmp	es:[si].FPU_VECS._SEG,0	; did it hook the vector?
	je	ft4			; no
	jmp	short ft7
ft6:	mov	es,cs:[CODE_DS]		; the copy that owns the shared code
	mov	si,es:[PSP_HEAP]
	add	si,ax
ft7:	mov	ax,es:[si].FPU_VECS._OFF
	mov	si,es:[si].FPU_VECS._SEG
	xchg	ax,[bp+6]		; replace BX and AX on the stack
	xchg	si,[bp+8]		; with the replaced handler's address
	xchg	bx,ax
	xchg	ax,si
	pop	bp
	pop	si
	pop	es
	ret				; enter that handler (RETF)
ENDPROC	fpuTrap0
;
; The heap (and stack) of the copy that owns the shared code, which the loader
; uses because COMHEAP specifies it (see BEG_HEAP), so that it remains while
; the transient portion is discarded.  Like the heap at BEG_HEAP (used by other
; copies), it begins with initialized BLKDEFs; the rest is zero.
;
	even
	DEFLBL	RES_HEAP,byte
	BLKDEF	<0,CBLKLEN,size CBLK,SIG_CBLK>
	BLKDEF	<0,FBLKLEN,size FBLK,SIG_FBLK>
	BLKDEF	<0,VBLKLEN,size VBLK,SIG_VBLK>
	BLKDEF	<0,SBLKLEN,size SBLK,SIG_SBLK>
	BLKDEF	<0,TBLKLEN,size TBLK,SIG_TBLK>
	BLKDEF	<0,0,size BLKHDR,SIG_ABLK>	; array blocks (sized by DIM)
	db	size CMDHEAP - (offset $ - offset RES_HEAP) dup (0)
	even
	DEFLBL	RES_END,byte

CODE	ENDS

	end	entry
