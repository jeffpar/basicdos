---
layout: page
title: Microsoft OS/2 2.0 (Pre-Release) on a COMPAQ DeskPro 386
permalink: /demos/os2/2.0/
machines:
  - id: deskpro386
    type: pcx86
    config: /machines/pcx86/compaq/compaq-deskpro386-vga-4mb.json
    debugger: available
    drives: '[{name:"OS/2 2.0 Pre-Release (47Mb)",type:5,path:"/demos/os2/2.0/MSOS2-2.0-PR2-47MB.json"}]'
---

The machine below is a COMPAQ DeskPro 386 with a 16Mhz 80386, 4Mb of memory (640K of conventional memory, 384K of "COMPAQ Built-in Memory" used for ROM Relocation and CEMM, and 3Mb of extended memory), a VGA Color Display, a 1.2Mb and a 1.44Mb diskette drive, a 47Mb hard disk, and a serial mouse on COM1.  The hard disk contains Microsoft's second pre-release of OS/2 2.0 (revision 6.78, May 1990), which is running below to help us make some comparisons between BASIC-DOS and OS/2 2.0 capabilities.

While [BASIC-DOS](/demos/bd/mmu/386/) has no graphical user interface (yet), it does have the ability to run 16-bit and 32-bit protected-mode programs, as well as DOS programs in V86-mode.  Take a look at the `SDK` folder in [BASIC-DOS on a COMPAQ DeskPro 386](/demos/bd/mmu/386/) for some examples.

{% include machine.html id="deskpro386" %}

OS/2 boots from the hard disk into Presentation Manager, whose Desktop Manager can start OS/2 sessions and DOS sessions, in a window or full screen; type `ver` in either kind of session to display "The Operating System/2 Version is 2.00".  Click the screen to capture the mouse, and press **Esc** to release it.

This pre-release came before IBM took over OS/2 2.0's development and added the Workplace Shell, so its desktop looks much like OS/2 1.2's, but it requires an 80386: it uses paging, runs 32-bit programs (built with the SDK's CL386 and LINK386), and runs each DOS session in its own V86 machine.

To compare the two systems, the hard disk has a `C:\TOOLS` folder laid out like the one on the [BASIC-DOS](/demos/bd/mmu/386/) hard disk, with the SDK's build tools (CL386, LINK386, NMAKE, etc) in `C:\TOOLS\BIN`, which **CONFIG.SYS** adds to the PATH, and the 386 compiler's include files and libraries in `C:\TOOLS\INCLUDE\386` and `C:\TOOLS\LIB\386`.  The HELLO and SUCKS demos in `C:\TOOLS\DEMOS` each have an MK386.CMD that builds their 32-bit versions; for example, in an OS/2 Window, type `cd \tools\demos\hello`, then `mk386`, and then `helloc`.
