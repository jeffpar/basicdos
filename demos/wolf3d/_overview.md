This demo runs a real DOS program, Wolfenstein 3D, on BASIC-DOS.  The game is an LZEXE-compressed EXE file built with Borland C++, so it exercises BASIC-DOS's EXE loader, its DOS file functions (open, read, seek, findfirst, and IOCTL), its memory functions (allocate, free, and resize), and its interrupt vector functions, while the game itself takes over the keyboard, the timer, the VGA, and the Sound Blaster directly.

The WOLF3D.BAT file in the DEMOS directory changes to DEMOS\WOLF3D, runs WOLF3D.EXE, and returns to the root directory when the game exits.  The game needs roughly 528K of free conventional memory, so BASIC-DOS gives it all the memory it asks for, less 64K for every other session that has a program loaded.  The hard disk is the same BASICDOS-10MB disk that the [10Mb Hard Disk](../../hd/386/) demo uses, but the machine boots a diskette whose CONFIG.SYS has a `CPU=8088` line, since the game, like any MZ EXE file, runs only in real mode, and on an 80286 or later, BASIC-DOS otherwise runs in protected mode.

### **CONFIG.SYS** from the BASIC-DOS Wolf3D Diskette

```
{% include_relative CONFIG.SYS %}
```
