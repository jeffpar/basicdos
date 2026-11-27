## BASIC-DOS Operating System

This directory contains the sources for everything on a BASIC-DOS distribution disk: the boot sector ([boot](boot/)), the built-in device drivers ([dev](dev/)), the kernel ([dos](dos/)), the command shell ([cmd](cmd/)), the installable device drivers ([dd](dd/)), the external utilities ([util](util/)), the NE libraries ([dll](dll/)), and the fonts that MODE FONT loads ([fonts](fonts/)), along with their shared include files ([inc](inc/)) and the [sdk](sdk/) sample programs.

Each component has its own makefile and builds into its own `OBJ` folder.  [mk.bat](mk.bat) builds them all on BASIC-DOS (it's **SRC\\MK.BAT** on the BASICDOS-20MB disk, and `mk.sh` runs it); on MS-DOS, `mkdos.sh` uses the **MKDOS.BAT** file in each folder instead, which runs that folder's makefile and then chains to the next folder.
