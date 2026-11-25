## BASIC-DOS Tests

This directory matches the **TESTS** directory of the BASIC-DOS disks: [regress](regress/) has the regression tests, [misc](misc/) has the other test programs, and [tools](tools/) has the test tools; [lib](lib/) has a library that some tests link with.  The batch files here run the tests: `REGRESS.BAT` runs the regression tests, and `STRESS.BAT` is a multitasking stress test; `BENCH.BAS` is the benchmark suite.

The one [makefile](makefile) here builds every assembly-language test, each into its folder's `OBJ` folder; the `.BAT` and `.BAS` tests are ready to run.  `manifest.txt` (in the repository root) lists which files go on which disks, and `tools/tests/quick.sh` runs most of the regression tests.
