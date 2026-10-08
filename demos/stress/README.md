---
layout: page
title: BASIC-DOS Multitasking Stress Tests
permalink: /demos/stress/
machines:
  - id: ibm5160
    type: pcx86
    config: /machines/pcx86/ibm/ibm-5160-cga-128kb-stress.json
    debugger: available
---

The machine below is an IBM PC XT with no diskettes loaded; it boots BASIC-DOS from its 10Mb hard disk (drive C:) and runs two 40-column sessions side by side, each running the same batch file, STRESS.BAT, at the same time.

Each pass of STRESS.BAT creates a series of folders nested 8 deep, with four small files in each folder whose names get longer as it goes (all of them named with string variables), and then deletes the files and folders again, unwinding back to the root directory, and then runs PRIMES.BAS before starting the next pass.  Each session uses its own folder names (eg, `S1L1` through `S1L8` in the left session, and `S2L1` through `S2L8` in the right), so the two sessions are constantly creating and deleting directory entries, clusters, and FAT entries on the same disk at the same time.

If any command fails (eg, a file can't be created or a folder can't be removed), the batch file stops with an error message, so a session that keeps counting passes is a session that hasn't found a problem.  To examine the disk at any point, click **Save HD** to download its current image (as a raw `.img` file), which you can check with a tool like MS-DOS CHKDSK.

{% include machine.html id="ibm5160" %}

### **CONFIG.SYS** from the BASICDOS-STRESS Hard Disk

```
{% include_relative CONFIG.SYS %}
```

### **STRESS.BAT** from the BASICDOS-STRESS Hard Disk

```
{% include_relative STRESS.BAT %}
```
