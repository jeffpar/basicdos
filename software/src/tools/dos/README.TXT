BASIC-DOS Build Tools
=====================

Most of the tools in this directory build BASIC-DOS from its source code (see
SRC: type CD \SRC and then MK), and they can all be used with other software
on BASIC-DOS, too; the exceptions are the 80386 tools, which are for code that
BASIC-DOS doesn't build yet.  None of them are part of BASIC-DOS: they came
from the four Microsoft products described below.  They're unmodified, except
for those on a BASIC-DOS disk that are protected-mode conversions (see the
last section).

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
and include files must be in the current directory (the conversions described
below don't have this limitation).  BASIC-DOS has no INCLUDE, LIB, or TMP
environment variables, so use /I for the include files, keep the libraries in the current directory (or
give LINK their path), and expect temporary files in the current directory.

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
used to build the libraries described in the last section.

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

MASM5.EXE is converted, too, and assembles the same object files as the
original; its listings differ only in the banner, and in the far memory
reported free, since its data segment is always 64K.

Their data segments are always 64K, whereas the originals use less when memory
is short, so in real mode, MAKE and MASM together need about 229K of free memory.

CL.EXE, C1.EXE, C2.EXE, and C3.EXE are converted, too, and compile the same
object files as the originals, in either mode.  In addition to the changes
above:

  - CL and C1 build include file paths with "\" instead of "/", so /I works.
  - CL passes each pass its arguments in the environment (MSC_CMD_FLAGS), so
    it copies the environment it builds to a block of its own for the pass.
  - Each pass contains Microsoft's 8087 emulator (for floating-point
    constants), which uses INT 34h through 3Eh; ring 3 programs can't issue
    or hook those, so the passes issue INT 3 instead, followed by the second
    byte of the original INT, and the emulator hooks only INT 3.

C programs for protected mode are NE programs, which LINK4 builds.  The
compiler's libraries start a program with real-mode code (it sizes the data
segment with segment arithmetic, shrinks the program's memory, and disables
interrupts), so LIB has BASIC-DOS versions of the four C libraries (SLIBC.LIB,
MLIBC.LIB, CLIBC.LIB, and LLIBC.LIB), in which the startup module (crt0) has
been replaced with the one in TOOLS\CRT\BDCRT0.ASM; they are otherwise the same.
To build a program (eg, HELLO.C, small model, with the include files and
libraries in these folders):

    CL /c /FPa /I\TOOLS\INCLUDE HELLO.C
    LINK4 HELLO,HELLO.EXE,NUL,\TOOLS\LIB\,HELLO.DEF

where HELLO.DEF contains these lines (the heap and the stack share the sum of
the two sizes; see BDCRT0.ASM):

    NAME HELLO
    PROTMODE
    CODE FIXED
    DATA FIXED
    STACKSIZE 2048
    HEAPSIZE 8192

Floating-point programs must be compiled with /FPa, which makes
every floating-point operation a call to the math library, since the default
(/FPi) produces the 8087 emulator's INT 34h through 3Dh instructions.  LIB has
BASIC-DOS versions of the four alternate math libraries, too (SLIBFA.LIB,
MLIBFA.LIB, CLIBFA.LIB, and LLIBFA.LIB), in which those calls, the C library's
conversions (for printf, scanf, atof, etc), and the math functions use the
FPU$ driver (see BDFP.ASM and BDMATH.C in TOOLS\FP), so a C program's doubles are
the same IEEE values as BASIC-DOS's, an 8087 is used if there is one, and a
program without FPU$ ends with "Floating point not loaded".  Microsoft's
libraries work in protected mode, too (they're all software, and need nothing
from the system), but their arithmetic isn't IEEE arithmetic.  FPTEST.C (in TOOLS\FP,
with a makefile) prints the same results with either.

The result runs in protected mode only.  STUB (in TOOLS; its source is in
TOOLS\STUB) copies an NE program, replacing its MZ stub with the BASIC-DOS NE
loader stub, and the copy runs in real mode, too, like the tools described
above:

    LINK4 HELLO,HELLO.NE,NUL,\TOOLS\LIB\,HELLO.DEF
    STUB HELLO.NE HELLO.EXE

TOOLS\HELLO has that sample, with a makefile that explains each step ("MAKE
MAKEFILE" builds it).  STUB is itself a C program built that way, and it
writes the same file as "node tools/misc/mkne.js --stub" on the host, so it
runs in either mode.  Limitations: the heap can't grow beyond the DEF file's sizes
(the library's code to grow it is still real-mode code), and spawn and exec
haven't been adapted (see CL's changes above).

The libraries were built on BASIC-DOS, in real mode, with these commands for
each memory model (here, small):

    MASM /MX /DMEM_S BDCRT0.ASM,CRT0.OBJ;
    DOSSEG CRT0.OBJ
    LIB SLIBC -+CRT0;
    MASM /MX /DMEM_S /I\SRC\INC BDFP.ASM,BDFP.OBJ;
    CL /c /AS /FPa /Gs BDMATH.C
    LIB @FA.RSP

where FA.RSP removes Microsoft's arithmetic, conversions, and math functions,
and adds ours (the modules that remain are fltuseda, fabs, matherr, huge,
frexp, ixtomx, cixtomx, fpreset, arndfstr, fccvt, cabs, bessel, and hypot):

    SLIBFA.LIB
    -ccall-ccalle-ifcall-ixconv-ixcomp-i4math-i8math-cfin-cfout-i8fin-i8fout&
    -i8tmul-cdisp-csqrt-ctran-ctrig-ctriga-ctrigh-i8sqr-i8help-i8comm-i8tran&
    -i8trig-ldexp-modf-flrceil-fmod+BDFP+BDMATH
    NUL
    NEW\SLIBFA.LIB

In the BASIC-DOS repository, the unmodified tools are in
software/src/tools/dos, and the conversions are in software/src/tools/bd
(the libraries are in the lib folder of each, the include files are in
software/src/tools/dos/include, and the startup code, the floating-point
sources, STUB's source, and the HELLO sample are in software/src/tools/bd's
crt, fp, stub, and hello folders, which a disk has as TOOLS\CRT, etc).  A
disk's TOOLS folder gets the former, overlaid with the latter, and mk.sh's
PATH$ searches bd first.  Run "node tools/misc/mkne.js" to rebuild all the
conversions from their originals.
