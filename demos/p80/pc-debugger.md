---
layout: page
title: BASIC-DOS on an IBM PC with Multiple Video Pages and Debugger
permalink: /demos/p80/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Multi-Page Demo"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5150" %}
