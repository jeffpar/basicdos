/**
 * @fileoverview Gulp file for basicdos.com
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright © 2020-2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at <https://www.pcjs.org>.
 */

let fs = require("fs");
let path = require("path");
let gulp = require("gulp");
var glob = require("glob");
let run = require("gulp-run-command").default;

let files = {
    "HELP": [
        "./software/pcx86/src/os/cmd/HELP.TXT",
        "./software/pcx86/src/os/cmd/txt.inc"
    ]
};

let demoFiles = [
    "./software/pcx86/src/os/dev/obj/BASDEV.COM",
    "./software/pcx86/src/os/dos/obj/BASDOS.COM",
    "./software/pcx86/src/os/cmd/obj/COMMAND.COM",
    "./software/pcx86/src/os/cmd/HELP.TXT",
    "./software/pcx86/src/tests/primes/PRIMES.BA*",
    "./software/pcx86/src/tests/bin/*.EXE",
    "./software/pcx86/src/tests/bin/*.COM",
    "./software/pcx86/src/tests/misc/BD*.BAT",
    "./software/pcx86/src/tests/misc/*.EXE",
    "./software/pcx86/src/msb/obj/*.EXE"
];

let minFiles = [
    "./software/pcx86/src/os/dev/obj/BASDEV.COM",
    "./software/pcx86/src/os/dos/obj/BASDOS.COM",
    "./software/pcx86/src/os/cmd/obj/COMMAND.COM",
    "./software/pcx86/src/os/cmd/HELP.TXT",
    "./software/pcx86/src/msb/obj/*.EXE"
];

let disks = {
    "BASIC-DOS": [
        "./demos/s80/CONFIG.SYS",
        "./demos/s80/AUTOEXEC.BAT"
    ].concat(minFiles),
    "BASIC-DOS1": [
        "./demos/s80/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT"
    ].concat(demoFiles),
    "BASIC-DOS2": [
        "./demos/d40/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT"
    ].concat(demoFiles),
    "BASIC-DOS3": [
        "./demos/d80/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT",
    ].concat(demoFiles),
    "BASIC-DOS4": [
        "./demos/dual/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT",
    ].concat(demoFiles),
    "BASIC-DOS5": [
        "./demos/dual/multi/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT",
    ].concat(demoFiles),
    "BDS-BOOT": [
        "./software/pcx86/src/os/boot/*.asm",
        "./software/pcx86/src/os/inc/*.inc",
        "./software/pcx86/src/os/boot/makefile",
        "./software/pcx86/src/os/boot/mk.bat"
    ],
    "BDS-DEV": [
        "./software/pcx86/src/os/dev/*.asm",
        "./software/pcx86/src/os/inc/*.inc",
        "./software/pcx86/src/os/dev/makefile",
        "./software/pcx86/src/os/dev/mk.bat"
    ],
    "BDS-DOS": [
        "./software/pcx86/src/os/dos/*.asm",
        "./software/pcx86/src/os/dos/*.lrf",
        "./software/pcx86/src/os/inc/*.inc",
        "./software/pcx86/src/os/dos/makefile",
        "./software/pcx86/src/os/dos/mk.bat"
    ],
    "BDS-CMD": [
        "./software/pcx86/src/os/cmd/*.inc",
        "./software/pcx86/src/os/cmd/*.asm",
        "./software/pcx86/src/os/cmd/*.lrf",
        "./software/pcx86/src/os/inc/*.inc",
        "./software/pcx86/src/os/cmd/makefile",
        "./software/pcx86/src/os/cmd/mk.bat"
    ],
    "BDS-TEST": [
        "./software/pcx86/src/tests/lib/*",
        "./software/pcx86/src/tests/misc/*",
        "./software/pcx86/src/tests/primes/*",
        "./software/pcx86/src/tests/printf/*",
        "./software/pcx86/src/os/inc/*.inc",
        "./software/pcx86/src/tests/makefile",
        "./software/pcx86/src/tests/mk.bat"
    ],
    "BDSRC": [
        "./software/pcx86/src/**"
    ],
    "PCDOS200-C400": "./software/pcx86/disks/PCDOS200-C400.json"
};

