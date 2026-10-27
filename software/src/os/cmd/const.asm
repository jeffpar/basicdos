;
; BASIC-DOS Command Processor Constants
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	HEAPDEFS equ 1			; (see HEAPDEF in cmd.inc)
	include	cmd.inc

;
; The token tables are built in two passes over the DEFTOK lists below (see
; KEYWORDS, KEYOPS, and OPTIONS), entirely in CODE: the TOKSTR pass stores
; every token's string, one after another following TOK_STRS, and then the
; DEFTOK pass builds each table's CTOKDEF entries, using TOK_STRS + tokPos as
; a string's offset (rather than a label of its own, to conserve symbol space)
; and counting its length with IRPC.  Two passes keep the strings and the
; entries from interleaving, which is what allowed the tables to live in CODE
; rather than DATA (which LINK places after all the code); that matters now
; that the modules linked after this one are not part of the core (see
; CORE_END below, and HEAP.ASM).
;
TOKSTR	macro	sym,val,func,pub
	db	"&sym&"
	endm

DEFTOK	macro	sym,val,func,pub
	IFNB	<pub>			;; define TOK_sym only if requested
	public	TOK_&sym		;; (to conserve symbol space)
TOK_&sym equ val
	ENDIF
	IFNB <func>
	EXTNEAR	<func>
	ENDIF
	len = 0
	IRPC	c,<sym>
	len = len + 1
	ENDM
	IFB <func>
	CTOKDEF	<val,len,offset DGROUP:TOK_STRS+tokPos,0>
	ELSE
	CTOKDEF	<val,len,offset DGROUP:TOK_STRS+tokPos,offset func>
	ENDIF
	tokPos = tokPos + len
	endm

DEFTOKENS macro tbl,val
	public	tbl
tbl	TOKTBL	<val,size CTOKDEF>
	endm

NUMTOKENS macro tbl,val
val = ((offset $ - offset tbl) - 2) / (size CTOKDEF)
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
	DEFSTR	VER_FINAL,<0>		; (also ends VER_DEBUG)
	DEFSTR	HELP_FILE,<"HELP.TXT",0>
	DEFSTR	PIPE_NAME,<"PIPE$",0>
	DEFSTR	FPU_NAME,<"FPU$",0>
	DEFSTR	STR_ON,<"ON",0>
	DEFSTR	STR_OFF,<"OFF",0>

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
; However, at the prompt, a '|' outside quotes now pipes the output of the
; line's statements (eg, "PRINT X | MORE"; see cmdPipe).
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
; Each list must be in alphabetical order, and each is processed twice, by
; TOKSTR and then by DEFTOK (see above).
;
KEYWORDS	macro	PASS
	PASS	ABS,   101,,PUB
	PASS	APPEND,211,,PUB
	PASS	AS,    209,,PUB
	PASS	ATN,   102
	PASS	AUTO,   12, cmdAuto
	PASS	BASE,  205,,PUB
	PASS	CD,     16, cmdChdir
	PASS	CHAIN,  71, genChain
	PASS	CIRCLE, 82, genCircle
	PASS	CLEAR,  81, genClear
	PASS	CLOSE,  88, genClose
	PASS	CLS,    40, genCLS
	PASS	COLOR,  41, genColor
	PASS	COPY,   20, cmdCopy
	PASS	COS,   103
	PASS	DATA,   83, genData
	PASS	DATE,   10, cmdDate
	PASS	DEF,    42, genDef
	PASS	DEFDBL, 43, genDefDbl
	PASS	DEFINT, 44, genDefInt
	PASS	DEFSTR, 46, genDefStr
	PASS	DEL,    24, cmdDel
	PASS	DELETE, 13, cmdDelete
	PASS	DIM,    54, genDim
	PASS	DIR,    21, cmdDir
	PASS	DOS,   100, genDosCall,PUB
	PASS	DRAW,   74, genDraw
	PASS	ECHO,   47, genEcho
	PASS	EDIT,   14, cmdEdit
	PASS	ELSE,  201,,PUB
	PASS	END,    57, genEnd
	PASS	ERASE,  55, genErase
	PASS	ERROR,  72, genError,PUB
	PASS	EXIT,    1, cmdExit
	PASS	EXP,   104
	PASS	FIELD,  91, genField
	PASS	FIX,   105
	PASS	FOR,    58, genFor,PUB
	PASS	GET,    75, genGet
	PASS	GOSUB,  59, genGosub,PUB
	PASS	GOTO,   48, genGoto,PUB
	PASS	HELP,    2, cmdHelp
	PASS	IF,     49  genIf
	PASS	INPUT,  89, genInput,PUB
	PASS	INT,   106
	PASS	IOCTL,  98, genIoctl,PUB
	PASS	KEY,    67, genKey
	PASS	KEYS,    3, cmdKeys
	PASS	LET,    50, genLet
	PASS	LINE,   76, genLine
	PASS	LIST,    4, cmdList
	PASS	LLIST,  19, cmdLlist
	PASS	LOAD,   22, cmdLoad
	PASS	LOCATE, 64, genLocate
	PASS	LOG,   107
	PASS	LPRINT,113, genLprint
	PASS	LSET,   92, genLset
	PASS	MD,     17, cmdMkdir
	PASS	MEM,     5, cmdMem
	PASS	MERGE,  27, cmdMerge,PUB
	PASS	MOUSE,  86, genMouse,PUB
	PASS	NEW,     6, cmdNew
	PASS	NEXT,   60, genNext
	PASS	OFF,   202,,PUB
	PASS	ON,    203, genOn,PUB
	PASS	OPEN,   87, genOpen
	PASS	OPTION, 56, genOption
	PASS	OUTPUT,210,,PUB
	PASS	PAINT,  77, genPaint
	PASS	PLAY,   70, genPlay
	PASS	POKE,   68, genPoke
	PASS	PRESET, 78, genPreset,PUB
	PASS	PRINT,  51, genPrint
	PASS	PRINTF, 99, genPrintf
	PASS	PSET,   79, genPset,PUB
	PASS	PUT,    80, genPut
	PASS	RANDOM,212,,PUB
	PASS	RANDOMIZE,96,genRandomize
	PASS	RD,     18, cmdRmdir
	PASS	READ,   84, genRead
	PASS	REM,    52
	PASS	REN,    26, cmdRen
	PASS	RESTART, 7, cmdRestart
	PASS	RESTORE,85, genRestore
	PASS	RESUME, 73, genResume
	PASS	RETURN, 53, genReturn
	PASS	RSET,   93, genRset
	PASS	RUN,     8, cmdRun
	PASS	SAVE,   15, cmdSave
	PASS	SCREEN, 65, genScreen,PUB
	PASS	SEG,   208,,PUB
	PASS	SIN,   108
	PASS	SOUND,  69, genSound
	PASS	SQR,   109
	PASS	STEP,  206,,PUB
	PASS	STOP,   61, genEnd
	PASS	SWAP,   97, genSwap
	PASS	TAN,   110,,PUB
	PASS	THEN,  204,,PUB
	PASS	TIME,   11, cmdTime
	PASS	TO,    207,,PUB
	PASS	TYPE,   23, cmdType
	PASS	USING, 213,,PUB
	PASS	VER,     9, cmdVer
	PASS	VIEW,  111, genView
	PASS	WEND,   62, genWend
	PASS	WHILE,  63, genWhile
	PASS	WIDTH,  66, genWidth
	PASS	WINDOW,112, genWindow
	PASS	WRITE,  90, genWrite
	endm

