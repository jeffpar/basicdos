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
        "./software/pcx86/src/inc/macros.inc"
    ],
    "BDS-DEV": [
        "./software/pcx86/src/dev/auxdev.asm",
        "./software/pcx86/src/dev/clkdev.asm",
        "./software/pcx86/src/dev/comdev.asm",
        "./software/pcx86/src/dev/condev.asm",
        "./software/pcx86/src/dev/devinit.asm",
        "./software/pcx86/src/dev/fdcdev.asm",
        "./software/pcx86/src/dev/ibmbio.lrf",
        "./software/pcx86/src/dev/lptdev.asm",
        "./software/pcx86/src/dev/nuldev.asm",
        "./software/pcx86/src/dev/prndev.asm",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/macros.inc"
    ],
    "BDS-DOS": [
        "./software/pcx86/src/dos/conio.asm",
        "./software/pcx86/src/dos/device.asm",
        "./software/pcx86/src/dos/disk.asm",
        "./software/pcx86/src/dos/dosdata.asm",
        "./software/pcx86/src/dos/dosints.asm",
        "./software/pcx86/src/dos/handle.asm",
        "./software/pcx86/src/dos/ibmdos.lrf",
        "./software/pcx86/src/dos/memory.asm",
        "./software/pcx86/src/dos/process.asm",
        "./software/pcx86/src/dos/session.asm",
        "./software/pcx86/src/dos/sysinit.asm",
        "./software/pcx86/src/dos/utility.asm",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/macros.inc"
    ],
    "BDS-UTIL": [
        "./software/pcx86/src/util/cmd.inc",
        "./software/pcx86/src/util/command.asm",
        "./software/pcx86/src/util/primes.asm",
        "./software/pcx86/src/util/tests.asm",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/macros.inc"
    ]
};

let watchTasks = [];
for (let diskName in disks) {
    let files = [];
    let buildTask = "BUILD-" + diskName;
    let diskImage = "./software/pcx86/disks/" + diskName + ".json";
    disks[diskName].forEach((file) => files.push(file));
    let diskFiles = "";
    for (let i = 0; i < files.length; i++) {
        if (diskFiles) diskFiles += ",";
        diskFiles += files[i];
    }
    gulp.task(buildTask, run("node /Users/jeff/Sites/pcjs/tools/modules/diskimage.js --files " + diskFiles + " --output " + diskImage + " --target=360 --overwrite"));
    let watchTask = "WATCH-" + diskName;
    watchTasks.push(watchTask);
    gulp.task(watchTask, function() {
        return gulp.watch(files, gulp.series(buildTask));
    });
}

gulp.task("default", gulp.parallel(watchTasks));
