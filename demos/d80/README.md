---
layout: page
title: BASIC-DOS with Two 80-Column Sessions
permalink: /demos/d80/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoMount:
      A: "BASICDOS-DISK3"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below boots the BASICDOS-DISK3 diskette, whose **CONFIG.SYS** defines two 80-column consoles, one above the other (16 rows on top and 9 rows on the bottom), each running its own copy of COMMAND.COM.

Both sessions are configured with borders, and a double-wide border indicates which session has keyboard focus.  Use **SHIFT-TAB** to toggle focus.

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASICDOS-DISK3 Diskette

```
{% include_relative CONFIG.SYS %}
```
