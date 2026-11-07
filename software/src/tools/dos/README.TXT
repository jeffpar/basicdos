BASIC-DOS Build Tools
=====================

Most of the tools in this directory build BASIC-DOS from its source code (see
SRC: type CD \SRC and then MK), and they can all be used with other software
on BASIC-DOS, too.  None of them are part of BASIC-DOS: they came from the
three Microsoft products described below.  They're unmodified, except for
those on a BASIC-DOS disk that are protected-mode conversions (see the last
section).

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

Two files were taken from this product:

    MAKE     EXE     23418  06-27-86   Program Maintenance Utility 4.02
    LINK4    EXE     60006  07-18-86   Segmented-Executable Linker 5.00.12

MAKE 4.02 replaces the MASM package's MAKE 4.00, which runs every command
through COMMAND /C; MAKE 4.02 runs programs directly, which is faster and
needs less memory.

LINK4 comes from the product's eighth diskette ("C WINDOWS"), which updated
the Windows Software Development Kit 1.01 for C 4.00.  It links "new
executable" (NE) programs, which list each segment's type (code or data),
size, and relocations, as a protected-mode loader needs.  It builds
TESTS\BIN\PRIMES.EXE (see TESTS\PRIMES\PRIMES.DEF), with the MS-DOS program
that LINK builds as its stub, so the file runs in real mode, too.

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

BASIC-DOS Protected-Mode Tools
------------------------------

MASM.EXE, MAKE.EXE, LINK.EXE, LINK4.EXE, EXEMOD.EXE, MAPSYM.EXE, and EXE2BIN.EXE
in TOOLS on a BASIC-DOS disk are converted to NE executables, which perform the
same as the originals: BASIC-DOS builds itself with them, in either mode, and
the binaries are the same as those of an MS-DOS build.  Protected-mode BASIC-DOS
runs the NE images at ring 3, and in real mode, an NE loader stub, in place of
the MZ image, runs the same NE image.  The NE images have fixed code and data
segments, translate the MZ segment relocations to NE relocations, replace
privileged CLI and STI instructions where necessary, and adapt the programs'
real-mode memory setup.  Their banners end in "BD" (eg, "Version 4.00BD") to
identify the conversions, except for EXE2BIN, which has no banner.

Their data segments are always 64K, whereas the originals use less when memory
is short, so in real mode, MAKE and MASM together need about 229K of free memory.

In the BASIC-DOS repository, the unmodified tools are in
software/src/tools/dos, and the conversions are in software/src/tools/bd.  A
disk's TOOLS folder gets the former, overlaid with the latter, and mk.sh's
PATH$ searches bd first.  Run "node tools/misc/mkne.js" to rebuild all the
conversions from their originals.
