#
# BASIC-DOS SDK Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright (c) 2026 Jeff Parsons
# @license MIT <https://basicdos.com/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
# Run "MAKE MAKEFILE" in this directory (SRC\SDK on a BASIC-DOS hard disk),
# with TOOLS\BIN in PATH$, in protected mode.  The BASIC-DOS build doesn't
# build these programs: they're here to be built on BASIC-DOS.
#
# MEM32.EXE is a 32-bit LE program (see MEM32.DEF).  MASM5 (MASM 5.10B)
# assembles 80386 code, which MASM 4.00 can't, and LINK386 links it; LINK386
# warns that there's no automatic data segment, which a flat program doesn't
# need.  LINK386 is an OS/2 program, which BASIC-DOS runs only in protected
# mode (with the libraries in EXT\DLL).
#
# FIND16.EXE is a 16-bit OS/2 1.x program (see FIND16.DEF), which also runs
# on OS/2: MASM5 assembles it twice, first with STUB defined, which LINK
# builds as the real-mode program (FIND16.STB) that LINK4 puts at the start
# of the NE file it builds from the second.
#
# The system's include files are in ..\INC, so its macros are available (eg,
# DBGBRK and ASSERT, which assemble code only with "MAKE REL=DEBUG MAKEFILE").
#
REL=FINAL

MEM32.EXE: MEM32.ASM MEM32.DEF
	MASM5 /D$(REL) /I..\INC $*.ASM,$*.OBJ,NUL;
	LINK386 $*.OBJ,$@,NUL,,$*.DEF;
	DEL $*.OBJ

FIND16.EXE: FIND16.ASM FIND16.DEF
	MASM5 /D$(REL) /DSTUB /I..\INC $*.ASM,$*.OBJ,NUL;
	LINK $*.OBJ,$*.STB;
	MASM5 /D$(REL) /I..\INC $*.ASM,$*.OBJ,NUL;
	LINK4 $*.OBJ,$@/ALIGN:16,NUL,,$*.DEF;
	DEL $*.OBJ
	DEL $*.STB
