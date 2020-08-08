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
	EXTERNS	<cmdCLS,cmdDate,CmdDir,cmdExit,cmdLoop,cmdMem>,near
	EXTERNS	<cmdTime,cmdType>,near
	EXTERNS	<genColor,genLet,genPrint>,near
	EXTERNS	<evalAddLong,evalSubLong,evalMulLong,evalDivLong>,near
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
; Each OPDEF contains 1) the operator symbol, 2) the operator precedence,
; and 3) the operator evaluators (for INT, LONG, SINGLE, DOUBLE, etc).
;
	DEFLBL	OPDEFS,byte
	OPDEF	<'+',1,evalAddLong>
	OPDEF	<'-',1,evalSubLong>
	OPDEF	<'*',4,evalMulLong>
	OPDEF	<'/',4,evalDivLong>
	DEFBYTE	OPDEFS_END,0

CODE	ENDS

	DEFTOKENS CMD_TOKENS,NUM_TOKENS
	DEFTOK	TOK_CLS,    1, "CLS",	cmdCLS	; TODO: will become genCLS
	DEFTOK	TOK_COLOR, 21, "COLOR",	genColor
	DEFTOK	TOK_DATE,   2, "DATE",	cmdDate
	DEFTOK	TOK_DIR,   11, "DIR",	cmdDir
	DEFTOK	TOK_EXIT,   3, "EXIT",	cmdExit
	DEFTOK	TOK_LET,   22, "LET",	genLet
	DEFTOK	TOK_LOOP,  12, "LOOP",	cmdLoop
	DEFTOK	TOK_MEM,    4, "MEM",	cmdMem
	DEFTOK	TOK_PRINT, 23, "PRINT",	genPrint
	DEFTOK	TOK_TIME,   5, "TIME",	cmdTime
	DEFTOK	TOK_TYPE,  13, "TYPE",	cmdType
	NUMTOKENS CMD_TOKENS,NUM_TOKENS

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
