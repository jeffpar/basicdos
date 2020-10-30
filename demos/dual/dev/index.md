---
layout: page
title: BASIC-DOS Development Machine with Dual Monitors
permalink: /maplebar/dual/dev/
machines:
  - id: ibm5160
    type: pcx86
    config: /configs/pcx86/machine/ibm-5160-dual-512kb-debugger.json
    autoType: $date\r$time\r\D:\rMK\r
    autoStart: true
    autoMount:
      A: "BASIC-DOS5"
      B: "BDS-BOOT"
---

The PC XT below is similar to our original PC XT
[Development Machine](/maplebar/dev/), but with dual monitors,
making it ideal for both dual monitor development *and* testing.

{% include machine.html id="ibm5160" %}
