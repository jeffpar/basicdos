These machines have no diskettes loaded; instead, they boot BASIC-DOS from a 10Mb hard disk (drive C:) and run one full-screen 80x25 session.

The hard disk has the system files, CONFIG.SYS and HELP.TXT in the root directory, along with these subdirectories:

- **BIN** contains the BASIC-DOS utilities (eg, FIND, MORE, and SORT)
- **SAMPLES** contains DONKEY.BAS and the other PC DOS BASIC samples
- **SRC** contains the BASIC-DOS source code and its build outputs (type `CD \SRC` and then `MK` to rebuild whatever has changed, or `MK FINAL CLEAN` to rebuild everything)
- **TESTS** contains HELLO.BAT, BENCH.BAS, PAINT.BAS, PRIMES.BAS, PRIMES.BAT, STRESS.BAT, and MSBASIC.EXE
- **TOOLS** contains MASM, LINK, MAKE, EXE2BIN, and the other MASM 4.00 tools used to build BASIC-DOS

CONFIG.SYS sets PATH$ to `C:\;C:\BIN;C:\SAMPLES;C:\TESTS;C:\TOOLS`, so programs in those directories can be run from anywhere, and the session's SHELL line runs `HELLO.BAT` to display the BASIC-DOS version and a colorful greeting.

Any changes you make to the hard disk are lost when you leave the page, unless you first click **Save HD** to download the hard disk as an IMG file.

### **CONFIG.SYS** from the BASICDOS-HD Hard Disk

```
{% include_relative CONFIG.SYS %}
```

{% comment %}

Use the following page parameter to add MSDOS320-C400 as drive D:

    drives: '[{name:"BASICDOS-HD",type:3,path:"/software/disks/BASICDOS-HD.json"},{name:"MSDOS320-C400",type:3,path:"/software/disks/MSDOS320-C400.json"}]'

(on an IBM PC AT, use drive type 1 for BASICDOS-HD)

{% endcomment %}
