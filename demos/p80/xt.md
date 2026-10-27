---
layout: page
title: BASIC-DOS on an IBM PC XT with Multiple Video Pages
permalink: /demos/p80/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Multi-Page Demo"
      B: "PC DOS 2.00 (Disk 1)"
    autoType: DATE $date\rTIME $time\r
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk.  It boots the BASIC-DOS Multi-Page Demo diskette and runs Multiple Video Pages, each on its own page of video memory; use **SHIFT-TAB** to switch between them.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so this page types `DATE` and `TIME` commands with the current date and time at the first prompt.

{% include machine.html id="ibm5160" %}

This demo is also available on an [IBM PC](../pc/), an [IBM PC AT](../at/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="xt" %}
