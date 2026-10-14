---
layout: page
title: BASIC-DOS on a Hard Disk
permalink: /demos/hd/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-640kb.json
    debugger: available
---

The machine below is an IBM PC XT with 640K of memory and no diskettes loaded; instead, it boots BASIC-DOS from its 10Mb hard disk (drive C:) and runs one full-screen 80x25 session.

{% include machine.html id="ibm5160" %}

The hard disk has the system files, CONFIG.SYS and HELP.TXT in the root directory, along with these subdirectories:

- **BIN** contains the BASIC-DOS utilities (eg, FIND, MORE, and SORT)
- **SAMPLES** contains DONKEY.BAS and the other PC DOS BASIC samples
- **SRC** contains the BASIC-DOS source code (type `CD \SRC` and then `MK` to build it)
- **TESTS** contains HELLO.BAT, BENCH.BAS, PAINT.BAS, PRIMES.BAS, PRIMES.BAT, STRESS.BAT, and MSBASIC.EXE
- **TOOLS** contains MASM, LINK, MAKE, EXE2BIN, and the other build tools from the MS-DOS 3.20 hard disk used to build BASIC-DOS

CONFIG.SYS sets PATH$ to `C:\;C:\BIN;C:\SAMPLES;C:\TESTS;C:\TOOLS`, so programs in those directories can be run from anywhere.  The local session's SHELL line runs `HELLO.BAT` to display the BASIC-DOS version and a colorful greeting.

Try [BASIC-DOS with a Serial Display](../serial/) for a separate boot diskette that creates both local and serial sessions.

Any changes you make to the hard disk are lost when you leave the page, unless you first click **Save HD** to download the hard disk as an IMG file.

### **CONFIG.SYS** from the BASICDOS-HD Hard Disk

```
{% include_relative CONFIG.SYS %}
```

{% comment %}

Use the following page parameter to add MSDOS320-C400 as drive D:

    drives: '[{name:"BASICDOS-HD",type:3,path:"/software/disks/BASICDOS-HD.json"},{name:"MSDOS320-C400",type:3,path:"/software/disks/MSDOS320-C400.json"}]'

{% endcomment %}
