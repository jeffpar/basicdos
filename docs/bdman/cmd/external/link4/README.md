---
layout: sheet
title: LINK4
permalink: /docs/bdman/cmd/external/link4/
---

{% include header.html %}

> LINK4 [*objects* [,*program* [,*map* [,*libraries* [,*definitions*]]]]]

LINK4 is Microsoft Segmented-Executable Linker 5.00.12.  It combines one or
more object modules into a segmented (NE) executable.  If a field is omitted,
LINK4 prompts for it; a semicolon after the last field accepts the remaining
defaults.

The definitions file controls the NE program's name, segments, imports,
exports, and protected-mode attributes.  BASIC-DOS uses LINK4 to build
**TESTS\\BIN\\PRIMES.EXE** from **TESTS\\PRIMES\\PRIMES.DEF**.  The `/ALIGN:`
switch follows the program field (for example,
`PRIMES.EXE/ALIGN:16`) and selects a power-of-two segment alignment.  At the
BASIC-DOS prompt, enter that value at LINK4's `Run File` prompt: COMMAND
currently treats the colon in a multi-letter switch as a command separator.
MAKE invokes LINK4 directly, so the same form works in a makefile.

The hard disk demo provides LINK4 in **TOOLS**.  Its dual MZ/NE executable
runs at ring 3 in protected mode, where its banner ends in
`Version 5.00.12BD`; MS-DOS and real-mode BASIC-DOS run the original MZ image
and display the original banner.

The unmodified Microsoft executable is
[LINK4.EXE](https://github.com/jeffpar/basicdos/blob/main/software/src/tools/dos/LINK4.EXE),
and [mklink4ne.js](https://github.com/jeffpar/basicdos/blob/main/tools/misc/mklink4ne.js)
creates the BASIC-DOS conversion.

{% include footer.html prev="LABEL:../label/" next="LS:../ls/" %}
