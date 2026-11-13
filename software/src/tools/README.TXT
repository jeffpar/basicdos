BASIC-DOS Build Tools
=====================

This is a collection of DOS-compatible tools used to build BASIC-DOS as well
as programs that run on BASIC-DOS.

Originally, these tools were run on MS-DOS (ie, MS-DOS 3.20) to build all
the BASIC-DOS binaries, but once BASIC-DOS was able to run the same tools, the
BASIC-DOS build process is now run entirely on BASIC-DOS.  You can do the
same on a BASIC-DOS hard disk with the BASIC-DOS sources in C:\SRC; just run
the MK.BAT file in that directory.

Over time, this collection has expanded to include some tools some needed to
build protected-mode binaries, first in assembly (using Microsoft MASM 4.00)
and later in C (using Microsoft C 4.00).

Microsoft Macro Assembler Package, Version 4.00 (October 16, 1985)
------------------------------------------------------------------

All of the package's files are here, except its MAKE.EXE (MAKE 4.00, 24300
bytes, 10-16-85), which has been replaced (see the next section):

    COUNT    ASM      5965  10-16-85   sample program (counts words in a file)
    CREF     EXE     15028  10-16-85   Cross-Reference Utility 4.00
    EXEMOD   EXE     11034  10-16-85   EXE File Header Utility 4.00
    EXEPACK  EXE     10848  10-16-85   EXE File Compression Utility 4.00
    LIB      EXE     28716  10-16-85   Library Manager 3.02
    LINK     EXE     43988  10-16-85   Linker 3.05 (September 29, 1985)
    MAPSYM   EXE     18026  10-16-85   Symbol File Generator 4.00
    MASM     EXE     85566  10-16-85   Macro Assembler 4.00
    README   DOC      7630  10-16-85   Microsoft's release notes
    SYMDEB   EXE     37021  10-16-85   Symbolic Debug Utility 4.00

Building BASIC-DOS requires only EXEMOD, LINK, MAPSYM, and MASM.  The other
files complete the package, for use with other software: CREF, EXEPACK, and
LIB are additional development tools, SYMDEB is a debugger (which the BASIC-DOS
Tests diskette has, too), COUNT.ASM is a sample, and README.DOC has Microsoft's
notes about the release.

Microsoft C Compiler, Version 4.00 (June 27, 1986)
--------------------------------------------------

These files were taken from this product:

    MAKE     EXE     23418  06-27-86   Program Maintenance Utility 4.02
    LINK4    EXE     60006  07-18-86   Segmented-Executable Linker 5.00.12
    CL       EXE     27381  06-27-86   C Compiler 4.00 (the driver)
    C1       EXE    130757  06-27-86   its first pass (preprocessor, parser)
    C2       EXE    116991  06-27-86   its second pass (code generator)
    C3       EXE     83481  06-27-86   its third pass (optimizer, object file)
    DOSSEG   EXE      4088  06-27-86   adds a DOSSEG record to an object file
    INCLUDE  <DIR>                     its include files (27, and 5 in SYS)
    LIB      <DIR>                     its libraries (9 of its 15)

MAKE 4.02 replaces the MASM package's MAKE 4.00, which runs every command
through COMMAND /C; MAKE 4.02 runs programs directly, which is faster and
needs less memory.

LINK4 comes from the product's eighth diskette ("C WINDOWS"), which updated
the Windows Software Development Kit 1.01 for C 4.00.  It links "new
executable" (NE) programs, which list each segment's type (code or data),
size, and relocations, as a protected-mode loader needs.  It builds
TESTS\BIN\PRIMES.EXE (see TESTS\PRIMES\PRIMES.DEF), with the MS-DOS program
that LINK builds as its stub, so the file runs in real mode, too.

CL, C1, C2, and C3 are the C compiler: CL runs the three passes, and then
LINK (unless /c is specified).  They're unmodified, and they compile and link
real-mode programs on BASIC-DOS as they do on MS-DOS, with one exception: CL
and C1 build the path of an include file with "/", which BASIC-DOS doesn't
accept in a path, so the /I switch doesn't find files in other directories,
and include files must be in the current directory (the BASIC-DOS versions
described below don't have this limitation).  BASIC-DOS has no INCLUDE, LIB,
or TMP environment variables, so use /I for the include files, keep the
libraries in the current directory (or give LINK their path), and expect
temporary files in the current directory.

INCLUDE has the compiler's include files, and LIB has its libraries for the
small, medium, compact, and large memory models (S, M, C, and L): the C
libraries (SLIBC.LIB, etc), the alternate math libraries (SLIBFA.LIB, etc),
and the helper library (LIBH.LIB), which every program needs.  The
floating-point libraries (SLIBFP.LIB, etc), the 8087 emulator (EM.LIB), and
the 8087 library (87.LIB) aren't included: their floating point is the
emulator's INT 34h through 3Dh instructions, which don't work in protected
mode.  So always compile with /FPa, even a program with no floating point,
since an object file compiled without it asks the linker for EM.LIB.

DOSSEG comes from the compiler's startup sources (its STARTUP folder).  It
adds the record to an object file that makes the linker use Microsoft's
segment order, and define _edata and _end, which MASM 4.00 can't do; it was
used to build the BASIC-DOS versions of the libraries.

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

Microsoft Windows 3.1 Device Development Kit (March 1992)
--------------------------------------------------------

Two files were taken from the DDK's 386\TOOLS folder, which has the tools for
building Windows 386 enhanced mode virtual devices (VxDs):

    LINK386  EXE    123008  01-05-92   Linear-Executable Linker 1.00.058
    MASM5    EXE    111396  01-05-92   Macro Assembler 5.10B

They're for 80386 code: MASM5 assembles .386P sources with 32-bit (USE32)
segments, and LINK386 links them into a "linear executable" (LE) file, of
4K pages and 32-bit fixups, as a paging loader needs.  A definitions file
selects the kind of LE file: EXETYPE OS2 (with NAME) makes a program, and
EXETYPE DEV386 (with LIBRARY) makes a VxD.  LINK386 is an OS/2 1.x program
whose DOS stub runs it on DOS, too (it has been tried on MS-DOS 3.20), and
the default stub of the programs it links says that they can't run on DOS.

BASIC-DOS Versions
------------------

Everything above describes the original files.  On a BASIC-DOS hard disk,
MASM, MASM5, MAKE, LINK, LINK4, EXEMOD, MAPSYM, EXE2BIN, and the C compiler
(CL, C1, C2, and C3) in TOOLS\BIN are BASIC-DOS versions that run in protected
mode, too; their banners end in "BD" (eg, "Version 4.00BD").  The C and
alternate math libraries in TOOLS\LIB are BASIC-DOS versions as well.  For
the details, and for how to build C programs, see README.md in the
software/src/tools folder of the BASIC-DOS repository
(https://github.com/jeffpar/basicdos), and the sample in TOOLS\HELLO.