let watchTasks = [];
for (let diskName in disks) {
    let buildTask = "BUILD-" + diskName;
    let diskImage = "./software/pcx86/disks/" + diskName + ".json";
    let archiveImage = "";
    let diskFiles = "";
    let kbTarget = 160;
    if (typeof disks[diskName] == "string") {
        kbTarget = 10000;
        diskFiles = "--disk " + disks[diskName];
        diskImage = diskImage.replace(diskName, "archive/" + diskName).replace(".json",".hdd");
    }
    else if (disks[diskName].length == 1) {
        kbTarget = 10000;
        diskFiles = "--dir " + path.dirname(disks[diskName][0]);
        archiveImage = " --normalize --output " + diskImage.replace(diskName, "archive/" + diskName).replace(".json",".hdd");
    } else {
        let dirPrev = "";
        for (let i = 0; i < disks[diskName].length; i++) {
            let fileNext = disks[diskName][i];
            if (fileNext.indexOf('*') >= 0) {
                let filesNext = glob.sync(fileNext);
                if (filesNext.length) {
                    disks[diskName].push(...filesNext);
                    continue;
                }
            }
            let dirNext = path.dirname(fileNext);
            if (dirNext == dirPrev) {
                fileNext = path.basename(fileNext);
            }
            if (diskFiles) diskFiles += ",";
            diskFiles += fileNext;
            dirPrev = dirNext;
        }
        diskFiles = "--files " + diskFiles;
        archiveImage = " --normalize --output " + diskImage.replace(diskName, "archive/" + diskName).replace(".json",".img") + " --writable";
        if (diskName.startsWith("BDS-")) {
            kbTarget = 360;
        } else {
            diskFiles += " --boot ./software/pcx86/src/os/boot/obj/BOOT1.COM";
        }
    }
    let cmd = "node \"${PCJS}/tools/diskimage/diskimage.js\" " + diskFiles + " --output " + diskImage + archiveImage + " --target=" + kbTarget + " --overwrite";
    cmd = cmd.replace(/\$\{([^}]+)\}/g, (_,n) => process.env[n]);
    gulp.task(buildTask, run(cmd));
    let watchTask = "WATCH-" + diskName;
    watchTasks.push(watchTask);
    gulp.task(watchTask, function() {
        return gulp.watch(disks[diskName], gulp.series(buildTask));
    });
}

for (let fileGroup in files) {
    let buildTask = "BUILD-" + fileGroup;
    let inputFile = files[fileGroup][0];
    let outputFile = files[fileGroup][1];
    gulp.task(buildTask, function(done) {
        let sINC = "";
        let sTXT = fs.readFileSync(inputFile, "utf8");
        let match, reCmds = new RegExp("([A-Z]+)[\\S\\s]*?\r\n(\r\n|$)", "g");
        while ((match = reCmds.exec(sTXT))) {
            /*
             * For each keyword found (eg, GOTO), generate the following:
             *
             *      TXT_GOTO_OFF    equ     0       ; offset of help for GOTO
             *      TXT_GOTO_LEN    equ     0       ; length of help for GOTO
             */
            sINC += "TXT_" + match[1] + "_OFF\tequ\t" + match.index + "\r\n";
            sINC += "TXT_" + match[1] + "_LEN\tequ\t" + match[0].length + "\r\n";
        }
        fs.writeFileSync(outputFile, sINC);
        done();
    });
    let watchTask = "WATCH-" + fileGroup;
    watchTasks.push(watchTask);
    gulp.task(watchTask, function() {
        return gulp.watch(inputFile, gulp.series(buildTask));
    });
}

gulp.task("watch", gulp.parallel(watchTasks));
