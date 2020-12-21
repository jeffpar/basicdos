---
layout: default
heading: BASIC-DOS Demos
permalink: /demos/
preview: /assets/images/maplebar.jpg
machines:
  - id: ibm5150
    type: pcx86
    config: /configs/pcx86/machine/ibm-5150-cga-64kb.json
    debugger: debugger
---

{% include machine.html id="ibm5150" %}

There are currently five BASIC-DOS demo configurations:

 1. [Single 25x80 session](?autoStart=true)
 2. [Two 40-column sessions](?autoMount={A:{name:"BASIC-DOS2"}})
 3. [Two 80-column sessions](?autoMount={A:{name:"BASIC-DOS3"}})
 4. [Dual monitors with single sessions](dual/)
 5. [Dual monitors with multiple sessions](dual/multi/)

The 40 and 80-column demos are configured with borders.  A double-wide border
indicates which session has keyboard focus.  Use **SHIFT-TAB** to toggle focus.

BASIC-DOS development was performed on this PC XT [Build Machine](../build/).
It's also available with [Dual Monitors](../build/dual/).

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
