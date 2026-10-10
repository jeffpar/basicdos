@ECHO OFF
REM CMDS.BAT: BASIC-DOS command tests (prints "failed" on error)
X = 1 ' X = 2
IF X <> 1 THEN PRINT "remark failed"
IF &H1F<>31 THEN PRINT "hex constant failed"
A$ = "it's" : IF LEN(A$) <> 4 THEN PRINT "quote failed"
SOUND 440,1
DIR /TOOLS/CASE.COM > T.TMP
TYPE T.TMP | CASE
DIR /TOOLS/CASE.COM | CASE
DIR /TOOLS/CASE.COM | MORE
DEL T.TMP
PRINT 1 :> T1.TMP
PRINT 2 :> T2.TMP
DEL T?.TMP
P$ = "paths":/TOOLS/SLEEP.COM 0
IF ERRORLEVEL <> 0 THEN PRINT "absolute command failed"
/TOOLS/SLEEP.COM 0
IF ERRORLEVEL <> 0 THEN PRINT "leading path command failed"
TOOLS/SLEEP.COM 0
IF ERRORLEVEL <> 0 THEN PRINT "relative command failed"
A:/TOOLS/SLEEP.COM 0
IF ERRORLEVEL <> 0 THEN PRINT "drive path command failed"
SLEEP 0
IF ERRORLEVEL <> 0 THEN PRINT "bare command failed"
TIME -D
HELP SQR
PRINT "CMDS done"
