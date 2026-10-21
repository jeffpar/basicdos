REM BASIC-DOS Test #3
REM Pipe test loop
DEFINT A-Z
10 DIR | TR a-z A-Z
GOTO 10
