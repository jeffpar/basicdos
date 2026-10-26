#!/bin/bash
#
# Usage: tools/pc/clean.sh [-n]
#
# Removes everything in tools/pc/disks that the rest of the project doesn't need: the disk images that pc.js builds
# (eg, BDV2.json), gulpfile.js's staging folders, the outputs of the test scripts (eg, bdhd, bench, and chkdsk), and any
# scratch folders and files, all of which are recreated as needed.  It keeps only:
#
#   objs, mkmode        the saved outputs of the other build mode, and the last build mode (see tools/release.sh)
#   MSDOS320-C400, PCDOS100, COMPAQ331-WOLF3D
#                       the disk contents that gulpfile.js extracts (see diskFiles())
#   hdsrc               the default hard disk folder of tools/tests/testhd.sh
#
# along with the folders that objs needs (ie, any empty folders in objs are removed too).  Use -n to list what would be
# removed without removing anything.  Since pc.js instances and builds use these files, nothing is removed while pc.js
# or a build or test script is running.
#
cd "$(dirname "$0")/disks" || exit 1
keep=" objs mkmode MSDOS320-C400 PCDOS100 COMPAQ331-WOLF3D hdsrc "
if [ "$1" != "-n" ] && pgrep -f 'tools/pc/pc\.js|mkdos\.sh|mk\.sh|quick\.sh|bench\.sh|testhd\.sh|chkdsk\.sh' > /dev/null; then
    echo "error: pc.js or a build or test script is running" >&2
    exit 1
fi
for f in * .[!.]*; do
    [ -e "$f" ] || continue
    case "$keep" in *" $f "*) continue ;; esac
    echo "$f"
    [ "$1" = "-n" ] || rm -rf "./$f"
done
[ "$1" = "-n" ] || [ ! -d objs ] || find objs -mindepth 1 -depth -type d -empty -delete
