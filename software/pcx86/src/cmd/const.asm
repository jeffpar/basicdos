;
; BASIC-DOS Command Interpreter Constants
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT
	EXTERNS	<cmdCLS,cmdDate,CmdDir,cmdExit,cmdMem>,near
	EXTERNS	<cmdTime,cmdType>,near
	EXTERNS	<genColor,genLet,genPrint>,near
	EXTERNS	<evalExpLong>,near
	EXTERNS	<evalAddLong,evalSubLong,evalMulLong,evalDivLong>,near
	EXTERNS	<evalModLong,evalNegLong,evalNotLong,evalImpLong>,near
	EXTERNS	<evalEqvLong,evalXorLong,evalOrLong,evalAndLong>,near
	EXTERNS	<evalEQLong,evalNELong,evalLTLong>,near
	EXTERNS	<evalGTLong,evalLELong,evalGELong>,near
	DEFSTR	COM_EXT,<".COM",0>
	DEFSTR	EXE_EXT,<".EXE",0>
	DEFSTR	DIR_DEF,<"*.*",0>
	DEFSTR	PERIOD,<".",0>
	DEFSTR	SYS_MEM,<"<SYS>",0>
	DEFSTR	DOS_MEM,<"DOS",0>
	DEFSTR	FREE_MEM,<"<FREE>",0>
;
; Table of operators
;
; Each OPDEF contains 1) an operator symbol, 2) the operator precedence,
; 3) number of args, and 4) operator evaluators (for INT, LONG, SINGLE, etc).
;
; Note that some of the operator symbols are internal only; the getKeywordOp
; function will convert reserved operator keywords to the corresponding
; character symbol in this table.
;
	DEFLBL	OPDEFS,byte
	OPDEF	<'(',1,0,0>
	OPDEF	<')',1,0,0>
	OPDEF	<'I',2,2,evalImpLong>	; 'IMP'
	OPDEF	<'E',3,2,evalEqvLong>	; 'EQV'
	OPDEF	<'X',4,2,evalXorLong>	; 'XOR'
	OPDEF	<'|',5,2,evalOrLong>	; 'OR'
	OPDEF	<'&',6,2,evalAndLong>	; 'AND'
	OPDEF	<'~',7,1,evalNotLong>	; 'NOT'
	OPDEF	<'=',8,2,evalEQLong>
	OPDEF	<'!',8,2,evalNELong>	; '<>' or '><'
	OPDEF	<'<',8,2,evalLTLong>
	OPDEF	<'>',8,2,evalGTLong>
	OPDEF	<'L',8,2,evalLELong>	; '<=' or '=<'
	OPDEF	<'G',8,2,evalGELong>	; '>=' or '=>'
	OPDEF	<'+',9,2,evalAddLong>
	OPDEF	<'-',9,2,evalSubLong>
	OPDEF	<'%',10,2,evalModLong>	; 'MOD'
	OPDEF	<'\',11,2,evalDivLong>
	OPDEF	<'*',12,2,evalMulLong>
	OPDEF	<'/',12,2,evalDivLong>
	OPDEF	<'P',13,1,0>		; unary '+'
	OPDEF	<'N',13,1,evalNegLong>	; unary '-'
	OPDEF	<'^',14,2,evalExpLong>
	DEFBYTE	OPDEFS_END,0

CODE	ENDS

	DEFTOKENS CMD_TOKENS,CMD_TOTAL
	DEFTOK	TOK_CLS,    1, "CLS",	cmdCLS	; TODO: will become genCLS
	DEFTOK	TOK_COLOR, 21, "COLOR",	genColor
	DEFTOK	TOK_DATE,   2, "DATE",	cmdDate
	DEFTOK	TOK_DIR,   11, "DIR",	cmdDir
	DEFTOK	TOK_EXIT,   3, "EXIT",	cmdExit
	DEFTOK	TOK_LET,   22, "LET",	genLet
	DEFTOK	TOK_MEM,    4, "MEM",	cmdMem
	DEFTOK	TOK_PRINT, 23, "PRINT",	genPrint
	DEFTOK	TOK_TIME,   5, "TIME",	cmdTime
	DEFTOK	TOK_TYPE,  12, "TYPE",	cmdType
	NUMTOKENS CMD_TOKENS,CMD_TOTAL

	DEFTOKENS KEYOP_TOKENS,KEYOP_TOTAL
	DEFTOK	TOK_AND,  '&', "AND"
	DEFTOK	TOK_EQV,  'E', "EQV"
	DEFTOK	TOK_IMP,  'I', "IMP"
	DEFTOK	TOK_MOD,  '%', "MOD"
	DEFTOK	TOK_NOT,  '~', "NOT"
	DEFTOK	TOK_OR,   '|', "OR"
	DEFTOK	TOK_XOR,  'X', "XOR"
	NUMTOKENS KEYOP_TOKENS,KEYOP_TOTAL

DATA	SEGMENT
	DEFWORD	segCode,0	; first code block
	db	size CBLK_HDR,CBLKSIG
	DEFWORD	segVars,0	; first var block
	db	size VBLK_HDR,VBLKSIG
	DEFWORD	segStrs,0	; first string block
	db	size SBLK_HDR,SBLKSIG
	DEFWORD	segText,0	; first text block
	dw	size CBLK_HDR,CBLKSIG
	COMHEAP	<size CMD_HEAP>	; COMHEAP (heap size) must be the last item
DATA	ENDS

	end
