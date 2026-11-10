;
; BASIC-DOS V86 Utility: DOS Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The DOS functions (INT 21h) that the machine's programs ask for: the ones
; that involve the machine (its vectors, DTA, PSPs, memory, and programs) are
; done here, and the rest are passed on to BASIC-DOS (see call_dos), with the
; current PSP's handles (see pft_load).
;
	include	v86host.inc

CODE    SEGMENT word public 'CODE'

	EXTBYTE	<VARS,in_call>
	EXTWORD	<cur_psp,root_psp>
	EXTLONG	<dta>
	EXTNEAR	<run,do_exit,do_ctrlc,seg_ptr,v86_get,v86_put>
	EXTNEAR	<get_word,put_word,push_word,pop_word>
	EXTNEAR	<mem_alloc,mem_free,mem_realloc,mem_freeall,load_prog>
	EXTNEAR	<start_prog,set_dta,fpu_copy>
	EXTWORD	<ld_cs,ld_ip,ld_ss,ld_sp>

	.286c

        ASSUME  CS:CODE, DS:CODE, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; int21
;
; Does the DOS function that the machine's program asked for, and then runs
; the machine again.
;
DEFPROC	int21
	push	ds
	pop	es
	mov	al,byte ptr [VARS+VR_EAX+1]
	mov	di,offset I21_FUNCS
	mov	cx,I21_FUNCS_LEN
	repne	scasb			; one we do here?
	jne	pass21			; no
	sub	di,offset I21_FUNCS + 1
	shl	di,1
	mov	ax,word ptr [VARS+VR_EAX]
	jmp	I21_PROCS[di]
;
; Pass anything else on to BASIC-DOS (see call_dos).
;
	DEFLBL	pass21,near
	mov	al,INT_DOSFUNC
	call	call_dos		; AX = result flags
	DEFLBL	i21f,near
	and	word ptr [VARS+VR_EFL],NOT FL_RESULTS
	or	word ptr [VARS+VR_EFL],ax
	jmp	run
	DEFLBL	i21ok,near
	sub	ax,ax			; no result flags (carry is clear)
	jmp	i21f
	DEFLBL	i21err,near		; AX = error code
	mov	word ptr [VARS+VR_EAX],ax
	mov	ax,FL_CARRY
	jmp	i21f
ENDPROC	int21

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; call_dos
;
; Does an INT (21h or 2Bh) with the machine's registers, DS and ES replaced
; by selectors for them, and the current PSP's handles in ours, and returns
; its registers to the machine.
;
; Inputs:
;	AL = INT_DOSFUNC or INT_DOSUTIL
;
; Outputs:
;	AX = result flags (see FL_RESULTS)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, BP, ES
;
DEFPROC	call_dos
	mov	byte ptr [cd_int+1],al
	call	pft_load
	mov	[in_call],1		; (see do_ctrlc)
	push	ds
	mov	ax,word ptr [VARS+VR_EAX]
	mov	bx,word ptr [VARS+VR_EBX]
	mov	cx,word ptr [VARS+VR_ECX]
	mov	dx,word ptr [VARS+VR_EDX]
	mov	si,word ptr [VARS+VR_ESI]
	mov	di,word ptr [VARS+VR_EDI]
	mov	bp,word ptr [VARS+VR_EBP]
	mov	es,word ptr [VARS+VR_ESSEL]
	mov	ds,word ptr [VARS+VR_DSSEL]
cd_int:	int	INT_DOSFUNC		; (or INT_DOSUTIL)
	pop	ds
	mov	word ptr [VARS+VR_EAX],ax
	mov	word ptr [VARS+VR_EBX],bx
	mov	word ptr [VARS+VR_ECX],cx
	mov	word ptr [VARS+VR_EDX],dx
	mov	word ptr [VARS+VR_ESI],si
	mov	word ptr [VARS+VR_EDI],di
	mov	word ptr [VARS+VR_EBP],bp
	pushf
	pop	ax
	and	ax,FL_RESULTS
	mov	[in_call],0
	DEFLBL	pft_save,near		; (save the handles; see pft_load)
	push	ax
	mov	ax,[cur_psp]
	mov	si,PSP_PFT
	mov	di,si
	mov	cx,PFT_LEN
	call	v86_put
	pop	ax
	ret
