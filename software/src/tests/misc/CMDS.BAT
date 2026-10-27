@ECHO OFF
REM CMDS.BAT: BASIC-DOS command tests (prints "failed" on error)
FAILS = 0
X = 1 ' X = 2
IF X <> 1 THEN PRINT "remark failed" : FAILS = FAILS + 1
IF &H1F<>31 THEN PRINT "hex constant failed" : FAILS = FAILS + 1
A$ = "it's" : IF LEN(A$) <> 4 THEN PRINT "quote failed" : FAILS = FAILS + 1
SOUND 440,1
DIR \EXT\TR.COM > T.TMP
TYPE T.TMP | TR a-z A-Z
DIR \EXT\TR.COM | TR a-z A-Z
DIR \EXT\TR.COM | MORE
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
SED "s/\(l*\)o/[\1]/g" T.TMP > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "he[ll],  w[]rld" THEN PRINT "SED groups failed" : FAILS = FAILS + 1
TYPE T.TMP | SED p | SED /N "$=;/^h/s/  */ /gp" > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : LINE INPUT #1, M$ : CLOSE #1
IF L$ + M$ <> "hello, world2" THEN PRINT "SED addresses failed" : FAILS = FAILS + 1
TYPE T.TMP | SED p | UNIQ /C > T2.TMP
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "      2 hello,  world" THEN PRINT "UNIQ failed" : FAILS = FAILS + 1
FIND /R /I "^H[a-z]*,  *W.*D$" T.TMP > T2.TMP
IF ERRORLEVEL THEN PRINT "FIND /R failed" : FAILS = FAILS + 1
SED "s/[a/b/" T.TMP
IF ERRORLEVEL = 0 THEN PRINT "SED error failed" : FAILS = FAILS + 1
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
F$ = "T1.TMP"
TR a-z A-Z < F$ > "T2.TMP"
OPEN "T2.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF VAL(L$) <> 1 THEN PRINT "redirection string failed" : FAILS = FAILS + 1
DEL "T1.TMP" + F$
IF ERRORLEVEL = 0 THEN PRINT "DEL expression failed" : FAILS = FAILS + 1
DEL T?.TMP
DIR /W \EXT\T*.COM > T.TMP
OPEN "T.TMP" FOR INPUT AS #1
FOR I = 1 TO 5 : LINE INPUT #1, L$ : NEXT : CLOSE #1
IF LEFT$(L$, 22) <> "TEE.COM         TR.COM" THEN PRINT "DIR /W failed" : FAILS = FAILS + 1
DIR /W \TOOLS > T.TMP
OPEN "T.TMP" FOR INPUT AS #1
FOR I = 1 TO 5 : LINE INPUT #1, L$ : NEXT : CLOSE #1
IF LEFT$(L$, 19) <> ".\              ..\" THEN PRINT "DIR /W dir failed" : FAILS = FAILS + 1
LS /r \T*.* > T.TMP
OPEN "T.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "\TOOLS\" THEN PRINT "LS failed" : FAILS = FAILS + 1
REM A BAS file writing more than a pipe holds must not wait for the reader
LS \EXT | SORT /R > T.TMP
OPEN "T.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF L$ <> "WC.COM" THEN PRINT "BAS pipe failed" : FAILS = FAILS + 1
OPEN "T1.TMP" FOR OUTPUT AS #1 : PRINT #1, "0123456789"; : CLOSE #1
HEXDUMP T1.TMP /S 2 /N 3 > T.TMP
OPEN "T.TMP" FOR INPUT AS #1 : LINE INPUT #1, L$ : CLOSE #1
IF LEFT$(L$, 24) <> "0000:0000       32 33 34" OR MID$(L$, 60, 5) <> "  234" THEN PRINT "HEXDUMP failed" : FAILS = FAILS + 1
DEL T1.TMP
TYPE NOFILE.TMP | SORT
IF ERRORLEVEL = 0 THEN PRINT "deferred error failed" : FAILS = FAILS + 1
REM A BAT or BAS file can't be the target of a pipe
VER | LS
IF ERRORLEVEL = 0 THEN PRINT "BAS pipe target failed" : FAILS = FAILS + 1
DEL T.TMP
P$ = "paths":\EXT\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "absolute command failed" : FAILS = FAILS + 1
\EXT\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "leading path command failed" : FAILS = FAILS + 1
EXT\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "relative command failed" : FAILS = FAILS + 1
REM Drive prefix immediately after a statement separator (dual-session startup)
P$ = "drive":A: :\EXT\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "compound drive command failed" : FAILS = FAILS + 1
A:\EXT\SLEEP.COM 0
IF ERRORLEVEL THEN PRINT "drive path command failed" : FAILS = FAILS + 1
SLEEP 0
IF ERRORLEVEL THEN PRINT "bare command failed" : FAILS = FAILS + 1
TIME /D
HELP SQR
IF FAILS THEN PRINT "CMDS failed" ELSE PRINT "CMDS passed"
