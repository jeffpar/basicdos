;
; BASIC-DOS Command Interpreter Constants
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	txt.inc

CODE    SEGMENT

	EXTERNS	<cmdDate,cmdDir,cmdExit,cmdHelp,cmdKeys,cmdList,cmdLoad>,near
	EXTERNS	<cmdMem,cmdNew,cmdRun,cmdRestart,cmdTime,cmdType,cmdVer>,near
	EXTERNS	<genCLS,genColor,genDefFn,genDefInt,genDefDbl,genDefStr>,near
	EXTERNS	<genEcho,genGoto,genIf,genLet,genPrint,genReturn>,near
	EXTERNS	<evalNegLong,evalNotLong>,near
	EXTERNS	<evalAddLong,evalSubLong,evalMulLong,evalDivLong>,near
	EXTERNS	<evalModLong,evalExpLong,evalImpLong>,near
	EXTERNS	<evalEqvLong,evalXorLong,evalOrLong,evalAndLong>,near
	EXTERNS	<evalEQLong,evalNELong,evalLTLong,evalGTLong>,near
	EXTERNS	<evalLELong,evalGELong,evalShlLong,evalShrLong>,near
	EXTERNS	<fnRndLong>,near

	EXTERNS	<evalEQStr,evalNEStr,evalLTStr,evalGTStr>,near
	EXTERNS	<evalLEStr,evalGEStr,evalAddStr>,near

	DEFSTR	COM_EXT,<".COM",0>	; these 4 file extensions must be
	DEFSTR	EXE_EXT,<".EXE",0>	; listed in the desired search order
	DEFSTR	BAT_EXT,<".BAT",0>
	DEFSTR	BAS_EXT,<".BAS",0>

	DEFSTR	DIR_DEF,<"*.*",0>
	DEFSTR	PERIOD,<".",0>
	DEFSTR	STD_VER,<0>
	DEFSTR	DBG_VER,<"DEBUG",0>
	DEFSTR	HELP_FILE,<"COMMAND.TXT",0>

	IFDEF	DEBUG
	DEFSTR	SYS_MEM,<"<SYS>",0>
	DEFSTR	DOS_MEM,<"<DOS>",0>
	DEFSTR	FREE_MEM,<"<FREE>",0>
	ENDIF	; DEBUG
;
; Table of BASIC-DOS expression operators
;
; Each OPDEF structure contains 1) operator symbol, 2) operator precedence,
; and 3) operator evaluators (currently, only one LONG evaluator is present
; for each operator).  Although the operators are listed in order of highest
; to lowest precedence, it's the operator precedence field that actually
; determines an operator's priority.
;
; Most operators are "binary ops" (ie, operators that require 2 stack-based
; arguments).  Exceptions include 3 "unary ops": unary -, unary +, and NOT,
; all of which are distinguished by an ODD precedence.
;
; Parentheses are another exception; they may appear to have low precedence,
; but that's just to ensure that when we encounter a closing parenthesis, all
; operators with a precedence higher than the opening parenthesis get popped.
;
; Note that all multi-character operators are converted to single character
; operators internally, to simplify operator management; genExpr takes care
; of any keyword operators listed in the KEYOP_TOKENS table, and validateOp
; takes care of any any multi-symbol operators listed in the RELOPS table.
;
; We've also taken some liberties with the language, by allowing '~' and '|'
; in addition to 'NOT' and 'OR', allowing '==' in addition to '=', and by
; adding '>>' and '<<' arithmetic shift operations.  It would have been nice
; to allow '&' in place of 'AND' as well, but unfortunately '&' was already
; used to prefix hex and octal constants.
;
; TODO: Speaking of hex and octal constants, maybe someday we'll also allow
; "0x" and "0o" prefixes, and maybe even a C-inspired version of PRINT USING
; called... drum roll... PRINTF USING.
;
	DEFLBL	OPDEFS_LONG,byte
	OPDEF	<'(',2,0>
	OPDEF	<')',2,0>
	OPDEF	<'^',26,evalExpLong>
	OPDEF	<'P',25,0>		; unary '+'
	OPDEF	<'N',25,evalNegLong>	; unary '-'
	OPDEF	<'*',24,evalMulLong>
	OPDEF	<'/',24,evalDivLong>
	OPDEF	<'\',22,evalDivLong>
	OPDEF	<'M',20,evalModLong>	; 'MOD'
	OPDEF	<'+',18,evalAddLong>
	OPDEF	<'-',18,evalSubLong>
	OPDEF	<'S',16,evalShlLong>	; BASIC-DOS: '<<'
	OPDEF	<'R',16,evalShrLong>	; BASIC-DOS: '>>'
	OPDEF	<'=',14,evalEQLong>	; BASIC-DOS allows '==' as well
	OPDEF	<'U',14,evalNELong>	; '<>' or '><'
	OPDEF	<'<',14,evalLTLong>
	OPDEF	<'>',14,evalGTLong>
	OPDEF	<'L',14,evalLELong>	; '<=' or '=<'
	OPDEF	<'G',14,evalGELong>	; '>=' or '=>'
	OPDEF	<'~',13,evalNotLong>	; 'NOT' (BASIC-DOS allows '~' as well)
	OPDEF	<'A',12,evalAndLong>	; 'AND'
	OPDEF	<'|',10,evalOrLong>	; 'OR'  (BASIC-DOS allows '|' as well)
	OPDEF	<'X',8,evalXorLong>	; 'XOR'
	OPDEF	<'E',6,evalEqvLong>	; 'EQV'
	OPDEF	<'I',4,evalImpLong>	; 'IMP'
	db	0			; terminator

	DEFLBL	OPDEFS_STR,byte
	OPDEF	<'(',2,0>
	OPDEF	<')',2,0>
	OPDEF	<'+',18,evalAddStr>
	OPDEF	<'=',14,evalEQStr>	; BASIC-DOS allows '==' as well
	OPDEF	<'U',14,evalNEStr>	; '<>' or '><'
	OPDEF	<'<',14,evalLTStr>
	OPDEF	<'>',14,evalGTStr>
	OPDEF	<'L',14,evalLEStr>	; '<=' or '=<'
	OPDEF	<'G',14,evalGEStr>	; '>=' or '=>'
	db	0			; terminator

	DEFLBL	RELOPS,byte
	db	"<>",'U',"><",'U',"<=",'L',"=<",'L',">=",'G',"=>",'G'
	db	"==",'=',"<<",'S',">>",'R'
	db	0			; terminator

	DEFLBL	PREDEF_VARS,byte
	db	VAR_LONG + 6,"MAXINT"	; TODO: Should this be "MAXINT%"?
	dd	7FFFFFFFh		; largest positive value
	db	VAR_FUNC + 4,"RND%"
	db	VAR_LONG,1		; returns VAR_LONG with 1 parameter
	db	VAR_LONG,PARM_OPT_ONE	; 1st parameter: VAR_LONG, optional
	dw	offset fnRndLong,0	; 0 implies our own CODE segment
	db	0			; terminator

	DEFLBL	PREDEF_ZERO,byte
	db	VAR_LONG
	dd	0			; predefined LONG zero constant

