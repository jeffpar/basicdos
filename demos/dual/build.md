---
layout: page
title: BASIC-DOS Build Machine with Dual Monitors
permalink: /maplebar/dual/build/
machines:
  - id: ibm5160
    type: pcx86
    config: /configs/pcx86/machine/ibm-5160-dual-512kb-debugger.json
    autoType: $date\r$time\r\D:\rMK\r
    autoStart: true
    autoMount:
      A: "BASIC-DOS5"
---

The IBM PC XT below is similar to our original [Build Machine](../../build/),
for Dual Monitor development and testing.

For more information, see the [Build Notes](../../build/#basic-dos-build-notes).

{% include machine.html id="ibm5160" %}