---
layout: page
title: BASIC-DOS Release with Debugger
permalink: /download/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb-fpu.json
    debugger: true
    autoMount:
      A:
        path: /software/disks/BASICDOS-360K.json
      B: "PC DOS 1.00"
---

{% include machine.html id="ibm5150" %}
