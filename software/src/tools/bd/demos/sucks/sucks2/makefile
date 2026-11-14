#
# Builds SUCKS2.EXE, a program that plays Ataxx using bit boards, which runs in
# protected mode and real mode.
#
# Run "MAKE MAKEFILE" in this folder (TOOLS\DEMOS\SUCKS2 on a BASIC-DOS hard
# disk), with TOOLS\BIN in PATH$; see ..\hello\makefile for what the steps do.
#
# SUCKS2.C is the original, changed only as much as C 4.00 requires: function
# definitions declare their parameters in the old style, and comments use
# /* */ instead of //.
#
sucks2.obj: sucks2.c
	cl /c /FPa /I..\..\include sucks2.c

sucks2.exe: sucks2.obj sucks2.def
	link4 sucks2,sucks2.ne,nul,..\..\lib\,sucks2.def
	stub sucks2.ne sucks2.exe
