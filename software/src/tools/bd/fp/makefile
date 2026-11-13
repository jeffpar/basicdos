#
# Builds FPTEST.EXE, a floating-point test that runs in protected mode and
# real mode.
#
# Run "MAKE MAKEFILE" in this folder (TOOLS\FP on a BASIC-DOS hard disk), with
# TOOLS\BIN in PATH$; see ..\hello\makefile for what the steps do.  /FPa makes
# every floating-point operation a call to the alternate math library in
# ..\LIB, whose arithmetic, conversions, and math functions are BDFP.ASM and
# BDMATH.C, which use the FPU$ driver.
#
fptest.obj: fptest.c
	cl /c /FPa /I..\include fptest.c

fptest.exe: fptest.obj fptest.def
	link4 fptest,fptest.ne,nul,..\lib\,fptest.def
	stub fptest.ne fptest.exe
