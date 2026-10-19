@ECHO OFF
REM CMDS.BAT: BASIC-DOS command tests (prints "failed" on error)
FAILS = 0
X = 1 ' X = 2
IF X <> 1 THEN PRINT "remark failed" : FAILS = FAILS + 1
IF &H1F<>31 THEN PRINT "hex constant failed" : FAILS = FAILS + 1
A$ = "it's" : IF LEN(A$) <> 4 THEN PRINT "quote failed" : FAILS = FAILS + 1
SOUND 440,1
DIR \BIN\CASE.COM > T.TMP
TYPE T.TMP | CASE
DIR \BIN\CASE.COM | CASE
DIR \BIN\CASE.COM | MORE
DEL T.TMP
PRINT 1 :> T1.TMP
PRINT 2 :> T2.TMP
DEL T?.TMP
P$ = "paths":\BIN\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "absolute command failed" : FAILS = FAILS + 1
\BIN\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "leading path command failed" : FAILS = FAILS + 1
BIN\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "relative command failed" : FAILS = FAILS + 1
REM Drive prefix immediately after a statement separator (dual-session startup)
P$ = "drive":A: :\BIN\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "compound drive command failed" : FAILS = FAILS + 1
A:\BIN\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "drive path command failed" : FAILS = FAILS + 1
SLEEP 0
IF ERRORLEVEL THEN PRINT "bare command failed" : FAILS = FAILS + 1
TIME /D
HELP SQR
IF FAILS THEN PRINT "CMDS failed" ELSE PRINT "CMDS passed"
