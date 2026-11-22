---
layout: page
title: BASIC-DOS on an IBM PC AT with Multiple Video Pages
permalink: /demos/bd/p80/at/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Multi-Page"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, a Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk.  It boots the BASIC-DOS Multi-Page diskette and runs Multiple Video Pages, each on its own page of video memory; use **SHIFT-TAB** to switch between them.  The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Unlike the PC and PC XT, the PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include machine.html id="ibm5170" %}

Additional hardware options:

- [Multiple Video Pages on IBM PC](../pc/)
- [Multiple Video Pages on IBM PC XT](../xt/)
- [Multiple Video Pages on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="at" %}
