;
; BASIC-DOS Code Generator Regions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; genRegion generates a program's lines out of order, so that a program whose
; first forward jump goes far ahead (eg, a GOSUB to a subroutine at the end)
; doesn't have to wait for every line before it to be generated.
;
; A region is a run of the program's lines that has been generated in order,
; and it ends with a cap (see genMore), where generation of the region will
; resume.  The program starts with one region (region 0), whose cap is the one
; genInit generates.  When the program takes a forward jump to a line that
; hasn't been generated yet, we start a new region at that line (at the end of
; the code), and the region whose lines would have reached it stops there
; instead; when a region reaches the line where the next region starts, it
; ends with a JMP to that region's code.  When every region has reached the
; end of the program (or the next region), the code is complete (GEN_DONE).
;
; Since a region's lines end where the next region begins, every line is still
; generated exactly once.  However, lines are generated in the order the
; program reaches them, so a DEFINT (for example) affects the lines generated
; after it, which are usually the lines the program runs after it, and a NEXT
; pairs with the open FOR on the nearest line before it (see findCtl).
;
; genInit reserves the table of regions at the end of the program's first code
; block, but only if this module is loaded (see genUpper); otherwise, genMore
; generates the lines in order, as it does for a single line (eg, a command
; typed at the prompt).  If the table is full, a forward jump just generates
; the lines that lead to it, as genMore would.
;
	include	cmd.inc
	include	gen.inc
	include	8086.inc

CODE	SEGMENT

	EXTNEAR	<ensureRoom,getNextLine,genRedir,genRedirEnd,genCommands>
	EXTNEAR	<checkCtl,patchJmp,emitJmp,undefLine,genCallCS>
	EXTNEAR	<genMore,genMoreSeq,genMoreErr>

	ASSUME	CS:CODE, DS:DATA, ES:DATA, SS:DATA
