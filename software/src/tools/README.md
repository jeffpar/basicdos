## BASIC-DOS Build Tools

[README.TXT](README.TXT) (which a BASIC-DOS hard disk has in **TOOLS**) describes where the original tools came from.  This page describes what BASIC-DOS has done with them: the protected-mode versions of the tools, the libraries and startup code for C programs, and how all of that is built.

### Layout

| Folder | On the hard disk | Contents |
| --- | --- | --- |
| [dos](dos/) | TOOLS\\BIN | The original tools, unmodified |
| [dos/include](dos/include/) | TOOLS\\INCLUDE | The C compiler's include files |
| [dos/lib](dos/lib/) | | The C compiler's libraries, unmodified |
| [bd](bd/) | TOOLS\\BIN | BASIC-DOS versions of the tools, and STUB.EXE |
| [bd/lib](bd/lib/) | TOOLS\\LIB | BASIC-DOS versions of the libraries (and LIBH.LIB from dos/lib) |
| [bd/crt](bd/crt/) | TOOLS\\CRT | The startup code for C programs (`bdcrt0.asm`) |
| [bd/fp](bd/fp/) | TOOLS\\FP | Floating point for C programs (`bdfp.asm`, `bdmath.c`), and a test (`fptest.c`) |
| [bd/stub](bd/stub/) | TOOLS\\STUB | The NE loader stub (`nestub.asm`, `NESTUB.BIN`) and STUB.EXE's source |
| [bd/hello](bd/hello/) | TOOLS\\HELLO | A C sample, with a makefile that explains each step |

The hard disk's **TOOLS\\BIN** gets the files in `dos`, overlaid with those in `bd`, and **TOOLS\\LIB** gets `dos/lib`, overlaid with `bd/lib` (see [gulpfile.js](../../../gulpfile.js)); `mk.sh` gets the same result by searching `bd` before `dos`.

### Protected-Mode Tools

MASM, MASM5, MAKE, LINK, LINK4, EXEMOD, MAPSYM, and EXE2BIN in `bd` are the originals converted from MZ to NE executables.  They perform the same as the originals: BASIC-DOS builds itself with them, in either mode, and the binaries are the same as those of an MS-DOS build.

Protected-mode BASIC-DOS runs the NE images at ring 3, and in real mode, an NE loader stub, in place of the MZ image, runs the same NE image.  The NE images have fixed code and data segments, translate the MZ segment relocations to NE relocations, replace privileged CLI and STI instructions where necessary, and adapt the programs' real-mode memory setup.  Their banners end in "BD" (eg, "Version 4.00BD") to identify the conversions, except for EXE2BIN, which has no banner.

MASM5 assembles the same object files as the original; its listings differ only in the banner, and in the far memory reported free.  The conversions' data segments are always 64K, whereas the originals use less when memory is short, so in real mode, MAKE and MASM together need about 229K.

The C compiler (CL, C1, C2, and C3) is converted, too, and compiles the same object files as the original, in either mode.  In addition to the changes above:

