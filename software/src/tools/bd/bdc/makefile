#
# Builds BDC.EXE, the BASIC-DOS C compiler, which runs in protected mode and
# real mode.
#
# Run "MAKE MAKEFILE" in this folder (TOOLS\BDC on a BASIC-DOS hard disk),
# with TOOLS\BIN in PATH$; see ..\demos\hello\makefile for what the steps do.
# This builds it with Microsoft C, whose code is smaller and faster than
# BDC's own, but BDC can build it, too: replace "cl /c /FPa /Gs" with "bdc".
#
# BDC is a small model program, and its tables (see BDC.H) take most of its
# 64K of data, so BDC.DEF's stack and heap sizes leave little to spare.
#
bdc.obj: bdc.c bdc.h
	cl /c /FPa /Gs /I..\include bdc.c

pp.obj: pp.c bdc.h
	cl /c /FPa /Gs /I..\include pp.c

decl.obj: decl.c bdc.h
	cl /c /FPa /Gs /I..\include decl.c

expr.obj: expr.c bdc.h
	cl /c /FPa /Gs /I..\include expr.c

gen.obj: gen.c bdc.h
	cl /c /FPa /Gs /I..\include gen.c

obj.obj: obj.c bdc.h
	cl /c /FPa /Gs /I..\include obj.c

bdc.exe: bdc.obj pp.obj decl.obj expr.obj gen.obj obj.obj bdc.def
	link4 bdc+pp+decl+expr+gen+obj,bdc.ne,nul,..\lib\,bdc.def
	stub bdc.ne bdc.exe
