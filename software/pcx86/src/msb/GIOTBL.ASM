; [ This translation created 10-Feb-83 by Version 4.3 ]

	.RADIX  8		; To be safe

CSEG	SEGMENT PUBLIC 'CODESG'
	ASSUME  CS:CSEG

INCLUDE	OEM.INC

	TITLE   GIOTBL - Device Name Table, Dispatch Table Address Tables
;                Initialization and Termination Dispatch Tables

COMMENT	*

--------- --- ---- -- ---------
COPYRIGHT (C) 1982 BY MICROSOFT
--------- --- ---- -- ---------

        *
	INCLUDE	GIO86U.INC
	.SALL

	INCLUDE	MSDOSU.INC	;MSDOS Constant Definitions
IF	CPM86
	INCLUDE	CPM86U.INC	;CPM86 Constant Definitions
ENDIF

	.RADIX	10

CPM86=0				;CPM86

;Device Switches


	PUBLIC	_DVTBL,_DVPTR,_DVINI,_DVTRM,$_NDEV

	EXTRN	DSKDSP:NEAR
	EXTRN	KYBDSP:NEAR,KYBINI:NEAR,KYBTRM:NEAR
	EXTRN	SCNDSP:NEAR,SCNINI:NEAR,SCNTRM:NEAR
	EXTRN	LPTDSP:NEAR,LPTINI:NEAR,LPTTRM:NEAR
	EXTRN	COMDSP:NEAR,COMINI:NEAR,COMTRM:NEAR
	EXTRN	CONDSP:NEAR,_RET:NEAR
	PAGE
	SUBTTL  Device name table

;*****************************************************************
;***                                                            ***
;***  Note:                                                     ***
;***    When adding additional devices, be sure to update       ***
;***    OEMRAM to add device control blocks if necessary.       ***
;***    Change $1STSD and $LSTSD if necessary.  Change NMCOMT   ***
;***    in switch file if adding COM device.                    ***
;***                                                            ***
;******************************************************************

NDEV	MACRO	NAM,DSPADR,INIADR,TRMADR,N
	DEV	NAM&N,DSPADR,INIADR,TRMADR
ENDM

NAMES	MACRO
	DEV	KYBD,KYBDSP,KYBINI,KYBTRM	;Keyboard
	DEV	SCRN,SCNDSP,SCNINI,SCNTRM	;Crt
	DEV	CONS,CONDSP,_RET,_RET	;Raw-I/O Crt (Esc Sequences)
	NLPT=0
REPT	NMLPT
	NLPT=NLPT+1
	NDEV	LPT,LPTDSP,LPTINI,LPTTRM,%NLPT	;Line printer
ENDM
	NCAS=0
REPT	GWCASS
	NCAS=NCAS+1
	NDEV	CAS,CASDSP,CASINI,CASTRM,%NCAS	;Line printer
ENDM
	NCOM=0
REPT	NMCOMT
	NCOM=NCOM+1
	NDEV	COM,COMDSP,COMINI,COMTRM,%NCOM	;COM channel NCOM
ENDM
ENDM


;Generate DEVTBL ( text followed by device # )
;
	NUM=377O
DEV	MACRO	NAM,DSPADR,INIADR,TRMADR
	PUBLIC	$_&NAM
	$_&NAM=NUM
        DB      "&NAM&"
	DB	OFFSET NUM
	NUM=NUM-1
ENDM
_DVTBL:
	NAMES
	DB	0		;0 ends table

	$_NDEV=377O-NUM		;number of non-disk Devices

;Generate DEVPTR ( Addresses of dispatch tables )
;
DEV	MACRO	NAM,DSPADR,INIADR,TRMADR
	DW	OFFSET DSPADR
ENDM
_DVPTR:
	DW	(DSKDSP)	;1st entry in dispatch table is Disk Dispatch table
	NAMES			;then 1 entry for each device

;Generate Initialization Dispatch table
;
DEV	MACRO	NAM,DSPADR,INIADR,TRMADR
	DW	OFFSET INIADR
ENDM
_DVINI:
	NAMES			;address of initialization routine for each device

;Generate Termination Dispatch table
;
DEV	MACRO	NAM,DSPADR,INIADR,TRMADR
	DW	OFFSET TRMADR
ENDM
_DVTRM:
	NAMES			;address of termination routine for each device

CSEG	ENDS
	END
