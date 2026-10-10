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

/*
 * Every BASIC-DOS disk has the same layout: the system files (BASDEV.COM, BASDOS.COM, and COMMAND.COM), CONFIG.SYS,
 * AUTOEXEC.BAT (when launched by a SHELL line), and HELP.TXT in the root, followed by a BASIC folder (BASIC
 * samples), a TOOLS folder (utilities in os/util), and a TESTS folder (other demo and test programs, eg, MSBASIC
 * and SYMDEB).
 * CONFIG.SYS sets PATH$ on each SHELL line (eg, SHELL=COMMAND.COM LET PATH$="A:/;A:/BASIC;A:/TOOLS;A:/TESTS").
 *
 * Each disk below lists its CONFIG.SYS, its AUTOEXEC.BAT (if any), and the files for its BASIC and TESTS folders;
 * every disk gets the same root files and TOOLS folder.  A hard disk image (a demo with no diskettes) is marked "hd",
 * and pc.js builds it (with --sys=bd:2, so it's bootable, and pc.js adds the system files and HELP.TXT itself).
 */
const SRC = "./software/pcx86/src";
const sysFiles = [ SRC + "/os/dev/obj/BASDEV.COM", SRC + "/os/dos/obj/BASDOS.COM", SRC + "/os/cmd/obj/COMMAND.COM" ];
const helpFile = SRC + "/os/cmd/HELP.TXT";
const toolFiles = [ SRC + "/os/util/obj/*.COM" ];
const primesFiles = [ SRC + "/tests/primes/PRIMES.BAS", SRC + "/tests/primes/PRIMES.BAT" ];
const sampleFiles = [ "./demos/basic/*.BAS", "./demos/mbrot/MBROT.BAS" ].concat(primesFiles);
const extraFiles = [ SRC + "/tests/misc/SYMDEB.EXE", SRC + "/msb/obj/*.EXE" ];
const testFiles = [ SRC + "/tests/bin/*.EXE", SRC + "/tests/bin/*.COM", SRC + "/tests/misc/BD*.BAT" ].concat(extraFiles);

let disks = {
    "BASICDOS": {
        config: "./demos/s80/CONFIG.SYS",
        autoexec: "./demos/s80/AUTOEXEC.BAT",
        BASIC: primesFiles,
        TESTS: extraFiles
    },
    "BASICDOS-DISK1": {
        config: "./demos/s80/CONFIG.SYS",
        autoexec: "./demos/d40/AUTOEXEC.BAT",
        BASIC: primesFiles,
        TESTS: testFiles
    },
    "BASICDOS-DISK2": {
        config: "./demos/d40/CONFIG.SYS",
        BASIC: primesFiles,
        TESTS: testFiles
    },
    "BASICDOS-DISK3": {
        config: "./demos/d80/CONFIG.SYS",
        BASIC: primesFiles,
        TESTS: testFiles
    },
    "BASICDOS-DISK4": {
        config: "./demos/dual/CONFIG.SYS",
        BASIC: primesFiles,
        TESTS: testFiles
    },
    "BASICDOS-DISK5": {
        config: "./demos/dual/multi/CONFIG.SYS",
        autoexec: "./demos/d40/AUTOEXEC.BAT",
        BASIC: primesFiles,
        TESTS: testFiles
    },
    "BASICDOS-DISK6": {
        config: "./demos/s80/CONFIG.SYS",
        autoexec: "./demos/d40/AUTOEXEC.BAT",
        BASIC: sampleFiles,             // DONKEY.BAS and the other PC DOS 1.00 BASIC samples
        TESTS: [ SRC + "/tests/misc/BENCH.BAS" ].concat(extraFiles)
    },
    "BASICDOS-HD": {
        hd: true,
        config: "./demos/hd/CONFIG.SYS",
        autoexec: "./demos/d40/AUTOEXEC.BAT",
        BASIC: sampleFiles,
        TESTS: [ SRC + "/tests/misc/BENCH.BAS" ].concat(extraFiles)
    },
    "BASICDOS-STRESS": {
        hd: true,
        config: "./demos/stress/CONFIG.SYS",
        BASIC: [ SRC + "/tests/primes/PRIMES.BAS" ],
        TESTS: [ "./demos/stress/STRESS.BAT" ]
    },
    "PCDOS200-C400": "./software/pcx86/disks/PCDOS200-C400.json"
};

