REM BASIC-DOS Test #2
REM Print random numbers
ECHO OFF
LET A = 0
20 PRINT "RND% ="; RND%
LET A = A + 1
IF A < 10 THEN GOTO 20
