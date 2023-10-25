;
; BASIC-DOS Command Interpreter Constants
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc
	include	txt.inc

CODE    SEGMENT

	EXTNEAR	<evalNegLong,evalNotLong>
	EXTNEAR	<evalAddLong,evalSubLong,evalMulLong,evalDivLong>
	EXTNEAR	<evalModLong,evalExpLong,evalImpLong>
	EXTNEAR	<evalEqvLong,evalXorLong,evalOrLong,evalAndLong>
	EXTNEAR	<evalEQLong,evalNELong,evalLTLong,evalGTLong>
	EXTNEAR	<evalLELong,evalGELong,evalShlLong,evalShrLong>

	EXTNEAR	<evalAddStr>
	EXTNEAR	<evalEQStr,evalNEStr,evalLTStr,evalGTStr,evalLEStr,evalGEStr>

	EXTNEAR	<getErrorLevel,getRndLong>

	DEFSTR	COM_EXT,<".COM",0>	; these 4 file extensions must be
	DEFSTR	EXE_EXT,<".EXE",0>	; listed in the desired search order
	DEFSTR	BAT_EXT,<".BAT",0>
	DEFSTR	BAS_EXT,<".BAS",0>

	DEFSTR	DIR_DEF,<"*.*",0>
	DEFSTR	PERIOD,<".",0>
	DEFSTR	VER_DEBUG,<" DEBUG">
	DEFSTR	VER_FINAL,<0,0>
	DEFSTR	HELP_FILE,<"HELP.TXT",0>
	DEFSTR	PIPE_NAME,<"PIPE$",0>
	DEFSTR	STR_ON,<"ON",0>
	DEFSTR	STR_OFF,<"OFF",0>

	IFDEF	DEBUG
	DEFSTR	SYS_MEM,<"<SYS>",0>
	DEFSTR	DOS_MEM,<"<DOS>",0>
	DEFSTR	BLK_NAMES,<"<CODE>",0,0,"<FUNC>",0,0,"<VAR>",0,"<STR>",0,"<TEXT>",0,0>
	DEFABS	BLK_WORDS,<(($ - BLK_NAMES) SHR 1)>
	DEFSTR	BLK_UNKNOWN,<"<UNK>",0>
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
; TODO: Determine what parser change impacted the ability to use '~' and '|'
; as alternative operators, because they no longer work (and, for example, a
; command such as "PRINT 1~4" now prints "1" instead of generating an error).
;
; TODO: Speaking of hex and octal constants, maybe someday we'll also allow
; "0x" and "0o" prefixes, and maybe even a C-inspired version of PRINT USING
; called... drum roll... PRINTF USING.
;
	DEFLBL	OPDEFS,byte
	OPDEF	<'(',2,0>
	OPDEF	<')',2,0>
	OPDEF	<'^',28,OPEVAL_EXP>
	OPDEF	<'P',27,0>		; unary '+'
	OPDEF	<'N',27,OPEVAL_NEG>	; unary '-'
	OPDEF	<'*',26,OPEVAL_MUL>
	OPDEF	<'/',26,OPEVAL_DIV>
	OPDEF	<'\',24,OPEVAL_IDIV>
	OPDEF	<'M',22,OPEVAL_MOD>	; 'MOD'
	OPDEF	<'+',20,OPEVAL_ADD>
	OPDEF	<'-',20,OPEVAL_SUB>
	OPDEF	<'S',16,OPEVAL_SHL>	; BASIC-DOS: '<<'
	OPDEF	<'R',16,OPEVAL_SHR>	; BASIC-DOS: '>>'
	OPDEF	<'=',14,OPEVAL_EQ>	; (BASIC-DOS allows '==' as well)
	OPDEF	<'U',14,OPEVAL_NE>	; '<>' or '><'
	OPDEF	<'<',14,OPEVAL_LT>
	OPDEF	<'>',14,OPEVAL_GT>
	OPDEF	<'L',14,OPEVAL_LE>	; '<=' or '=<'
	OPDEF	<'G',14,OPEVAL_GE>	; '>=' or '=>'
	OPDEF	<'~',13,OPEVAL_NOT>	; 'NOT' (BASIC-DOS allows '~' as well)
	OPDEF	<'A',12,OPEVAL_AND>	; 'AND'
	OPDEF	<'|',10,OPEVAL_OR>	; 'OR'  (BASIC-DOS allows '|' as well)
	OPDEF	<'X',8,OPEVAL_XOR>	; 'XOR'
	OPDEF	<'E',6,OPEVAL_EQV>	; 'EQV'
	OPDEF	<'I',4,OPEVAL_IMP>	; 'IMP'
	db	0			; terminator

	DEFLBL	EVAL_LONG,word
	dw	evalNegLong
	dw	evalExpLong
	dw	evalMulLong
	dw	evalDivLong
	dw	evalAddLong
	dw	evalSubLong
	dw	evalEQLong
	dw	evalNELong
	dw	evalLTLong
	dw	evalGTLong
	dw	evalLELong
	dw	evalGELong
	dw	evalNotLong
	dw	evalDivLong
	dw	evalModLong
	dw	evalShlLong
	dw	evalShrLong
	dw	evalAndLong
	dw	evalOrLong
	dw	evalXorLong
	dw	evalEqvLong
	dw	evalImpLong

	DEFLBL	EVAL_DOUBLE,word
	dw	0 ; evalNegDouble
	dw	0 ; evalExpDouble
	dw	0 ; evalMulDouble
	dw	0 ; evalDivDouble
	dw	0 ; evalAddDouble
	dw	0 ; evalSubDouble
	dw	0 ; evalEQDouble
	dw	0 ; evalNEDouble
	dw	0 ; evalLTDouble
	dw	0 ; evalGTDouble
	dw	0 ; evalLEDouble
	dw	0 ; evalGEDouble
	dw	0
	dw	0
	dw	0
	dw	0
	dw	0
	dw	0
	dw	0
	dw	0
	dw	0
	dw	0

	DEFLBL	EVAL_STR,word
	dw	0,0,0,0,evalAddStr,0
	dw	evalEQStr
	dw	evalNEStr
	dw	evalLTStr
	dw	evalGTStr
	dw	evalLEStr
	dw	evalGEStr
	dw	0,0,0,0,0,0,0,0,0,0

	DEFLBL	RELOPS,byte
	db	"<>",'U',"><",'U',"<=",'L',"=<",'L',">=",'G',"=>",'G'
	db	"==",'=',"<<",'S',">>",'R'
	db	0			; terminator

	DEFLBL	PREDEF_VARS,byte
	db	VAR_FUNC + 10,"ERRORLEVEL"
	db	VAR_LONG,0		; returns VAR_LONG with 0 parameters
	dw	offset getErrorLevel,0	; 0 implies our own CODE segment
	db	VAR_LONG + 6,"MAXINT"	; TODO: Should this be "MAXINT%"?
	dd	7FFFFFFFh		; largest positive value
	db	VAR_FUNC + 4,"RND%"
	db	VAR_LONG,1		; returns VAR_LONG with 1 parameter
	db	VAR_LONG,PARM_OPT_ONE	; 1st parameter: VAR_LONG, optional
	dw	offset getRndLong,0	; 0 implies our own CODE segment
	db	0			; terminator

