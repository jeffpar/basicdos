---
layout: page
title: BASIC-DOS on an IBM PC with Two 40-Column Sessions
permalink: /demos/d40/pc/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoMount:
      A: "BASICDOS-DISK2"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088, 128K of memory, a Color Display, and two diskette drives.  It boots the BASICDOS-DISK2 diskette and runs two 40-column sessions side by side; use **SHIFT-TAB** to toggle focus.

{% include machine.html id="ibm5150" %}

This demo is also available on an [IBM PC XT](../xt/) and an [IBM PC AT](../at/).

{% include_relative _overview.md hw="pc" %}
