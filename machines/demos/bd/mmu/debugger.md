---
layout: page
title: BASIC-DOS on an IBM PC AT with Extended Memory and Debugger
permalink: /machines/demos/bd/mmu/debugger/
redirect_from:
  - /demos/bd/mmu/debugger/
  - /demos/mmu/debugger/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-2mb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Extended Memory"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5170" %}
