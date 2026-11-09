---
layout: page
title: BASIC-DOS on an IBM PC with Multiple Video Pages and Debugger
permalink: /demos/p80/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-mda-64kb.json
    debugger: true
    sizeRAM: 128
    autoMount:
      A: "BASIC-DOS Multi-Page Demo"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5150" name="IBM PC, 128Kb RAM, Dual Floppy Drives, MDA, No Ports" %}
