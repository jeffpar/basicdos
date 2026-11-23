---
layout: page
title: BASIC-DOS on an IBM PC XT with Two 80-Column Consoles
permalink: /demos/bd/d80/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS 80-Cols"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Color Display, two diskette drives, and a 20Mb hard disk.  It boots the BASIC-DOS 80-Cols diskette and runs two 80-column consoles, one above the other; use **SHIFT-TAB** to toggle focus.  The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so PCjs supplies them at startup.

{% include machine.html id="ibm5160" %}

Additional hardware options:

- [80-Column Consoles on IBM PC](../pc/)
- [80-Column Consoles on IBM PC AT](../at/)
- [80-Column Consoles on COMPAQ DeskPro 386](../386/)

Additional IBM PC XT configurations:

- [Parallel Printer on LPT1](../../parallel/)
- [Serial Console on COM1](../../serial/)

{% include_relative _overview.md hw="xt" %}
