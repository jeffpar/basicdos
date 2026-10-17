BASIC-DOS Build Tools
=====================

The tools in this directory build BASIC-DOS from its source code (see SRC:
type CD \SRC and then MK), and they can build other software on BASIC-DOS,
too.  None of them are part of BASIC-DOS: they came from the three Microsoft
products described below, and none of them has been modified.

Microsoft Macro Assembler Package, Version 4.00 (October 16, 1985)
------------------------------------------------------------------

All of the package's files are here, except MAKE.EXE, which has been
replaced (see the next section):

    COUNT    ASM      5965  10-16-85   sample program (counts words in a file)
    CREF     EXE     15028  10-16-85   Cross-Reference Utility 4.00
    EXEMOD   EXE     11034  10-16-85   EXE File Header Utility 4.00
    EXEPACK  EXE     10848  10-16-85   EXE File Compression Utility 4.00
    LIB      EXE     28716  10-16-85   Library Manager 3.02
    LINK     EXE     43988  10-16-85   Linker 3.05 (September 29, 1985)
    MAKE     EXE     24300  10-16-85   Program Maintenance Utility 4.00
    MAPSYM   EXE     18026  10-16-85   Symbol File Generator 4.00
    MASM     EXE     85566  10-16-85   Macro Assembler 4.00
    README   DOC      7630  10-16-85   Microsoft's release notes
    SYMDEB   EXE     37021  10-16-85   Symbolic Debug Utility 4.00

Microsoft C Compiler, Version 4.00 (June 27, 1986)
--------------------------------------------------

One file was taken from this product:

    MAKE     EXE     23418  06-27-86   Program Maintenance Utility 4.02

It replaces the MASM package's MAKE 4.00, which runs every command through
COMMAND /C; MAKE 4.02 runs programs directly, which is faster and needs less
memory.

Microsoft MS-DOS, Version 3.20 (July 7, 1986)
---------------------------------------------

One file was taken from this product:

    EXE2BIN  EXE      3050  07-07-86   EXE to binary (.COM) file converter

EXE2BIN was never part of the MASM package; it came with DOS.  Unlike the
EXE2BINs of DOS 1.x, 2.x, and 3.0x, whose 128-byte stacks are too small for
BASIC-DOS (which runs INT 21h functions on the caller's stack), this one has
a 362-byte stack.  It also insists on running on DOS 3.20 exactly (it follows
its DOS version call with "XCHG AH,AL" and "CMP AX,0314h"), so BASIC-DOS
recognizes that code and reports the version it's looking for; see
DOS_MSC_GETVER in the BASIC-DOS technical reference.  The file is unmodified.

The other tools have small stacks, too (MAPSYM's SP is 80h and LINK's is
100h), but BASIC-DOS has built itself with them without trouble.
