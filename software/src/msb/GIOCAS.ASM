; [ This translation created 10-Feb-83 by Version 4.3 ]

	.RADIX  8		; To be safe

CSEG	SEGMENT PUBLIC 'CODESG'
	ASSUME  CS:CSEG

INCLUDE	OEM.INC

	TITLE   GIOCAS - Cassette Machine Independent Device Driver Code

COMMENT	*

--------- --- ---- -- ---------
COPYRIGHT (C) 1981 BY MICROSOFT
--------- --- ---- -- ---------

Written by:     Len Oorthuys

        *
	INCLUDE	GIO86U.INC
	INCLUDE	MSDOSU.INC
	.SALL


	EXTRN	DERDNA:NEAR
PUBLIC	MOTOR
MOTOR:	JMP	DERDNA		;Device unavailable error


CSEG	ENDS
	END