ENDPROC	call_dos

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pft_load
;
; Copies the current PSP's handles (its PSP_PFT) to ours, which is where DOS
; finds them, while we do a call for its program (see call_dos), after which
; pft_save copies them back.
;
; Modifies:
;	AX, CX, SI, DI, ES
;
DEFPROC	pft_load
	mov	ax,[cur_psp]
	mov	si,PSP_PFT
	mov	di,si
	mov	cx,PFT_LEN
	jmp	v86_get
ENDPROC	pft_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The DOS functions that we do here, and their handlers.
;
	DEFLBL	I21_FUNCS,byte
	db	DOS_PSP_TERM, DOS_DSK_SETDTA, DOS_MSC_SETVEC, DOS_DSK_GETDTA
	db	31h, DOS_MSC_GETVEC, DOS_HDL_CREATE, DOS_HDL_OPEN
	db	DOS_HDL_CLOSE, DOS_HDL_IOCTL, DOS_MEM_ALLOC, DOS_MEM_FREE
	db	DOS_MEM_REALLOC, DOS_PSP_EXEC SHR 8, DOS_PSP_RETURN
	db	DOS_PSP_RETCODE, DOS_PSP_SET, DOS_PSP_GET, DOS_MSC_GETVARS, 62h
I21_FUNCS_LEN	equ	$ - I21_FUNCS
	DEFLBL	I21_PROCS,word
	dw	i21term, i21sd, i21sv, i21gd
	dw	i21keep, i21gv, i21open, i21open
	dw	i21close, i21ioctl, i21alloc, i21free
	dw	i21realloc, i21exec, i21exit
	dw	i21retcode, i21setpsp, i21getpsp, i21vars, i21getpsp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Vectors, the DTA, and PSPs.
;
DEFPROC	i21sv				; set vector AL to DS:DX
	call	vec_ptr			; ES:DI -> vector
	mov	ax,word ptr [VARS+VR_EDX]
	mov	es:[di].OFF,ax
	mov	ax,word ptr [VARS+VR_DS]
	mov	es:[di].SEG,ax
	jmp	i21ok
	DEFLBL	i21gv,near		; get vector AL in ES:BX
	call	vec_ptr
	mov	ax,es:[di].OFF
	mov	cx,es:[di].SEG
	jmp	short i21esbx
	DEFLBL	i21sd,near		; set DTA to DS:DX
	mov	ax,word ptr [VARS+VR_EDX]
	mov	[dta].OFF,ax
	mov	ax,word ptr [VARS+VR_DS]
	mov	[dta].SEG,ax
	call	set_dta
	jmp	i21ok
	DEFLBL	i21gd,near		; get DTA in ES:BX
	mov	ax,[dta].OFF
	mov	cx,[dta].SEG
i21esbx:mov	word ptr [VARS+VR_EBX],ax
	mov	word ptr [VARS+VR_ES],cx
	jmp	i21ok
	DEFLBL	i21setpsp,near		; set PSP to BX
	mov	ax,word ptr [VARS+VR_EBX]
	mov	[cur_psp],ax
	jmp	i21ok
	DEFLBL	i21getpsp,near		; get PSP in BX
	mov	ax,[cur_psp]
	mov	word ptr [VARS+VR_EBX],ax
	jmp	i21ok
;
; DOS_MSC_GETVARS returns the total memory (in Kb) in AX, which for the
; program is the machine's.
;
	DEFLBL	i21vars,near
	mov	al,INT_DOSFUNC
	call	call_dos
	mov	word ptr [VARS+VR_EAX],V86_PARAS SHR 6
	jmp	i21f
ENDPROC	i21sv

;
; vec_ptr returns ES:DI -> the machine's vector AL.
;
DEFPROC	vec_ptr
	mov	ah,0
	shl	ax,2
	xchg	di,ax
	sub	ax,ax
	jmp	seg_ptr
