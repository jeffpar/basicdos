---
layout: page
title: BASIC-DOS on an IBM PC XT Hard Disk with Debugger
permalink: /demos/hd/xt/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: true
    autoType: DATE $date\rTIME $time\r
---

{% include machine.html id="ibm5160" %}
