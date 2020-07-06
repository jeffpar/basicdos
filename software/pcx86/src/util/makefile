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

.ASM.COM:
	$(ASM) $(AFLAGS) /I..\INC $**,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

COMMAND.COM: COMMAND.ASM

EXEC.COM: EXEC.ASM

PRIMES.COM: PRIMES.ASM

SLEEP.COM: SLEEP.ASM
