CD BOOT
REM Use MK FINAL to create a non-debug release
IF "%1"=="" MK DEBUG ALL
IF "%1"=="debug" MK DEBUG ALL
IF "%1"=="DEBUG" MK DEBUG ALL
IF "%1"=="final" MK FINAL ALL
IF "%1"=="FINAL" MK FINAL ALL
