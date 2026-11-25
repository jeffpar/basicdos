## BASIC-DOS Kernel

This directory contains the sources for `BASDOS.COM`, the BASIC-DOS kernel and second system file: the DOS interrupt entry points (`dosints.asm`), file, disk, FAT, and buffer services, memory, process, and session management, the NE and LE program loaders (`neload.asm` and `leload.asm`), support for ring 3 programs and protected-mode faults, and system initialization (`sysinit.asm`, which processes CONFIG.SYS, and `drvinit.asm`, which loads installable device drivers).

[basdos.lrf](basdos.lrf) gives the link order.  `sprintf.asm` is also linked into a few test programs in [tests](../../tests/).
