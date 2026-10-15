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
# Listings are off; to create them, set LST=OBJ\$*.LST
#
LST=NUL

OBJ\DEBUG.COM: DBGDEV.ASM ..\..\INC\BIOS.INC ..\..\INC\DEV.INC ..\..\INC\UART.INC ..\..\INC\VERSION.INC
	$(ASM) $(AFLAGS) DBGDEV.ASM,OBJ\DBGDEV.OBJ,$(LST);
	$(LINK) OBJ\DBGDEV.OBJ,OBJ\DBGDEV.EXE,OBJ\DBGDEV.MAP/MAP;
	$(EXE2BIN) OBJ\DBGDEV.EXE $@
	DEL OBJ\DBGDEV.OBJ
	DEL OBJ\DBGDEV.EXE
