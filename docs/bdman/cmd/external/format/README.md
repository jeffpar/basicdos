---
layout: sheet
title: FORMAT
permalink: /docs/bdman/cmd/external/format/
---

{% include header.html %}

> FORMAT *drive*: [/S] [/V[:*label*]] [/F:*size*] [/1] [/8]

Formats the diskette or hard disk volume in *drive*.  FORMAT can't format the current drive, which also supplies the boot sector and any system files.

- `/S` copies BASDEV.COM, BASDOS.COM, and COMMAND.COM from the root directory of the current drive, making the volume bootable, and makes BASDEV.COM and BASDOS.COM read-only hidden system files and COMMAND.COM a read-only system file
- `/V` gives the new volume a label, which FORMAT asks for (pressing ENTER leaves it without one), and `/V:`*label* gives it that label; a label has up to 11 characters, and can't include `* ? / \ | . , ; : + = [ ] < >` or `"`
- `/F:`*size* selects a diskette's size: `360`, `720`, or `1200`
- `/1` formats one side of a 360K diskette
- `/8` formats 8 sectors per track on a 360K diskette, for PC DOS 1.x

### Diskettes

FORMAT prompts for the diskette, formats and verifies every track (with the diskette driver's [IOCTL](../../basic/#ioctl) requests), writes the boot sector (a copy of the current drive's, with the new diskette's parameters), the two FATs, and the root directory, reports the space on the diskette, and asks whether to format another.

| Switches | Size | Cylinders | Sides | Sectors per track | Cluster size | Root entries |
|----------|------|-----------|-------|-------------------|--------------|--------------|
| `/F:360` | 360K | 40 | 2 | 9 | 1K | 112 |
| `/F:360 /1` | 180K | 40 | 1 | 9 | 512 | 64 |
| `/F:360 /8` | 320K | 40 | 2 | 8 | 1K | 112 |
| `/F:360 /1 /8` | 160K | 40 | 1 | 8 | 512 | 64 |
| `/F:720` | 720K | 80 | 2 | 9 | 1K | 112 |
| `/F:1200` | 1.2M | 80 | 2 | 15 | 512 | 224 |

Without `/F`, FORMAT uses the drive's own size, which the BIOS of a PC AT (or later) reports, and a PC or XT doesn't (so 360K), and a 1.44M drive formats 720K diskettes.  On a machine whose BIOS reports a drive's size, `/F:360` needs a 5.25-inch drive, `/F:720` a 3.5-inch drive, and `/F:1200` a high-capacity 5.25-inch drive.  Cluster sizes and root directory sizes follow the PC DOS 2.x rules, with 12-bit FATs, except that 1.2M diskettes get PC DOS 3.x's layout.

A write-protected diskette, an empty drive, or a track that can't be formatted (`Track` *n* `bad - disk unusable`) ends the format.

	FORMAT B: /V:WORK
	Insert new diskette for drive B:
	and strike any key when ready
	Formatting...Format complete

	 362496 bytes total disk space
	 362496 bytes available on disk

	Format another (Y/N)?

### Hard Disks

For a hard disk drive, FORMAT first displays the disk's geometry and partition table (each partition's type, starting sector, size, and drive letter, if it's a FAT volume).

If the disk has FAT volumes, FORMAT formats the drive named on the command line (or if that drive is the whole disk, asks which volume to format), after a warning that all data on the drive will be lost.  If the disk has no FAT volumes, there's nothing to format, which FORMAT reports.

If the disk has no partition table (eg, a new hard disk, which BASIC-DOS gives a drive letter anyway, with "unknown media"), FORMAT offers to create one, with a single volume (starting at the second track and ending at a cylinder boundary) of the size you choose in Mb, up to 32Mb (65535 sectors) or the size of the disk; it then writes a master boot record (with the hard disk driver's boot code) and formats the new volume.

A volume's layout depends on its size.  Up to 32680 sectors, it follows the PC DOS 2.x rules; a larger volume gets a 16-bit FAT, as PC DOS 3.x did.

| Volume size | Cluster size | Root entries | FAT |
|-------------|--------------|--------------|-----|
| Up to 256K | 512 | 64 | 12-bit |
| Up to 1Mb | 1K | 112 | 12-bit |
| Up to 4Mb | 2K | 256 | 12-bit |
| Up to 32680 sectors (about 16Mb) | 4K | 512 | 12-bit |
| Up to 65535 sectors (32Mb) | 2K | 512 | 16-bit |

Hard disk volumes aren't verified, and extended partitions aren't supported.

### Messages

- `Cannot format the current drive`
- `Cannot format drive` *drive* `(files are open)`
- `Drive` *drive* `can't format` *size*`K diskettes`: the drive's size doesn't allow it
- `Invalid size (use /F:360, /F:720, or /F:1200)`, or for a new hard disk volume, `Invalid size`
- `No such volume`: the drive you chose isn't one of the disk's volumes
- `/1 and /8 are only for 360K`
- `Write protect error`
- `Drive not ready`
- `Track` *n* `bad - disk unusable`
- `Invalid drive`
- `Too many characters in volume label` or `Invalid characters in volume label`: FORMAT then asks for the label
- `Unable to copy` *file*: a system file couldn't be copied for `/S`, and the rest aren't copied
- `Format failed (error` *n*`)`, for any other error

A missing drive, an unknown switch, or a second drive displays `Syntax error`.

Source: [FORMAT.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/FORMAT.BAS)

{% include footer.html prev="FIND:../find/" next="HELP:../help/" %}
