---
layout: page
title: BASIC-DOS on an IBM PC with a Mouse
permalink: /demos/mouse/pc/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-ega-256kb-mouse.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Single"
    autoType: $date\r$time\rPAINT\r
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 256K of memory, an Enhanced Color Display, and two diskette drives, plus a serial mouse on COM2.  It boots the BASIC-DOS Single diskette and runs PAINT.BAS.  Click the screen to capture the mouse, and hold the left button down to draw; press **Esc** twice to exit.

{% include machine.html id="ibm5150" %}

Additional demo configurations:

- [Serial Mouse on IBM PC XT](../xt/)
- [Serial Mouse on IBM PC AT](../at/)
- [Serial Mouse on COMPAQ DeskPro 386](../386/)

{% include_relative _overview.md hw="pc" %}
