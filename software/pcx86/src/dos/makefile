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
AFLAGS=/D$(REL) /I..\INC

#
# Inference rules in the DOS MAKE utility apparently work only if the
# files are in the same folder.  So for now, these rules must be copied
# under each dependency.
#
.ASM.OBJ:
	$(ASM) $(AFLAGS) $**,$@;

.ASM.LST:
	$(ASM) $(AFLAGS) $**,$@,$*.LST;

OBJ\DOSDATA.OBJ: DOSDATA.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\DOSINTS.OBJ: DOSINTS.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\CONIO.OBJ: CONIO.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\DEVICE.OBJ: DEVICE.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\DISK.OBJ: DISK.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\FCBIO.OBJ: FCBIO.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\HANDLE.OBJ: HANDLE.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\MEMORY.OBJ: MEMORY.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\MISC.OBJ: MISC.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\PROCESS.OBJ: PROCESS.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\SESSION.OBJ: SESSION.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\SPRINTF.OBJ: SPRINTF.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\UTILITY.OBJ: UTILITY.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\UTILSYS.OBJ: UTILSYS.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\SYSINIT.OBJ: SYSINIT.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\IBMDOS.EXE: OBJ\DOSDATA.OBJ OBJ\DOSINTS.OBJ OBJ\CONIO.OBJ OBJ\DEVICE.OBJ \
	OBJ\DISK.OBJ OBJ\FCBIO.OBJ OBJ\HANDLE.OBJ OBJ\MEMORY.OBJ OBJ\MISC.OBJ \
	OBJ\PROCESS.OBJ OBJ\SESSION.OBJ OBJ\SPRINTF.OBJ OBJ\UTILITY.OBJ \
	OBJ\UTILSYS.OBJ OBJ\SYSINIT.OBJ
	$(LINK) @$*.LRF

OBJ\IBMDOS.COM: OBJ\IBMDOS.EXE
	$(EXE2BIN) $** $@
