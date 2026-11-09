---
layout: page
title: BASIC-DOS on an IBM PC with Multiple Video Pages
permalink: /demos/p80/pc/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-mda-64kb.json
    debugger: available
    sizeRAM: 256
    autoMount:
      A: "BASIC-DOS Multi-Page Demo"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 256K of memory, a Monochrome Display, and two diskette drives.  It boots the BASIC-DOS Multi-Page Demo diskette and runs three full-screen consoles, but a monochrome adapter has memory for only one page, so the other two consoles get virtual pages (4,000 bytes each) in system memory instead; use **SHIFT-TAB** to switch between them, and the page of the console you switch to trades places with the page on the screen.  The other machines run this demo on a Color Display, with each console on its own page of video memory.

{% include machine.html id="ibm5150" name="IBM PC, 256Kb RAM, Dual Floppy Drives, MDA, No Ports" %}

This demo is also available on an [IBM PC XT](../xt/), an [IBM PC AT](../at/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="pc" %}
