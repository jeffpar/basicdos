---
layout: page
title: BASIC-DOS on an IBM PC XT with Dual Monitors and Debugger
permalink: /demos/dual/xt/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-dual-640kb.json
    debugger: true
    autoMount:
      A: "BASICDOS-DISK4"
---

{% include machine.html id="ibm5160" %}