ENDPROC	vec_ptr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Handles: a handle that a program opens is a reference to its SFH, as is
; each copy that a new PSP gets (see psp_build), and only when the last one
; is closed (or its PSP ends) does DOS close it.
;
DEFPROC	i21open				; (DOS_HDL_CREATE or DOS_HDL_OPEN)
	mov	al,INT_DOSFUNC
	call	call_dos
	test	al,FL_CARRY		; did it fail?
	jnz	io9			; yes
	mov	bx,word ptr [VARS+VR_EAX]
	mov	bl,ds:[PSP_PFT][bx]	; BL = its SFH
	mov	bh,0
	inc	byte ptr [VARS+V_REFS+bx]
io9:	jmp	i21f
	DEFLBL	i21close,near
	mov	bx,word ptr [VARS+VR_EBX]
	cmp	bx,PFT_LEN		; a valid handle?
	jae	ic8			; no (so let DOS say so)
	push	bx
	call	pft_load
	pop	bx
	call	sfh_close		; another reference?
	jnc	ic9			; yes
ic8:	jmp	pass21			; no, so DOS must close it
ic9:	jmp	i21ok
ENDPROC	i21open

;
; sfh_close drops a reference to the SFH of our handle BX (whose handles are
; those of the current PSP); if there are others, it frees the handle
; (saving the PSP's handles) and returns carry clear, and otherwise, carry
; set, so that the caller closes it.
;
DEFPROC	sfh_close
	mov	al,ds:[PSP_PFT][bx]
	cmp	al,SFH_NONE
	stc
	je	sc9			; not open (DOS will say so)
	push	bx
	mov	bl,al
	mov	bh,0
	cmp	byte ptr [VARS+V_REFS+bx],1	; the last reference?
	jbe	sc8			; yes
	dec	byte ptr [VARS+V_REFS+bx]
	pop	bx
	mov	byte ptr ds:[PSP_PFT][bx],SFH_NONE
	call	pft_save
	clc
	ret
sc8:	mov	byte ptr [VARS+V_REFS+bx],0
	pop	bx
	stc
sc9:	ret
ENDPROC	sfh_close

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; i21ioctl
;
; IOCTL_GETFPU (from FPU$) gets a far pointer to a copy of FPU$'s functions in
; the machine (see fpu_copy), which its programs call directly; every other
; IOCTL is passed on.
;
DEFPROC	i21ioctl
	cmp	al,IOCTL_GETFPU
	je	ii1
	jmp	pass21
ii1:	mov	al,INT_DOSFUNC
	call	call_dos		; the program's DS:SI = FPU$'s pointer
	test	al,FL_CARRY
	jnz	ii9
	mov	ax,[fpu_seg]
	test	ax,ax			; do we have a copy?
	jnz	ii2			; yes
	mov	ax,word ptr [VARS+VR_DS]
	mov	di,word ptr [VARS+VR_ESI]
	inc	di
	inc	di
	call	get_word		; AX = the FPUTBL's selector
	call	fpu_copy		; AX = its copy's segment
	jnc	ii1a
	jmp	i21err
ii1a:	mov	[fpu_seg],ax
ii2:	xchg	dx,ax
	mov	ax,word ptr [VARS+VR_DS]
	mov	di,word ptr [VARS+VR_ESI]
	inc	di
	inc	di
	call	put_word
	sub	dx,dx
	mov	di,word ptr [VARS+VR_ESI]
	call	put_word		; the program's DS:SI = the copy's
	sub	ax,ax
ii9:	jmp	i21f
ENDPROC	i21ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Memory blocks (see mem_alloc).
;
DEFPROC	i21alloc			; allocate BX paras, of type AL
	mov	bx,word ptr [VARS+VR_EBX]
	mov	dx,[cur_psp]
	call	mem_alloc
	jc	ia8
	mov	word ptr [VARS+VR_EAX],ax
	jmp	i21ok
ia8:	mov	word ptr [VARS+VR_EBX],bx
	jmp	i21err
	DEFLBL	i21free,near		; free ES
	mov	ax,word ptr [VARS+VR_ES]
	call	mem_free
	jc	ia9
	jmp	i21ok
	DEFLBL	i21realloc,near		; reallocate ES to BX paras
	mov	ax,word ptr [VARS+VR_ES]
	mov	bx,word ptr [VARS+VR_EBX]
	call	mem_realloc
	jc	ia8
	jmp	i21ok
ia9:	jmp	i21err
ENDPROC	i21alloc

;
; The registers that save_regs saves (in the order pushed), and that term_prog
; restores (in reverse).
;
	DEFLBL	REG_LIST,byte
	db	VR_DS, VR_ES, VR_EBP, VR_EDI, VR_ESI
	db	VR_EDX, VR_ECX, VR_EBX, VR_EAX
REGS_LEN	equ	($ - REG_LIST) * 2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; i21exec
;
; Loads a program (DS:DX) with the EPB at ES:BX into the machine, for AL = 0,
; 1, or 6 (see load_prog), and for AL = 0, starts it; or for AL = 2, starts
; the program that the current PSP loaded (with the EPB from AL = 1).  As in
; BASIC-DOS, the caller's registers are saved on its stack (see save_regs),
; and are restored when the program ends (see term_prog).
;
DEFPROC	i21exec
	cmp	al,2			; start?
	jne	ie1			; no
	jmp	ie5
ie1:	cmp	al,1
	jbe	ie2
	cmp	al,6
	je	ie2
	mov	ax,ERR_INVALID
ie1e:	jmp	i21err
ie2:	mov	[ie_func],al
	mov	ax,word ptr [VARS+VR_DS]
	mov	si,word ptr [VARS+VR_EDX]
	mov	di,offset VARS + V_PATH
	mov	cx,NAME_LEN - 1
	call	v86_get			; V_PATH = its name
	mov	byte ptr [VARS + V_PATH + NAME_LEN - 1],0
	mov	ax,word ptr [VARS+VR_ES]
	mov	si,word ptr [VARS+VR_EBX]
	mov	di,offset VARS + V_EPB
	mov	cx,size EPB
	call	v86_get			; V_EPB = its EPB
	mov	ax,word ptr [VARS + V_EPB + EPB_CMDTAIL + 2]
	mov	si,word ptr [VARS + V_EPB + EPB_CMDTAIL]
	mov	di,offset VARS + V_TAIL
	mov	cx,128
	call	v86_get			; V_TAIL = its command tail
	mov	bl,[VARS + V_TAIL]
	cmp	bl,126
	jbe	ie3
	mov	bl,126
	mov	[VARS + V_TAIL],bl
ie3:	mov	bh,0
	mov	byte ptr [VARS + V_TAIL + 1 + bx],CHR_RETURN
	mov	dx,offset VARS + V_PATH
	mov	ax,DOS_HDL_OPEN SHL 8	; AL = 0 (read)
	int	21h			; AX = its handle
	jc	ie1e
	xchg	bx,ax
	mov	al,INT_DOSEXIT
	call	vec_ptr			; ES:DI -> exit vector
	mov	ax,word ptr [VARS+VR_EIP]
	mov	es:[di].OFF,ax		; it returns to our caller
	mov	ax,word ptr [VARS+VR_CS]
	mov	es:[di].SEG,ax
	mov	ax,word ptr [VARS + V_EPB + EPB_ENVSEG]
	mov	cx,[cur_psp]
	call	load_prog		; AX = its PSP
	jc	ie1e
	push	ax
	mov	ax,[cur_psp]
	call	save_regs		; save the caller's registers
	pop	ax
	mov	[cur_psp],ax
	cmp	[ie_func],0		; start it, too?
	jne	ie4			; no
	call	start_prog
	jmp	run
;
; For AL = 1 (or 6), return the program's registers in the caller's EPB, with
; an initial AX (0) on its stack, as DOS does, and the caller continues.
;
ie4:	add	word ptr [VARS+VR_ESP],REGS_LEN	; (our caller's stack again)
	sub	[ld_sp],2
	mov	ax,[ld_ss]
	mov	di,[ld_sp]
	sub	dx,dx
	call	put_word
	mov	ax,word ptr [VARS+VR_ES]
	mov	bx,word ptr [VARS+VR_EBX]
	add	bx,EPB_INIT_SP
	mov	dx,[ld_sp]
	call	ie_put
	mov	dx,[ld_ss]
	call	ie_put
	mov	dx,[ld_ip]
	call	ie_put
	mov	dx,[ld_cs]
	call	ie_put
	mov	ax,[cur_psp]
	mov	[dta].SEG,ax
	mov	[dta].OFF,PSP_DTA
	call	set_dta
	jmp	i21ok
ie_put:	mov	di,bx			; put DX at the machine's AX:BX
	inc	bx
	inc	bx
	jmp	put_word
;
; For AL = 2, start the current PSP's program, at the EPB's registers (and
; with the trap flag, if DX asks for it), and it returns to our caller.
;
ie5:	mov	ax,word ptr [VARS+VR_ES]
	mov	si,word ptr [VARS+VR_EBX]
	add	si,EPB_INIT_SP
	mov	di,offset VARS + V_EPB + EPB_INIT_SP
	mov	cx,8
	call	v86_get			; its SS:SP and CS:IP
	mov	ax,[cur_psp]
	mov	di,PSP_EXIT
	mov	dx,word ptr [VARS+VR_EIP]
	call	put_word
	mov	di,PSP_EXIT + 2
	mov	dx,word ptr [VARS+VR_CS]
	call	put_word		; it returns to our caller
	mov	ax,[cur_psp]
	mov	di,PSP_PARENT
	call	get_word
	call	save_regs		; save the caller's registers
	mov	ax,word ptr [VARS + V_EPB + EPB_INIT_SP]
	mov	word ptr [VARS+VR_ESP],ax
	mov	ax,word ptr [VARS + V_EPB + EPB_INIT_SP + 2]
	mov	word ptr [VARS+VR_SS],ax
	call	pop_word
	mov	word ptr [VARS+VR_EAX],ax
	mov	ax,word ptr [VARS + V_EPB + EPB_INIT_IP]
	mov	word ptr [VARS+VR_EIP],ax
	mov	ax,word ptr [VARS + V_EPB + EPB_INIT_IP + 2]
	mov	word ptr [VARS+VR_CS],ax
	mov	ax,word ptr [VARS+VR_EDX]
	and	ax,FL_TRAP
	or	ax,FL_DEFAULT
	mov	word ptr [VARS+VR_EFL],ax
	mov	ax,[cur_psp]
	mov	word ptr [VARS+VR_DS],ax
	mov	word ptr [VARS+VR_ES],ax
	jmp	run
ENDPROC	i21exec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; save_regs
;
; Pushes the caller's registers (AX through DS, which term_prog restores when
; the program ends) on its stack, and saves its stack in its PSP's PSP_STACK.
;
; Inputs:
;	AX = the caller's PSP
;
; Modifies:
;	AX, BX, DX, SI, DI, ES
;
DEFPROC	save_regs
	push	ax
	mov	si,offset REG_LIST
	mov	bx,REGS_LEN / 2
sr1:	lodsb
	cbw
	xchg	di,ax
	mov	ax,word ptr VARS[di]
	call	push_word
	dec	bx
	jnz	sr1
	pop	ax
	mov	di,PSP_STACK
	mov	dx,word ptr [VARS+VR_ESP]
	call	put_word
	mov	di,PSP_STACK + 2
	mov	dx,word ptr [VARS+VR_SS]
	jmp	put_word
ENDPROC	save_regs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; term_prog
;
; Ends the current program (as DOS does): its handles are closed (see
; sfh_close), the vectors that its PSP saved are restored, its parent gets
; its exit code and type, its memory is freed (unless it's kept), and its
; parent continues at the exit vector, with the registers that it had when it
; started the program (see save_regs).  If it's the machine's first program,
; we end.
;
; Inputs:
;	AL = exit code, AH = exit type (EXTYPE_*)
;
DEFPROC	term_prog
	mov	bx,[cur_psp]
	cmp	bx,[root_psp]		; the machine's first program?
	jne	tp1			; no
	jmp	do_exit			; yes, so we end, too
tp1:	mov	[tp_code],ax
	call	pft_load
	sub	bx,bx
tp2:	cmp	byte ptr ds:[PSP_PFT][bx],SFH_NONE
	je	tp3a			; not open
	push	bx
	call	sfh_close		; another reference?
	jnc	tp3			; yes
	mov	ah,DOS_HDL_CLOSE
	int	21h			; no, so close it
tp3:	pop	bx
tp3a:	inc	bx
	cmp	bx,PFT_LEN
	jb	tp2
	mov	ax,[cur_psp]
	mov	si,PSP_EXIT
	mov	di,offset VARS + V_BUF
	mov	cx,12
	call	v86_get			; V_BUF = PSP_EXIT to PSP_ERROR
	mov	si,offset VARS + V_BUF
	sub	ax,ax
	mov	di,INT_DOSEXIT * 4
	mov	cx,12
	call	v86_put			; restore those vectors
	mov	ax,[cur_psp]
	mov	di,PSP_PARENT
	call	get_word
	mov	[tp_parent],ax
	mov	di,PSP_EXCODE
	mov	dx,[tp_code]
	call	put_word		; its parent gets its exit code
	mov	ax,[cur_psp]
	mov	di,PSP_DTAPREV
	call	get_word
	mov	[dta].OFF,ax
	mov	ax,[cur_psp]
	mov	di,PSP_DTAPREV + 2
	call	get_word
	mov	[dta].SEG,ax
	cmp	byte ptr [tp_code+1],EXTYPE_KEEP
	je	tp4
	mov	dx,[cur_psp]
	call	mem_freeall
tp4:	mov	ax,[tp_parent]
	mov	[cur_psp],ax
	call	set_dta
;
; The parent continues at the exit vector, with its registers.
;
	mov	ax,word ptr [VARS+V_BUF]
	mov	word ptr [VARS+VR_EIP],ax
	mov	ax,word ptr [VARS+V_BUF+2]
	mov	word ptr [VARS+VR_CS],ax
	mov	ax,[cur_psp]
	mov	di,PSP_STACK
	call	get_word
	mov	word ptr [VARS+VR_ESP],ax
	mov	ax,[cur_psp]
	mov	di,PSP_STACK + 2
	call	get_word
	mov	word ptr [VARS+VR_SS],ax
	mov	si,offset REG_LIST + REGS_LEN / 2
	mov	bx,REGS_LEN / 2
tp5:	dec	si
	call	pop_word
	push	ax
	mov	al,[si]
	cbw
	xchg	di,ax
	pop	ax
	mov	word ptr VARS[di],ax
	dec	bx
	jnz	tp5
	mov	word ptr [VARS+VR_EFL],FL_DEFAULT
	jmp	run
;
; DOS_PSP_TERM, DOS_PSP_RETURN, and 31h (keep, for which we keep DX paras).
;
	DEFLBL	i21term,near
	sub	ax,ax
	jmp	term_prog
	DEFLBL	i21exit,near
	mov	ah,EXTYPE_NORMAL
	jmp	term_prog
	DEFLBL	i21keep,near
	push	ax
	mov	ax,[cur_psp]
	mov	bx,word ptr [VARS+VR_EDX]
	call	mem_realloc
	pop	ax
	mov	ah,EXTYPE_KEEP
	jmp	term_prog
ENDPROC	term_prog

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; i21retcode
;
; Returns the exit code (AL) and type (AH) of the last program that ended; if
; it ended with CTRLC, its parent gets the CTRLC, too (as in BASIC-DOS), and
; this call is restarted (and returns) when the parent's handler returns.
;
DEFPROC	i21retcode
	mov	ax,[cur_psp]
	mov	di,PSP_EXCODE
	call	get_word
	mov	word ptr [VARS+VR_EAX],ax
	cmp	ah,EXTYPE_CTRLC
	je	rc1
	jmp	i21ok
rc1:	mov	dl,al
	mov	dh,EXTYPE_NORMAL
	mov	ax,[cur_psp]
	mov	di,PSP_EXCODE
	call	put_word
	mov	[in_call],1		; (so do_ctrlc restarts the call)
	jmp	do_ctrlc
ENDPROC	i21retcode

	DEFWORD	fpu_seg,0		; the machine's copy of FPU$, if any
	DEFWORD	tp_code,0		; the ending program's exit code
	DEFWORD	tp_parent,0		; and its parent
	DEFBYTE	ie_func,0		; the EXEC subfunction

CODE	ENDS

	end
