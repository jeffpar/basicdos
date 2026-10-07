---
layout: page
title: BASIC-DOS with "Dueling Monitors"
permalink: /demos/dual/multi/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-dual-256kb.json
    debugger: available
    autoMount:
      A: "BASICDOS-DISK5"
---

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASICDOS-DISK5 Diskette

```
{% include_relative CONFIG.SYS %}
```
