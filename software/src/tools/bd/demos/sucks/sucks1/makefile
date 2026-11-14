#
# Builds SUCKS1.EXE, a program that plays Ataxx, which runs in
# protected mode and real mode.
#
# Run "MAKE MAKEFILE" in this folder (TOOLS\DEMOS\SUCKS1 on a BASIC-DOS hard
# disk), with TOOLS\BIN in PATH$; see ..\hello\makefile for what the steps do.
#
# SUCKS1.C is the original, changed only as much as C 4.00 requires: function
# definitions declare their parameters in the old style, and comments use
# /* */ instead of // (it also defines max, which C 4.00's STDLIB.H does not).
#
sucks1.obj: sucks1.c
	cl /c /FPa /I..\..\include sucks1.c

sucks1.exe: sucks1.obj sucks1.def
	link4 sucks1,sucks1.ne,nul,..\..\lib\,sucks1.def
	stub sucks1.ne sucks1.exe
