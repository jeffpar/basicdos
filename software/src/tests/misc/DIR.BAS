	' DIR.BAS: displays a directory listing like DIR, using DIR$
	'
	'   DIR.BAS [filespec] [/A]
	'
	' Each DIR$ result contains a file's attributes (1 byte), time (2), date
	' (2), and size (4), followed by its name.  As with DIR, hidden files are
	' listed only with /A, with a "*" after the name.  Unlike DIR, the total
	' is the sum of the file sizes (not of the clusters they occupy), there's
	' no free space line, and the directory's path is shown as given (eg, ..
	' isn't resolved), after the current directory if it's relative to it.
	'
	DEFINT A-Z
	' The attributes (A) include system files and directories, and with /A,
	' hidden files
	S$ = "" : A = &H14
	FOR I = 1 TO 2
	X$ = UCASE$(ARG$(I))
	IF X$ = "/A" OR X$ = "-A" THEN A = &H16 ELSE IF X$ <> "" THEN S$ = X$
	NEXT
	C$ = MID$(CURDIR$, 3, 1) : D$ = LEFT$(CURDIR$, 2)
	IF MID$(S$, 2, 1) = ":" THEN D$ = LEFT$(S$, 2)
	' A filespec that ends with ":" or the path char, or that names a
	' directory (without wildcards), lists all the files in the directory
	R$ = RIGHT$(S$, 1)
	IF S$ = "" OR R$ = ":" OR R$ = C$ THEN S$ = S$ + "*.*" : GOTO 10
	F$ = DIR$(S$, 16) : IF F$ = "" THEN GOTO 10
	IF ASC(F$) AND 16 AND INSTR(S$, "*") = 0 AND INSTR(S$, "?") = 0 THEN S$ = S$ + C$ + "*.*"
10	F$ = DIR$(S$, A)
	IF F$ = "" THEN PRINT "Unable to find "; S$ : END
	' Display the volume label and the directory, which is the filespec's
	' path (up to its last path char), relative to the current directory
	V$ = DIR$(D$ + C$ + "*.*", 8)
	PRINT : PRINT " Volume in drive "; LEFT$(D$, 1);
	IF V$ = "" THEN PRINT " has no label" ELSE F$ = V$ : GOSUB 50 : PRINTF USING " is %-8s%s"; N$, E$
	I = 0
	WHILE INSTR(I + 1, S$, C$) : I = INSTR(I + 1, S$, C$) : WEND
	P$ = LEFT$(S$, I) : IF MID$(P$, 2, 1) = ":" THEN P$ = MID$(P$, 3)
	IF LEN(P$) > 1 THEN P$ = LEFT$(P$, LEN(P$) - 1)
	IF LEFT$(P$, 1) = C$ OR D$ <> LEFT$(CURDIR$, 2) THEN GOTO 20
	Q$ = MID$(CURDIR$, 3)
	IF Q$ <> C$ AND P$ <> "" THEN Q$ = Q$ + C$
	P$ = Q$ + P$
20	PRINT " Directory of "; D$; P$ : PRINT
	' List each match, with its size (or <DIR>), date, and time
	F$ = DIR$(S$, A) : N = 0 : T = 0
	WHILE F$ <> ""
	K$ = " " : IF ASC(F$) AND 2 THEN K$ = "*"
	GOSUB 50 : PRINTF USING "%-8s %-3s%s"; N$, E$, K$;
	L = CVL(MID$(F$, 6, 4))
	IF ASC(F$) AND 16 THEN PRINT "  <DIR>"; ELSE PRINTF USING "%7d"; L;
	X = CVI(MID$(F$, 2, 2)) : IF X < 0 THEN X = X + 65536
	H = X \ 2048 : M = (X \ 32) AND 63 : A$ = "a"
	IF H >= 12 THEN H = H - 12 : A$ = "p"
	IF H = 0 THEN H = 12
	X = CVI(MID$(F$, 4, 2)) : IF X < 0 THEN X = X + 65536
	PRINTF USING " %2d-%02d-%02d %2d:%02d%s"; (X \ 32) AND 15, X AND 31, (X \ 512 + 80) MOD 100, H, M, A$
	N = N + 1 : T = T + L
	F$ = DIR$
	WEND
	PRINTF USING "%8d file(s) %8d bytes"; N, T
	END
50	' Split the name in F$ into N$ and E$ ("." and ".." have no extension)
	N$ = MID$(F$, 10) : E$ = "" : I = INSTR(N$, ".")
	IF I > 1 THEN E$ = MID$(N$, I + 1) : N$ = LEFT$(N$, I - 1)
	RETURN
