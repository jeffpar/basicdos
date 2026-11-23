---
layout: page
title: BASIC-DOS on an IBM PC XT with a Mouse
permalink: /demos/bd/mouse/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-ega-640kb-mouse.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Mouse"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, an Enhanced Color Display, two diskette drives, and a 20Mb hard disk, plus a serial mouse on COM2.  It boots the BASIC-DOS Mouse diskette, whose CONFIG.SYS runs PAINT.BAS.  Click the screen to capture the mouse, and hold the left button down to draw; press **Esc** twice to exit.  The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.  The PC XT has no clock to keep the date and time, so PCjs supplies them at startup.

{% include machine.html id="ibm5160" %}

Additional hardware options:

- [Serial Mouse on IBM PC](../pc/)
- [Serial Mouse on IBM PC AT](../at/)
- [Serial Mouse on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="xt" %}
