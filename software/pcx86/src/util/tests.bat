REM The first BASIC-DOS test file
COLOR 7,1
PRINT 2+2
PRINT 1;2;3;4;5;6;7;8;9
LET a = 99
PRINT (-a)^2/3+&hff*(3+4)
REM Result should be 5052
PRINT -(-a)^2/3+&hff*(3+44)
REM Result should be 8718
REM
REM String support is coming soon
REM Until then, avoid using strings
