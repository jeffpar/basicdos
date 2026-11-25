---
layout: sheet
title: SYS
permalink: /docs/bdman/cmd/external/sys/
---

{% include header.html %}

> SYS *drive*: [/N]

Makes *drive* bootable without reformatting it: SYS copies BASDEV.COM, BASDOS.COM, and COMMAND.COM from the root directory of the system drive (the drive that COMMAND.COM was loaded from) to the root directory of *drive* (replacing any copies already there), makes them read-only system files (and BASDEV.COM and BASDOS.COM hidden), and gives *drive*'s boot sector the system drive's boot code, keeping *drive*'s disk parameters.

Since the boot code follows the system files' cluster chains, they don't have to be the first files on the drive, or contiguous, so SYS works on any FAT volume with room for them (including one formatted by another DOS).

### Removing the Boot Message

`/N` makes *drive* boot without displaying its boot message (`Diskette loading...`, or `Hard disk loading...` on a hard disk volume, which SYS sets either way) or waiting 2 seconds for a key.  It's the only way to do this, since the message appears before CONFIG.SYS is read.  SYS without `/N` restores the message and the wait, regardless of what the system drive's boot code does.

The boot code still checks once for a key, so **Esc**, `P`, `R`, or `-` still work if you press one while the machine is starting up, after its keyboard test.  Pressing a key too early, or holding one down from the start, stops the self-test with a `301` keyboard error.  For settings that apply to every boot, use [CPU=](../../../cfg/#cpu) and [SWITCHAR=](../../../cfg/#switchar) instead.

[FORMAT /S](../format/) also copies the system drive's boot code, so a disk formatted that way boots the same way as the system drive.

### Messages

- `System transferred`, if SYS succeeds
- `Cannot transfer the system to the system drive`
- `Drive` *drive* `doesn't have a FAT volume`
- `Drive` *drive* `doesn't have BASIC-DOS` *version* `boot code`, for the system drive, if its boot code isn't the running version of BASIC-DOS
- `Unable to copy` *file*
- `Write protect error`
- `Drive not ready`
- `Invalid drive`
- `Unable to transfer the system (error` *n*`)`, for any other error

A missing drive, an unknown switch, or any other argument that isn't a single drive is a [usage error](../../#usage-errors).

Source: [SYS.BAS](https://github.com/jeffpar/basicdos/blob/main/src/os/util/bas/SYS.BAS)

{% include footer.html prev="SORT:../sort/" next="TEE:../tee/" %}
