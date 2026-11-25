These machines have no diskettes loaded; instead, they boot BASIC-DOS from a 20Mb hard disk (drive C:) and run one full-screen 80x25 console.

The hard disk has the system files and CONFIG.SYS in the root directory, along with these subdirectories:

- **EXT** contains the BASIC-DOS utilities: assembly language programs (eg, FIND, MORE, SORT, and DEBUG.COM, and HELP.COM with HELP.TXT) in **EXT\\CMD**, and BASIC programs (eg, FORMAT.BAS and LS.BAS) in **EXT\\BAS**
- **DEMOS** contains the programs that the demos run (eg, HELLO.BAT, PAINT.BAS, PRIMES.BAS, and JIVE.EXE), along with BROGUE.BAS and DONKEY.BAS (from the PC DOS 1.00 diskette), and its WOLF3D subdirectory contains the shareware version of Wolfenstein 3D (type `WOLF3D` to run it)
- **SRC** contains the BASIC-DOS source code and its build outputs (type `CD \SRC` and then `MK` to rebuild whatever has changed, or `MK FINAL CLEAN` to rebuild everything)
- **TESTS** contains BENCH.BAS, STRESS.BAT, and REGRESS.BAT, which runs the regression tests in its **REGRESS** subdirectory (eg, DOSTESTS.COM; type `CD \TESTS` and then `REGRESS`); its **MISC** subdirectory has other test programs (eg, GFXTESTS.BAS, and the BAT and EXE versions of PRIMES), and its **SAMPLES** subdirectory has the other PC DOS 1.00 BASIC samples (type `CD \TESTS\SAMPLES` and then `SAMPLES` for their menu, or the name of one, such as `CIRCLE`)
- **TOOLS\BIN** contains MASM5, MASM, LINK, MAKE, EXE2BIN, and the other tools used to build BASIC-DOS, along with DISKREAD.COM, DISKWRIT.COM, SYMDEB.EXE, and MSBASIC.EXE

CONFIG.SYS sets PATH$ to `C:\;C:\EXT\CMD;C:\EXT\BAS;C:\DEMOS;C:\TOOLS\BIN`, so programs in those directories can be run from anywhere, and the session's SHELL line runs `HELLO.BAT` to display a colorful greeting.

Type `CLAUDE` to ask Claude questions; the page asks for your Claude API key, or you can add it to the page's address as `#claudekey=` followed by the key (see [CLAUDE](/docs/bdman/cmd/external/claude/)).

Any changes you make to the hard disk are lost when you leave the page, unless you first click **Save HD** to download the hard disk as an IMG file.

### **CONFIG.SYS** from the BASICDOS-20MB Hard Disk

```
{% include_relative CONFIG.SYS %}
```

{% comment %}

Use the following page parameter to add MSDOS320-C400 as drive D:

    drives: '[{name:"BASICDOS-20MB",type:3,path:"/disks/current/BASICDOS-20MB.json"},{name:"MSDOS320-C400",type:3,path:"/disks/historical/dos/MSDOS320-C400.json"}]'

(on an IBM PC AT or COMPAQ DeskPro 386, use drive type 2 for BASICDOS-20MB)

{% endcomment %}
