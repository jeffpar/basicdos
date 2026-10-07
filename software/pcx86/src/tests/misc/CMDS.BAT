@ECHO OFF
REM CMDS.BAT: BASIC-DOS command tests (prints "failed" on error)
X = 1 ' X = 2
IF X <> 1 THEN PRINT "remark failed"
IF &H1F<>31 THEN PRINT "hex constant failed"
A$ = "it's" : IF LEN(A$) <> 4 THEN PRINT "quote failed"
SOUND 440,1
DIR CASE.COM > T.TMP
TYPE T.TMP | CASE
DIR CASE.COM | CASE
DEL T.TMP
TIME -D
HELP SQR
PRINT "CMDS done"
