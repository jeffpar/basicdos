;
; BASIC-DOS V86 Utility: DOSUTIL Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The DOSUTIL functions (INT 2Bh) that the machine's programs ask for.  Most
; are passed on to BASIC-DOS (see call_dos), but some need more: the PRINTF
; functions' format strings (which follow the INT) and pointers, TOKID's and
; STRSTR's data in the program's CS, LOAD's command-line pointer, and the
; ones that involve the machine (QRYMEM, TERM, ALIAS, and MAPSEG).
;
; This module must be the last one linked (see the makefile), since the heap
; follows it.
;
	include	v86host.inc
	include	parser.inc

CODE    SEGMENT word public 'CODE'

	EXTBYTE	<in_call>
	EXTWORD	<cur_psp>
	EXTNEAR	<run,call_dos,pft_load,pft_save,i21f,i21ok,i21err>
	EXTNEAR	<term_prog,seg_ptr,v86_ptr,v86_get,v86_put,get_word>
	EXTNEAR	<mem_query>

	.286c

        ASSUME  CS:CODE, DS:CODE, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; int2b
;
; Does the DOSUTIL function that the machine's program asked for, and then
; runs the machine again.
;
DEFPROC	int2b
	push	ds
	pop	es
	mov	al,byte ptr [VARS+VR_EAX+1]
	mov	di,offset I2B_FUNCS
	mov	cx,I2B_FUNCS_LEN
	repne	scasb			; one we do here?
	jne	pass2b			; no
	sub	di,offset I2B_FUNCS + 1
	shl	di,1
	mov	ax,word ptr [VARS+VR_EAX]
	jmp	I2B_PROCS[di]
	DEFLBL	pass2b,near
	mov	al,INT_DOSUTIL
	call	call_dos
	jmp	i21f
ENDPROC	int2b

	DEFLBL	I2B_FUNCS,byte
	db	DOS_UTL_STRSTR, DOS_UTL_PRINTF, DOS_UTL_HPRINTF
	db	DOS_UTL_DPRINTF, DOS_UTL_SPRINTF, DOS_UTL_TPRINTF
	db	DOS_UTL_TOKID, DOS_UTL_PARSESW, DOS_UTL_LOAD
	db	DOS_UTL_QRYMEM, DOS_UTL_TERM, DOS_UTL_ALIAS, DOS_UTL_MAPSEG
I2B_FUNCS_LEN	equ	$ - I2B_FUNCS
	DEFLBL	I2B_PROCS,word
	dw	ustrstr, uprintf, uprintf
	dw	uprintf, uprintf, uprintf
	dw	utokid, uparsesw, uload
	dw	uqrymem, uterm, ualias, umapseg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uprintf
;
; The PRINTF functions read their format strings from the caller's CS:IP
; (after the INT), or for TPRINTF, from DS:BX, and their parameters from the
; caller's stack.  So we copy the format to V_STUB (after an INT 2Bh, and
; followed by a JMP back to us), with each %s changed to %ls, and copy the
; parameters to V_PARMS, with every pointer changed to a far pointer through
; the machine's selectors, and do the INT there, with those parameters on our
; stack.  For TPRINTF, whose parameters are typed (VAR_LONG, VAR_STR, or
; VAR_DOUBLE, and a value), the strings and doubles are pointers, too.
;
DEFPROC	uprintf
	mov	word ptr [VARS+V_STUB],(INT_DOSUTIL SHL 8) OR OP_INT
	mov	[pf_typed],0
	mov	cx,word ptr [VARS+VR_CS]
	mov	si,word ptr [VARS+VR_EIP]
	cmp	ah,DOS_UTL_TPRINTF
	jne	up1
	inc	[pf_typed]
	mov	cx,word ptr [VARS+VR_DS]
	mov	si,word ptr [VARS+VR_EBX]