CODE	ENDS

	DEFTOKENS KEYWORD_TOKENS,KEYWORD_TOTAL
	DEFTOK	CLS,    40, genCLS
	DEFTOK	COLOR,  41, genColor
	DEFTOK	COPY,   20, cmdCopy
	DEFTOK	DATE,   10, cmdDate
	DEFTOK	DEF,    42, genDefFn
	DEFTOK	DEFDBL, 43, genDefDbl
	DEFTOK	DEFINT, 44, genDefInt
	DEFTOK	DEFSNG, 45, genDefDbl
	DEFTOK	DEFSTR, 46, genDefStr
	DEFTOK	DIR,    21, cmdDir
	DEFTOK	ECHO,   47, genEcho
	DEFTOK	ELSE,  201
	DEFTOK	EXIT,    1, cmdExit
	DEFTOK	GOTO,   48, genGoto
	DEFTOK	HELP,    2, cmdHelp
	DEFTOK	IF,     49  genIf
	DEFTOK	KEYS,    3, cmdKeys
	DEFTOK	LET,    50, genLet
	DEFTOK	LIST,    4, cmdList
	DEFTOK	LOAD,   22, cmdLoad
	DEFTOK	MEM,     5, cmdMem
	DEFTOK	NEW,     6, cmdNew
	DEFTOK	OFF,   202
	DEFTOK	ON,    203
	DEFTOK	PRINT,  51, genPrint
	DEFTOK	REM,    52
	DEFTOK	RESTART, 7, cmdRestart
	DEFTOK	RETURN, 53, genReturn
	DEFTOK	RUN,     8, cmdRun
	DEFTOK	THEN,  204
	DEFTOK	TIME,   11, cmdTime
	DEFTOK	TYPE,   23, cmdType
	DEFTOK	VER,     9, cmdVer
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
; This is where per-process data begins; it must be at the end of the file.
;
	DEFLBL	BEG_HEAP,word
	BLKDEF	<0,CBLKLEN,size CBLK,SIG_CBLK>
	BLKDEF	<0,FBLKLEN,size FBLK,SIG_FBLK>
	BLKDEF	<0,VBLKLEN,size VBLK,SIG_VBLK>
	BLKDEF	<0,SBLKLEN,size SBLK,SIG_SBLK>
	BLKDEF	<0,TBLKLEN,size TBLK,SIG_TBLK>
	COMHEAP	<size CMDHEAP>,BEG_HEAP		; this must be the last item...

DATA	ENDS

	end
