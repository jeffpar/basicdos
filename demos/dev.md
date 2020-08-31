---
layout: page
title: BASIC-DOS Development Machine
permalink: /maplebar/dev/
machines:
  - id: ibm5160
    type: pcx86
    config: /configs/pcx86/machine/ibm-5160-cga-512kb-debugger.json
    autoType: $date\r$time\r
    autoStart: true
    messages: int
    autoMount:
      A: "BASIC-DOS2"
      B: "PC DOS 2.00 (Disk 1)"
---

The PC XT below serves as both a development and test machine.  The diskette
in drive A: will boot a recent version of BASIC-DOS, unless you press **Esc**
to boot from drive C:.  Even though hard disks didn't exist when BASIC-DOS
was "created," we knew that IBM PCs would eventually have them, so if the boot
sector detects a hard disk, it will prompt you; otherwise, it will boot straight
into BASIC-DOS.  All the other [BASIC-DOS Demos](../) run on floppy-based IBM
PCs, so no prompt will appear.

This machine contains two 10Mb hard disks: drive C: contains all the tools
used to build BASIC-DOS, and drive D: contains all the source code.
To build BASIC-DOS, switch to drive D: and type **MK**. The **MK.BAT** batch
files use the Microsoft **MAKE** utility to do most of the work, but the batch
files are also responsible for copying the resulting binaries to whatever
diskette is currently in drive A:.

By default, the binaries contain *DEBUG* code (eg, assertions and debugging
aids).  To build non-debug binaries, type **MK NODEBUG**, or **MKCLEAN NODEBUG**
if switching between *DEBUG* and *NODEBUG* binaries.  The **MKCLEAN.BAT** batch
file simply deletes all the binaries before running **MK.BAT**.

{% include machine.html id="ibm5160" %}

### **CONFIG.SYS** from the BASIC-DOS2 Diskette

```
{% include_relative d40/CONFIG.SYS %}
```
