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
import { spawn, execSync } from "child_process";

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
 * The files on every BASIC-DOS disk come from software/manifest.txt, which lists the files for each folder (ROOT, EXT,
 * DEMOS, SAMPLES, and TESTS).  Every demo diskette gets ROOT (the system files, its own CONFIG.SYS and AUTOEXEC.BAT,
 * if any, and HELP.TXT), followed by EXT, DEMOS, and SAMPLES, so each demo diskette differs only in its CONFIG.SYS,
 * which sets PATH$ on each SHELL line (eg, SHELL=COMMAND.COM PATH$="A:/;A:/EXT;A:/DEMOS;A:/SAMPLES").
 *
 * The release diskette, BASICDOS-360K, is the same, but its build also writes a raw image of it (marked "img"),
 * BASICDOS-360K.img, which the home page offers for download, and its title includes the version (eg, "BASIC-DOS 2.01
 * (Release)"), which also lists it first.
 *
 * The TESTS files (with the regression tests in TESTS/REGRESS and other test programs in TESTS/MISC) and the TOOLS
 * files (eg, SYMDEB and MSBASIC) are on a separate data diskette (marked "data"), BASICDOS-360K-TESTS; it isn't
 * bootable, so it has no root files, and it can be loaded in drive B: of any demo.
 *
 * A hard disk image (a demo with no diskettes) is marked "hd", and pc.js builds it (with --sys=bd:2, so it's bootable,
 * and pc.js adds the system files and HELP.TXT itself).  A disk can list its own "folders" instead of the diskette
 * folders (see BASICDOS-10MB), where each folder is either a list of files, a directory (whose contents are copied,
 * including any OBJ directories), or a function that returns a list of files from other disk images (see diskFiles()).
 * A folder named FOLDER/SUBFOLDER is a subfolder (eg, DEMOS/WOLF3D), and a file spec of the form IMAGE.json/PATH
 * names a file (or files) inside a disk image, which diskimage.js extracts first (eg, the WOLF3D files come from the
 * COMPAQ331-WOLF3D hard disk in the pcjs-harddisks repository, via the same /harddisks/ path that pcjs.org uses).
 *
 * A SAMPLES folder's files get the timestamps of the matching files on the PC DOS 1.00 diskette (PCDOS100).
 *
 * Every disk gets a volume label, "BD-" plus the end of its name (eg, BD-D40 for BASICDOS-360K-D40), unless it sets
 * its own "label".  A diskette with a "title" is listed under that title in the diskette list of every machine's FDC
 * (see writeDiskettes()).
 *
 * A ZIP file in a list of files (eg, PUBLIC.zip) is extracted into the folder itself, preserving the original
 * timestamps of its files.
 *
 * Which disks a build updates depends on the mode of its binaries (the mode of the last mkdos.sh or mk.sh build, which
 * tools/pc/disks/mkmode records) and package.json's config.release: a disk marked "final" (the release diskette, and
 * the 64K demo, which doesn't have room for DEBUG binaries) is updated only with FINAL binaries, and every other disk
 * is updated with any binaries, except FINAL binaries while config.release is "debug".  So while config.release is
 * "debug", a DEBUG build updates all but the "final" disks, and a FINAL build updates only the "final" disks; once
 * it's "final", a FINAL build updates them all, and a DEBUG build updates all but the "final" disks.
 */
const SRC = "./software/src";
/*
 * The BASIC-DOS version comes from package.json's version (see tools/release.sh): its major number, and its minor
 * number as two digits (eg, "2.1.0" is BASIC-DOS 2.01).
 */
const VERSION = JSON.parse(fs.readFileSync("./package.json", "utf8")).version.replace(/^(\d+)\.(\d+).*$/,
    (match, major, minor) => major + "." + minor.padStart(2, "0"));
const MKMODE = "./tools/pc/disks/mkmode";
const FINAL = fs.existsSync(MKMODE) && fs.readFileSync(MKMODE, "utf8").trim() == "FINAL";
const RELEASE = JSON.parse(fs.readFileSync("./package.json", "utf8")).config?.release == "final";
/*
 * On every bootable disk, BASDEV.COM and BASDOS.COM are read-only hidden system files, and COMMAND.COM is a
 * read-only system file (which DIR lists, since in BASIC-DOS, only the hidden attribute keeps a file out of DIR);
 * diskimage.js sets them with --attr, and pc.js (for hard disks) uses the "attrs" in tools/pc/pc.json5.
 */
const SYSATTRS = "BASDEV.COM:RHS,BASDOS.COM:RHS,COMMAND.COM:RS";
const manifest = {};
let section;
for (let line of fs.readFileSync("./software/manifest.txt", "utf8").split(/\r?\n/)) {
    line = line.replace(/#.*/, "").trim();
    let match = line.match(/^\[([\w\/]+)\]$/);
    if (match) {
        manifest[section = match[1]] = [];
    } else if (line && section) {
        manifest[section].push(line);
    }
}
const diskFolders = { EXT: manifest.EXT, DEMOS: manifest.DEMOS, SAMPLES: manifest.SAMPLES };
/**
 * diskFiles(diskName, fileSpecs)
 *
 * Returns the paths of the specified files (eg, "TOOLS/MASM4/*") from one of our disk images (eg, the MS-DOS 3.20
 * build disk, MSDOS320-C400), whose files are extracted (with PCJS's diskimage.js) to tools/pc/disks/diskName
 * the first time they're needed.
 *
 * @param {string} diskName
 * @param {Array.<string>} fileSpecs
 * @returns {Array.<string>}
 */
function diskFiles(diskName, fileSpecs)
{
    let diskFile = diskName.endsWith(".json")? diskName : "./software/disks/" + diskName + ".json";
    let diskDir = "./tools/pc/disks/" + path.basename(diskFile, ".json");
    if (!fs.existsSync(diskDir)) {
        execSync("node \"" + process.env["PCJS"] + "/tools/diskimage/diskimage.js\" " + diskFile + " --extract --dest=" + diskDir, { stdio: "ignore" });
    }
    return fileSpecs.map(fileSpec => diskDir + "/" + fileSpec);
}

let disks = {
    "BASICDOS-360K": {
        config: "./download/CONFIG.SYS",
        label: "BASIC-DOS",
        title: "BASIC-DOS " + VERSION + " (Release)",
        img: true,
        final: true
    },
    "BASICDOS-360K-S80": { config: "./demos/s80/CONFIG.SYS", title: "BASIC-DOS 80-Column Demo" },
    "BASICDOS-360K-D40": { config: "./demos/d40/CONFIG.SYS", title: "BASIC-DOS 40-Column Demo" },
    "BASICDOS-360K-D80": { config: "./demos/d80/CONFIG.SYS", title: "BASIC-DOS 80-Column Split Demo" },
    "BASICDOS-360K-P80": { config: "./demos/p80/CONFIG.SYS", title: "BASIC-DOS Multi-Page Demo" },
    "BASICDOS-360K-DUAL": { config: "./demos/dual/CONFIG.SYS", title: "BASIC-DOS Dual Monitor Demo" },
    "BASICDOS-360K-MULTI": { config: "./demos/dual/multi/CONFIG.SYS", title: "BASIC-DOS Multi-Session Demo" },
    "BASICDOS-360K-SERIAL": { config: "./demos/serial/CONFIG.SYS", title: "BASIC-DOS HD Serial Port Demo" },
    "BASICDOS-360K-VT100": { config: "./demos/vt100/CONFIG.SYS", title: "BASIC-DOS HD VT100 Demo" },
    "BASICDOS-360K-DEBUG": { config: "./demos/debug/CONFIG.SYS", title: "BASIC-DOS Serial Debugger Demo" },
    "BASICDOS-360K-M64": { config: "./demos/m64/CONFIG.SYS", title: "BASIC-DOS Monochrome Demo", final: true },
    "BASICDOS-360K-TESTS": {
        title: "BASIC-DOS Tests",
        data: true,
        folders: {
            TESTS: manifest.TESTS,
            "TESTS/REGRESS": manifest["TESTS/REGRESS"],
            "TESTS/MISC": manifest["TESTS/MISC"],
            TOOLS: manifest.TOOLS
        }
    },
    "BASICDOS-10MB": {
        hd: true,
        config: "./demos/hd/CONFIG.SYS",
        folders: {
            EXT: manifest.EXT,
            //
            // WOLF3D.BAT runs the game in DEMOS/WOLF3D, so only this disk gets it, and PUBLIC.zip has JIVE.EXE
            //
            DEMOS: manifest.DEMOS.concat([ "./demos/wolf3d/WOLF3D.BAT", "./software/tests/PUBLIC.zip" ]),
            "DEMOS/WOLF3D": manifest["DEMOS/WOLF3D"],
            SAMPLES: manifest.SAMPLES,
            SRC: SRC + "/os",           // the BASIC-DOS source (with an MK.BAT that builds it on BASIC-DOS)
            TESTS: manifest.TESTS,
            "TESTS/REGRESS": manifest["TESTS/REGRESS"],
            "TESTS/MISC": manifest["TESTS/MISC"],
            //
            // The MASM 4.00 files come from the MS-DOS 3.20 build disk, but the build tools in software/src/tools
            // (the same ones that mk.sh uses) replace their counterparts, adding MAKE 4.02 and MS-DOS 3.20's EXE2BIN
            // (see software/src/tools/README.TXT); the manifest's TOOLS (eg, SYMDEB, which MASM4 has too, and MSBASIC) are
            // added last.
            //
            TOOLS: () => diskFiles("MSDOS320-C400", [ "TOOLS/MASM4/*" ]).concat([ SRC + "/tools/*" ], manifest.TOOLS)
        }
    }
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
            let disk = fileSpec.match(/^(.*\.json)\/(.*)$/);
            if (disk) fileSpec = diskFiles(disk[1], [disk[2]])[0];
            let files = fileSpec.indexOf('*') >= 0? globSync(fileSpec).sort() : [fileSpec];
            for (let file of files) {
                let target = path.join(dirTarget, name || path.basename(file));
                if (!name && path.extname(file).toLowerCase() == ".zip") {
                    execSync("unzip -q -o \"" + file + "\" -d \"" + dirTarget + "\"");
                } else {
                    fs.cpSync(file, target, { preserveTimestamps: true });
                }
                if (dirTarget == dirStage) entries.push(target);
            }
        }
    };
    for (let file of disk.data? [] : manifest.ROOT) {
        if (file != "CONFIG.SYS") {
            if (!disk.hd) copyFiles([file], dirStage);
            continue;
        }
        copyFiles([disk.config], dirStage, "CONFIG.SYS");
        let launchesAutoexec = fs.readFileSync(disk.config, "utf8").split(/\r?\n/).some(line =>
            /^SHELL=/i.test(line) && /\bAUTOEXEC(?:\.BAT)?\b/i.test(line));
        if (disk.autoexec && launchesAutoexec) copyFiles([disk.autoexec], dirStage, "AUTOEXEC.BAT");
    }
    /*
     * MK.BAT (in SRC) builds DEBUG binaries unless there's an MKFINAL file in its parent directory (as MKDOS.BAT does
     * on the build disk), so the hard disk gets one if its binaries are FINAL (see FINAL).
     */
    if (disk.hd && FINAL) {
        fs.writeFileSync(path.join(dirStage, "MKFINAL"), "");
    }
    let folders = disk.folders || diskFolders;
    for (let folder in folders) {
        let files = folders[folder];
        if (typeof files == "function") files = files();
        if (!files.length) continue;
        let dirTarget = path.join(dirStage, folder);
        if (typeof files == "string") {
            /*
             * Copy the directory (including its OBJ directories, so that MK rebuilds only what changes), except
             * for hidden files and the MS-DOS build's mkdos.bat files (which chain from one subdirectory to the
             * next); the mk.bat at the top builds everything.
             */
            fs.cpSync(files, dirTarget, { recursive: true, filter: (src) => {
                let name = path.basename(src);
                return name[0] != '.' && name.toUpperCase() != "MKDOS.BAT";
            }, preserveTimestamps: true });
        } else {
            fs.mkdirSync(dirTarget);
            copyFiles(files, dirTarget);
            if (folder == "SAMPLES") {
                /*
                 * The samples are text copies of the tokenized originals on the PC DOS 1.00 diskette, so give
                 * each one its original's timestamp.
                 */
                for (let file of fs.readdirSync(dirTarget)) {
                    let original = diskFiles("PCDOS100", [ file ])[0];
                    if (!fs.existsSync(original)) continue;
                    let stat = fs.statSync(original);
                    fs.utimesSync(path.join(dirTarget, file), stat.atime, stat.mtime);
                }
            }
        }
        if (folder.indexOf('/') < 0) entries.push(dirTarget);      // a subfolder is part of its folder's entry
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
        let label = disks[diskName].label || diskName.replace(/^BASICDOS-(360K-)?/, "BD-");
        let cmd;
        if (disks[diskName].hd) {
            cmd = "node ./tools/pc/pc.js ibm5160 ./tools/pc/disks/" + diskName + " --sys=bd:2 --target=10M --normalize --bare --label=" + label + " --save=" + diskImage;
        } else {
            cmd = "node \"" + process.env["PCJS"] + "/tools/diskimage/diskimage.js\" --files " + entries.join(",") +
                  (disks[diskName].data? "" : " --boot " + SRC + "/os/boot/obj/BOOT1.COM --attr=" + SYSATTRS) +
                  " --output " + diskImage +
                  " --label=" + label + " --normalize --writable --target=360 --overwrite";
            if (disks[diskName].img) {
                cmd += " && node \"" + process.env["PCJS"] + "/tools/diskimage/diskimage.js\" --disk=" + diskImage +
                       " --output=" + diskImage.replace(/\.json$/, ".img") + " --writable --overwrite";
            }
        }
        /*
         * The staging directory is needed only to build the disk, so it's removed once the build succeeds (if the
         * build fails, it's left for inspection).
         */
        run(cmd)(function(err) {
            if (!err) fs.rmSync("./tools/pc/disks/" + diskName, { recursive: true, force: true });
            done(err);
        });
    };
}

