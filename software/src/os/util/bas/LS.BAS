	' LS.BAS: lists files and directories, like the UNIX ls command
	'
	'   LS [-1aFlRrSt] [filespec]...
	'
	' Lists each directory (default ".") and the matches of each other
	' filespec, sorted, in columns (or one per line, with -1 or when output
	' is to a file or pipe).  -l is a long listing, -a includes hidden files
	' and names beginning with ".", -F marks directories and programs, -t
	' and -S sort by time and size, -r reverses the order, and -R lists
	' subdirectories, too.
	'
	' A listing's entries (DIR$ strings, with names as displayed) are in
	' E$, their sort keys in K$, and their order in P; the directories still
	' to be listed are in D$.
	'
	DEFINT A-Z
	DIM E$(512), K$(512), P(512), D$(255), Z(6)
	' Options set Z (-1, -a, -F, -l, -R, and -r, in order), or for -S or
	' -t, K (the position after the bytes to sort on); NA counts filespecs
	I = 1 : A$ = ARG$(1)
	WHILE A$ <> ""
	IF LEFT$(A$, 1) <> "-" THEN NA = NA + 1 : GOTO 10
	FOR J = 2 TO LEN(A$)
	C = INSTR("1aFlRrSt", MID$(A$, J, 1))
	IF C = 0 THEN GOTO 90
	IF C < 7 THEN Z(C) = -1
	IF C = 7 THEN K = 10
	IF C = 8 THEN K = 6
	NEXT
10	I = I + 1 : A$ = ARG$(I)
	WEND
	O = Z(1) : A = Z(2) : F = Z(3) : L = Z(4) : R = Z(5) : V = Z(6)
	' Columns fit the console's width (W); output that isn't to a console
	' (eg, a file or pipe, which don't support IOCTL &HD1) gets one name
	' per line
	ON ERROR GOTO 95
	DOS &H44D1, 1 : W = DOS(3) AND 255
20	ON ERROR GOTO 0
	' Dates after T0 (6 months before today, TD) up to today show the time
	T$ = DATE$ : M = VAL(T$)
	TD = (VAL(MID$(T$, 7)) - 1980) * 512 + M * 32 + VAL(MID$(T$, 4))
	T0 = TD - 192 : IF M <= 6 THEN T0 = TD - 320
	MO$ = "   JanFebMarAprMayJunJulAugSepOctNovDec"
	PC$ = MID$(CURDIR$, 3, 1)
	' Add the matches of each filespec that isn't a directory (eg, *.BAS),
	' named with its drive and path (Q$), and keep directories in D$
	I = 1 : A$ = ARG$(1)
	WHILE A$ <> ""
	IF LEFT$(A$, 1) = "-" THEN GOTO 30
	A$ = UCASE$(A$) : Y$ = A$
	IF INSTR(":" + PC$, RIGHT$(A$, 1)) = 0 THEN Y$ = A$ + PC$
	IF DIR$(Y$ + "*.*") <> "" THEN ND = ND + 1 : D$(ND) = A$ : GOTO 30
	Q$ = ""
	FOR J = 1 TO LEN(A$)
	IF INSTR(":" + PC$, MID$(A$, J, 1)) THEN Q$ = LEFT$(A$, J)
	NEXT
	N0 = N : F$ = DIR$(A$)
	WHILE F$ <> ""
	GOSUB 200 : F$ = DIR$
	WEND
	IF N = N0 THEN PRINT "Unable to find "; A$
30	I = I + 1 : A$ = ARG$(I)
	WEND
	IF NA = 0 THEN ND = 1 : D$(1) = "."
	FOR J = 1 TO ND \ 2 : SWAP D$(J), D$(ND + 1 - J) : NEXT
	IF N THEN GOSUB 100 : GOSUB 110 : G = 1
	' Then list each directory, after its name (if there's more than one
	' filespec, or -R), followed for -R by its subdirectories
40	IF ND = 0 THEN END
	A$ = D$(ND) : ND = ND - 1 : N = 0 : Q$ = "" : Y$ = A$
	IF INSTR(":" + PC$, RIGHT$(A$, 1)) = 0 THEN Y$ = A$ + PC$
	F$ = DIR$(Y$ + "*.*")
	WHILE F$ <> ""
	GOSUB 200 : F$ = DIR$
	WEND
	IF G THEN PRINT
	IF NA > 1 OR R THEN PRINT A$; ":"
	GOSUB 100
	IF L THEN PRINT "total" + STR$(T)
	GOSUB 110 : G = 1
	IF R = 0 THEN GOTO 40
	FOR J = N TO 1 STEP -1
	F$ = E$(P(J)) : GOSUB 150 : N$ = MID$(F$, 10)
	IF DR AND LEFT$(N$, 1) <> "." THEN ND = ND + 1 : D$(ND) = Y$ + N$
	NEXT
	GOTO 40
