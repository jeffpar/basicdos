IF "%1"=="NODEBUG" MAKE REL=NODEBUG MAKEFILE
IF NOT "%1"=="NODEBUG" MAKE REL=DEBUG MAKEFILE
IF ERRORLEVEL 1 GOTO EXIT
WBOOT BOOT.COM A:BOOT2.COM
IF "%2"=="" GOTO EXIT
CD ..\DEV
MK %1 %2
:EXIT
