---
layout: page
title: Build Machine
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

### Developing with Visual Studio Code

[Visual Studio Code](https://code.visualstudio.com) has been the IDE of choice
for all BASIC-DOS development.  VS Code can't build the source code directly,
but it makes it easy to start a web server running your own copy of the BASIC-DOS
Build Machine.

You'll find that the BASIC-DOS [repository](https://github.com/jeffpar/basicdos)
includes a `.vscode` folder with a [tasks.json](https://github.com/jeffpar/basicdos/blob/master/.vscode/tasks.json)
that defines several tasks that should be configured to start when VS Code loads
the BASIC-DOS project.

The first task (`bundle: serve`) starts up the Jekyll web server.  Make sure
you've successfully run both `npm install` and `bundle install` in your local
copy of the BASIC-DOS repository.  Once your server is installed and running,
verify you can access the BASIC-DOS Build Machine at `http://localhost:4040/build/`.

The second task (`gulp: watch`) starts several file-watcher tasks that rebuild
the BASIC-DOS source disk image whenever a BASIC-DOS source file has been changed
locally (eg, by the VS Code editor).

Note that this task also requires the PCjs
[DiskImage](https://github.com/jeffpar/pcjs/tree/master/tools#pcjs-diskimage-utility)
utility, so you should clone the [PCjs](https://github.com/jeffpar/pcjs)
repository and set the environment variable `PCJS` to the fully-qualified name
of the directory containing that clone.  Verify that `diskimage` works; eg:

    node $PCJS/tools/modules/diskimage.js

    DiskImage v2.04
    Copyright © 2012-2020 Jeff Parsons <Jeff@pcjs.org>

    nothing to do

Every time the Gulp task builds a new disk image, the Jekyll web server should
automatically detect the change and rebuild the web site (on macOS, that entire
process takes only a few seconds).  When that's done, refresh your web browser
to reload the BASIC-DOS Build Machine, press **Esc**, and let the **MK** command
rebuild any BASIC-DOS binaries that are out-of-date.

If you want to copy the binaries from the Build Machine back to your local
machine, click the Build Machine's `Save HD1` button, be sure to tell your
browser you *really* want to download and keep `BDSRC.img`, and then use the
PCjs `diskimage` utility to extract files from the virtual hard disk;
eg:

    node $PCJS/tools/modules/diskimage.js BDSRC.img --extract --overwrite
    cp -pR BDSRC/* $BASICDOS/software/pcx86/bdsrc/

Be very careful when using commands like those shown above.  It's easy to lose
your work if it turns out the Build Machine's disk image was stale (eg, the
file-watcher didn't actually run, or the web server didn't rebuild the site, or
the web browser wasn't refreshed).
