10 REM EXPRERR.BAS: expression error tests (prints "failed" on error)
20 REM Each invalid expression is written to ET.BAS, followed by a line that
30 REM creates ET.TMP (which must never run), and ET.BAS is run; it must report
40 REM error M$ (in ET.OUT) and set ERRORLEVEL, without creating ET.TMP.
50 Q$ = CHR$(34) : FAILS = 0
60 E$ = "-" + Q$ + "a" + Q$ : M$ = "Type mismatch" : GOSUB 1000
70 E$ = Q$ + "a" + Q$ + "*" + Q$ + "b" + Q$ : GOSUB 1000
80 E$ = "MID$(" + Q$ + "hello" + Q$ + ",2," + Q$ + "x" + Q$ + "-1)" : GOSUB 1000
90 E$ = "MID$(" + Q$ + "hello" + Q$ + ",2,1+)" : M$ = "Syntax error" : GOSUB 1000
100 DEL ET.BAS : DEL ET.OUT
110 IF MID$("hello",2,) + "!" <> "ello!" THEN PRINT "empty parameter failed" : FAILS = FAILS + 1
115 TRUE = 5 : FALSE% = 5 : IF TRUE <> -1 OR FALSE THEN PRINT "TRUE/FALSE failed" : FAILS = FAILS + 1
116 GOSUB 3000
120 IF FAILS THEN PRINT "EXPRERR failed" ELSE PRINT "EXPRERR passed"
130 END
1000 OPEN "ET.BAS" FOR OUTPUT AS #1
1010 PRINT #1, "PRINT " + E$
1020 PRINT #1, "OPEN " + Q$ + "ET.TMP" + Q$ + " FOR OUTPUT AS #1 : CLOSE #1"
1030 CLOSE #1
1040 ET > ET.OUT
1045 IF ERRORLEVEL = 0 THEN PRINT E$; " ERRORLEVEL failed" : FAILS = FAILS + 1
1046 L$ = "" : OPEN "ET.OUT" FOR INPUT AS #1 : IF NOT EOF(1) THEN LINE INPUT #1, L$
1047 CLOSE #1 : IF L$ <> M$ + " in line 1" THEN PRINT E$; " message failed: "; L$ : FAILS = FAILS + 1
1050 IF EXISTS("ET.TMP") THEN PRINT E$; " failed" : FAILS = FAILS + 1 : DEL ET.TMP
1060 RETURN
2000 IF ERR <> E THEN PRINT "test"; T; "ERR"; ERR; "failed" : FAILS = FAILS + 1
2010 E = 0 : RESUME 3010
3000 REM Overflow and division by zero (E = the error expected, or 1 for a bad result)
3005 T = 0 : E = 0 : A% = &H7FFFFFFF : N% = &H80000000 : M% = &H20000 : Z% = 0 : Z# = 0
3010 IF E THEN PRINT "test"; T; "failed" : FAILS = FAILS + 1
3020 T = T + 1 : E = 0 : ON ERROR GOTO 2000
3030 ON T GOTO 3100,3101,3102,3103,3105,3106,3108,3109,3111,3112,3113,3114,3115
3040 ON ERROR GOTO 0 : RETURN
3100 E = 6 : B% = A% + 1 : GOTO 3010
3101 E = 6 : B% = -A% - 2 : GOTO 3010
3102 E = 6 : B% = M% * &H4000 : GOTO 3010
3103 B% = (-M%) * &H4000 : IF B% <> N% THEN E = 1
3104 GOTO 3010
3105 E = 6 : B% = N% \ -1 : GOTO 3010
3106 IF N% MOD -1 THEN E = 1 ELSE E = 6 : B% = -N%
3107 GOTO 3010
3108 E = 6 : B% = 2 : B% = B% ^ 31 : GOTO 3010
3109 IF 2 ^ 30 <> &H40000000 OR (-1) ^ -3 <> -1 THEN E = 1 ELSE E = 11 : B% = Z% ^ -1
3110 GOTO 3010
3111 E = 6 : FOR I% = A% - 1 TO A% : NEXT : GOTO 3010
3112 E = 11 : B% = A% \ Z% : GOTO 3010
3113 E = 6 : D# = 1E+308 : D# = D# * 10 : GOTO 3010
3114 E = 11 : D# = 1 / Z# : GOTO 3010
3115 E = 6 : B% = 1E+10 : GOTO 3010
