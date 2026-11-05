---
layout: sheet
title: SYS
permalink: /docs/bdman/cmd/external/sys/
---

{% include header.html %}

> SYS *drive*:

Makes *drive* bootable without reformatting it: SYS copies BASDEV.COM, BASDOS.COM, and COMMAND.COM from the root directory of the current drive to the root directory of *drive* (replacing any copies already there), makes them read-only system files (and BASDEV.COM and BASDOS.COM hidden), and gives *drive*'s boot sector the current drive's boot code, keeping *drive*'s disk parameters.

Since the boot code follows the system files' cluster chains, they don't have to be the first files on the drive, or contiguous, so SYS works on any FAT volume with room for them (including one formatted by another DOS).

### Messages

- `System transferred`, if SYS succeeds
- `Cannot transfer the system to the current drive`
- `Drive` *drive* `doesn't have a FAT volume`
- `Unable to copy` *file*
- `Write protect error`
- `Drive not ready`
- `Invalid drive`
- `Unable to transfer the system (error` *n*`)`, for any other error

A missing argument, or an argument that isn't a drive, displays `Syntax error`.

Source: [SYS.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/SYS.BAS)

{% include footer.html prev="SORT:../sort/" next="TEE:../tee/" %}
