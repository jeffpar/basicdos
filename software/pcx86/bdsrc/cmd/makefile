#
# BASIC-DOS Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright (c) 2020-2021 Jeff Parsons
# @license MIT <https://www.pcjs.org/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
ASM=MASM
LINK=LINK
EXE2BIN=EXE2BIN
AFLAGS=/D$(REL) /I. /I..\INC

#
# Inference rules in the DOS MAKE utility apparently work only if the files
# are in the same folder.  So for now, each dependency must copy these rules.
#
.ASM.OBJ:
	$(ASM) $(AFLAGS) $*.ASM,$@;

.ASM.LST:
	$(ASM) $(AFLAGS) $*.ASM,$.OBJ,$@;

OBJ\CMD.OBJ: CMD.ASM CMD.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\GEN.OBJ: GEN.ASM CMD.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\LIBC.OBJ: LIBC.ASM CMD.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\LONG.OBJ: LONG.ASM CMD.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\MEM.OBJ: MEM.ASM CMD.INC ..\INC\DOS.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\STR.OBJ: STR.ASM CMD.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\VAR.OBJ: VAR.ASM CMD.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\CONST.OBJ: CONST.ASM CMD.INC TXT.INC
	$(ASM) $(AFLAGS) $*.ASM,$@;

OBJ\COMMAND.COM: OBJ\CMD.OBJ OBJ\GEN.OBJ OBJ\LIBC.OBJ OBJ\LONG.OBJ \
	OBJ\MEM.OBJ OBJ\STR.OBJ OBJ\VAR.OBJ OBJ\CONST.OBJ COMMAND.LRF
	$(LINK) @$*.LRF
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.EXE
