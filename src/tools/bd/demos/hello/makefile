#
# Builds BIN\HELLO.EXE, a C program that runs in protected mode and real mode.
#
# Run "MAKE MAKEFILE" in this folder, with TOOLS\BIN in PATH$.  The steps are:
#
#   1. CL compiles HELLO.C (/c means compile only, since CL would run LINK)
#      to BIN\HELLO.OBJ (/Fo names the object file).  BASIC-DOS has no
#      INCLUDE variable, so /I names the include folder.  /FPa selects the
#      alternate math library, the only floating point that works in
#      protected mode; use it even if a program has none, since it also
#      determines which libraries the object file asks for.  For another
#      memory model, add /AM, /AC, or /AL (LINK4 then uses that model's
#      libraries).
#
#   2. LINK4 links BIN\HELLO.OBJ with the libraries in ..\..\LIB (the
#      trailing "\" makes it a folder to search), making an NE program, as
#      BIN\HELLO.DEF asks.  That file must have PROTMODE, CODE FIXED, DATA
#      FIXED, STACKSIZE (2048 or more), and HEAPSIZE statements.  The NE file
#      runs in protected mode.
#
#   3. STUB copies BIN\HELLO.NE to BIN\HELLO.EXE with the NE loader stub,
#      which makes it run in real mode, too.
#
# MAKEBDC and MAKE386 build the same program in the BDC and 386 folders, so
# each makefile's files are kept apart from the others'.
#
bin\hello.obj: hello.c
	cl /c /FPa /I..\..\include /Fobin\hello.obj hello.c

bin\hello.exe: bin\hello.obj bin\hello.def
	link4 bin\hello,bin\hello.ne,nul,..\..\lib\,bin\hello.def
	stub bin\hello.ne bin\hello.exe
