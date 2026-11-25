## BASIC-DOS Command Shell

This directory contains the sources for `COMMAND.COM`, the BASIC-DOS command shell: its internal commands, and the BASIC that it compiles and runs, from the tokenizer and code generators (`gen*.asm`) to the run-time support for strings, arrays, files, graphics, and sound.  It also contains [HELP.TXT](HELP.TXT), the help text that HELP displays.

The modules through `INIT.OBJ` in [cmd.lrf](cmd.lrf) are COMMAND's core, which must still load on a 64K machine; the modules after it are loaded only when there's room, and the core reaches them only through `genCommands`, `genUpper`, and `genFuncExpr`.  The include chain (`cmd.inc`, plus `devapi.inc` and `dosapi.inc` from [inc](../inc/)) is at the limit of MASM's symbol space.
