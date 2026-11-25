;
; BASIC-DOS Code Generator: Labels and Control Structures
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The label and control-structure bookkeeping for genflow.asm's statements
; (eg, addLabel, findLabel, pushCtl, and checkRefs), which is separate only
; because genflow.asm has no symbol space for it.
;
	DOSFUNC equ 1
	GENDEFS equ 1
	include	cmd.inc
	include	gen.inc

CODE    SEGMENT

	EXTNEAR	<compErrLine,getLineNum,patchJmp>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

LBL_MAX		equ	LBL_DATA	; highest label defined so far

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; firstBlock and nextBlock
;
; Labels (and open FORs and WHILEs) may be in any block of the code block
; chain, since each block has its own LBLREF table; a function block, however,
; is a chain of one.
;
; Inputs:
;	ES -> code (or function) block
;
; Outputs:
;	AX = first (or next) block, or zero if none
;
; Modifies:
;	AX
;
DEFPROC	firstBlock
	mov	ax,es
	cmp	es:[BLK_SIG],SIG_CBLK	; code block?
	jne	fb9			; no
	push	si
	mov	si,ss:[PSP_HEAP]
	mov	ax,ss:[si].CBLKDEF.BDEF_NEXT
	pop	si
fb9:	ret
ENDPROC	firstBlock

DEFPROC	nextBlock
	sub	ax,ax
	cmp	es:[BLK_SIG],SIG_CBLK	; code block?
	jne	nb9			; no
	mov	ax,es:[BLK_NEXT]
