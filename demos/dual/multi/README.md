---
layout: page
title: BASIC-DOS with "Dueling Monitors"
permalink: /demos/dual/multi/
machines:
  - id: ibm5150
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-dual-256kb.json
    debugger: debugger/
    autoMount:
      A: "BASIC-DOS5"
---

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASIC-DOS5 Diskette

```
{% include_relative CONFIG.SYS %}
```
