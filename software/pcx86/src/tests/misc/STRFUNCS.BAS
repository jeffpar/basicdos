10 REM STRFUNCS.BAS: BASIC-DOS string function tests (prints "failed" on error)
20 DEFINT A-Z
30 A$ = "HELLO" : B$ = A$ + " WORLD" : E$ = ""
40 IF B$ <> "HELLO WORLD" THEN PRINT "concatenation failed"
50 IF A$ + "" <> A$ OR "" + A$ <> A$ OR E$ + E$ <> "" THEN PRINT "empty concatenation failed"
60 IF LEN(B$) <> 11 OR LEN(E$) <> 0 OR LEN("") <> 0 THEN PRINT "LEN failed"
70 IF LEFT$(B$,5) <> "HELLO" OR LEFT$(B$,0) <> "" OR LEFT$(B$,99) <> B$ THEN PRINT "LEFT$ failed"
80 IF RIGHT$(B$,5) <> "WORLD" OR RIGHT$(B$,0) <> "" OR RIGHT$(B$,99) <> B$ THEN PRINT "RIGHT$ failed"
90 IF MID$(B$,3,4) <> "LLO " OR MID$(B$,7) <> "WORLD" OR MID$(B$,12) <> "" THEN PRINT "MID$ failed"
100 IF MID$(B$,1) <> B$ OR MID$(B$,11,5) <> "D" OR MID$(B$,2,0) <> "" THEN PRINT "MID$ edge failed"
110 IF ASC("A") <> 65 OR ASC(B$) <> 72 THEN PRINT "ASC failed"
120 IF CHR$(65) <> "A" OR LEN(CHR$(0)) <> 1 OR ASC(CHR$(255)) <> 255 THEN PRINT "CHR$ failed"
130 IF STR$(123) <> " 123" OR STR$(-5) <> "-5" OR STR$(1.5) <> " 1.5" THEN PRINT "STR$ failed"
140 IF VAL("123") <> 123 OR VAL(" -1 2.5") <> -12.5 OR VAL("1E3") <> 1000 THEN PRINT "VAL failed"
150 IF VAL("") <> 0 OR VAL("ABC") <> 0 OR VAL("12ABC") <> 12 THEN PRINT "VAL edge failed"
160 IF INSTR(B$,"WORLD") <> 7 OR INSTR(B$,"X") <> 0 OR INSTR(8,B$,"O") <> 8 THEN PRINT "INSTR failed"
170 IF INSTR(B$,"") <> 1 OR INSTR(3,B$,"") <> 3 OR INSTR(E$,"A") <> 0 THEN PRINT "INSTR edge failed"
180 IF INSTR(B$,"HELLO WORLD!") <> 0 OR INSTR(12,B$,"") <> 0 THEN PRINT "INSTR bound failed"
190 IF SPACE$(3) <> "   " OR SPACE$(0) <> "" THEN PRINT "SPACE$ failed"
200 IF STRING$(3,"*") <> "***" OR STRING$(2,65) <> "AA" OR STRING$(0,65) <> "" THEN PRINT "STRING$ failed"
210 IF HEX$(255) <> "FF" OR HEX$(0) <> "0" OR HEX$(-1) <> "FFFFFFFF" THEN PRINT "HEX$ failed"
220 IF OCT$(8) <> "10" OR OCT$(511) <> "777" THEN PRINT "OCT$ failed"
230 IF UCASE$("abC1") <> "ABC1" OR LCASE$("ABc1") <> "abc1" THEN PRINT "UCASE$/LCASE$ failed"
240 C$ = "abc" : D$ = UCASE$(C$)
250 IF C$ <> "abc" OR D$ <> "ABC" THEN PRINT "UCASE$ copy failed"
260 IF NOT ("A" < "B" AND "AB" > "A" AND "A" <= "A" AND "B" >= "A") THEN PRINT "compare failed"
270 IF "A" = "B" OR "" <> E$ OR "A" < "" OR "ABC" = "ABD" THEN PRINT "compare edge failed"
280 IF LEN(DATE$) <> 10 OR LEN(TIME$) <> 8 OR MID$(DATE$,3,1) <> "-" THEN PRINT "DATE$/TIME$ failed"
290 F$ = STRING$(200,"A") + STRING$(55,"B")
300 IF LEN(F$) <> 255 OR RIGHT$(F$,1) <> "B" THEN PRINT "max length failed"
310 DEF FNA$(X$) = X$ + X$
320 DEF FNB$(X$) = LEFT$(X$,1) + MID$(X$,2)
330 DEF FNC(X$, Y$) = LEN(X$) + LEN(Y$)
340 IF FNA$("AB") <> "ABAB" OR FNA$(A$ + "!") <> "HELLO!HELLO!" THEN PRINT "DEF FNA$ failed"
350 IF FNB$(A$ + "!") <> "HELLO!" OR FNB$(B$) <> B$ THEN PRINT "DEF FNB$ failed"
360 IF FNC(A$, "XY" + "Z") <> 8 THEN PRINT "DEF FNC failed"
370 G$ = A$ : A$ = "BYE"
380 IF G$ <> "HELLO" OR A$ <> "BYE" THEN PRINT "assignment copy failed"
390 G$ = G$ : G$ = G$ + G$
400 IF G$ <> "HELLOHELLO" THEN PRINT "self assignment failed"
410 H$ = MID$(G$, 3) : G$ = H$
420 IF G$ <> "LLOHELLO" OR H$ <> G$ THEN PRINT "MID$ assignment failed"
430 A! = 1.5 : A$ = "X" + STR$(A!)
440 IF A$ <> "X 1.5" THEN PRINT "suffix failed"
450 PRINT "STRFUNCS done"
