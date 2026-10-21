---
layout: page
title: BASIC-DOS on an IBM PC with Debugger
permalink: /demos/s80/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb-fpu.json
    debugger: true
    autoMount:
      A: "BASIC-DOS 80-Column Demo"
      B: "PC DOS 1.00"
---

{% include machine.html id="ibm5150" %}
