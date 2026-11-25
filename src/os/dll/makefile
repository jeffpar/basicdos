#
# BASIC-DOS Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright (c) 2026 Jeff Parsons
# @license MIT <https://basicdos.com/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
# MASM5 is MASM 5.10B; use ASM=MASM on MAKE's command line to assemble with
# MASM 4.00 instead.
#
ASM=MASM5
#
# LINK4 builds NE libraries (the DLL files that the NE loader looks for in
# the system drive's EXT\DLL directory, or the one that LIBPATH= names).
#
LINK4=LINK4
AFLAGS=/MX /R /D$(REL) /I..\INC
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
OBJ\INCS: ..\INC\DEVAPI.INC ..\INC\DOSAPI.INC ..\INC\MACROS.INC \
	..\INC\OS2.INC
	TYPE NUL > OBJ\INCS

#
# Each library has a module definitions file that names it (LIBRARY) and
# lists the functions it exports, with their ordinals.
#
OBJ\DOSCALLS.DLL: DOSCALLS.ASM DOSCALLS.DEF OBJ\INCS
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK4) OBJ\$*.OBJ,$@/ALIGN:16,NUL,,$*.DEF;
	DEL OBJ\$*.OBJ

OBJ\KBDCALLS.DLL: KBDCALLS.ASM KBDCALLS.DEF OBJ\INCS
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK4) OBJ\$*.OBJ,$@/ALIGN:16,NUL,,$*.DEF;
	DEL OBJ\$*.OBJ

OBJ\MSG.DLL: MSG.ASM MSG.DEF OBJ\INCS
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK4) OBJ\$*.OBJ,$@/ALIGN:16,NUL,,$*.DEF;
	DEL OBJ\$*.OBJ

OBJ\NLS.DLL: NLS.ASM NLS.DEF OBJ\INCS
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK4) OBJ\$*.OBJ,$@/ALIGN:16,NUL,,$*.DEF;
	DEL OBJ\$*.OBJ
