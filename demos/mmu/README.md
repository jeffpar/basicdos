---
layout: page
title: BASIC-DOS Protected Mode
permalink: /demos/mmu/
machines:
  - id: vt100
    type: vt100
    name: DEC VT100 Debugger Terminal
    config: /machines/dec/vt100/vt100.json
    layout: /_includes/machines/vt100/vt100-display.html
    compiled: true
    connection: serialPort->ibm5170.com2
  - id: ibm5170
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5170-cga-2mb.json
    debugger: true
    connection: com2->vt100.serialPort
    autoMount:
      A: "BASIC-DOS Protected Mode Demo"
      B: "BASIC-DOS Tests"
---

The machine below is an IBM PC AT (Model 5170) with a 6Mhz 80286, 2Mb of memory (640K of conventional memory and 1408K of extended memory), a Color Display, a 1.2Mb and a 1.44Mb diskette drive, a 10Mb hard disk, and a DEC VT100 on COM2 for BASIC-DOS's own debugger.  It boots the BASIC-DOS Protected Mode Demo diskette.

See [Protected-Mode Initialization](/docs/bdtech/mmu/#pminit) for more details.

{% include vt100-demo.html id="ibm5170" %}

### **CONFIG.SYS** from the BASIC-DOS Protected Mode Demo Diskette

```
{% include_relative CONFIG.SYS %}
```
