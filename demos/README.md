---
layout: page
heading: BASIC-DOS Demos
permalink: /demos/
---

Each BASIC-DOS demo runs on up to four generations of PC hardware: the original IBM PC (Model 5150) with its 4.77Mhz 8088 and diskette drives, the IBM PC XT (Model 5160), which added a 10Mb hard disk, the IBM PC AT (Model 5170), with a 6Mhz 80286 and a battery-powered real-time clock that keeps the date and time, and the COMPAQ DeskPro 386, COMPAQ's first PC with a 16Mhz 80386, shown here with 1Mb of memory (2Mb in the Extended Memory demos) and a VGA.  Click a machine to run that demo on that hardware.

| Demo | IBM PC | IBM PC XT | IBM PC AT | COMPAQ DeskPro 386 |
|------|--------|-----------|-----------|--------------------|
| 1. Monochrome | [64K, MDA](m64/pc/) | [640K, MDA](m64/xt/) | | |
| 2. VT100 Console | [64K, VT100](term/pc/) | [640K, VT100](term/xt/) | [640K, VT100x2](term/at/) | |
| 3. Color Graphics | [128K, CGA, 8087](s80/pc/) | [640K, CGA, 8087](s80/xt/) | [640K, CGA, 80287](s80/at/) | [1Mb, VGA, 80387](s80/386/) |
| 4. Dual 40-Column | [128K, CGA](d40/pc/) | [640K, CGA](d40/xt/) | [640K, CGA](d40/at/) | [1Mb, VGA](d40/386/) |
| 5. Dual 80-Column | [128K, CGA](d80/pc/) | [640K, CGA](d80/xt/) | [640K, CGA](d80/at/) | [1Mb, VGA](d80/386/) |
| 6. Multiple Pages | [256K, MDA](p80/pc/) | [640K, CGA](p80/xt/) | [640K, CGA](p80/at/) | [1Mb, VGA](p80/386/) |
| 7. Dual Monitors | [256K, MDA, CGA](dual/pc/) | [640K, MDA, CGA](dual/xt/) | [640K, MDA, CGA](dual/at/) | [1Mb, MDA, CGA](dual/386/) |
| 8. Serial Mouse | [256K, EGA, Mouse](mouse/pc/) | [640K, EGA, Mouse](mouse/xt/) | [640K, EGA, Mouse](mouse/at/) | [1Mb, VGA, Mouse](mouse/386/) |
| 9. VT100 Debugger | [256K, EGA, VT100](debug/pc/) | [640K, EGA, VT100](debug/xt/) | [640K, EGA, VT100](debug/at/) | [1Mb, VGA, VT100](debug/386/) |
| 10. 10Mb Drive | | [640K, EGA](hd/xt/) | [640K, EGA](hd/at/) | [1Mb, VGA](hd/386/) |
| 11. 10Mb (VT100 Console) | | [640K, EGA, VT100](vt100/xt/) | [640K, EGA, VT100](vt100/at/) | [1Mb, VGA, VT100](vt100/386/) |
| 12. Wolfenstein 3D | | | [640K, VGA, Sound](wolf3d/at/) | [1Mb, VGA, Sound](wolf3d/386/) |
| 13. Extended Memory (2Mb) | | | [2Mb, CGA](mmu/) | [2Mb, VGA](mmu/386/) |
| 14. Extended Memory (Debugger) | | | [2Mb, CGA, VT100](mmu/vt100/) | [2Mb, VGA, VT100](mmu/vt100/386/) |

The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to continue.  The PC XT, PC AT, and DeskPro 386 machines also have the 10Mb BASIC-DOS hard disk (drive C:), so when they boot a diskette, you can press **Esc** to boot from the hard disk instead.  On a PC AT or DeskPro 386, the demos run in protected mode (and on the DeskPro 386, with the 80386's features), except Wolfenstein 3D, which needs real mode; press **R** to run any other demo in real mode instead.

A *VT100 Console* is a BASIC-DOS session on a DEC VT100 terminal, which you can type commands at, while a *VT100 Debugger* is DEBUG.COM, BASIC-DOS's own debugger, running on a VT100 connected to COM2 (most demos also have a page with the PCjs debugger, which is part of the emulator).

In the demos with multiple consoles, use **SHIFT-TAB** to toggle keyboard focus between consoles.
