---
layout: page
heading: BASIC-DOS Demos
permalink: /demos/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    debugger: available
---

There are currently seven BASIC-DOS demo configurations:

 1. [Single 25x80 session](?autoStart=true)
 2. [Two 40-column sessions](?autoMount={A:{name:"BASICDOS-DISK2"}})
 3. [Two 80-column sessions](?autoMount={A:{name:"BASICDOS-DISK3"}})
 4. [Dual monitors with single sessions](dual/)
 5. [Dual monitors with multiple sessions](dual/multi/)
 6. [BASIC-DOS running DONKEY.BAS](basic/)
 7. [BASIC-DOS on a Hard Disk](hd/)

The 40 and 80-column demos are configured with borders.  A double-wide border indicates which session has keyboard focus.  Use **SHIFT-TAB** to toggle focus.

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASICDOS-DISK1 Diskette

```
{% include_relative s80/CONFIG.SYS %}
```

### **CONFIG.SYS** from the BASICDOS-DISK2 Diskette

```
{% include_relative d40/CONFIG.SYS %}
```

### **CONFIG.SYS** from the BASICDOS-DISK3 Diskette

```
{% include_relative d80/CONFIG.SYS %}
```
