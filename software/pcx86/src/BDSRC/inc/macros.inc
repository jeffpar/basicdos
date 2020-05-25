PCJS_MULTIPLIER	EQU	8

FARPTR	struc
off	dw	?
seg	dw	?
FARPTR	ends

ASSERTEQ	macro	v1,v2
		IFE	v1 EQ v2
		IF1
		%out	v1 NE v2
		ENDIF
		ENDIF
		endm
