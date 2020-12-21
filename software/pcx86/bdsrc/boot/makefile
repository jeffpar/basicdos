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
AFLAGS=/D$(REL) /I..\INC

#
# Inference rules in the DOS MAKE utility apparently work only if the files
# are in the same folder.  So for now, each dependency must copy these rules.
#
.ASM.COM:
	$(ASM) $(AFLAGS) $*.ASM,$*.OBJ;
	$(LINK) $*.OBJ,$*.EXE,$*.MAP/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

OBJ\BOOT.COM: BOOT.ASM ..\INC\VERSION.INC
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\WBOOT.COM: WBOOT.ASM
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ;
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE
