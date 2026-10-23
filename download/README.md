---
layout: page
title: BASIC-DOS Release
permalink: /download/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb-fpu.json
    debugger: available
    autoMount:
      A:
        path: /software/disks/BASICDOS-360K.json
      B: "PC DOS 1.00"
---

The BASIC-DOS release diskette is a bootable 360K diskette with everything you need to try BASIC-DOS:

- The root directory contains the system files (BASDEV.COM, BASDOS.COM, and COMMAND.COM), **CONFIG.SYS**, and **HELP.TXT**
- **EXT** contains the external BASIC-DOS utilities (eg, ATTRIB, CHKDSK, COMP, DISKCOPY, FORMAT, MODE, SYS, TREE, VI, and the [filters](/docs/bdman/cmd/external/#filters)) and DEBUG.COM
- **DEMOS** contains a few demo programs: DIR.BAS, FIBO.BAT, HELLO.BAT, PAINT.BAS, PIPES.BAT, and PRIMES.BAS
- **SAMPLES** contains the BASIC samples from the IBM PC DOS 1.00 diskette (eg, DONKEY.BAS)

Download it as [BASICDOS-360K](/software/disks/BASICDOS-360K.img), a raw 360K diskette image that most PC emulators can boot (and that can be written to a real 5.25-inch 360K diskette).  Every BASIC-DOS demo machine also lists it first in its diskette drive menus, as **{{ site.data.pcx86.basicdos-diskettes["/software/disks/BASICDOS-360K.json"] }}**.

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088 with an 8087, 128K of memory, a Color Display, and two diskette drives.  It boots the release diskette, which runs a single 80-column session.  Type **HELP** for a list of commands, **DIR** to list the files on the diskette, **PRIMES** to run PRIMES.BAS, or the name of a BASIC sample (eg, **DONKEY**).

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASIC-DOS Release Diskette

```
{% include_relative CONFIG.SYS %}
```

See the [BASIC-DOS Manual](/docs/bdman/) for more information, and the [Demos](/demos/) for BASIC-DOS running in other configurations.
