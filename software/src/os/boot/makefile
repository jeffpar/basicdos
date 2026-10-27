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
AFLAGS=/MX /R /D$(REL) /I..\INC
#
# Use LST=NUL to turn listings off and LST=OBJ\$*.LST to turn them on.
#
LST=NUL

#
# Every module depends on OBJ\INCS, an empty file that's re-created whenever
# any include file changes, so that every module is rebuilt then, too (MAKE
# has no pseudo-targets, and MS-DOS's COPY would keep the old file's time).
#
OBJ\INCS: ..\INC\8086.INC ..\INC\BIOS.INC ..\INC\CPU.INC ..\INC\DEV.INC \
	..\INC\DEVAPI.INC ..\INC\DISK.INC ..\INC\DOS.INC ..\INC\DOSAPI.INC \
	..\INC\FPU.INC ..\INC\MACROS.INC ..\INC\PARSER.INC ..\INC\UART.INC \
	..\INC\UTIL.INC ..\INC\VERSION.INC
	TYPE NUL > OBJ\INCS

#
# Inference rules in the DOS MAKE utility apparently work only if the files
# are in the same folder.  So for now, each dependency must copy these rules.
#
.ASM.COM:
	$(ASM) $(AFLAGS) $*.ASM,$*.OBJ,$(LST);
	$(LINK) $*.OBJ,$*.EXE,$*.MAP/MAP;
	$(EXE2BIN) $*.EXE $@
	DEL $*.OBJ
	DEL $*.EXE

OBJ\BOOT.COM: BOOT.ASM OBJ\INCS
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE

OBJ\BOOT1.COM: OBJ\BOOT.COM
	COPY OBJ\BOOT.COM $@

OBJ\WBOOT.COM: WBOOT.ASM OBJ\INCS
	$(ASM) $(AFLAGS) $*.ASM,OBJ\$*.OBJ,$(LST);
	$(LINK) OBJ\$*.OBJ,OBJ\$*.EXE,OBJ\$*.MAP/MAP;
	$(EXE2BIN) OBJ\$*.EXE $@
	DEL OBJ\$*.OBJ
	DEL OBJ\$*.EXE
