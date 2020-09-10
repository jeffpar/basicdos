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
AFLAGS=/D$(REL) /I. /I..\INC

#
# Inference rules in the DOS MAKE utility apparently work only if the
# files are in the same folder.  So for now, these rules must be copied
# under each dependency.
#
.ASM.OBJ:
	$(ASM) $(AFLAGS) $**,$@;

.ASM.LST:
	$(ASM) $(AFLAGS) $**,$@,$*.LST;

OBJ\CMD.OBJ: CMD.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\EVAL.OBJ: EVAL.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\GEN.OBJ: GEN.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\MEM.OBJ: MEM.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\STDIO.OBJ: STDIO.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\VARS.OBJ: VARS.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\CONST.OBJ: CONST.ASM
	$(ASM) $(AFLAGS) $**,$@;

OBJ\COMMAND.COM: OBJ\CMD.OBJ OBJ\EVAL.OBJ OBJ\GEN.OBJ OBJ\MEM.OBJ \
	OBJ\STDIO.OBJ OBJ\VARS.OBJ OBJ\CONST.OBJ
	$(LINK) @$*.LRF
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.EXE
