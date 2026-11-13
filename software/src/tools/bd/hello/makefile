#
# Builds HELLO.EXE, a C program that runs in protected mode and real mode.
#
# Run "MAKE MAKEFILE" in this folder, with TOOLS in PATH$.  The steps are:
#
#   1. CL compiles HELLO.C (/c means compile only, since CL would run LINK).
#      BASIC-DOS has no INCLUDE variable, so /I names the include folder.
#      /FPa selects the alternate math library, the only floating point that
#      works in protected mode; use it even if a program has none, since it
#      also determines which libraries the object file asks for.  For another
#      memory model, add /AM, /AC, or /AL (LINK4 then uses that model's
#      libraries).
#
#   2. LINK4 links HELLO.OBJ with the libraries in ..\LIB (the trailing "\"
#      makes it a folder to search), making an NE program, as HELLO.DEF asks.
#      That file must have PROTMODE, CODE FIXED, DATA FIXED, STACKSIZE (2048
#      or more), and HEAPSIZE statements.  HELLO.NE runs in protected mode.
#
#   3. STUB copies HELLO.NE to HELLO.EXE with the BASIC-DOS NE loader stub,
#      which makes it run in real mode, too.
#
hello.obj: hello.c
	cl /c /FPa /I..\include hello.c

hello.exe: hello.obj hello.def
	link4 hello,hello.ne,nul,..\lib\,hello.def
	stub hello.ne hello.exe
