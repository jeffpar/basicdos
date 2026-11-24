---
layout: page
title: BASIC-DOS on an IBM PC AT with Multiple Video Pages and Debugger
permalink: /machines/demos/bd/p80/at/debugger/
redirect_from:
  - /demos/bd/p80/at/debugger/
  - /demos/p80/at/debugger/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS Multi-Page"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5170" %}
