;
; BASIC-DOS Command Processor Constants
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

;
; DEFTOK stores each token's string in CODE, where all the strings follow
; TOK_STRS (see const.asm), so that a string's offset is TOK_STRS + tokPos,
; rather than a label of its own (to conserve symbol space).
;
DEFTOK	macro	sym,val,func,pub
	IFNB	<pub>			;; define TOK_sym only if requested
	public	TOK_&sym		;; (to conserve symbol space)
TOK_&sym equ val
	ENDIF
	IFNB <func>
	EXTNEAR	<func>
	ENDIF
CODE	SEGMENT
	db	"&sym&"
	len = (offset $ - offset TOK_STRS) - tokPos
CODE	ENDS
DATA	SEGMENT
	IFB <func>
	CTOKDEF	<val,len,offset DGROUP:TOK_STRS+tokPos,0>
	ELSE
	CTOKDEF	<val,len,offset DGROUP:TOK_STRS+tokPos,offset func>
	ENDIF
DATA	ENDS
	tokPos = tokPos + len
	endm

DEFTOKENS macro tbl,val
DATA	SEGMENT
	public	tbl
tbl	TOKTBL	<val,size CTOKDEF>
DATA	ENDS
	endm

NUMTOKENS macro tbl,val
DATA	SEGMENT
val = ((offset $ - offset tbl) - 2) / (size CTOKDEF)
DATA	ENDS
	endm


CODE    SEGMENT

	EXTNEAR	<evalNegLong,evalNotLong>
	EXTBYTE	<RES_HEAP>
	EXTNEAR	<evalAddLong,evalSubLong,evalMulLong,evalDivLong>
	EXTNEAR	<evalModLong,evalExpLong,evalImpLong>
	EXTNEAR	<evalEqvLong,evalXorLong,evalOrLong,evalAndLong>
	EXTNEAR	<evalEQLong,evalNELong,evalLTLong,evalGTLong>
	EXTNEAR	<evalLELong,evalGELong,evalShlLong,evalShrLong>

	EXTNEAR	<evalAddStr>
	EXTNEAR	<evalEQStr,evalNEStr,evalLTStr,evalGTStr,evalLEStr,evalGEStr>


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
	DEFSTR	FPU_NAME,<"FPU$",0>
	DEFSTR	STR_ON,<"ON",0>
	DEFSTR	STR_OFF,<"OFF",0>

	DEFSTR	SYS_MEM,<"<SYS>",0>
	DEFSTR	DOS_MEM,<"<DOS>",0>
	DEFSTR	BLK_NAMES,<"<CODE>",0,0,"<FUNC>",0,0,"<VAR>",0,"<STR>",0>
	db	"<TEXT>",0,0,"<ARR>",0
	DEFABS	BLK_WORDS,<(($ - BLK_NAMES) SHR 1)>
	DEFSTR	BLK_UNKNOWN,<"<UNK>",0>
	DEFSTR	FREE_MEM,<"<FREE>",0>
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

;
; There's no EVAL_DOUBLE table; the evaluators for doubles come from the
; FPU$ driver's FPUTBL (see FPU_TABLE and genCallFPU).
;
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


CODE	ENDS

