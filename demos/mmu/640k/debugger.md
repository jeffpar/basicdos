---
layout: page
title: BASIC-DOS on an IBM PC AT in Protected Mode with 640K and Debugger
permalink: /demos/mmu/640k/debugger/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Protected Mode"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5170" %}
