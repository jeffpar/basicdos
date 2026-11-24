;
; BASIC-DOS Visual Editor: Motions and Tables
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
;
; The motion functions, the command and motion tables, and the heap (so this
; module must be linked last).
;
	include	vi.inc

CODE	SEGMENT word public 'CODE'

	ASSUME	CS:CODE, DS:CODE, ES:NOTHING, SS:CODE	; ES = text segment

	EXTNEAR	<cmdAlias,cmdEx,cmdInfo,cmdIns,cmdJoin,cmdOp,cmdOpen,cmdPut>
	EXTNEAR	<cmdRedraw,cmdReplace,cmdScroll,cmdSearch,cmdTilde,cmdUndo>
	EXTNEAR	<cmdZZ,colToOff,decB,downN,findPat,firstNonBlank,getc,getKey>
	EXTNEAR	<gotoLine,incB,lineEnd,lineStart,lookup,upN>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Motions
;
; Every motion is called with AL = key, BX = offset, CX = count, and DL = 0,
; and returns BX = new offset and DL = motion flags (M_*), or carry set if
; the motion failed.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; motionAt
;
; Inputs:
;	AL = motion key, BX = offset, CX = count
;
DEFPROC	motionAt
	mov	si,offset MOTTBL
	call	lookup
	jc	mo9
	mov	dl,0
	jmp	word ptr [si-2]
