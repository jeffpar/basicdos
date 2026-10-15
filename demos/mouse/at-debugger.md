---
layout: page
title: BASIC-DOS on an IBM PC AT with a Mouse and Debugger
permalink: /demos/mouse/at/debugger/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb-mouse.json
    debugger: true
    autoMount:
      A: "BASICDOS-360K-S80"
    autoType: PAINT\r
---

{% include machine.html id="ibm5170" %}
