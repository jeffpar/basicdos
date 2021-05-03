;
; BASIC-DOS Math Library
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	8086.inc
	include	devapi.inc
	include	dos.inc
	include	dosapi.inc

DOS	segment word public 'CODE'

	EXTWORD	<scb_active>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; atoi
;
; Convert string at DS:SI to number in AX using base BL, using validation
; values at ES:DI.  It will also advance SI past the first non-digit character
; to facilitate parsing of a series of delimited, validated numbers.
;
; For validation, ES:DI must point to a triplet of (def,min,max) 16-bit values
; and like SI, DI will be advanced, making it easy to parse a series of values,
; each with their own set of (def,min,max) values.
;
; For no validation (and to leave SI pointing to the first non-digit), set
; DI to -1.
;
; Returns:
;	AX = value, DS:SI -> next character (ie, AFTER first non-digit)
;	Carry set on a validation error (AX will be set to the default value)
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	atoi,DOS
	mov	cx,-1
	DEFLBL	atoi_len,near		; CX = length
	mov	bl,[bp].REG_BL
	DEFLBL	atoi_base,near		; BL = base (eg, 10)
	mov	bh,0
	mov	[bp].TMP_BX,bx		; TMP_BX equals 16-bit base
	mov	[bp].TMP_AL,bh		; TMP_AL is sign (0 for +, -1 for -)
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY

	mov	ah,-1			; cleared when digit found
	sub	bx,bx			; DX:BX = value
	sub	dx,dx			; (will be returned in DX:AX)

ai0:	jcxz	ai6
	lodsb				; skip any leading whitespace
	dec	cx
	cmp	al,CHR_SPACE
	je	ai0
	cmp	al,CHR_TAB
	je	ai0

	cmp	al,'-'			; minus sign?
	jne	ai1			; no
	cmp	byte ptr [bp].TMP_AL,0	; already negated?
	jl	ai6			; yes, not good
	dec	byte ptr [bp].TMP_AL	; make a note to negate later
	jmp	short ai4

ai1:	cmp	al,'a'			; remap lower-case
	jb	ai2			; to upper-case
	sub	al,20h
ai2:	cmp	al,'A'			; remap hex digits
	jb	ai3			; to characters above '9'
	cmp	al,'F'
	ja	ai6			; never a valid digit
	sub	al,'A'-'0'-10
ai3:	cmp	al,'0'			; convert ASCII digit to value
	jb	ai6
	sub	al,'0'
	cmp	al,[bp].TMP_BL		; outside the requested base?
	jae	ai6			; yes
	cbw				; clear AH (digit found)
;
; Multiply DX:BX by the base in TMP_BX before adding the digit value in AX.
;
	push	ax
	xchg	ax,bx
	mov	[bp].TMP_DX,dx
	mul	word ptr [bp].TMP_BX	; DX:AX = orig BX * BASE
	xchg	bx,ax			; DX:BX
	xchg	[bp].TMP_DX,dx
	xchg	ax,dx
	mul	word ptr [bp].TMP_BX	; DX:AX = orig DX * BASE
	add	ax,[bp].TMP_DX
	adc	dx,0			; DX:AX:BX = new result
	xchg	dx,ax			; AX:DX:BX = new result
	test	ax,ax
	jz	ai3a
	int	04h			; signal overflow
ai3a:	pop	ax			; DX:BX = DX:BX * TMP_BX

	add	bx,ax			; add the digit value in AX now
	adc	dx,0
	jno	ai4
;
; This COULD be an overflow situation UNLESS DX:BX is now 80000000h AND
; the result is going to be negated.  Unfortunately, any negation may happen
; later, so it's insufficient to test the sign in TMP_AL; we'll just have to
; allow it.
;
	test	bx,bx
	jz	ai4
	int	04h			; signal overflow

ai4:	jcxz	ai6
	lodsb				; fetch the next character
	dec	cx
	jmp	ai1			; and continue the evaluation

ai6:	cmp	byte ptr [bp].TMP_AL,0
	jge	ai6a
	neg	dx
	neg	bx
	sbb	dx,0
	into				; signal overflow if set

ai6a:	cmp	di,-1			; validation data provided?
	jg	ai6c			; yes
	je	ai6b			; -1 for 16-bit result only
	mov	[bp].REG_DX,dx		; -2 for 32-bit result (update REG_DX)
ai6b:	dec	si			; rewind SI to first non-digit
	add	ah,1			; (carry clear if one or more digits)
	jmp	short ai9

ai6c:	test	ah,ah			; any digits?
	jz	ai6d			; yes
	mov	bx,es:[di]		; no, get the default value
	stc
	jmp	short ai8
ai6d:	cmp	bx,es:[di+2]		; too small?
	jae	ai7			; no
	mov	bx,es:[di+2]		; yes (carry set)
	jmp	short ai8
ai7:	cmp	es:[di+4],bx		; too large?
	jae	ai8			; no
	mov	bx,es:[di+4]		; yes (carry set)
ai8:	lea	di,[di+6]		; advance DI in case there are more
	mov	[bp].REG_DI,di		; update REG_DI

ai9:	mov	[bp].REG_AX,bx		; update REG_AX
	mov	[bp].REG_SI,si		; update caller's SI, too
	ret
ENDPROC atoi

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; atof64
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; Inputs:
;	REG_ES:REG_SI -> string
;
; Outputs:
;	REG_ES:REG_DI -> result (in FAC)
;
; Modifies:
;
DEFPROC	atof64,DOS
;
; The following code was adapted from $FINDB in MATH1.ASM.  The roles
; of BX and SI have been reversed: SI -> string, and BX is used as a flag.
;
	XOR	DI,DI			;DIGITS PAST DECIMAL POINT
	MOV	CX,DI			;DECIMAL POINT FLAG
	MOV	BX,DI			;(BX) WILL FLAG POS/NEG EXPONENT
	NOT	CX			;SET ALL BITS
	CALL	$DZERO			;(FAC)=0
FN30:	CALL	$CHRGT			;FETCH 1ST CHARACTER FROM TEXT
	CMP	AL,'-'  	    	;NEGATIVE NUMBER?
	PUSHF				;WILL SAVE ZF FOR POSSIBLE NEGATION
	CMP	AL,'+'			;NEED TO ADVANCE TEXT POINTER FOR
	JZ	FN50			;LEADING SIGN
	DEC	SI			;
FN50:	CALL	$CHRGT			;GET NEXT CHARACTER OF NUMBER
	JNB	FN60			;IF NOT DIGIT GO EXAMINE FURTHER
FN55:	CALL	$FIDIG			;MUL FAC BY TEN AND ADD IN THE DIGIT
	JMP	SHORT FN50
;
; Check for the following special chars: '.', 'D', 'd', 'E', 'e', '!', '#'.
;
; The values are 2Eh, 44h, 64h, 45h, 65h, 21h, and 23h, so after we eliminate
; all values below 20h, we can add 20h and avoid checks for 44h and 45h.
;
; We use inline checks because a character table ($FINCH) and jump table (FN95)
; don't actually save much.
;
FN60:	CMP	AL,20H
	JB	FN96			;GO FINISH UP NUMBER [UNRECOGNIZED]
	OR	AL,20H
	CMP	AL,'.'
	JE	FN100
	CMP	AL,'#'
	JE	FN96
	CMP	AL,'!'			;WE TREAT '!' JUST LIKE '#'
	JE	FN96
	CMP	AL,'D'
	JE	FN92
	CMP	AL,'E'			;WE TREAT 'E' JUST LIKE 'D'
	JNE	FN96			;GO FINISH UP NUMBER [UNRECOGNIZED]

FN92:	XOR	AL,AL			;SET CONDITION CODES CORRECTLY
FN94:	CALL	$FINEX			;CALCULATE EXPONENT
FN96:	CALL	$FINE			;MODIFY NUMBER TO REFLECT EXPONENT
	JMP	SHORT FINF		;CLEAN UP, NEGATE AS NECESSARY

FN100:	INC	CX			;TO DENOTE DECIMAL PT. DETECTED
	JNZ	FN96			;GO FINISH UP NO.-2ED DECIMAL PT. SEEN!
	JMP	FN50			;GO PROCESS NEXT CHAR.

;FN500:	CALL	$FIND			;IT WAS A "#" (DOUBLE PRECISION)

FINF:	POPF				;RECALL SIGN FLAG
	JNZ	FN990			;RETURN IF NOT NEGATIVE NO.
	CALL	$NEG			;NEGATE NUMBER

