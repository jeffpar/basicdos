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
AFLAGS=/DDEBUG

.ASM.COM:
	$(ASM) $(AFLAGS) /I../INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

BOOT.COM: BOOT.ASM

WBOOT.COM: WBOOT.ASM
