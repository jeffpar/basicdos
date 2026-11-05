	' ATTRIB.BAS: displays or changes the attributes of files
	'
	'   ATTRIB [+R|-R] [+H|-H] [+S|-S] [+A|-A] [filespec]
	'
	' Lists each file matching filespec (default *.*), including hidden
	' and system files, with its attributes: A (archive), S (system), H
	' (hidden), and R (read-only).  Attributes given with + are set first,
	' and those given with - are cleared (with DOS function &H4301); one +
	' or - can be followed by several attributes (eg, +RS).
	'
	DEFINT A-Z
	DOS &H3700 : W$ = CHR$(DOS(3) AND 255)
	S$ = "*.*" : SM = 0 : CM = 0 : A = 0
	I = 1 : A$ = UCASE$(ARG$(1))
	WHILE A$ <> ""
	C$ = LEFT$(A$, 1)
	IF C$ <> "+" AND C$ <> "-" THEN IF C$ = W$ OR F THEN GOTO 90
	IF C$ <> "+" AND C$ <> "-" THEN S$ = A$ : F = 1 : GOTO 10
	IF LEN(A$) = 1 THEN GOTO 90
	FOR J = 2 TO LEN(A$)
	' The attribute bits are 1 (R), 2 (H), 4 (S), and 32 (A)
	B = INSTR("RHS", MID$(A$, J, 1)) : IF B = 3 THEN B = 4
	IF MID$(A$, J, 1) = "A" THEN B = 32
	IF B = 0 THEN GOTO 90
	IF C$ = "+" THEN SM = SM OR B ELSE CM = CM OR B
	NEXT
10	I = I + 1 : A$ = UCASE$(ARG$(I))
	WEND
	' P$ is the directory part of the filespec, which each name is added to
	C$ = MID$(CURDIR$, 3, 1)
	FOR I = LEN(S$) TO 1 STEP -1
	IF MID$(S$, I, 1) = C$ OR MID$(S$, I, 1) = ":" THEN GOTO 20
	NEXT
20	P$ = LEFT$(S$, I)
	DEF FNA$(M, L$) = MID$(" " + L$, 1 - ((A AND M) <> 0), 1)
	ON ERROR GOTO 80
	F$ = DIR$(S$, 6)
	ON ERROR GOTO 0
	IF F$ = "" THEN PRINT "Unable to find "; S$ : END 1
30	A = ASC(F$) : N$ = MID$(F$, 10)
	B = (A AND NOT CM) OR SM
	IF B <> A THEN DOS &H4301, 0, B, P$ + N$ : A = B
	PRINT "  "; FNA$(32, "A"); "  "; FNA$(4, "S"); FNA$(2, "H");
	PRINT FNA$(1, "R"); "     "; P$; N$
	F$ = DIR$
	IF F$ <> "" THEN GOTO 30
	END
80	PRINT "Invalid drive" : END 1
90	PRINT "Syntax error" : END 1