up1:	xchg	ax,cx
	mov	di,offset VARS + V_BUF
	mov	cx,BUF_LEN
	call	v86_get			; V_BUF = (at most) the format
	mov	ax,word ptr [VARS+VR_ESP]
	mov	[pf_parm],ax		; the next parameter (on its stack)
	mov	si,offset VARS + V_BUF
	mov	di,offset VARS + V_STUB + 2
	cmp	[pf_typed],0		; is the format inline?
	je	up1a			; yes
	call	pf_jmp			; no, so the JMP follows the INT
up1a:	mov	[pf_fmt],di		; DI -> where the format goes
	mov	bx,offset VARS + V_PARMS
	push	ds
	pop	es
up2:	cmp	di,offset VARS + V_STUB + STUB_LEN - 8
	jae	up2a			; (the stub is full)
	lodsb
	stosb
	test	al,al			; the end of the format?
	jnz	up2b			; no
	jmp	up9
up2a:	mov	al,0			; (end it there)
	stosb
	jmp	up9
up2b:	cmp	al,'%'
	jne	up2
	mov	[pf_lflag],0
up3:	lodsb
	stosb
	cmp	al,'%'			; "%%"
	je	up2
	cmp	al,'l'
	jne	up4
	inc	[pf_lflag]
	jmp	up3
up4:	push	di
	mov	di,offset PF_FLAGS
	mov	cx,PF_FLAGS_LEN
	repne	scasb			; a flag (or width, or precision)?
	pop	di
	je	up3			; yes
	cmp	al,'*'			; a width (or precision) parameter?
	je	up6			; yes
	cmp	al,'s'
	je	up5
	cmp	al,'f'
	je	up5a
	push	di
	mov	di,offset PF_TYPES
	mov	cx,PF_TYPES_LEN
	repne	scasb			; a type that takes a value?
	pop	di
	jne	up2			; no
	cmp	[pf_typed],0
	jne	up6
	call	pf_word			; yes
	cmp	[pf_lflag],0
	je	up2
	call	pf_word			; (and a long takes two)
	jmp	up2
up5:	cmp	[pf_typed],0		; %s
	jne	up6
	cmp	[pf_lflag],0		; a far pointer already?
	jne	up5a			; yes
	mov	byte ptr [di-1],'l'	; no, so make it one: %ls
	mov	al,'s'
	stosb
	call	pf_getw			; AX = its offset
	mov	cx,word ptr [VARS+VR_DS]
	jmp	short up5b
up5a:	cmp	[pf_typed],0		; %f (or %ls), a far pointer
	jne	up6
	call	pf_getw
	push	ax
	call	pf_getw
	xchg	cx,ax
	pop	ax			; CX:AX = the far pointer
up5b:	call	pf_far
	jmp	up2
up6:	cmp	[pf_typed],0		; a typed parameter?
	jne	up7			; yes
	call	pf_word			; no, just a word ("*")
	jmp	up3
up7:	call	pf_getw			; AX = type
	mov	[bx],ax
	inc	bx
	inc	bx
	push	ax
	call	pf_getw
	push	ax
	call	pf_getw
	xchg	cx,ax
	pop	ax			; CX:AX = its value
	pop	dx
	cmp	dl,VAR_STR		; a pointer?
	je	up8
	cmp	dl,VAR_DOUBLE
	je	up8			; yes
	mov	[bx],ax
	mov	[bx+2],cx
	add	bx,4
	jmp	short up8a
up8:	call	pf_far
up8a:	cmp	byte ptr [di-1],'*'	; was it for a width?
	jne	up8b			; no
	jmp	up3			; yes, so the specifier continues
up8b:	jmp	up2
;
; Do the INT, at V_STUB, which jumps back to pf_back.
;
up9:	sub	si,offset VARS + V_BUF
	mov	[pf_flen],si		; the format's length (with its null)
	call	pf_jmp			; (after the format, if inline)
	mov	[pf_ret],offset pf_back
	sub	bx,offset VARS + V_PARMS
	mov	[pf_plen],bx		; the parameters' length
	call	pft_load
	mov	cx,[pf_plen]
	sub	sp,cx
	mov	di,sp
	mov	si,offset VARS + V_PARMS
	rep	movsb			; the parameters, on our stack
	mov	[in_call],1		; (see do_ctrlc)
	mov	ax,word ptr [VARS+VR_EAX]
	mov	bx,word ptr [VARS+VR_EBX]
	mov	cx,word ptr [VARS+VR_ECX]
	mov	di,word ptr [VARS+VR_EDI]
	mov	es,word ptr [VARS+VR_ESSEL]
	cmp	ah,DOS_UTL_SPRINTF	; is the format at DS:BX, too?
	jb	upa			; no
	mov	bx,[pf_fmt]
