	' HEXDUMP.BAS: displays a file in hexadecimal
	'
	'   HEXDUMP file [/S offset] [/N length]
	'
	' Each line shows 16 bytes in the format of DEBUG's DB command: an
	' address, the bytes in hex (with a dash after the 8th byte), and the
	' bytes as characters (with a period for each one outside 20h-7Eh).
	' The address is the file offset, as a segment (1000h for each 64K) and
	' an offset.  /S starts at a decimal offset (default 0), and /N stops
	' after length bytes (default: the rest of the file); as in DEBUG, lines
	' begin at multiples of 16, so the first and last can be partial.
	' Options start with the switch char (W$), which is "/" unless
	' CONFIG.SYS changes it (eg, to "-").
	'
	' The file (P$) is read as 128-byte random access records (R$), so a
	' line never spans two records.  Each line is one PRINTF of the address,
	' the bytes (B), and their characters (L$), using the format in F$; a
	' partial line uses a copy (G$) that prints spaces (%-2c of 32) in place
	' of the bytes it doesn't display.
	'
	DEFINT A-Z
	DIM B(16)
	DOS &H3700 : W$ = CHR$(DOS(3) AND 255)
	N = -1 : I = 1 : A$ = ARG$(1)
	WHILE A$ <> ""
	C$ = UCASE$(A$)
	IF C$ = W$ + "S" THEN I = I + 1 : S = VAL(ARG$(I)) : GOTO 10
	IF C$ = W$ + "N" THEN I = I + 1 : N = VAL(ARG$(I)) : GOTO 10
	' Any other option, or a second file, is an error
	IF LEFT$(C$, 1) = W$ OR P$ <> "" THEN GOTO 90
	P$ = C$
10	I = I + 1 : A$ = ARG$(I)
	WEND
	' So is a negative offset (but a negative length means the rest)
	IF P$ = "" OR S < 0 THEN GOTO 90
	IF NOT EXISTS(P$) THEN PRINT "Unable to find "; P$ : END
	OPEN P$ AS #1 LEN = 128 : FIELD #1, 128 AS R$
	' E is the offset after the last byte to display (0 if there are none)
	E = LOF(1) : IF N >= 0 AND N < E - S THEN E = S + N
	IF E <= S THEN E = 0
	F$ = "%04x:%04x "
	FOR J = 1 TO 16 : F$ = F$ + "%02x " : NEXT
	MID$(F$, 50, 1) = "-" : F$ = F$ + " %s" : G$ = F$
	FOR R = S - S MOD 16 TO E - 1 STEP 16
	K = R \ 128 + 1 : IF K <> K0 THEN GET #1, K : K0 = K
	L$ = MID$(R$, (R AND 127) + 1, 16)
	' Columns J1 through J2 are the bytes to display
	J1 = S - R + 1 : IF J1 < 1 THEN J1 = 1
	J2 = E - R : IF J2 > 16 THEN J2 = 16
	IF J1 = 1 AND J2 = 16 THEN GOTO 20
	FOR J = 1 TO 16
	IF J < J1 OR J > J2 THEN B(J) = 32 : MID$(L$, J, 1) = " " : MID$(G$, J * 5 + 6, 4) = "%-2c"
	NEXT
20	FOR J = J1 TO J2
	B = ASC(MID$(L$, J, 1)) : B(J) = B
	IF B < 32 OR B > 126 THEN MID$(L$, J, 1) = "."
	NEXT
	PRINTF USING G$; (R \ 65536) * 4096, R AND 65535, B(1), B(2), B(3), B(4), B(5), B(6), B(7), B(8), B(9), B(10), B(11), B(12), B(13), B(14), B(15), B(16), L$
	IF J1 > 1 OR J2 < 16 THEN G$ = F$
	NEXT
	CLOSE
	END
90	PRINT "Usage: HEXDUMP file ["; W$; "S offset] ["; W$; "N length]"
