---
layout: page
title: BASIC-DOS with Two 40-Column Sessions
permalink: /demos/d40/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    autoMount:
      A: "BASICDOS-DISK2"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below boots the BASICDOS-DISK2 diskette, whose **CONFIG.SYS** defines two 40-column consoles side by side, each running its own copy of COMMAND.COM.  The left session runs BD4.BAT, a batch file that lists the diskette's directory over and over (press **CTRL-C** to stop it), while the right session waits for your commands.

Both sessions are configured with borders, and a double-wide border indicates which session has keyboard focus.  Use **SHIFT-TAB** to toggle focus.

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASICDOS-DISK2 Diskette

```
{% include_relative CONFIG.SYS %}
```
