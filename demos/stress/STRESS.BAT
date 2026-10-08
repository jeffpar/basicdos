REM BASIC-DOS multitasking stress test (see demos/stress): creates folders
REM nested 8 deep, with files of increasingly long names in each, deletes
REM them all, and runs PRIMES.BAS, forever; the argument (eg, 1 or 2) makes
REM this session's folder names unique, so that several sessions can run it
REM at once
	DEFINT A-Z
	S$ = "S" + ARG$(1)
	N = 0
10	N = N + 1
	PRINT "Session "; ARG$(1); ", pass"; N
	L = 0
20	L = L + 1
	D$ = S$ + "L" + MID$(STR$(L), 2)
	MD D$
	CD D$
	PRINT "L"; MID$(STR$(L), 2); " ";
	FOR J = 1 TO 4
	F$ = LEFT$("ABCDEFGH", J * 2) + "." + MID$(STR$(L), 2)
	PRINT "Session "; ARG$(1); ", level"; L; ", file"; J :> F$
	NEXT
	IF L < 8 THEN GOTO 20
	PRINT
30	FOR J = 1 TO 4
	F$ = LEFT$("ABCDEFGH", J * 2) + "." + MID$(STR$(L), 2)
	DEL F$
	NEXT
	D$ = S$ + "L" + MID$(STR$(L), 2)
	CD ..
	RD D$
	L = L - 1
	IF L > 0 THEN GOTO 30
	PRIMES 1000
	GOTO 10
