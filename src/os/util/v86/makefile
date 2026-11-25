#
# BASIC-DOS Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright (c) 2020-2026 Jeff Parsons
# @license MIT <https://basicdos.com/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
# MASM5 is MASM 5.10B; use ASM=MASM on MAKE's command line to assemble with
# MASM 4.00 instead.
#
ASM=MASM5
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
# The exception is VERSION.INC: only the modules that include it depend on
# it, so that a new version rebuilds only those.
#
OBJ\INCS: V86HOST.INC ..\..\INC\8086.INC ..\..\INC\BIOS.INC \
	..\..\INC\CPU.INC ..\..\INC\DEVAPI.INC ..\..\INC\DOSAPI.INC \
	..\..\INC\FPU.INC ..\..\INC\MACROS.INC ..\..\INC\PARSER.INC \
	..\..\INC\SND.INC ..\..\INC\V86.INC
	TYPE NUL > OBJ\INCS

#
# V86UTIL.OBJ must be linked last, since the heap (VARS) follows it.
#
OBJ\V86.COM: V86.ASM V86BIOS.ASM V86DOS.ASM V86HW.ASM V86PROC.ASM V86UTIL.ASM \
	OBJ\INCS
	$(ASM) $(AFLAGS) V86.ASM,OBJ\V86.OBJ,$(LST);
	$(ASM) $(AFLAGS) V86BIOS.ASM,OBJ\V86BIOS.OBJ,$(LST);
	$(ASM) $(AFLAGS) V86DOS.ASM,OBJ\V86DOS.OBJ,$(LST);
	$(ASM) $(AFLAGS) V86HW.ASM,OBJ\V86HW.OBJ,$(LST);
	$(ASM) $(AFLAGS) V86PROC.ASM,OBJ\V86PROC.OBJ,$(LST);
	$(ASM) $(AFLAGS) V86UTIL.ASM,OBJ\V86UTIL.OBJ,$(LST);
	$(LINK) OBJ\V86.OBJ+OBJ\V86BIOS.OBJ+OBJ\V86DOS.OBJ+OBJ\V86HW.OBJ+OBJ\V86PROC.OBJ+OBJ\V86UTIL.OBJ,OBJ\V86.EXE;
	$(EXE2BIN) OBJ\V86.EXE $@
	DEL OBJ\V86.OBJ
	DEL OBJ\V86BIOS.OBJ
	DEL OBJ\V86DOS.OBJ
	DEL OBJ\V86HW.OBJ
	DEL OBJ\V86PROC.OBJ
	DEL OBJ\V86UTIL.OBJ
	DEL OBJ\V86.EXE