FN990:	RET
ENDPROC atof64

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $CHRGT (CHRGET)
;
; Adapted from GWMAIN.ASM, copyright (c) Microsoft Corporation.
;
; SI is used as the index of the next character (originally, BX was used as
; the index of the previous character, which required pre-incrementing and
; and prevented the use of LODS); unnecessary character classification checks
; have been removed, and digit classification has been simplified.
;
; Inputs:
;	REG_ES:SI -> next character
;
; Outputs:
;	Carry set if digit, clear otherwise
;
; Modifies:
;	AL, SI, flags
;
DEFPROC	$CHRGT,DOS
	PUSH	ES
	MOV	ES,[BP].REG_ES
	ASSUME	ES:NOTHING
	LODS	BYTE PTR ES:[SI]
	CMP	AL,'0'
	CMC
	JNC	CG9			; JUMP IF < '0'
	CMP	AL,'9'+1		; CARRY SET IF < '9'
CG9:	POP	ES
	RET
ENDPROC	$CHRGT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $DZERO
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; DOUBLE PRECISION ZERO
;
; Inputs:
;	DI -> SCB_FAC
;
; Modifies:
;	AX
;
DEFPROC	$DZERO,DOS
	PUSH	DI
	LEA	DI,[DI].$DFACL
	XOR	AX,AX
	; CLD
	STOSW
	STOSW
	STOSW
	STOSW
	POP	DI
	RET
ENDPROC	$DZERO

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $FIDIG
;
; Adapted from MATH2.ASM, copyright (c) Microsoft Corporation.
;
; CONVERTS DIGIT (AL) TO BINARY VALUE AND ADDS TO NUMBER ACCUMULATED.
;
; AS $FIDIG IS ENTERED CF=1 AND (DI) WILL HOLD PLACES TO THE RIGHT OF
; DECIMAL POINT (IF DECIMAL POINT HAS OCCURRED).  (CX) WILL BE EITHER
; ALL BITS SET OR ALL BITS CLEARED.  ALL BITS SET INDICATES A DECIMAL
; POINT HAS NOT BEEN SEEN YET AND (CX)=0 INDICATES DEC. PT. SEEN.
;
DEFPROC	$FIDIG,DOS
	ADC	DI,CX			;(DI) INCREMENTED ONLY IF DEC. PT. SEEN
	PUSH	BX			;MUST NOW SAVE ALL NECESSARY REGS.
	PUSH	CX			;
	PUSH	DI			;
	MOV	DI,[SCB_ACTIVE]		;
	LEA	DI,[DI].SCB_FAC		;
	SUB	AL,'0'		      	;SUBTRACT OUT ASCII BIAS
	PUSH	AX			;SAVE THE NUMBER
	CALL	$MUL10			;MULTIPLY BY 10
	CALL	$MOVAF			;MOVE $FAC TO $ARG
	POP	AX			;RECALL DIGIT
	CWD				;DX:AX = VALUE OF DIGIT
	CALL	$FLTD			;CONVERT TO DOUBLE PRECISION
	CALL	$FADDD			;ADD IN THE OLD ACCUMULATED VALUE
	POP	DI			;GET NO. DIGITS TO RIGHT OF DECIMAL PT.
	POP	CX			;GET DECIMAL PT. FLAG BACK
	POP	BX			;
	RET				;COMPLETE
ENDPROC	$FIDIG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $FINE
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; THIS ROUTINE MODIFIES THE CURRENT FAC WHICH HAS THE INPUT SIGNIFICANT
; DIGITS SO THAT THE EXPONENT IS REFLECTED IN THE NUMBER. FOR EXAMPLE, IF THE
; NUMBER INPUT IS 1.9876E-17 THEN THE FAC CURRENTLY HAS THE NUMBER 19876.
; IT MUST BE MULTIPLIED BY 10^-21 TO CORRECTLY REFLECT THE INPUT NUMBER.
; IT IS THE JOB OF THIS ROUTINE TO DETERMINE THE CORRECT MULTIPLIER AND PERFORM
; THE MULTIPLICATION.
;
; CALL $FINE WITH (SI) CONTAINING 0 IF POSITIVE EXPONENT, ALL BITS SET IF
; NEGATIVE EXPONENT. (DX) CONTAINS THE INPUT EXPONENT (FOR THE EXAMPLE ABOVE
; =17) AND (DI) CONTAINS THE NUMBER PLACES TO THE RIGHT OF THE DECIMAL POINT.
;
DEFPROC	$FINE,DOS
	OR	SI,SI			;SEE IF DX SHOULD BE NEGATED
	JNS	FIN05			;IF NOT PROCEED
	NEG	DX			;NEGATE
FIN05:	SUB	DX,DI			;SUBTRACT OUT DIGITS TO RIGHT OF DP.
	JO	FIN80			;UNDERFLOW IF OVERFLOW FLAG SET
	JZ	FIN55			;NUMBER COMPLETE AS IS
;
; HERE WE HAVE THE EXPONENT IN DX. WE HAVE MULTIPLIERS RANGING
; FROM (10^-38,10^38) TO USE IN DETERMINING THE CORRECT FAC. WE
; MAY NEED TO DO SEVERAL MULTIPLIES TO CORRECTLY FORM THE NUMBER.
; FOR EXAMPLE IF THE NUMBER INPUT WAS 1234567.E-40 DX WOULD
; HAVE -40. IF THIS WERE THE CASE WE NEED TO DO A MULTIPLY BY 10^-38
; THEN A MULTIPLY BY 10^-2 TO GET THE RIGHT NUMBER.
;
; All calculations are done in double precision and then converted
; back to the original type.  Integers are converted to single precision.
;
MDPTEN:
	PUSH	BX			; Preserve text pointer
	; CALL	$GETYP			; Get the current type,
	; PUSHF				; And save, so that we can convert back
	; JNB	FIN20			; If already D.P., no conversion necessary
	; CALL	FRCDBL			; Force result to be double precision
FIN20:	OR	DX,DX			; Test sign of exponent
	JS	FIN30			;IF NEGATIVE EXPONENT JUMP
;
; POSITIVE EXPONENT . IF GREATER THAN D^38 THEN WE HAVE OVERFLOW
; Unless the number is zero, in which case just return zero.
;
	TEST	BYTE PTR $FAC,LOW 377O	;Is the number zero?
	JZ	FIN80			;Yes, just return zero then.
	CMP	DX,39D
	JB	FIN40			;OK PROCEED
	; POPF				; Get back type flags
	; JNB	FIN25			; Already D.P., nothing to convert
	; CALL	$CSD			; Convert double to single
FIN25:	POP	BX			; Restore text pointer
	JMP	$OVFLS			;OVERFLOW
;
; Negative exponent.
; Might require two divisions since highest table entry is 10^38.
;
FIN30:	CMP	DX,-38D			;Will one pass be enough?
	JGE	FIN40			;Yes.
	ADD	DX,38D			;No, will two divisions get it?
	CMP	DX,-38D
	JL	FIN80			;No, underflow - return zero.
	CALL	MDP10			;Yes, do the first one
	MOV	DX,-38D			;Then divide by 10^38.
FIN40:	CALL	MDP10			; Do the division
FIN45:
	; POPF				; Get back type flags
	; JNB	FIN50			; Already D.P., nothing to convert
	; CALL	$CSD			; Convert double to single

; At this point the number is restored to its original type, with the
; exception of integers being converted to single precision.

FIN50:	POP	BX			; Restore text pointer
FIN55:	RET

FIN80:	CALL	$ZERO			;UNDERFLOW!
	JMP	SHORT FIN45		; Restore proper type
;
; Multiply or divide by double precision power of ten.
; On entry DX contains the exponent.
; If the exponent is positive, multiply.
; If exponent is negative, divide.
;
MDP10:
	OR	DX,DX			;Is the exponent negative?
	PUSHF				;Remember whether to multiply or
					;divide.
	JNS	POSEXP			;Positive exponent.
	NEG	DX			;Negative exponent, make it positive.
POSEXP: MOV	CX,3			;DX:=DX*8 to get offset into powers
	SHL	DX,CL			;of ten table.
	ADD	DX,OFFSET $DP00 	;DX:=pointer to power of ten.
	XCHG	BX,DX			;Move it to BX.
	CALL	$MOVAC			;MOVE D.P. NO. TO ARG
	POPF				;Divide?
	JS	DBLDIV			;Yes.
	JMP	$FMULD			;No, multiply and return to caller
DBLDIV: JMP	DDIVFA			;Double precision divide; FAC=FAC/ARG,
					; Return to caller.
