BASIC-DOS Build Tools
=====================

This is a collection of DOS-compatible tools used to build BASIC-DOS as well
as programs that run on BASIC-DOS.

Originally, these tools were run on MS-DOS (ie, MS-DOS 3.20) to build all
the BASIC-DOS binaries, but once BASIC-DOS was able to run the same tools, the
BASIC-DOS build process is now run entirely on BASIC-DOS.  You can do the
same on a BASIC-DOS hard disk with the BASIC-DOS sources in C:\SRC; just run
the MK.BAT file in that directory.

Either way, building BASIC-DOS (MKDOS.BAT on MS-DOS, MK.BAT on BASIC-DOS) runs
only MAKE, MASM5, LINK, LINK4 (for TESTS\MISC\OBJ\PRIMES.EXE), EXE2BIN, EXEMOD (for
MSBASIC.EXE), and MAPSYM, all from this collection: on BASIC-DOS, MK finds
their BASIC-DOS versions in TOOLS\BD, and on MS-DOS, the build disk's
AUTOEXEC.BAT puts the originals (D:\TOOLS\DOS) first in the PATH.

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

Building BASIC-DOS uses only EXEMOD, LINK, and MAPSYM from this package (and
MASM5, below, in place of MASM).  The other files complete the package, for use
with other software: CREF, EXEPACK, and LIB are additional development tools,
SYMDEB is a debugger (which the BASIC-DOS Tests diskette has, too), COUNT.ASM
is a sample, and README.DOC has Microsoft's notes about the release.

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
TESTS\MISC\OBJ\PRIMES.EXE (see TESTS\MISC\PRIMES.DEF), with the MS-DOS program
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

One file was taken from the DDK's 386\TOOLS folder, which has the tools for
building Windows 386 enhanced mode virtual devices (VxDs):

    MASM5    EXE    111396  01-05-92   Macro Assembler 5.10B

MASM5 assembles 80386 code: .386P sources with 32-bit (USE32) segments, as
32-bit object files for LINK386 (see the next section).  The DDK has a
LINK386 of its own (1.00.058, 123008 bytes, 01-05-92), which BASIC-DOS used
until the OS/2 SDK's replaced it.

The BASIC-DOS makefiles assemble with MASM5 (ASM=MASM5).  Everything still
assembles with MASM 4.00 (run MAKE with ASM=MASM), to the same binaries except
for AND, OR, and XOR with small immediates, which only MASM5 encodes in the
shorter (sign-extended byte) form.  The 80386 instructions in 16-bit code are
still DB bytes, because once a module uses .386, MASM5 writes 32-bit OMF
records, which LINK 3.x and LINK4 reject.

Microsoft OS/2 2.00 Software Development Kit, Pre-Release 2 (June 1, 1990)
--------------------------------------------------------------------------

These files were taken from the kit's first two "SDK LANG" diskettes (their
BIN folders), except for LINK386, which is from the first "SDK TK" diskette
(its OS2BIN folder, where it's the compressed file LINK386.EX@, which the
kit's UNPACK expands):

    LINK386  EXE    133102  05-30-90   Linear-Executable Linker 1.01.015
    CL386    EXE     42705  06-01-90   386 C Compiler 1.00.075 (the driver)
    CL386    ERR      1465  06-01-90   its error messages
    CL386    MSG      2146  06-01-90   its help text (CL386 /HELP)
    C1_386   EXE    155328  06-01-90   its first pass (preprocessor, parser)
    C1_386   ERR     19951  06-01-90   the first pass's error messages
    C2_386   EXE    256985  06-01-90   its second pass (code generator)
    C3_386   EXE    132172  06-01-90   its third pass (optimizer, object file)
    C23_386  ERR      3260  06-01-90   the other passes' error messages

LINK386 links 32-bit object files into a "linear executable" (LE) file, of
4K pages and 32-bit fixups, as a paging loader needs.  A definitions file
selects the kind of LE file: EXETYPE OS2 (with NAME) makes a program, and
NAME's WINDOWCOMPAT says what kind of program, which this LINK386 otherwise
warns about.  It gives each of a program's objects (its code, data, and
stack) an address that's a multiple of 64K, where the DDK's LINK386 used
the next 4K; BASIC-DOS loads a program's objects one after another either
way, so a program needs no more memory for it.

CL386 is Microsoft's first C compiler for the 80386, which was never released
as a product: it compiles C to 32-bit code for a flat address space, as 32-bit
object files that LINK386 links.  LINK386, CL386, and CL386's passes are
16-bit OS/2 1.x programs (CL386 and its passes have DOS stubs that run them
on DOS, too; they have been tried on MS-DOS 3.20), and CL386 passes each pass
its options in an environment string (MSC_CMD_FLAGS), and looks for the
passes in the current directory and then in PATH.

On BASIC-DOS, they run in protected mode as the OS/2 programs that they are
(so their banners have no "BD"): the NE loader starts each with OS/2's
registers, and the OS/2 functions that they import are in the libraries in
EXT\DLL (DOSCALLS.DLL, KBDCALLS.DLL, MSG.DLL, and NLS.DLL; see the BASIC-DOS
technical reference).

The kit's C library (LIBC.LIB, on the third "SDK LANG" diskette) is for OS/2
2.0, so it isn't here: a 32-bit C program for BASIC-DOS is compiled without
it (/Zl) and linked with startup code and functions of its own, which make
DOS calls.  SDK\FIND32.C in the BASIC-DOS sources is an example, with its
library in SDK\CRT32.ASM and CRT32.H:

    CL386 /c /Gs /Zl FIND32.C
    MASM5 CRT32.ASM,CRT32.OBJ,NUL;
    LINK386 CRT32.OBJ FIND32.OBJ,FIND32.EXE,NUL,,FIND32.DEF;

The BASIC-DOS repository has images of all 26 of the kit's diskettes, in
tools/os2/2.0/pr2/disks (MSOS2-2.0-PR2-*.img: the system's INSTALL and
DISK1-8, DEBUG1-2, LANG1-6, TOOLKIT1-5, and NET1-4); they're not on the
BASIC-DOS disks.

BASIC-DOS Versions
------------------

Everything above describes the original files.  On a BASIC-DOS hard disk,
MASM, MASM5, MAKE, LINK, LINK4, EXEMOD, MAPSYM, EXE2BIN, and the C compiler
(CL, C1, C2, and C3) in TOOLS\BIN are BASIC-DOS versions that run in protected
mode, too; their banners end in "BD" (eg, "Version 4.00BD").  The C and
alternate math libraries in TOOLS\LIB are BASIC-DOS versions as well.  For
the details, and for how to build C programs, see README.md in the
software/src/tools folder of the BASIC-DOS repository
(https://github.com/jeffpar/basicdos), and the sample in TOOLS\DEMOS\HELLO.

CL386 and C1_386 in TOOLS\BIN are BASIC-DOS versions, too, with one change:
each imported an OS/2 function by name, and the BASIC-DOS program loader
knows a library's functions only by number, so the file names that number
instead (their banners are unchanged).  C2_386, C3_386, and LINK386 are the
originals.  All five run on BASIC-DOS in protected mode only, and they
run on any 80286 or later, although the programs they compile need an 80386.

BDC.EXE in TOOLS\BIN isn't one of the original tools: it's a small, fast C
compiler written for BASIC-DOS, with its source in TOOLS\BDC.  Its object
files link with the Microsoft C libraries, as "MAKE BDC" in
TOOLS\DEMOS\SUCKS shows (the makefile there uses Microsoft C).
