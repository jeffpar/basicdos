IF "%1"=="FINAL" MAKE REL=FINAL MAKEFILE
IF NOT "%1"=="FINAL" MAKE REL=DEBUG MAKEFILE
IF ERRORLEVEL 1 GOTO EXIT
COPY PRIMES.BA* A:
COPY OBJ\*.EXE A:
COPY OBJ\*.COM A:
COPY BD*.BAT A:
IF "%2"=="" GOTO EXIT
CD ..\MSB
MK %1 %2
:EXIT
