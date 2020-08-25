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
    "BASIC-DOS1": [
        "./software/pcx86/src/dev/obj/IBMBIO.COM",
        "./software/pcx86/src/dos/obj/IBMDOS.COM",
        "./software/pcx86/src/cmd/obj/COMMAND.COM",
        "./software/pcx86/src/cfg/config1/CONFIG.SYS",
        "./software/pcx86/src/util/PRIMES.BAT",
        "./software/pcx86/src/util/obj/PRIMES.EXE",
        "./software/pcx86/src/util/obj/SLEEP.COM",
        "./software/pcx86/src/util/TESTS.BAT",
        "./software/pcx86/src/util/obj/TESTS.COM",
        "./software/pcx86/src/gwb/obj/GWB.EXE",
        "./software/pcx86/src/util/obj/SYMDEB.EXE"
    ],
    "BASIC-DOS2": [
        "./software/pcx86/src/dev/obj/IBMBIO.COM",
        "./software/pcx86/src/dos/obj/IBMDOS.COM",
        "./software/pcx86/src/cmd/obj/COMMAND.COM",
        "./software/pcx86/src/cfg/config2/CONFIG.SYS",
        "./software/pcx86/src/util/PRIMES.BAT",
        "./software/pcx86/src/util/obj/PRIMES.EXE",
        "./software/pcx86/src/util/obj/SLEEP.COM",
        "./software/pcx86/src/util/TESTS.BAT",
        "./software/pcx86/src/util/obj/TESTS.COM",
        "./software/pcx86/src/util/obj/SYMDEB.EXE"
    ],
    "BASIC-DOS3": [
        "./software/pcx86/src/dev/obj/IBMBIO.COM",
        "./software/pcx86/src/dos/obj/IBMDOS.COM",
        "./software/pcx86/src/cmd/obj/COMMAND.COM",
        "./software/pcx86/src/cfg/config3/CONFIG.SYS",
        "./software/pcx86/src/util/PRIMES.BAT",
        "./software/pcx86/src/util/obj/PRIMES.EXE",
        "./software/pcx86/src/util/obj/SLEEP.COM",
        "./software/pcx86/src/util/TESTS.BAT",
        "./software/pcx86/src/util/obj/TESTS.COM",
        "./software/pcx86/src/gwb/obj/GWB.EXE"
    ],
    "BASIC-DOS4": [
        "./software/pcx86/src/dev/obj/IBMBIO.COM",
        "./software/pcx86/src/dos/obj/IBMDOS.COM",
        "./software/pcx86/src/cmd/obj/COMMAND.COM",
        "./software/pcx86/src/cfg/config4/CONFIG.SYS",
        "./software/pcx86/src/util/PRIMES.BAT",
        "./software/pcx86/src/util/obj/PRIMES.EXE",
        "./software/pcx86/src/util/obj/SLEEP.COM",
        "./software/pcx86/src/util/TESTS.BAT",
        "./software/pcx86/src/util/obj/TESTS.COM",
        "./software/pcx86/src/gwb/obj/GWB.EXE",
        "./software/pcx86/src/util/obj/SYMDEB.EXE"
    ],
    "BASIC-DOS5": [
        "./software/pcx86/src/dev/obj/IBMBIO.COM",
        "./software/pcx86/src/dos/obj/IBMDOS.COM",
        "./software/pcx86/src/cmd/obj/COMMAND.COM",
        "./software/pcx86/src/cfg/config5/CONFIG.SYS",
        "./software/pcx86/src/util/PRIMES.BAT",
        "./software/pcx86/src/util/obj/PRIMES.EXE",
        "./software/pcx86/src/util/obj/SLEEP.COM",
        "./software/pcx86/src/util/TESTS.BAT",
        "./software/pcx86/src/util/obj/TESTS.COM",
        "./software/pcx86/src/gwb/obj/GWB.EXE",
        "./software/pcx86/src/util/obj/SYMDEB.EXE"
    ],
    "BDS-BOOT": [
        "./software/pcx86/src/boot/boot.asm",
        "./software/pcx86/src/boot/wboot.asm",
        "./software/pcx86/src/inc/8086.inc",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/devapi.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/dosapi.inc",
        "./software/pcx86/src/inc/macros.inc",
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
        "./software/pcx86/src/inc/8086.inc",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/devapi.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/dosapi.inc",
        "./software/pcx86/src/inc/macros.inc",
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
        "./software/pcx86/src/dos/memory.asm",
        "./software/pcx86/src/dos/misc.asm",
        "./software/pcx86/src/dos/process.asm",
        "./software/pcx86/src/dos/session.asm",
        "./software/pcx86/src/dos/sprintf.asm",
        "./software/pcx86/src/dos/sysinit.asm",
        "./software/pcx86/src/dos/utility.asm",
        "./software/pcx86/src/inc/8086.inc",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/devapi.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/dosapi.inc",
        "./software/pcx86/src/inc/macros.inc",
        "./software/pcx86/src/dos/mk.bat"
    ],
    "BDS-UTIL": [
        "./software/pcx86/src/util/cmd.inc",
        "./software/pcx86/src/util/cmd.asm",
        "./software/pcx86/src/util/eval.asm",
        "./software/pcx86/src/util/gen.asm",
        "./software/pcx86/src/util/mem.asm",
        "./software/pcx86/src/util/stdio.asm",
        "./software/pcx86/src/util/vars.asm",
        "./software/pcx86/src/util/const.asm",
        "./software/pcx86/src/util/primes.asm",
        "./software/pcx86/src/util/sleep.asm",
        "./software/pcx86/src/util/tests.asm",
        "./software/pcx86/src/inc/8086.inc",
        "./software/pcx86/src/inc/bios.inc",
        "./software/pcx86/src/inc/dev.inc",
        "./software/pcx86/src/inc/devapi.inc",
        "./software/pcx86/src/inc/disk.inc",
        "./software/pcx86/src/inc/dos.inc",
        "./software/pcx86/src/inc/dosapi.inc",
        "./software/pcx86/src/inc/macros.inc",
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
    let kbTarget = 160;
    if (disks[diskName].length == 1) {
        kbTarget = 10000;
        diskFiles = "--dir " + path.dirname(disks[diskName][0]);
        hddImage = " --output " + diskImage.replace(diskName, "archive/" + diskName).replace(".json",".hdd");
    } else {
        let dirPrev = "";
        for (let i = 0; i < disks[diskName].length; i++) {
            if (diskFiles) diskFiles += ",";
            let fileNext = disks[diskName][i];
            let dirNext = path.dirname(fileNext);
            if (dirNext == dirPrev) {
                fileNext = path.basename(fileNext);
            }
            diskFiles += fileNext;
            dirPrev = dirNext;
        }
        diskFiles = "--files " + diskFiles;
        if (diskName.startsWith("BDS-")) {
            kbTarget = 320;
        } else {
            diskFiles += " --boot ./software/pcx86/src/boot/obj/BOOT.COM";
        }
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
