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

This IBM PC XT from [PCjs Machines](https://www.pcjs.org) serves as
both a BASIC-DOS build machine and test machine.  It's also been configured
to run several times faster than a normal 4.77Mhz IBM PC, in order to improve
build time -- there *are* limits to our desire to relive the original IBM PC
experience.

Since BASIC-DOS is designed for the IBM PC, it doesn't support hard disks,
but it does have the ability to *detect* a hard disk and boot from it if you
press **Esc**.  This allows a machine to always have a BASIC-DOS diskette in
drive A: without being forced to boot from it.

See the [Build Notes](#basic-dos-build-notes) below for more details.  The
Build Machine is also available with [Dual Monitors](dual/).

{% include machine.html id="ibm5160" %}

### BASIC-DOS Build Notes

The BASIC-DOS Build Machine contains two 10Mb hard disks:

  - Drive C: contains PC DOS 2.00 and all the tools used to build BASIC-DOS
  - Drive D: contains the BASIC-DOS source code

To build BASIC-DOS, press **Esc** when the machine boots.  The machine
will load PC DOS 2.00 from drive C:, switch to drive D:, and run **MK.BAT**.
The MK.BAT files use the Microsoft **MAKE** utility to do most of the work,
but the batch files are also responsible for copying the built binaries to the
BASIC-DOS diskette currently in drive A:.

If the batch files finish successfully, reboot the machine (press Ctrl-Alt-Del)
and then press **Enter** instead of **Esc** at the BASIC-DOS boot prompt.
You should now be running BASIC-DOS on the IBM PC XT, which BASIC-DOS treats as
an IBM PC.

NOTE: The boot prompt appears only if BASIC-DOS detects a hard disk *or* the
PCjs Debugger is present.

By default, the binaries contain *DEBUG* code (eg, assertions and debugging
aids).  To build non-debug binaries, type **MK FINAL**, or **MKCLEAN FINAL**
if switching between *DEBUG* and *FINAL* binaries.  The **MKCLEAN.BAT** batch
file simply deletes all the binaries before running **MK.BAT**.

### Developing with Visual Studio Code

[Visual Studio Code](https://code.visualstudio.com) has been the IDE of choice
for all BASIC-DOS development.  VS Code can't build the source code directly,
but it can start a web server running your own copy of the BASIC-DOS Build
Machine.  The BASIC-DOS [repository](https://github.com/jeffpar/basicdos)
includes a `.vscode` folder with a [tasks.json](https://github.com/jeffpar/basicdos/blob/master/.vscode/tasks.json)
that defines several tasks that should be configured to start when VS Code loads
the BASIC-DOS project.

The first task (`bundle serve`) starts up the Jekyll web server.  Make sure
you've successfully run both `npm install` and `bundle install` in your local
copy of the BASIC-DOS repository.  Once your server is installed and running,
verify you can access the BASIC-DOS Build Machine at `http://localhost:4040/build/`.

The second task (`gulp watch`) starts a file-watcher task that rebuilds
the BASIC-DOS source disk image whenever a BASIC-DOS source file has been changed
locally (eg, by the VS Code editor).

Note that this task also requires the PCjs
[DiskImage](https://github.com/jeffpar/pcjs/tree/master/tools#pcjs-diskimage-utility)
utility, so you should clone the [PCjs](https://github.com/jeffpar/pcjs)
repository, run the usual `npm install`, and then set the environment variable
`PCJS` to the fully-qualified name of the directory containing the clone.  Then
verify that `diskimage` works; eg:

    node $PCJS/tools/modules/diskimage.js

    DiskImage v2.04
    Copyright © 2012-2020 Jeff Parsons <Jeff@pcjs.org>

    nothing to do

Every time the BASIC-DOS `gulp watch` task builds a new disk image, the Jekyll
web server should automatically detect the change and rebuild the web site (on
macOS, that entire process takes only a few seconds).  When that's done,
refresh your web browser to reload the BASIC-DOS Build Machine, press **Esc**,
and let the **MK** command rebuild any BASIC-DOS binaries that are out-of-date.

If you then want to copy the binaries from the Build Machine back to your local
file system, click the machine's `Save HD1` button, be sure to tell your
browser you *really* want to download and keep `BDSRC.img`, and then use the
PCjs `diskimage` utility to extract files from the virtual hard disk;
eg:

    node $PCJS/tools/modules/diskimage.js BDSRC.img --extract --overwrite
    cp -pR BDSRC/* $BASICDOS/software/pcx86/bdsrc/

Be very careful when using commands like those shown above.  It's easy to lose
your work if it turns out the Build Machine's disk image was stale (eg, the
file watcher didn't actually run, or the web server didn't actually rebuild the
site with a new disk image, or you didn't actually refresh your web browser).

Whew, that's a lot of "actuallies."
