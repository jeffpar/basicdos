/**
 * @fileoverview Gulp file for basicdos.com
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright © 2020-2021 Jeff Parsons
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
        "./software/pcx86/bdsrc/cmd/HELP.TXT",
        "./software/pcx86/bdsrc/cmd/txt.inc"
    ]
};

let demoFiles = [
    "./software/pcx86/bdsrc/dev/obj/IBMBIO.COM",
    "./software/pcx86/bdsrc/dos/obj/IBMDOS.COM",
    "./software/pcx86/bdsrc/cmd/obj/COMMAND.COM",
    "./software/pcx86/bdsrc/cmd/HELP.TXT",
    "./software/pcx86/bdsrc/test/PRIMES.BA*",
    "./software/pcx86/bdsrc/test/obj/*.EXE",
    "./software/pcx86/bdsrc/test/obj/*.COM",
    "./software/pcx86/bdsrc/test/BD*.BAT",
    "./software/pcx86/bdsrc/test/bin/*.EXE",
    "./software/pcx86/bdsrc/msb/obj/*.EXE"
];

let minFiles = [
    "./software/pcx86/bdsrc/dev/obj/IBMBIO.COM",
    "./software/pcx86/bdsrc/dos/obj/IBMDOS.COM",
    "./software/pcx86/bdsrc/cmd/obj/COMMAND.COM",
    "./software/pcx86/bdsrc/cmd/HELP.TXT",
    "./software/pcx86/bdsrc/msb/obj/*.EXE"
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
        "./software/pcx86/bdsrc/boot/*.asm",
        "./software/pcx86/bdsrc/inc/*.inc",
        "./software/pcx86/bdsrc/boot/makefile",
        "./software/pcx86/bdsrc/boot/mk.bat"
    ],
    "BDS-DEV": [
        "./software/pcx86/bdsrc/dev/*.asm",
        "./software/pcx86/bdsrc/inc/*.inc",
        "./software/pcx86/bdsrc/dev/makefile",
        "./software/pcx86/bdsrc/dev/mk.bat"
    ],
    "BDS-DOS": [
        "./software/pcx86/bdsrc/dos/*.asm",
        "./software/pcx86/bdsrc/dos/*.lrf",
        "./software/pcx86/bdsrc/inc/*.inc",
        "./software/pcx86/bdsrc/dos/makefile",
        "./software/pcx86/bdsrc/dos/mk.bat"
    ],
    "BDS-CMD": [
        "./software/pcx86/bdsrc/cmd/*.inc",
        "./software/pcx86/bdsrc/cmd/*.asm",
        "./software/pcx86/bdsrc/cmd/*.lrf",
        "./software/pcx86/bdsrc/inc/*.inc",
        "./software/pcx86/bdsrc/cmd/makefile",
        "./software/pcx86/bdsrc/cmd/mk.bat"
    ],
    "BDS-TEST": [
        "./software/pcx86/bdsrc/test/*.asm",
        "./software/pcx86/bdsrc/test/*.BAS",
        "./software/pcx86/bdsrc/test/*.BAT",
        "./software/pcx86/bdsrc/inc/*.inc",
        "./software/pcx86/bdsrc/test/makefile",
        "./software/pcx86/bdsrc/test/mk.bat"
    ],
    "BDSRC": [
        "./software/pcx86/bdsrc/**"
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
        archiveImage = " --output " + diskImage.replace(diskName, "archive/" + diskName).replace(".json",".img") + " --writable";
        if (diskName.startsWith("BDS-")) {
            kbTarget = 360;
        } else {
            diskFiles += " --boot ./software/pcx86/bdsrc/boot/obj/BOOT.COM";
        }
    }
    let cmd = "node \"${PCJS}/tools/modules/diskimage.js\" " + diskFiles + " --output " + diskImage + archiveImage + " --target=" + kbTarget + " --overwrite";
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
