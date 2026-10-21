---
layout: page
title: BASIC-DOS on an IBM PC with Two 40-Column Sessions and Debugger
permalink: /demos/d40/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    debugger: true
    autoMount:
      A: "BASIC-DOS 40-Column Demo"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5150" %}
