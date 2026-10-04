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
; discards before loading an external program (by shrinking our memory block)
; and then reloads from COMMAND.COM after the program ends, so that programs
; can use that memory, too.  Since the transient portion is reloaded from the
; file, it must not contain any data that changes; FPU_TABLE, for example, is
; kept here instead.
;
	include	cmd.inc

CODE    SEGMENT
	org	100h

	EXTNEAR	<main,ctrlc>
	EXTWORD	<BEG_HEAP>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

	DEFLBL	entry,near
	jmp	main
;
; FPU_TABLE is a far pointer to the FPU$ driver's FPUTBL, which every
; instance of this process obtains at startup (see main); it's the same for
; every instance, so it's fine to keep it in our shared code segment.  It
; remains zero if the FPU$ driver isn't available.
;
	DEFPTR	FPU_TABLE
	DEFWORD	CMD_REFS,0		; # of copies using the shared code
	DEFWORD	TRANS_SUM,0		; checksum of the transient portion
	DEFLBL	CMD_PATH,byte		; (main updates the drive letters)
	db	"A:COMMAND.COM",0
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
;	DS = ES = SS = CS (ie, the copy that owns the shared code)
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
	mov	bx,offset DGROUP:RES_END
	call	toParas
	mov	ah,DOS_MEM_REALLOC
	int	21h			; discard the transient portion
	pop	bx
	pop	dx
	mov	ax,DOS_PSP_EXEC1
	int	21h			; load the program at DS:DX
	jc	rt1
	mov	ax,DOS_PSP_EXEC2
	int	21h			; and run it
	clc
rt1:	pushf
	push	ax
	push	dx			; preserve DX for the caller's error path
	mov	dx,offset rcIgnore	; CTRLC must not terminate us, either,
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	int	21h			; until the transient portion is back
	push	cs
	pop	es
rt2:	call	resParas		; BX = paras for the transient, too
	mov	ah,DOS_MEM_REALLOC
	int	21h			; restore our memory block
	jnc	rt3
	mov	dx,offset MSG_NOMEM	; that should only fail if something
	call	resPrompt		; (eg, a TSR) is still using the memory
	jmp	rt2
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
	mov	cx,offset DGROUP:BEG_HEAP
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
	mov	ah,DOS_TTY_IN
	int	21h
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
	mov	bx,cs
	mov	cx,ss
	cmp	bx,cx			; do we own the shared code?
	jne	tp9			; no
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
	mov	bx,offset DGROUP:BEG_HEAP
	DEFLBL	toParas,near		; converts the offset in BX to paras
	add	bx,15
	mov	cl,4
	shr	bx,cl
	ret
ENDPROC	resParas

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; resSum
;
; Inputs:
;	None
;
; Outputs:
;	AX = checksum of the transient portion (the sum of its words)
;
; Modifies:
;	AX, CX, SI
;
DEFPROC	resSum
	mov	si,offset DGROUP:RES_END
	mov	cx,offset DGROUP:BEG_HEAP
	sub	cx,si
	shr	cx,1			; CX = # words in the transient portion
	sub	ax,ax
rs1:	add	ax,cs:[si]
	inc	si
	inc	si
	loop	rs1
	ret
ENDPROC	resSum

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
;
; The heap (and stack) of the copy that owns the shared code; main moves the
; heap here, so that it remains while the transient portion is discarded.
;
	even
	DEFLBL	RES_HEAP,byte
	db	size CMDHEAP dup (0)
	even
	DEFLBL	RES_END,byte

CODE	ENDS

	end	entry
