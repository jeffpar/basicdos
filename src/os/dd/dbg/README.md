## BASIC-DOS Debugger

This directory contains the sources for `DEBUG.COM`, which runs both as an installable device driver (a `DEVICE=` line in CONFIG.SYS), where it's a debugger for the whole system with its monitor on a serial port, and as a program (`DEBUG [program [arguments]]`), with its monitor on the console.  `dbgdev.asm` is the driver itself, `dbgcmd.asm` reads and runs commands, `dbgdis.asm` is the disassembler and assembler, `dbgvec.asm` traps interrupt vectors, and `dbginit.asm` initializes the driver and handles program mode.
