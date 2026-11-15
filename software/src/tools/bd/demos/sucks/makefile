#
# Builds SUCKS1.EXE and SUCKS2.EXE, two programs that play Ataxx (see
# README.TXT), which run in protected mode and real mode.  SUCKS2 uses bit
# boards.
#
# Run "MAKE MAKEFILE" in this folder (TOOLS\DEMOS\SUCKS on a BASIC-DOS hard
# disk), with TOOLS\BIN in PATH$; see ..\hello\makefile for what the steps do.
# This makefile uses Microsoft C 4.00; "MAKE BDC" builds the same programs
# (as SUCKS1B.EXE and SUCKS2B.EXE) with BDC, the BASIC-DOS C compiler, which
# is several times faster.
#
# The C files are the originals, changed only as much as C 4.00 requires:
# function definitions declare their parameters in the old style, and comments
# use /* */ instead of // (SUCKS1.C also defines max, which C 4.00's STDLIB.H
# does not).
#
sucks1.obj: sucks1.c
	cl /c /FPa /I..\..\include sucks1.c

sucks1.exe: sucks1.obj sucks1.def
	link4 sucks1,sucks1.ne,nul,..\..\lib\,sucks1.def
	stub sucks1.ne sucks1.exe

sucks2.obj: sucks2.c
	cl /c /FPa /I..\..\include sucks2.c

sucks2.exe: sucks2.obj sucks2.def
	link4 sucks2,sucks2.ne,nul,..\..\lib\,sucks2.def
	stub sucks2.ne sucks2.exe
