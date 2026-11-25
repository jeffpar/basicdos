## Microsoft BASIC

This directory contains a buildable copy of Microsoft BASIC ("GW-BASIC"), using the open-source files from [GitHub](https://github.com/microsoft/GW-BASIC) and a reverse-engineered OEM source file courtesy of the [OS/2 Museum](OEM.ASM); it builds `MSBASIC.EXE`, which is in **TOOLS\\BIN** on the BASICDOS-20MB disk, for comparing BASIC-DOS with Microsoft BASIC.  The open-source files lack TIMER, so this copy adds it, as in BASICA and later GW-BASIC versions: the TIMER function (seconds since midnight, to hundredths), TIMER ON, OFF, and STOP, and ON TIMER(*n*) GOSUB (*n* = 1 to 86400 seconds).  [ref](ref/) has an earlier reference build.

NOTE: These files are copyright (c) Microsoft Corporation; see the [MIT License](LICENSE).  They're included for reference and testing purposes only and are *not* part of the BASIC-DOS distribution.
