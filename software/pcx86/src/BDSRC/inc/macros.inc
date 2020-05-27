PCJS_MULTIPLIER EQU 16

FARPTR	struc
off	dw	?
seg	dw	?
FARPTR	ends

ERROR	macro	msg
	IF1
	%out 	msg
	ENDIF
	.ERROR
	endm

ASSERT	macro	v1,op,v2
	IFE	v1 op v2
	ERROR	<Assertion failed: v1 op v2>
	IF1
	%out
	ENDIF
	ENDIF
	endm
