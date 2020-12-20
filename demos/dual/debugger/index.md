---
layout: page
title: BASIC-DOS with Dual Monitors and Debugger
permalink: /demos/dual/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-dual-256kb-debugger.json
    autoMount:
      A: "BASIC-DOS4"
      B: "PC DOS 2.00 (Disk 2)"
---

{% include machine.html id="ibm5150" %}