upa:	mov	si,offset VARS + V_STUB
	jmp	si
pf_back:mov	word ptr [VARS+VR_EAX],ax
	pushf
	pop	ax
	and	ax,FL_RESULTS
	add	sp,[pf_plen]
	mov	[in_call],0
	call	pft_save
	cmp	[pf_typed],0		; was the format inline?
	jne	upb			; no
	mov	cx,[pf_flen]
	add	word ptr [VARS+VR_EIP],cx	; yes, so skip it
upb:	jmp	i21f
ENDPROC	uprintf

;
; pf_jmp stores a JMP back to us (through pf_ret) at DI, which the INT returns
; to: after the format (which DOS skips), or for TPRINTF, right after the INT.
;
DEFPROC	pf_jmp
	mov	ax,26FFh		; JMP [pf_ret]
	stosw
	mov	ax,offset pf_ret
	stosw
	ret
ENDPROC	pf_jmp

;
; pf_word copies a parameter word to [BX] (and BX advances), pf_getw gets one
; (in AX), and pf_far stores the far pointer CX:AX (a segment and offset in
; the machine) as one through the machine's selectors.
;
DEFPROC	pf_word
	call	pf_getw
	mov	[bx],ax
	inc	bx
	inc	bx
	ret
ENDPROC	pf_word

DEFPROC	pf_getw
	push	di
	push	es
	mov	ax,word ptr [VARS+VR_SS]
	mov	di,[pf_parm]
	add	[pf_parm],2
	call	get_word
	pop	es
	pop	di
	ret
ENDPROC	pf_getw

DEFPROC	pf_far
	push	di
	push	es
	push	ax
	or	ax,cx			; a null pointer?
	pop	ax
	jz	pfr1			; yes, so it stays one
	push	ax
	xchg	ax,cx
	pop	di
	call	seg_ptr			; ES:DI -> the machine's CX:AX
	mov	ax,di
	mov	cx,es
pfr1:	mov	[bx],ax
	mov	[bx+2],cx
	add	bx,4
	pop	es
	pop	di
	ret
ENDPROC	pf_far

	DEFSTR	PF_FLAGS,<"-#0123456789.b">
	DEFSTR	PF_TYPES,<"cdux","WFMDXYGHNSA">

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ustrstr
;
; STRSTR's source string is at the caller's CS:SI, so we copy it to V_BUF,
; which is at the same offset in our CS.
;
DEFPROC	ustrstr
	mov	ax,word ptr [VARS+VR_CS]
	mov	si,word ptr [VARS+VR_ESI]
	push	si
	mov	di,offset VARS + V_BUF
	mov	cx,BUF_LEN
	call	v86_get
	mov	byte ptr [VARS + V_BUF + BUF_LEN - 1],0
	mov	word ptr [VARS+VR_ESI],offset VARS + V_BUF
	mov	al,INT_DOSUTIL
	call	call_dos
	pop	word ptr [VARS+VR_ESI]
	jmp	i21f
ENDPROC	ustrstr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utokid
;
; TOKID's table (TOKTBL and its TOKDEFs, sorted) is at the caller's CS:DX, so
; we search it here, as utl_tokid does: the token (CX chars at DS:SI) is
; upper-cased, and on a match, AX = its ID and SI -> its TOKDEF (carry
; clear); otherwise, AX = 0 (carry set).
;
DEFPROC	utokid
	mov	cx,word ptr [VARS+VR_ECX]
	mov	ch,0
	mov	[tk_len],cl
	mov	ax,word ptr [VARS+VR_DS]
	mov	si,word ptr [VARS+VR_ESI]
	mov	di,offset VARS + V_BUF
	push	di
	call	v86_get			; V_BUF = the token
	pop	si
	mov	cl,[tk_len]
	jcxz	tk1
