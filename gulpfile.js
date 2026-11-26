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
 * The files on every BASIC-DOS disk come from manifest.txt, which lists the files for each folder (ROOT, the EXT
 * folders, DEMOS, and TESTS).  Every demo diskette gets ROOT (the system files, and its own CONFIG.SYS and
 * AUTOEXEC.BAT, if any), followed by EXT/CMD (which includes HELP.TXT), EXT/BAS, EXT/DLL (the libraries), and DEMOS, so each demo diskette
 * differs only in its CONFIG.SYS, which sets PATH$ on each SHELL line (eg, SHELL=COMMAND.COM
 * PATH$="A:\;A:\EXT\CMD;A:\EXT\BAS;A:\DEMOS").
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
 * rather than sorted by name).  A disk can list its own "folders" instead of the diskette folders (see BASICDOS-20MB),
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
 * Every disk has two sets of images (see SETS): disks/current, with FINAL binaries, which the web site uses, and
 * disks/debug, with DEBUG binaries, except for the disks marked "final" (the release diskette and the 64K demos, which
 * need FINAL binaries), which are only in disks/current.  "gulp demos" (which mk.sh and mkdos.sh run after a build)
 * updates the set of the current build mode (the mode of the last mkdos.sh or mk.sh build, which tools/pc/disks/mkmode
 * records), and "gulp build" updates both.  A diskette whose mode isn't the current one gets that mode's saved binaries
 * (see SAVED), so any change to a diskette's files (eg, its CONFIG.SYS) updates it in both sets ("gulp watch" updates
 * the disks of both sets that a changed file is on); the hard disk, whose system files pc.js adds from src itself (and
 * whose SRC has the current mode's OBJ folders), is updated only by a build of its mode.
 */
const SRC = "./src";
/*
 * The BASIC-DOS version comes from package.json's version (see tools/release.sh): its major number, its minor
 * number as two digits, and a letter for a nonzero patch number, its revision (eg, "2.1.0" is BASIC-DOS 2.01, and
 * "2.10.1" is 2.10A).
 */
const [MAJOR, MINOR, REV] = JSON.parse(fs.readFileSync("./package.json", "utf8")).version.split(".").map(Number);
const VERSION = MAJOR + "." + String(MINOR).padStart(2, "0") + (REV ? String.fromCharCode(64 + REV) : "");
/*
 * The distribution files (the root files, and the files that the manifest lists in the EXT folders and DEMOS) are dated
 * September 9, 1986, at a time that matches the version (eg, 2:10 AM for 2.10, whatever its revision), on every
 * disk, and so is every disk's volume label (diskimage.js's --labeldate, and pc.js's --sysdate); the PC DOS 1.00
 * samples keep their own timestamps (see stageDisk()).
 */
const DIST_TIME = "1986-09-09T" + String(MAJOR).padStart(2, "0") + ":" + String(MINOR).padStart(2, "0");
const DIST_DATE = new Date(DIST_TIME);         // (a date-time string without a time zone is local time)
const MKMODE = "./tools/pc/disks/mkmode";
/*
 * Each build mode's outputs are saved here while the other mode is current, in the same folders that they have in
 * src (see setMode in tools/release.sh).
 */
const SAVED = "./tools/pc/disks/objs";
/*
 * readMode() returns the build mode that MKMODE records ("" if none).  tools/release.sh's setMode changes it to
 * SWITCHING before it swaps the build outputs, so buildDisk() rereads it after building each disk, and leaves the
 * disk unchanged if the mode isn't still MODE: the disk's binaries may be from either mode.
 */
const readMode = () => fs.existsSync(MKMODE)? fs.readFileSync(MKMODE, "utf8").trim() : "";
const MODE = readMode();
const SWITCHING = MODE == "SWITCHING";
/*
 * The folder of each build mode's set of disk images.
 */
const SETS = { FINAL: "./disks/current", DEBUG: "./disks/debug" };
/*
 * diskimage.js prints its banner, options, and output file for every diskette it builds, so it runs with --quiet
 * (which still reports errors) unless gulp is run with --verbose (eg, "npx gulp watch --verbose").
 */
const VERBOSE = process.argv.includes("--verbose");
const DIQUIET = VERBOSE? "" : " --quiet";
/*
 * On every bootable disk, BASDEV.COM and BASDOS.COM are read-only hidden system files, and COMMAND.COM is a
 * read-only system file (which DIR lists, since in BASIC-DOS, only the hidden attribute keeps a file out of DIR);
 * diskimage.js sets them with --attr, and pc.js (for hard disks) uses the "attrs" in tools/pc/pc.json5.
 */
const SYSATTRS = "BASDEV.COM:RHS,BASDOS.COM:RHS,COMMAND.COM:RS";
const manifest = {};
let section;
for (let line of fs.readFileSync("./manifest.txt", "utf8").split(/\r?\n/)) {
    line = line.replace(/#.*/, "").trim();
    let match = line.match(/^\[([\w\/]+)\]$/);
    if (match) {
        manifest[section = match[1]] = [];
    } else if (line && section) {
        manifest[section].push(line);
    }
}
/*
 * toolFiles(dir) returns the files (not the folders) in src/tools/dir.
 */
const toolFiles = (dir) => globSync(SRC + "/tools/" + dir + "/*").sort().filter((file) =>
    !fs.statSync(file).isDirectory());

//
// The distribution diskette and the demo diskettes have only EXT (CMD, BAS, and DLL) and DEMOS; the tests are on the
// TESTS diskette, so that no other diskette has to make room for them.
//
const distFolders = { "EXT/CMD": manifest["EXT/CMD"], "EXT/BAS": manifest["EXT/BAS"], "EXT/DLL": manifest["EXT/DLL"], DEMOS: manifest.DEMOS };
//
// The demo diskettes (every diskette except the distribution diskette) leave out CLAUDE.BAS, which needs a gateway
// on COM2 that the demo pages don't have, so that they have room for everything else.
//
const demoFolders = { ...distFolders, "EXT/BAS": manifest["EXT/BAS"].filter(file => !/(^|\/)CLAUDE\.BAS$/i.test(file)) };
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
    let diskFile = diskName.endsWith(".json")? diskName : "./disks/historical/dos/" + diskName + ".json";
    let diskDir = "./tools/pc/disks/" + path.basename(diskFile, ".json");
    if (!fs.existsSync(diskDir)) {
        execSync("node \"" + process.env["PCJS"] + "/tools/diskimage/diskimage.js\" " + diskFile + " --extract --dest=" + diskDir, { stdio: "ignore" });
    }
    return fileSpecs.map(fileSpec => diskDir + "/" + fileSpec);
}

let disks = {
    "BASICDOS-360K": {
        config: "./disks/downloads/CONFIG.SYS",
        label: "BASIC-DOS",
        title: "BASIC-DOS " + VERSION + " (Release)",
        folders: distFolders,
        img: true,
        final: true
    },
    "BASICDOS-360K-S80": { config: "./machines/demos/bd/s80/CONFIG.SYS", title: "BASIC-DOS Single" },
    "BASICDOS-360K-D40": { config: "./machines/demos/bd/d40/CONFIG.SYS", title: "BASIC-DOS 40-Cols" },
    "BASICDOS-360K-D80": { config: "./machines/demos/bd/d80/CONFIG.SYS", title: "BASIC-DOS 80-Cols" },
    "BASICDOS-360K-P80": { config: "./machines/demos/bd/p80/CONFIG.SYS", title: "BASIC-DOS Multi-Page" },
    "BASICDOS-360K-P80PM": { config: "./machines/demos/bd/mmu/CONFIG.SYS", title: "BASIC-DOS Extended Memory" },
    "BASICDOS-360K-DUAL": { config: "./machines/demos/bd/dual/CONFIG.SYS", title: "BASIC-DOS Dual Monitor" },
    "BASICDOS-360K-MULTI": { config: "./machines/demos/bd/dual/multi/CONFIG.SYS", title: "BASIC-DOS Multi-Console" },
    "BASICDOS-360K-SERIAL": { config: "./machines/demos/bd/serial/CONFIG.SYS", title: "BASIC-DOS HD Serial Port" },
    "BASICDOS-360K-VT100": { config: "./machines/demos/bd/vt100/CONFIG.SYS", title: "BASIC-DOS HD VT100" },
    "BASICDOS-360K-DEBUG": { config: "./machines/demos/bd/debug/CONFIG.SYS", title: "BASIC-DOS Serial Debugger" },
    "BASICDOS-360K-MOUSE": { config: "./machines/demos/bd/mouse/CONFIG.SYS", title: "BASIC-DOS Mouse" },
    "BASICDOS-360K-M64": { config: "./machines/demos/bd/m64/CONFIG.SYS", title: "BASIC-DOS Monochrome", final: true, folders: demoFolders },
    "BASICDOS-360K-REAL": { config: "./machines/demos/bd/m64/hd/CONFIG.SYS", title: "BASIC-DOS HD Real Mode" },
    "BASICDOS-360K-WOLF3D": { config: "./machines/demos/bd/wolf3d/CONFIG.SYS", title: "BASIC-DOS Wolf3D" },
    "BASICDOS-360K-TERM": { config: "./machines/demos/bd/term/CONFIG.SYS", title: "BASIC-DOS Terminal", final: true, folders: demoFolders },
    "BASICDOS-360K-TERMHD": { config: "./machines/demos/bd/term/hd/CONFIG.SYS", title: "BASIC-DOS HD Terminal" },
    "BASICDOS-360K-TERM2": { config: "./machines/demos/bd/term/dual/CONFIG.SYS", title: "BASIC-DOS HD Multi-Terminal" },
    "BASICDOS-360K-MMU": { config: "./machines/demos/bd/mmu/vt100/CONFIG.SYS", title: "BASIC-DOS Extended Memory VT100" },
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
    "BASICDOS-20MB": {
        hd: true,
        config: "./machines/demos/bd/hd/CONFIG.SYS",
        folders: {
            ...distFolders,
            //
            // WOLF3D.BAT runs the game in DEMOS/WOLF3D, so only this disk gets it; the demos in src/demos/other
            // (eg, CLOCK.BAS, TETRIS.BAS, and PUBLIC.zip's JIVE.EXE) are on this disk only, too
            //
            DEMOS: manifest.DEMOS.concat([ "./machines/demos/bd/wolf3d/WOLF3D.BAT", "./src/demos/other/*.BA?", "./src/demos/other/PUBLIC.zip" ]),
            "DEMOS/WOLF3D": manifest["DEMOS/WOLF3D"],
            SRC: SRC + "/os",           // the BASIC-DOS source (with an MK.BAT that builds it on BASIC-DOS)
            TESTS: manifest.TESTS,
            "TESTS/REGRESS": manifest["TESTS/REGRESS"],
            "TESTS/MISC": manifest["TESTS/MISC"],
            "TESTS/SAMPLES": manifest["TESTS/SAMPLES"],
            //
            // The tools in src/tools/dos (see src/tools/README.TXT), overlaid with the BASIC-DOS versions in
            // src/tools/bd (eg, MASM, MAKE, and LINK4; mk.sh gets the same result from the order of its PATH$), and then
            // the manifest's TOOLS (eg, MSBASIC).
            //
            // All of those go in TOOLS/BIN (which the hard disk configurations add to PATH$); TOOLS itself has
            // only README.TXT.
            //
            TOOLS: [ SRC + "/tools/README.TXT" ],
            "TOOLS/BIN": toolFiles("dos").concat(toolFiles("os2"), toolFiles("bd"), manifest.TOOLS),
            //
            // The C compiler's include files and libraries; the BASIC-DOS libraries replace the originals with the
            // same names, just as the BASIC-DOS tools do.  The 386 C compiler's are in their 386 subfolders, where
            // the library is the original, and the BASIC-DOS startup code (BDCRT386.OBJ) is added to it.
            //
            "TOOLS/INCLUDE": [ SRC + "/tools/dos/include/*" ],
            "TOOLS/INCLUDE/SYS": [ SRC + "/tools/dos/include/SYS/*" ],
            "TOOLS/INCLUDE/386": [ SRC + "/tools/os2/include/*" ],
            "TOOLS/INCLUDE/386/SYS": [ SRC + "/tools/os2/include/SYS/*" ],
            "TOOLS/LIB": [ SRC + "/tools/dos/lib/*", SRC + "/tools/bd/lib/*" ],
            "TOOLS/LIB/386": [ SRC + "/tools/os2/lib/*", SRC + "/tools/bd/lib/386/*" ],
            //
            // The BASIC-DOS C startup code and floating-point library sources (with a test), the source of STUB.EXE,
            // and the C demos (HELLO is the sample that explains each step); all but the first have a makefile that
            // builds a program there, and the demos also have MAKE386, which builds them with the 386 C compiler.
            // SUCKS gets everything in its folder (MAKEBDC is its makefile for BDC) but README.md (README.TXT is the
            // version for the disk).
            //
            "TOOLS/CRT": [ SRC + "/tools/bd/crt/*" ],
            "TOOLS/FP": [ SRC + "/tools/bd/fp/*" ],
            "TOOLS/STUB": [ SRC + "/tools/bd/stub/*" ],
            "TOOLS/BDC": [ SRC + "/tools/bd/bdc/*" ],             // the BASIC-DOS C compiler's source (BDC.EXE is in TOOLS/BIN)
            "TOOLS/DEMOS/HELLO": [ SRC + "/tools/bd/demos/hello/*" ],
            "TOOLS/DEMOS/SUCKS": [ SRC + "/tools/bd/demos/sucks/*.c", SRC + "/tools/bd/demos/sucks/*.def", SRC + "/tools/bd/demos/sucks/make*", SRC + "/tools/bd/demos/sucks/README.TXT" ]
        }
    }
};

/**
 * binPath(mode, fileSpec)
 *
 * Returns the path of a build output (a file spec for an OBJ or BIN folder in src) for the given build mode, which is
 * the saved copy (see SAVED) if that mode isn't the current one; any other spec is unchanged.
 *
 * @param {string} mode
 * @param {string} fileSpec
 * @returns {string}
 */
function binPath(mode, fileSpec)
{
    let match = path.normalize(fileSpec).match(/^src\/(.*\/(obj|bin)\/[^\/]+)$/i);
    return match && mode != MODE? path.join(SAVED, mode, match[1]) : fileSpec;
}

/**
 * stageDir(diskName, mode)
 *
 * Returns the staging directory for a disk of the given build mode's set (tools/pc/disks/diskName for FINAL, and
 * tools/pc/disks/diskName-DEBUG for DEBUG).
 *
 * @param {string} diskName
 * @param {string} mode
 * @returns {string}
 */
const stageDir = (diskName, mode) => "./tools/pc/disks/" + diskName + (mode == "FINAL"? "" : "-" + mode);

/**
 * stageDisk(diskName, mode)
 *
 * Copies the files for a BASIC-DOS disk (see "disks" above), with the given build mode's binaries, to a staging
 * directory (see stageDir()), and returns the root entries in the order they should appear on the disk.
 *
 * @param {string} diskName
 * @param {string} mode
 * @returns {Array.<string>}
 */
function stageDisk(diskName, mode)
{
    let disk = disks[diskName];
    let dirStage = stageDir(diskName, mode);
    fs.rmSync(dirStage, { recursive: true, force: true });
    fs.mkdirSync(dirStage, { recursive: true });
    let entries = [];
    let distSpecs = new Set(manifest.ROOT.concat(manifest["EXT/CMD"], manifest["EXT/BAS"], manifest["EXT/DLL"], manifest.DEMOS));
    let copyFiles = function(fileSpecs, dirTarget, name, dist = false) {
        for (let fileSpec of fileSpecs) {
            let image = fileSpec.match(/^(.*\.json)\/(.*)$/);
            if (image) fileSpec = diskFiles(image[1], [image[2]])[0];
            let source = binPath(mode, fileSpec);
            let files = source.indexOf('*') >= 0? globSync(source).sort() : [source];
            for (let file of files) {
                /*
                 * A wildcard doesn't include folders (eg, the C compiler's lib and include folders in
                 * src/tools/dos), which a disk lists as folders of their own.
                 */
                if (fileSpec.indexOf('*') >= 0 && fs.statSync(file).isDirectory()) continue;
                let target = path.join(dirTarget, name || path.basename(file));
                if (!name && path.extname(file).toLowerCase() == ".zip") {
                    execSync("unzip -q -o \"" + file + "\" -d \"" + dirTarget + "\"");
                } else {
                    fs.cpSync(file, target, { preserveTimestamps: true });
                    if (dist || distSpecs.has(fileSpec)) fs.utimesSync(target, DIST_DATE, DIST_DATE);
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
        copyFiles([disk.config], dirStage, "CONFIG.SYS", true);
        let launchesAutoexec = fs.readFileSync(disk.config, "utf8").split(/\r?\n/).some(line =>
            /^SHELL=/i.test(line) && /\bAUTOEXEC(?:\.BAT)?\b/i.test(line));
        if (disk.autoexec && launchesAutoexec) copyFiles([disk.autoexec], dirStage, "AUTOEXEC.BAT", true);
    }
    /*
     * MK.BAT (in SRC, and in SRC\SDK) builds FINAL binaries unless there's an MKDEBUG file in the root directory, so
     * the hard disk gets one if its binaries are DEBUG.
     */
    if (disk.hd && mode == "DEBUG") {
        fs.writeFileSync(path.join(dirStage, "MKDEBUG"), "");
        fs.utimesSync(path.join(dirStage, "MKDEBUG"), DIST_DATE, DIST_DATE);
        entries.push(path.join(dirStage, "MKDEBUG"));
    }
    let folders = disk.folders || demoFolders;
    for (let folder in folders) {
        let files = folders[folder];
        if (!files.length) continue;
        let dirTarget = path.join(dirStage, folder);
        if (typeof files == "string") {
            /*
             * Copy the directory (including its OBJ directories, so that MK rebuilds only what changes), except
             * for hidden files, README.md files (which describe each folder in the repository), and the MS-DOS
             * build's mkdos.bat files (which chain from one subdirectory to the next); the mk.bat at the top builds
             * everything.
             */
            fs.cpSync(files, dirTarget, { recursive: true, filter: (src) => {
                let name = path.basename(src).toUpperCase();
                return name[0] != '.' && name != "README.MD" && name != "MKDOS.BAT";
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
        //
        // A subfolder is part of its folder's entry, which a disk may not list on its own (eg, a demo diskette's TESTS).
        //
        let dirTop = path.join(dirStage, folder.split('/')[0]);
        if (!entries.includes(dirTop)) entries.push(dirTop);
    }
    /*
     * The distribution folders get the distribution date, too, once nothing else will be copied into them.
     */
    for (let folder of ["EXT/CMD", "EXT/BAS", "EXT/DLL", "EXT", "DEMOS"]) {
        let dirTarget = path.join(dirStage, folder);
        if (fs.existsSync(dirTarget)) fs.utimesSync(dirTarget, DIST_DATE, DIST_DATE);
    }
    return entries;
}

/**
 * buildDisk(diskName, mode, diskImage)
 *
 * Returns a gulp task function that stages the files for a BASIC-DOS disk with the given build mode's binaries and
 * then builds the disk image: a hard disk with pc.js, or a 360K diskette with diskimage.js (which requires PCJS).
 *
 * @param {string} diskName
 * @param {string} mode
 * @param {string} diskImage
 * @returns {function(function(Error=))}
 */
function buildDisk(diskName, mode, diskImage)
{
    return function(done) {
        let entries = stageDisk(diskName, mode);
        let dirStage = stageDir(diskName, mode);
        let label = disks[diskName].label || diskName.replace(/^BASICDOS-(360K-)?/, "BD-");
        /*
         * The disk is built as diskNew, which replaces diskImage only if the build mode didn't change while its
         * binaries were read (see readMode()).
         */
        let diskNew = dirStage + "-new.json";
        fs.mkdirSync(path.dirname(diskImage), { recursive: true });
        let cmd;
        if (disks[diskName].hd) {
            //
            // pc.js adds the system files (and CONFIG.SYS) itself, so it dates them (see DIST_TIME).
            //
            cmd = "node ./tools/pc/pc.js ibm5160 " + dirStage + " --sys=bd:2 --sysdate=" + DIST_TIME + " --drivetype=615:4:17 --fat=16:2048 --normalize --bare --label=" + label +
                  " --order=" + entries.map(entry => path.basename(entry)).join(",") + " --save=" + diskNew;
        } else {
            cmd = "node \"" + process.env["PCJS"] + "/tools/diskimage/diskimage.js\" --files " + entries.join(",") +
                  (disks[diskName].data? "" : " --boot " + binPath(mode, SRC + "/os/boot/obj/BOOT1.COM") + " --attr=" + SYSATTRS) +
                  " --output " + diskNew +
                  " --label=" + label + " --labeldate=" + DIST_TIME + " --normalize --writable --target=360 --overwrite" + DIQUIET;
        }
        /*
         * The staging directory is needed only to build the disk, so it's removed once the build succeeds (if the
         * build fails, it's left for inspection).
         */
        run(cmd)(function(err) {
            if (!err && readMode() != MODE) {
                fs.rmSync(diskNew, { force: true });
                err = new Error("build mode changed while building " + diskName + ", so it wasn't updated");
            }
            if (err) {
                done(err);
                return;
            }
            fs.renameSync(diskNew, diskImage);
            fs.rmSync(dirStage, { recursive: true, force: true });
            if (!disks[diskName].img) {
                done();
                return;
            }
            run("node \"" + process.env["PCJS"] + "/tools/diskimage/diskimage.js\" --disk=" + diskImage +
                " --output=" + diskImage.replace(/\.json$/, ".img") + " --writable --overwrite" + DIQUIET)(done);
        });
    };
}

/**
 * writeDiskettes(done)
 *
 * Writes the titled diskettes (see "disks" above) to machines/pcx86/basicdos-diskettes.json, which maps each diskette
 * path to its title; since Jekyll's data_dir is "machines", _includes/machine.html adds them to every FDC's list.  It
 * also writes machines/pcx86/basicdos-configs.json, which maps each disk's name to its CONFIG.SYS, for the pages whose
 * machines boot a disk whose CONFIG.SYS is in another folder (eg, {{ site.data.pcx86.basicdos-configs.BASICDOS-20MB }}
 * on the Wolfenstein 3D pages), since include_relative can't reach another folder.  And it writes
 * machines/pcx86/basicdos-diskettes-debug.json, which maps the path of every disk in disks/debug (ie, every disk that
 * isn't marked "final") to its title (or its name, if it has none), which a page on a developer server uses when its URL
 * has "?debug=true" (see _includes/scripts.html).
 *
 * @param {function(Error=)} done
 */
function writeDiskettes(done)
{
    let diskettes = {}, debugDisks = {}, configs = {};
    for (let diskName in disks) {
        let disk = disks[diskName];
        if (disk.title) diskettes["/disks/current/" + diskName + ".json"] = disk.title;
        if (!disk.final) debugDisks[SETS.DEBUG.replace(/^\./, "") + "/" + diskName + ".json"] = disk.title || diskName;
        if (disk.config) configs[diskName] = fs.readFileSync(disk.config, "utf8");
    }
    let writeData = function(file, data) {
        let text = JSON.stringify(data, null, 2) + "\n";
        if (!fs.existsSync(file) || fs.readFileSync(file, "utf8") != text) fs.writeFileSync(file, text);
    };
    writeData("./machines/pcx86/basicdos-diskettes.json", diskettes);
    writeData("./machines/pcx86/basicdos-diskettes-debug.json", debugDisks);
    writeData("./machines/pcx86/basicdos-configs.json", configs);
    done();
}
gulp.task("diskettes", writeDiskettes);

/**
 * diskSources(diskName, mode)
 *
 * Returns the files that a BASIC-DOS disk of the given build mode's set is built from, as stageDisk() and buildDisk()
 * use them: paths that may contain wildcards, where a folder that's copied whole (eg, the hard disk's SRC) ends with
 * "/**", and build outputs are the mode's (see binPath()).  Files that come from inside another disk image aren't
 * included.
 *
 * @param {string} diskName
 * @param {string} mode
 * @returns {Array.<string>}
 */
function diskSources(diskName, mode)
{
    let disk = disks[diskName];
    let sources = [disk.config, disk.autoexec];
    if (!disk.data && !disk.hd) {
        sources.push(...manifest.ROOT.filter(file => file != "CONFIG.SYS"), SRC + "/os/boot/obj/BOOT1.COM");
    }
    let folders = disk.folders || demoFolders;
    for (let folder in folders) {
        let files = folders[folder];
        if (typeof files == "string") sources.push(files + "/**"); else sources.push(...files);
    }
    return sources.filter(file => file && !/\.json\//.test(file)).map(file => binPath(mode, file));
}

/**
 * isAffected(diskName, mode, files)
 *
 * Returns true if any of the given files (resolved paths) is one that the disk of the given build mode's set is built
 * from; a wildcard matches by name, so a file that's been deleted, or added since the last build, still counts.
 *
 * @param {string} diskName
 * @param {string} mode
 * @param {Array.<string>} files
 * @returns {boolean}
 */
function isAffected(diskName, mode, files)
{
    return diskSources(diskName, mode).some(source => {
        let re = new RegExp("^" + path.resolve(source).replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*\*/g, "\0").replace(/\*/g, "[^/]*").replace(/\?/g, "[^/]").replace(/\0/g, ".*") + "$", "i");
        return files.some(file => re.test(file));
    });
}

/*
 * The "watch" task (below) runs "demos" with the files that changed in BD_CHANGED (one path per line, or "*" if there
 * were too many to list), so that only the disks (of either set) built from those files are rebuilt; a change to one
 * of WATCHALL (the files that define what's on every disk) rebuilds them all.
 */
const WATCHALL = [ "./manifest.txt", "./gulpfile.js", "./package.json" ];
let changed = process.env["BD_CHANGED"]? process.env["BD_CHANGED"].split("\n").map(file => path.resolve(file)) : null;
let changedAll = changed && (process.env["BD_CHANGED"] == "*" || WATCHALL.some(file => changed.includes(path.resolve(file))));

/*
 * demoTasks updates the current mode's set (or with BD_CHANGED, the disks of both sets that the changes affect), and
 * buildTasks updates both sets.  A set whose mode isn't the current one is built only if that mode's binaries were
 * saved, and it doesn't get the hard disk (see above).
 */
let demoTasks = ["diskettes"], buildTasks = ["diskettes"];
for (let mode in SETS) {
    if (SWITCHING) break;               // the binaries may be from either mode (see readMode())
    if (mode != MODE && !fs.existsSync(path.join(SAVED, mode))) continue;
    for (let diskName in disks) {
        let disk = disks[diskName];
        if (mode != "FINAL" && disk.final) continue;
        if (mode != MODE && disk.hd) continue;
        let buildTask = SETS[mode].replace(/^.*\//, "") + "/" + diskName;
        let diskImage = SETS[mode] + "/" + diskName + ".json";
        gulp.task(buildTask, checkOutput(buildDisk(diskName, mode, diskImage), diskImage));
        buildTasks.push(buildTask);
        if (changed? changedAll || isAffected(diskName, mode, changed) : mode == MODE) demoTasks.push(buildTask);
    }
}

if (process.env["BD_CHANGED"]) {
    console.log(demoTasks.length > 1? "updating " + demoTasks.slice(1).join(", ") : "no disks to update");
}

/*
 * "gulp build" (or simply "gulp") rebuilds every disk on demand, and "gulp watch" rebuilds the disks that a file is
 * on whenever the file changes (eg, a BAS file in DEMOS, a CONFIG.SYS, or the binaries of a new build), 2 seconds
 * after the last change.  Each update is a separate "gulp demos", so that it uses the current manifest, build mode,
 * and version, and if files change during an update, another one follows it.  An update waits while the build mode is
 * SWITCHING, and if the mode changes during an update (whose disks then may not have been updated), every disk of both
 * sets is updated next.  While updates are pending or running, WATCHBUSY exists, so that setMode (in tools/release.sh)
 * can wait for them to finish before it swaps the build outputs (eg, between the builds of "mk.sh all").
 *
 * WATCHED covers more than the disks use, since the manifest can list any file in those folders; the test
 * configurations (src/configs, which tools/tests/prep.sh fills) aren't on any disk, so they're ignored,
 * as are hidden files.  A pc.js build writes its outputs back to src only when it exits, so an update never
 * sees a build that's still running.
 *
 * While it runs, the watcher's process ID is in WATCHPID, which tells mk.sh and mkdos.sh that they don't need to run
 * "gulp demos" themselves (see watching() in tools/release.sh).
 */
const WATCHED = WATCHALL.concat([ SRC + "/**", "./machines/demos/**", "./disks/downloads/**" ]);
const WATCHPID = "./tools/pc/disks/watch.pid";
const WATCHBUSY = "./tools/pc/disks/watch.busy";

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
    let setBusy = (busy) => busy? fs.writeFileSync(WATCHBUSY, "") : fs.rmSync(WATCHBUSY, { force: true });
    process.on("exit", () => { fs.rmSync(WATCHPID, { force: true }); setBusy(false); });
    for (let signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(signal, () => process.exit());
    let files = new Set(), timer = null, running = false;
    let schedule = () => { clearTimeout(timer); timer = setTimeout(update, 2000); };
    let update = function() {
        if (running) return;            // (the update in progress schedules the next one)
        if (!files.size) return setBusy(false);
        let mode = readMode();
        if (mode == "SWITCHING") return schedule();
        let list = [...files];
        files.clear();
        running = true;
        let env = Object.assign({}, process.env, { BD_CHANGED: list.length > 2000 || list.includes("*")? "*" : list.join("\n") });
        spawn("npx gulp demos --silent" + (VERBOSE? " --verbose" : ""), { shell: true, stdio: "inherit", env }).on("close", (code) => {
            running = false;
            if (readMode() != mode) {
                files.add("*");
            } else if (code) {
                console.log("error: unable to update the disks (run \"npx gulp demos\" for details)");
            }
            if (files.size) schedule(); else setBusy(false);
        });
    };
    let watcher = gulp.watch(WATCHED, {
        ignored: (file) => /(^|\/)\.[^\/.]/.test(file) || /(^|\/)src\/configs\//.test(file)
    });
    watcher.on("all", (event, file) => { files.add(file); setBusy(true); schedule(); });
    return watcher;
});
gulp.task("demos", gulp.series(demoTasks));
gulp.task("build", gulp.series(buildTasks));
gulp.task("default", gulp.series("build"));