;
; The table of regions (see genInit) begins with the number of open regions
; (zero until genRegion first runs), followed by REG_MAX REGIONs; a region
; whose REG_CAP segment is zero is free (or hasn't been capped yet).
;
REGION		struc
REG_CAP		dd	?		; 00h: the region's cap
REG_PTR		dd	?		; 04h: LINE_PTR of its last line
REG_LEN		dw	?		; 08h: LINE_LEN of its last line
REG_NUM		dw	?		; 0Ah: LINE_NUM of its last line
REG_STOP	dw	?		; 0Ch: LINE_NUM where it ends (or 0)
REG_NEXT	dd	?		; 0Eh: the code of the region there
REGION		ends

REG_MAX		equ	(REG_TBLSIZE - 2) / size REGION
REG_GAP		equ	2		; lines to skip without a new region

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; genRegion
;
; genMore jumps here (with the same stack), after it has made sure there's
; enough stack space, so that we can generate the lines that the placeholder
; (or cap) that called genMore needs.
;
; Inputs:
;	Return address -> byte following the placeholder
;
; Outputs:
;	DS -> first var block (if any; see genCode)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	genRegion,FAR
	mov	bx,ss:[PSP_HEAP]
	mov	ax,ss
	cmp	ss:[bx].LINE_PTR.SEG,ax	; generating a single line?
	jne	gr0			; no
	jmp	genMoreSeq		; yes, so there's only one cap
gr0:	push	bp
	mov	bp,sp
	sub	word ptr [bp+2],5	; return to the placeholder
	push	ss
	pop	ds
	mov	es,[bp+4]
	push	es:[CBLK_DATA]		; [bp-2] = placeholder's data segment
	sub	sp,4			; [bp-4] = region, [bp-6] = its stop
	call	getRegions		; ES:SI -> table of regions
	cmp	word ptr es:[si],0	; any regions yet?
	jne	gr1			; yes
;
; Region 0 is the program's first (and so far, only) region, so its cap is
; the one at the end of the code, and its last line is the current line.
;
	inc	word ptr es:[si]	; one region is open
	inc	si
	inc	si			; ES:SI -> region 0
	mov	[bp-4],si
	call	endCode			; DX:AX -> end of the code
	sub	ax,5			; DX:AX -> its cap
	call	saveRegion
;
; If the placeholder is a region's cap, generate more of that region.
;
gr1:	mov	dx,[bp-2]
	mov	cx,[bp+2]		; DX:CX -> placeholder
	call	getRegions
	inc	si
	inc	si			; ES:SI -> first region
	mov	bx,REG_MAX
gr1a:	cmp	es:[si].REG_CAP.OFF,cx
	jne	gr1b
	cmp	es:[si].REG_CAP.SEG,dx	; is it this region's cap?
	je	gr5x			; yes
gr1b:	add	si,size REGION
	dec	bx
	jnz	gr1a
;
; Otherwise, it's either a reference to a line (see genGoto) or the JMP that
; skips a FOR or WHILE loop, whose body follows the JMP, a dword, and the
; loop's line # and position (see pushCtl); either way, its block's LBLREF
; table has an entry.
;
	mov	es,dx			; ES:CX -> placeholder
	mov	ax,cx
	or	ax,LBL_RESOLVE		; AX = LBL_IP of a reference
	mov	bx,cx
	add	bx,13			; BX = LBL_IP of a loop
	mov	si,es:[CBLK_REFS]	; (FBLK_REFS is the same)
gr2:	cmp	si,es:[BLK_SIZE]	; end of the LBLREF table?
	jae	gr2x			; yes (this shouldn't happen)
	cmp	es:[si].LBL_IP,ax	; is it the reference?
	je	gr3			; yes
	cmp	es:[si].LBL_IP,bx	; is it the loop?
	jne	gr2a			; no
	cmp	es:[si].LBL_NUM,CTL_WHILE
	jb	gr2a			; no
	jmp	gr4			; yes
gr2a:	add	si,size LBLREF
	jmp	gr2
gr2x:	jmp	grErr
gr5x:	jmp	gr5
;
; For a reference, find the line, and the open region whose lines would reach
; it (ie, it's after the region's last line, and before where it stops).
;
gr3:	mov	ax,es:[si].LBL_NUM	; AX = label #
	mov	[bp-6],ax
	cmp	es:[BLK_SIG],SIG_CBLK	; in a code block (not a DEF block)?
	jne	gr3x			; no
	sub	dx,dx
	call	findText		; DS:SI -> line, DX = position
	push	ss
	pop	ds
	jc	gr3x			; no such line
	call	getRegions
	inc	si
	inc	si			; ES:SI -> first region
	mov	bx,REG_MAX
gr3a:	cmp	es:[si].REG_CAP.SEG,0	; is the region open?
	je	gr3b			; no
	cmp	dx,es:[si].REG_NUM	; is the line after its last line?
	jbe	gr3b			; no
	mov	ax,es:[si].REG_STOP
	dec	ax			; (so that no stop is 0FFFFh)
	cmp	dx,ax			; and before where it stops?
	jbe	gr3c			; yes
gr3b:	add	si,size REGION
	dec	bx
	jnz	gr3a
gr3x:	mov	ax,[bp-6]
	call	undefLine		; "Undefined line number"
	jmp	grErr
;
; If the line is only a line or two beyond the region's last line, or there's
; no room for another region, just generate more of the region.
;
gr3c:	mov	ax,dx
	sub	ax,es:[si].REG_NUM	; AX = lines beyond its last line
	cmp	ax,REG_GAP
	jbe	gr5x
	push	si
	call	getRegions
	lea	di,[si+2]		; ES:DI -> first region
	pop	si
	mov	cx,REG_MAX
gr3d:	cmp	es:[di].REG_CAP.SEG,0	; is this region free?
	je	gr3e			; yes
	add	di,size REGION
	loop	gr3d
	jmp	gr5			; no free region
;
; Start a new region (ES:DI) at the line, or at any blank lines just before it
; (since getNextLine skips blank lines, a region must never stop at one), and
; stop the old region (ES:SI) where the new one starts.
;
gr3e:	mov	cx,dx			; CX = first line of the new region
gr3f:	mov	dx,cx
	dec	dx			; DX = the line before it
	cmp	dx,es:[si].REG_NUM	; is it the old region's last line?
	jbe	gr3g			; yes
	push	si
	sub	ax,ax
	call	findText		; DS:SI -> the line before
	cmp	byte ptr [si+2],0	; is it blank?
	pop	si
	jne	gr3g			; no
	loop	gr3f
gr3g:	push	si
	mov	dx,cx
	sub	ax,ax
	call	findText		; DS:SI -> first line of the new region
	mov	ax,si
	mov	bx,ds
	pop	si
	push	ss
	pop	ds
	mov	es:[di].REG_PTR.OFF,ax
	mov	es:[di].REG_PTR.SEG,bx
	mov	es:[di].REG_LEN,0	; (so getNextLine starts at that line)
	mov	ax,cx
	dec	ax
	mov	es:[di].REG_NUM,ax
	mov	ax,es:[si].REG_STOP
	mov	es:[di].REG_STOP,ax	; the new region ends where the old
	mov	es:[si].REG_STOP,cx	; one did, and the old one ends here
	mov	ax,es:[si].REG_NEXT.OFF
	mov	es:[di].REG_NEXT.OFF,ax
	mov	ax,es:[si].REG_NEXT.SEG
	mov	es:[di].REG_NEXT.SEG,ax
	call	endCode			; DX:AX -> end of the code, where the
	mov	es:[si].REG_NEXT.OFF,ax	; new region's code will start
	mov	es:[si].REG_NEXT.SEG,dx
	call	getRegions
	inc	word ptr es:[si]	; one more region is open
	mov	si,di
	jmp	short gr5
;
; For a loop, the open region with the nearest last line at or after the
; loop's line is the one that generates its NEXT or WEND.
;
gr4:	mov	si,cx
	mov	dx,es:[si+11]		; DX = position of the loop's line
	call	getRegions
	inc	si
	inc	si			; ES:SI -> first region
	sub	di,di			; DI = nearest region (none yet)
	mov	cx,0FFFFh		; CX = its last line
	mov	bx,REG_MAX
gr4a:	cmp	es:[si].REG_CAP.SEG,0	; is the region open?
	je	gr4b			; no
	mov	ax,es:[si].REG_NUM
	cmp	ax,dx			; is its last line the loop or after?
	jb	gr4b			; no
	cmp	ax,cx			; and the nearest so far?
	jae	gr4b			; no
	xchg	cx,ax
	mov	di,si
gr4b:	add	si,size REGION
	dec	bx
	jnz	gr4a
	mov	si,di
	test	si,si			; did we find one?
	jnz	gr5			; yes
	mov	es,[bp-2]
	call	checkCtl		; no, so it's "FOR without NEXT" (etc)
	jmp	grErr
;
; Generate more of the region at ES:SI, starting at its cap (if it's at the
; end of the code), or at the end of the code (with a JMP there from its cap,
; if it has one).
;
gr5:	mov	[bp-4],si
	mov	ax,es:[si].REG_STOP
	mov	[bp-6],ax
	mov	bx,ds:[PSP_HEAP]
	mov	ax,es:[si].REG_PTR.OFF
	mov	[bx].LINE_PTR.OFF,ax
	mov	ax,es:[si].REG_PTR.SEG
	mov	[bx].LINE_PTR.SEG,ax
	mov	ax,es:[si].REG_LEN
	mov	[bx].LINE_LEN,ax
	mov	ax,es:[si].REG_NUM
	mov	[bx].LINE_NUM,ax
	les	di,es:[si].REG_CAP	; ES:DI -> its cap, if any
	call	endCode			; DX:AX -> end of the code
	mov	cx,es
	jcxz	gr6			; no cap yet (it's a new region)
	lea	si,[di+5]
	cmp	si,ax			; is the cap at the end of the code?
	jne	gr5a			; no
	cmp	cx,dx
	je	gr7			; yes, so generate from the cap
gr5a:	mov	si,di			; ES:SI -> cap
	push	ax
	call	patchJmp		; JMP from the cap to the end
	pop	ax
gr6:	mov	es,dx
	mov	di,ax			; ES:DI -> end of the code

gr7:	mov	ax,CODE_ROOM
	call	ensureRoom		; make sure there's room for a line
	jc	grErr
	mov	si,ds:[PSP_HEAP]
	mov	ax,[si].LINE_NUM
	inc	ax
	cmp	ax,[bp-6]		; is the next line where it ends?
	je	grJmp			; yes
	call	getNextLine
	jc	grEnd			; no more lines
	call	genRedir		; any ":>" redirection?
	jc	grErr			; yes, but it's invalid
	push	ax
	push	dx
	push	cx
	call	genCommands		; generate code
	pop	cx
	pop	dx
	pop	ax
	jc	grErr
	test	ax,ax			; was the line redirected?
	jz	gr8			; no
	mov	si,ds:[PSP_HEAP]
	mov	[si].LINE_LEN,ax	; restore the line's length
	call	genRedirEnd		; and end the redirection
	jc	grErr
gr8:	call	chkPlace		; is the placeholder still there?
	je	gr7			; yes, so generate another line
	mov	dx,es
	mov	ax,di			; DX:AX -> the region's new cap
	call	saveRegion
	GENCALL	genMore			; cap the region again
gr9:	mov	es:[BLK_FREE],di
	mov	bx,ds:[PSP_HEAP]
	mov	ds,[bx].VBLKDEF.BDEF_NEXT
	ASSUME	DS:NOTHING
	mov	sp,bp
	pop	bp
	ret
	ASSUME	DS:DATA

grErr:	push	ss
	pop	ds
	jmp	genMoreErr		; (which resets SP)
;
; The region has reached the next region, so jump to that region's code.
;
grJmp:	push	es
	push	di
	call	getRegions
	mov	si,[bp-4]
	mov	ax,es:[si].REG_NEXT.OFF
	mov	dx,es:[si].REG_NEXT.SEG
	pop	di
	pop	es
	call	emitJmp
	call	closeRegion
	jmp	short gr8a
;
; The region has reached the end of the program, so terminate it, and if it
; was the last open region, the code is complete (unless a FOR has no NEXT,
; etc).
;
grEnd:	push	ss
	pop	ds
	mov	al,OP_RETF		; terminate the code
	stosb
	call	closeRegion		; was that the last open region?
	jnz	gr8a			; no
	call	checkCtl		; any FOR without NEXT (etc)?
	jc	grErr			; yes
	mov	bx,ds:[PSP_HEAP]
	or	[bx].GEN_FLAGS,GEN_DONE
;
; Either way, the region is done, so if the placeholder that called us is
; still there, find the region that will replace it.
;
gr8a:	mov	es:[BLK_FREE],di
	call	chkPlace		; is the placeholder still there?
	je	gr8b			; yes
	jmp	gr9
gr8b:	jmp	gr1
ENDPROC	genRegion

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkPlace
;
; Inputs:
;	[bp+2] -> placeholder (see genRegion)
;
; Outputs:
;	ZF set if the placeholder is still a far CALL to genMore
;
; Modifies:
;	SI
;
DEFPROC	chkPlace
	lds	si,dword ptr [bp+2]	; DS:SI -> placeholder
	ASSUME	DS:NOTHING
	cmp	byte ptr [si],OP_CALLF	; still a call to genMore?
	jne	cp9			; no
	cmp	word ptr [si+1],offset genMore
cp9:	push	ss
	pop	ds
	ASSUME	DS:DATA
	ret
ENDPROC	chkPlace

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; closeRegion
;
; Inputs:
;	[bp-4] = region (see genRegion)
;
; Outputs:
;	ZF set if no regions are open now
;
; Modifies:
;	None
;
DEFPROC	closeRegion
	push	es
	push	si
	call	getRegions
	push	si
	mov	si,[bp-4]
	mov	es:[si].REG_CAP.SEG,0	; the region is free
	pop	si
	dec	word ptr es:[si]	; and one less region is open
	pop	si
	pop	es
	ret
ENDPROC	closeRegion

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; endCode
;
; Inputs:
;	None
;
; Outputs:
;	DX:AX -> end of the code (BLK_FREE of the last code block)
;
; Modifies:
;	AX, DX
;
DEFPROC	endCode
	push	es
	push	si
	mov	si,ss:[PSP_HEAP]
	mov	ax,ss:[si].CBLKDEF.BDEF_NEXT
ec1:	mov	es,ax
	mov	ax,es:[BLK_NEXT]
	test	ax,ax			; is there another code block?
	jnz	ec1			; yes
	mov	dx,es
	mov	ax,es:[BLK_FREE]
	pop	si
	pop	es
	ret
ENDPROC	endCode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; findText
;
; Finds a line of the program's text, either by its label # or by its position
; (counting every line, as LINE_NUM does; see getNextLine), whichever comes
; first.
;
; Inputs:
;	AX = label # (0 if none)
;	DX = position (0 if none)
;
; Outputs:
;	If carry clear, DS:SI -> line, AX = its label #, DX = its position
;
; Modifies:
;	AX, DX, SI, DS
;
DEFPROC	findText
	ASSUME	DS:NOTHING
	push	bx
	push	cx
	xchg	bx,ax			; BX = label # to find
	sub	cx,cx			; CX = position of the line
	mov	si,ss:[PSP_HEAP]
	mov	ax,ss:[si].TBLKDEF.BDEF_NEXT
ft1:	test	ax,ax			; another text block?
	stc
	jz	ft9			; no
	mov	ds,ax
	mov	si,size TBLK		; DS:SI -> its first line
ft2:	cmp	si,ds:[BLK_FREE]	; end of this text block?
	jb	ft3			; no
	mov	ax,ds:[BLK_NEXT]
	jmp	ft1
ft3:	inc	cx
	mov	ax,[si]			; AX = the line's label #
	cmp	cx,dx			; is it at the position?
	je	ft8			; yes
	test	bx,bx			; looking for a label #?
	jz	ft4			; no
	cmp	ax,bx			; is it the label #?
	je	ft8			; yes
ft4:	mov	al,[si+2]
	mov	ah,0
	add	si,ax
	add	si,3			; DS:SI -> the next line
	jmp	ft2
ft8:	mov	dx,cx			; DX = position (and carry is clear)
ft9:	pop	cx
	pop	bx
	ret
	ASSUME	DS:DATA
ENDPROC	findText

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getRegions
;
; Inputs:
;	None
;
; Outputs:
;	ES:SI -> table of regions (see genInit)
;
; Modifies:
;	SI, ES
;
DEFPROC	getRegions
	mov	si,ss:[PSP_HEAP]
	mov	es,ss:[si].CBLKDEF.BDEF_NEXT
	mov	si,es:[BLK_SIZE]
	add	si,LBL_MAPLEN * 2	; (after addLabel's maps)
	ret
ENDPROC	getRegions

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; saveRegion
;
; Saves the region's cap and the current line (LINE_PTR, LINE_LEN, and
; LINE_NUM), where its generation will resume.
;
; Inputs:
;	DX:AX -> cap
;	[bp-4] = region (see genRegion)
;
; Outputs:
;	None
;
; Modifies:
;	AX
;
DEFPROC	saveRegion
	push	es
	push	bx
	push	si
	call	getRegions
	mov	si,[bp-4]
	mov	es:[si].REG_CAP.OFF,ax
	mov	es:[si].REG_CAP.SEG,dx
	mov	bx,ss:[PSP_HEAP]
	mov	ax,ss:[bx].LINE_PTR.OFF
	mov	es:[si].REG_PTR.OFF,ax
	mov	ax,ss:[bx].LINE_PTR.SEG
	mov	es:[si].REG_PTR.SEG,ax
	mov	ax,ss:[bx].LINE_LEN
	mov	es:[si].REG_LEN,ax
	mov	ax,ss:[bx].LINE_NUM
	mov	es:[si].REG_NUM,ax
	pop	si
	pop	bx
	pop	es
	ret
ENDPROC	saveRegion

CODE	ENDS

	end
