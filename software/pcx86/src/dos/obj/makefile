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
.ASM.OBJ:
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

.ASM.LST:
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@,$*.LST;

DOSDATA.OBJ: ..\DOSDATA.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

DOSINTS.OBJ: ..\DOSINTS.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

CONIO.OBJ: ..\CONIO.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

DEVICE.OBJ: ..\DEVICE.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

DISK.OBJ: ..\DISK.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

FCBIO.OBJ: ..\FCBIO.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

HANDLE.OBJ: ..\HANDLE.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

MEMORY.OBJ: ..\MEMORY.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

MISC.OBJ: ..\MISC.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

PROCESS.OBJ: ..\PROCESS.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

SESSION.OBJ: ..\SESSION.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

SPRINTF.OBJ: ..\SPRINTF.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

UTILITY.OBJ: ..\UTILITY.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

SYSINIT.OBJ: ..\SYSINIT.ASM
	$(ASM) $(AFLAGS) /I..\..\INC $**,$@;

IBMDOS.COM: DOSDATA.OBJ DOSINTS.OBJ CONIO.OBJ DEVICE.OBJ DISK.OBJ FCBIO.OBJ HANDLE.OBJ \
	MEMORY.OBJ MISC.OBJ PROCESS.OBJ SESSION.OBJ SPRINTF.OBJ UTILITY.OBJ SYSINIT.OBJ
	$(LINK) @$*.LRF
	$(EXE2BIN) $*.EXE $@
	DEL $*.EXE
