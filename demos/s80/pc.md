---
layout: page
title: BASIC-DOS on an IBM PC with a Single Session
permalink: /demos/s80/pc/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb-fpu.json
    debugger: available
    autoMount:
      A: "BASICDOS-360K-S80"
      B: "PC DOS 1.00"
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088 with an 8087, 128K of memory, a Color Display, and two diskette drives.  It boots the BASICDOS-360K-S80 diskette and runs a single 80-column session, with the BASIC samples (eg, DONKEY.BAS) in its SAMPLES directory.

{% include machine.html id="ibm5150" %}

Use the **MEM** command to display current memory usage.

This demo is also available on an [IBM PC XT](../xt/), an [IBM PC AT](../at/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="pc" %}
