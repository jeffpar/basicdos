#
# BASIC-DOS Serial Debugger (DEBUG.COM) Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright (c) 2026 Jeff Parsons
# @license MIT <https://basicdos.com/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
ASM=MASM
LINK=LINK
EXE2BIN=EXE2BIN
AFLAGS=/MX /R /D$(REL) /I..\..\INC
#
# Use LST=NUL to turn listings off and LST=OBJ\$*.LST to turn them on.
#
LST=NUL

#
# Every module depends on OBJ\INCS, an empty file that's re-created whenever
# any include file changes, so that every module is rebuilt then, too (MAKE
# has no pseudo-targets, and MS-DOS's COPY would keep the old file's time).
#
OBJ\INCS: ..\..\INC\8086.INC ..\..\INC\BIOS.INC ..\..\INC\CPU.INC \
	..\..\INC\DEV.INC ..\..\INC\DEVAPI.INC ..\..\INC\DISK.INC \
	..\..\INC\DOS.INC ..\..\INC\DOSAPI.INC ..\..\INC\FPU.INC \
	..\..\INC\MACROS.INC ..\..\INC\PARSER.INC ..\..\INC\UART.INC \
	..\..\INC\UTIL.INC ..\..\INC\VERSION.INC
	TYPE NUL > OBJ\INCS

OBJ\DBGDEV.OBJ: DBGDEV.ASM OBJ\INCS
	$(ASM) $(AFLAGS) DBGDEV.ASM,$@,$(LST);

OBJ\DBGDIS.OBJ: DBGDIS.ASM OBJ\INCS
	$(ASM) $(AFLAGS) DBGDIS.ASM,$@,$(LST);

OBJ\DBGINIT.OBJ: DBGINIT.ASM OBJ\INCS
	$(ASM) $(AFLAGS) DBGINIT.ASM,$@,$(LST);

#
# DBGINIT.OBJ must come last, since a driver keeps only the code of the
# modules before it (up to resident_end).
#
OBJ\DEBUG.COM: OBJ\DBGDEV.OBJ OBJ\DBGDIS.OBJ OBJ\DBGINIT.OBJ
	$(LINK) OBJ\DBGDEV.OBJ+OBJ\DBGDIS.OBJ+OBJ\DBGINIT.OBJ,OBJ\DBGDEV.EXE,OBJ\DBGDEV.MAP/MAP;
	$(EXE2BIN) OBJ\DBGDEV.EXE $@
	DEL OBJ\DBGDEV.EXE
