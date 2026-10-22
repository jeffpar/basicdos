#
# Sourced (from the repository root) by mk.sh and mkdos.sh, which take their defaults from package.json:
#
#   "version"   the major and minor numbers (eg, 2.0 of "2.0.0") are the BASIC-DOS version, which this script copies to
#               VERSION_MAJOR (0-9) and VERSION_MINOR (0-99) in software/src/os/inc/version.inc whenever they change
#               (only then, since the makefiles depend on it); the minor number is displayed with two digits, so
#               "2.1.0" is BASIC-DOS 2.01, and "2.10.0" is 2.10
#   "config"    its "release" property ("final" or "debug") is the default build mode, which this script sets $release to
#               (in upper case); it's in "config" because VS Code's package.json schema expects a top-level "release"
#               property to be an object (semantic-release's configuration)
#
read -r version release < <(node -e 'const p = require("./package.json"); console.log(p.version, p.config?.release)')
if [[ ! $version =~ ^([0-9])\.([0-9]{1,2})(\.|$) ]]; then
    echo "error: package.json version \"$version\" must begin with major.minor (0-9.0-99)" >&2
    exit 1
fi
major=${BASH_REMATCH[1]}
minor=$((10#${BASH_REMATCH[2]}))
release=$(echo "$release" | tr a-z A-Z)
if [ "$release" != FINAL ] && [ "$release" != DEBUG ]; then
    echo "error: package.json config.release must be \"final\" or \"debug\"" >&2
    exit 1
fi
inc=software/src/os/inc/version.inc
if ! grep -q "^VERSION_MAJOR	equ	$major	" $inc || ! grep -q "^VERSION_MINOR	equ	$minor	" $inc; then
    sed -e "s/^\(VERSION_MAJOR	equ	\)[0-9]*/\1$major/" -e "s/^\(VERSION_MINOR	equ	\)[0-9]*/\1$minor/" $inc > $inc.tmp &&
        mv $inc.tmp $inc || exit 1
    echo "BASIC-DOS version set to $major.$(printf %02d $minor)"
fi
