#
# BASIC-DOS Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright (c) 2020-2021 Jeff Parsons
# @license MIT <https://basicdos.com/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
ASM=MASM
LINK=LINK
EXE2BIN=EXE2BIN
AFLAGS=/D$(REL) /I..\INC

#
# Inference rules in the DOS MAKE utility apparently work only if the files
# are in the same folder.  So for now, each dependency must copy these rules.
#
.ASM.COM:
	$(ASM) $(AFLAGS) $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

.ASM.EXE:
	$(ASM) $(AFLAGS) $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE;
	DEL $*.OBJ

OBJ\CASE.COM: CASE.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\PRIMES.EXE: PRIMES.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	DEL OBJ\$*.OBJ

OBJ\SLEEP.COM: SLEEP.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\TESTS.COM: TESTS.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\DISKREAD.COM: DISKREAD.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\DISKWRIT.COM: DISKWRIT.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE
