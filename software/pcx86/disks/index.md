---
layout: page
title: IBM PC XT with Color Display
permalink: /tasty/dev/
machines:
  - id: ibm-5160-cga
    type: pcx86
    config: /configs/pcx86/machine/ibm-5160-cga-512kb.json
    autoType: $date\r$time\r
    autoStart: true
    autoMount:
      A: "BASIC-DOS"
      B: "BDS-BOOT"
---

{% include machine.html id="ibm-5160-cga" %}