ENDPROC	$FINE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $FINEX
;
; Adapted from MATH2.ASM, copyright (c) Microsoft Corporation.
;
; THE PURPOSE OF THIS ROUTINE IS TO DETERMINE THE INPUT EXPONENT BASE 10
; AND LEAVE IN (DX).  ADDITIONALLY IF A MINUS "-" SIGN IS ENCOUNTERED, $FINEX
; WILL SET ALL BITS OF (SI).  OTHERWISE ALL BITS OF (SI) WILL BE CLEARED.
;
; CALL $FINEX WITH THE SIGNIFICANT DIGITS OF THE NUMBER IN THE FAC.
;
DEFPROC	$FINEX
	XOR	SI,SI			;IN CASE EXPONENT IS POSITIVE
	MOV	DX,SI			;WILL BUILD EXPONENT IN DX
	CALL	$CHRGT			;GET FIRST CHARACTER OF EXPONENT
	JB	FX20			;NO SIGN SO DEFAULT POS.
	CMP	AL,LOW "-"      	;NEGATIVE EXPONENT
	JNZ	FX00			;IF NOT MUST BE POSITIVE
	NOT	SI			;NEGATIVE EXPONENT
	JMP	SHORT FX10		;GO GET NEXT CHARACTER
FX00:	CMP	AL,LOW "+"
	JZ	FX10
					;ILLEGAL CHARACTER MUST LEAVE
	RET				;(BX) POINTING HERE
FX10:	CALL	$CHRGT			;GET NEXT CHARACTER
	JB	FX20			;IF DIGIT PROCESS AS EXPONENT
	RET				;OTHERWISE RETURN
FX20:	CMP	DX,3276D		;OVERFLOW IF THIS DOESN'T GET CF=1
	JB	FX30			;NO-USE THIS DIGIT
	MOV	DX,32767D		;TO ASSURE OVERFLOW
	JMP	SHORT FX10
FX30:	PUSH	AX			;SAVE NEW DIGIT
	MOV	AX,10D			;MUST MULTIPLY DX BY 10
	MUL	DX			;ANSWER NOW IN AX
	POP	DX			;RECALL DIGIT TO DX
	SUB	DL,LOW 60		;SUBTRACT OUT ASCII BIAS
	XOR	DH,DH			;TO BE SURE AX HAS CORRECT NO.
	ADD	DX,AX			;ADD TO DX
	JMP	SHORT FX10
ENDPROC	$FINEX

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $FLTD
;
; Adapted from MATH2.ASM, copyright (c) Microsoft Corporation.
;
; CONVERTS THE SIGNED INTEGER IN (DX:AX) TO A REAL (FLOATING POINT) NUMBER
; AND STORES IT IN THE FAC.
;
; NOTE: Since Microsoft BASIC supported only 16-bit integers, their $FLT
; input was a 16-bit value in DX.  BASIC-DOS supports 32-bit integers, so I've
; rewritten the $FLT -> $NORMS -> $ROUNS logic as $FLTD -> $NORMD -> $ROUND
; ($NORMD and $ROUND already existed, so only $FLTD is "new").
;
; This will also be a bit slower; even though the $FLT functions were "FAC"
; functions, they were single-precision and kept the entire number in registers
; most of the time (BL:DX, with AH as an overflow byte, and BH as a copy of
; the exponent).
;
; Inputs:
;	DX:AX = 32-bit integer to convert to double-precision
;	DI -> SCB_FAC
;
DEFPROC	$FLTD,DOS
	XOR	CX,CX			;ZERO CX
	ADD	DI,(OFFSET $DFACL-1)	;ADVANCE DI TO $DFACL-1 IN SCB_FAC
	XCHG	AX,CX			;SAVE AX TO CX, ZERO AX
	STOSB				;ZERO THE OVERFLOW BYTE ($DFACL-1)
	XCHG	AX,CX			;RESTORE AX FROM CX, ZERO CX
	MOV	BX,(32 + 80H)		;BL = EXPONENT, BH = POSITIVE SIGN
	OR	DX,DX			;SETS SF=1 IF NEGATIVE NO.
	JNS	FLT10			;IF POSITIVE PROCEED
	NEG	DX
	NEG	AX
	SBB	DX,CX			;DX:AX
	MOV	BH,80H			;BH = NEGATIVE SIGN
FLT10:	STOSW				;STORE AX IN THE LOWEST MANTISSA WORD
	XCHG	AX,DX
	STOSW				;STORE DX IN THE NEXT MANTISSA WORD
	XCHG	AX,CX
	STOSW				;ZERO THE NEXT MANTISSA WORD
	STOSB				;ZERO THE HIGHEST MANTISSA BYTE
	XCHG	AX,BX
	STOSW				;SET EXPONENT AND TEMPORARY SIGN BYTE
	SUB	DI,(OFFSET $DFACL-1)+10	;REWIND DI BACK TO START OF SCB_FAC
;
; Fall into $NORMD
;
ENDPROC	$FLTD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $NORMD
;
; Adapted from MATH2.ASM, copyright (c) Microsoft Corporation.
;
; NORMALIZES THE NUMBER IN $FAC+1 THRU $DFACL-1, FOLLOWED BY ROUNDING
; AND PACKING THE $FAC.
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$NORMD,DOS
	MOV	DL,71Q			;MAX BITS TO SHIFT LEFT
	LEA	BX,[DI].$DFACL-1

NORD05:	PUSH	DI
	LEA	SI,[DI].$FAC
	LEA	DI,[DI].$FAC-1
	JMP	SHORT NORD30
NORD10:
	MOV	CX,4
	CLC				;CF=0
NORD20: RCL	WORD PTR [BX],1
	INC	BX
	INC	BX			;POINT TO NEXT WORD
	LOOP	NORD20
	SUB	BX,8			;POINT BACK TO END OF NUMBER
NORD25:
	DEC	BYTE PTR [SI]		;DECREMENT EXPONENT
	JZ	NORD40			;DO CLEAN-UP IF UNDERFLOW
	DEC	DL			;SEE IF MAX BITS SHIFTED
	JZ	NORD40			;IF SO TERMINATE SHIFTS
NORD30: TEST	BYTE PTR [DI],377Q	;SF=1 IF NOW NORMALIZED
	JS	NORD40			;NORMALIZED
	JNZ	NORD10			;MUST SHIFT BIT AT A TIME
;
; CAN DO AT 1 BYTE MOVE LEFT
;
	SUB	BYTE PTR [SI],10Q	;SUBTRACT 8
	JBE	NORD40			;UNDERFLOW
	SUB	DL,10Q			;SEE IF MAX BITS SHIFTED
	JBE	NORD40			;AND IF SO QUIT
	SUB	SI,2			;SI -> $FAC-2
	MOV	CX,7			;7 BYTES TO MOVE
	STD				;SO FOLLOWING MOVB WILL DECREMENT
	REP	MOVSB			;REPEAT CX TIMES (THE MOVB)
	POP	DI

	MOV	[DI].$DFACL-1,0		;ZERO OVERFLOW
	JMP	NORD05			;SEE IF MORE CASES

NORD35:	JMP	$DZERO

NORD40: JBE	NORD35			;UNDERFLOW JUMP
;
; Fall into $ROUND
;
ENDPROC	$NORMD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $ROUND
;
; Adapted from MATH2.ASM, copyright (c) Microsoft Corporation.
;
; ROUND THE DOUBLE PRECISION FLOATING POINT NUMBER IN $FAC+1 THRU $DFACL-1
; AND PACK.
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$ROUND,DOS
	LEA	BX,[DI].$DFACL-1
	ADD	WORD PTR [BX],200Q	;ADD TO HIGH BIT OV OVERFLOW BYTE
	MOV	CX,3			;3 MORE BYTES TO LOOK AT POTENTIALLY
	JNB	RDD20			;IF CF=0 WE ARE DONE

RDD10:	INC	BX
	INC	BX
	INC	WORD PTR [BX]		;IF THIS GETS ZF=1 THEN CARRY
	JNZ	RDD20			;FINISHED WHEN ZF=0
	LOOP	RDD10
	INC	[DI].$FAC		;MUST INCREMENT EXPONENT
	RCR	WORD PTR [BX],1		;SET HIGH BYTE TO 200

RDD20:	JZ	RDD30			;OVERFLOW HOOK
	TEST	[DI].$DFACL-1,377Q	;SEE IF OVERFLOW BYTE ZERO
	JNZ	$ROUNX
	AND	[DI].$DFACL,376Q	;MAKE ANSWER EVEN

$ROUNX:	AND	[DI].$FAC-1,177Q	;CLEAR SIGN BIT
	MOV	AL,[DI].$FAC+1		;FETCH SIGN BYTE
	AND	AL,200Q			;CLEAR ALL BUT SIGN
	OR	[DI].$FAC-1,AL		;AND SET SIGN APPROPRIATELY
	RET

