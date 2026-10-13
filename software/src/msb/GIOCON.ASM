; [ This translation created 10-Feb-83 by Version 4.3 ]

	.RADIX  8		; To be safe

CSEG	SEGMENT PUBLIC 'CODESG'
	ASSUME  CS:CSEG

INCLUDE	OEM.INC

	TITLE   GIOCON - Machine Independent CONS: Device Support

COMMENT	*

--------- --- ---- -- ---------
COPYRIGHT (C) 1982 BY MICROSOFT
--------- --- ---- -- ---------

        *
	INCLUDE	GIO86U.INC
	.SALL

CPM86=0				;CPM86

;This module becomes NULL if CONSSW is 0
;
	INCLUDE	MSDOSU.INC	;MSDOS Constant Definitions



	PUBLIC	CONDSP,_RET,CONSOT

	EXTRN	DERBFM:NEAR,PDCBAX:NEAR
	EXTRN	DEVBOT:NEAR,DEVBIN:NEAR

	PAGE
	SUBTTL  CONS (Raw-CRT output Dispatch Table and Routines)

;Console Dispatch Table
;
CONDSP:
	DW	(DERBFM)	;test EOF for file opened to this device
	DW	(DERBFM)	;LOC
	DW	(DERBFM)	;LOF
	DW	(_RET)		;perform special CLOSE functions for this device
	DW	(DERBFM)	;set device width
	DW	(DERBFM)	;GET/PUT random record from/to this device
	DW	(CONOPN)	;perform special OPEN functions for this device
	DW	(DERBFM)	;input 1 byte from file opened on this device
	DW	(CONSOT)	;output 1 byte to file opened on this device
	DW	(CONGPS)	;POS
	DW	(CONGWD)	;get device width
	DW	(_RET)		;set device comma width
	DW	(_RET)		;get device comma width
	DW	(DEVBIN)	;block input from file opened on this device
	DW	(DEVBOT)	;block output to file opened on this device

;CONOPN - perform any device dependent open functions.
; Entry - [AL]=  device id
;                0 if default device,
;                1..n for Disk A:, B:, ...
;                -1..-n for non-disk devices
;         [BX] = file number (0..n)
;         [CX] = random record size if [FILMOD] = random
;                (if [CX] = 0, use default record size)
;         [DI] = device offset (2=SCND, 4=SCRN, etc.)
;         [FILMOD] = file mode
;                    MD.SQI = 1 ;sequential input
;                    MD.SQO = 2 ;sequential output
;                    MD.RND = 3 ;random
;                    MD.APP = 4 ;append
;         [FILNAM] = filename
;         [FILEXT] = 1..3 byte filename extension
; Exit  - [SI] points to new FDB
;         FDB is linked into FDB chain with all standard
;         fields initialized.
;         All other registers are preserved.
;

	EXTRN	INIFDB:NEAR

CONOPN:
	MOV	AH,LOW OFFSET MD_SQO	;allow open for output only
	MOV	DX,255D		;initial file column position=0
				;initial file width=255
	JMP	INIFDB

;CONGPS - return current file position.
; Entry - SI points to File-Data-Block.
; Exit  - [AH] = current file column. (0-relative)
;         All other registers preserved
;
CONGPS:	MOV	AH,LOW 0
_RET:	RET

;CONGWD - get device width
; Exit  - [AH] = device width as set by xxxSWD
;         All other registers preserved
;
CONGWD:
	MOV	AH,LOW 255D	;infinite width
	RET

;CONSOT - Write one byte to the console.
;
;ENTRY  - AL = Character to output
;EXIT   - All registers except SI and DI are preserved.
;
CONSOT:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	CMP	AL,LOW 255D
	JZ	CONSOX		;Don't allow outputing FFH
	MOV	DL,AL
	CALLOS	C_DCIO		;Direct Console I/O
CONSOX:	JMP	PDCBAX		;Pop DX,CX,BX,AX and RET

CSEG	ENDS
	END
