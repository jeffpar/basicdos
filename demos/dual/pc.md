---
layout: page
title: BASIC-DOS on an IBM PC with Dual Monitors
permalink: /demos/dual/pc/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-dual-128kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS Dual Monitor Demo"
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 128K of memory, two monitors (a Monochrome Display and a Color Display), and two diskette drives.  It boots the BASIC-DOS Dual Monitor Demo diskette and runs one session on each monitor: PRIMES.BAT on the Monochrome Display and, since there's no hard disk, PIPES.BAT on the Color Display, which pipes the output of DIR through the TR filter (converting it to upper-case) over and over.

{% include machine.html id="ibm5150" %}

Use **SHIFT-TAB** to move keyboard focus from one session to the next.  For even more sessions, try the [Dueling Monitors](../multi/pc/) demo, which runs FOUR sessions, two on each monitor.

This demo is also available on an [IBM PC XT](../xt/), an [IBM PC AT](../at/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="pc" %}