/**
 * stageDisk(diskName)
 *
 * Copies the files for a BASIC-DOS disk (see "disks" above) to a staging directory (tools/pc/disks/diskName),
 * and returns the root entries in the order they should appear on the disk.
 *
 * @param {string} diskName
 * @returns {Array.<string>}
 */
function stageDisk(diskName)
{
    let disk = disks[diskName];
    let dirStage = "./tools/pc/disks/" + diskName;
    fs.rmSync(dirStage, { recursive: true, force: true });
    fs.mkdirSync(dirStage, { recursive: true });
    let entries = [];
    let copyFiles = function(fileSpecs, dirTarget, name) {
        for (let fileSpec of fileSpecs) {
            let files = fileSpec.indexOf('*') >= 0? globSync(fileSpec).sort() : [fileSpec];
            for (let file of files) {
                let target = path.join(dirTarget, name || path.basename(file));
                fs.copyFileSync(file, target);
                if (dirTarget == dirStage) entries.push(target);
            }
        }
    };
    if (!disk.hd) copyFiles(sysFiles, dirStage);
    copyFiles([disk.config], dirStage, "CONFIG.SYS");
    let launchesAutoexec = fs.readFileSync(disk.config, "utf8").split(/\r?\n/).some(line =>
        /^SHELL=/i.test(line) && /\bAUTOEXEC(?:\.BAT)?\b/i.test(line));
    if (disk.autoexec && launchesAutoexec) copyFiles([disk.autoexec], dirStage, "AUTOEXEC.BAT");
    if (!disk.hd) copyFiles([helpFile], dirStage);
    let folders = { BASIC: disk.BASIC || [], TOOLS: toolFiles, TESTS: disk.TESTS || [] };
    for (let folder in folders) {
        if (!folders[folder].length) continue;
        let dirTarget = path.join(dirStage, folder);
        fs.mkdirSync(dirTarget);
        copyFiles(folders[folder], dirTarget);
        entries.push(dirTarget);
    }
    return entries;
}

/**
 * buildDisk(diskName, diskImage)
 *
 * Returns a gulp task function that stages the files for a BASIC-DOS disk and then builds the disk image:
 * a hard disk with pc.js, or a 360K diskette with diskimage.js (which requires PCJS).
 *
 * @param {string} diskName
 * @param {string} diskImage
 * @returns {function(function(Error=))}
 */
function buildDisk(diskName, diskImage)
{
    return function(done) {
        let entries = stageDisk(diskName);
        let cmd;
        if (disks[diskName].hd) {
            cmd = "node ./tools/pc/pc.js ibm5160 ./tools/pc/disks/" + diskName + " --sys=bd:2 --target=10M --normalize --bare --label=BASICDOS --save=" + diskImage;
        } else {
            let archiveImage = diskImage.replace(diskName, "archive/" + diskName).replace(".json",".img");
            cmd = "node \"" + process.env["PCJS"] + "/tools/diskimage/diskimage.js\" --files " + entries.join(",") +
                  " --boot " + SRC + "/os/boot/obj/BOOT1.COM --output " + diskImage + " --normalize --output " + archiveImage +
                  " --writable --target=360 --overwrite";
        }
        run(cmd)(done);
    };
}

let buildTasks = [], demoTasks = [];
for (let diskName in disks) {
    let buildTask = "BUILD-" + diskName;
    let diskImage = "./software/pcx86/disks/" + diskName + ".json";
    if (typeof disks[diskName] == "string") {
        let archiveImage = diskImage.replace(diskName, "archive/" + diskName).replace(".json",".hdd");
        let cmd = "node \"${PCJS}/tools/diskimage/diskimage.js\" --disk " + disks[diskName] + " --output " + archiveImage + " --target=10000 --overwrite";
        cmd = cmd.replace(/\$\{([^}]+)\}/g, (_,n) => process.env[n]);
        gulp.task(buildTask, checkOutput(run(cmd), archiveImage));
        buildTasks.push(buildTask);
        continue;
    }
    gulp.task(buildTask, checkOutput(buildDisk(diskName, diskImage), diskImage));
    buildTasks.push(buildTask);
    demoTasks.push(buildTask);
}

/*
 * There's no longer a "watch" task: mk.sh runs "demos" after every build (to update the BASIC-DOS demo diskettes
 * with the new binaries), while "gulp build" (or simply "gulp") regenerates everything on demand.
 */
gulp.task("demos", gulp.series(demoTasks));
gulp.task("build", gulp.series(buildTasks));
gulp.task("default", gulp.series("build"));
