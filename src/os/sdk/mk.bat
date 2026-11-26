	@ECHO OFF
	REM Usage: MK [FINAL or DEBUG] [CLEAN] (FINAL is the default, unless
	REM there's an MKDEBUG file in the root directory, as there is on a
	REM hard disk with DEBUG binaries; CLEAN deletes the programs, and any
	REM files that a failed build left, for a clean build).
	REM Builds the SDK programs (MEM32.EXE, FIND16.EXE, and FIND32.EXE) on
	REM BASIC-DOS (in SRC\SDK on BASICDOS-20MB), in protected mode, with
	REM TOOLS\BIN in PATH$.
	REM NOTE: MAKE can't tell when the mode changes, so use CLEAN to
	REM rebuild everything in a new mode.  ERRORLEVEL is 1 if MK fails.
	M$ = UCASE$(ARG$(1))
	IF M$ = "" AND EXISTS("..\..\MKDEBUG") THEN M$ = "DEBUG"
	IF M$ = "" THEN M$ = "FINAL"
	IF M$ <> "FINAL" AND M$ <> "DEBUG" THEN 200
	C$ = UCASE$(ARG$(2))
	IF C$ <> "" AND C$ <> "CLEAN" THEN 200
	IF C$ = "CLEAN" THEN GOSUB 300
	IF M$ = "DEBUG" THEN MAKE REL=DEBUG MAKEFILE : GOTO 100
	MAKE REL=FINAL MAKEFILE
100	IF ERRORLEVEL THEN PRINT "MK failed" : END 1
	END
200	PRINT "Usage: MK [FINAL or DEBUG] [CLEAN]"
	END 1
300	T$ = ".EXE.OBJ.STB"
	FOR I = 1 TO LEN(T$) STEP 4
	F$ = "*" + MID$(T$,I,4)
	IF EXISTS(F$) THEN DEL F$
	NEXT
	RETURN
