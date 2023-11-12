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
.ASM.OBJ:
	$(ASM) $(AFLAGS) $*.ASM,$@;

.ASM.LST:
	$(ASM) $(AFLAGS) $*.ASM,$@,$*.LST;

OBJ\DOSDATA.OBJ: DOSDATA.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\DOSINTS.OBJ: DOSINTS.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\CONIO.OBJ: CONIO.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\DEVICE.OBJ: DEVICE.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\DISK.OBJ: DISK.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\FCBIO.OBJ: FCBIO.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\HANDLE.OBJ: HANDLE.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\MEMORY.OBJ: MEMORY.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\MATH.OBJ: MATH.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\MISC.OBJ: MISC.ASM ..\INC\DOS.INC ..\INC\VERSION.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\PROCESS.OBJ: PROCESS.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\SESSION.OBJ: SESSION.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\SPRINTF.OBJ: SPRINTF.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\UTILITY.OBJ: UTILITY.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\UTILSYS.OBJ: UTILSYS.ASM ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\SYSINIT.OBJ: SYSINIT.ASM ..\INC\DOS.INC ..\INC\VERSION.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\BASDOS.EXE: OBJ\DOSDATA.OBJ OBJ\DOSINTS.OBJ OBJ\CONIO.OBJ OBJ\DEVICE.OBJ \
	OBJ\DISK.OBJ OBJ\FCBIO.OBJ OBJ\HANDLE.OBJ OBJ\MATH.OBJ OBJ\MEMORY.OBJ \
	OBJ\MISC.OBJ OBJ\PROCESS.OBJ OBJ\SESSION.OBJ OBJ\SPRINTF.OBJ \
    OBJ\UTILITY.OBJ OBJ\UTILSYS.OBJ OBJ\SYSINIT.OBJ BASDOS.LRF
	$(LINK) @$*.LRF

OBJ\BASDOS.COM: OBJ\BASDOS.EXE
	$(EXE2BIN) $** $@