RDD30:	JMP	$OVFLS
ENDPROC	$ROUND

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $FSUBD
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$FSUBD,DOS			;($FAC):=($ARG)-($FAC)
	MOV	AX,WORD PTR [DI].$FAC-1
	OR	AH,AH			;IF ZF=1 ARG IS ANSWER
	JZ	FADDX1
	XOR	[DI].$FAC-1,200Q	;FLIP SIGN OF FAC
	JMP	SHORT $FADDD
FADDX1: CALL	$MOVFA			;MOVE DOUBLE PREC ARG TO FAC
FADDX2: RET
ENDPROC	$FSUBD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $FADDD
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; THIS ROUTINE PERFORMS DOUBLE PRECISION FLOATING POINT ADDITION/SUBTRACTION
; I.E. (FAC)=(FAC)+-(ARG)
;
; THE LARGER NO. WILL BE PLACED IN THE FAC, THE SMALLER NO. IN THE ARG
; WILL BE SHIFTED RIGHT UNTIL THEIR BINARY POINTS ALIGN AND THE TWO WILL BE
; ADDED/SUBTRACTED.  IF IT TURNS OUT THAT THE EXPONENTS WERE EQUAL AND THE
; OPERATION WAS A SUBTRACTION THEN A CARRY OUT OF THE HIGH BYTE CAN OCCUR.
;
; IF THIS IS THE CASE, OUR CHOICE AS TO WHICH WAS THE LARGER NO. WAS INCORRECT
; AND WE HAVE TO NEGATE OUR MANTISSA AND COMPLEMENT THE SIGN OF THE RESULT.
;
; THE FORMAT OF DOUBLE PRECISION NUMBERS IS AS FOLLOWS
;
; BIT:
; 66665555 55555544 44444444 33333333 33222222 22221111 11111100 00000000
; 32109876 54321098 76543210 98765432 10987654 32109876 54321098 76543210
; AAAAAAAA BCCCCCCC CCCCCCCC CCCCCCCC CCCCCCCC CCCCCCCC CCCCCCCC CCCCCCCC
; [$FAC  ] [$FAC-1] [$FAC-2] [$FACLO] [$DFACL  [$DFACL  [$DFACL  [$DFACL]
;                                        +3  ]    +2  ]    +1  ]
;
; WHERE A=EXPONENT BIASED 128
;       B=SIGN(1=NEGATIVE,0=POSITIVE) OF NUMBER
;       C=BITS 2-56 OF MANTISSA (BIT 1 IS UNDERSTOOD 1)
;         (ALSO BIT 54 IS HIGH ORDER BIT)
; NOTE: THE BINARY POINT IS TO THE LEFT OF THE UNDERSTOOD 1
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$FADDD,DOS			;($FAC):=($ARG)+($FAC)
	MOV	AL,0			;WANT TO ZERO OVERFLOW BYTES
	MOV	[DI].$DFACL-1,AL
	MOV	[DI].$ARGLO-1,AL
	MOV	AL,[DI].$ARG		;IF ($ARG)=0 THEN JUST RET
	OR	AL,AL			;
	JZ	FADDX2			;RETURN
	MOV	AX,WORD PTR [DI].$FAC-1	;
	OR	AH,AH			;IF EXPONENT=0, NO. IS ZERO
	JZ	FADDX1			;ARG IS THE ANSWER
	MOV	BX,WORD PTR [DI].$ARG-1	;FETCH SIGN AND EXPONENT
	OR	[DI].$FAC-1,200Q	;RESTORE HIDDEN 1 MANTISSA BIT
	OR	[DI].$ARG-1,200Q
	MOV	CL,AH			;WILL FORM SHIFT COUNT IN (CL)
	SUB	CL,BH			;
	MOV	[DI].$FAC+1,AL		;ASSUME SIGN OF FAC
	JZ	FDD25			;PROCEED IF EXPONENTS EQUAL
	JNB	FDD20			;IF FAC LARGER (OR EQUAL) JUMP
;
; $ARG HAS THE LARGER EXPONENT SO WE MUST EXCHANGE FAC AND ARG AND
; USE SIGN OF THE ARG
;
	XCHG	AL,BL			;HIGH MANTISSA BYTE EXCHANGE
	NEG	CL			;NED POS. SHIFT COUNT
	MOV	[DI].$FAC+1,AL		;ADAPT ARG SIGN
	MOV	[DI].$FAC,BH		;ADAPT ARG EXPONENT
	PUSH	AX			;SAVE ARG MANTISSA BITS
	PUSH	CX			;WILL NEED AS COUNT FOR LOOP
	CALL	$XCGAF			;EXCHANGE ARG AND FAC
	POP	CX			;RECALL OLD CX
	POP	AX			;GET MANTISSA BYTES BACK
;
; WE NOW HAVE THE SUSPECTED LARGER NO IN THE FAC, WE NEED TO KNOW IF WE ARE
; TO SUBTRACT (SIGNS ARE DIFFERENT) AND WE NEED TO RESTORE THE HIDDEN MANTISSA
; BIT FURTHER, IF THERE IS TO BE MORE THAN 56 BITS SHIFTED TO ALIGN THE BINARY
; POINTS THEN THE LESSOR NO. IS INSIGNIFICANT IN COMPARISON TO THE LARGER NO.
; SO WE CAN JUST RETURN AND CALL THE LARGER NO. THE ANSWER.
;
FDD20:	CMP	CL,57D			;THIS MUST SET CF TO CONTINUE
	JNB	FDD95			;RETURN IF CF=0
	PUSH	BX			;SAVE MANTISSA BITS
	CLC				;SO WE DON'T GET CF IN THERE
	CALL	$SHRA			;SHIFT ARG RIGHT (CL) BITS
	MOV	AL,[DI].$FAC+1		;RECALL SIGN (AL DESTROYED BY $SHRA)
	POP	BX
FDD25:	XOR	AL,BL			;WILL NOW DETERMINE IF ADD/SUB
	LEA	BX,[DI].$DFACL-1
	LEA	SI,[DI].$ARGLO-1
	MOV	CX,4			;4 SIXTEEN BIT OPERATIONS
	CLC				;CF=0
;
; WE ARE NOW STAGED TO DO THE ADD/SUBTRACT. IT WILL BE DONE AS 4 SIXTEEN
; BIT OPERATIONS.
;
	; CLD				;SO LODW WILL INCB
					;Note 9-Aug-82/MLC - This CLD is
					;for the LODWs at both FDD30 and
					;FDD50.
	JS	FDD50			;IF SF=1 GO SUBTRACT
FDD30:	LODSW				;FETCH NEXT BYTE ARG
					;Note 9-Aug-82/MLC - CLD is outside
					;loop above.
	ADC	WORD PTR [BX],AX	;ADD IT TO FAC
	INC	BX
	INC	BX
	LOOP	FDD30
	JNB	FDD40			;GO ROUND IF CF=0
;
; WE HAD OVERFLOW OUT OF THE HIGH MANTISSA BIT. WE MUST INCREMENT
; THE EXPONENT AND SHIFT THE OVERFLOW BIT BACK INTO THE FAC BY
; SHIFTING THE FAC RIGHT 1 BIT.
;
FDD35:	LEA	BX,[DI].$FAC		;FETCH ADDRESS OF EXPONENT
	INC	BYTE PTR [BX]		;INCREMENT THE EXPONENT
	JZ	FDD90			;IF ZF=1 - OVERFLOW
	DEC	BX
	DEC	BX			;BX POINTS TO $FAC-2
	MOV	CX,4			;4 SIXTEEN BIT SHIFTS
;
; WE ARE NOW SET TO SHIFT THE FAC RIGHT 1 BIT. RECALL WE GOT HERE
; WITH CF=1. THE INSTRUCTIONS SINCE WE GOT HERE HAVEN'T AFFECTED
; CF SO WHEN WE SHIFT RIGHT WE WILL SHIFT CF INTO THE HIGH MANTISSA BIT.
;
FDD37:	RCR	WORD PTR [BX],1
	DEC	BX
	DEC	BX
	LOOP	FDD37
FDD40:	JMP	$ROUND			;GO ROUND THE RESULT

;
; TO GET HERE THE SIGNS OF THE FAC AND ARG WERE DIFFERENT THUS
; IMPLYING A DESIRED SUBTRACT.
;
FDD50:	LODSW				;FETCH NEXT WORD OF ARG
					;Note 9-Aug-82/MLC - The CLD is
					;just above FDD30.
	SBB	WORD PTR [BX],AX	;SUBTRACT FROM FAC
	INC	BX
	INC	BX
	LOOP	FDD50
	JNB	FDD80			;GO NORMALIZE AND ROUND
