REM The first BASIC-DOS test file:
REM Printing Fibonacci numbers
COLOR 7,1
LET A = 0:LET B = 1
10 PRINT A;
LET C = A + B:LET A = B:LET B = C
GOTO 10
