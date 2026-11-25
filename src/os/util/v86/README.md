## BASIC-DOS V86 Utility

This directory contains the sources for `V86.COM` (`V86 [PATH$="path"[:]] [/M:size] [program [arguments]]`), which runs a real-mode program (COMMAND.COM by default) in a V86 machine on an 80386 in protected mode.  `v86.asm` sets up the machine, and the other modules handle its DOS calls (`v86dos.asm`), BIOS calls (`v86bios.asm`, which translates them into console IOCTLs), hardware (`v86hw.asm`), and processor events (`v86proc.asm`).
