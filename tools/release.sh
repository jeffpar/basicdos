#
# Sourced (from the repository root) by mk.sh and mkdos.sh, which take the BASIC-DOS version from package.json's
# "version": its major, minor, and patch numbers (eg, 2, 11, and 1 of "2.11.1") are the BASIC-DOS version and revision,
# which this script copies to VERSION_MAJOR (0-9), VERSION_MINOR (0-99), and VERSION_REV (0-26) in
# src/os/inc/version.inc whenever they change (only then, since the modules that include it depend on it, so any
# change rebuilds them); the minor number is displayed with two digits, and a nonzero revision as a letter (1 is A,
# 26 is Z), so "2.1.0" is BASIC-DOS 2.01, and "2.11.1" is 2.11A.
#
read -r version < <(node -e 'console.log(require("./package.json").version)')
if [[ ! $version =~ ^([0-9])\.([0-9]{1,2})\.([0-9]{1,2})$ ]] || [ $((10#${BASH_REMATCH[3]})) -gt 26 ]; then
    echo "error: package.json version \"$version\" must be major.minor.revision (0-9.0-99.0-26)" >&2
    exit 1
fi
major=${BASH_REMATCH[1]}
minor=$((10#${BASH_REMATCH[2]}))
rev=$((10#${BASH_REMATCH[3]}))
inc=src/os/inc/version.inc
if ! grep -q "^VERSION_MAJOR	equ	$major	" $inc || ! grep -q "^VERSION_MINOR	equ	$minor	" $inc ||
        ! grep -q "^VERSION_REV	equ	$rev	" $inc; then
    sed -e "s/^\(VERSION_MAJOR	equ	\)[0-9]*/\1$major/" -e "s/^\(VERSION_MINOR	equ	\)[0-9]*/\1$minor/" \
        -e "s/^\(VERSION_REV	equ	\)[0-9]*/\1$rev/" $inc > $inc.tmp && mv $inc.tmp $inc || exit 1
    letter=
    [ $rev -gt 0 ] && letter=$(printf "\\$(printf %o $((64 + rev)))")
    echo "BASIC-DOS version set to $major.$(printf %02d $minor)$letter"
fi
#
# watching
#
# Succeeds if "gulp watch" is running (its process ID is in tools/pc/disks/watch.pid; see gulpfile.js), in which case
# it updates the disk images when a build's outputs change, so mk.sh and mkdos.sh don't have to.
#
watching() {
    local pid
    pid=$(cat tools/pc/disks/watch.pid 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}
#
# getModes [mode]
#
# Sets $modes to the build modes that mk.sh or mkdos.sh should build, in order, for the given mode (in any case):
# FINAL, DEBUG, or ALL (the default), which builds DEBUG first and then FINAL, so that FINAL is the current mode
# afterward.  Any other mode fails.
#
getModes() {
    case "$(echo "${1:-ALL}" | tr a-z A-Z)" in
        FINAL) modes=FINAL ;;
        DEBUG) modes=DEBUG ;;
        ALL) modes="DEBUG FINAL" ;;
        *) return 1 ;;
    esac
}
#
# waitWatch
#
# Waits while "gulp watch" has disk updates pending or running (it keeps tools/pc/disks/watch.busy while it does; see
# gulpfile.js), or any "gulp demos" is running, after giving the watcher a few seconds to see the files that a build
# just wrote, so that setMode doesn't swap the build outputs while the last mode's disks are still being updated (eg,
# between the builds of "mk.sh all").  It gives up after 10 minutes.
#
waitWatch() {
    local n=0
    watching && sleep 3
    while { [ -e tools/pc/disks/watch.busy ] && watching; } || pgrep -f "gulp demos" > /dev/null; do
        [ $n -ge 600 ] && break
        sleep 1; n=$((n + 1))
    done
}
#
# setMode mode
#
# Records the build mode in tools/pc/disks/mkmode (which gulpfile.js also reads), and keeps each mode's build outputs
# (the OBJ folders, and tests/BIN) separately, so that switching modes doesn't rebuild everything: when the mode
# changes, each output folder is moved to tools/pc/disks/objs/<old mode>, and the new mode's folder is moved back from
# tools/pc/disks/objs/<new mode>, so MAKE sees that mode's last outputs (with their original timestamps) and rebuilds
# only what's changed since.  If the new mode has no saved folder yet, the old mode's outputs are copied instead (and
# left in place, so mk.sh can still boot them), and the folder's INCS file (which every module in the makefiles depends
# on) is deleted, so MAKE rebuilds everything in it (without touching any sources, which would make the other mode's
# saved outputs look out of date, too); if the last mode is unknown, its outputs aren't saved.
#
# While the folders move, mkmode says SWITCHING, so a disk update (gulp demos) that's already running can tell that
# the binaries it staged may be from either mode (see readMode() in gulpfile.js); if a switch fails, mkmode still says
# SWITCHING, so the next switch treats the last mode as unknown.
#
setMode() {
    local mode=$1 last dir src=src saved=tools/pc/disks/objs
    last=$(cat tools/pc/disks/mkmode 2>/dev/null)
    [ "$last" = "$mode" ] && return
    mkdir -p tools/pc/disks
    waitWatch
    echo SWITCHING > tools/pc/disks/mkmode || exit 1
    for dir in $(cd $src && find os tests msb -type d \( -iname obj -o -iname bin \) -prune); do
        if [ "$last" = FINAL ] || [ "$last" = DEBUG ]; then
            rm -rf "$saved/$last/$dir"
            mkdir -p "$saved/$last/$(dirname "$dir")" || exit 1
            if [ -d "$saved/$mode/$dir" ]; then
                mv "$src/$dir" "$saved/$last/$dir" && mv "$saved/$mode/$dir" "$src/$dir" || exit 1
                continue
            fi
            cp -Rp "$src/$dir" "$saved/$last/$dir" || exit 1
        fi
        find "$src/$dir" -maxdepth 1 -iname INCS -delete
    done
    echo "$mode" > tools/pc/disks/mkmode
}
#
# updateDisks
#
# After a successful build (if PCJS is set), updates the disk images of the build's mode (see gulpfile.js: FINAL
# builds update disks/current, and DEBUG builds disks/debug), unless "gulp watch" is running, which updates them itself
# a couple of seconds later.
#
updateDisks() {
    if [ -n "$PCJS" ] && ! watching && ! npx gulp demos --silent > /dev/null; then
        echo "error: unable to update the disks (run \"npx gulp demos\" for details)" >&2
        return 1
    fi
}
