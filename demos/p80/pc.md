---
layout: page
title: BASIC-DOS on an IBM PC with Multiple Video Pages
permalink: /demos/p80/pc/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    debugger: available
    autoMount:
      A: "BASICDOS-360K-P80"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 128K of memory, a Color Display, and two diskette drives.  It boots the BASICDOS-360K-P80 diskette and runs Multiple Video Pages, each on its own page of video memory; use **SHIFT-TAB** to switch between them.

{% include machine.html id="ibm5150" %}

This demo is also available on an [IBM PC XT](../xt/), an [IBM PC AT](../at/), and a [COMPAQ DeskPro 386](../386/).

{% include_relative _overview.md hw="pc" %}
