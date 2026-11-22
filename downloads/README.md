---
layout: page
title: BASIC-DOS Release
permalink: /downloads/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb-fpu.json
    debugger: available
    autoMount:
      A:
        path: /software/disks/2026/BASICDOS-360K.json
      B: "PC DOS 1.00"
---

The BASIC-DOS release diskette is a bootable 360K diskette with everything you need to try BASIC-DOS:

- The root directory contains the system files (BASDEV.COM, BASDOS.COM, and COMMAND.COM) and **CONFIG.SYS**
- **EXT** contains the external BASIC-DOS utilities: **EXT\\CMD** has the assembly language programs (eg, HELP, VI, DEBUG.COM, and the [filters](/docs/bdman/cmd/external/#filters)) and HELP.TXT, and **EXT\\BAS** has the utilities written in BASIC (eg, ATTRIB, CHKDSK, COMP, DISKCOPY, FORMAT, LS, MODE, SYS, and TREE)
- **DEMOS** contains a few demo programs (eg, BROGUE.BAS, DIR.BAS, HELLO.BAT, PAINT.BAS, PRIMES.BAS), along with DONKEY.BAS, a BASIC game from the IBM PC DOS 1.00 diskette

Download it as [BASICDOS-360K](/software/disks/2026/BASICDOS-360K.img), a raw 360K diskette image that most PC emulators can boot (and that can be written to a real 5.25-inch 360K diskette).  Every BASIC-DOS demo machine also lists it first in its diskette drive menus, as **{{ site.data.pcx86.basicdos-diskettes["/software/disks/2026/BASICDOS-360K.json"] }}**.

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088 with an 8087, 128K of memory, a Color Display, and two diskette drives.  It boots the release diskette, which runs a single 80-column session.  Type **HELP** for a list of commands, **DIR** to list the files on the diskette, **PRIMES** to run PRIMES.BAS, or **DONKEY** to run DONKEY.BAS.

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASIC-DOS Release Diskette

```
{% include_relative CONFIG.SYS %}
```

See the [BASIC-DOS Manual](/docs/bdman/) for more information, and the [Demos](/demos/) for BASIC-DOS running in other configurations.
