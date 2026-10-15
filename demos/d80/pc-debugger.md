---
layout: page
title: BASIC-DOS on an IBM PC with Two 80-Column Sessions and Debugger
permalink: /demos/d80/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    debugger: true
    autoMount:
      A: "BASICDOS-360K-D80"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5150" %}
