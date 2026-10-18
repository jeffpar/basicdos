;
; BASIC-DOS DATE and TIME Commands
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	dosfunc.inc

CODE    SEGMENT

	EXTNEAR	<getToken,printCRLF>

        ASSUME  CS:CODE, DS:DATA, ES:DATA, SS:DATA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdDate
;
; Set a new system date (eg, "MM-DD-YY", "MM/DD/YYYY").  Omitted portions
; of the date string default to the current date's values.  This intentionally
; differs from cmdTime, where omitted portions always default to zero.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdDate
	mov	ax,offset promptDate
	call	getInput		; DS:SI -> string
	jc	dt8			; do nothing on empty string
	mov	ah,'-'
	call	getValues
	xchg	dx,cx			; DH = month, DL = day, CX = year
	cmp	cx,100
	jae	dt1
	add	cx,1900			; 2-digit years are automatically
	cmp	cx,1980			; adjusted to 4-digit years 1980-2079
	jae	dt1
	add	cx,100
dt1:	mov	ah,DOS_MSC_SETDATE
	int	21h			; set the date
	test	al,al			; success?
	jnz	dt2			; no
	stc				; (and ZF is set)
	call	promptDate		; display the new date
	jmp	short dt8
dt2:	PRINTF	<"Invalid date",13,10>
	cmp	[di].TOK_CNT,0		; did we process a command-line token?
	stc
	je	dt9			; yes (so report an error)
	jmp	cmdDate
dt8:	clc
	ret

	DEFLBL	promptDate,near
	DOSUTIL	GETDATE			; GETDATE returns packed date
	xchg	dx,cx
	jnc	dt9			; if caller's carry clear, skip output
	pushf
	PRINTF	<"Current date is %.3W %M-%02D-%Y",13,10>,ax,ax,ax,ax
	popf				; do we need a prompt?
	jz	dt9			; no
	PRINTF	<"Enter new date: ">
	test	ax,ax			; clear CF and ZF
dt9:	ret
ENDPROC	cmdDate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; cmdTime
;
; Set a new system time (eg, "HH:MM:SS.DD")  Any portion of the time string
; that's omitted defaults to zero.  TIME /P prompts for a new time, and TIME /D
; displays the difference between the current time and the previous time.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;
; Outputs:
;	None
;
; Modifies:
;	Any
;
DEFPROC	cmdTime
	TESTSW	<'D'>			; /D present?
	jz	tm3			; no

	sub	ax,ax			; set ZF
	DOSUTIL	GETTIME
	push	cx			; CX:DX = current time
	push	dx
	call	printTime
	pop	dx
	pop	cx

	push	cx
	push	dx
	push	bx
	sub	dl,[bx].PREV_TIME.LOW.LOB
	jnb	tm1a
	add	dl,100			; adjust hundredths
	stc
tm1a:	sbb	dh,[bx].PREV_TIME.LOW.HIB
	jnb	tm1b
	add	dh,60			; adjust seconds
	stc
tm1b:	sbb	cl,[bx].PREV_TIME.HIW.LOB
	jnb	tm1c
	add	cl,60			; adjust minutes
	stc
tm1c:	sbb	ch,[bx].PREV_TIME.HIW.HIB
	jnb	tm1d
	add	ch,24			; adjust hours
tm1d:	mov	al,ch			; AL = hours
	mov	bl,cl			; BL = minutes
	mov	cl,dh			; CL = seconds, DL = hundredths
	PRINTF	<"Elapsed time is %2bu:%02bu:%02bu.%02bu",13,10>,ax,bx,cx,dx
	pop	bx
	pop	[bx].PREV_TIME.LOW
	pop	[bx].PREV_TIME.HIW
	jmp	short tm7

tm3:	mov	ax,offset promptTime
	call	getInput		; DS:SI -> string
	jc	tm7			; do nothing on empty string
	mov	ah,':'
	call	getValues
	mov	ah,DOS_MSC_SETTIME
	int	21h			; set the time
	test	al,al			; success?
	jnz	tm4			; no
	stc				; (and ZF is set)
	call	promptTime		; display the new time
	jmp	short tm7
tm4:	PRINTF	<"Invalid time",13,10>
	cmp	[di].TOK_CNT,0		; did we process a command-line token?
	stc
	je	tm9			; yes (so report an error)
	jmp	cmdTime
tm7:	clc
	ret

	DEFLBL	promptTime,near
	jnc	tm8
	DOSUTIL	GETTIME			; GETTIME returns packed time
	mov	[bx].PREV_TIME.LOW,dx
	mov	[bx].PREV_TIME.HIW,cx

	DEFLBL	printTime,near
	mov	cl,dh			; CL = seconds, DL = hundredths
	pushf
	PRINTF	<"Current time is %2H:%02N:%02bu.%02bu",13,10>,ax,ax,cx,dx
	popf
	jz	tm8
	PRINTF	<"Enter new time: ">
	test	ax,ax			; clear CF and ZF
