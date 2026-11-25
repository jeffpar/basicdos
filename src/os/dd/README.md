## BASIC-DOS Installable Device Drivers

This directory contains the installable device drivers, which CONFIG.SYS loads with `DEVICE=` lines.  Each driver has its own subdirectory, with its own makefile and `OBJ` folder; currently, the only one is [dbg](dbg/), the serial debugger (`DEBUG.COM`).
