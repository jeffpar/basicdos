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
	include	txt.inc

CODE    SEGMENT
	EXTERNS	<cmdDate,cmdDir,cmdExit,cmdHelp,cmdList,cmdLoad>,near
	EXTERNS	<cmdMem,cmdNew,cmdRun,cmdTime,cmdType,cmdVer>,near
	EXTERNS	<genCLS,genColor,genDefInt,genDefDbl,genDefStr>,near
	EXTERNS	<genEcho,genGoto,genIf,genLet>,near
	EXTERNS	<evalNegLong,evalNotLong>,near
	EXTERNS	<evalAddLong,evalSubLong,evalMulLong,evalDivLong>,near
	EXTERNS	<evalModLong,evalExpLong,evalImpLong>,near
	EXTERNS	<evalEqvLong,evalXorLong,evalOrLong,evalAndLong>,near
	EXTERNS	<evalEQLong,evalNELong,evalLTLong,evalGTLong>,near
	EXTERNS	<evalLELong,evalGELong,evalShlLong,evalShrLong>,near

	EXTERNS	<genExprNum,genExprStr>,near
	EXTERNS	<printArgs>,near

	DEFSTR	COM_EXT,<".COM",0>	; these 4 file extensions must be
	DEFSTR	EXE_EXT,<".EXE",0>	; listed in the desired search order
	DEFSTR	BAT_EXT,<".BAT",0>
	DEFSTR	BAS_EXT,<".BAS",0>

	DEFSTR	DIR_DEF,<"*.*",0>
	DEFSTR	PERIOD,<".",0>
	DEFSTR	SYS_MEM,<"<SYS>",0>
	DEFSTR	DOS_MEM,<"<DOS>",0>
	DEFSTR	FREE_MEM,<"<FREE>",0>
	DEFSTR	STD_VER,<0>
	DEFSTR	DBG_VER,<"DEBUG",0>
	DEFSTR	HELP_FILE,<"COMMAND.TXT",0>
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
; operators internally, to simplify operator management; genExprNum takes care
; of any keyword operators listed in the KEYOP_TOKENS table, and validateOp
; takes care of any any multi-symbol operators listed in the RELOPS table.
;
; We've also taken some liberties with the language, by allowing '~' and '|'
; in addition to 'NOT' and 'OR', and by adding '>>' and '<<' arithmetic shift
; operations.  It would have been nice to allow '&' in place of 'AND' as well,
; but unfortunately '&' was already used to prefix hex and octal constants.
;
; TODO: Speaking of hex and octal constants, maybe someday we'll also allow
; "0x" and "0o" prefixes, and maybe even a C-inspired version of PRINT USING
; called... drum roll... PRINTF USING.
;
	DEFLBL	OPDEFS,byte
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
	OPDEF	<'S',16,evalShlLong>	; '<<'
	OPDEF	<'R',16,evalShrLong>	; '>>'
	OPDEF	<'=',14,evalEQLong>
	OPDEF	<'U',14,evalNELong>	; '<>' or '><'
	OPDEF	<'<',14,evalLTLong>
	OPDEF	<'>',14,evalGTLong>
	OPDEF	<'L',14,evalLELong>	; '<=' or '=<'
	OPDEF	<'G',14,evalGELong>	; '>=' or '=>'
	OPDEF	<'~',13,evalNotLong>	; 'NOT'
	OPDEF	<'A',12,evalAndLong>	; 'AND'
	OPDEF	<'|',10,evalOrLong>	; 'OR'
	OPDEF	<'X',8,evalXorLong>	; 'XOR'
	OPDEF	<'E',6,evalEqvLong>	; 'EQV'
	OPDEF	<'I',4,evalImpLong>	; 'IMP'
	DEFBYTE	OPDEFS_END,0

	DEFLBL	RELOPS,byte
	db	"<>",'U',"><",'U',"<=",'L',"=<",'L',">=",'G',"=>",'G'
	db	"==",'=',"<<",'S',">>",'R'
	db	0

	DEFLBL	SYNTAX_TABLES,word
;
; Syntax tables are a series of bytes processed by synCheck that define
; both the syntax and the code generation logic for a given keyword.
;
	DEFLBL	synPrint,byte
	db	SC_GENPB,VAR_NONE	; start with VAR_NONE on the stack
	db	SC_PEKTK,CLS_ANY	; peek for any token

	db	SC_MASYM,';'		; semi-colon pushes
	db	SC_GENPB,VAR_SEMI	; VAR_SEMI onto the stack

	db	SC_MASYM,','		; comma pushes
	db	SC_GENPB,VAR_COMMA	; VAR_COMMA onto the stack

	db	SC_MATCH,CLS_STR	; string constant
	db	SC_CALFN,SCF_GENXSTR	; generates call to genExprStr
	db	SC_GENPB,VAR_STR

	db	SC_MATCH,CLS_VAR_STR	; string variable
	db	SC_CALFN,SCF_GENXSTR	; also generates call to genExprStr
	db	SC_GENPB,VAR_STR

	db	SC_MATCH,CLS_ANY	; anything else
	db	SC_CALFN,SCF_GENXNUM	; generates call to genExprNum
	db	SC_GENPB,VAR_LONG	; (failure triggers jump to next block)

	db	SC_NEXTK,0		; check for more tokens if no failure
	db	SC_GENFN,SCF_PRTARGS,-1	; otherwise generate call to printArgs

	DEFLBL	SCF_TABLE,word		; synCheck function table:
	dw	genExprNum		; SCF_GENXNUM
	dw	genExprStr		; SCF_GENXSTR
	dw	printArgs		; SCF_PRTARGS

CODE	ENDS

	DEFTOKENS KEYWORD_TOKENS,KEYWORD_TOTAL
	DEFTOK	CLS,    60, genCLS
	DEFTOK	COLOR,  61, genColor
	DEFTOK	DATE,   40, cmdDate
	DEFTOK	DEFINT, 62, genDefInt
	DEFTOK	DEFDBL, 63, genDefDbl
	DEFTOK	DEFSNG, 64, genDefDbl
	DEFTOK	DEFSTR, 65, genDefStr
	DEFTOK	DIR,    20, cmdDir
	DEFTOK	ECHO,   66, genEcho
	DEFTOK	ELSE,  201
	DEFTOK	EXIT,    1, cmdExit
	DEFTOK	GOTO,   67, genGoto
	DEFTOK	HELP,   41, cmdHelp
	DEFTOK	IF,     68  genIf
	DEFTOK	LET,    69, genLet
	DEFTOK	LIST,    2, cmdList
	DEFTOK	LOAD,   21, cmdLoad
	DEFTOK	MEM,    42, cmdMem
	DEFTOK	NEW,     3, cmdNew
	DEFTOK	PRINT,  70, synPrint
	DEFTOK	REM,    71
	DEFTOK	RUN,     4, cmdRun
	DEFTOK	THEN,  202
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

	DEFLBL	BEG_HEAP,word
	BLK_DEF	<0,size CBLK_HDR,SIG_CBLK>
	BLK_DEF	<0,size VBLK_HDR,SIG_VBLK>
	BLK_DEF	<0,size SBLK_HDR,SIG_SBLK>
	BLK_DEF	<0,size TBLK_HDR,SIG_TBLK>
	COMHEAP	<size CMD_HEAP>,BEG_HEAP

DATA	ENDS

	end
