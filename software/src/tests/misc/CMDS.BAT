@ECHO OFF
REM CMDS.BAT: BASIC-DOS command tests (prints "failed" on error)
FAILS = 0
X = 1 ' X = 2
IF X <> 1 THEN PRINT "remark failed" : FAILS = FAILS + 1
IF &H1F<>31 THEN PRINT "hex constant failed" : FAILS = FAILS + 1
A$ = "it's" : IF LEN(A$) <> 4 THEN PRINT "quote failed" : FAILS = FAILS + 1
SOUND 440,1
DIR \BIN\TR.COM > T.TMP
TYPE T.TMP | TR a-z A-Z
DIR \BIN\TR.COM | TR a-z A-Z
DIR \BIN\TR.COM | MORE
DEL T.TMP
PRINT "hello,  world" :> T.TMP
TYPE T.TMP | TR a-z A-Z > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "HELLO,  WORLD" THEN PRINT "TR translate failed" : FAILS = FAILS + 1
TYPE T.TMP | TR a-z X > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "XXXXX,  XXXXX" THEN PRINT "TR short set2 failed" : FAILS = FAILS + 1
TYPE T.TMP | TR /D lo > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "he,  wrd" THEN PRINT "TR delete failed" : FAILS = FAILS + 1
TYPE T.TMP | TR /S " " > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "hello, world" THEN PRINT "TR squeeze failed" : FAILS = FAILS + 1
TYPE T.TMP | TR /C /D a-z\r\n > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "helloworld" THEN PRINT "TR complement failed" : FAILS = FAILS + 1
TR a-z A-Z < T.TMP > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "HELLO,  WORLD" THEN PRINT "input redirection failed" : FAILS = FAILS + 1
TR a-z A-Z < T.TMP | TR /D L > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "HEO,  WORD" THEN PRINT "input pipe failed" : FAILS = FAILS + 1
TR a-z A-Z < T.TMP EXTRA > T2.TMP
IF ERRORLEVEL = 0 THEN PRINT "input argument failed" : FAILS = FAILS + 1
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "HEO,  WORD" THEN PRINT "input syntax output failed" : FAILS = FAILS + 1
TR a-z A-Z < NOFILE.TMP
IF ERRORLEVEL = 0 THEN PRINT "missing input failed" : FAILS = FAILS + 1
DEL T?.TMP
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
