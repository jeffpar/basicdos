## BASIC-DOS Built-in Device Drivers

This directory contains the built-in device drivers, one per `*dev.asm` file (with a few helper modules, eg, `convid.asm` for the video side of the VKD$ console driver): two CPU$ drivers (`386dev.asm` for an 80286 or later, and `x86dev.asm`, which stays only when the first one doesn't), and drivers for the NUL device, the console (VKD$), serial ports, printers, the clock, floppy and hard disk controllers, pipes, the FPU, the mouse, and sound.

Each driver builds as a separate `.COM` file, and the makefile concatenates them into `BASDEV.COM`, the first system file, with `BOOT2.COM` (from [boot](../boot/)) at the start and `DEVINIT.COM` (from `devinit.asm`, which initializes each driver and removes the ones that aren't needed, followed by `multicfg.asm`, which processes CONFIG.SYS's startup menus and blocks, and is overwritten once it has) at the end.
