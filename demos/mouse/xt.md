---
layout: page
title: BASIC-DOS on an IBM PC XT with a Mouse
permalink: /demos/mouse/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-ega-640kb-mouse.json
    debugger: available
    autoMount:
      A: "BASIC-DOS 80-Column Demo"
    autoType: DATE $date\rTIME $time\rPAINT\r
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, an Enhanced Color Display, two diskette drives, and a 10Mb hard disk, plus a serial mouse on COM2.  It boots the BASIC-DOS 80-Column Demo diskette and runs PAINT.BAS.  Click the screen to capture the mouse, and hold the left button down to draw; press **Esc** twice to exit.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so this page types `DATE` and `TIME` commands with the current date and time at the first prompt.

{% include machine.html id="ibm5160" %}

This demo is also available on an [IBM PC](../pc/), an [IBM PC AT](../at/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="xt" %}
