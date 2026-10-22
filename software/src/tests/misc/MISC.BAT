REM MISC.BAT: runs the BASIC-DOS tests in \TESTS\MISC (run it from \TESTS)
REM Each test prints "failed" (or "passed") messages, and the tests that
REM return an exit code are checked here.  Not run: DBGTEST.COM (it needs
REM DEBUG.SYS and a debugger terminal), ASSERT.COM (it fakes an assertion
REM failure, for a debugger to stop on), and MICRO.BAS (a benchmark).
IF NOT EXISTS("MISC\DOSTESTS.COM") THEN PRINT "Run MISC from \TESTS" : END
D$ = LEFT$(CURDIR$, 1)
CD MISC
FPUTESTS
IF ERRORLEVEL THEN PRINT "FPUTESTS failed"
DOSTESTS
IF ERRORLEVEL THEN PRINT "DOSTESTS failed"
STRFUN
STRPOOL
ARRAYS
FLOW
EXPRERR
VARS
FILEIO
PRTUSING
REM CMDS and MOVES expect to run in the root of the boot drive (CMDS also
REM runs A:\BIN\SLEEP.COM), so CMDS is skipped unless this is drive A:
IF D$ <> "A" THEN PRINT "CMDS skipped (run it from A:\)" : GOTO 10
CD \
\TESTS\MISC\CMDS
10	CD \
\TESTS\MISC\MOVES
CD \TESTS\MISC
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
PRINT "MISC done"
