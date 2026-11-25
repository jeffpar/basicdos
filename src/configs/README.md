## BASIC-DOS Test Configurations

Each folder in [console/serial](console/serial/) is the root of a test disk that pc.js builds, with its console on COM1: [fpe](console/serial/fpe/) (a floppy, without an FPU), [fpu](console/serial/fpu/) (a floppy, with an FPU), [hd](console/serial/hd/) (a 10Mb hard disk), and [m64](console/serial/m64/) (a floppy for evaluating a 64K machine).  `boot.sh` boots the first three, `tools/tests/quick.sh` tests them, and `tools/tests/prep.sh` copies the latest binaries and test files into them first.  [mk](mk/) isn't a disk; its CONFIG.SYS is the one that `mk.sh` gives pc.js (with `--config`) for the hard disk that it builds BASIC-DOS on.

Only each configuration's CONFIG.SYS and AUTOEXEC.BAT are tracked (see [.gitignore](.gitignore)).  The configuration folders have no README files, since everything in them goes on their disks.
