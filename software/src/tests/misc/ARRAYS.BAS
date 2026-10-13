10 REM ARRAYS.BAS: BASIC-DOS array tests (prints "failed" on error)
20 DEFINT A-Z
30 F0 = FRE(0)
40 DIM A(10), D#(5), S$(20), M(3,4), T(2,3,4)
50 IF A(0) <> 0 OR A(10) <> 0 OR D#(5) <> 0 OR S$(20) <> "" THEN PRINT "default values failed"
60 I = 0
70 A(I) = I * I : I = I + 1 : IF I <= 10 THEN GOTO 70
80 I = 0 : T = 0
90 T = T + A(I) : I = I + 1 : IF I <= 10 THEN GOTO 90
100 IF T <> 385 THEN PRINT "sum failed:"; T
110 D#(1) = 1.5 : D#(2) = D#(1) * 2 + .25
120 IF D#(2) <> 3.25 THEN PRINT "double element failed"
130 I = 0
140 J = 0
150 M(I,J) = I * 10 + J : J = J + 1 : IF J <= 4 THEN GOTO 150
160 I = I + 1 : IF I <= 3 THEN GOTO 140
170 IF M(0,0) <> 0 OR M(3,4) <> 34 OR M(2,1) <> 21 OR M(1,4) <> 14 THEN PRINT "2-D failed"
180 T(2,3,4) = 234 : T(1,2,3) = 123 : T(0,0,0) = -1
190 IF T(2,3,4) <> 234 OR T(1,2,3) <> 123 OR T(0,0,0) <> -1 OR T(2,3,3) <> 0 THEN PRINT "3-D failed"
200 IF A(A(2)) <> 16 OR M(A(1), A(2)) <> 14 THEN PRINT "nested subscript failed"
210 A = 5 : A$ = "X" : DIM A$(2) : A$(1) = "Y"
220 IF A <> 5 OR A(1) <> 1 OR A$ <> "X" OR A$(1) <> "Y" OR A$(0) <> "" THEN PRINT "name separation failed"
230 X(10) = 99 : Y$(0) = "AUTO"
240 IF X(10) <> 99 OR X(0) <> 0 OR Y$(0) <> "AUTO" THEN PRINT "automatic DIM failed"
250 DEF FNE(I) = A(I) * 2
260 IF FNE(3) <> 18 THEN PRINT "DEF FN failed"
270 LET A(4) = 7 : A(5) = A(4) + A(5)
280 IF A(4) <> 7 OR A(5) <> 32 THEN PRINT "LET failed"
290 S$(0) = "AB" : S$(1) = S$(0) + "CD" : S$(0) = S$(0) + "!"
300 IF S$(0) <> "AB!" OR S$(1) <> "ABCD" OR LEN(S$(1)) <> 4 THEN PRINT "string element failed"
310 B$ = S$(1) : S$(1) = "Z"
320 IF B$ <> "ABCD" OR S$(1) <> "Z" THEN PRINT "string copy failed"
330 N = 0
340 I = 0
350 S$(I) = STRING$((I * 7 + N) MOD 40, 65 + I) : I = I + 1 : IF I <= 20 THEN GOTO 350
360 I = 0
370 IF S$(I) <> STRING$((I * 7 + N) MOD 40, 65 + I) THEN PRINT "string array failed at"; N; I
380 I = I + 1 : IF I <= 20 THEN GOTO 370
390 N = N + 1 : IF N < 100 THEN GOTO 340
400 DIM BIG(5000)
410 BIG(0) = 1 : BIG(4999) = 2 : BIG(5000) = 3
420 IF BIG(0) + BIG(4999) + BIG(5000) <> 6 OR BIG(2500) <> 0 THEN PRINT "large array failed"
430 ERASE A, D#, S$, M, T, A$, X, Y$, BIG
440 DIM A(1) : A(1) = 3
450 IF A(1) <> 3 THEN PRINT "re-DIM failed"
460 ERASE A : B$ = "" : A$ = ""
470 OPTION BASE 1 : DIM Z(3) : Z(1) = 1 : Z(3) = 3
480 IF Z(1) + Z(3) <> 4 THEN PRINT "OPTION BASE failed"
490 ERASE Z : OPTION BASE 0
500 F1 = FRE(0)
510 IF F1 <> F0 THEN PRINT "leak check failed:"; F0 - F1
520 PRINT "ARRAYS done"
