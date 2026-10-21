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
OBJ\FIND.COM: FIND.ASM UTILVARS.INC UTILPROC.INC ..\..\INC\UTIL.INC
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\MORE.COM: MORE.ASM UTILVARS.INC UTILPROC.INC
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\SLEEP.COM: SLEEP.ASM
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\SORT.COM: SORT.ASM UTILVARS.INC UTILPROC.INC
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\TEE.COM: TEE.ASM UTILVARS.INC UTILPROC.INC
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\TR.COM: TR.ASM
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\WC.COM: WC.ASM UTILVARS.INC UTILPROC.INC ..\..\INC\UTIL.INC
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE
