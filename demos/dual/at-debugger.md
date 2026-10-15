---
layout: page
title: BASIC-DOS on an IBM PC AT with Dual Monitors and Debugger
permalink: /demos/dual/at/debugger/
machines:
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-dual-640kb.json
    debugger: true
    autoMount:
      A: "BASICDOS-360K-DUAL"
---

{% include machine.html id="ibm5170" %}
