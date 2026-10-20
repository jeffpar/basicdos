---
layout: page
title: BASIC-DOS on an IBM PC with Three Full-Screen Sessions and Debugger
permalink: /demos/p80/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    debugger: true
    autoMount:
      A: "BASICDOS-360K-P80"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5150" %}
