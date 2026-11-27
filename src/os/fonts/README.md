## BASIC-DOS Fonts

This directory contains the fonts that [MODE FONT](../../../docs/bdman/cmd/external/mode/) loads on an EGA or VGA, which are copied as-is to **EXT\\FONTS** on a BASIC-DOS disk.  A font file holds the lines of all 256 characters, in order, one byte per line (bit 7 is the leftmost pixel), so its length is 256 times the number of lines per character.

`OS2.F14` is the 8x14 font that OS/2 2.0 (the second pre-release, on the [OS/2 2.0](../../../machines/demos/os2/2.0/) demo's hard disk) uses for its windowed DOS and OS/2 sessions: the "System" font in **C:\OS2\DLL\DISPLAY.DLL** (its 8x8 font is the windows' "Small Font").  That font has the glyphs of OS/2's Universal Glyph List (383 of them, in code page 850's order, followed by the rest) rather than one code page's characters, so its characters were chosen with OS/2's own code page 437 table, in **C:\OS2\DLL\PMWIN.DLL**.
