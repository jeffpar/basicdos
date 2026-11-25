## BASIC-DOS Boot Code

`boot.asm` builds `BOOT.COM` (copied to `BOOT1.COM`), which contains the BASIC-DOS boot sector followed by the boot code that doesn't fit in it.  `wboot.asm` builds `WBOOT.COM`, which writes the first 512 bytes of `BOOT1.COM` to the boot sector of the diskette in drive A: (unless `/N` is given) and writes the rest to `BOOT2.COM`, which the [dev](../dev/) makefile puts at the start of `BASDEV.COM`.

`WBOOT.COM` is a build tool, not a distribution file.
