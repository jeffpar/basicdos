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

.ASM.OBJ:
	$(ASM) $(AFLAGS) /I..\INC $**,$@;

.ASM.LST:
	$(ASM) $(AFLAGS) /I..\INC $**,$@,$*.LST;

COMMAND.OBJ: COMMAND.ASM

CONST.OBJ: CONST.ASM

COMMAND.COM: COMMAND.OBJ CONST.OBJ
	$(LINK) @$*.LRF
	$(EXE2BIN) $*.EXE $@
	DEL $*.EXE
