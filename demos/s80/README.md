---
layout: page
title: BASIC-DOS with a Single Session
permalink: /demos/s80/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb.json
    debugger: ../debugger
    autoMount:
      A: "BASICDOS-DISK1"
      B: "PC DOS 2.00 (Disk 1)"
---

The machine below boots the BASICDOS-DISK1 diskette, whose **CONFIG.SYS** doesn't define any consoles, so BASIC-DOS creates a single 80-column, 25-row session, running COMMAND.COM, which runs **AUTOEXEC.BAT** to display the BASIC-DOS version and a colorful greeting.  Type **HELP** for a list of commands, **DIR** to list the files on the diskette, and **PRIMES** to run PRIMES.BAS.

The machine is configured with 128K, and you can use the **MEM** command to display current memory usage (or **MEM -D** for details).  See the other [BASIC-DOS Demos](../) for configurations with multiple sessions.

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASICDOS-DISK1 Diskette

```
{% include_relative CONFIG.SYS %}
```
