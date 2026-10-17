	' MODE.BAS: sets the display, a serial port, or a printer
	'
	'   MODE 40|80|BW40|BW80|CO40|CO80          display columns (and color)
	'   MODE COMn:baud[,parity[,data[,stop]]]   serial port (eg, COM1:9600,N,8,1)
	'   MODE LPTn:[cols][,lines]                printer columns (80 or 132) and
	'                                           lines per inch (6 or 8)
	'
	' A serial port is set by opening it with its parameters and an input
	' buffer length of 0, which initializes the port and releases it again (a
	' port that's already open, eg, the console, isn't changed).
	'
	DEFINT A-Z
	M$ = UCASE$(ARG$(1))
	IF LEFT$(M$, 3) = "COM" THEN GOTO 20
	IF LEFT$(M$, 3) = "LPT" THEN GOTO 30
	W$ = RIGHT$(M$, 2)
	IF W$ <> "40" AND W$ <> "80" THEN GOTO 40
	IF LEN(M$) <> 2 AND LEFT$(M$, 2) <> "BW" AND LEFT$(M$, 2) <> "CO" THEN GOTO 40
	IF LEFT$(M$, 2) = "BW" THEN SCREEN 0, 0
	IF LEFT$(M$, 2) = "CO" THEN SCREEN 0, 1
	IF W$ = "40" THEN WIDTH 40 ELSE WIDTH 80
	END
20	' Serial port: the parity, data bits, and stop bits default to N, 8, and 1,
	' and a two-digit baud rate is an abbreviation (eg, 96 for 9600)
	R$ = MID$(M$, 6) + ","
	GOSUB 50 : B$ = I$
	IF B$ = "11" THEN B$ = "110" ELSE IF LEN(B$) = 2 THEN B$ = B$ + "00"
	GOSUB 50 : P$ = I$ : IF P$ = "" THEN P$ = "N"
	GOSUB 50 : D$ = I$ : IF D$ = "" THEN D$ = "8"
	GOSUB 50 : S$ = I$ : IF S$ = "" THEN S$ = "1"
	IF B$ = "" OR INSTR("NOE", P$) = 0 THEN GOTO 40
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
40	PRINT "Usage: MODE 40|80|BW40|BW80|CO40|CO80"
	PRINT "       MODE COMn:baud[,parity[,data[,stop]]]"
	PRINT "       MODE LPTn:[cols][,lines]"
	END
50	' Return the next comma-separated item of R$ in I$
	I = INSTR(R$, ",")
	IF I = 0 THEN I$ = "" : RETURN
	I$ = LEFT$(R$, I - 1) : R$ = MID$(R$, I + 1)
	RETURN