tk0:	mov	al,[si]
	cmp	al,'a'
	jb	tk0a
	cmp	al,'z'
	ja	tk0a
	sub	byte ptr [si],20h
tk0a:	inc	si
	loop	tk0
tk1:	mov	ax,word ptr [VARS+VR_CS]
	mov	di,word ptr [VARS+VR_EDX]
	call	get_word		; AL = # TOKDEFs, AH = size of each
	mov	[tk_bot],al
	mov	[tk_size],ah
	mov	[tk_top],0
tk2:	mov	al,[tk_top]
	cmp	al,[tk_bot]		; nothing left?
	je	tk8			; right, so no match
	add	al,[tk_bot]
	mov	ah,0
	rcr	ax,1			; AL = the middle
	mov	[tk_mid],al
	mul	[tk_size]
	add	ax,word ptr [VARS+VR_EDX]
	add	ax,2
	mov	[tk_def],ax		; the TOKDEF's offset
	xchg	si,ax
	mov	ax,word ptr [VARS+VR_CS]
	mov	di,offset VARS + V_HDR
	mov	cx,size TOKDEF
	call	v86_get			; V_HDR = the TOKDEF
	mov	ax,word ptr [VARS+VR_CS]
	mov	si,word ptr [VARS + V_HDR + TOKDEF_OFF]
	mov	cl,[VARS + V_HDR + TOKDEF_LEN]
	mov	ch,0
	mov	di,offset VARS + V_FCB
	call	v86_get			; V_FCB = its string
	mov	si,offset VARS + V_BUF
	mov	di,offset VARS + V_FCB
	mov	cl,[tk_len]
	mov	ch,[VARS + V_HDR + TOKDEF_LEN]
	push	ds
	pop	es
