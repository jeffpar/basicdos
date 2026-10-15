---
layout: page
title: BASIC-DOS on an IBM PC XT with Two 80-Column Sessions and Debugger
permalink: /demos/d80/xt/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: true
    autoMount:
      A: "BASICDOS-360K-D80"
      B: "PC DOS 2.00 (Disk 1)"
---

{% include machine.html id="ibm5160" %}
