;
; BASIC-DOS Predefined Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The table of predefined functions (PREDEF_VARS), which findVar searches
; (see var.asm) before any of a program's variables.
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<getErrorLevel,getRnd,getRndLong,getErr,peekByte,getMouse>
	EXTNEAR	<fileEof,fileLoc,fileLof,fileMki,fileMkl,fileMkd,fileIoctlStr>
	EXTNEAR	<fileCvi,fileCvl,fileCvd,cvtDbl,cvtLong,getCsrlin,getErl>
	EXTNEAR	<getPos,getScreen,getSgn,strTab>
	EXTNEAR	<strArg,strAsc,strChr,strDate,strFre,strHex,strInkey,strInstr>
	EXTNEAR	<strLCase,strLeft,strLen,strMid,strOct,strRight,strSpace>
	EXTNEAR	<strStr,strString,strTime,strUCase,strVal,strCurDir,strPath>
	EXTNEAR	<getExists,strDir>

	DEFLBL	PREDEF_VARS,byte
;
; Each predefined function is a VAR_FUNC with its return type, the number of
; parameters, the type and flags (or default value) of each parameter, and the
; address of the function (a segment of 0 implies our own CODE segment).  Like
; all predefined vars, they match any type, so (for example) "LEFT$" and "LEFT"
; are the same.  A default of 0FEh (-2) for MID$ means "the rest".
;
	db	VAR_FUNC + 3,"ARG"
	db	VAR_STR,1
	db	VAR_LONG,0FEh		; (a negative default means all args)
	dw	offset strArg,0
	db	VAR_FUNC + 3,"ASC"
	db	VAR_LONG,1
	db	VAR_STR,PARM_REQUIRED
	dw	offset strAsc,0
	db	VAR_FUNC + 3,"CHR"
	db	VAR_STR,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset strChr,0
	db	VAR_FUNC + 4,"CDBL"
	db	VAR_DOUBLE,1
	db	VAR_DOUBLE,PARM_REQUIRED
	dw	offset cvtDbl,0
	db	VAR_FUNC + 4,"CINT"
	db	VAR_LONG,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset cvtLong,0
	db	VAR_FUNC + 4,"CSNG"
	db	VAR_DOUBLE,1
	db	VAR_DOUBLE,PARM_REQUIRED
	dw	offset cvtDbl,0
	db	VAR_FUNC + 6,"CSRLIN"
	db	VAR_LONG,0
	dw	offset getCsrlin,0
	db	VAR_FUNC + 6,"CURDIR"
	db	VAR_STR,0
	dw	offset strCurDir,0
	db	VAR_FUNC + 3,"CVD"
	db	VAR_DOUBLE,1
	db	VAR_STR,PARM_REQUIRED
	dw	offset fileCvd,0
	db	VAR_FUNC + 3,"CVI"
	db	VAR_LONG,1
	db	VAR_STR,PARM_REQUIRED
	dw	offset fileCvi,0
	db	VAR_FUNC + 3,"CVL"
	db	VAR_LONG,1
	db	VAR_STR,PARM_REQUIRED
	dw	offset fileCvl,0
	db	VAR_FUNC + 4,"DATE"
	db	VAR_STR,0
	dw	offset strDate,0
	db	VAR_FUNC + 3,"DIR"
	db	VAR_STR,2
	db	VAR_STR,PARM_OPT_ZERO	; (an empty filespec means the next match)
	db	VAR_LONG,16h		; hidden, system, and directory attrs
	dw	offset strDir,0
	db	VAR_FUNC + 3,"EOF"
	db	VAR_LONG,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset fileEof,0
	db	VAR_FUNC + 3,"ERL"
	db	VAR_LONG,0
	dw	offset getErl,0
	db	VAR_FUNC + 3,"ERR"
	db	VAR_LONG,0
	dw	offset getErr,0
	db	VAR_FUNC + 10,"ERRORLEVEL"
	db	VAR_LONG,0		; returns VAR_LONG with 0 parameters
	dw	offset getErrorLevel,0	; 0 implies our own CODE segment
	db	VAR_FUNC + 6,"EXISTS"
	db	VAR_LONG,1
	db	VAR_STR,PARM_REQUIRED
	dw	offset getExists,0
	db	VAR_FUNC + 3,"FRE"
	db	VAR_LONG,1
	db	VAR_CHAR,PARM_OPT_ZERO
	dw	offset strFre,0
	db	VAR_FUNC + 3,"HEX"
	db	VAR_STR,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset strHex,0
	db	VAR_FUNC + 5,"INKEY"
	db	VAR_STR,0
	dw	offset strInkey,0
	db	VAR_FUNC + 5,"IOCTL"
	db	VAR_STR,3
	db	VAR_LONG,PARM_REQUIRED
	db	VAR_LONG,PARM_REQUIRED
	db	VAR_LONG,PARM_OPT_ZERO
	dw	offset fileIoctlStr,0
	db	VAR_FUNC + 5,"INSTR"
	db	VAR_LONG,3
	db	VAR_LSKIP,PARM_OPT_ONE
	db	VAR_STR,PARM_REQUIRED
	db	VAR_STR,PARM_REQUIRED
	dw	offset strInstr,0
	db	VAR_FUNC + 5,"LCASE"
	db	VAR_STR,1
	db	VAR_STR,PARM_REQUIRED
	dw	offset strLCase,0
	db	VAR_FUNC + 4,"LEFT"
	db	VAR_STR,2
	db	VAR_STR,PARM_REQUIRED
	db	VAR_LONG,PARM_REQUIRED
	dw	offset strLeft,0
	db	VAR_FUNC + 3,"LEN"
	db	VAR_LONG,1
	db	VAR_STR,PARM_REQUIRED
	dw	offset strLen,0
	db	VAR_LONG + 6,"MAXINT"
	dd	7FFFFFFFh		; largest positive value
	db	VAR_FUNC + 3,"LOC"
	db	VAR_LONG,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset fileLoc,0
	db	VAR_FUNC + 3,"LOF"
	db	VAR_LONG,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset fileLof,0
	db	VAR_FUNC + 3,"MID"
	db	VAR_STR,3
	db	VAR_STR,PARM_REQUIRED
	db	VAR_LONG,PARM_REQUIRED
	db	VAR_LONG,0FEh
	dw	offset strMid,0
	db	VAR_FUNC + 3,"MKD"
	db	VAR_STR,1
	db	VAR_DOUBLE,PARM_REQUIRED
	dw	offset fileMkd,0
	db	VAR_FUNC + 3,"MKI"
	db	VAR_STR,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset fileMki,0
	db	VAR_FUNC + 3,"MKL"
	db	VAR_STR,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset fileMkl,0
	db	VAR_FUNC + 5,"MOUSE"	; (see genExpr's TOK_MOUSE check)
	db	VAR_LONG,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset getMouse,0
	db	VAR_FUNC + 4,"PEEK"
	db	VAR_LONG,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset peekByte,0
	db	VAR_FUNC + 3,"OCT"
	db	VAR_STR,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset strOct,0
	db	VAR_FUNC + 4,"PATH"
	db	VAR_STR,0
	dw	offset strPath,0
	db	VAR_FUNC + 3,"POS"
	db	VAR_LONG,1
	db	VAR_LONG,PARM_OPT_ZERO
	dw	offset getPos,0
	db	VAR_FUNC + 5,"RIGHT"
	db	VAR_STR,2
	db	VAR_STR,PARM_REQUIRED
	db	VAR_LONG,PARM_REQUIRED
	dw	offset strRight,0
	db	VAR_FUNC + 3,"RND"
	db	VAR_DOUBLE,1		; RND returns VAR_DOUBLE (see findVar)
	db	VAR_LONG,PARM_OPT_ONE
	dw	offset getRnd,0
	db	VAR_FUNC + 3,"RND"
	db	VAR_LONG,1		; RND% returns VAR_LONG with 1 parameter
	db	VAR_LONG,PARM_OPT_ONE	; 1st parameter: VAR_LONG, optional
	dw	offset getRndLong,0
	db	VAR_FUNC + 6,"SCREEN"	; (see genExpr's TOK_SCREEN check)
	db	VAR_LONG,3
	db	VAR_LONG,PARM_REQUIRED
	db	VAR_LONG,PARM_REQUIRED
	db	VAR_LONG,PARM_OPT_ZERO
	dw	offset getScreen,0
	db	VAR_FUNC + 3,"SGN"
	db	VAR_LONG,1
	db	VAR_DOUBLE,PARM_REQUIRED
	dw	offset getSgn,0
	db	VAR_FUNC + 5,"SPACE"
	db	VAR_STR,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset strSpace,0
	db	VAR_FUNC + 3,"STR"
	DEFLBL	STR_DATA,byte		; (see genFuncExpr)
	db	VAR_STR,1
	db	VAR_DOUBLE,PARM_REQUIRED
	dw	offset strStr,0
	db	VAR_FUNC + 3,"SPC"
	db	VAR_STR,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset strSpace,0
	db	VAR_FUNC + 6,"STRING"
	db	VAR_STR,2
	db	VAR_LONG,PARM_REQUIRED
	db	VAR_CHAR,PARM_REQUIRED
	dw	offset strString,0
	db	VAR_FUNC + 3,"TAB"
	db	VAR_STR,1
	db	VAR_LONG,PARM_REQUIRED
	dw	offset strTab,0
	db	VAR_FUNC + 4,"TIME"
	db	VAR_STR,0
	dw	offset strTime,0
	db	VAR_FUNC + 5,"UCASE"
	db	VAR_STR,1
	db	VAR_STR,PARM_REQUIRED
	dw	offset strUCase,0
	db	VAR_FUNC + 3,"VAL"
	DEFLBL	VAL_DATA,byte		; (see genFuncExpr)
	db	VAR_DOUBLE,1
	db	VAR_STR,PARM_REQUIRED
	dw	offset strVal,0
	db	0			; terminator

CODE	ENDS

	end
