---
layout: page
heading: BASIC-DOS Demos
permalink: /machines/demos/
redirect_from: /demos/
---

Each BASIC-DOS demo runs on up to four generations of PC hardware: the original IBM PC (Model 5150) with its 4.77Mhz 8088 and diskette drives, the IBM PC XT (Model 5160), which added a hard disk, the IBM PC AT (Model 5170), with a 6Mhz 80286 and a battery-powered real-time clock that keeps the date and time, and the COMPAQ DeskPro 386, COMPAQ's first PC with a 16Mhz 80386, shown here with 1Mb of memory (2Mb in the Extended Memory demos) and a VGA.  Click a machine to run that demo on that hardware.

You can also browse the [BASIC-DOS Release Diskettes](/disks/downloads/) to test or download the latest release, or check this box <label><input type="checkbox" id="bdRelease"> to load a Release Diskette in any of the machines below.</label>

<script>
  //
  // When the box is checked, each machine link in the table gets an autoMount parameter that loads the
  // current BASIC-DOS Release Diskette in drive A (PCjs reads machine parameters from the page's URL).
  //
  (function() {
    var box = document.getElementById("bdRelease");
    var mount = '{A:{path:"/disks/current/BASICDOS-360K.json"}}';
    function update() {
      document.querySelectorAll("table a[href]").forEach(function(a) {
        var url = new URL(a.href, location.href);
        if (box.checked) url.searchParams.set("autoMount", mount); else url.searchParams.delete("autoMount");
        a.href = url.href;
      });
    }
    box.addEventListener("change", update);
    window.addEventListener("pageshow", update);     // (a browser may restore the box when returning to the page)
  })();
</script>

| Demo | IBM PC | IBM PC XT | IBM PC AT | COMPAQ DeskPro 386 |
|------|--------|-----------|-----------|--------------------|
| 1. Monochrome | [64K, MDA](bd/m64/pc/) | [640K, MDA](bd/m64/xt/) | | |
| 2. VT100 Console | [64K, VT100](bd/term/pc/) | [640K, VT100](bd/term/xt/) | [640K, VT100x2](bd/term/at/) | |
| 3. Color Graphics | [128K, CGA, 8087](bd/s80/pc/) | [640K, CGA, 8087](bd/s80/xt/) | [640K, CGA, 80287](bd/s80/at/) | [1Mb, VGA, 80387](bd/s80/386/) |
| 4. Dual 40-Column | [128K, CGA](bd/d40/pc/) | [640K, CGA](bd/d40/xt/) | [640K, CGA](bd/d40/at/) | [1Mb, VGA](bd/d40/386/) |
| 5. Dual 80-Column | [128K, CGA](bd/d80/pc/) | [640K, CGA](bd/d80/xt/) | [640K, CGA](bd/d80/at/) | [1Mb, VGA](bd/d80/386/) |
| 6. Multiple Pages | [256K, MDA](bd/p80/pc/) | [640K, CGA](bd/p80/xt/) | [640K, CGA](bd/p80/at/) | [1Mb, VGA](bd/p80/386/) |
| 7. Dual Monitors | [256K, MDA, CGA](bd/dual/pc/) | [640K, MDA, CGA](bd/dual/xt/) | [640K, MDA, CGA](bd/dual/at/) | [1Mb, MDA, CGA](bd/dual/386/) |
| 8. Serial Mouse | [256K, EGA, Mouse](bd/mouse/pc/) | [640K, EGA, Mouse](bd/mouse/xt/) | [640K, EGA, Mouse](bd/mouse/at/) | [1Mb, VGA, Mouse](bd/mouse/386/) |
| 9. VT100 Debugger | [256K, EGA, VT100](bd/debug/pc/) | [640K, EGA, VT100](bd/debug/xt/) | [640K, EGA, VT100](bd/debug/at/) | [1Mb, VGA, VT100](bd/debug/386/) |
| 10. 20Mb Drive | | [640K, EGA](bd/hd/xt/) | [640K, EGA](bd/hd/at/) | [1Mb, VGA](bd/hd/386/) |
| 11. 20Mb (VT100 Console) | | [640K, EGA, VT100](bd/vt100/xt/) | [640K, EGA, VT100](bd/vt100/at/) | [1Mb, VGA, VT100](bd/vt100/386/) |
| 12. Wolfenstein 3D | | | [640K, VGA, Sound](bd/wolf3d/at/) | [1Mb, VGA, Sound](bd/wolf3d/386/) |
| 13. Extended Memory (2Mb) | | | [2Mb, CGA](bd/mmu/) | [2Mb, VGA](bd/mmu/386/) |
| 14. Extended Memory (Debugger) | | | [2Mb, CGA, VT100](bd/mmu/vt100/) | [2Mb, VGA, VT100](bd/mmu/vt100/386/) |

To compare BASIC-DOS features to OS/2 2.0, we also have [Microsoft OS/2 2.0 (Pre-Release 2)](os2/2.0/) installed on a 4Mb COMPAQ DeskPro 386, using the 1990 Microsoft OS/2 2.00 Software Development Kit diskettes.

The boot sector first displays `Diskette loading...`; press any key (or wait 2 seconds) to continue.  The PC XT, PC AT, and DeskPro 386 machines also have the 20Mb BASIC-DOS hard disk (drive C:), so when they boot a diskette, you can press **Esc** to boot from the hard disk instead.  On a PC AT or DeskPro 386, the demos run in protected mode (and on the DeskPro 386, with the 80386's features), except Wolfenstein 3D, which needs real mode; press **R** to run any other demo in real mode instead.

A *VT100 Console* is a BASIC-DOS session on a DEC VT100 terminal, which you can type commands at, while a *VT100 Debugger* is DEBUG.COM, BASIC-DOS's own debugger, running on a VT100 connected to COM2 (most demos also have a page with the PCjs debugger, which is part of the emulator).

In the demos with multiple consoles, use **SHIFT-TAB** to toggle keyboard focus between consoles.
