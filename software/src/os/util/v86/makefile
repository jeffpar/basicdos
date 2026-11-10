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
# Use LST=NUL to turn listings off and LST=OBJ\$*.LST to turn them on.
#
LST=NUL

#
# Every module depends on OBJ\INCS, an empty file that's re-created whenever
# any include file changes, so that every module is rebuilt then, too (MAKE
# has no pseudo-targets, and MS-DOS's COPY would keep the old file's time).
#
OBJ\INCS: V86HOST.INC ..\..\INC\8086.INC ..\..\INC\BIOS.INC \
	..\..\INC\CPU.INC ..\..\INC\DEVAPI.INC ..\..\INC\DOSAPI.INC \
	..\..\INC\FPU.INC ..\..\INC\MACROS.INC ..\..\INC\PARSER.INC \
	..\..\INC\V86.INC ..\..\INC\VERSION.INC
	TYPE NUL > OBJ\INCS

#
# V86UTIL.OBJ must be linked last, since the heap (VARS) follows it.
#
OBJ\V86.COM: V86.ASM V86DOS.ASM V86PROC.ASM V86UTIL.ASM OBJ\INCS
	$(ASM) $(AFLAGS) V86.ASM,OBJ\V86.OBJ,$(LST);
	$(ASM) $(AFLAGS) V86DOS.ASM,OBJ\V86DOS.OBJ,$(LST);
	$(ASM) $(AFLAGS) V86PROC.ASM,OBJ\V86PROC.OBJ,$(LST);
	$(ASM) $(AFLAGS) V86UTIL.ASM,OBJ\V86UTIL.OBJ,$(LST);
	$(LINK) OBJ\V86.OBJ+OBJ\V86DOS.OBJ+OBJ\V86PROC.OBJ+OBJ\V86UTIL.OBJ,OBJ\V86.EXE;
	$(EXE2BIN) OBJ\V86.EXE $@
	DEL OBJ\V86.OBJ
	DEL OBJ\V86DOS.OBJ
	DEL OBJ\V86PROC.OBJ
	DEL OBJ\V86UTIL.OBJ
	DEL OBJ\V86.EXE
