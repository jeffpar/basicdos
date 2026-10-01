#
# BASIC-DOS Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright (c) 2020-2026 Jeff Parsons
# @license MIT <https://basicdos.com/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
ASM=MASM
CL=CL
LINK=LINK
EXE2BIN=EXE2BIN
MAPSYM=MAPSYM
CFLAGS=
AFLAGS=/MX /R /D$(REL) /I..\OS\INC

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

.C.EXE:
	$(CL) $(CFLAGS) $** /FoOBJ\$*.OBJ /Fe$@;
	DEL $*.OBJ

BIN\CASE.COM: MISC\CASE.ASM
	$(ASM) $(AFLAGS) $**,BIN\$*.OBJ;
	$(LINK) BIN\$*.OBJ,BIN\$*.EXE;
	$(EXE2BIN) BIN\$*.EXE $@
	DEL BIN\$*.OBJ
	DEL BIN\$*.EXE

BIN\DISKREAD.COM: MISC\DISKREAD.ASM
	$(ASM) $(AFLAGS) $**,BIN\$*.OBJ;
	$(LINK) BIN\$*.OBJ,BIN\$*.EXE;
	$(EXE2BIN) BIN\$*.EXE $@
	DEL BIN\$*.OBJ
	DEL BIN\$*.EXE

BIN\DISKWRIT.COM: MISC\DISKWRIT.ASM
	$(ASM) $(AFLAGS) $**,BIN\$*.OBJ;
	$(LINK) BIN\$*.OBJ,BIN\$*.EXE;
	$(EXE2BIN) BIN\$*.EXE $@
	DEL BIN\$*.OBJ
	DEL BIN\$*.EXE

BIN\DOSTESTS.COM: MISC\DOSTESTS.ASM
	$(ASM) $(AFLAGS) $**,BIN\$*.OBJ;
	$(LINK) BIN\$*.OBJ,BIN\$*.EXE;
	$(EXE2BIN) BIN\$*.EXE $@
	DEL BIN\$*.OBJ
	DEL BIN\$*.EXE

BIN\SLEEP.COM: MISC\SLEEP.ASM
	$(ASM) $(AFLAGS) $**,BIN\$*.OBJ;
	$(LINK) BIN\$*.OBJ,BIN\$*.EXE;
	$(EXE2BIN) BIN\$*.EXE $@
	DEL BIN\$*.OBJ
	DEL BIN\$*.EXE

BIN\PRIMES.EXE: PRIMES\PRIMES.ASM
	$(ASM) $(AFLAGS) $**,BIN\$*.OBJ;
	$(LINK) BIN\$*.OBJ,BIN\$*.EXE;
	DEL BIN\$*.OBJ

OBJ\BDLIB.OBJ: LIB\BDLIB.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;

OBJ\SPRINTF.OBJ: ..\OS\DOS\SPRINTF.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;

OBJ\PRINTF.OBJ: PRINTF\PRINTF.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;

BIN\PRINTF.COM: OBJ\BDLIB.OBJ OBJ\SPRINTF.OBJ OBJ\PRINTF.OBJ
	$(LINK) /MAP OBJ\BDLIB.OBJ+OBJ\SPRINTF.OBJ+OBJ\PRINTF.OBJ,OBJ\PRINTF.EXE,OBJ\PRINTF.MAP;
	$(EXE2BIN) OBJ\PRINTF.EXE $@
	CD OBJ
	$(MAPSYM) PRINTF.MAP
	DEL PRINTF.EXE
	CD ..

BIN\CPRINTF.EXE: PRINTF\CPRINTF.C
	$(CL) $(CFLAGS) $** /Fe$@;
	DEL $*.OBJ
