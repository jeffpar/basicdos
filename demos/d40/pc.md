---
layout: page
title: BASIC-DOS on an IBM PC with Two 40-Column Consoles
permalink: /demos/d40/pc/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS 40-Cols"
      B: "PC DOS 2.00 (Disk 1)"
    autoType: $date\r$time\r
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 128K of memory, a Color Display, and two diskette drives.  It boots the BASIC-DOS 40-Cols diskette and runs two 40-column consoles side by side; use **SHIFT-TAB** to toggle focus.

{% include machine.html id="ibm5150" %}

Additional hardware options:

- [40-Column Consoles on IBM PC XT](../xt/)
- [40-Column Consoles on IBM PC AT](../at/)
- [40-Column Consoles on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="pc" %}