/**
 * writeDiskettes(done)
 *
 * Writes the titled diskettes (see "disks" above) to machines/pcx86/basicdos-diskettes.json, which maps each diskette
 * path to its title; since Jekyll's data_dir is "machines", _includes/machine.html adds them to every FDC's list.
 *
 * @param {function(Error=)} done
 */
function writeDiskettes(done)
{
    let diskettes = {};
    for (let diskName in disks) {
        if (disks[diskName].title) diskettes["/software/disks/" + diskName + ".json"] = disks[diskName].title;
    }
    let file = "./machines/pcx86/basicdos-diskettes.json";
    let text = JSON.stringify(diskettes, null, 2) + "\n";
    if (!fs.existsSync(file) || fs.readFileSync(file, "utf8") != text) fs.writeFileSync(file, text);
    done();
}
gulp.task("diskettes", writeDiskettes);

let demoTasks = ["diskettes"];
for (let diskName in disks) {
    if (disks[diskName].final? !FINAL : FINAL && !RELEASE) continue;
    let buildTask = "BUILD-" + diskName;
    let diskImage = "./software/disks/" + diskName + ".json";
    gulp.task(buildTask, checkOutput(buildDisk(diskName, diskImage), diskImage));
    demoTasks.push(buildTask);
}

/*
 * There's no longer a "watch" task: mkdos.sh runs "demos" after every build (to update the BASIC-DOS demo diskettes
 * with the new binaries), while "gulp build" (or simply "gulp") regenerates everything on demand.
 */
gulp.task("demos", gulp.series(demoTasks));
gulp.task("build", gulp.series(demoTasks));
gulp.task("default", gulp.series("build"));
