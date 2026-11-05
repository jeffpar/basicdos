---
layout: page
title: BASIC-DOS on an IBM PC AT with Multiple Video Pages in Protected Mode and Debugger
permalink: /demos/mmu/debugger/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-2mb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Protected Mode"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5170" %}
