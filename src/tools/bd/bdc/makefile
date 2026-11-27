#
# Builds BIN\BDC.EXE, the BASIC-DOS C compiler, which runs in protected mode
# and real mode.
#
# Run "MAKE MAKEFILE" in this folder (TOOLS\BDC on a BASIC-DOS hard disk),
# with TOOLS\BIN in PATH$; see ..\demos\hello\makefile for what the steps do.
# This builds it with Microsoft C, whose code is smaller and faster than
# BDC's own, but BDC can build it, too: replace "cl /c /FPa /Gs" with "bdc".
# "MAKE MAKE386" builds a 32-bit version (in 386) with the Microsoft 386 C
# Compiler.
#
# BDC is a small model program, and its tables (see BDC.H) take most of its
# 64K of data, so BIN\BDC.DEF's stack and heap sizes leave little to spare.
#
bin\bdc.obj: bdc.c bdc.h
	cl /c /FPa /Gs /I..\include /Fobin\bdc.obj bdc.c

bin\pp.obj: pp.c bdc.h
	cl /c /FPa /Gs /I..\include /Fobin\pp.obj pp.c

bin\decl.obj: decl.c bdc.h
	cl /c /FPa /Gs /I..\include /Fobin\decl.obj decl.c

bin\expr.obj: expr.c bdc.h
	cl /c /FPa /Gs /I..\include /Fobin\expr.obj expr.c

bin\gen.obj: gen.c bdc.h
	cl /c /FPa /Gs /I..\include /Fobin\gen.obj gen.c

bin\obj.obj: obj.c bdc.h
	cl /c /FPa /Gs /I..\include /Fobin\obj.obj obj.c

bin\bdc.exe: bin\bdc.obj bin\pp.obj bin\decl.obj bin\expr.obj bin\gen.obj bin\obj.obj bin\bdc.def
	link4 bin\bdc+bin\pp+bin\decl+bin\expr+bin\gen+bin\obj,bin\bdc.ne,nul,..\lib\,bin\bdc.def
	stub bin\bdc.ne bin\bdc.exe
