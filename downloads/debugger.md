---
layout: page
title: BASIC-DOS Release with Debugger
permalink: /downloads/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb-fpu.json
    debugger: true
    autoMount:
      A:
        path: /software/disks/2026/BASICDOS-360K.json
      B: "PC DOS 1.00"
---

{% include machine.html id="ibm5150" %}
