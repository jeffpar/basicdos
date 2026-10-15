#
# BASIC-DOS Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright (c) 2020-2026 Jeff Parsons
# @license MIT <https://basicdos.com/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
ASM=MASM
LINK=LINK
EXE2BIN=EXE2BIN
AFLAGS=/MX /R /D$(REL) /I. /I..\..\INC
#
# Listings are off; to create them, set LST=OBJ\$*.LST
#
LST=NUL

#
# Inference rules in the DOS MAKE utility apparently work only if the files
# are in the same folder.  So for now, each dependency must copy these rules.
#
OBJ\VI.COM: VI.ASM VIBUF.ASM VICMD.ASM VIMOVE.ASM VI.INC
	$(ASM) $(AFLAGS) VI.ASM,OBJ\VI.OBJ,$(LST);
	$(ASM) $(AFLAGS) VIBUF.ASM,OBJ\VIBUF.OBJ,$(LST);
	$(ASM) $(AFLAGS) VICMD.ASM,OBJ\VICMD.OBJ,$(LST);
	$(ASM) $(AFLAGS) VIMOVE.ASM,OBJ\VIMOVE.OBJ,$(LST);
	$(LINK) OBJ\VI.OBJ+OBJ\VIBUF.OBJ+OBJ\VICMD.OBJ+OBJ\VIMOVE.OBJ,OBJ\VI.EXE;
	$(EXE2BIN) OBJ\VI.EXE $@
	DEL OBJ\VI.OBJ
	DEL OBJ\VIBUF.OBJ
	DEL OBJ\VICMD.OBJ
	DEL OBJ\VIMOVE.OBJ
	DEL OBJ\VI.EXE