;
; TO GET HERE FAC TURNED OUT SMALLER THAN THE ARG. TO CORRECT
; THE ANSWER IN THE FAC WE MUST NEGATE THE MANTISSA BITS
; AND THE SIGN IN $FAC+1
;
	NOT	BYTE PTR [BX+1]		;COMPLEMENT SIGN
	MOV	CX,4			;4 SIXTEEN BIT COMPLEMENTS
FDD60:	DEC	BX
	DEC	BX
	NOT	WORD PTR [BX]		;COMPLEMENT FAC
	LOOP	FDD60
;
; MUST NOW ADD 1 FOR 2'S COMPLEMENT ARITH.
;
	MOV	CX,4
FDD70:	INC	WORD PTR [BX]		;IF ZF=1 THEN CARRY
	JNZ	FDD80			;SINCE THEY DON'T SET CF
	INC	BX
	INC	BX
	LOOP	FDD70
	JZ	FDD35			;IF ZF=1 MUST INCREMENT EXP
FDD80:	JMP	$NORMD			;GO NORMALIZE
FDD90:	JMP	$OVFLS			;OVERFLOW!
FDD95:	JMP	$ROUNX			;PUT IN THE SIGN AND DONE
ENDPROC	$FADDD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $SHRA
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; SHIFT $ARG RIGHT (CX) BITS
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$SHRA,DOS
	LEA	BX,[DI].$ARG-2
	CMP	CL,10Q			;CAN I DO A BYTE MOVE
	JB	SHRA30			;IF NOT PROCEED AS NORMAL
;
; FOR SPEED PURPOSES WE WILL DO A BYTE MOVE TO THE RIGHT
;
	PUSH	CX			;SAVE BITS TO SHIFT
	MOV	CX,7			;7 BYTE MOVE
	LEA	BX,[DI].$ARGLO-1
	MOV	AH,[BX]			;FETCH OVERFLOW BYTE
SHRA11: MOV	AL,[BX+1]
	MOV	[BX],AL
	INC	BX
	LOOP	SHRA11
	XOR	AL,AL
	MOV	[BX],AL
	POP	CX			;RECALL BIT COUNT
	SUB	CL,10Q
	AND	AH,40Q			;WILL NEED TO RE-ESTABLISH ST
	JZ	$SHRA			;NO-ST JUST PROCEED
	OR	[DI].$ARGLO-1,AH
	JMP	$SHRA

SHRA20:	OR	BYTE PTR [BX+2],40Q	;"OR" IN ST BIT
	JMP	SHORT SHRA35

SHRA30:	OR	CL,CL
	JZ	SHRA40			;JUMP IF DONE
	PUSH	CX			;SAVE NO. BITS TO SHIFT
	CLC				;DON'T WANT THE CARRY SHIFTED IN
	CALL	$SHDR
	POP	CX
	TEST	BYTE PTR [BX+2],20Q	;SEE IF SHIFTED THRU "ST"
	JNZ	SHRA20			;MUST "OR" ST BIT IN IF NON-ZERO
SHRA35:	LOOP	$SHRA
SHRA40: RET
ENDPROC	$SHRA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $SHDR
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; DOUBLE PRECISION RIGHT SHIFT
;
; Inputs:
;	BX -> double-precision number
;	DI -> SCB_FAC
;
DEFPROC	$SHDR,DOS
	MOV	CX,4			;SHIFT (CX) WORDS RIGHT
$SHRM:	RCR	WORD PTR [BX],1		;SHIFT 1 WORD RIGHT THRU CF
	DEC	BX
	DEC	BX			;TO NEXT WORD
	LOOP	$SHRM			;DO THIS (CX) TIMES
	RET
ENDPROC	$SHDR

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $XCGAF
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; EXCHANGE FAC AND ARG (DOUBLE PRECISION)
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$XCGAF,DOS
	PUSH	DI
	LEA	SI,[DI].$DFACL		;WILL EXCHANGE FAC AND ARG (D.P.)
	LEA	DI,[DI].$ARGLO
	; CLD				;SO MOVW WILL INCREMENT INDICES
	MOV	CX,4			;WILL MOVE 4 WORDS (8 BYTES)
XCG10:	MOV	AX,[DI]			;FETCH DESTINATION WORD
	MOVSW				;MOVE FAC TO ARG & INCREMENT INDICES
	MOV	[SI-2],AX		;ARG TO FAC
	LOOP	XCG10			;CONTINUE
	POP	DI
	RET
ENDPROC	$XCGAF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $MUL10
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; MULTIPLY THE FAC BY 10.
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$MUL10,DOS
	MOV	BX,OFFSET $DP01 	;ADDRESS OF DOUBLE PREC 10.
	CALL	$MOVAC			;MOVE 10. TO ARG
	CALL	$FMULD			;MULTIPLY
	RET
ENDPROC	$MUL10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $NEG
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; FLIP THE SIGN BIT.
;
DEFPROC	$NEG,DOS
	PUSH	DI			;
	MOV	DI,[SCB_ACTIVE]		;
	LEA	DI,[DI].SCB_FAC		;
	XOR	BYTE PTR [DI].$FAC-1,80h;FLIP SIGN OF FAC
	POP	DI
	RET
ENDPROC	$NEG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $FMULD
;
; Adapted from MATH2.ASM, copyright (c) Microsoft Corporation.
;
; THIS ROUTINE FORMS THE DOUBLE PRECISION PRODUCT:
;
;	($FAC):=($FAC)*($ARG)
;
; THE TECHNIQUE USED IS DESCRIBED IN KNUTH, VOL II P.233 AND IS CALLED
; ALGORITHM "M".
;
; CALLING SEQUENCE: CALL $FMULD WITH THE MULTIPLIER AND MULTIPLICAND IN THE
; $FAC AND $ARG.
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$FMULD,DOS
	MOV	AL,[DI].$FAC		;WILL FIRST SEE IF FAC IS ZERO
	OR	AL,AL			;AND IF SO JUST RETURN
	JZ	FMD10
	MOV	AL,[DI].$ARG		;WILL NOW SEE IF ARG IS ZERO AND
	OR	AL,AL			;IF SO SET FAC TO ZERO AND RETURN
	JNZ	FMD20			;IF NOT ZERO PROCEED TO MULTIPLY
	JMP	$DZERO			;ZERO THE FAC
FMD10:	RET

FMD20:	MOV	BX,WORD PTR [DI].$ARG-1	;FETCH SIGN AND EXP. TO BX
	CALL	$AEXPS			;ADD THE EXPONENTS
	PUSH	WORD PTR [DI].$FAC	;EXPONENT,SIGN
	MOV	WORD PTR [DI].$ARG-1,BX	;REPLACE UNPACKED MANTISSA
					;PUT THE SIGN OF THE PRODUCT IN FAC+1
	CALL	$SETDB			;MOVE THE FAC TO $DBUFF SO PRODUCT
					;CAN BE FORMED IN THE FAC, AND ZERO
					;THE FAC AND RETURNS WITH (AX)=0
	MOV	SI,AX			;J
	MOV	WORD PTR [DI].$FAC,AX
	LEA	BX,[DI].$DBUFF
	MOV	WORD PTR [DI].$ARG,AX
	LEA	BP,[DI].$ARGLO		;POINT TO MULTIPLICAND BASE

	PUSH	DI
M1:	MOV	AX,WORD PTR [BX+SI]	;FETCH MULTIPLIER V(J)
	OR	AX,AX			;SEE IF ZERO
	JZ	M4D			;IF ZERO W(J)=0
	XOR	DI,DI			;I
	MOV	CX,DI			;K
M4:	MOV	AX,WORD PTR [BX+SI]	;FETCH MULTIPLIER V(J)
	MUL	WORD PTR DS:[BP+DI]	;FORM PRODUCT V(J)*U(J) IN (DX:AX)

	PUSH	BX			;SAVE PTR. TO MULTIPLIER BASE
	; MOV	BX,SI			;
	; ADD	BX,DI			;I+J
	; ADD	BX,OFFSET $DFACL-8	;W(I+J) ADDRESS IN BX
	LEA	BX,[BX+SI]+($DFACL-8)-$DBUFF
	ADD	BX,DI

	ADD	AX,[BX]			;(DX:AX)=U(I)*V(J)+W(I+J)
	JNB	M4A
	INC	DX
