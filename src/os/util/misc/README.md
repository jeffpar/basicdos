## BASIC-DOS Single-File Utilities

This directory contains the external commands that are each a single assembly-language file: the filters (`FIND.COM`, `MORE.COM`, `SED.COM`, `SORT.COM`, `TEE.COM`, `TR.COM`, `UNIQ.COM`, and `WC.COM`), `HELP.COM` (which displays [HELP.TXT](../../cmd/HELP.TXT)), and `SLEEP.COM`.  `utilproc.inc` and `utilvars.inc` hold the code and data that they share (eg, argument parsing, switch checking, and usage errors).