CODE	ENDS

	DEFTOKENS KEYWORD_TOKENS,KEYWORD_TOTAL
	DEFTOK	CLS,    60, genCLS
	DEFTOK	COLOR,  61, genColor
	DEFTOK	DATE,   40, cmdDate
	DEFTOK	DEF,    62, genDefFn
	DEFTOK	DEFDBL, 63, genDefDbl
	DEFTOK	DEFINT, 64, genDefInt
	DEFTOK	DEFSNG, 65, genDefDbl
	DEFTOK	DEFSTR, 66, genDefStr
	DEFTOK	DIR,    20, cmdDir
	DEFTOK	ECHO,   67, genEcho
	DEFTOK	ELSE,  201
	DEFTOK	EXIT,    1, cmdExit
	DEFTOK	GOTO,   68, genGoto
	DEFTOK	HELP,   41, cmdHelp
	DEFTOK	IF,     69  genIf
	DEFTOK	KEYS,    2, cmdKeys
	DEFTOK	LET,    70, genLet
	DEFTOK	LIST,    3, cmdList
	DEFTOK	LOAD,   21, cmdLoad
	DEFTOK	MEM,    42, cmdMem
	DEFTOK	NEW,     4, cmdNew
	DEFTOK	OFF,   202
	DEFTOK	ON,    203
	DEFTOK	PRINT,  71, genPrint
	DEFTOK	REM,    72
	DEFTOK	RESTART, 5, cmdRestart
	DEFTOK	RETURN, 73, genReturn
	DEFTOK	RUN,     6, cmdRun
	DEFTOK	THEN,  204
	DEFTOK	TIME,   43, cmdTime
	DEFTOK	TYPE,   22, cmdType
	DEFTOK	VER,    44, cmdVer
	NUMTOKENS KEYWORD_TOKENS,KEYWORD_TOTAL

	DEFTOKENS KEYOP_TOKENS,KEYOP_TOTAL
	DEFTOK	AND,   'A'
	DEFTOK	EQV,   'E'
	DEFTOK	IMP,   'I'
	DEFTOK	MOD,   'M'
	DEFTOK	NOT,   '~'
	DEFTOK	OR,    '|'
	DEFTOK	XOR,   'X'
	NUMTOKENS KEYOP_TOKENS,KEYOP_TOTAL

DATA	SEGMENT
;
; This is where non-constant data begins; it must be at the end of the file.
;
	DEFLBL	BEG_HEAP,word
	BLKDEF	<0,CBLKLEN,size CBLK,SIG_CBLK>
	BLKDEF	<0,FBLKLEN,size FBLK,SIG_FBLK>
	BLKDEF	<0,VBLKLEN,size VBLK,SIG_VBLK>
	BLKDEF	<0,SBLKLEN,size SBLK,SIG_SBLK>
	BLKDEF	<0,TBLKLEN,size TBLK,SIG_TBLK>
	COMHEAP	<size CMD_HEAP>,BEG_HEAP	; this must be the last item...

DATA	ENDS

	end
