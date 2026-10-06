---
layout: page
title: BASIC-DOS with Dual Monitors
permalink: /demos/dual/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-dual-128kb.json
    debugger: available
    autoMount:
      A: "BASIC-DOS4"
      B: "PC DOS 2.00 (Disk 2)"
---

The machine below is configured with both MDA and CGA adapters, each connected to its own monitor, and BASIC-DOS has been configured for two sessions, with each session assigned to its own monitor.  At first glance, it might appear there are two machines running, but it really is just a single IBM PC running two BASIC-DOS sessions.

{% include machine.html id="ibm5150" %}

Like all the other [BASIC-DOS Demos](../), use **SHIFT-TAB** to toggle keyboard focus between sessions.  Since these sessions don't use borders, the presence of a blinking cursor indicates which session has focus.

The machine is configured for 128K, and you can use the **MEM** command to display current memory usage and **MEM /D** for detailed memory usage.

A **MEMSIZE** line in **CONFIG.SYS** (eg, **MEMSIZE=128**) can limit the total memory used by BASIC-DOS.  You might be tempted to think that **MEMSIZE** is a way to "partition" memory, so that each session has a dedicated amount, but no -- **MEMSIZE** is simply a means of testing BASIC-DOS with different memory sizes.  And in any case, partitioning memory would not be a good strategy.

### **CONFIG.SYS** from the BASIC-DOS4 Diskette

```
{% include_relative CONFIG.SYS %}
```
