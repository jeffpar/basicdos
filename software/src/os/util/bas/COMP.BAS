	' COMP.BAS: compares files
	'
	'   COMP file1 file2
	'
	' Compares each file matching file1 (which can contain wildcards, but
	' doesn't match hidden files) with file2; if file2 is a drive or
	' directory, the file there with the same name is used.  As in PC DOS,
	' each difference is reported with its offset (in hex) and the bytes
	' from both files, until 10 differences have been found.
	'
	' Each match is compared as DIR$ finds it, since the search's state is
	' in the DTA, which neither EXISTS nor the file I/O disturbs.  The files
	' are opened for random access, with 128-byte records, and when two
	' records differ, their bytes are compared one at a time.  X is set if
	' any comparison fails, which ends the program with ERRORLEVEL 1.
	'
	DEFINT A-Z
	A$ = UCASE$(ARG$(1)) : B$ = UCASE$(ARG$(2))
	DOS &H3700 : W$ = CHR$(DOS(3) AND 255)
	IF A$ = "" OR B$ = "" OR ARG$(3) <> "" OR LEFT$(A$, 1) = W$ OR LEFT$(B$, 1) = W$ THEN PRINT "Syntax error" : END 1
	PC$ = MID$(CURDIR$, 3, 1)
	' P$ is file1's drive and directory, which each match's name follows
	FOR I = LEN(A$) TO 1 STEP -1
	IF MID$(A$, I, 1) = PC$ OR MID$(A$, I, 1) = ":" THEN GOTO 10
	NEXT
10	P$ = LEFT$(A$, I)
	ON ERROR GOTO 90
	' Unlike EXISTS, DIR$ reports an invalid drive, so use it to check file2,
	' and if file2 is a directory, end it with the path character
	C$ = RIGHT$(B$, 1) : F$ = DIR$(B$, &H16)
	IF C$ <> ":" AND C$ <> PC$ AND F$ <> "" THEN IF ASC(F$) AND &H10 THEN B$ = B$ + PC$
	' Like DIR, include system files, but not hidden files
	F$ = DIR$(A$, 4)
	IF F$ = "" THEN PRINT "Unable to find "; A$ : END 1
20	F1$ = P$ + MID$(F$, 10) : F2$ = B$
	C$ = RIGHT$(B$, 1) : IF C$ = ":" OR C$ = PC$ THEN F2$ = B$ + MID$(F$, 10)
	PRINT F1$; " and "; F2$
	IF NOT EXISTS(F2$) THEN PRINT "Unable to find "; F2$ : X = 1 : GOTO 70
	OPEN F1$ AS #1 LEN = 128 : FIELD #1, 128 AS R1$
	OPEN F2$ AS #2 LEN = 128 : FIELD #2, 128 AS R2$
	L = LOF(1)
	IF L <> LOF(2) THEN PRINT "Files are different sizes" : X = 1 : GOTO 60
	E = 0
	FOR R = 1 TO (L + 127) \ 128
	GET #1, R : GET #2, R
	IF R1$ = R2$ THEN GOTO 50
	K = L - (R - 1) * 128 : IF K > 128 THEN K = 128
	FOR J = 1 TO K
	IF MID$(R1$, J, 1) = MID$(R2$, J, 1) THEN GOTO 40
	PRINT "Compare error at OFFSET "; HEX$((R - 1) * 128 + J - 1)
	PRINT "File 1 = "; HEX$(ASC(MID$(R1$, J, 1)))
	PRINT "File 2 = "; HEX$(ASC(MID$(R2$, J, 1)))
	E = E + 1 : X = 1
	IF E = 10 THEN PRINT "10 Mismatches - ending compare" : GOTO 60
40	NEXT
50	NEXT
	IF E = 0 THEN PRINT "Files compare ok"
60	CLOSE
70	F$ = DIR$
	IF F$ <> "" THEN PRINT : GOTO 20
	END X
90	CLOSE : X = 1
	IF ERR = 77 THEN PRINT "Invalid drive" : END 1
	' A file that's open for random access (read/write) can't be opened
	' again, so a file can't be compared with itself, unless it's read-only
	IF ERR = 55 THEN PRINT "Unable to open both files (the same file?)" : RESUME 70
	PRINT "Unable to compare (error"; ERR; ")"
	RESUME 70
