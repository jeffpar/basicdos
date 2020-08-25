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
	EXTERNS	<cmdDate,cmdDir,cmdExit,cmdHelp,cmdList,cmdLoad,cmdMem>,near
	EXTERNS	<cmdRun,cmdTime,cmdType>,near
	EXTERNS	<genCLS,genColor,genDefInt,genGoto,genIf,genLet,genPrint>,near
	EXTERNS	<evalNegLong,evalNotLong>,near
	EXTERNS	<evalAddLong,evalSubLong,evalMulLong,evalDivLong>,near
	EXTERNS	<evalModLong,evalExpLong,evalImpLong>,near
	EXTERNS	<evalEqvLong,evalXorLong,evalOrLong,evalAndLong>,near
	EXTERNS	<evalEQLong,evalNELong,evalLTLong,evalGTLong>,near
	EXTERNS	<evalLELong,evalGELong,evalShlLong,evalShrLong>,near

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
; Each OPDEF structure contains 1) operator symbol, 2) operator precedence,
; and 3) operator evaluators (currently, only one LONG evaluator is present
; for each operator).  Although the operators are listed in order of highest
; to lowest precedence, it's the operator precedence field that actually
; determines an operator's priority.
;
; Most operators are "binary ops" (ie, operators that require 2 stack-based
; arguments).  There are 3 "unary ops": unary '-', unary '+', and 'NOT',
; each distinguished by an ODD precedence.
;
; Parentheses require special treatment; they may appear to have low
; precedence (1), but that's simply to ensure that when we encounter a
; closing parenthesis, all operators with a precedence higher than the opening
; parenthesis get popped.
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

CODE	ENDS
;
; Keywords with IDs < 20 only require GENERIC parsing, and keywords with
; IDs < 10 don't use filespecs for their first argument.
;
	DEFTOKENS KEYWORD_TOKENS,KEYWORD_TOTAL
	DEFTOK	TOK_CLS,    20, "CLS",    genCLS
	DEFTOK	TOK_COLOR,  21, "COLOR",  genColor
	DEFTOK	TOK_DATE,    1, "DATE",   cmdDate
	DEFTOK	TOK_DEFINT, 22, "DEFINT", genDefInt
	DEFTOK	TOK_DIR,    10, "DIR",    cmdDir
	DEFTOK	TOK_ELSE,  101, "ELSE"
	DEFTOK	TOK_EXIT,    2, "EXIT",   cmdExit
	DEFTOK	TOK_GOTO,   23, "GOTO",   genGoto
	DEFTOK	TOK_HELP,    3, "HELP",   cmdHelp
	DEFTOK	TOK_IF,     24, "IF",     genIf
	DEFTOK	TOK_LET,    25, "LET",    genLet
	DEFTOK	TOK_LIST,    4, "LIST",   cmdList
	DEFTOK	TOK_LOAD,   11, "LOAD",   cmdLoad
	DEFTOK	TOK_MEM,     5, "MEM",    cmdMem
	DEFTOK	TOK_PRINT,  26, "PRINT",  genPrint
	DEFTOK	TOK_REM,    27, "REM"
	DEFTOK	TOK_RUN,     6, "RUN",    cmdRun
	DEFTOK	TOK_THEN,  102, "THEN"
	DEFTOK	TOK_TIME,    7, "TIME",   cmdTime
	DEFTOK	TOK_TYPE,   12, "TYPE",   cmdType
	NUMTOKENS KEYWORD_TOKENS,KEYWORD_TOTAL

	DEFTOKENS KEYOP_TOKENS,KEYOP_TOTAL
	DEFTOK	TOK_AND,  'A', "AND"
	DEFTOK	TOK_EQV,  'E', "EQV"
	DEFTOK	TOK_IMP,  'I', "IMP"
	DEFTOK	TOK_MOD,  'M', "MOD"
	DEFTOK	TOK_NOT,  '~', "NOT"
	DEFTOK	TOK_OR,   '|', "OR"
	DEFTOK	TOK_XOR,  'X', "XOR"
	NUMTOKENS KEYOP_TOKENS,KEYOP_TOTAL

DATA	SEGMENT

	DEFLBL	HEAP,word
	BLK_DEF	<0,size CBLK_HDR,CBLKSIG>
	BLK_DEF	<0,size VBLK_HDR,VBLKSIG>
	BLK_DEF	<0,size SBLK_HDR,SBLKSIG>
	BLK_DEF	<0,size TBLK_HDR,TBLKSIG>
	COMHEAP	<size CMD_HEAP>,HEAP

DATA	ENDS

	end
