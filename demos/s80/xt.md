---
layout: page
title: BASIC-DOS on an IBM PC XT with a Single Session
permalink: /demos/s80/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb-fpu.json
    debugger: available
    autoMount:
      A: "BASIC-DOS 80-Column Demo"
      B: "PC DOS 1.00"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088 with an 8087, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk.  It boots the BASIC-DOS 80-Column Demo diskette and runs a single 80-column session, with the BASIC samples (eg, DONKEY.BAS) in its SAMPLES directory.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.

{% include machine.html id="ibm5160" %}

Use the **MEM** command to display current memory usage.

This demo is also available on an [IBM PC](../pc/), an [IBM PC AT](../at/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="xt" %}
