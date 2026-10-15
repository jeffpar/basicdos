---
layout: page
title: BASIC-DOS on an IBM PC AT with a Single Session
permalink: /demos/s80/at/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb.json
    autoMount:
      A: "BASICDOS-360K-S80"
      B: "PC DOS 1.00"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk.  It boots the BASICDOS-360K-S80 diskette and runs a single 80-column session, with the BASIC samples (eg, DONKEY.BAS) in its SAMPLES directory.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 5 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  Unlike the PC and PC XT, the PC AT has a battery-powered real-time clock, so BASIC-DOS starts with the current date and time (type `DATE` or `TIME` to see them).

{% include machine.html id="ibm5170" %}

Use the **MEM** command to display current memory usage (or **MEM /D** for details).

This demo is also available on an [IBM PC](../pc/), an [IBM PC XT](../xt/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="at" %}
