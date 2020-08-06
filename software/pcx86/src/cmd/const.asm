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
	EXTERNS	<evalAdd32,evalSub32>,near
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
; and 3) the operator evaluator. 
;
	DEFLBL	OPDEFS,byte
	OPDEF	<'+',4,evalAdd32>
	OPDEF	<'-',4,evalSub32>
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
	DEFWORD	segCode,0	; code block
	DEFWORD	segVars,0	; var block
	DEFWORD	segData,0	; data block
	DEFWORD	segText,0	; text block
	COMHEAP	<size CMD_HEAP>	; COMHEAP (heap size) must be the last item
DATA	ENDS

	end
