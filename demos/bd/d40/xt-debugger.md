---
layout: page
title: BASIC-DOS on an IBM PC XT with Two 40-Column Consoles and Debugger
permalink: /demos/bd/d40/xt/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS 40-Cols"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5160" %}
