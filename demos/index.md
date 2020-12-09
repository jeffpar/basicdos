---
layout: page
title: BASIC-DOS Demo
permalink: /maplebar/demos/
machines:
  - id: ibm5150
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    debugger: available
---

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASIC-DOS1 Diskette

```
{% include_relative s80/CONFIG.SYS %}
```

### **CONFIG.SYS** from the BASIC-DOS2 Diskette

```
{% include_relative d40/CONFIG.SYS %}
```

### **CONFIG.SYS** from the BASIC-DOS3 Diskette

```
{% include_relative d80/CONFIG.SYS %}
```
