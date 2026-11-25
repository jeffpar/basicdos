## BASIC-DOS Regression Tests

This directory contains the regression tests, which check their own results and report any failures: assembly-language tests of the kernel and drivers (eg, `DOSTESTS.COM`, `CPUTESTS.COM`, `FPUTESTS.COM`, `HARDERR.COM`, and `R3TESTS.COM`), and BASIC and batch tests of COMMAND.COM (eg, `ARRAYS.BAS`, `FLOW.BAS`, `STRFUN.BAS`, `VARS.BAS`, and `CMDS.BAT`).  `REGRESS.BAT` (in [tests](../)) runs them all, and `tools/tests/quick.sh` runs most of them on test machines.
