/**
 * @fileoverview Gulp file for basicdos.com
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright © 2020-2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at <https://www.pcjs.org>.
 */

import fs from "fs";
import path from "path";
import gulp from "gulp";
import { globSync } from "glob";
import { spawn } from "child_process";

/**
 * run(cmd)
 *
 * Returns a gulp task function that runs the given shell command, with output sent to the console.
 *
 * @param {string} cmd
 * @returns {function(function(Error=))}
 */
function run(cmd)
{
    return function(done) {
        spawn(cmd, { shell: true, stdio: "inherit" }).on("close", (code) => {
            done(code? new Error("command failed with exit code " + code + ": " + cmd) : undefined);
        });
    };
}

/**
 * checkOutput(task, outputFile)
 *
 * Returns a gulp task function that runs the given task and then fails if the output file wasn't updated,
 * since diskimage.js reports some errors (eg, "file(s) too large") without returning a non-zero exit code.
 *
 * @param {function(function(Error=))} task
 * @param {string} outputFile
 * @returns {function(function(Error=))}
 */
function checkOutput(task, outputFile)
{
    return function(done) {
        let msStart = Date.now() - 1000;
        task(function(err) {
            if (!err && !(fs.existsSync(outputFile) && fs.statSync(outputFile).mtimeMs >= msStart)) {
                err = new Error("unable to update " + outputFile);
            }
            done(err);
        });
    };
}

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
    "./software/pcx86/src/tests/misc/SYMDEB.EXE",
    "./software/pcx86/src/msb/obj/*.EXE"
];

let disks = {
    "BASICDOS": [
        "./demos/s80/CONFIG.SYS",
        "./demos/s80/AUTOEXEC.BAT"
    ].concat(minFiles),
    "BASICDOS-DISK1": [
        "./demos/s80/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT"
    ].concat(demoFiles),
    "BASICDOS-DISK2": [
        "./demos/d40/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT"
    ].concat(demoFiles),
    "BASICDOS-DISK3": [
        "./demos/d80/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT",
    ].concat(demoFiles),
    "BASICDOS-DISK4": [
        "./demos/dual/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT",
    ].concat(demoFiles),
    "BASICDOS-DISK5": [
        "./demos/dual/multi/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT",
    ].concat(demoFiles),
    "BASICDOS-DISK6": [
        "./demos/s80/CONFIG.SYS",
        "./demos/d40/AUTOEXEC.BAT",
        "./demos/basic/*.BAS",          // DONKEY.BAS and the other PC DOS 1.00 BASIC samples
        "./demos/mbrot/MBROT.BAS",
        "./software/pcx86/src/tests/misc/BENCH.BAS"
    ].concat(minFiles),
    /*
     * A hard disk image (a demo with no diskettes) is described by an object instead: "root" lists the
     * files for the root directory, and every other property lists the files for a subdirectory.  pc.js
     * builds it (with --sys=bd:2, so it's bootable, and the BASIC-DOS system files are added to the root).
     */
    "BASICDOS-HD": {
        "root": [
            "./demos/hd/CONFIG.SYS",
            "./demos/d40/AUTOEXEC.BAT",
            "./software/pcx86/src/tests/misc/SYMDEB.EXE",
            "./software/pcx86/src/msb/obj/*.EXE"
        ],
        "BASIC": [
            "./demos/basic/*.BAS",
            "./demos/mbrot/MBROT.BAS",
            "./software/pcx86/src/tests/misc/BENCH.BAS",
            "./software/pcx86/src/tests/primes/PRIMES.BAS"
        ]
    },
    "BASICDOS-STRESS": {
        "root": [
            "./demos/stress/CONFIG.SYS",
            "./demos/stress/STRESS.BAT",
            "./software/pcx86/src/tests/primes/PRIMES.BAS"
        ]
    },
    "PCDOS200-C400": "./software/pcx86/disks/PCDOS200-C400.json"
};

/**
 * buildHD(diskName, diskImage)
 *
 * Returns a gulp task function that copies the files for a hard disk image (see "BASICDOS-HD" above) to a
 * staging directory (tools/pc/disks/diskName) and then uses pc.js to build a bootable BASIC-DOS hard disk
 * image from that directory.
 *
 * @param {string} diskName
 * @param {string} diskImage
 * @returns {function(function(Error=))}
 */
function buildHD(diskName, diskImage)
{
    return function(done) {
        let dirStage = "./tools/pc/disks/" + diskName;
        fs.rmSync(dirStage, { recursive: true, force: true });
        let dirs = disks[diskName];
        for (let dirName in dirs) {
            let dirTarget = dirName == "root"? dirStage : path.join(dirStage, dirName);
            fs.mkdirSync(dirTarget, { recursive: true });
            for (let fileSpec of dirs[dirName]) {
                let files = fileSpec.indexOf('*') >= 0? globSync(fileSpec) : [fileSpec];
                for (let file of files) {
                    fs.copyFileSync(file, path.join(dirTarget, path.basename(file)));
                }
            }
        }
        let cmd = "node ./tools/pc/pc.js ibm5160 " + dirStage + " --sys=bd:2 --target=10M --normalize --bare --label=BASICDOS --save=" + diskImage;
        run(cmd)(done);
    };
}

let buildTasks = [], demoTasks = [];
for (let diskName in disks) {
    let buildTask = "BUILD-" + diskName;
    let diskImage = "./software/pcx86/disks/" + diskName + ".json";
    let archiveImage = "";
    let diskFiles = "";
    let kbTarget = 360;                 // all diskettes are 360K (180K is too small now)
    if (!Array.isArray(disks[diskName]) && typeof disks[diskName] == "object") {
        gulp.task(buildTask, checkOutput(buildHD(diskName, diskImage), diskImage));
        buildTasks.push(buildTask);
        demoTasks.push(buildTask);
        continue;
    }
    if (typeof disks[diskName] == "string") {
        kbTarget = 10000;
        diskFiles = "--disk " + disks[diskName];
        diskImage = diskImage.replace(diskName, "archive/" + diskName).replace(".json",".hdd");
    }
    else {
        let dirPrev = "";
        for (let i = 0; i < disks[diskName].length; i++) {
            let fileNext = disks[diskName][i];
            if (fileNext.indexOf('*') >= 0) {
                let filesNext = globSync(fileNext).sort();  // newer versions of glob no longer sort
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
        diskFiles += " --boot ./software/pcx86/src/os/boot/obj/BOOT1.COM";
    }
    let cmd = "node \"${PCJS}/tools/diskimage/diskimage.js\" " + diskFiles + " --output " + diskImage + archiveImage + " --target=" + kbTarget + " --overwrite";
    cmd = cmd.replace(/\$\{([^}]+)\}/g, (_,n) => process.env[n]);
    gulp.task(buildTask, checkOutput(run(cmd), diskImage));
    buildTasks.push(buildTask);
    if (diskName.startsWith("BASICDOS")) demoTasks.push(buildTask);
}

/*
 * There's no longer a "watch" task: mk.sh runs "demos" after every build (to update the BASIC-DOS demo diskettes
 * with the new binaries), while "gulp build" (or simply "gulp") regenerates everything on demand.
 */
gulp.task("demos", gulp.series(demoTasks));
gulp.task("build", gulp.series(buildTasks));
gulp.task("default", gulp.series("build"));
