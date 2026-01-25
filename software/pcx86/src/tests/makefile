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
MAPSYM=MAPSYM
AFLAGS=/D$(REL) /I..\OS\INC

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

OBJ\DOSTESTS.COM: DOSTESTS.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\SPRINTF.OBJ: ..\OS\DOS\SPRINTF.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;

OBJ\STRTESTS.OBJ: STRTESTS.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;

OBJ\STRTESTS.COM: OBJ\SPRINTF.OBJ OBJ\STRTESTS.OBJ
	$(LINK) /MAP OBJ\STRTESTS.OBJ+OBJ\SPRINTF.OBJ,OBJ\STRTESTS.EXE,OBJ\STRTESTS.MAP;
	$(EXE2BIN) OBJ\STRTESTS.EXE $@
	$(MAPSYM) OBJ\STRTESTS.MAP OBJ\STRTESTS.SYM;
	DEL OBJ\SPRINTF.OBJ
	DEL OBJ\STRTESTS.OBJ

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
