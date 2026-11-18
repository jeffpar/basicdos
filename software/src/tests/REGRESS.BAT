@ECHO OFF
REM REGRESS.BAT: runs the regression tests in \TESTS\REGRESS (run it
REM from \TESTS).  Each test prints "failed" (or "passed") messages, and
REM the tests that return an exit code are checked here.  The programs in
REM \TESTS\MISC aren't run, since each needs something more (eg, a CGA,
REM V86.COM, or a debugger), faults or fails on purpose, measures instead
REM of checking (MICRO.BAS), or just runs (eg, PIPES.BAT).
IF NOT EXISTS("REGRESS\DOSTESTS.COM") THEN PRINT "Run REGRESS from \TESTS" : END
D$ = LEFT$(CURDIR$, 1)
CD REGRESS
FPUTESTS
IF ERRORLEVEL THEN PRINT "FPUTESTS failed"
DOSTESTS
IF ERRORLEVEL THEN PRINT "DOSTESTS failed"
BUFTESTS
IF ERRORLEVEL THEN PRINT "BUFTESTS failed"
REM CPUTESTS is skipped at ring 3, and R3TESTS everywhere else
CPUTESTS
IF ERRORLEVEL THEN PRINT "CPUTESTS failed"
R3TESTS
IF ERRORLEVEL THEN PRINT "R3TESTS failed"
STRFUN
STRPOOL
ARRAYS
FLOW
EXPRERR
VARS
FILEIO
PRTUSING
RUNFILE
ATTRS
REM CMDS and MOVES expect to run in the root of the boot drive (CMDS also
REM runs A:\EXT\SLEEP.COM), so CMDS is skipped unless this is drive A:
IF D$ <> "A" THEN PRINT "CMDS skipped (run it from A:\)" : GOTO 10
CD \
\TESTS\REGRESS\CMDS
10	CD \
\TESTS\REGRESS\MOVES
CD \TESTS\REGRESS
FCBTESTS
IF ERRORLEVEL THEN PRINT "FCBTESTS failed"
REM HARDERR needs an empty drive B:, and its last test aborts it (exit 255)
REM (it exits with 0 instead if other sessions are running, since its disk
REM hook would affect them)
IF D$ = "B" THEN PRINT "HARDERR skipped (drive B: must be empty)" : GOTO 20
HARDERR
IF ERRORLEVEL AND ERRORLEVEL <> 255 THEN PRINT "HARDERR abort failed"
20	IOERR.COM
IF ERRORLEVEL THEN PRINT "IOERR failed"
PRINTF
IF ERRORLEVEL THEN PRINT "PRINTF failed"
CD \TESTS
PRINT "REGRESS done"
