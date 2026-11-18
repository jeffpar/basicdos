---
layout: page
title: BASIC-DOS on an IBM PC with Dueling Monitors
permalink: /demos/dual/multi/pc/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-dual-128kb.json
    debugger: available
    sizeRAM: 256
    autoMount:
      A: "BASIC-DOS Multi-Console"
    autoType: $date\r$time\r
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 256K of memory, two monitors (a Monochrome Display and a Color Display), and two diskette drives.  It boots the BASIC-DOS Multi-Console diskette and runs FOUR consoles, two on each monitor.

{% include machine.html id="ibm5150" name="IBM PC, 256Kb RAM, Dual Floppy Drives, MDA and CGA" %}

Use **SHIFT-TAB** to move keyboard focus from one console to the next.

Additional demo configurations:

- [Dueling Monitors on IBM PC XT](../xt/)
- [Dueling Monitors on IBM PC AT](../at/)
- [Dueling Monitors on COMPAQ DeskPro 386](../386/)
- [Dual Monitors on IBM PC](../../pc/)

{% include_relative _overview.md hw="pc" %}
