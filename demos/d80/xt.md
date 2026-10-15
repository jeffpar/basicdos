---
layout: page
title: BASIC-DOS on an IBM PC XT with Two 80-Column Sessions
permalink: /demos/d80/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    autoMount:
      A: "BASICDOS-360K-D80"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk.  It boots the BASICDOS-360K-D80 diskette and runs two 80-column sessions, one above the other; use **SHIFT-TAB** to toggle focus.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 5 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.

{% include machine.html id="ibm5160" %}

This demo is also available on an [IBM PC](../pc/), an [IBM PC AT](../at/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="xt" %}
