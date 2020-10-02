#
# BASIC-DOS Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright (c) 2012-2020 Jeff Parsons
# @license MIT <https://www.pcjs.org/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
ASM=MASM
LINK=LINK
EXE2BIN=EXE2BIN
AFLAGS=/D$(REL) /I..\INC

#
# Inference rules in the DOS MAKE utility apparently work only if the
# files are in the same folder.  So for now, these rules must be copied
# under each dependency.
#
.ASM.COM:
	$(ASM) $(AFLAGS) $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE,$*.MAP/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

OBJ\NULDEV.COM: NULDEV.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\CONDEV.COM: CONDEV.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\AUXDEV.COM: AUXDEV.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\COMDEV.COM: COMDEV.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\PRNDEV.COM: PRNDEV.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\LPTDEV.COM: LPTDEV.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\CLKDEV.COM: CLKDEV.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\FDCDEV.COM: FDCDEV.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\DEVINIT.COM: DEVINIT.ASM
	$(ASM) $(AFLAGS) $**,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\IBMBIO.COM: ..\BOOT\OBJ\BOOT2.COM OBJ\NULDEV.COM OBJ\CONDEV.COM \
	OBJ\AUXDEV.COM OBJ\COMDEV.COM OBJ\PRNDEV.COM OBJ\LPTDEV.COM \
	OBJ\CLKDEV.COM OBJ\FDCDEV.COM OBJ\DEVINIT.COM
	COPY /B ..\BOOT\OBJ\BOOT2.COM+OBJ\NULDEV.COM+OBJ\CONDEV.COM+OBJ\AUXDEV.COM+OBJ\COMDEV.COM OBJ\IBMBIO.BIN
	COPY /B OBJ\IBMBIO.BIN+OBJ\PRNDEV.COM+OBJ\LPTDEV.COM+OBJ\CLKDEV.COM+OBJ\FDCDEV.COM+OBJ\DEVINIT.COM OBJ\IBMBIO.COM
	DEL OBJ\IBMBIO.BIN