M4A:	ADD	AX,CX			;T=U(I)*V(J)+W(I+J)+K
	JNB	M4B
	INC	DX
M4B:	MOV	[BX],AX			;W(I+J)= T MOD 2^16
	MOV	CX,DX			;K=INT(T/2^16)
	POP	BX			;RECALL PTR TO MULTIPLIER BASE

	CMP	DI,6			;FINISHED INNER LOOP?
	JZ	M4C			;IF SO JUMP AND SET W(J)
	INC	DI
	INC	DI
	JMP	SHORT M4
M4C:	MOV	AX,CX			;(AX)=K

M4D:	PUSH	BX			;SAVE PTR TO MULTIPLIER BASE
	LEA	BX,[BX].$DFACL-$DBUFF
	MOV	WORD PTR [BX+SI],AX	;W(J)=K OR 0 (0 IF V(J) WERE 0)
	POP	BX			;RECALL PTR TO MULTIPLIER BASE

	CMP	SI,6			;FINISHED OUTER LOOP?
	JZ	M5
	INC	SI
	INC	SI
	JMP	SHORT M1

M5:	POP	DI			;MULTIPLICATION COMPLETE AND IN FAC
	LEA	SI,[DI].$DFACL-2	;WILL NOW SET ST
	STD				;WANT NON-ZERO BYTE ASAP SO PROB.
					;SEEMS HIGHER OF GETTING ONE IF
					;(SI) IS DECREMENTED
	MOV	CX,7			;7-BYTE CHECK
M5A:	LODSB				;FETCH NEXT BYTE
	OR	AL,AL
	LOOPZ	M5A
	JZ	M6			;DON'T NEED TO SET ST
	OR	[DI].$DFACL-1,40Q	;"OR" IN ST BIT

M6:	CLD				;RESTORE DEFAULT DIRECTION
	MOV	AL,[DI].$FAC-1		;SEE IF WE NEED TO INC EXPONENT
	OR	AL,AL
	POP	WORD PTR [DI].$FAC	;RESTORE EXPONENT,SIGN
	JS	M9
	LEA	BX,[DI].$DFACL-1	;MUST SHIFT 1 BIT LEFT

	MOV	CX,4
M7:	RCL	WORD PTR [BX],1
	INC	BX
	INC	BX
	LOOP	M7
M8:	JMP	$ROUND			;NOW ROUND

M9:	INC	[DI].$FAC		;INCREMENT EXPONENT
	JNZ	M8
	JMP	$OVFLS			;OVERFLOW!
ENDPROC	$FMULD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $FDIVD
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; THIS ROUTINE DIVIDES THE ARG BY THE FAC LEAVING THE QUOTIENT IN THE FAC.
;
; Inputs:
;	DI -> SCB_FAC
;*******************************************************************

DEFPROC	$FDIVD,DOS
	MOV	SI,OFFSET $ARGLO
	MOV	DI,OFFSET $DFACL
$DDIV:
	MOV	AX,WORD PTR 6[SI]	;High half of numerator
	MOV	CX,WORD PTR 6[DI]	;High half of denominator
	XOR	AL,CL			;Compute sign
	MOV	BYTE PTR $FAC+1,AL	;and store in $FAC
	OR	CH,CH			;Denominator zero?
	JZ	DDIV0
	OR	AH,AH			;Numerator zero?
	JZ	EXIT1
	SUB	AH,LOW 128D		;Remove bias from exponents
	SUB	CH,LOW 128D
	SUB	AH,CH			;Compute result exponent
	JO	DOVCKJ

;AH has the (tentative) true exponent of the result. It is correct if the
;result needs normalizing one bit. If not, 1 will be added to it. A true
;exponent of -128, not normally allowed except to represent zero, is OK
;here because of this possible future incrementing.

	CLD				;9-Aug-82/MLC - Good for the LODC,
					;LODW, LODW, and LODW which follow.
	ADD	AH,LOW 128D		;Put bias back
	PUSH	AX			;SAVE sign and exponent
	LODSB				;Load up dividend
	MOV	CH,AL
	XOR	CL,CL
	LODSW
	XCHG	AX,BX
	LODSW
	XCHG	AX,DX
	LODSW
	OR	AH,LOW 200O		;Set implied bit
	XCHG	AX,DX			;Divisor in DX:AX:BX:CX

;Move divisor to FAC so we can get at it easily. More importantly, get it in
;the necessary form - extended to 64 bits with zeros, implied bit set.
;The form we want it in will have the mantissa MSB where the exponent usually
;is, so by moving high to low we will not destroy the divisor even if it is
;already in the FAC.

	MOV	SI,DI
	ADD	SI,5			;Point to high end of divisor
	MOV	DI,OFFSET $FAC-1
	STD				;Direction DOWN
	MOVSW				;Move divisor to FAC
	MOVSW
	MOVSW
	INC	SI
	INC	DI
	MOVSB
	CLD				;DRESTR direction
	MOV	BYTE PTR 0[DI],LOW 0	;Extend to 64 bits with a zero
	OR	BYTE PTR $FAC,LOW 200O	;Set implied bit

;Now we're all set:
;       DX:AX:BX:CX has dividend
;       FAC has divisor (not in normal format)
;Both are extended to 64 bits with zeros and have implied bit set.
;Top of stack has sign and tentative exponent.

	SHR	DX,1			;Make sure dividend is smaller than
	RCR	AX,1			; divisor by dividing it by two
	RCR	BX,1
	RCR	CX,1
	CALL	DDIV16			;Get a quotient digit
	PUSH	DI
	CALL	DDIV16
	PUSH	DI
	CALL	DDIV16
	PUSH	DI
	CALL	DDIV16
	OR	AX,BX			;Remainder zero?
	OR	AX,CX
	OR	AX,DX
	MOV	DX,DI			;Get lowest word in position
	JZ	DNSTK1
	OR	DL,LOW 1		;Set sticky bit if not
DNSTK1:
	POP	CX			;Recover quotient digits
	POP	BX
	POP	DI
	JMP	DNRMCHK

EXIT1:	JMP	$DZERO			;ZERO THE FAC
DOVCKJ: JNS	EXIT1
	JMP	$OVFLS
DDIV:
DDIVFA: MOV	SI,OFFSET $DFACL
	MOV	DI,OFFSET $ARGLO
	JMP	SHORT $DDIV

DDIV0:	MOV	BYTE PTR $FAC+1,AL
	JMP	$DIV0S

DDIV16:
	MOV	SI,WORD PTR $DFACL+6	;Get high word of divisor
	XOR	DI,DI			;Initialize quotient digit to zero
	CMP	DX,SI			;Will we overflow?
	JAE	DMXQUO			;If so, go handle special
	OR	DX,DX			;Is dividend small?
	JNZ	DODIV
	CMP	SI,AX			;Will divisor fit at all?
	JA	ZERQUO			;No - quotient is zero
DODIV:
	DIV	SI			;AX is our digit "guess"
	PUSH	DX			;SAVE remainder
	XCHG	AX,DI			;Quotient digit in DI
	XOR	BP,BP			;Initialize quotient * divisor
	MOV	SI,BP
	MOV	AX,WORD PTR $DFACL
	OR	AX,AX			;If zero, SAVE multiply time
	JZ	REM2
	MUL	DI			;Begin computing quotient * divisor
	MOV	SI,DX
REM2:
	PUSH	AX			;SAVE lowest word of quotient * divisor
	MOV	AX,WORD PTR $DFACL+2
	OR	AX,AX
	JZ	REM3
	MUL	DI
	ADD	SI,AX
	ADC	BP,DX
REM3:
	MOV	AX,WORD PTR $DFACL+4
	OR	AX,AX
	JZ	REM4
	MUL	DI
	ADD	BP,AX
	ADC	DX,0
	XCHG	AX,DX
REM4:					;Quotient * divisor in AX:BP:SI:[SP]
	POP	DX			;Recover lowest word of quotient * divisor
	NEG	DX			;Subtract from dividend
	SBB	CX,SI
	SBB	BX,BP
	POP	BP			;Remainder from DIV
	SBB	BP,AX
	XCHG	AX,BP
ZERQUO:					;Remainder in AX:BX:CX:DX
	XCHG	AX,DX
	XCHG	AX,CX
	XCHG	AX,BX
	JNB	RETRES			;Remainder in DX:AX:BX:CX
DRESTR:
	DEC	DI			;Drop quotient since it didn't fit
	ADD	CX,WORD PTR $DFACL	;Add divisor in until remainder goes +
	ADC	BX,WORD PTR $DFACL+2
	ADC	AX,WORD PTR $DFACL+4
	ADC	DX,WORD PTR $DFACL+6
	JNB	DRESTR
RETRES: RET

DMXQUO:
	DEC	DI			;DI=FFFF=2**16-1
	SUB	CX,WORD PTR $DFACL
	SBB	BX,WORD PTR $DFACL+2
	SBB	AX,WORD PTR $DFACL+4
	ADD	CX,WORD PTR $DFACL+2
	ADC	BX,WORD PTR $DFACL+4
	ADC	AX,DX
	MOV	DX,WORD PTR $DFACL
	CMC
	JMP	SHORT ZERQUO
DNRMCHK:
	POP	AX			;Get exp. and sign back
	OR	DI,DI			;See if normalized
	JS	DINCEX			;Yes - increment exponent
	SHL	DX,1			;Normalize
	RCL	CX,1
	RCL	BX,1
	RCL	DI,1
	OR	AH,AH
	JNZ	DDRND
	JMP	$DZERO
DINCEX:
	INC	AH
	JZ	DDOVFL
$DROUND:
DDRND:
	CMP	DL,LOW 200O		;Check extended bits
	JA	FPRNDUP
	JB	DDSV
;Extended bits equal exactly one-half LSB, so round even
	TEST	DH,LOW 1		;Already even?
	JZ	DDSV
FPRNDUP:
	ADD	DH,LOW 1
	ADC	CX,0
	ADC	BX,0			;Propagate carry
	ADC	DI,0
	JNB	DDSV			;Overflow?
;If we overflowed, DI:BX:CX:DH must now be zero, so we can leave it that way.
	INC	AH			;Increment exponent
	JNZ	DDSV
DDOVFL: JMP	$OVFLS
DDSV:
	AND	AL,LOW 200O		;Strip to sign bit
	XCHG	BX,DI
	AND	BH,LOW 177O		;Mask off implied bit
	OR	AL,BH			;Combine sign with mantissa
	MOV	WORD PTR $DFACL+6,AX
	MOV	BYTE PTR $FAC-2,BL
	MOV	BX,DI
	MOV	DI,OFFSET $DFACL
	MOV	AL,DH
	CLD
	STOSB
	XCHG	AX,CX
	STOSW
	XCHG	AX,BX
	STOSW
	RET
ENDPROC	$FDIVD

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $AEXPS
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; PERFORM THE ADDITION OF DOUBLE PRECISION EXPONENTS.
;
; CALLING SEQUENCE: CALL $AEXPS WITH THE DOUBLE PRECISION NUMERATOR
; (MULTIPLIER) IN ($ARG) AND THE DENOMINATOR (MULTIPLICAND) IN THE ($FAC).
; THE $ARG EXPONENT AND HIGH MANTISSA BYTE MUST BE IN BH:BL.
;
DEFPROC	$AEXPS,DOS
	STC				;CF=1
	JMP	SHORT SES00
ENDPROC	$AEXPS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $SEXPS
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; PERFORM THE SUBTRACTION OF DOUBLE PRECISION EXPONENTS.
;
; CALLING SEQUENCE: CALL $SEXPS WITH THE DOUBLE PRECISION NUMERATOR
; (MULTIPLIER) IN ($ARG) AND THE DENOMINATOR (MULTIPLICAND) IN THE ($FAC).
; THE $ARG EXPONENT AND HIGH MANTISSA BYTE MUST BE IN BH:BL.
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$SEXPS,DOS
	CLC				;CF=0
SES00:	MOV	SI,BX			;WILL NEED FOR LATER
	PUSHF				;SAVE MULTIPLY/DIVIDE FLAG
	MOV	CX,WORD PTR [DI].$FAC-1	;(CH)=$FAC:(CL)=$FAC-1
	MOV	AL,BL			;FETCH (BX:DX) SIGN BYTE
	XOR	AL,CL			;CORRECT SIGN IN AL
	MOV	[DI].$FAC+1,AL		;MOVE TO $FAC+1
	MOV	AL,BH			;GET (BX:DX) EXPONENT
	XOR	AH,AH			;WILL USE 16-BIT ARITHMETIC
	MOV	BL,CH			;TO CALCULATE EXPONENTS
	XOR	BH,BH
	POPF				;SEE IF ADD OR SUBTRACT OF EXPONENTS
	JNB	SES05			;JUMP IF SUBTRACT
	ADD	AX,BX			;HAVE IN TWO BIASES
	SUB	AX,401Q			;NOW HAVE RAW SUM LESS 1
	JMP	SHORT SES07		;GO CHECK FOR OVERFLOW/UNDERFLOW
SES05:	SUB	AX,BX			;BIASES CANCEL OUT
SES07:	OR	AH,AH			;
	JS	SES10			;MUST GO CHECK FOR UNDERFLOW
	CMP	AX,200Q			;CF=0 IF OVERFLOW
	JB	SES20			;PROCEED IF OK
	MOV	BX,SI			;GET (BX) OFF STACK
	ADD	SP,2			;GET $SEXPS RETURN ADDRESS OFF STACK
	JMP	$OVFLS			;GO DO OVERFLOW CODE
SES10:					;POTENTIAL UNDERFLOW
	ADD	AX,200Q			;BIAS MUST BRING IT IN POSITIVE
	JNS	SES30			;IF IT IS POSITIVE PROCEED
	MOV	BX,SI			;BET (BX) OFF STACK
	ADD	SP,2			;GET $SEXPS RETURN ADDRESS OFF STACK
	JMP	$DZERO			;GO ZERO THE FAC AND RETURN
SES20:	ADD	AX,200Q			;ADD IN THE BIAS

SES30:	MOV	[DI].$FAC,AL		;PUT CORRECT EXPONENT IN $FAC

	; MOV	BX,OFFSET $FAC-1	;ADDRESS OF HIGH MANTISSA BITS
	; OR	BYTE PTR 0[BX],LOW 200	;OR IN THE HIDDEN "1"
	OR	[DI].$FAC-1,200Q

	MOV	BX,SI			;GET (BX:DX) HIGH MANTISSA BITS
	XOR	BH,BH			;CLEAR SUPERFLUOUS BITS
	OR	BL,200Q			;RESTORE HIDDEN "1"
	RET
ENDPROC	$SEXPS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $MOVAF
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; MOVE THE $FAC TO $ARG.
;
; Inputs:
;	DI -> SCB_FAC
;
; Outputs:
; 	None
;
; Modifies:
;	None
;
DEFPROC	$MOVAF,DOS
	PUSH	SI
	PUSH	DI
	LEA	SI,[DI].$DFACL
	LEA	DI,[DI].$ARGLO
	MOVSW
	MOVSW
	MOVSW
	MOVSW
	POP	DI
	POP	SI
	RET
ENDPROC	$MOVAF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $MOVAC
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; ROUTINE TO MOVE A DOUBLE PRECISION NO. POINTED TO BY (BX)
; FROM THE CODE SEGMENT TO ARG.
;
; Inputs:
;	DI -> SCB_FAC
;
; Outputs:
; 	BX -> $ARG (word containing top mantissa byte and exponent)
;
; Modifies:
;	BX, CX, SI
;
DEFPROC	$MOVAC,DOS
	MOV	CX,OFFSET $ARGLO
	JMP	SHORT MBF05
ENDPROC	$MOVAC

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $MOVBF
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; THIS ROUTINE IS USED TO MOVE A DOUBLE PRECISION NO. FROM THE CODE SEGMENT
; TO $DBUFF. THE NO. IS POINTED TO BY (BX).
;
; Inputs:
;	BX -> double-precision number
;	DI -> SCB_FAC
;
; Outputs:
; 	BX -> $DBUFF (word containing top mantissa byte and exponent)
;
; Modifies:
;	BX, CX, SI
;
DEFPROC	$MOVBF,DOS
	MOV	CX,OFFSET $DBUFF
MBF05:	PUSH	DI
	ADD	DI,CX
	MOV	SI,BX			;SO WE CAN USE MOVS
	MOVS	WORD PTR ES:[DI],WORD PTR CS:[SI]
	MOVS	WORD PTR ES:[DI],WORD PTR CS:[SI]
	MOVS	WORD PTR ES:[DI],WORD PTR CS:[SI]
	MOVS	WORD PTR ES:[DI],WORD PTR CS:[SI]
	MOV	BX,DI			;UPDATE (BX)
	SUB	BX,2			;GET POINTER CORRECT
	POP	DI
	RET
ENDPROC	$MOVBF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $OVFLS
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; PLACES CORRECT INFINITY IN THE FAC AND PRINTS OVERFLOW MESSAGE.
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$OVFLS,DOS
	RET				;TODO
