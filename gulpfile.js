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
 * DEMOS, and TESTS).  Every demo diskette gets ROOT (the system files, and its own CONFIG.SYS and
 * AUTOEXEC.BAT, if any), followed by EXT (which includes HELP.TXT) and DEMOS, so each demo diskette
 * differs only in its CONFIG.SYS, which sets PATH$ on each SHELL line (eg, SHELL=COMMAND.COM
 * PATH$="A:/;A:/EXT;A:/DEMOS").
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
 * and pc.js adds the system files itself, and with --order, so its root entries are in the same order as a diskette's,
 * rather than sorted by name).  A disk can list its own "folders" instead of the diskette folders (see BASICDOS-10MB),
 * where each folder is either a list of files or a directory (whose contents are copied, including any OBJ
 * directories).  A folder named FOLDER/SUBFOLDER is a subfolder (eg, DEMOS/WOLF3D), and a file spec of the form IMAGE.json/PATH names a file (or
 * files) inside a disk image, which diskimage.js extracts first (eg, the WOLF3D files come from the COMPAQ331-WOLF3D
 * hard disk in the pcjs-harddisks repository, via the same /harddisks/ path that pcjs.org uses).
 *
 * The PC DOS 1.00 BASIC samples are only on the hard disk, in TESTS/SAMPLES, except for DONKEY.BAS, which is in DEMOS
 * on every disk; each one gets the timestamp of the matching file on the PC DOS 1.00 diskette (PCDOS100).
 *
 * Every disk gets a volume label, "BD-" plus the end of its name (eg, BD-D40 for BASICDOS-360K-D40), unless it sets
 * its own "label".  A diskette with a "title" is listed under that title in the diskette list of every machine's FDC
 * (see writeDiskettes()).
 *
 * A ZIP file in a list of files (eg, PUBLIC.zip) is extracted into the folder itself, preserving the original
 * timestamps of its files.
 *
 * Which disks a build updates depends on the mode of its binaries (the mode of the last mkdos.sh or mk.sh build, which
 * tools/pc/disks/mkmode records) and package.json's config.release: a disk marked "final" (the release diskette, the
 * 64K demos, which don't have room for DEBUG binaries, and the Protected Mode demo, whose CPU$ work is built FINAL) is
 * updated only with FINAL binaries, and every other disk is updated with any binaries, except FINAL binaries while
 * config.release is "debug".  So while config.release is "debug", a DEBUG build updates all but the "final" disks, and
 * a FINAL build updates only the "final" disks; once it's "final", a FINAL build updates them all, and a DEBUG build
 * updates all but the "final" disks.
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
/*
 * toolFiles(dir) returns the files (not the folders) in software/src/tools/dir.
 */
const toolFiles = (dir) => globSync(SRC + "/tools/" + dir + "/*").sort().filter((file) =>
    !fs.statSync(file).isDirectory());

const diskFolders = { EXT: manifest.EXT, DEMOS: manifest.DEMOS };
/**
 * diskFiles(diskName, fileSpecs)
 *
 * Returns the paths of the specified files (eg, "*.BAS") from one of our disk images (eg, the PC DOS 1.00 diskette,
 * PCDOS100), whose files are extracted (with PCJS's diskimage.js) to tools/pc/disks/diskName
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
    "BASICDOS-360K-S80": { config: "./demos/s80/CONFIG.SYS", title: "BASIC-DOS Single" },
    "BASICDOS-360K-D40": { config: "./demos/d40/CONFIG.SYS", title: "BASIC-DOS 40-Cols" },
    "BASICDOS-360K-D80": { config: "./demos/d80/CONFIG.SYS", title: "BASIC-DOS 80-Cols" },
    "BASICDOS-360K-P80": { config: "./demos/p80/CONFIG.SYS", title: "BASIC-DOS Multi-Page" },
    "BASICDOS-360K-P80PM": { config: "./demos/mmu/CONFIG.SYS", title: "BASIC-DOS (80286)" },
    "BASICDOS-360K-PM386": { config: "./demos/mmu/386/CONFIG.SYS", title: "BASIC-DOS (80386)" },
    "BASICDOS-360K-DUAL": { config: "./demos/dual/CONFIG.SYS", title: "BASIC-DOS Dual Monitor" },
    "BASICDOS-360K-MULTI": { config: "./demos/dual/multi/CONFIG.SYS", title: "BASIC-DOS Multi-Console" },
    "BASICDOS-360K-SERIAL": { config: "./demos/serial/CONFIG.SYS", title: "BASIC-DOS HD Serial Port" },
    "BASICDOS-360K-VT100": { config: "./demos/vt100/CONFIG.SYS", title: "BASIC-DOS HD VT100" },
    "BASICDOS-360K-DEBUG": { config: "./demos/debug/CONFIG.SYS", title: "BASIC-DOS Serial Debugger" },
    "BASICDOS-360K-M64": { config: "./demos/m64/CONFIG.SYS", title: "BASIC-DOS Monochrome", final: true },
    "BASICDOS-360K-M640": { config: "./demos/m64/m640/CONFIG.SYS", title: "BASIC-DOS 640K Monochrome" },
    "BASICDOS-360K-TERM": { config: "./demos/term/CONFIG.SYS", title: "BASIC-DOS Terminal", final: true },
    "BASICDOS-360K-TERMHD": { config: "./demos/term/hd/CONFIG.SYS", title: "BASIC-DOS HD Terminal" },
    "BASICDOS-360K-TERM2": { config: "./demos/term/dual/CONFIG.SYS", title: "BASIC-DOS HD Multi-Terminal" },
    "BASICDOS-360K-MMU": { config: "./demos/mmu/vt100/CONFIG.SYS", title: "BASIC-DOS (80286) VT100" },
    "BASICDOS-360K-MMU386": {
        config: "./demos/mmu/vt100/386/CONFIG.SYS", title: "BASIC-DOS (80386) VT100"
    },
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
            SRC: SRC + "/os",           // the BASIC-DOS source (with an MK.BAT that builds it on BASIC-DOS)
            TESTS: manifest.TESTS,
            "TESTS/REGRESS": manifest["TESTS/REGRESS"],
            "TESTS/MISC": manifest["TESTS/MISC"],
            "TESTS/SAMPLES": manifest["TESTS/SAMPLES"],
            //
            // The tools in software/src/tools/dos (see software/src/tools/README.TXT), overlaid with the BASIC-DOS versions in
            // software/src/tools/bd (eg, MASM, MAKE, and LINK4; mk.sh gets the same result from the order of its PATH$), and then
            // the manifest's TOOLS (eg, MSBASIC).
            //
            // All of those go in TOOLS/BIN (which the hard disk configurations add to PATH$); TOOLS itself has
            // only README.TXT.
            //
            TOOLS: [ SRC + "/tools/README.TXT" ],
            "TOOLS/BIN": toolFiles("dos").concat(toolFiles("bd"), manifest.TOOLS),
            //
            // The C compiler's include files and libraries; the BASIC-DOS libraries replace the originals with the
            // same names, just as the BASIC-DOS tools do.
            //
            "TOOLS/INCLUDE": [ SRC + "/tools/dos/include/*" ],
            "TOOLS/INCLUDE/SYS": [ SRC + "/tools/dos/include/SYS/*" ],
            "TOOLS/LIB": [ SRC + "/tools/dos/lib/*", SRC + "/tools/bd/lib/*" ],
            //
            // The BASIC-DOS C startup code and floating-point library sources (with a test), the source of STUB.EXE,
            // and the C demos (HELLO is the sample that explains each step); all but the first have a makefile that
            // builds a program there.  SUCKS gets everything in its folder (bdc is its makefile for BDC) but README.md (README.TXT is the
            // version for the disk).
            //
            "TOOLS/CRT": [ SRC + "/tools/bd/crt/*" ],
            "TOOLS/FP": [ SRC + "/tools/bd/fp/*" ],
            "TOOLS/STUB": [ SRC + "/tools/bd/stub/*" ],
            "TOOLS/BDC": [ SRC + "/tools/bd/bdc/*" ],             // the BASIC-DOS C compiler's source (BDC.EXE is in TOOLS/BIN)
            "TOOLS/DEMOS/HELLO": [ SRC + "/tools/bd/demos/hello/*" ],
            "TOOLS/DEMOS/SUCKS": [ SRC + "/tools/bd/demos/sucks/*.c", SRC + "/tools/bd/demos/sucks/*.def", SRC + "/tools/bd/demos/sucks/makefile", SRC + "/tools/bd/demos/sucks/bdc", SRC + "/tools/bd/demos/sucks/README.TXT" ]
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
                /*
                 * A wildcard doesn't include folders (eg, the C compiler's lib and include folders in
                 * software/src/tools/dos), which a disk lists as folders of their own.
                 */
                if (fileSpec.indexOf('*') >= 0 && fs.statSync(file).isDirectory()) continue;
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
        entries.push(path.join(dirStage, "MKFINAL"));
    }
    let folders = disk.folders || diskFolders;
    for (let folder in folders) {
        let files = folders[folder];
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
            fs.mkdirSync(dirTarget, { recursive: true });   // a folder may have no entry for its parent (eg, TOOLS/DEMOS)
            copyFiles(files, dirTarget);
            if (folder == "TESTS/SAMPLES") {
                /*
                 * A sample that DEMOS lists (ie, DONKEY.BAS) is on the disk already, so leave it out here.
                 */
                for (let file of manifest.DEMOS) {
                    fs.rmSync(path.join(dirTarget, path.basename(file)), { force: true });
                }
            }
            if (folder == "TESTS/SAMPLES" || folder == "DEMOS") {
                /*
                 * The samples (and DONKEY.BAS, in DEMOS) are text copies of the tokenized originals on the PC DOS
                 * 1.00 diskette, so give each one its original's timestamp.
                 */
                for (let file of fs.readdirSync(dirTarget)) {
                    if (path.extname(file).toUpperCase() != ".BAS") continue;
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
            cmd = "node ./tools/pc/pc.js ibm5160 ./tools/pc/disks/" + diskName + " --sys=bd:2 --target=10M --normalize --bare --label=" + label +
                  " --order=" + entries.map(entry => path.basename(entry)).join(",") + " --save=" + diskImage;
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
 * path to its title; since Jekyll's data_dir is "machines", _includes/machine.html adds them to every FDC's list.  It
 * also writes machines/pcx86/basicdos-configs.json, which maps each disk's name to its CONFIG.SYS, for the pages whose
 * machines boot a disk whose CONFIG.SYS is in another folder (eg, {{ site.data.pcx86.basicdos-configs.BASICDOS-10MB }}
 * on the Wolfenstein 3D pages), since include_relative can't reach another folder.
 *
 * @param {function(Error=)} done
 */
function writeDiskettes(done)
{
    let diskettes = {}, configs = {};
    for (let diskName in disks) {
        let disk = disks[diskName];
        if (disk.title) diskettes["/software/disks/" + diskName + ".json"] = disk.title;
        if (disk.config) configs[diskName] = fs.readFileSync(disk.config, "utf8");
    }
    let writeData = function(file, data) {
        let text = JSON.stringify(data, null, 2) + "\n";
        if (!fs.existsSync(file) || fs.readFileSync(file, "utf8") != text) fs.writeFileSync(file, text);
    };
    writeData("./machines/pcx86/basicdos-diskettes.json", diskettes);
    writeData("./machines/pcx86/basicdos-configs.json", configs);
    done();
}
gulp.task("diskettes", writeDiskettes);

/**
 * diskSources(diskName)
 *
 * Returns the files that a BASIC-DOS disk is built from, as stageDisk() and buildDisk() use them: paths that may
 * contain wildcards, where a folder that's copied whole (eg, the hard disk's SRC) ends with "/**".  Files that come
 * from inside another disk image aren't included.
 *
 * @param {string} diskName
 * @returns {Array.<string>}
 */
function diskSources(diskName)
{
    let disk = disks[diskName];
    let sources = [disk.config, disk.autoexec];
    if (!disk.data && !disk.hd) {
        sources.push(...manifest.ROOT.filter(file => file != "CONFIG.SYS"), SRC + "/os/boot/obj/BOOT1.COM");
    }
    let folders = disk.folders || diskFolders;
    for (let folder in folders) {
        let files = folders[folder];
        if (typeof files == "string") sources.push(files + "/**"); else sources.push(...files);
    }
    return sources.filter(file => file && !/\.json\//.test(file));
}

/**
 * isAffected(diskName, files)
 *
 * Returns true if any of the given files (resolved paths) is one that the disk is built from; a wildcard matches
 * by name, so a file that's been deleted, or added since the last build, still counts.
 *
 * @param {string} diskName
 * @param {Array.<string>} files
 * @returns {boolean}
 */
function isAffected(diskName, files)
{
    return diskSources(diskName).some(source => {
        let re = new RegExp("^" + path.resolve(source).replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*\*/g, "\0").replace(/\*/g, "[^/]*").replace(/\0/g, ".*") + "$", "i");
        return files.some(file => re.test(file));
    });
}

/*
 * The "watch" task (below) runs "demos" with the files that changed in BD_CHANGED (one path per line, or "*" if there
 * were too many to list), so that only the disks built from those files are rebuilt; a change to one of WATCHALL
 * (the files that define what's on every disk) rebuilds them all.
 */
const WATCHALL = [ "./software/manifest.txt", "./gulpfile.js", "./package.json" ];
let changed = process.env["BD_CHANGED"]? process.env["BD_CHANGED"].split("\n").map(file => path.resolve(file)) : null;
if (changed && (process.env["BD_CHANGED"] == "*" || WATCHALL.some(file => changed.includes(path.resolve(file))))) {
    changed = null;
}

let demoTasks = ["diskettes"];
for (let diskName in disks) {
    if (disks[diskName].final? !FINAL : FINAL && !RELEASE) continue;
    if (changed && !isAffected(diskName, changed)) continue;
    let buildTask = "BUILD-" + diskName;
    let diskImage = "./software/disks/" + diskName + ".json";
    gulp.task(buildTask, checkOutput(buildDisk(diskName, diskImage), diskImage));
    demoTasks.push(buildTask);
}

if (process.env["BD_CHANGED"]) {
    console.log(demoTasks.length > 1? "updating " + demoTasks.slice(1).map(task => task.replace("BUILD-", "")).join(", ") : "no disks to update");
}

/*
 * "gulp build" (or simply "gulp") rebuilds every disk on demand, and "gulp watch" rebuilds the disks that a file is
 * on whenever the file changes (eg, a BAS file in DEMOS, a CONFIG.SYS, or the binaries of a new build), 2 seconds
 * after the last change.  Each update is a separate "gulp demos", so that it uses the current manifest, build mode,
 * and version, and if files change during an update, another one follows it.
 *
 * WATCHED covers more than the disks use, since the manifest can list any file in those folders; the test
 * configurations (software/src/configs, which tools/tests/prep.sh fills) aren't on any disk, so they're ignored,
 * as are hidden files.  A pc.js build writes its outputs back to software/src only when it exits, so an update never
 * sees a build that's still running.
 *
 * While it runs, the watcher's process ID is in WATCHPID, which tells mk.sh and mkdos.sh that they don't need to run
 * "gulp demos" themselves (see watching() in tools/release.sh).
 */
const WATCHED = WATCHALL.concat([ SRC + "/**", "./demos/**", "./download/**", "./software/tests/**" ]);
const WATCHPID = "./tools/pc/disks/watch.pid";

gulp.task("watch", function() {
    if (!process.env["PCJS"] && fs.existsSync("../pcjs/tools/diskimage/diskimage.js")) {
        process.env["PCJS"] = path.resolve("../pcjs");
    }
    if (!process.env["PCJS"]) throw new Error("PCJS must be set to the pcjs repository");
    /*
     * Two watchers would update the same disks at the same time, so there can be only one.
     */
    try {
        process.kill(+fs.readFileSync(WATCHPID, "utf8"), 0);
        throw new Error("gulp watch is already running");
    } catch (err) {
        if (err.message.startsWith("gulp watch")) throw err;
    }
    fs.mkdirSync(path.dirname(WATCHPID), { recursive: true });
    fs.writeFileSync(WATCHPID, process.pid + "\n");
    process.on("exit", () => fs.rmSync(WATCHPID, { force: true }));
    for (let signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(signal, () => process.exit());
    let files = new Set();
    let update = function(done) {
        let list = [...files];
        files.clear();
        if (!list.length) return done();
        let env = Object.assign({}, process.env, { BD_CHANGED: list.length > 2000? "*" : list.join("\n") });
        spawn("npx gulp demos --silent", { shell: true, stdio: "inherit", env }).on("close", (code) => {
            if (code) console.log("error: unable to update the disks (run \"npx gulp demos\" for details)");
            done();
        });
    };
    let watcher = gulp.watch(WATCHED, {
        delay: 2000,
        ignored: (file) => /(^|\/)\.[^\/.]/.test(file) || /(^|\/)software\/src\/configs\//.test(file)
    }, update);
    watcher.on("all", (event, file) => files.add(file));
    return watcher;
});
gulp.task("demos", gulp.series(demoTasks));
gulp.task("build", gulp.series(demoTasks));
gulp.task("default", gulp.series("build"));
