---
layout: page
heading: BASIC-DOS Demos
permalink: /demos/
---

Each BASIC-DOS demo runs on up to three generations of IBM hardware: the original IBM PC (Model 5150) with its 4.77Mhz 8088 and diskette drives, the IBM PC XT (Model 5160), which added a 10Mb hard disk, and the IBM PC AT (Model 5170), with a 6Mhz 80286 and a battery-powered real-time clock that keeps the date and time.  Click a machine to run that demo on that hardware.

| Demo | IBM PC | IBM PC XT | IBM PC AT |
|------|--------|-----------|-----------|
| 1. Full-Screen Session | [128K, CGA](s80/pc/) | [640K, CGA](s80/xt/) | [640K, CGA](s80/at/) |
| 2. 40-column Sessions | [128K, CGA](d40/pc/) | [640K, CGA](d40/xt/) | [640K, CGA](d40/at/) |
| 3. 80-column Sessions | [128K, CGA](d80/pc/) | [640K, CGA](d80/xt/) | [640K, CGA](d80/at/) |
| 4. Dual Monitors | [128K, MDA, CGA](dual/pc/) | [640K, MDA, CGA](dual/xt/) | [640K, MDA, CGA](dual/at/) |
| 5. Serial Mouse | [256K, CGA, Mouse](mouse/pc/) | [640K, CGA, Mouse](mouse/xt/) | [640K, CGA, Mouse](mouse/at/) |
| 6. Serial Debugger | [128K, CGA, VT100](debug/pc/) | [640K, CGA, VT100](debug/xt/) | [640K, CGA, VT100](debug/at/) |
| 7. 10Mb Hard Disk | | [640K, CGA](hd/xt/) | [640K, CGA](hd/at/) |
| 8. 10Mb Hard Disk with VT100 | | [640K, CGA, VT100](vt100/xt/) | [640K, CGA, VT100](vt100/at/) |

The PC XT and PC AT machines also have the 10Mb BASIC-DOS hard disk (drive C:), so when they boot a diskette, the boot sector first displays `Press a key to start...`; press any key (or wait 5 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  There's also a [Serial Display](serial/) demo, which runs a second session on a simple text pane connected to COM1.

In the demos with multiple sessions, use **SHIFT-TAB** to toggle keyboard focus between sessions.
