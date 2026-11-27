#
# Builds BIN\SUCKS1.EXE and BIN\SUCKS2.EXE, two programs that play Ataxx (see
# README.TXT), which run in protected mode and real mode.  SUCKS2 uses bit
# boards.
#
# Run "MAKE MAKEFILE" in this folder (TOOLS\DEMOS\SUCKS on a BASIC-DOS hard
# disk), with TOOLS\BIN in PATH$; see ..\hello\makefile for what the steps do.
# This makefile uses Microsoft C 4.00; "MAKE MAKEBDC" builds the same
# programs in BDC with BDC, the BASIC-DOS C compiler, which is several times
# faster, and "MAKE MAKE386" builds 32-bit versions in 386 with the Microsoft
# 386 C Compiler.
#
# The C files are the originals, changed only as much as C 4.00 requires:
# function definitions declare their parameters in the old style, and comments
# use /* */ instead of // (SUCKS1.C also defines max, which C 4.00's STDLIB.H
# does not).
#
bin\sucks1.obj: sucks1.c
	cl /c /FPa /I..\..\include /Fobin\sucks1.obj sucks1.c

bin\sucks1.exe: bin\sucks1.obj bin\sucks1.def
	link4 bin\sucks1,bin\sucks1.ne,nul,..\..\lib\,bin\sucks1.def
	stub bin\sucks1.ne bin\sucks1.exe

bin\sucks2.obj: sucks2.c
	cl /c /FPa /I..\..\include /Fobin\sucks2.obj sucks2.c

bin\sucks2.exe: bin\sucks2.obj bin\sucks2.def
	link4 bin\sucks2,bin\sucks2.ne,nul,..\..\lib\,bin\sucks2.def
	stub bin\sucks2.ne bin\sucks2.exe
