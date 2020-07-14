/**
 * @fileoverview Gulp file for basicdos.com
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright © 2012-2020 Jeff Parsons
 * @license MIT <https://www.basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at <https://www.pcjs.org>.
 */

let path = require("path");
let gulp = require("gulp");
let run = require("gulp-run-command").default;

let disks = {
    "BDS-BOOT": [
        "./software/pcx86/src/boot/boot.asm",
        "./software/pcx86/src/boot/wboot.asm",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/macros.inc",
        "./software/pcx86/src/boot/makefile",
        "./software/pcx86/src/boot/mk.bat"
    ],
    "BDS-DEV": [
        "./software/pcx86/src/dev/auxdev.asm",
        "./software/pcx86/src/dev/clkdev.asm",
        "./software/pcx86/src/dev/comdev.asm",
        "./software/pcx86/src/dev/condev.asm",
        "./software/pcx86/src/dev/devinit.asm",
        "./software/pcx86/src/dev/fdcdev.asm",
        "./software/pcx86/src/dev/lptdev.asm",
        "./software/pcx86/src/dev/nuldev.asm",
        "./software/pcx86/src/dev/prndev.asm",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/macros.inc",
        "./software/pcx86/src/dev/makefile",
        "./software/pcx86/src/dev/mk.bat"
    ],
    "BDS-DOS": [
        "./software/pcx86/src/dos/conio.asm",
        "./software/pcx86/src/dos/device.asm",
        "./software/pcx86/src/dos/disk.asm",
        "./software/pcx86/src/dos/dosdata.asm",
        "./software/pcx86/src/dos/dosints.asm",
        "./software/pcx86/src/dos/fcbio.asm",
        "./software/pcx86/src/dos/handle.asm",
        "./software/pcx86/src/dos/ibmdos.lrf",
        "./software/pcx86/src/dos/memory.asm",
        "./software/pcx86/src/dos/misc.asm",
        "./software/pcx86/src/dos/process.asm",
        "./software/pcx86/src/dos/session.asm",
        "./software/pcx86/src/dos/sprintf.asm",
        "./software/pcx86/src/dos/sysinit.asm",
        "./software/pcx86/src/dos/utility.asm",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/macros.inc",
        "./software/pcx86/src/dos/makefile",
        "./software/pcx86/src/dos/mk.bat"
    ],
    "BDS-UTIL": [
        "./software/pcx86/src/util/cmd.inc",
        "./software/pcx86/src/util/command.asm",
        "./software/pcx86/src/util/exec.asm",
        "./software/pcx86/src/util/primes.asm",
        "./software/pcx86/src/util/sleep.asm",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/macros.inc",
        "./software/pcx86/src/util/makefile",
        "./software/pcx86/src/util/mk.bat"
    ],
    "BDS-SRC": [
        "./software/pcx86/src/**"
    ]
};

let watchTasks = [];
for (let diskName in disks) {
    let buildTask = "BUILD-" + diskName;
    let diskImage = "./software/pcx86/disks/" + diskName + ".json";
    let hddImage = "";
    let diskFiles = "";
    let kbTarget = 320;
    if (disks[diskName].length == 1) {
        kbTarget = 10000;
        diskFiles = "--dir " + path.dirname(disks[diskName][0]);
        hddImage = " --output " + diskImage.replace(diskName, "archive/" + diskName).replace(".json",".hdd");
    } else {
        for (let i = 0; i < disks[diskName].length; i++) {
            if (diskFiles) diskFiles += ",";
            diskFiles += disks[diskName][i];
        }
        diskFiles = "--files " + diskFiles;
    }
    let cmd = "node ${PCJS}/tools/modules/diskimage.js " + diskFiles + " --output " + diskImage + hddImage + " --target=" + kbTarget + " --overwrite";
    cmd = cmd.replace(/\$\{([^}]+)\}/g, (_,n) => process.env[n]);
    gulp.task(buildTask, run(cmd));
    let watchTask = "WATCH-" + diskName;
    watchTasks.push(watchTask);
    gulp.task(watchTask, function() {
        return gulp.watch(disks[diskName], gulp.series(buildTask));
    });
}

gulp.task("watch", gulp.parallel(watchTasks));
