## BASIC-DOS SDK Samples

This directory contains sample programs that are built on BASIC-DOS itself, in protected mode (it's **SRC\\SDK** on the BASICDOS-20MB disk, and neither `mkdos.sh` nor `mk.sh` builds it); `MK [FINAL or DEBUG] [CLEAN]` there builds them all.  `MEM32.EXE` is a 32-bit LE program, which MASM5 assembles and LINK386 links; `FIND16.EXE` is a 16-bit OS/2 1.x version of `FIND.COM` (without regular expressions) that calls only DOSCALLS functions (with PCALL, from `os2.inc`), so the same file runs on OS/2 and on BASIC-DOS in protected mode.

`FIND32.EXE` is the same program again as a 32-bit LE program written in C (`find32.c`), which CL386 compiles and LINK386 links with `crt32.asm` (startup code and a small library of DOS calls, declared in `crt32.h`), since CL386's own library is for OS/2 2.0.
