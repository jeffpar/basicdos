@echo off

echo.
echo This batch program compiles Ralf Brown's Interrupt List to a WINHELP file
echo in the current directory (defined as OutPath in INT2WHLP.CFG). INT2WHLP
echo will request the InPath directory containing the Interrupt List files.
echo.
echo Up to 10 parameters to this program are passed to INT2WHLP. Thus for example
echo   %0 -2-
echo will compile a helpfile without the expanded index.
echo.
echo 12 MB free disk space are required for the compilation (based on release 40).
echo.
echo HC31 is expected to be found on the DOS path.
echo.
echo Intermediate files are deleted after the compilation.
echo.
pause

echo.
echo The following time estimates are based on Interrupt List release 40 and
echo a 486/33MHz based computer.
echo.
echo Compiling to RTF files (appr. 80 seconds)
echo.
shift
int2whlp %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
if NOT errorlevel 2 goto warnings
echo.
echo Some error occured, quitting.
echo.
goto done

:warnings
if NOT errorlevel 1 goto hc
echo.
echo Warning(s) issued, press Ctrl C and answer Y to quit, or
pause

:hc
echo.
echo Compiling RTF files to a HLP file (appr. 33 minutes - high compression,
echo existing INTWIN.PH file)
echo.
if exist intwin.hlp del intwin.hlp
hc31 intwin
if exist intwin.hlp goto delete
echo.
echo Some error occured, intermediate files are not deleted.
echo.
goto done

:delete
echo.
echo.
echo Deleting intermediate files.
echo.
echo Press Ctrl C to quit, or any other key to delete the files.
pause>NUL
del index.rtf>NUL
del int.rtf>NUL
del subint.rtf>NUL
del table.rtf>NUL
del inttopic.rtf>NUL
del tabtopic.rtf>NUL
del intwin.hpj>NUL

:done
