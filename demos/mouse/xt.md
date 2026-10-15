---
layout: page
title: BASIC-DOS on an IBM PC XT with a Mouse
permalink: /demos/mouse/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb-mouse.json
    autoMount:
      A: "BASICDOS-DISK1"
    autoType: PAINT\r
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, a Color Display, two diskette drives, and a 10Mb hard disk, plus a serial mouse on COM2.  It boots the BASICDOS-DISK1 diskette and runs PAINT.BAS.  Click the screen to capture the mouse, and hold the left button down to draw; press **Esc** twice to exit.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 5 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.

{% include machine.html id="ibm5160" %}

This demo is also available on an [IBM PC](../pc/) and an [IBM PC AT](../at/).

{% include_relative _overview.md hw="xt" %}
