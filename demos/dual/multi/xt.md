---
layout: page
title: BASIC-DOS on an IBM PC XT with Dueling Monitors
permalink: /demos/dual/multi/xt/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-dual-640kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Multi-Session Demo"
---

The machine below is an IBM PC XT (Model 5160) with a 4.77Mhz 8088, 640K of memory, two monitors (a Monochrome Display and a Color Display), two diskette drives, and a 10Mb hard disk.  It boots the BASIC-DOS Multi-Session Demo diskette and runs FOUR sessions, two on each monitor.  Since the machine has a hard disk, the boot sector first displays `Press a key to start...` on the Monochrome Display; press any key (or wait 2 seconds) to boot from the diskette, or press **Esc** to boot from the hard disk instead.

{% include machine.html id="ibm5160" %}

Use **SHIFT-TAB** to move keyboard focus from one session to the next.

This demo is also available on an [IBM PC](../pc/), an [IBM PC AT](../at/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="xt" %}
