## BASIC-DOS NE Libraries

This directory contains the NE libraries (`DOSCALLS.DLL`, `KBDCALLS.DLL`, `MSG.DLL`, and `NLS.DLL`), each built from an `.asm` file and a `.DEF` file, that provide OS/2 1.x functions to protected-mode NE programs.  The kernel's NE loader looks for them in the system drive's **EXT\\DLL** directory, or in the one that a `LIBPATH=` line in CONFIG.SYS names.
