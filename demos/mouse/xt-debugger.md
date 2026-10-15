---
layout: page
title: BASIC-DOS on an IBM PC XT with a Mouse and Debugger
permalink: /demos/mouse/xt/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb-mouse.json
    debugger: true
    autoMount:
      A: "BASICDOS-360K-S80"
    autoType: PAINT\r
---

{% include machine.html id="ibm5160" %}
