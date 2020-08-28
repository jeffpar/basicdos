REM BASIC-DOS Test #1
REM Print Fibonacci numbers
COLOR 7,1
LET A = 0:LET B = 1
10 PRINT A;
LET C = A + B
LET A = B:LET B = C
IF A < 100 THEN GOTO 10