100	' Sort P by the keys (a Shell sort, with gaps of ..., 13, 4, and 1),
	' reverse it for -r, and find the longest name (NW) and size (SW), and
	' the total size in K (T)
	H = 1 : WHILE H < N : H = H * 3 + 1 : WEND
	WHILE H > 1
	H = H \ 3
	FOR I = H + 1 TO N
	X = P(I) : K$ = K$(X) : J = I
105	IF J > H THEN IF K$(P(J - H)) > K$ THEN P(J) = P(J - H) : J = J - H : GOTO 105
	P(J) = X
	NEXT
	WEND
	IF V THEN FOR J = 1 TO N \ 2 : SWAP P(J), P(N + 1 - J) : NEXT
	NW = 0 : SW = 0 : T = 0
	FOR J = 1 TO N
	F$ = E$(P(J)) : GOSUB 150 : S$ = STR$(CVL(MID$(F$, 6)))
	IF LEN(N$) > NW THEN NW = LEN(N$)
	IF LEN(S$) > SW THEN SW = LEN(S$)
	T = T + (CVL(MID$(F$, 6)) + 1023) \ 1024
	NEXT
	RETURN
110	' Display the names in as many columns as fit (each 2 wider than the
	' longest name, except the last), filled down the screen
	IF L THEN GOTO 120
	C = (W + 1) \ (NW + 2) : IF O OR C = 0 THEN C = 1
	RW = (N + C - 1) \ C
	FOR I = 1 TO RW
	FOR J = I TO N STEP RW
	F$ = E$(P(J)) : GOSUB 150 : PRINT N$;
	IF J + RW <= N THEN PRINT SPACE$(NW + 2 - LEN(N$));
	NEXT
	PRINT
	NEXT
	RETURN
120	' Display each name's mode, links, size, and date (X) and time (Y)
	FOR J = 1 TO N
	F$ = E$(P(J)) : GOSUB 150 : S$ = STR$(CVL(MID$(F$, 6)))
	M$ = "-rw-r--r--" : IF EX THEN M$ = "-rwxr-xr-x"
	IF DR THEN M$ = "drwxr-xr-x"
	IF ASC(F$) AND 1 THEN MID$(M$, 3, 1) = "-"
	X = CVI(MID$(F$, 4)) AND 65535 : Y = CVI(MID$(F$, 2)) AND 65535
	T$ = STR$(10000 + (Y \ 2048) * 100 + ((Y \ 32) AND 63))
	T$ = MID$(T$, 3, 2) + ":" + RIGHT$(T$, 2)
	IF X <= T0 OR X > TD THEN T$ = STR$(X \ 512 + 1980)
	PRINT M$; " 1"; SPACE$(SW - LEN(S$)); S$;
	M = (X \ 32) AND 15 : PRINT " "; MID$(MO$, M * 3 + 1, 3);
	PRINT RIGHT$(" " + STR$(X AND 31), 3); " "; T$; " "; N$
	NEXT
	RETURN
150	' Set N$ to entry F$'s name (with -F's suffix), DR if it's a directory,
	' and EX if it's a program
	N$ = MID$(F$, 10) : DR = (ASC(F$) AND &H10) <> 0
	EX = INSTR(" .COM .EXE .BAT .BAS", " " + RIGHT$(N$, 4)) > 0
	IF F AND DR THEN N$ = N$ + PC$
	IF F AND EX AND NOT DR THEN N$ = N$ + "*"
	RETURN
200	' Add entry F$, with Q$ before its name, unless it's hidden or its
	' name begins with a period (without -a), and its sort key: the name,
	' after the 4 bytes before K (inverted, so -S and -t sort descending)
	IF NOT A AND ((ASC(F$) AND 2) <> 0 OR MID$(F$, 10, 1) = ".") THEN RETURN
	N = N + 1 : E$(N) = LEFT$(F$, 9) + Q$ + MID$(F$, 10) : K$ = ""
	IF K THEN FOR J = 1 TO 4 : K$ = K$ + CHR$(255 - ASC(MID$(F$, K - J))) : NEXT
	K$(N) = K$ + MID$(E$(N), 10) : P(N) = N
	RETURN
90	PRINT "Usage: LS [-1aFlRrSt] [filespec]..."
	END
95	O = -1 : RESUME 20
