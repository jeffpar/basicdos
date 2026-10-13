10 REM VARS.BAS: LIST VARS must not change values or array bounds
15 K$ = PATH$
20 I% = -2147483647 : I# = 1.25 : S$ = "hello" : E$ = ""
30 DIM A%(2,3), B$(4), C#(1)
40 A%(2,3) = 42 : B$(4) = "last" : C#(1) = 2.5
50 DEF FNT%(P%) = P% + 1
60 IF FNT%(3) <> 4 THEN PRINT "function failed"
70 OPTION BASE 1 : DIM Q%(3) : Q%(3) = 9
80 ERASE C#
90 LIST VARS
100 LIST 20-30
110 IF I% <> -2147483647 OR I# <> 1.25 THEN PRINT "LIST numeric failed"
120 IF S$ <> "hello" OR E$ <> "" THEN PRINT "LIST string failed"
130 IF A%(2,3) <> 42 OR B$(4) <> "last" THEN PRINT "LIST array failed"
140 IF Q%(3) <> 9 OR FNT%(3) <> 4 THEN PRINT "LIST bounds/function failed"
150 LIST VARS :> VARS.TMP
160 OPEN "VARS.TMP" FOR INPUT AS #1
170 LINE INPUT #1, L$
175 IF L$ <> "PATH$ = " + CHR$(34) + K$ + CHR$(34) THEN PRINT "LIST PATH failed"
177 LINE INPUT #1, L$ : CLOSE #1
180 IF L$ <> "K$ = " + CHR$(34) + K$ + CHR$(34) THEN PRINT "LIST redirection failed"
185 IF PATH$ <> K$ THEN PRINT "LIST preserved value failed"
190 DEL VARS.TMP
200 PRINT "VARS done"
