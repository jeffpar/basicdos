---
layout: page
title: BASIC-DOS on an IBM PC XT with a Single Console and Debugger
permalink: /demos/s80/xt/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb-fpu.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Single"
      B: "PC DOS 1.00"
---

{% include machine.html id="ibm5160" %}
