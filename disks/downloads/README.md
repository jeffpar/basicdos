---
layout: page
title: BASIC-DOS Release Diskettes
permalink: /disks/downloads/
redirect_from:
  - /download/
  - /downloads/
machines:
  - id: ibm5150
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5150-cga-128kb-fpu.json
    debugger: available
    autoMount:
      A:
        path: /disks/current/BASICDOS-360K.json
      B: "PC DOS 1.00"
---

The BASIC-DOS release diskettes are bootable disks with everything you need to try BASIC-DOS:

- The root directory contains the system files (BASDEV.COM, BASDOS.COM, and COMMAND.COM) and **CONFIG.SYS**
- **EXT** contains the external BASIC-DOS utilities: **EXT\\CMD** has the assembly language programs (eg, HELP, VI, DEBUG.COM, and the [filters](/docs/bdman/cmd/external/#filters)) and HELP.TXT, and **EXT\\BAS** has the utilities written in BASIC (eg, ATTRIB, CHKDSK, COMP, DISKCOPY, FORMAT, LS, MODE, SYS, and TREE)
- **DEMOS** contains a few demo programs (eg, BROGUE.BAS, DIR.BAS, HELLO.BAT, PAINT.BAS, PRIMES.BAS), along with DONKEY.BAS, a BASIC game from the IBM PC DOS 1.00 diskette

Download it as one of these raw diskette images, which most PC emulators can boot, or which can be written to a physical diskette:

- [BASICDOS-360K](/disks/current/BASICDOS-360K.img), for a 5.25-inch 360K diskette
- [BASICDOS-1440K](/disks/current/BASICDOS-1440K.img), for a 3.5-inch 1.44M diskette

The machine below is an IBM PC (Model 5150) with a 4.77Mhz 8088 with an 8087, 128K of memory, a Color Display, and two diskette drives.  It boots the release diskette, whose startup menu offers the configurations that the machine's hardware supports (eg, two 40-column consoles on its Color Display), and after 5 seconds, starts a single 80-column console.  Type **HELP** for a list of commands, **DIR** to list the files on the diskette, **PRIMES** to run PRIMES.BAS, or **DONKEY** to run DONKEY.BAS.

{% include machine.html id="ibm5150" %}

### **CONFIG.SYS** from the BASIC-DOS Release Diskette

Its [startup menus](/docs/bdman/cfg/#startup-menus) offer most of the [Demos](/machines/demos/) configurations: on an 80286 or later, protected or real mode first, and then each configuration whose block's conditions the machine meets (eg, `[DUAL:MDA+CGA+256K]` only with both an MDA and a CGA, and at least 256K of memory).  On a machine without a video adapter, the menus are on a VT100 connected to COM1.

```
{% include_relative CONFIG.SYS %}
```

See the [BASIC-DOS Manual](/docs/bdman/) for more information, and the [Demos](/machines/demos/) for BASIC-DOS running in other configurations.
