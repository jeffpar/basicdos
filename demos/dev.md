---
layout: page
title: BASIC-DOS Development Machine
permalink: /maplebar/dev/
machines:
  - id: ibm5160
    type: pcx86
    config: /configs/pcx86/machine/ibm-5160-cga-512kb-debugger.json
    autoType: $date\r$time\r\D:\rMK\r
    autoStart: true
    messages: int
    autoMount:
      A: "BASIC-DOS2"
      B: "PC DOS 2.00 (Disk 1)"
---

The PC XT below serves as both a [development](#development-notes) and test
machine.  The diskette in drive A: loads the latest version of [BASIC-DOS](../),
which allows you to press **Esc** to boot from the hard disk and rebuild
BASIC-DOS.

{% include machine.html id="ibm5160" %}

### Development Notes

The BASIC-DOS development machine contains two 10Mb hard disks: drive C:
contains all the tools used to build BASIC-DOS, and drive D: contains all the
source code.

To build BASIC-DOS, switch to drive D: and type **MK**. The **MK.BAT** batch
files use the Microsoft **MAKE** utility to do most of the work, but the batch
files are also responsible for copying the resulting binaries to whatever
diskette is currently in drive A:.

By default, the binaries contain *DEBUG* code (eg, assertions and debugging
aids).  To build non-debug binaries, type **MK FINAL**, or **MKCLEAN FINAL**
if switching between *DEBUG* and *FINAL* binaries.  The **MKCLEAN.BAT** batch
file simply deletes all the binaries before running **MK.BAT**.

### **CONFIG.SYS** from the BASIC-DOS2 Diskette

```
{% include_relative d40/CONFIG.SYS %}
```
