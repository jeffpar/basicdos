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
	$(ASM) $(AFLAGS) /I.. /I..\..\INC $**,$@;

.ASM.LST:
	$(ASM) $(AFLAGS) /I.. /I..\..\INC $**,$@,$*.LST;

CMD.OBJ: ..\CMD.ASM
	$(ASM) $(AFLAGS) /I.. /I..\..\INC $**,$@;

EVAL.OBJ: ..\EVAL.ASM
	$(ASM) $(AFLAGS) /I.. /I..\..\INC $**,$@;

GEN.OBJ: ..\GEN.ASM
	$(ASM) $(AFLAGS) /I.. /I..\..\INC $**,$@;

STDIO.OBJ: ..\STDIO.ASM
	$(ASM) $(AFLAGS) /I.. /I..\..\INC $**,$@;

VARS.OBJ: ..\VARS.ASM
	$(ASM) $(AFLAGS) /I.. /I..\..\INC $**,$@;

CONST.OBJ: ..\CONST.ASM
	$(ASM) $(AFLAGS) /I.. /I..\..\INC $**,$@;

COMMAND.COM: CMD.OBJ EVAL.OBJ GEN.OBJ CONST.OBJ
	$(LINK) @$*.LRF
	$(EXE2BIN) $*.EXE $@
	DEL $*.EXE