tk3:	lodsb
	scasb				; compare the token to its string
	jne	tk5
	sub	cx,0101h
	jz	tk7			; a match
	test	cl,cl
	stc
	jz	tk5			; the token is shorter (so it's less)
	test	ch,ch
	jz	tk5			; its string is shorter (so it's more)
	jmp	tk3
tk5:	mov	al,[tk_mid]
	jnc	tk6
	mov	[tk_bot],al		; less, so look below the middle
	jmp	tk2
tk6:	inc	ax
	mov	[tk_top],al		; more, so look above it
	jmp	tk2
tk7:	mov	al,[VARS + V_HDR + TOKDEF_ID]
	mov	ah,0
	mov	word ptr [VARS+VR_EAX],ax
	mov	ax,[tk_def]
	mov	word ptr [VARS+VR_ESI],ax
	jmp	i21ok
tk8:	sub	ax,ax
	mov	word ptr [VARS+VR_EAX],ax
	mov	ax,FL_CARRY
	jmp	i21f
ENDPROC	utokid

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uparsesw
;
; PARSESW records the switches in our PSP (PSP_DIGITS and PSP_LETTERS), so
; they're copied to the current PSP.
;
DEFPROC	uparsesw
	mov	al,INT_DOSUTIL
	call	call_dos
	push	ax
	mov	ax,[cur_psp]
	mov	si,PSP_DIGITS
	mov	di,si
	mov	cx,6
	call	v86_put
	pop	ax
	jmp	i21f
ENDPROC	uparsesw

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uload
;
; LOAD loads a program into a new session (eg, a pipeline's next program),
; which runs as an ordinary BASIC-DOS program, not in the machine; its SPB
; (at ES:BX) is copied to V_EPB, with its command-line pointer changed to
; one through the machine's selectors (and no environment).
;
DEFPROC	uload
	mov	ax,word ptr [VARS+VR_ES]
	mov	si,word ptr [VARS+VR_EBX]
	push	si
	mov	di,offset VARS + V_EPB
	mov	cx,size SPB
	call	v86_get
	mov	ax,word ptr [VARS + V_EPB + SPB_CMDLINE + 2]
	mov	di,word ptr [VARS + V_EPB + SPB_CMDLINE]
	call	seg_ptr
	mov	word ptr [VARS + V_EPB + SPB_CMDLINE],di
	mov	word ptr [VARS + V_EPB + SPB_CMDLINE + 2],es
	mov	word ptr [VARS + V_EPB + SPB_ENVSEG],0
	push	word ptr [VARS+VR_ESSEL]
	mov	word ptr [VARS+VR_ESSEL],ds
	mov	word ptr [VARS+VR_EBX],offset VARS + V_EPB
	mov	al,INT_DOSUTIL
	call	call_dos
	pop	word ptr [VARS+VR_ESSEL]
	pop	word ptr [VARS+VR_EBX]
	jmp	i21f
ENDPROC	uload

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uqrymem
;
; QRYMEM finds the machine's blocks (see mem_query).
;
DEFPROC	uqrymem
	mov	cx,word ptr [VARS+VR_ECX]
	mov	dx,word ptr [VARS+VR_EDX]
	call	mem_query		; AX = MCB, ES:DI -> MCB
	jnc	uq1
	mov	ax,FL_CARRY
	jmp	i21f
uq1:	mov	word ptr [VARS+VR_ES],ax
	mov	word ptr [VARS+VR_EDI],MCB_NAME
	inc	ax
	mov	word ptr [VARS+VR_EBX],ax
	mov	ax,es:[di].MCB_OWNER
	mov	word ptr [VARS+VR_EAX],ax
	mov	ax,es:[di].MCB_PARAS
	mov	dx,ax
	shl	ax,4
	shr	dx,12
	mov	word ptr [VARS+VR_EDX],ax
	mov	word ptr [VARS+VR_ESI],dx
	jmp	i21ok
ENDPROC	uqrymem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uterm, ualias, and umapseg
;
; TERM ends the program, with exit code DL and type DH; ALIAS's code alias of
; a block is the block, as in real mode, and so is MAPSEG's selector for a
; segment, and MAPSEG with AL = 1 gets the word at BX:SI (in the machine,
; below V86_PARAS); a V86 machine can't make one of its own.
;
DEFPROC	uterm
	mov	ax,word ptr [VARS+VR_EDX]
	jmp	term_prog
	DEFLBL	ualias,near
	mov	ax,word ptr [VARS+VR_EBX]
	mov	word ptr [VARS+VR_EAX],ax
	jmp	i21ok
	DEFLBL	umapseg,near
	cmp	al,1
	jb	ualias
	ja	um8
	mov	ax,word ptr [VARS+VR_EBX]
	cmp	ax,V86_PARAS		; in the machine?
	jb	um1			; yes
	jmp	pass2b			; no (eg, the ROM)
um1:	mov	di,word ptr [VARS+VR_ESI]
	call	get_word
	mov	word ptr [VARS+VR_EAX],ax
	jmp	i21ok
um8:	mov	ax,ERR_INVALID
	jmp	i21err
ENDPROC	uterm

	DEFWORD	pf_ret,0		; (see uprintf)
	DEFWORD	pf_fmt,0		; the format's copy
	DEFWORD	pf_parm,0		; the next parameter's offset
	DEFWORD	pf_flen,0		; the format's length
	DEFWORD	pf_plen,0		; the parameters' length
	DEFBYTE	pf_typed,0		; nonzero for TPRINTF
	DEFBYTE	pf_lflag,0		; nonzero after an 'l'
	DEFBYTE	tk_len,0		; (see utokid) the token's length
	DEFBYTE	tk_top,0		; the first TOKDEF to search
	DEFBYTE	tk_bot,0		; the one after the last
	DEFBYTE	tk_mid,0		; the middle one
	DEFBYTE	tk_size,0		; the size of each
	DEFWORD	tk_def,0		; the middle one's offset

	COMHEAP	<V_END + STACK_LEN>	; (must be the last item)
	DEFLBL	VARS,byte		; (the heap; see v86host.inc)

CODE	ENDS

	end
