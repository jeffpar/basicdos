---
layout: page
title: BASIC-DOS on an IBM PC with 64K, a Monochrome Display, and Debugger
permalink: /demos/m64/pc/debugger/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-mda-64kb.json
    debugger: true
    autoMount:
      A: "BASICDOS-360K-M64"
      B: "PC DOS 1.00"
---

{% include machine.html id="ibm5150" %}
