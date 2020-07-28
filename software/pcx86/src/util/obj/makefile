#
# BASIC-DOS Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright © 2012-2020 Jeff Parsons
# @license MIT <https://www.pcjs.org/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
ASM=MASM
LINK=LINK
EXE2BIN=EXE2BIN
AFLAGS=/D$(REL)

#
# Inference rules in the DOS MAKE utility apparently work only if the
# files are in the same folder.  So for now, these rules must be copied
# under each dependency.
#
.ASM.COM:
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

.ASM.EXE:
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE;
	DEL $*.OBJ

PRIMES.EXE: ..\PRIMES.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE;
	DEL $*.OBJ

SLEEP.COM: ..\SLEEP.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

TESTS.COM: ..\TESTS.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE
