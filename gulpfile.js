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
    "BDSRC": "./software/pcx86/src/BDSRC/**"
};

let files = [];
let tasks = [];
for (let diskName in disks) {
    let taskName = "build" + diskName;
    let diskDir = path.dirname(disks[diskName]);
    let diskImage = "./software/pcx86/disks/" + diskName + ".json";
    files.push(disks[diskName]);
    tasks.push(taskName);
    gulp.task(taskName, run("node /Users/jeff/Sites/pcjs/tools/modules/diskimage.js --dir " + diskDir + " --output " + diskImage + " --target=360 --overwrite"));
}

gulp.task("watch", function() {
    return gulp.watch(files, gulp.series(tasks));
});

gulp.task("default", gulp.series("watch"));
