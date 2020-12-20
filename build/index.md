---
layout: page
title: BASIC-DOS Build Machine
permalink: /build/
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

The IBM PC XT below serves as both a BASIC-DOS Build Machine.
It's also available with [Dual Monitors](dual/).

BASIC-DOS doesn't support hard disks, but the BASIC-DOS diskette in drive A:
will detect the hard disk and allow you to boot from it if you press **Esc**.
See the [Build Notes](#basic-dos-build-notes) below.  

{% include machine.html id="ibm5160" %}

### BASIC-DOS Build Notes

The BASIC-DOS build machine contains two 10Mb hard disks:

  - Drive C: contains PC DOS 2.00 and all the tools used to build BASIC-DOS
  - Drive D: contains the BASIC-DOS source code

To build BASIC-DOS, press **Esc** when the machine boots.  The machine
will load PC DOS 2.00 from drive C:, switch to drive D:, and run **MK.BAT**.
The MK.BAT files use the Microsoft **MAKE** utility to do most of the work,
but the batch files are also responsible for copying the built binaries to the
BASIC-DOS diskette currently in drive A:.

If the batch files finish successfully, reboot the machine (press Ctrl-Alt-Del)
and then press **Enter** instead of **Esc** at the BASIC-DOS boot prompt; the
boot prompt only appears if BASIC-DOS detects a hard disk (or the PCjs Debugger
is present).

By default, the binaries contain *DEBUG* code (eg, assertions and debugging
aids).  To build non-debug binaries, type **MK FINAL**, or **MKCLEAN FINAL**
if switching between *DEBUG* and *FINAL* binaries.  The **MKCLEAN.BAT** batch
file simply deletes all the binaries before running **MK.BAT**.
