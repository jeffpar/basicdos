@ECHO OFF
REM CMDS.BAT: BASIC-DOS command tests (prints "failed" on error)
X = 1 ' X = 2
IF X <> 1 THEN PRINT "remark failed"
IF &H1F<>31 THEN PRINT "hex constant failed"
A$ = "it's" : IF LEN(A$) <> 4 THEN PRINT "quote failed"
SOUND 440,1
DIR /BIN/CASE.COM > T.TMP
TYPE T.TMP | CASE
DIR /BIN/CASE.COM | CASE
DIR /BIN/CASE.COM | MORE
DEL T.TMP
PRINT 1 :> T1.TMP
PRINT 2 :> T2.TMP
DEL T?.TMP
P$ = "paths":/BIN/SLEEP.COM 0
IF ERRORLEVEL <> 0 THEN PRINT "absolute command failed"
/BIN/SLEEP.COM 0
IF ERRORLEVEL <> 0 THEN PRINT "leading path command failed"
BIN/SLEEP.COM 0
IF ERRORLEVEL <> 0 THEN PRINT "relative command failed"
REM Drive prefix immediately after a statement separator (dual-session startup)
P$ = "drive":A: :/BIN/SLEEP.COM 0
IF ERRORLEVEL <> 0 THEN PRINT "compound drive command failed"
A:/BIN/SLEEP.COM 0
IF ERRORLEVEL <> 0 THEN PRINT "drive path command failed"
SLEEP 0
IF ERRORLEVEL <> 0 THEN PRINT "bare command failed"
TIME -D
HELP SQR
PRINT "CMDS done"
