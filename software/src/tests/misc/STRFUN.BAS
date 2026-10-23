10 REM STRFUN.BAS: BASIC-DOS string function tests (prints "failed" on error)
20 DEFINT A-Z
30 A$ = "HELLO" : B$ = A$ + " WORLD" : E$ = ""
40 IF B$ <> "HELLO WORLD" THEN PRINT "concatenation failed" : FAILS = FAILS + 1
50 IF A$ + "" <> A$ OR "" + A$ <> A$ OR E$ + E$ <> "" THEN PRINT "empty concatenation failed" : FAILS = FAILS + 1
60 IF LEN(B$) <> 11 OR LEN(E$) <> 0 OR LEN("") <> 0 THEN PRINT "LEN failed" : FAILS = FAILS + 1
70 IF LEFT$(B$,5) <> "HELLO" OR LEFT$(B$,0) <> "" OR LEFT$(B$,99) <> B$ THEN PRINT "LEFT$ failed" : FAILS = FAILS + 1
80 IF RIGHT$(B$,5) <> "WORLD" OR RIGHT$(B$,0) <> "" OR RIGHT$(B$,99) <> B$ THEN PRINT "RIGHT$ failed" : FAILS = FAILS + 1
90 IF MID$(B$,3,4) <> "LLO " OR MID$(B$,7) <> "WORLD" OR MID$(B$,12) <> "" THEN PRINT "MID$ failed" : FAILS = FAILS + 1
100 IF MID$(B$,1) <> B$ OR MID$(B$,11,5) <> "D" OR MID$(B$,2,0) <> "" THEN PRINT "MID$ edge failed" : FAILS = FAILS + 1
110 IF ASC("A") <> 65 OR ASC(B$) <> 72 THEN PRINT "ASC failed" : FAILS = FAILS + 1
120 IF CHR$(65) <> "A" OR LEN(CHR$(0)) <> 1 OR ASC(CHR$(255)) <> 255 THEN PRINT "CHR$ failed" : FAILS = FAILS + 1
130 IF STR$(123) <> " 123" OR STR$(-5) <> "-5" OR STR$(1.5) <> " 1.5" THEN PRINT "STR$ failed" : FAILS = FAILS + 1
140 IF VAL("123") <> 123 OR VAL(" -1 2.5") <> -12.5 OR VAL("1E3") <> 1000 THEN PRINT "VAL failed" : FAILS = FAILS + 1
150 IF VAL("") <> 0 OR VAL("ABC") <> 0 OR VAL("12ABC") <> 12 THEN PRINT "VAL edge failed" : FAILS = FAILS + 1
155 IF VAL("&HFF") <> 255 OR VAL(" &h 1f") <> 31 OR VAL("&O17") <> 15 OR VAL("&17") <> 15 OR VAL("&HFFFFFFFF") <> -1 OR VAL("&H") <> 0 THEN PRINT "VAL &H/&O failed" : FAILS = FAILS + 1
160 IF INSTR(B$,"WORLD") <> 7 OR INSTR(B$,"X") <> 0 OR INSTR(8,B$,"O") <> 8 THEN PRINT "INSTR failed" : FAILS = FAILS + 1
170 IF INSTR(B$,"") <> 1 OR INSTR(3,B$,"") <> 3 OR INSTR(E$,"A") <> 0 THEN PRINT "INSTR edge failed" : FAILS = FAILS + 1
180 IF INSTR(B$,"HELLO WORLD!") <> 0 OR INSTR(12,B$,"") <> 0 THEN PRINT "INSTR bound failed" : FAILS = FAILS + 1
190 IF SPACE$(3) <> "   " OR SPACE$(0) <> "" THEN PRINT "SPACE$ failed" : FAILS = FAILS + 1
200 IF STRING$(3,"*") <> "***" OR STRING$(2,65) <> "AA" OR STRING$(0,65) <> "" THEN PRINT "STRING$ failed" : FAILS = FAILS + 1
210 IF HEX$(255) <> "FF" OR HEX$(0) <> "0" OR HEX$(-1) <> "FFFFFFFF" THEN PRINT "HEX$ failed" : FAILS = FAILS + 1
220 IF OCT$(8) <> "10" OR OCT$(511) <> "777" THEN PRINT "OCT$ failed" : FAILS = FAILS + 1
230 IF UCASE$("abC1") <> "ABC1" OR LCASE$("ABc1") <> "abc1" THEN PRINT "UCASE$/LCASE$ failed" : FAILS = FAILS + 1
240 C$ = "abc" : D$ = UCASE$(C$)
250 IF C$ <> "abc" OR D$ <> "ABC" THEN PRINT "UCASE$ copy failed" : FAILS = FAILS + 1
260 IF NOT ("A" < "B" AND "AB" > "A" AND "A" <= "A" AND "B" >= "A") THEN PRINT "compare failed" : FAILS = FAILS + 1
270 IF "A" = "B" OR "" <> E$ OR "A" < "" OR "ABC" = "ABD" THEN PRINT "compare edge failed" : FAILS = FAILS + 1
280 IF LEN(DATE$) <> 10 OR LEN(TIME$) <> 8 OR MID$(DATE$,3,1) <> "-" THEN PRINT "DATE$/TIME$ failed" : FAILS = FAILS + 1
290 F$ = STRING$(200,"A") + STRING$(55,"B")
300 IF LEN(F$) <> 255 OR RIGHT$(F$,1) <> "B" THEN PRINT "max length failed" : FAILS = FAILS + 1
310 DEF FNA$(X$) = X$ + X$
320 DEF FNB$(X$) = LEFT$(X$,1) + MID$(X$,2)
330 DEF FNC(X$, Y$) = LEN(X$) + LEN(Y$)
340 IF FNA$("AB") <> "ABAB" OR FNA$(A$ + "!") <> "HELLO!HELLO!" THEN PRINT "DEF FNA$ failed" : FAILS = FAILS + 1
350 IF FNB$(A$ + "!") <> "HELLO!" OR FNB$(B$) <> B$ THEN PRINT "DEF FNB$ failed" : FAILS = FAILS + 1
360 IF FNC(A$, "XY" + "Z") <> 8 THEN PRINT "DEF FNC failed" : FAILS = FAILS + 1
370 G$ = A$ : A$ = "BYE"
380 IF G$ <> "HELLO" OR A$ <> "BYE" THEN PRINT "assignment copy failed" : FAILS = FAILS + 1
390 G$ = G$ : G$ = G$ + G$
400 IF G$ <> "HELLOHELLO" THEN PRINT "self assignment failed" : FAILS = FAILS + 1
410 H$ = MID$(G$, 3) : G$ = H$
420 IF G$ <> "LLOHELLO" OR H$ <> G$ THEN PRINT "MID$ assignment failed" : FAILS = FAILS + 1
430 A! = 1.5 : A$ = "X" + STR$(A!)
440 IF A$ <> "X 1.5" THEN PRINT "suffix failed" : FAILS = FAILS + 1
441 S1$ = "ONE" + "" : S2$ = "TWO" + "" : SWAP S1$, S2$
442 IF S1$ <> "TWO" OR S2$ <> "ONE" THEN PRINT "SWAP strings failed" : FAILS = FAILS + 1
443 X = FRE(0) : IF S1$ <> "TWO" OR S2$ <> "ONE" THEN PRINT "SWAP owners failed" : FAILS = FAILS + 1
444 IF SPC(3) <> "   " OR LEN(SPC(0)) <> 0 THEN PRINT "SPC failed" : FAILS = FAILS + 1
445 IF MID$(CURDIR$,2,1) <> ":" OR LEN(CURDIR$) < 3 THEN PRINT "CURDIR$ failed" : FAILS = FAILS + 1
446 MS$ = "HELLO WORLD" : MID$(MS$,7) = "THERE" : MID$(MS$,1,2) = "xyz" : IF MS$ <> "xyLLO THERE" THEN PRINT "MID$ statement failed" : FAILS = FAILS + 1
447 MID$(MS$,11) = "ABC" : MID$(MS$,3,0) = "QQ" : DIM MA$(2) : MA$(1) = "ABCDE" : MID$(MA$(1),2,2) = "xyz" : IF MS$ <> "xyLLO THERA" OR MA$(1) <> "AxyDE" THEN PRINT "MID$ statement edge failed" : FAILS = FAILS + 1
448 FOR I = 1 TO 2 : ML$ = "LIT" : MC = MC + (ML$ <> "LIT") : MID$(ML$,1) = "B" : NEXT : IF MC OR ML$ <> "BIT" THEN PRINT "MID$ statement literal failed" : FAILS = FAILS + 1
450 IF FAILS THEN PRINT "STRFUN failed" ELSE PRINT "STRFUN passed"