ENDPROC	$OVFLS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $SETDB
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; MOVE FAC TO DBUFF FOR MULTIPLY AND ZERO FAC.
;
; Inputs:
;	DI -> SCB_FAC
;
; Outputs:
;	AX = CX = 0
;
; Modifies:
;	AX, BX, CX, SI
;
DEFPROC	$SETDB,DOS
	MOV	BX,OFFSET $DBUFF+1
	CALL	$VMVMF			;MOVE FAC TO DBUFF
	PUSH	DI
	LEA	DI,[DI].$DFACL-8	;WILL NOW ZERO 16 BYTES OF FAC
	MOV	CX,8
	XOR	AX,AX
	; CLD
	REP	STOSW			;STORES (AX) INTO LOCATIONS
	POP	DI
	MOV	[DI].$DBUFF,AL		;ZERO OVERFLOW BYTE
	MOV	[DI].$ARGLO-1,AL	;ZERO OVERFLOW BYTE OF ARG
	RET
ENDPROC	$SETDB

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $MOVFA
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; MOVE THE $ARG TO THE FAC.
;
; Inputs:
;	DI -> SCB_FAC
;
DEFPROC	$MOVFA
	PUSH	DI
	LEA	SI,[DI].ARGLO		;"FROM" ADDRESS
	LEA	DI,[DI].$DFACL		;"TO" ADDRESS
	JMP	SHORT MOVEM
ENDPROC	$MOVFA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; $VMVMF
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; MOVE THE FAC TO THE NO. POINTED TO BY (BX).
;
; Inputs:
;	BX = offset of destination SCB_FAC register
;	DI -> SCB_FAC
;
; Modifies:
;	CX, SI
;
; TODO: Determine whether we should also preserve SI.
;
DEFPROC	$VMVMF,DOS
	PUSH	DI
	; XCHG	DI,BX			;(DI)=DESTINATION,(BX)=ORIGIN
	; MOV	BX,OFFSET $DFACL
	LEA	SI,[DI].$DFACL
	LEA	DI,[DI+BX]

	DEFLBL	MOVEM,near		;MOVE NO. POINTED TO BY (BX) TO NO.
					;POINTED TO BY (DI) FOR (CX) WORDS
	; XCHG	BX,SI			;SO MOVW CAN BE USED
	; CLD				;SO MOVW WILL INC
		     			;DO MOVE (CX) TIMES
	; REP	MOVSW			;MOVE "FROM" TO "TO"
	; XCHG	BX,SI			;GET REGISTERS STRAIGHT

	MOVSW				;ASSUME DOUBLE PRECISION
	MOVSW
	MOVSW
	MOVSW
	POP	DI
	RET
ENDPROC	$VMVMF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; itof64
;
; Inputs:
;	DX:AX = 32-bit value
;
; Outputs:
;	ES:DI -> result (in FAC)
;
; Modifies:
;
DEFPROC	itof64,DOS
	ret
ENDPROC itof64

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; div_32_16
;
; Divide DX:AX by CX, returning quotient in DX:AX and remainder in BX.
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	div_32_16
	mov	bx,ax			; save low dividend in BX
	mov	ax,dx			; divide high dividend
	sub	dx,dx			; DX:AX = new dividend
	div	cx			; AX = high quotient
	xchg	ax,bx			; move to BX, restore low dividend
	div	cx			; AX = low quotient
	xchg	dx,bx			; DX:AX = new quotient, BX = remainder
	ret
ENDPROC	div_32_16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; mul_32_16
;
; Multiply DX:AX by CX, returning result in DX:AX.
;
; Modifies:
;	AX, DX
;
DEFPROC	mul_32_16
	push	bx
	mov	bx,dx
	mul	cx			; DX:AX = orig AX * CX
	push	ax			;
	xchg	ax,bx			; AX = orig DX
	mov	bx,dx			; BX:[SP] = orig AX * CX
	mul	cx			; DX:AX = orig DX * CX
	add	ax,bx
	adc	dx,0
	xchg	dx,ax
	pop	ax			; DX:AX = new result
	pop	bx
	ret
ENDPROC	mul_32_16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; TABLE DXX CONTAINS DOUBLE PRECISION POWERS OF TEN FROM -38 TO +38
;
; Adapted from MATH1.ASM, copyright (c) Microsoft Corporation.
;
; 20-May-82 / MLC - Most of the negative powers of ten have been
; removed.  Routines which used to multiply by these negative powers of
; ten have been changed to divide by the corresponding positive power
; of ten.  ($FINE and $FOTNV)
;
	.RADIX	8
$DPM01: DB	315,314,314,314,314,314,114,175 ;10^-01
$DP00:	DB	000,000,000,000,000,000,000,201 ;10^00
$DP01:	DB	000,000,000,000,000,000,040,204 ;10^01
	DB	000,000,000,000,000,000,110,207 ;10^02
	DB	000,000,000,000,000,000,172,212 ;10^03
	DB	000,000,000,000,000,100,034,216 ;10^04
	DB	000,000,000,000,000,120,103,221 ;10^05
$DP06:	DB	000,000,000,000,000,044,164,224 ;10^06
$DP07:	DB	000,000,000,000,200,226,030,230 ;10^07
	DB	000,000,000,000,040,274,076,233 ;10^08
$DP09:	DB	000,000,000,000,050,153,156,236 ;10^09
	DB	000,000,000,000,371,002,025,242 ;10^10
	DB	000,000,000,100,267,103,072,245 ;10^11
	DB	000,000,000,020,245,324,150,250 ;10^12
	DB	000,000,000,052,347,204,021,254 ;10^13
	DB	000,000,200,364,040,346,065,257 ;10^14
	DB	000,000,240,061,251,137,143,262 ;10^15
$DP16:	DB	000,000,004,277,311,033,016,266 ;10^16
	DB	000,000,305,056,274,242,061,271 ;10^17
	DB	000,100,166,072,153,013,136,274 ;10^18
	DB	000,350,211,004,043,307,012,300 ;10^19
	DB	000,142,254,305,353,170,055,303 ;10^20
	DB	200,172,027,267,046,327,130,306 ;10^21
	DB	220,254,156,062,170,206,007,312 ;10^22
	DB	264,127,012,077,026,150,051,315 ;10^23
	DB	241,355,314,316,033,302,123,320 ;10^24
	DB	205,024,100,141,121,131,004,324 ;10^25
	DB	246,031,220,271,245,157,045,327 ;10^26
	DB	017,040,364,047,217,313,116,332 ;10^27
	DB	012,224,370,170,071,077,001,336 ;10^28
	DB	014,271,066,327,007,217,041,341 ;10^29
	DB	117,147,004,315,311,362,111,344 ;10^30
	DB	043,201,105,100,174,157,174,347 ;10^31
	DB	266,160,053,250,255,305,035,353 ;10^32
	DB	343,114,066,022,031,067,105,356 ;10^33
	DB	034,340,303,126,337,204,166,361 ;10^34
	DB	021,154,072,226,013,023,032,365 ;10^35
	DB	026,007,311,173,316,227,100,370 ;10^36
	DB	333,110,273,032,302,275,160,373 ;10^37
	DB	211,015,265,120,231,166,026,377 ;10^38
$DHALF:	DB	000			;DOUBLE PRECISION .5D00
	DB	000
	DB	000
	DB	000
$SHALF:	DB	000			;SINGLE PRECISION .5E00
	DB	000
	DB	000
	DB	200
$SQRH:	DB	361			;SQR(.5)
	DB	004
	DB	065
	DB	200
;
; FOR LOG CALCULATIONS HART ALGORITHM 2524 WILL BE USED
; IN THIS ALGORITHM WE WILL CALCULATE BASE 2 LOG AS FOLLOWS
; LOG(X)=P(X)/Q(X)
;
$LOGP:	DB	4
	DB	232			;4.8114746
	DB	367
	DB	031
	DB	203
	DB	044			;6.105852
	DB	143
	DB	103
	DB	203
	DB	165			;-8.86266
	DB	315
	DB	215
	DB	204
	DB	251			;-2.054667
	DB	177
	DB	203
	DB	202
$LOGQ:	DB	4
	DB	000			;1.
	DB	000
	DB	000
	DB	201
	DB	342			;6.427842
	DB	260
	DB	115
	DB	203
	DB	012			;4.545171
	DB	162
	DB	021
	DB	203
	DB	364			;.3535534
	DB	004
	DB	065
	DB	177
$LN2:	DB	030			;LOG BASE E OF 2.0
	DB	162
	DB	061
	DB	200
	.RADIX	10

DOS	ends

	end
