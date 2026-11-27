	' MODE.BAS: sets the display, a serial port, or a printer
	'
	'   MODE [video options|serial port options|parallel port options]
	'
	' Video options:
	'   40|80|132|BW40|BW80|CO40|CO80[,rows]  columns (and color), and rows
	'                                         (25, 43, or 50)
	'   FONT [file]                           font (EGA or VGA), or without a
	'                                         file, the adapter's own font
	' Serial port options:
	'   COMn:baud[,parity[,data[,stop]]]      eg, COM1:9600,N,8,1
	' Parallel port options:
	'   LPTn:[cols][,lines]                   printer columns (80 or 132) and
	'                                         lines per inch (6 or 8)
	'
	' A serial port is set by opening it with its parameters and an input
	' buffer length of 0, which initializes the port and releases it again (a
	' port that's already open, eg, the console, isn't changed).
	'
	' The console knows which rows the display adapter supports (43 needs
	' an EGA or VGA, and 50 needs a VGA), and anything else that it can't
	' display (eg, 40 columns on an MDA, or 132 on anything but a VT100
	' terminal) is an error, too.
	'
	DEFINT A-Z
	M$ = UCASE$(ARG$(1))
	IF LEFT$(M$, 3) = "COM" THEN GOTO 20
	IF LEFT$(M$, 3) = "LPT" THEN GOTO 30
	IF M$ = "FONT" THEN GOTO 40
	R$ = M$ + ","
	GOSUB 50 : M$ = I$
	GOSUB 50 : L$ = I$
	IF R$ <> "" THEN GOTO 990
	W$ = RIGHT$(M$, 2)
	IF M$ = "132" THEN W$ = M$ : M$ = "80"
	IF W$ <> "40" AND W$ <> "80" AND W$ <> "132" THEN GOTO 990
	IF LEN(M$) <> 2 AND LEFT$(M$, 2) <> "BW" AND LEFT$(M$, 2) <> "CO" THEN GOTO 990
	IF L$ <> "" AND L$ <> "25" AND L$ <> "43" AND L$ <> "50" THEN GOTO 990
	ON ERROR GOTO 900
	IF LEFT$(M$, 2) = "BW" THEN SCREEN 0, 0
	IF LEFT$(M$, 2) = "CO" THEN SCREEN 0, 1
	IF L$ = "" THEN WIDTH VAL(W$) ELSE WIDTH VAL(W$), VAL(L$)
	' Like PC DOS, clear the screen with the default colors (white on black,
	' and a white border), even if the mode didn't change
	COLOR 7, 0, 7 : CLS
	END
20	' Serial port: the parity, data bits, and stop bits default to N, 8, and 1,
	' and a two-digit baud rate is an abbreviation (eg, 96 for 9600)
	R$ = MID$(M$, 6) + ","
	GOSUB 50 : B$ = I$
	IF B$ = "11" THEN B$ = "110" ELSE IF LEN(B$) = 2 THEN B$ = B$ + "00"
	GOSUB 50 : P$ = I$ : IF P$ = "" THEN P$ = "N"
	GOSUB 50 : D$ = I$ : IF D$ = "" THEN D$ = "8"
	GOSUB 50 : S$ = I$ : IF S$ = "" THEN S$ = "1"
	IF B$ = "" OR INSTR("NOE", P$) = 0 THEN GOTO 990
	OPEN LEFT$(M$, 4) + ":" + B$ + "," + P$ + "," + D$ + "," + S$ + ",0" AS #1
	CLOSE #1
	END
30	' Printer: send the IBM/Epson codes for condensed (132 columns) or normal
	' (80 columns) print, and for 8 or 6 lines per inch
	R$ = MID$(M$, 6) + ","
	GOSUB 50 : C$ = I$
	GOSUB 50 : L$ = I$
	OPEN LEFT$(M$, 4) FOR OUTPUT AS #1
	IF C$ = "132" THEN PRINT #1, CHR$(15);
	IF C$ = "80" THEN PRINT #1, CHR$(18);
	IF L$ = "8" THEN PRINT #1, CHR$(27); "0";
	IF L$ = "6" THEN PRINT #1, CHR$(27); "2";
	CLOSE #1
	END
40	' Font: a file of 256 characters, each with LOF / 256 lines, goes to the
	' console (IOCTL &HDE) in records of up to 255 bytes (the most a string
	' holds); a file name without a path is in EXT\FONTS on the system drive
	F$ = ARG$(2)
	DOS &H3700 : IF LEFT$(F$, 1) = CHR$(DOS(3) AND 255) THEN GOTO 990
	IF ARG$(3) <> "" THEN GOTO 990
	ON ERROR GOTO 900
	OPEN "CON" FOR OUTPUT AS #1
	IF F$ = "" THEN IOCTL #1, &HDE, 0, 0 : END
	DOS &H3704 : A = DOS(3) : P$ = CHR$(A AND 255)
	IF INSTR(F$, ":") = 0 AND INSTR(F$, P$) = 0 THEN F$ = CHR$(A \ 256) + ":" + P$ + "EXT" + P$ + "FONTS" + P$ + F$
	OPEN F$ FOR INPUT AS #2 : L = LOF(2) : CLOSE #2
	H = L \ 256 : IF H = 0 OR L MOD 256 THEN ERROR 5 ' BERR_ILLFUNC
	N = 255 \ H
	OPEN F$ AS #2 LEN = N * H : FIELD #2, N * H AS D$
	FOR C = 0 TO 255 STEP N : GET #2 : IOCTL #1, &HDE, D$, H * 256 + C : NEXT
	CLOSE
	END
50	' Return the next comma-separated item of R$ in I$
	I = INSTR(R$, ",")
	IF I = 0 THEN I$ = "" : RETURN
	I$ = LEFT$(R$, I - 1) : R$ = MID$(R$, I + 1)
	RETURN
900	' Report a runtime error, whose number (ERR) is the exit code
	CLOSE
	IF ERR = 5 THEN PRINT "Illegal function call" : END ERR ' BERR_ILLFUNC
	IF ERR = 53 THEN PRINT "Unable to find "; F$ : END ERR ' BERR_NOFILE
	PRINT "Unable to set the mode (error"; ERR; ")" : END ERR
990	END 80 ' BERR_USAGE
