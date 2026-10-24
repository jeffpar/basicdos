10 REM RUNFILE.BAS: RUN tests (prints "failed" on error).  RUN file replaces
20 REM the program, and RUN alone restarts it, clearing its variables and
30 REM closing its files, so the test runs itself, counting runs in RT.TMP.
40 IF NOT EXISTS("RT.TMP") THEN GOTO 100
50 OPEN "RT.TMP" FOR INPUT AS #1 : INPUT #1, N : CLOSE #1
60 IF R$ <> "" THEN PRINT "RUN variables failed"
70 IF N = 2 THEN KILL RT.TMP : PRINT "RUNFILE passed" : END
80 OPEN "RT.TMP" FOR OUTPUT AS #1 : PRINT #1, 2
90 R$ = "X" : RUN : GOTO 140
100 RUN "NOFILE"
110 IF ERRORLEVEL = 0 THEN PRINT "RUN missing file failed"
120 OPEN "RT.TMP" FOR OUTPUT AS #1 : PRINT #1, 1
130 R$ = ARG$(0) : RUN R$
140 CLOSE : KILL RT.TMP : PRINT "RUNFILE failed" : END
