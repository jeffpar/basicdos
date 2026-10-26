---
layout: page
title: BASIC-DOS on an IBM PC with a Mouse and Debugger
permalink: /demos/mouse/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-ega-256kb-mouse.json
    debugger: true
    autoMount:
      A: "BASIC-DOS 80-Column Demo"
    autoType: PAINT\r
---

{% include machine.html id="ibm5150" %}
