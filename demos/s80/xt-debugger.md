---
layout: page
title: BASIC-DOS on an IBM PC XT with a Single Session and Debugger
permalink: /demos/s80/xt/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb-fpu.json
    debugger: true
    autoMount:
      A: "BASIC-DOS 80-Column Demo"
      B: "PC DOS 1.00"
    autoType: DATE $date\rTIME $time\r
---

{% include machine.html id="ibm5160" %}
