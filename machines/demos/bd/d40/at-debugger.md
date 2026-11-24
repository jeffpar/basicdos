---
layout: page
title: BASIC-DOS on an IBM PC AT with Two 40-Column Consoles and Debugger
permalink: /machines/demos/bd/d40/at/debugger/
redirect_from:
  - /demos/bd/d40/at/debugger/
  - /demos/d40/at/debugger/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-640kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS 40-Cols"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5170" %}
