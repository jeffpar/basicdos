---
layout: page
title: BASIC-DOS on an IBM PC XT with Two 40-Column Consoles
permalink: /demos/d40/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS 40-Cols"
      B: "PC DOS 2.00 (Disk 1)"
    autoType: $date\r$time\r
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk.  It boots the BASIC-DOS 40-Cols diskette and runs two 40-column consoles side by side; use **SHIFT-TAB** to toggle focus.  The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so BASIC-DOS prompts for them at startup, and this page types the current date and time.

{% include machine.html id="ibm5160" %}

Additional demo configurations:

- [40-Column Consoles on IBM PC](../pc/)
- [40-Column Consoles on IBM PC AT](../at/)
- [40-Column Consoles on COMPAQ DeskPro 386](../386/)
- [Serial Port on IBM PC XT](../../serial/) with a serial console on COM1
- [Parallel Port on IBM PC XT](../../parallel/) with a printer on LPT1

{% include_relative _overview.md hw="xt" %}
