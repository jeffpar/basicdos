---
layout: page
title: BASIC-DOS with Dual Monitors (and Debugger)
permalink: /maplebar/dual/debugger/
machines:
  - id: ibm5160
    type: pcx86
    config: /configs/pcx86/machine/ibm-5160-dual-512kb-debugger.json
    autoType: $date\r$time\r
    autoStart: true
    autoMount:
      A: "BASIC-DOS4"
      B: "BDS-BOOT"
---

{% include machine.html id="ibm5160" %}
