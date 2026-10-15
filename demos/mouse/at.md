---
layout: page
title: BASIC-DOS on an IBM PC AT with a Mouse
permalink: /demos/mouse/at/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb-mouse.json
    autoMount:
      A: "BASICDOS-360K-S80"
    autoType: PAINT\r
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk, plus a serial mouse on COM2.  It boots the BASICDOS-360K-S80 diskette and runs PAINT.BAS.  Click the screen to capture the mouse, and hold the left button down to draw; press **Esc** twice to exit.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 5 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.

{% include machine.html id="ibm5170" %}

This demo is also available on an [IBM PC](../pc/), an [IBM PC XT](../xt/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="at" %}
