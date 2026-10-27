	' TREE.BAS: displays the directory structure of a drive or directory
	'
	'   TREE [drive:][path] [/F] [/A]
	'
	' Each directory's subdirectories are listed below it (after its files,
	' for /F), connected by line-drawing characters, or ASCII ones for /A.
	' Without a path, TREE starts with the current directory.  Options start
	' with the switch char (W$), which is "/" unless CONFIG.SYS changes it
	' (eg, to "-").
	'
	' Since BASIC has no local variables, each level of the tree being
	' walked (L) has its own element in a few arrays: the directory's path
	' (P$), the prefix of its lines (X$), and where its subdirectory names
	' begin (B) in N$, how many there are (C), and which is next (I).
	'
	DEFINT A-Z
	DIM P$(32), X$(32), B(32), C(32), I(32), N$(400)
	DOS &H3700 : W$ = CHR$(DOS(3) AND 255)
	S$ = "" : F = 0 : A = 0 : J = 1 : A$ = UCASE$(ARG$(1))
	WHILE A$ <> ""
	IF A$ = W$ + "F" THEN F = 1 : GOTO 5
	IF A$ = W$ + "A" THEN A = 1 : GOTO 5
	' Any other option, or a second path, is an error
	IF LEFT$(A$, 1) = W$ OR S$ <> "" THEN GOTO 95
	S$ = A$
5	J = J + 1 : A$ = UCASE$(ARG$(J))
	WEND
	' The pieces of each line: a branch (G1$), the last branch (G2$), and
	' the prefix below a branch that has more after it (G3$)
	G1$ = CHR$(195) + STRING$(3, 196) : G2$ = CHR$(192) + STRING$(3, 196)
	G3$ = CHR$(179) + "   "
	IF A THEN G1$ = "+---" : G2$ = "\---" : G3$ = "|   "
	PC$ = MID$(CURDIR$, 3, 1)
	IF S$ = "" THEN S$ = CURDIR$
	D$ = LEFT$(CURDIR$, 2) : IF MID$(S$, 2, 1) = ":" THEN D$ = LEFT$(S$, 2)
	ON ERROR GOTO 90
	V$ = DIR$(D$ + PC$ + "*.*", 8)
	ON ERROR GOTO 0
	V$ = MID$(V$, 10) : J = INSTR(V$, ".")
	IF J THEN V$ = LEFT$(LEFT$(V$, J - 1) + SPACE$(8), 8) + MID$(V$, J + 1)
	PRINT "Directory PATH listing";
	IF V$ <> "" THEN PRINT " for Volume "; V$ ELSE PRINT
	PRINT S$
	' P$(0) is the starting directory, ending with ":" or the path character
	IF RIGHT$(S$, 1) <> ":" AND RIGHT$(S$, 1) <> PC$ THEN S$ = S$ + PC$
	L = 0 : P$(0) = S$ : X$(0) = "" : B(0) = 0
	GOSUB 50
	IF C(0) = 0 THEN PRINT "No subdirectories exist"
	' Visit the next subdirectory at level L, or if there are no more, go
	' back to the previous level
10	IF I(L) < C(L) THEN GOTO 20
	L = L - 1
	IF L < 0 THEN END
	GOTO 10
20	J = B(L) + I(L) : I(L) = I(L) + 1
	Y$ = G3$ : IF I(L) = C(L) THEN Y$ = "    " : PRINT X$(L); G2$; N$(J)
	IF Y$ = G3$ THEN PRINT X$(L); G1$; N$(J)
	IF L = 32 THEN GOTO 10
	P$(L + 1) = P$(L) + N$(J) + PC$ : X$(L + 1) = X$(L) + Y$
	B(L + 1) = B(L) + C(L) : L = L + 1
	GOSUB 50
	GOTO 10
50	' List the subdirectories of P$(L) in N$ (starting at B(L)), and for /F,
	' display its files (with the prefix that its subdirectories, if any,
	' continue)
	C(L) = 0 : I(L) = 0 : N = 0
	E$ = DIR$(P$(L) + "*.*", &H16)
	WHILE E$ <> ""
	A$ = MID$(E$, 10)
	IF (ASC(E$) AND &H10) = 0 THEN N = N + 1 : GOTO 60
	IF A$ = "." OR A$ = ".." OR B(L) + C(L) > 400 THEN GOTO 60
	N$(B(L) + C(L)) = A$ : C(L) = C(L) + 1
60	E$ = DIR$
	WEND
	IF F = 0 OR N = 0 THEN RETURN
	Y$ = X$(L) + "    " : IF C(L) THEN Y$ = X$(L) + G3$
	E$ = DIR$(P$(L) + "*.*", 6)
	WHILE E$ <> ""
	PRINT Y$; MID$(E$, 10)
	E$ = DIR$
	WEND
	PRINT Y$
	RETURN
90	PRINT "Invalid drive specification" : END
95	PRINT "Usage: TREE [drive:][path] ["; W$; "F] ["; W$; "A]"