mo9:	ret
ENDPROC	motionAt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; chkMoved
;
; Outputs:
;	Carry set if BX is the cursor offset (ie, the motion didn't move)
;
DEFPROC	chkMoved
	cmp	bx,[bp].V_CUR
	stc
	je	cm9
	clc
cm9:	ret
ENDPROC	chkMoved

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mLeft (h, BACKSPACE, DEL), mRight (l, SPACE)
;
DEFPROC	mLeft
	push	bx
	call	lineStart
	mov	dx,bx
	pop	bx
ml1:	cmp	bx,dx
	jbe	ml9
	dec	bx
	loop	ml1
ml9:	mov	dl,0
	jmp	chkMoved
ENDPROC	mLeft

DEFPROC	mRight
	push	bx
	call	lineEnd
	mov	dx,bx
	pop	bx
mri1:	cmp	bx,dx
	jae	ml9
	inc	bx
	loop	mri1
	jmp	ml9
ENDPROC	mRight

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mDown (j), mUp (k), mNext (+, ENTER), mPrev (-)
;
DEFPROC	mDown
	call	lineStart
	call	downN
	jmp	short vertMove
ENDPROC	mDown

DEFPROC	mUp
	call	lineStart
	call	upN
	DEFLBL	vertMove,near
	push	bx
	mov	bx,[bp].V_CUR
	call	lineStart
	pop	ax
	cmp	ax,bx			; did the line change?
	stc
	je	vm9			; no
	xchg	bx,ax
	mov	ax,[bp].V_WANT
	call	colToOff
	mov	dl,M_LINE OR M_VERT
	clc
vm9:	ret
ENDPROC	mUp

DEFPROC	mNext
	call	mDown
	jmp	short toFirst
ENDPROC	mNext

DEFPROC	mPrev
	call	mUp
	DEFLBL	toFirst,near
	jc	tf9
	call	firstNonBlank
	mov	dl,M_LINE
tf9:	ret
ENDPROC	mPrev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mHome (0), mFirst (^), mEnd ($)
;
DEFPROC	mHome
	call	lineStart
	jmp	chkMoved
ENDPROC	mHome

DEFPROC	mFirst
	call	firstNonBlank
	jmp	chkMoved
ENDPROC	mFirst

DEFPROC	mEnd
	call	lineEnd
	mov	[bp].V_WANT,7FFFh	; stay at the end of the line
	mov	dl,M_VERT
	clc
	ret
ENDPROC	mEnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mWord (w, W), mBack (b, B), mEndWord (e, E)
;
; Words are runs of letters, digits, and underscores, or runs of other
; non-blank characters; big words (W, B, and E) are runs of non-blanks.
;
DEFPROC	mWord
	call	setBig
mw1:	call	classAt
	mov	dh,ah			; DH = class of the starting character
mw2:	call	incB
	jc	mw9
	call	classAt
	cmp	ah,dh			; still the same class?
	je	mw2			; yes
mw3:	test	ah,ah			; blank?
	jnz	mw4			; no, so this starts the next word
	call	incB
	jc	mw9
	call	classAt
	jmp	mw3
mw4:	loop	mw1
mw9:	mov	dl,0
	jmp	chkMoved
ENDPROC	mWord

DEFPROC	mBack
	call	setBig
mb1:	call	decB
	jc	mb9
	call	classAt
	test	ah,ah			; blank?
	jz	mb1			; yes, keep going
	mov	dh,ah
mb2:	call	decB
	jc	mb4
	call	classAt
	cmp	ah,dh			; still the same class?
	je	mb2			; yes
	inc	bx
mb4:	loop	mb1
mb9:	mov	dl,0
	jmp	chkMoved
ENDPROC	mBack

DEFPROC	mEndWord
	call	setBig
me1:	call	incB
	jc	me9
	call	classAt
	test	ah,ah			; blank?
	jz	me1			; yes, keep going
	mov	dh,ah
me2:	call	incB
	jc	me4
	call	classAt
	cmp	ah,dh			; still the same class?
	je	me2			; yes
	dec	bx
me4:	loop	me1
me9:	mov	dl,M_INCL
	jmp	chkMoved
ENDPROC	mEndWord

DEFPROC	setBig
	and	[bp].V_FLAGS,NOT F_BIG
	cmp	al,'a'			; upper-case key?
	jae	sb9			; no
	or	[bp].V_FLAGS,F_BIG
sb9:	ret
ENDPROC	setBig

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; classAt
;
; Outputs:
;	AL = character at BX, AH = its class: 0 for blanks (including LF and
;	the end of the text), 1 for word characters, and 2 for others
;
DEFPROC	classAt
	call	getc
	mov	ah,0
	jc	ca9
	cmp	al,CHR_SPACE
	je	ca9
	cmp	al,CHR_TAB
	je	ca9
	cmp	al,CHR_LINEFEED
	je	ca9
	inc	ah
	test	[bp].V_FLAGS,F_BIG
	jnz	ca9
	cmp	al,80h
	jae	ca9
	cmp	al,'_'
	je	ca9
	cmp	al,'0'
	jb	ca8
	cmp	al,'9'
	jbe	ca9
	mov	ah,al
	and	ah,NOT 20h		; upper-case letters
	cmp	ah,'A'
	jb	ca8
	cmp	ah,'Z'
	mov	ah,1
	jbe	ca9
ca8:	mov	ah,2
ca9:	ret
ENDPROC	classAt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mGoto (G), mG (gg)
;
DEFPROC	mGoto
	cmp	[bp].V_COUNT,0		; line # specified?
	jne	gg2			; yes
	mov	bx,[bp].V_LEN		; no, so go to the last line
	dec	bx
	call	firstNonBlank
	jmp	short gg3
ENDPROC	mGoto

DEFPROC	mG
	push	cx
	call	getKey
	pop	cx
	cmp	al,'g'
	stc
	jne	gg9
	DEFLBL	gg2,near
	call	gotoLine
gg3:	mov	dl,M_LINE
	clc
gg9:	ret
ENDPROC	mG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mScreen (H, M, L)
;
DEFPROC	mScreen
	mov	bx,[bp].V_TOP
	dec	cx			; CX = count - 1
	cmp	al,'H'
	je	msc2
	push	cx
	push	ax
	mov	cl,[bp].V_TROWS
	mov	ch,0
	dec	cx
	call	downN			; BX = last line, AX = lines below
	pop	dx
	pop	cx
	cmp	dl,'L'
	je	msc1
	shr	ax,1			; middle line
	xchg	cx,ax
	mov	bx,[bp].V_TOP
	jmp	short msc2
msc1:	call	upN
	jmp	short msc3
msc2:	call	downN
msc3:	call	firstNonBlank
	mov	dl,M_LINE
	clc
	ret
ENDPROC	mScreen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mFind (f, F, t, T), mRepeat (;, ,)
;
DEFPROC	mFind
	push	cx
	push	ax
	call	getKey
	pop	dx
	pop	cx
	test	ah,ah			; non-ASCII key?
	jnz	mf8			; yes
	cmp	al,CHR_ESCAPE
	je	mf8
	mov	[bp].V_FCHR,al
	mov	[bp].V_FCMD,dl
	mov	al,dl
	jmp	short findChr
mf8:	stc
	ret
ENDPROC	mFind

DEFPROC	mRepeat
	mov	ah,al
	mov	al,[bp].V_FCMD
	test	al,al			; any previous find?
	stc
	jz	fc9			; no
	cmp	ah,','
	jne	mrp1
	xor	al,20h			; ',' reverses the direction
mrp1:
;
; findChr: AL = command (f, F, t, or T)
;
	DEFLBL	findChr,near
	mov	dh,al			; DH = command
	mov	ah,[bp].V_FCHR
	push	bx
fc1:	test	dh,20h			; forward?
	jz	fc2			; no
	inc	bx
	jmp	short fc3
fc2:	call	decB
	jc	fc8
fc3:	call	getc
	jc	fc8
	cmp	al,CHR_LINEFEED
	je	fc8
	cmp	al,ah
	jne	fc1
	loop	fc1
	pop	ax
	mov	dl,0
	cmp	dh,'t'			; 't' stops before the character
	jne	fc4
	dec	bx
fc4:	cmp	dh,'T'			; and 'T' after it
	jne	fc5
	inc	bx
fc5:	test	dh,20h			; forward?
	jz	fc6			; no
	mov	dl,M_INCL		; yes, so it's inclusive
fc6:	jmp	chkMoved
fc8:	pop	bx
	stc
fc9:	ret
ENDPROC	mRepeat

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mMatch (%)
;
; Finds the next bracket on the line, and then its matching bracket.
;
DEFPROC	mMatch
mm1:	call	getc
	jc	mm9
	cmp	al,CHR_LINEFEED
	stc
	je	mm9
	mov	si,offset BRACKETS
	mov	cx,BRACKETS_LEN
mm2:	cmp	al,[si]
	je	mm3
	inc	si
	loop	mm2
	inc	bx
	jmp	mm1
mm3:	mov	ah,al			; AH = bracket
	sub	si,offset BRACKETS
	mov	di,1			; DI = direction
	xor	si,1			; SI = index of the matching bracket
	test	si,1			; is it a closing bracket?
	jnz	mm4			; yes
	neg	di
mm4:	mov	dl,BRACKETS[si]		; DL = matching bracket
	sub	cx,cx			; CX = nesting level
mm5:	add	bx,di
	call	getc
	jc	mm9
	cmp	al,ah			; another bracket?
	jne	mm6			; no
	inc	cx
	jmp	mm5
mm6:	cmp	al,dl			; matching bracket?
	jne	mm5			; no
	jcxz	mm7
	dec	cx
	jmp	mm5
mm7:	mov	dl,M_INCL
mm9:	ret
ENDPROC	mMatch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mSearch (n, N)
;
DEFPROC	mSearch
	cmp	al,'N'
	mov	al,[bp].V_SDIR
	jne	mse1
	xor	al,1			; 'N' reverses the direction
mse1:	call	findPat
	mov	dl,0
	ret
ENDPROC	mSearch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Tables and messages
;
; The command table is followed by the motion table (and cmdLoop checks
; which one the key was found in), and the motion table ends with zero.
;
	DEFLBL	CMDTBL,byte
	db	'i'
	dw	cmdIns
	db	'a'
	dw	cmdIns
	db	'I'
	dw	cmdIns
	db	'A'
	dw	cmdIns
	db	'o'
	dw	cmdOpen
	db	'O'
	dw	cmdOpen
	db	'd'
	dw	cmdOp
	db	'c'
	dw	cmdOp
	db	'y'
	dw	cmdOp
	db	'x'
	dw	cmdAlias
	db	'X'
	dw	cmdAlias
	db	'D'
	dw	cmdAlias
	db	'C'
	dw	cmdAlias
	db	's'
	dw	cmdAlias
	db	'S'
	dw	cmdAlias
	db	'Y'
	dw	cmdAlias
	db	'p'
	dw	cmdPut
	db	'P'
	dw	cmdPut
	db	'r'
	dw	cmdReplace
	db	'~'
	dw	cmdTilde
	db	'J'
	dw	cmdJoin
	db	'u'
	dw	cmdUndo
	db	'/'
	dw	cmdSearch
	db	'?'
	dw	cmdSearch
	db	':'
	dw	cmdEx
	db	'Z'
	dw	cmdZZ
	db	CHR_CTRLG
	dw	cmdInfo
	db	CHR_CTRLL
	dw	cmdRedraw
	db	CHR_CTRLF
	dw	cmdScroll
	db	CHR_CTRLB
	dw	cmdScroll
	db	CHR_CTRLD
	dw	cmdScroll
	db	CHR_CTRLU
	dw	cmdScroll
	db	CHR_CTRLE
	dw	cmdScroll
	db	CHR_CTRLY
	dw	cmdScroll

	DEFLBL	MOTTBL,byte
	db	'h'
	dw	mLeft
	db	CHR_BACKSPACE
	dw	mLeft
	db	CHR_DEL
	dw	mLeft
	db	'l'
	dw	mRight
	db	CHR_SPACE
	dw	mRight
	db	'j'
	dw	mDown
	db	'k'
	dw	mUp
	db	'+'
	dw	mNext
	db	CHR_RETURN
	dw	mNext
	db	'-'
	dw	mPrev
	db	'0'
	dw	mHome
	db	'^'
	dw	mFirst
	db	'$'
	dw	mEnd
	db	'w'
	dw	mWord
	db	'W'
	dw	mWord
	db	'b'
	dw	mBack
	db	'B'
	dw	mBack
	db	'e'
	dw	mEndWord
	db	'E'
	dw	mEndWord
	db	'G'
	dw	mGoto
	db	'g'
	dw	mG
	db	'H'
	dw	mScreen
	db	'M'
	dw	mScreen
	db	'L'
	dw	mScreen
	db	'f'
	dw	mFind
	db	'F'
	dw	mFind
	db	't'
	dw	mFind
	db	'T'
	dw	mFind
	db	';'
	dw	mRepeat
	db	','
	dw	mRepeat
	db	'%'
	dw	mMatch
	db	'n'
	dw	mSearch
	db	'N'
	dw	mSearch
	db	0

BRACKETS	db	"()[]{}"
BRACKETS_LEN	equ	$ - BRACKETS

	COMHEAP	<size VIVARS + STACK_LEN>

CODE	ENDS

	end
