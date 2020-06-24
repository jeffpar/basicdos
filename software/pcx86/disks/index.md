---
layout: page
title: IBM PC XT with Color Display
permalink: /tasty/dev/
machines:
  - id: ibm-5160-cga
    type: pcx86
    config: /configs/pcx86/machine/ibm-5160-cga-640kb.json
    autoType: $date\r$time\r
    autoStart: true
    autoMount:
      A: "BD-BIN"
      B: "BD-SRC"
---

{% include machine.html id="ibm-5160-cga" %}
