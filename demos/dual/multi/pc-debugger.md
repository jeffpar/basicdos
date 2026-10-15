---
layout: page
title: BASIC-DOS on an IBM PC with Dueling Monitors and Debugger
permalink: /demos/dual/multi/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-dual-128kb.json
    debugger: true
    sizeRAM: 256
    autoMount:
      A: "BASICDOS-360K-MULTI"
---

{% include machine.html id="ibm5150" name="IBM PC, 256Kb RAM, Dual Floppy Drives, MDA and CGA" %}
