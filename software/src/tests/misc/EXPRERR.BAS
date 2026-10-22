10 REM EXPRERR.BAS: expression error tests (prints "failed" on error)
20 REM Each invalid expression is written to ET.BAS, after a line that creates
30 REM ET.TMP and ENDs (so that bad code never runs), and ET.BAS is run; it
40 REM should report a syntax error and set ERRORLEVEL, without creating ET.TMP.
50 Q$ = CHR$(34) : FAILS = 0
60 E$ = "-" + Q$ + "a" + Q$ : GOSUB 1000
70 E$ = Q$ + "a" + Q$ + "*" + Q$ + "b" + Q$ : GOSUB 1000
80 E$ = "MID$(" + Q$ + "hello" + Q$ + ",2," + Q$ + "x" + Q$ + "-1)" : GOSUB 1000
90 E$ = "MID$(" + Q$ + "hello" + Q$ + ",2,1+)" : GOSUB 1000
100 DEL ET.BAS
110 IF MID$("hello",2,) + "!" <> "ello!" THEN PRINT "empty parameter failed" : FAILS = FAILS + 1
120 IF FAILS THEN PRINT "EXPRERR failed" ELSE PRINT "EXPRERR passed"
130 END
1000 OPEN "ET.BAS" FOR OUTPUT AS #1
1010 PRINT #1, "OPEN " + Q$ + "ET.TMP" + Q$ + " FOR OUTPUT AS #1 : CLOSE #1 : END"
1020 PRINT #1, "PRINT " + E$
1030 CLOSE #1
1040 ET
1045 IF ERRORLEVEL = 0 THEN PRINT E$; " ERRORLEVEL failed" : FAILS = FAILS + 1
1050 IF EXISTS("ET.TMP") THEN PRINT E$; " failed" : FAILS = FAILS + 1 : DEL ET.TMP
1060 RETURN
