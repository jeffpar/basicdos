#
# Builds STUB.EXE, which adds the BASIC-DOS NE loader stub to an NE program.
#
# Run "MAKE MAKEFILE" in this folder (TOOLS\STUB on a BASIC-DOS hard disk),
# with TOOLS\BIN in PATH$; see ..\hello\makefile for what the steps do.  The
# stub's code is NESTUB.ASM, assembled with /DSTUBLIB as a far data segment of
# the program (MASM then reports one open conditional), with the BASIC-DOS
# include files in \SRC\INC.
#
# The last step uses the STUB.EXE in TOOLS\BIN to add the stub to the new one.
#
nestub.obj: nestub.asm
	masm /MX /R /DFINAL /DSTUBLIB /I\SRC\INC nestub.asm,nestub.obj,nul,nul

stub.obj: stub.c
	cl /c /FPa /Gs /I..\include stub.c

stub.exe: stub.obj nestub.obj stub.def
	link4 stub+nestub,stub.ne,nul,..\lib\,stub.def
	..\bin\stub stub.ne stub.exe
