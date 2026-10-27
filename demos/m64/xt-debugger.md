---
layout: page
title: BASIC-DOS on an IBM PC XT with 640K, a Monochrome Display, and Debugger
permalink: /demos/m64/xt/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-mda-640kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS 640K Monochrome Demo"
      B: "PC DOS 1.00"
    autoType: DATE $date\rTIME $time\r
---

{% include machine.html id="ibm5160" %}