;
; Keywords with IDs from 101 (TOK_ABS) to 110 (TOK_TAN) are numeric functions
; that genExpr handles (by calling the corresponding FPU$ functions), so their
; IDs must remain consecutive and in the same order as genExpr's FN_FPUTBL.
;
CODE	SEGMENT
TOK_STRS label	byte			; the token strings (see DEFTOK)
CODE	ENDS
	tokPos = 0

	DEFTOKENS KEYWORD_TOKENS,KEYWORD_TOTAL
	DEFTOK	ABS,   101,,PUB
	DEFTOK	APPEND,211,,PUB
	DEFTOK	AS,    209,,PUB
	DEFTOK	ATN,   102
	DEFTOK	AUTO,   12, cmdAuto
	DEFTOK	BASE,  205,,PUB
	DEFTOK	CD,     16, cmdChdir
	DEFTOK	CHAIN,  71, genChain
	DEFTOK	CHDIR,  16, cmdChdir
	DEFTOK	CIRCLE, 82, genCircle
	DEFTOK	CLEAR,  81, genClear
	DEFTOK	CLOSE,  88, genClose
	DEFTOK	CLS,    40, genCLS
	DEFTOK	COLOR,  41, genColor
	DEFTOK	COPY,   20, cmdCopy
	DEFTOK	COS,   103
	DEFTOK	DATA,   83, genData
	DEFTOK	DATE,   10, cmdDate
	DEFTOK	DEF,    42, genDef
	DEFTOK	DEFDBL, 43, genDefDbl
	DEFTOK	DEFINT, 44, genDefInt
	DEFTOK	DEFSNG, 45, genDefDbl
	DEFTOK	DEFSTR, 46, genDefStr
	DEFTOK	DEL,    24, cmdDel,PUB
	DEFTOK	DELETE, 13, cmdDelete
	DEFTOK	DIM,    54, genDim
	DEFTOK	DIR,    21, cmdDir
	DEFTOK	DRAW,   74, genDraw
	DEFTOK	ECHO,   47, genEcho
	DEFTOK	EDIT,   14, cmdEdit
	DEFTOK	ELSE,  201,,PUB
	DEFTOK	END,    57, genEnd
	DEFTOK	ERASE,  55, genErase,PUB
	DEFTOK	ERROR,  72, genError,PUB
	DEFTOK	EXIT,    1, cmdExit
	DEFTOK	EXP,   104
	DEFTOK	FIELD,  91, genField
	DEFTOK	FIX,   105
	DEFTOK	FOR,    58, genFor,PUB
	DEFTOK	GET,    75, genGet
	DEFTOK	GOSUB,  59, genGosub,PUB
	DEFTOK	GOTO,   48, genGoto,PUB
	DEFTOK	HELP,    2, cmdHelp
	DEFTOK	IF,     49  genIf
	DEFTOK	INPUT,  89, genInput,PUB
	DEFTOK	INT,   106
	DEFTOK	KEY,    67, genKey
	DEFTOK	KEYS,    3, cmdKeys
	DEFTOK	KILL,   25, cmdDel
	DEFTOK	LET,    50, genLet
	DEFTOK	LINE,   76, genLine
	DEFTOK	LIST,    4, cmdList
	DEFTOK	LOAD,   22, cmdLoad
	DEFTOK	LOCATE, 64, genLocate
	DEFTOK	LOG,   107
	DEFTOK	LSET,   92, genLset
	DEFTOK	MD,     17, cmdMkdir
	DEFTOK	MEM,     5, cmdMem
	DEFTOK	MKDIR,  17, cmdMkdir
	DEFTOK	MOUSE,  86, genMouse,PUB
	DEFTOK	MV,     26, cmdRen
	DEFTOK	NEW,     6, cmdNew
	DEFTOK	NEXT,   60, genNext
	DEFTOK	OFF,   202,,PUB
	DEFTOK	ON,    203, genOn,PUB
	DEFTOK	OPEN,   87, genOpen
	DEFTOK	OPTION, 56, genOption
	DEFTOK	OUTPUT,210,,PUB
	DEFTOK	PAINT,  77, genPaint
	DEFTOK	PLAY,   70, genPlay
	DEFTOK	POKE,   68, genPoke
	DEFTOK	PRESET, 78, genPreset,PUB
	DEFTOK	PRINT,  51, genPrint
	DEFTOK	PSET,   79, genPset,PUB
	DEFTOK	PUT,    80, genPut
	DEFTOK	RANDOM,212,,PUB
	DEFTOK	RANDOMIZE,96,genRandomize
	DEFTOK	RD,     18, cmdRmdir
	DEFTOK	READ,   84, genRead
	DEFTOK	REM,    52
	DEFTOK	REN,    26, cmdRen
	DEFTOK	RENAME, 26, cmdRen
	DEFTOK	RESET,  94, genClose
	DEFTOK	RESTART, 7, cmdRestart
	DEFTOK	RESTORE,85, genRestore
	DEFTOK	RESUME, 73, genResume
	DEFTOK	RETURN, 53, genReturn
	DEFTOK	RMDIR,  18, cmdRmdir
	DEFTOK	RSET,   93, genRset
	DEFTOK	RUN,     8, cmdRun
	DEFTOK	SAVE,   15, cmdSave
	DEFTOK	SCREEN, 65, genScreen,PUB
	DEFTOK	SEG,   208,,PUB
	DEFTOK	SIN,   108
	DEFTOK	SOUND,  69, genSound
	DEFTOK	SQR,   109
	DEFTOK	STEP,  206,,PUB
	DEFTOK	STOP,   61, genEnd
	DEFTOK	SWAP,   97, genSwap
	DEFTOK	SYSTEM, 95, genEnd
	DEFTOK	TAN,   110,,PUB
	DEFTOK	THEN,  204,,PUB
	DEFTOK	TIME,   11, cmdTime
	DEFTOK	TO,    207,,PUB
	DEFTOK	TYPE,   23, cmdType
	DEFTOK	VER,     9, cmdVer
	DEFTOK	WEND,   62, genWend
	DEFTOK	WHILE,  63, genWhile
	DEFTOK	WIDTH,  66, genWidth
	DEFTOK	WRITE,  90, genWrite
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
	BLKDEF	<0,0,size BLKHDR,SIG_ABLK>	; array blocks (sized by DIM)
	COMHEAP	<size CMDHEAP>,BEG_HEAP,RES_HEAP ; this must be the last item

DATA	ENDS

	end
