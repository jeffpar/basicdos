---
layout: page
title: BASIC-DOS on an IBM PC AT with a Single Session and Debugger
permalink: /demos/s80/at/debugger/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb-fpu.json
    debugger: true
    autoMount:
      A: "BASIC-DOS 80-Column Demo"
      B: "PC DOS 1.00"
---

{% include machine.html id="ibm5170" %}