tm8:	mov	cx,0			; instead of retaining current values
	mov	dx,cx			; set all defaults to zero
tm9:	ret
ENDPROC	cmdTime

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getInput
;
; Use by cmdDate and cmdTime to set DS:SI to an input string.
;
; Inputs:
;	BX -> CMDHEAP
;	DI -> TOKENBUF
;	AX = prompt function
;
; Outputs:
;	CX, DX = default values from caller-supplied function
;	DS:SI -> CR-terminated string
;	Carry clear if input exists, carry set if no input provided
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	getInput
	mov	dl,[bx].CMD_ARG
	call	getToken
	jnc	gi1
;
; No input was provided, and we don't prompt unless /P was specified.
;
	push	ax
	TESTSW	<'P'>
	pop	ax
	stc
;
; The prompt function performs three important steps:
;
;   1)	Load current values in CX, DX
;   2)	If CF is set, print current values
;   3)	If ZF is clear, prompt for new values and clear CF
;
gi1:	call	ax			; AX = caller-supplied function
	jbe	gi9			; if CF or ZF set, we're done
;
; Request new values.
;
	push	dx
	lea	si,[bx].LINEBUF
	mov	word ptr [si].INP_MAX,12; max of 12 chars (including CR)
	mov	dx,si
	mov	ah,DOS_TTY_INPUT
	int	21h
	call	printCRLF
	pop	dx
	inc	si
	cmp	byte ptr [si],1		; set carry if no characters
	inc	si			; skip ahead to characters, if any
	ret

gi9:	mov	[di].TOK_CNT,0		; zero count to prevent reprocessing
	ret
ENDPROC	getInput

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getValues
;
; Used by cmdDate and cmdTime to get a series of delimited values.
;
; Inputs:
;	AH = default delimiter
;	SI -> DS-relative string data (CR-terminated)
;
; Outputs:
;	CH, CL, DH, DL
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	getValues
	push	bx
	xchg	bx,ax			; BH = default delimiter
	call	getValue
	jc	gvs2
	mov	ch,al			; CH = 1st value (eg, month)

gvs2:	call	getValue
	jc	gvs3
	mov	cl,al			; CL = 2nd value (eg, day)

gvs3:	cmp	bh,':'
	jne	gvs4
	mov	bh,'.'

gvs4:	call	getValue
	jc	gvs5
	mov	dx,ax			; DX = 3rd value (eg, year)

gvs5:	cmp	bh,'-'			; are we dealing with a date?
	je	gvs9			; yes

	mov	dh,al			; DH = 3rd value (eg, seconds)
	push	dx
	push	di
	mov	bl,10			; BL = base 10
	lea	dx,[si+2]
	mov	di,-1			; DI = -1 (no validation data)
	DOSUTIL	ATOI16			; DS:SI -> string
	jc	gvs8
	sub	dx,si			; too many digits?
	jc	gvs6			; yes
	je	gvs7			; no, exactly 2 digits
	mov	dl,10			; one digit must be multiplied by 10
	mul	dl
	jmp	short gvs7
gvs6:	mov	al,-1
gvs7:	clc
gvs8:	pop	di
	pop	dx
	jc	gvs9
	mov	dl,al			; DL = 4th value (eg, hundredths)

gvs9:	pop	bx
	ret
ENDPROC	getValues

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; getValue
;
; Used by getValues to get a single delimited value.
;
; No data validation is performed here, since the DOS_MSC_SETDATE and
; DOS_MSC_SETTIME functions are required to validate their inputs.
;
; If delimiter validation fails, an out-of-bounds value (-1) is returned.
;
; Inputs:
;	BH = default delimiter
;	SI -> DS-relative string data (CR-terminated)
;
; Outputs:
;	If carry clear, AX = value (-1 if invalid delimiter)
;	If carry set, no data
;
; Modifies:
;	AX, BL, SI
;
DEFPROC	getValue
	push	di
	mov	bl,10			; BL = base 10
	mov	di,-1			; DI = -1 (no validation data)
	DOSUTIL	ATOI16			; DS:SI -> string
	sbb	di,di			; DI = -1 if no data
	mov	bl,[si]			; BL = termination character
	cmp	bl,CHR_RETURN		; CR (or null terminator)?
	jbe	gv9			; presumably
	inc	si
	cmp	bl,bh			; expected termination character?
	je	gv9			; yes
	cmp	bh,'-'			; was dash specified?
	jne	gv8			; no
	cmp	bl,'/'			; yes, so allow slash as well
	je	gv9			; no, not slash either
gv8:	or	ax,-1			; return invalid value
	sub	di,di			; and ensure carry will be clear
gv9:	add	di,1			; otherwise, set carry if no data
	pop	di
	ret
ENDPROC	getValue

CODE	ENDS

	end