- CL and C1 build include file paths with `\` instead of `/`, so `/I` works (BASIC-DOS doesn't accept `/` in a path).
- CL passes each pass its arguments in the environment (`MSC_CMD_FLAGS`), so it copies the environment it builds to a block of its own for the pass.
- Each pass contains Microsoft's 8087 emulator (for floating-point constants), which uses INT 34h through 3Eh; ring 3 programs can't issue or hook those, so the passes issue INT 3 instead, followed by the second byte of the original INT, and the emulator hooks only INT 3.

[tools/misc/mkne.js](../../../tools/misc/mkne.js) makes all the conversions from their originals: run `node tools/misc/mkne.js` to rebuild them.

### C Programs

C programs for protected mode are NE programs, which LINK4 builds.  The compiler's libraries start a program with real-mode code (it sizes the data segment with segment arithmetic, shrinks the program's memory, and disables interrupts), so `bd/lib` has BASIC-DOS versions of the four C libraries (SLIBC.LIB, MLIBC.LIB, CLIBC.LIB, and LLIBC.LIB), in which the startup module (crt0) has been replaced with [bdcrt0.asm](bd/crt/bdcrt0.asm); they're otherwise the same.

To build a program on a BASIC-DOS hard disk (eg, HELLO.C, small model):

    CL /c /FPa /I\TOOLS\INCLUDE HELLO.C
    LINK4 HELLO,HELLO.NE,NUL,\TOOLS\LIB\,HELLO.DEF
    STUB HELLO.NE HELLO.EXE

where HELLO.DEF contains these lines (the heap and the stack share the sum of the two sizes; see `bdcrt0.asm`):

    NAME HELLO
    PROTMODE
    CODE FIXED
    DATA FIXED
    STACKSIZE 2048
    HEAPSIZE 8192

HELLO.NE runs in protected mode only.  STUB copies an NE program, replacing its MZ stub with the BASIC-DOS NE loader stub, and the copy runs in real mode, too, like the tools above.  [bd/hello](bd/hello/) has that sample, with a makefile that explains each step (`MAKE MAKEFILE` builds it).

STUB is itself a C program built that way (see [bd/stub](bd/stub/)), and it writes the same file as `node tools/misc/mkne.js --stub in.exe out.exe` on the host.  Its copy of the stub's code comes from `nestub.asm`, which is also the source of `NESTUB.BIN`, the copy that mkne.js uses.

Always compile with `/FPa`, even a program with no floating point: an object file compiled without it asks the linker for the 8087 emulator's library (EM.LIB), which isn't provided.

Limitations: the heap can't grow beyond the DEF file's sizes (the library's code to grow it is still real-mode code), and spawn and exec haven't been adapted (see CL's changes above).

### Floating Point

`/FPa` makes every floating-point operation a call to the alternate math library; the default (`/FPi`) produces the 8087 emulator's INT 34h through 3Dh instructions, which don't work at ring 3.  `bd/lib` has BASIC-DOS versions of the four alternate math libraries (SLIBFA.LIB, MLIBFA.LIB, CLIBFA.LIB, and LLIBFA.LIB), in which those calls, the C library's conversions (for printf, scanf, atof, etc), and the math functions use the FPU$ driver (see [bdfp.asm](bd/fp/bdfp.asm) and [bdmath.c](bd/fp/bdmath.c)).  So a C program's doubles are the same IEEE values as BASIC-DOS's, an 8087 is used if there is one, and a program without FPU$ ends with "Floating point not loaded".

Microsoft's alternate math libraries work in protected mode, too (they're all software, and need nothing from the system), but their arithmetic isn't IEEE arithmetic.  [fptest.c](bd/fp/fptest.c) prints the same results with either (`MAKE MAKEFILE` in its folder builds it).

### Building the Libraries

The libraries in `bd/lib` were built on BASIC-DOS, in real mode, from those in `dos/lib`, with these commands for each memory model (here, small):

    MASM /MX /DMEM_S BDCRT0.ASM,CRT0.OBJ;
    DOSSEG CRT0.OBJ
    LIB SLIBC -+CRT0;
    MASM /MX /DMEM_S /I\SRC\INC BDFP.ASM,BDFP.OBJ;
    CL /c /AS /FPa /Gs BDMATH.C
    LIB @FA.RSP

where FA.RSP removes Microsoft's arithmetic, conversions, and math functions, and adds ours (the modules that remain are fltuseda, fabs, matherr, huge, frexp, ixtomx, cixtomx, fpreset, arndfstr, fccvt, cabs, bessel, and hypot):

    SLIBFA.LIB
    -ccall-ccalle-ifcall-ixconv-ixcomp-i4math-i8math-cfin-cfout-i8fin-i8fout&
    -i8tmul-cdisp-csqrt-ctran-ctrig-ctriga-ctrigh-i8sqr-i8help-i8comm-i8tran&
    -i8trig-ldexp-modf-flrceil-fmod+BDFP+BDMATH
    NUL
    NEW\SLIBFA.LIB

Of the compiler's 15 libraries, `dos/lib` has only the nine that are used: the four C libraries, the four alternate math libraries, and the helper library (LIBH.LIB), which every program needs.  The floating-point libraries (SLIBFP.LIB, etc), the 8087 emulator (EM.LIB), and the 8087 library (87.LIB) are the `/FPi` libraries.
