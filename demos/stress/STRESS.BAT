REM BASIC-DOS multitasking stress test (see demos/stress): creates folders
REM nested 4 deep, each with 4 small files of increasingly long names plus
REM 128 empty files (enough to grow each folder beyond its first cluster),
REM deletes them all, and runs PRIMES.BAS, forever; the argument (eg, 1 or 2)
REM makes this session's folder names unique, so that several sessions can
REM run it at once (session 1 runs PRIMES.BAS first, so that the sessions
REM are out of step)
	DEFINT A-Z
	S$ = "S" + ARG$(1)
	N = 0
	IF ARG$(1) = "1" THEN GOTO 40
10	N = N + 1
	PRINT "Session "; ARG$(1); ", pass"; N
	L = 0
20	L = L + 1
	L$ = MID$(STR$(L), 2)
	D$ = S$ + "L" + L$
	MD D$
	IF ERRORLEVEL <> 0 THEN GOTO 90
	CD D$
	IF ERRORLEVEL <> 0 THEN GOTO 90
	PRINT "L"; L$; " ";
	FOR J = 1 TO 4
	F$ = LEFT$("ABCDEFGH", J * 2) + "." + L$
	PRINT "Session "; ARG$(1); ", level"; L; ", file"; J :> F$
	NEXT
	FOR J = 1 TO 128
	OPEN "X" + MID$(STR$(J), 2) + "." + L$ FOR OUTPUT AS #1
	CLOSE #1
	NEXT
	IF L < 4 THEN GOTO 20
	PRINT
30	L$ = MID$(STR$(L), 2)
	FOR J = 1 TO 4
	F$ = LEFT$("ABCDEFGH", J * 2) + "." + L$
	DEL F$
	IF ERRORLEVEL <> 0 THEN GOTO 90
	NEXT
	F$ = "X*." + L$
	DEL F$
	IF ERRORLEVEL <> 0 THEN GOTO 90
	D$ = S$ + "L" + L$
	CD ..
	IF ERRORLEVEL <> 0 THEN GOTO 90
	RD D$
	IF ERRORLEVEL <> 0 THEN GOTO 90
	L = L - 1
	IF L > 0 THEN GOTO 30
40	PRIMES 1000
	GOTO 10
90	PRINT "Session "; ARG$(1); " failed on pass"; N; ", level"; L
	END
