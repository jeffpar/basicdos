MAKE MAKEFILE
IF ERRORLEVEL 1 GOTO EXIT
COPY COMMAND.COM A:
COPY EXEC.COM A:
COPY PRIMES.COM A:
COPY SLEEP.COM A:
IF "%1"=="" GOTO EXIT
CD ..
:EXIT
