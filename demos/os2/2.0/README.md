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

The machine below is a COMPAQ DeskPro 386 with a 16Mhz 80386, 4Mb of memory (640K of conventional memory, 3Mb of extended memory, plus 384K of "Shadow RAM" near the 16Mb boundary), a VGA Color Display, a 1.2Mb and a 1.44Mb diskette drive, a 47Mb hard disk, and a serial mouse on COM1.  The hard disk contains Microsoft's second pre-release of OS/2 2.0 (revision 6.78, May 1990), which is running below to help us make some comparisons between BASIC-DOS and OS/2 2.0 capabilities.

While [BASIC-DOS](/demos/bd/mmu/386/) has no graphical user interface (yet), it does have the ability to run 16-bit and 32-bit protected-mode programs, as well as DOS programs in V86-mode.  Take a look at the `SDK` folder in [BASIC-DOS on a COMPAQ DeskPro 386](/demos/bd/mmu/386/) for some examples.

{% include machine.html id="deskpro386" %}

OS/2 boots from the hard disk into Presentation Manager, whose Desktop Manager can start OS/2 sessions and DOS sessions, in a window or full screen; type `ver` in either kind of session to display "The Operating System/2 Version is 2.00".  Click the screen to capture the mouse, and press **Esc** to release it.

This pre-release came before IBM took over OS/2 2.0's development and added the Workplace Shell, so its desktop looks much like OS/2 1.2's, but it requires an 80386: it uses paging, runs 32-bit programs (built with the SDK's CL386 and LINK386), and runs each DOS session in its own V86 machine.  The installation's optional "Device Support" diskette step wasn't completed.

Running this pre-release required several fixes to the PCjs emulator, mostly in 80386 call gates, task switches, and privilege checks, plus the 8042 keyboard controller; a [Debugger](debugger/) page has the same machine with the PCjs debugger.
