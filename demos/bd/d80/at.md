---
layout: page
title: BASIC-DOS on an IBM PC AT with Two 80-Column Consoles
permalink: /demos/bd/d80/at/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS 80-Cols"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, a Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 20Mb hard disk.  It boots the BASIC-DOS 80-Cols diskette and runs two 80-column consoles, one above the other; use **SHIFT-TAB** to toggle focus.  The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Unlike the PC and PC XT, the PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include machine.html id="ibm5170" %}

Additional hardware options:

- [80-Column Consoles on IBM PC](../pc/)
- [80-Column Consoles on IBM PC XT](../xt/)
- [80-Column Consoles on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="at" %}
