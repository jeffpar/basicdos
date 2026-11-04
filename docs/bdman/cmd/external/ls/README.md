---
layout: sheet
title: LS
permalink: /docs/bdman/cmd/external/ls/
---

{% include header.html %}

> LS [/1alRrSt] [*filespec*]...

Lists files and directories like the UNIX `ls` command.  Each *filespec* that's a directory (eg, `LS \EXT`, `LS ..`, or `LS A:`) lists the files in that directory, and without one, the current directory is listed.  Any other *filespec* lists the files that match it (and with wildcards, the directories that match it, too), with the *filespec*'s drive and path in front of each name, as a UNIX shell would expand them (eg, `LS \EXT\T*.COM` lists `\EXT\TEE.COM  \EXT\TR.COM`); those files are listed first, all together, and then each directory, after a line with its name and a colon if more than one *filespec* was given.  A *filespec* that matches nothing is reported (eg, `Unable to find X.BAS`).

Names are sorted, and listed in columns down the screen, each column 2 characters wider than the longest name, with as many columns as fit the console's width.  Each directory's name ends with the path character (eg, `EXT\`), as UNIX's `ls -p` shows directories; programs aren't marked.  When the output isn't the console (eg, `LS > FILES.TXT`), names are listed one per line, as UNIX does.  Hidden files, and the `.` and `..` entries of a subdirectory, are listed only with `/a`.

Options start with the switch character (`/`, unless [SWITCHAR](../../../cfg/#switchar) changes it, eg, to `-`), are case-sensitive, and can be combined (eg, `LS /ltr` is the same as `LS /l /t /r`):

- `/1` lists one name per line
- `/a` lists all files, including hidden files and the `.` and `..` entries
- `/l` lists each file's mode, size, date, and name, after a `total` line with the directory's size in K (the sum of each file's size rounded up to a whole K); the mode is `d` for a directory (or `-`), followed by `rwx` for a directory or program (a COM, EXE, BAT, or BAS file), or `rw-` for any other file, without the `w` for a read-only file.  Sizes are right-justified in 7 columns.  The date shows the time if it's within the last 6 months, or else the year.  Since files have no owners or links, there are no owner, group, or link count columns, and only one set of permissions.
- `/R` lists the subdirectories of each directory listed, too, after a line with each one's path (eg, `.\TESTS:`)
- `/r` reverses the order
- `/S` sorts by size, largest first
- `/t` sorts by date and time, newest first (and `/tr`, oldest first)

Files with the same size or time are sorted by name.  A listing can have up to 512 names (more is a "Subscript out of range" error).  A drive that doesn't exist displays `Invalid drive`, and any other option displays LS's usage.

	LS \EXT
	ATTRIB.BAS    FIND.COM      LABEL.BAS     SLEEP.COM     TREE.BAS
	CHKDSK.BAS    FORMAT.BAS    LS.BAS        SORT.COM      UNIQ.COM
	COMP.BAS      HELP.COM      MODE.BAS      SYS.BAS       VI.COM
	DEBUG.COM     HELP.TXT      MORE.COM      TEE.COM       VOL.BAS
	DISKCOPY.BAS  HEXDUMP.BAS   SED.COM       TR.COM        WC.COM
	LS \
	AUTOEXEC.BAT  CONFIG.SYS    TESTS\
	COMMAND.COM   EXT\          TOOLS\
	LS /lt \EXT\T*.*
	-rwx     533 Oct 24 11:22 \EXT\TEE.COM
	-rwx     579 Oct 24 11:22 \EXT\TR.COM
	-rwx    2978 Oct 23 12:17 \EXT\TREE.BAS

Source: [LS.BAS](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/bas/LS.BAS)

{% include footer.html prev="LABEL:../label/" next="MODE:../mode/" %}
