REM BASIC-DOS Test #1
REM Print Fibonacci numbers
@ECHO OFF
COLOR 7,1
DEF ADD(A,B)=A+B
LET A = 0:LET B = 1
10 PRINT A;
LET C = ADD(A,B)
LET A = B:LET B = C
IF A < 1000000 THEN GOTO 10
PRINT
@ECHO ON
REM BASIC-DOS Test #2
REM Print random numbers
@ECHO OFF
LET A = 0
20 PRINT "RND% ="; RND%
LET A = A + 1
IF A < 10 THEN GOTO 20