KEYOPS	macro	PASS
	PASS	AND,   'A'
	PASS	EQV,   'E'
	PASS	IMP,   'I'
	PASS	MOD,   'M'
	PASS	NOT,   '~'
	PASS	OR,    '|'
	PASS	XOR,   'X'
	endm

;
; Options recognized by commands (eg, LIST VARS and RESTART SYSTEM).
;
OPTIONS	macro	PASS
	PASS	SYSTEM,   2,,PUB
	PASS	VARS,     3,,PUB
	endm

CODE	SEGMENT

TOK_STRS label	byte			; the token strings (see TOKSTR)
	KEYWORDS TOKSTR
	KEYOPS	TOKSTR
	OPTIONS	TOKSTR

	tokPos = 0
	DEFTOKENS KEYWORD_TOKENS,KEYWORD_TOTAL
	KEYWORDS DEFTOK
	NUMTOKENS KEYWORD_TOKENS,KEYWORD_TOTAL

	DEFTOKENS KEYOP_TOKENS,KEYOP_TOTAL
	KEYOPS	DEFTOK
	NUMTOKENS KEYOP_TOKENS,KEYOP_TOTAL

	DEFTOKENS OPTION_TOKENS,OPTION_TOTAL
	OPTIONS	DEFTOK
	NUMTOKENS OPTION_TOKENS,OPTION_TOTAL

;
; This is the end of COMMAND's core.  The modules linked after this one (see
; CMD.LRF) are omitted when there isn't enough memory for the entire image, so
; the core ends with its own copy of the heap template (see HEAPDEF in cmd.inc
; and HEAP.ASM), which is where the heap begins in that case, and CORE_END
; tells the loader how much to load (see CD_CORESIZE in dosapi.inc).
;
	HEAPDEF	CORE_HEAP
	DEFLBL	CORE_END,word

CODE	ENDS

	end
