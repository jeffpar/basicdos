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
	EXTERNS	<parseColor,parseExpr>,near
	DEFSTR	COM_EXT,<".COM",0>
	DEFSTR	EXE_EXT,<".EXE",0>
	DEFSTR	DIR_DEF,<"*.*",0>
	DEFSTR	PERIOD,<".",0>
	DEFSTR	RES_MEM,<"RESERVED",0>
	DEFSTR	SYS_MEM,<"SYSTEM",0>
	DEFSTR	DOS_MEM,<"DOS",0>
CODE	ENDS

	DEFTOKENS CMD_TOKENS,NUM_TOKENS
	DEFTOK	TOK_CLS,   20, "CLS",	cmdCLS
	DEFTOK	TOK_COLOR, 21, "COLOR",	parseColor
	DEFTOK	TOK_DATE,   1, "DATE",	cmdDate
	DEFTOK	TOK_DIR,   11, "DIR",	cmdDir
	DEFTOK	TOK_EXIT,   2, "EXIT",	cmdExit
	DEFTOK	TOK_LOOP,  12, "LOOP",	cmdLoop
	DEFTOK	TOK_MEM,    3, "MEM",	cmdMem
	DEFTOK	TOK_PRINT, 22, "PRINT",	parseExpr
	DEFTOK	TOK_TIME,   4, "TIME",	cmdTime
	DEFTOK	TOK_TYPE,  13, "TYPE",	cmdType
	NUMTOKENS CMD_TOKENS,NUM_TOKENS

DATA	SEGMENT
	COMHEAP	<size CMD_WS>	; COMHEAP (heap size) must be the last item
DATA	ENDS

	end
