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
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

NULDEV.COM: ..\NULDEV.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

CONDEV.COM: ..\CONDEV.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

AUXDEV.COM: ..\AUXDEV.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

COMDEV.COM: ..\COMDEV.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

PRNDEV.COM: ..\PRNDEV.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

LPTDEV.COM: ..\LPTDEV.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

CLKDEV.COM: ..\CLKDEV.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

FDCDEV.COM: ..\FDCDEV.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

DEVINIT.COM: ..\DEVINIT.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

IBMBIO.COM: ..\..\BOOT\OBJ\BOOT2.COM NULDEV.COM CONDEV.COM AUXDEV.COM COMDEV.COM \
	PRNDEV.COM LPTDEV.COM CLKDEV.COM FDCDEV.COM DEVINIT.COM
	COPY /B ..\..\BOOT\OBJ\BOOT2.COM+NULDEV.COM+CONDEV.COM+AUXDEV.COM+COMDEV.COM+PRNDEV.COM IBMBIO.BIN
	COPY /B IBMBIO.BIN+LPTDEV.COM+CLKDEV.COM+FDCDEV.COM+DEVINIT.COM IBMBIO.COM
	DEL IBMBIO.BIN
