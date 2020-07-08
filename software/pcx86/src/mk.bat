CD BOOT
REM Use MK NODEBUG to create a non-debug release
IF "%1"=="" MK DEBUG ALL
IF NOT "%1"=="" MK %1 ALL

