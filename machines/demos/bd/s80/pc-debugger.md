---
layout: page
title: BASIC-DOS on an IBM PC with Debugger
permalink: /machines/demos/bd/s80/pc/debugger/
redirect_from:
  - /demos/bd/s80/pc/debugger/
  - /demos/s80/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb-fpu.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Single"
      B: "PC DOS 1.00"
---

{% include machine.html id="ibm5150" %}