nb9:	ret
ENDPROC	nextBlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; addLabel
;
; Adds a label definition or reference (if LBL_RESOLVE is set) to the current
; code block's LBLREF table.  For a definition, we first scan all the LBLREF
; tables to resolve any references (by replacing their placeholders with JMPs,
; and then removing them; see genGoto and removeRef).  A duplicate definition
; (from a line # that appears twice) is added, too, but findLabel finds the
; oldest, so the first one generated wins.
;
; Since every numbered line is a definition, scanning for every one would take
; time proportional to the square of the number of lines, so we keep a map of
; the label #s that references are waiting for (see lblBit), and a definition
; whose bit is clear can't resolve anything, so it needs no scan.  The scan of
; the code blocks rebuilds the map from the references that are left; the scan
; of a function block (during a DEF block, which has its own labels, and which
; is always scanned) doesn't, since it can't see the code blocks' references.
; We also keep a map of the label #s defined, and the highest label defined so
; far (LBL_MAX), for findLabel.
;
; Inputs:
;	AX = label #
;	DI = code gen offset (+ LBL_RESOLVE for a reference)
;	ES -> current code block
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	addLabel
	push	bx
	push	si
	mov	dx,ax			; DX = label #
	mov	cx,es			; CX = current code block
	call	lblBit			; ES:BX -> its bit, AL = mask
	test	di,LBL_RESOLVE		; is this a reference?
	jz	al0			; no
	or	es:[bx],al		; yes, so it's waiting for the label
al8:	mov	es,cx
	mov	si,es:[CBLK_REFS]
	sub	si,size LBLREF
	mov	es:[CBLK_REFS],si
	mov	es:[si].LBL_NUM,dx
	mov	es:[si].LBL_IP,di
	clc
	pop	si
	pop	bx
	ret

al0:	or	es:[bx+LBL_MAPLEN],al	; the label is defined
	mov	si,ss:[PSP_HEAP]
	cmp	dx,ss:[si+LBL_MAX]	; beyond the highest label so far?
	jbe	al0a			; no
	mov	ss:[si+LBL_MAX],dx	; yes, so it's the new highest
al0a:	test	es:[bx],al		; could a reference be waiting for it?
	mov	es,cx
	jnz	al0b			; yes
	cmp	es:[BLK_SIG],SIG_CBLK	; in a code block?
	je	al8			; yes, so there's nothing to resolve
al0b:	cmp	es:[BLK_SIG],SIG_CBLK	; are we scanning the code blocks?
	mov	bx,0			; (BX = 0 if not rebuilding the map)
	jne	al0c			; no
	push	cx
	push	di
	call	lblBit			; BX = non-zero (rebuilding the map)
	mov	di,es:[BLK_SIZE]	; ES:DI -> map of references
	mov	cx,LBL_MAPLEN / 2
	sub	ax,ax
	rep	stosw			; (the scan will rebuild it)
	pop	di
	pop	cx
	mov	es,cx
al0c:	call	firstBlock		; AX = first block
al1:	mov	es,ax
	mov	si,es:[CBLK_REFS]
al2:	cmp	si,es:[BLK_SIZE]	; end of this LBLREF table?
	jae	al5			; yes
	mov	ax,es:[si].LBL_IP
	cmp	es:[si].LBL_NUM,dx	; label # match?
	je	al3			; yes
	test	ax,LBL_RESOLVE		; another reference?
	jz	al4			; no
	test	bx,bx			; rebuilding the map?
	jz	al4			; no
	push	es
	push	dx
	push	bx
	mov	dx,es:[si].LBL_NUM
	call	lblBit
	or	es:[bx],al		; it's still waiting for its label
	pop	bx
	pop	dx
	pop	es
	jmp	short al4
al3:	test	ax,LBL_RESOLVE		; is this a reference?
	jz	al4			; no, an earlier definition
	push	si
	push	dx
	and	ax,NOT LBL_RESOLVE
	xchg	si,ax			; ES:SI -> placeholder
	mov	dx,cx
	mov	ax,di			; DX:AX -> target
	call	patchJmp
	pop	dx
	pop	si
	call	removeRef		; the reference is resolved
al4:	add	si,size LBLREF
	jmp	al2
al5:	call	nextBlock
	test	ax,ax
	jnz	al1
	jmp	al8
ENDPROC	addLabel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; lblBit
;
; Finds a label #'s bit in addLabel's maps (see genInit), which have a bit for
; each value of a label #'s low byte, so a clear bit means that no label # in
; the map has that low byte.
;
; Inputs:
;	DX = label #
;
; Outputs:
;	ES:BX -> its byte in the map of references (the map of definitions
;	follows it), AL = its bit
;
; Modifies:
;	AX, BX, ES
;
DEFPROC	lblBit
	push	cx
	mov	cl,dl
	and	cl,7
	mov	al,1
	shl	al,cl			; AL = bit
	mov	bl,dl
	mov	cl,3
	shr	bl,cl
	mov	bh,0			; BX = byte
	mov	cx,ss:[PSP_HEAP]
	xchg	cx,bx
	mov	es,ss:[bx].CBLKDEF.BDEF_NEXT
	xchg	cx,bx
	add	bx,es:[BLK_SIZE]	; ES:BX -> byte in the first code block
	pop	cx
	ret
ENDPROC	lblBit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; removeRef
;
; Removes a resolved reference, or a FOR or WHILE whose NEXT or WEND has been
; generated, from its block's LBLREF table, by moving the newer entries (those
; below it) up over it, so that the scans (eg, addLabel's and findCtl's) see
; only labels and the references and loops still in progress.  An entry above
; it (eg, the next one addLabel's scan examines) doesn't move.
;
; Inputs:
;	ES:SI -> LBLREF
;
; Outputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	removeRef
	push	cx
	push	si
	push	di
	push	ds
	push	es
	pop	ds			; DS:SI -> LBLREF
	mov	cx,si
	sub	cx,es:[CBLK_REFS]	; (FBLK_REFS is the same)
	shr	cx,1			; CX = # words of newer entries
	lea	di,[si+size LBLREF-2]	; ES:DI -> last word of the LBLREF
	dec	si
	dec	si			; DS:SI -> last word of the newer ones
	std
	rep	movsw
	cld
	add	es:[CBLK_REFS],size LBLREF
	pop	ds
	pop	di
	pop	si
	pop	cx
	ret
ENDPROC	removeRef

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findLabel
;
; A label beyond the highest one defined so far (LBL_MAX; see addLabel), or
; whose bit in the map of definitions is clear, can't be defined yet, so a
; forward reference (the usual case) rarely needs a scan.  The code blocks are
; scanned in order, each from its oldest entry, so if a line # appears twice,
; the first definition generated is the one we find.
;
; Inputs:
;	AX = label #
;	ES:DI -> current code block
;
; Outputs:
;	Carry clear if found, DX:AX -> label; otherwise, a reference is added
;	(see addLabel)
;
; Modifies:
;	AX, CX, DX
;
DEFPROC	findLabel
	push	si
	mov	si,ss:[PSP_HEAP]
	cmp	ax,ss:[si+LBL_MAX]	; beyond the highest label so far?
	ja	fl5			; yes, so it's a forward reference
	push	es
	push	bx
	mov	dx,ax			; DX = label #
	call	lblBit			; ES:BX -> its bit, AL = mask
	test	es:[bx+LBL_MAPLEN],al	; could the label be defined?
	pop	bx
	pop	es
	jz	fl5a			; no
	push	es
	call	firstBlock		; AX = first block
fl1:	mov	es,ax
	mov	si,es:[BLK_SIZE]	; (the oldest entries come last)
fl2:	sub	si,size LBLREF
	cmp	si,es:[CBLK_REFS]	; start of this LBLREF table?
	jb	fl4			; yes
	cmp	es:[si].LBL_NUM,dx	; label # match?
	jne	fl2			; no
	mov	ax,es:[si].LBL_IP
	test	ax,LBL_RESOLVE		; is this a reference?
	jz	fl8			; no, it's the (oldest) definition
	jmp	fl2
fl4:	call	nextBlock
	test	ax,ax
	jnz	fl1
	pop	es
fl5a:	xchg	ax,dx			; AX = label #
fl5:	pop	si
	push	di
	or	di,LBL_RESOLVE
	call	addLabel		; add a reference
	pop	di
	stc
	ret
fl8:	mov	dx,es			; DX:AX -> label
	pop	es
	pop	si
	clc
	ret
ENDPROC	findLabel

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pushCtl
;
; Stores the line # of the FOR or WHILE (for checkCtl) and its line's position
; (LINE_NUM, for findCtl and genRegion), and then pushes a CTL_FOR or CTL_WHILE
; entry for the loop's body (which follows them) onto the code block's LBLREF
; table.
;
; Inputs:
;	AX = CTL_FOR or CTL_WHILE
;	ES:DI -> code block
;
; Outputs:
;	Carry clear
;
; Modifies:
;	AX, CX, DX, SI, DI
;
DEFPROC	pushCtl
	xchg	dx,ax			; DX = CTL_FOR or CTL_WHILE
	call	getLineNum		; CX = line #, SI -> heap
	xchg	ax,cx
	stosw				; store the line #
	mov	ax,ss:[si].LINE_NUM
	stosw				; and the line's position
	xchg	ax,dx			; AX = CTL_FOR or CTL_WHILE
	mov	dx,di			; DX = offset of the loop's body
	push	di
	mov	di,es:[CBLK_REFS]	; (FBLK_REFS is the same)
	sub	di,size LBLREF
	mov	es:[CBLK_REFS],di
	stosw				; LBL_NUM <- AX
	xchg	ax,dx
	stosw				; LBL_IP <- DX
	pop	di
	clc
	ret
ENDPROC	pushCtl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findCtl
;
; Finds the innermost open FOR or WHILE: the one on the nearest line at or
; before the current line (and if a line has several, the last one), rather
; than the last one generated, since lines may be generated out of order (see
; genRegion).  findCtlAt finds the one nearest the line at position CX.
;
; Inputs:
;	ES -> code block
;	CX = position (findCtlAt only; 0FFFFh for any line)
;
; Outputs:
;	If carry clear, DX:SI -> LBLREF, AX = CTL_FOR or CTL_WHILE;
;	otherwise, AX = 0
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	findCtl
	mov	si,ss:[PSP_HEAP]
	mov	cx,ss:[si].LINE_NUM	; CX = the current line's position
	DEFLBL	findCtlAt,near
	push	es
	push	bx
	push	di
	sub	dx,dx			; DX = 0 (none found yet)
	sub	di,di			; DI = position + 1 of the best so far
	call	firstBlock		; AX = first block
fc1:	mov	es,ax
	mov	si,es:[BLK_SIZE]	; (the oldest entries come last)
fc2:	sub	si,size LBLREF
	cmp	si,es:[CBLK_REFS]	; start of this LBLREF table?
	jb	fc4			; yes
	cmp	es:[si].LBL_NUM,CTL_WHILE; CTL_WHILE or CTL_FOR?
	jb	fc2			; no
	push	si
	mov	si,es:[si].LBL_IP
	mov	ax,es:[si-2]		; AX = its position (see pushCtl)
	pop	si
	cmp	ax,cx			; at or before the line?
	ja	fc2			; no
	inc	ax
	cmp	ax,di			; and at or after the best so far?
	jb	fc2			; no
	xchg	di,ax			; yes
	mov	dx,es
	mov	bx,si			; DX:BX -> best one so far
	jmp	fc2
fc4:	call	nextBlock
	test	ax,ax
	jnz	fc1
	test	dx,dx			; did we find one?
	stc
	jz	fc9			; no
	mov	es,dx
	mov	si,bx			; DX:SI -> LBLREF
	mov	ax,es:[si].LBL_NUM
	clc
fc9:	pop	di
	pop	bx
	pop	es
	ret
ENDPROC	findCtl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; checkCtl
;
; Called by genMore when there are no more lines to generate, to make sure
; that every FOR and WHILE has a matching NEXT or WEND, and that every label
; reference (eg, GOTO 100) was resolved; an unresolved reference is still a
; placeholder (see genGoto), so we report it and end the program.  An open
; FOR or WHILE is reported with its own line # (see pushCtl).
;
; Inputs:
;	ES -> code block
;
; Outputs:
;	Carry set if there's an open FOR or WHILE, or an undefined label
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	checkCtl
	push	es
	mov	cx,0FFFFh		; (any line)
	call	findCtlAt		; DX:SI -> innermost FOR or WHILE
	jc	cct1			; there isn't one
	mov	es,dx
	mov	si,es:[si].LBL_IP	; SI = offset of the loop's body
	mov	cx,es:[si-4]		; CX = line # of the FOR or WHILE
	inc	ax			; CTL_FOR (0FFFFh)?
	mov	al,BERR_NONEXT		; "FOR without NEXT"
	je	cct0			; yes
	mov	al,BERR_NOWEND		; "WHILE without WEND"
cct0:	call	compErrLine
	jmp	short cct8
cct1:	mov	si,ss:[PSP_HEAP]
	mov	ax,ss:[si].CBLKDEF.BDEF_NEXT
	call	checkRefs		; check the code blocks
	jc	cct8
	mov	si,ss:[PSP_HEAP]
	mov	ax,ss:[si].FBLKDEF.BDEF_NEXT
	call	checkRefs		; and the function blocks
cct8:	pop	es
	ret
ENDPROC	checkCtl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; checkRefs
;
; Inputs:
;	AX = first block of a chain of code (or function) blocks
;
; Outputs:
;	Carry set if there's an unresolved label reference (and a message
;	was printed)
;
; Modifies:
;	AX, SI, ES
;
DEFPROC	checkRefs
crf1:	test	ax,ax			; any more blocks?
	jz	crf9			; no (carry clear)
	mov	es,ax
	mov	si,es:[CBLK_REFS]	; (FBLK_REFS is the same)
crf2:	cmp	si,es:[BLK_SIZE]	; end of this LBLREF table?
	jae	crf4			; yes
	mov	ax,es:[si].LBL_NUM
	test	es:[si].LBL_IP,LBL_RESOLVE
	jnz	crf8			; an unresolved reference
	add	si,size LBLREF
	jmp	crf2
crf4:	mov	ax,es:[BLK_NEXT]
	jmp	crf1
	DEFLBL	undefLine,near		; (AX = label #; see genRegion)
crf8:	PRINTF	<"Undefined line number %u",13,10>,ax
	mov	si,ss:[PSP_HEAP]
	mov	ss:[si].ERR_CODE,BERR_NOLINE ; (so genCode reports no more)
	stc
crf9:	ret
ENDPROC	checkRefs

CODE	ENDS

	end
