---
layout: default
heading: Welcome to BASIC-DOS
permalink: /
---

## PC DOS Reimagined

Read the [Blog](blog/), then check out the [Preview](preview/), which
highlights a few of the original [Demos](demos/).

[![BASIC-DOS 1.00](assets/images/BASIC-DOS-Cover.gif)](preview/)

## License

[BASIC-DOS](https://github.com/jeffpar/basicdos) is an open-source project
on [GitHub](https://github.com/jeffpar) released under the terms of an
[MIT License](/LICENSE.txt).

{% comment %}

The new build process requires the [PCjs](https://github.com/jeffpar/pcjs)
repository along with the BASIC-DOS repository.  It's recommended that you set
environment variables for both repositories and then update your PATH to include
the directories for both `diskimage.js` and `pc.js`; eg:

    $ export PCJS="$HOME/pcjs"
    $ export BASICDOS="$HOME/basicdos"
    $ export PATH="$PATH:$PCJS/tools/diskimage:$PCJS/tools/pc"

Then run this command to get a `tools` disk image:

    $ diskimage.js https://harddisks.pcjs.org/pcx86/10mb/MSDOS330-C400.json $PCJS/tools/pc/disks/tools.json

Now you're ready to build BASIC-DOS, using `pc.js` to load the `tools` disk image as
drive C and the BASIC-DOS source code as drive D:

    $ pc.js --disk tools.json $BASICDOS/software/pcx86/src -n
    [Press CTRL-D to enter command mode]
    C:\>dir

    Volume in drive C is PCJS       
    Directory of  C:\

    COMMAND  COM    25308   2-02-88  12:00a
    AUTOEXEC BAT      185   9-28-23   2:39p
    CONFIG   SYS       22   1-01-80  12:03a
    DOS          <DIR>      9-05-23  11:37a
    MBR          <DIR>      9-27-23   6:24a
    PUZZLED      <DIR>      9-05-23  11:37a
    TMP          <DIR>      1-01-80  12:13a
    TOOLS        <DIR>      9-05-23  11:37a
            8 File(s)   5726208 bytes free

    C:\>d:

    D:\>dir

    Volume in drive D is SRC        
    Directory of  D:\

    README   MD      3637  12-21-20   2:00p
    BD           <DIR>     11-07-23  10:09a
    CONF         <DIR>     11-07-23  10:09a
    MK       BAT      260  11-07-23   9:26a
    MKCLEAN  BAT      299  11-07-23   9:27a
    MSB          <DIR>     11-07-23  10:09a
    TEST         <DIR>     11-07-23  10:09a
            7 File(s)    835584 bytes free

    D:\>mk
    Microsoft (R) Program Maintenance Utility  Version 4.02
    Copyright (C) Microsoft Corp 1984, 1985, 1986.  All rights reserved.
    
    ...

{% endcomment %}
