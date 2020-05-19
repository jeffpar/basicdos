---
layout: page
title: IBM PC XT with Color Display
permalink: /tasty/dev/
machines:
  - id: ibm-5160-cga
    type: pcx86
    config: /configs/pcx86/machine/ibm-5160-cga-256kb.json
    drives: '[{name:"10Mb Hard Disk",type:3,path:"/software/pcx86/disks/PCDOS200-C400.img"}]'
    autoMount:
      A: None
    autoType: $date\r$time\r
    autoStart: true
---

{% include machine.html id="ibm-5160-cga" %}
