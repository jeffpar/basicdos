---
layout: page
title: BASIC-DOS on an IBM PC AT with a Mouse
permalink: /demos/mouse/at/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-ega-640kb-mouse.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Mouse"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 640K of memory, an Enhanced Color Display, a 1.2Mb and a 1.44Mb diskette drive, and a 10Mb hard disk, plus a serial mouse on COM2.  It boots the BASIC-DOS Mouse diskette, whose CONFIG.SYS runs PAINT.BAS.  Click the screen to capture the mouse, and hold the left button down to draw; press **Esc** twice to exit.  The boot sector first displays `System starting...`; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.

{% include machine.html id="ibm5170" %}

Additional hardware options:

- [Serial Mouse on IBM PC](../pc/)
- [Serial Mouse on IBM PC XT](../xt/)
- [Serial Mouse on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="at" %}
